import type { Redis } from 'ioredis';
import type { Db } from '../db/db.js';
import type { Room } from './roomManager.js';

/** Where room snapshots live, so a reconnecting player (or a restarted server) can resume. */
export interface RoomStore {
  save(room: Room): Promise<void>;
  load(code: string): Promise<Room | null>;
  delete(code: string): Promise<void>;
  setUserRoom(userId: string, code: string | null): Promise<void>;
  getUserRoom(userId: string): Promise<string | null>;
}

const ROOM_TTL_S = 6 * 60 * 60;

export class RedisRoomStore implements RoomStore {
  constructor(private redis: Redis, private prefix = 'slr:') {}

  async save(room: Room): Promise<void> {
    await this.redis.set(`${this.prefix}room:${room.code}`, JSON.stringify(room), 'EX', ROOM_TTL_S);
  }
  async load(code: string): Promise<Room | null> {
    const raw = await this.redis.get(`${this.prefix}room:${code}`);
    return raw ? (JSON.parse(raw) as Room) : null;
  }
  async delete(code: string): Promise<void> {
    await this.redis.del(`${this.prefix}room:${code}`);
  }
  async setUserRoom(userId: string, code: string | null): Promise<void> {
    if (code) await this.redis.set(`${this.prefix}user:${userId}:room`, code, 'EX', ROOM_TTL_S);
    else await this.redis.del(`${this.prefix}user:${userId}:room`);
  }
  async getUserRoom(userId: string): Promise<string | null> {
    return this.redis.get(`${this.prefix}user:${userId}:room`);
  }
}

/**
 * Postgres-backed store: used when there is no Redis (e.g. free Render + Neon), so a server
 * restart or redeploy doesn't wipe live matches — players reconnect and carry on.
 */
export class PgRoomStore implements RoomStore {
  constructor(private db: Db) {}

  /** Drop snapshots older than the room TTL (called at startup). */
  async prune(): Promise<void> {
    await this.db.query(`DELETE FROM live_rooms WHERE updated_at < now() - make_interval(secs => $1)`, [ROOM_TTL_S]);
    await this.db.query(`DELETE FROM live_user_rooms WHERE updated_at < now() - make_interval(secs => $1)`, [ROOM_TTL_S]);
  }
  async save(room: Room): Promise<void> {
    await this.db.query(
      `INSERT INTO live_rooms (code, data, updated_at) VALUES ($1, $2, now())
       ON CONFLICT (code) DO UPDATE SET data = EXCLUDED.data, updated_at = now()`,
      [room.code, JSON.stringify(room)],
    );
  }
  async load(code: string): Promise<Room | null> {
    const { rows } = await this.db.query(
      `SELECT data FROM live_rooms WHERE code = $1 AND updated_at > now() - make_interval(secs => $2)`,
      [code, ROOM_TTL_S],
    );
    return rows[0] ? (rows[0].data as Room) : null;
  }
  async delete(code: string): Promise<void> {
    await this.db.query('DELETE FROM live_rooms WHERE code = $1', [code]);
  }
  async setUserRoom(userId: string, code: string | null): Promise<void> {
    if (code) {
      await this.db.query(
        `INSERT INTO live_user_rooms (user_id, code, updated_at) VALUES ($1, $2, now())
         ON CONFLICT (user_id) DO UPDATE SET code = EXCLUDED.code, updated_at = now()`,
        [userId, code],
      );
    } else {
      await this.db.query('DELETE FROM live_user_rooms WHERE user_id = $1', [userId]);
    }
  }
  async getUserRoom(userId: string): Promise<string | null> {
    const { rows } = await this.db.query(
      `SELECT code FROM live_user_rooms WHERE user_id = $1 AND updated_at > now() - make_interval(secs => $2)`,
      [userId, ROOM_TTL_S],
    );
    return rows[0]?.code ?? null;
  }
}

export class MemoryRoomStore implements RoomStore {
  rooms = new Map<string, string>();
  users = new Map<string, string>();
  async save(room: Room) { this.rooms.set(room.code, JSON.stringify(room)); }
  async load(code: string) { const r = this.rooms.get(code); return r ? (JSON.parse(r) as Room) : null; }
  async delete(code: string) { this.rooms.delete(code); }
  async setUserRoom(userId: string, code: string | null) { if (code) this.users.set(userId, code); else this.users.delete(userId); }
  async getUserRoom(userId: string) { return this.users.get(userId) ?? null; }
}
