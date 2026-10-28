import pg from 'pg';
import { migrations } from './migrations.js';

export type Db = pg.Pool;

export function createDb(url: string): Db {
  // Hosted Postgres (Neon, Supabase, Render…) needs TLS; local/docker Postgres doesn't.
  const local = /@(localhost|127\.0\.0\.1|postgres)(:|\/)/.test(url);
  const pool = new pg.Pool({
    connectionString: url,
    max: 10,
    idleTimeoutMillis: 30_000,
    ssl: local || /sslmode=disable/.test(url) ? undefined : { rejectUnauthorized: false },
  });
  // Hosted databases drop idle connections (Neon suspends after 5 min). Without this handler
  // an idle client's error is unhandled and crashes the whole process; the pool reconnects on next use.
  pool.on('error', err => { console.error('postgres idle client error (recovering):', err.message); });
  return pool;
}

export async function migrate(db: Db): Promise<void> {
  const client = await db.connect();
  try {
    await client.query('SELECT pg_advisory_lock(727101)'); // one migrator at a time
    await client.query(`CREATE TABLE IF NOT EXISTS schema_migrations (id TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())`);
    const { rows } = await client.query<{ id: string }>('SELECT id FROM schema_migrations');
    const done = new Set(rows.map(r => r.id));
    for (const m of migrations) {
      if (done.has(m.id)) continue;
      await client.query('BEGIN');
      try {
        await client.query(m.sql);
        await client.query('INSERT INTO schema_migrations (id) VALUES ($1)', [m.id]);
        await client.query('COMMIT');
      } catch (e) {
        await client.query('ROLLBACK');
        throw e;
      }
    }
  } finally {
    await client.query('SELECT pg_advisory_unlock(727101)').catch(() => {});
    client.release();
  }
}
