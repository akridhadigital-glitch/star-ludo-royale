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
}

const COLS = `id, name, avatar, coins, gems, games_played, wins, captures, firebase_uid IS NOT NULL AS has_google`;

function toUser(r: any): User {
  return {
    id: r.id, name: r.name, avatar: Number(r.avatar), coins: Number(r.coins), gems: Number(r.gems),
    gamesPlayed: Number(r.games_played), wins: Number(r.wins), captures: Number(r.captures), hasGoogle: !!r.has_google,
  };
}

/** Trim, drop control characters, collapse spaces, max 14 chars. Returns null if nothing usable is left. */
export function cleanName(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  const s = raw.replace(/[\u0000-\u001f\u007f-\u009f<>]/g, '').replace(/\s+/g, ' ').trim().slice(0, 14).trim();
  return s.length ? s : null;
}

export function defaultGuestName(): string {
  return `Player${Math.floor(1000 + Math.random() * 9000)}`;
}

export class UserRepo {
  constructor(private db: Db) {}

  async byId(id: string): Promise<User | null> {
    const { rows } = await this.db.query(`SELECT ${COLS} FROM users WHERE id = $1`, [id]);
    return rows[0] ? toUser(rows[0]) : null;
  }

  async upsertGuest(deviceId: string, name: string | null): Promise<User> {
    const { rows } = await this.db.query(
      `INSERT INTO users (device_id, name) VALUES ($1, $2)
       ON CONFLICT (device_id) DO UPDATE SET last_seen_at = now()
       RETURNING ${COLS}`,
      [deviceId, name ?? defaultGuestName()],
    );
    return toUser(rows[0]);
  }

  async byFirebaseUid(uid: string): Promise<User | null> {
    const { rows } = await this.db.query(`SELECT ${COLS} FROM users WHERE firebase_uid = $1`, [uid]);
    return rows[0] ? toUser(rows[0]) : null;
  }

  async linkFirebase(userId: string, uid: string): Promise<User> {
    const { rows } = await this.db.query(`UPDATE users SET firebase_uid = $2 WHERE id = $1 RETURNING ${COLS}`, [userId, uid]);
    return toUser(rows[0]);
  }

  async createFromFirebase(uid: string, name: string | null): Promise<User> {
    const { rows } = await this.db.query(`INSERT INTO users (firebase_uid, name) VALUES ($1, $2) RETURNING ${COLS}`, [uid, name ?? defaultGuestName()]);
    return toUser(rows[0]);
  }

  async updateProfile(id: string, patch: { name?: string; avatar?: number }): Promise<User | null> {
    const { rows } = await this.db.query(
      `UPDATE users SET name = COALESCE($2, name), avatar = COALESCE($3, avatar) WHERE id = $1 RETURNING ${COLS}`,
      [id, patch.name ?? null, patch.avatar ?? null],
    );
    return rows[0] ? toUser(rows[0]) : null;
  }

  async delete(id: string): Promise<void> {
    await this.db.query('DELETE FROM users WHERE id = $1', [id]);
  }

  async leaderboard(limit = 50): Promise<{ rank: number; name: string; avatar: number; wins: number; gamesPlayed: number }[]> {
    const { rows } = await this.db.query(
      `SELECT name, avatar, wins, games_played FROM users WHERE games_played > 0 ORDER BY wins DESC, games_played ASC, created_at ASC LIMIT $1`,
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
