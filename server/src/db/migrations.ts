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
  {
    id: '002_unique_names',
    sql: `
      ALTER TABLE users ADD COLUMN name_set BOOLEAN NOT NULL DEFAULT false;
      -- Existing duplicate names (case-insensitive): keep the oldest, give the rest a short suffix.
      WITH d AS (
        SELECT id, row_number() OVER (PARTITION BY lower(name) ORDER BY created_at, id) AS rn FROM users
      )
      UPDATE users u SET name = left(u.name, 8) || '_' || substr(md5(u.id::text), 1, 5)
      FROM d WHERE d.id = u.id AND d.rn > 1;
      CREATE UNIQUE INDEX users_name_lower_uniq ON users (lower(name));
    `,
  },
];
