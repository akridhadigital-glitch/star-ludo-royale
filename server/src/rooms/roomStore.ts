import type { Redis } from 'ioredis';
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

export class MemoryRoomStore implements RoomStore {
  rooms = new Map<string, string>();
  users = new Map<string, string>();
  async save(room: Room) { this.rooms.set(room.code, JSON.stringify(room)); }
  async load(code: string) { const r = this.rooms.get(code); return r ? (JSON.parse(r) as Room) : null; }
  async delete(code: string) { this.rooms.delete(code); }
  async setUserRoom(userId: string, code: string | null) { if (code) this.users.set(userId, code); else this.users.delete(userId); }
  async getUserRoom(userId: string) { return this.users.get(userId) ?? null; }
}
