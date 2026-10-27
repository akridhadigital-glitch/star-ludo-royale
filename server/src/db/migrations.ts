/** Ordered, append-only migrations. Never edit a migration that has shipped; add a new one. */
export const migrations: { id: string; sql: string }[] = [
  {
    id: '001_init',
    sql: `
      CREATE TABLE users (
        id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        device_id     TEXT UNIQUE,
        firebase_uid  TEXT UNIQUE,
        name          TEXT NOT NULL,
        avatar        SMALLINT NOT NULL DEFAULT 0,
        coins         BIGINT NOT NULL DEFAULT 25000,
        gems          INTEGER NOT NULL DEFAULT 25,
        games_played  INTEGER NOT NULL DEFAULT 0,
        wins          INTEGER NOT NULL DEFAULT 0,
        captures      INTEGER NOT NULL DEFAULT 0,
        created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
        last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now()
      );
      CREATE INDEX users_leaderboard_idx ON users (wins DESC, games_played ASC);

      CREATE TABLE matches (
        id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        room_code   TEXT NOT NULL,
        players     JSONB NOT NULL,
        winner_id   UUID REFERENCES users(id) ON DELETE SET NULL,
        moves       INTEGER NOT NULL,
        started_at  TIMESTAMPTZ NOT NULL,
        ended_at    TIMESTAMPTZ NOT NULL DEFAULT now()
      );
    `,
  },
];
