import type { Db } from './db/db.js';

export interface User {
  id: string;
  name: string;
  avatar: number;
  coins: number;
  gems: number;
  gamesPlayed: number;
  wins: number;
  captures: number;
  hasGoogle: boolean;
  /** True once the player picked their own (unique) name. Required for online play. */
  nameSet: boolean;
}

const COLS = `id, name, name_set, avatar, coins, gems, games_played, wins, captures, firebase_uid IS NOT NULL AS has_google`;

function toUser(r: any): User {
  return {
    id: r.id, name: r.name, avatar: Number(r.avatar), coins: Number(r.coins), gems: Number(r.gems),
    gamesPlayed: Number(r.games_played), wins: Number(r.wins), captures: Number(r.captures), hasGoogle: !!r.has_google, nameSet: !!r.name_set,
  };
}

/** Trim, drop control characters, collapse spaces, max 14 chars. Returns null if nothing usable is left. */
export function cleanName(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  const s = raw.replace(/[\u0000-\u001f\u007f-\u009f<>]/g, '').replace(/\s+/g, ' ').trim().slice(0, 14).trim();
  return s.length ? s : null;
}

export function defaultGuestName(): string {
  return `Player${Math.floor(10000 + Math.random() * 90000)}`;
}

export class NameError extends Error {
  constructor(public code: 'name_invalid' | 'name_reserved' | 'name_taken') { super(code); }
}

const RESERVED = /^(player\d*|computer|bot\s*\d*|admin|administrator|moderator|support|system|star ?ludo.*|null|undefined)$/i;

/** Rules for a chosen name: 3–14 letters/numbers in any script (incl. Hindi vowel signs), space, _ . - ; not reserved. */
export function validateName(raw: unknown): string {
  const name = cleanName(raw);
  if (!name || name.length < 3 || !/^[\p{L}\p{N}][\p{L}\p{M}\p{N} _.\-]*$/u.test(name)) throw new NameError('name_invalid');
  if (RESERVED.test(name)) throw new NameError('name_reserved');
  return name;
}

const isUniqueViolation = (e: any) => e?.code === '23505' && String(e?.constraint ?? '').includes('name');

export class UserRepo {
  constructor(private db: Db) {}

  async byId(id: string): Promise<User | null> {
    const { rows } = await this.db.query(`SELECT ${COLS} FROM users WHERE id = $1`, [id]);
    return rows[0] ? toUser(rows[0]) : null;
  }

  /** Inserts with a generated placeholder name, retrying on the (rare) clash. */
  private async insertWithGeneratedName(sql: string, params: unknown[]): Promise<User> {
    for (let i = 0; ; i++) {
      try {
        const { rows } = await this.db.query(sql, [...params, defaultGuestName()]);
        return toUser(rows[0]);
      } catch (e) {
        if (!isUniqueViolation(e) || i >= 8) throw e;
      }
    }
  }

  /** Guests start with a placeholder name; they choose a unique one before playing online. */
  async upsertGuest(deviceId: string): Promise<User> {
    return this.insertWithGeneratedName(
      `INSERT INTO users (device_id, name) VALUES ($1, $2)
       ON CONFLICT (device_id) DO UPDATE SET last_seen_at = now()
       RETURNING ${COLS}`,
      [deviceId],
    );
  }

  async isNameAvailable(name: string, exceptUserId?: string): Promise<boolean> {
    const { rows } = await this.db.query(
      `SELECT 1 FROM users WHERE lower(name) = lower($1) AND ($2::uuid IS NULL OR id <> $2::uuid) LIMIT 1`,
      [name, exceptUserId ?? null],
    );
    return rows.length === 0;
  }

  async byFirebaseUid(uid: string): Promise<User | null> {
    const { rows } = await this.db.query(`SELECT ${COLS} FROM users WHERE firebase_uid = $1`, [uid]);
    return rows[0] ? toUser(rows[0]) : null;
  }

  async linkFirebase(userId: string, uid: string): Promise<User> {
    const { rows } = await this.db.query(`UPDATE users SET firebase_uid = $2 WHERE id = $1 RETURNING ${COLS}`, [userId, uid]);
    return toUser(rows[0]);
  }

  async createFromFirebase(uid: string): Promise<User> {
    return this.insertWithGeneratedName(`INSERT INTO users (firebase_uid, name) VALUES ($1, $2) RETURNING ${COLS}`, [uid]);
  }

  /** `name` must already be validated. Throws NameError('name_taken') if someone else has it. */
  async updateProfile(id: string, patch: { name?: string; avatar?: number }): Promise<User | null> {
    try {
      const { rows } = await this.db.query(
        `UPDATE users SET name = COALESCE($2, name), name_set = name_set OR $2 IS NOT NULL,
           avatar = COALESCE($3, avatar) WHERE id = $1 RETURNING ${COLS}`,
        [id, patch.name ?? null, patch.avatar ?? null],
      );
      return rows[0] ? toUser(rows[0]) : null;
    } catch (e) {
      if (isUniqueViolation(e)) throw new NameError('name_taken');
      throw e;
    }
  }

  async delete(id: string): Promise<void> {
    await this.db.query('DELETE FROM users WHERE id = $1', [id]);
  }

  async leaderboard(limit = 50): Promise<{ rank: number; name: string; avatar: number; wins: number; gamesPlayed: number }[]> {
    const { rows } = await this.db.query(
      `SELECT name, avatar, wins, games_played FROM users WHERE games_played > 0 AND (device_id IS NULL OR device_id NOT LIKE 'smoke%') ORDER BY wins DESC, games_played ASC, created_at ASC LIMIT $1`,
      [limit],
    );
    return rows.map((r, i) => ({ rank: i + 1, name: r.name, avatar: Number(r.avatar), wins: Number(r.wins), gamesPlayed: Number(r.games_played) }));
  }

  /** Records a finished online match and pays rewards, atomically. */
  async recordMatch(m: {
    roomCode: string; startedAt: number; moves: number; winnerId: string | null;
    players: { userId: string; color: string; captures: number; coins: number; gems: number; won: boolean }[];
  }): Promise<void> {
    const client = await this.db.connect();
    try {
      await client.query('BEGIN');
      for (const p of m.players) {
        await client.query(
          `UPDATE users SET coins = coins + $2, gems = gems + $3, games_played = games_played + 1,
             wins = wins + $4, captures = captures + $5 WHERE id = $1`,
          [p.userId, p.coins, p.gems, p.won ? 1 : 0, p.captures],
        );
      }
      await client.query(
        `INSERT INTO matches (room_code, players, winner_id, moves, started_at) VALUES ($1, $2, $3, $4, to_timestamp($5 / 1000.0))`,
        [m.roomCode, JSON.stringify(m.players), m.winnerId, m.moves, m.startedAt],
      );
      await client.query('COMMIT');
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
  }
}
