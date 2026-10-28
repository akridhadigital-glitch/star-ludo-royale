import { Server, type Socket } from 'socket.io';
import type { Server as HttpServer } from 'node:http';
import { z } from 'zod';
import type { Tokens } from './auth.js';
import type { UserRepo } from './users.js';
import { RoomError, type RoomEmitter, type RoomManager } from './rooms/roomManager.js';
import { roomView } from './views.js';

type Ack = (res: Record<string, unknown>) => void;

/**
 * Socket protocol (see docs/PROTOCOL.md).
 * Client → server events all take (payload, ack) and get { ok: true, ... } or { ok: false, error }.
 */
export function createIo(httpServer: HttpServer, corsOrigin: string): Server {
  return new Server(httpServer, {
    cors: { origin: corsOrigin === '*' ? true : corsOrigin.split(',') },
    pingInterval: 10000,
    pingTimeout: 8000,
    // No connectionStateRecovery: it appends an offset argument to every broadcast, which the
    // Dart socket client delivers as part of the payload. The app re-attaches via `room:resume`.
  });
}

export function ioEmitter(io: Server): RoomEmitter {
  return {
    roomUpdate: room => { io.to(`room:${room.code}`).emit('room:update', roomView(room)); },
    gameEvents: (code, payload) => { io.to(`room:${code}`).emit('game:events', payload); },
    chat: (code, payload) => { io.to(`room:${code}`).emit('chat:message', payload); },
  };
}

export function attachSocketHandlers(io: Server, deps: { tokens: Tokens; users: UserRepo; rooms: RoomManager; log?: (m: string, e?: unknown) => void }) {
  const { rooms } = deps;
  /** userId → sockets currently attached to a room */
  const presence = new Map<string, Set<string>>();

  io.use(async (socket, next) => {
    const token = socket.handshake.auth?.token;
    const userId = typeof token === 'string' ? deps.tokens.verify(token) : null;
    const user = userId ? await deps.users.byId(userId).catch(() => null) : null;
    if (!user) return next(new Error('unauthorized'));
    socket.data.user = { userId: user.id, name: user.name, avatar: user.avatar };
    next();
  });

  io.on('connection', (socket: Socket) => {
    const me = socket.data.user as { userId: string; name: string; avatar: number };

    const bind = async (code: string) => {
      const prev = socket.data.roomCode as string | undefined;
      if (prev && prev !== code) await unbind();
      socket.data.roomCode = code;
      await socket.join(`room:${code}`);
      const set = presence.get(me.userId) ?? new Set<string>();
      set.add(socket.id);
      presence.set(me.userId, set);
      await rooms.setConnected(me.userId, code, true);
    };
    const unbind = async (markOffline = true) => {
      const code = socket.data.roomCode as string | undefined;
      if (!code) return;
      socket.data.roomCode = undefined;
      await socket.leave(`room:${code}`);
      const set = presence.get(me.userId);
      set?.delete(socket.id);
      if (!set || set.size === 0) {
        presence.delete(me.userId);
        if (markOffline) await rooms.setConnected(me.userId, code, false);
      }
    };

    const on = <T>(event: string, schema: z.ZodType<T>, fn: (p: T) => Promise<Record<string, unknown> | void>) => {
      socket.on(event, async (payload: unknown, ack?: Ack) => {
        const reply = typeof ack === 'function' ? ack : () => {};
        try {
          const p = schema.parse(payload ?? {});
          const res = await fn(p);
          reply({ ok: true, ...(res ?? {}) });
        } catch (e) {
          if (e instanceof RoomError) reply({ ok: false, error: e.code });
          else if (e instanceof z.ZodError) reply({ ok: false, error: 'bad_request' });
          else { deps.log?.(`socket ${event} failed`, e); reply({ ok: false, error: 'server_error' }); }
        }
      });
    };

    const code = z.object({ code: z.string().trim().toUpperCase().regex(/^[A-Z0-9]{6}$/) });
    const roomCode = () => {
      const c = socket.data.roomCode as string | undefined;
      if (!c) throw new RoomError('not_in_room');
      return c;
    };

    on('room:create', z.object({ maxPlayers: z.number().int() }), async p => {
      const room = await rooms.create(me, p.maxPlayers);
      await bind(room.code);
      return { room: roomView(room) };
    });

    on('room:join', code, async p => {
      const room = await rooms.join(me, p.code);
      await bind(room.code);
      return { room: roomView(room) };
    });

    on('room:resume', z.object({}), async () => {
      const room = await rooms.activeRoomOf(me.userId);
      if (!room) return { room: null };
      await bind(room.code);
      return { room: roomView(room) };
    });

    on('room:leave', z.object({}), async () => {
      const c = socket.data.roomCode as string | undefined;
      const active = c ?? (await rooms.activeRoomOf(me.userId))?.code;
      await unbind(false);
      if (active) await rooms.leave(me.userId, active);
    });

    on('room:start', z.object({}), async () => { await rooms.start(me.userId, roomCode()); });
    on('game:roll', z.object({}), async () => { await rooms.roll(me.userId, roomCode()); });
    on('game:move', z.object({ token: z.number().int().min(0).max(3) }), async p => { await rooms.move(me.userId, roomCode(), p.token); });
    on('chat:send', z.object({ id: z.string().max(16) }), async p => { await rooms.chat(me.userId, roomCode(), p.id); });

    socket.on('disconnect', () => { unbind(true).catch(e => deps.log?.('unbind failed', e)); });
  });
}
