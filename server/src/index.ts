import { Redis } from 'ioredis';
import { loadConfig, type Config } from './config.js';
import { createDb, migrate } from './db/db.js';
import { Tokens, createFirebaseVerifier, type GoogleVerifier } from './auth.js';
import { UserRepo } from './users.js';
import { MemoryRoomStore, RedisRoomStore } from './rooms/roomStore.js';
import { RoomManager, type Room, type RoomEmitter } from './rooms/roomManager.js';
import { buildHttp } from './http.js';
import { attachSocketHandlers, createIo, ioEmitter } from './socket.js';
import type { Server } from 'socket.io';

export function recordMatchWith(users: UserRepo) {
  return async (room: Room) => {
    if (!room.result || !room.game || !room.startedAt) return;
    const winner = room.game.winner;
    await users.recordMatch({
      roomCode: room.code,
      startedAt: room.startedAt,
      moves: room.game.moveNo,
      winnerId: room.members.find(m => m.color === winner)?.userId ?? null,
      players: room.members.filter(m => m.color).map(m => ({
        userId: m.userId,
        color: m.color!,
        captures: room.game!.captures[m.color!] ?? 0,
        coins: room.result!.rewards[m.userId]?.coins ?? 0,
        gems: room.result!.rewards[m.userId]?.gems ?? 0,
        won: m.color === winner,
      })),
    });
  };
}

export interface ServerOverrides {
  google?: GoogleVerifier | null;
  rollDice?: () => number;
  awayMs?: number;
  turnMs?: number;
}

/** Boots the whole server. Used by main() and by the integration tests. */
export async function startServer(config: Config, o: ServerOverrides = {}) {
  const db = createDb(config.DATABASE_URL);
  await migrate(db);
  const redis = config.REDIS_URL ? new Redis(config.REDIS_URL, { maxRetriesPerRequest: 3 }) : null;
  const users = new UserRepo(db);
  const tokens = new Tokens(config.JWT_SECRET);
  const google = o.google !== undefined ? o.google
    : config.FIREBASE_PROJECT_ID ? await createFirebaseVerifier(config.FIREBASE_PROJECT_ID) : null;

  // The room manager emits through socket.io, which needs the HTTP server, which needs the room manager.
  // Break the cycle with a late-bound emitter.
  let io: Server | null = null;
  const emitter: RoomEmitter = {
    roomUpdate: r => { if (io) ioEmitter(io).roomUpdate(r); },
    gameEvents: (c, p) => { if (io) ioEmitter(io).gameEvents(c, p); },
    chat: (c, p) => { if (io) ioEmitter(io).chat(c, p); },
  };
  let log: (m: string, e?: unknown) => void = (m, e) => console.error(m, e);
  const rooms = new RoomManager({
    store: redis ? new RedisRoomStore(redis) : new MemoryRoomStore(), emitter, recordMatch: recordMatchWith(users),
    turnMs: o.turnMs ?? config.TURN_SECONDS * 1000, awayMs: o.awayMs, rollDice: o.rollDice, log: (m, e) => log(m, e),
  });

  const http = await buildHttp({ users, tokens, google, rooms, corsOrigin: config.CORS_ORIGIN, logger: config.NODE_ENV !== 'test' });
  log = (m, e) => http.log.error({ err: e }, m);
  io = createIo(http.server, config.CORS_ORIGIN);
  attachSocketHandlers(io, { tokens, users, rooms, log });
  await http.listen({ port: config.PORT, host: config.HOST });

  const close = async () => {
    rooms.shutdown();
    io?.close();
    await http.close();
    await redis?.quit();
    await db.end();
  };
  return { http, io, rooms, users, db, redis, close, google };
}

async function main() {
  const config = loadConfig();
  const s = await startServer(config);
  s.http.log.info(`Star Ludo Royale server on :${config.PORT} (Google sign-in ${s.google ? 'on' : 'off'})`);
  const shutdown = async () => { await s.close(); process.exit(0); };
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}

if (process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href) {
  main().catch(err => { console.error(err); process.exit(1); });
}
