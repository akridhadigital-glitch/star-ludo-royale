import { z } from 'zod';

const schema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  PORT: z.coerce.number().int().default(8080),
  HOST: z.string().default('0.0.0.0'),
  DATABASE_URL: z.string().url(),
  /** Optional. Without it, live rooms are kept in server memory (fine for a single server). */
  REDIS_URL: z.string().optional(),
  JWT_SECRET: z.string().min(32, 'JWT_SECRET must be at least 32 characters'),
  CORS_ORIGIN: z.string().default('*'),
  /** Firebase project id. Only needed for Google sign-in; guest login works without it. */
  FIREBASE_PROJECT_ID: z.string().optional(),
  TURN_SECONDS: z.coerce.number().int().min(5).max(60).default(15),
  /**
   * DEMO ONLY. Comma-separated player names whose dice are weighted in their favour.
   * Rooms with such a player show a visible "DEMO MODE" banner to everyone. Leave empty in production.
   */
  DEMO_LUCKY_NAMES: z.string().optional(),
});

export type Config = z.infer<typeof schema>;

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const parsed = schema.safeParse(env);
  if (!parsed.success) {
    const msg = parsed.error.issues.map(i => `${i.path.join('.')}: ${i.message}`).join('\n');
    throw new Error(`Invalid configuration:\n${msg}`);
  }
  return parsed.data;
}
