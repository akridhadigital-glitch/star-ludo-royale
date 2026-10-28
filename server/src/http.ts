import Fastify, { type FastifyInstance, type FastifyRequest } from 'fastify';
import cors from '@fastify/cors';
import rateLimit from '@fastify/rate-limit';
import { z } from 'zod';
import type { Tokens, GoogleVerifier } from './auth.js';
import { cleanName, type UserRepo } from './users.js';
import type { RoomManager } from './rooms/roomManager.js';
import { roomView } from './views.js';

export interface HttpDeps {
  users: UserRepo;
  tokens: Tokens;
  google: GoogleVerifier | null;
  rooms: RoomManager;
  corsOrigin: string;
  logger?: boolean;
}

class HttpError extends Error {
  constructor(public status: number, public code: string) { super(code); }
}

export async function buildHttp(deps: HttpDeps): Promise<FastifyInstance> {
  const app = Fastify({ logger: deps.logger ?? false, trustProxy: true, bodyLimit: 16 * 1024 });
  await app.register(cors, {
    origin: deps.corsOrigin === '*' ? true : deps.corsOrigin.split(','),
    // Default is GET,HEAD,POST only, which silently blocked profile edits (PATCH) and account deletion (DELETE) on the web.
    methods: ['GET', 'HEAD', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
  });
  await app.register(rateLimit, { max: 120, timeWindow: '1 minute' });

  app.setErrorHandler((err: any, _req, reply) => {
    if (err instanceof HttpError) return reply.status(err.status).send({ error: err.code });
    if (err instanceof z.ZodError) return reply.status(400).send({ error: 'bad_request', issues: err.issues.map(i => i.path.join('.')) });
    if (err.statusCode === 429) return reply.status(429).send({ error: 'rate_limited' });
    if (err.statusCode && err.statusCode < 500) return reply.status(err.statusCode).send({ error: 'bad_request' });
    app.log.error(err);
    return reply.status(500).send({ error: 'server_error' });
  });

  const authUser = async (req: FastifyRequest) => {
    const h = req.headers.authorization;
    const id = h?.startsWith('Bearer ') ? deps.tokens.verify(h.slice(7)) : null;
    if (!id) throw new HttpError(401, 'unauthorized');
    const user = await deps.users.byId(id);
    if (!user) throw new HttpError(401, 'unauthorized');
    return user;
  };

  app.get('/health', async () => ({ ok: true }));

  const authLimit = { config: { rateLimit: { max: 20, timeWindow: '1 minute' } } };

  app.post('/v1/auth/guest', authLimit, async req => {
    const body = z.object({ deviceId: z.string().min(16).max(128).regex(/^[A-Za-z0-9_-]+$/), name: z.string().optional() }).parse(req.body);
    const user = await deps.users.upsertGuest(body.deviceId, cleanName(body.name));
    return { token: deps.tokens.sign(user.id), user };
  });

  /**
   * Google sign-in. The app signs in with Firebase Auth (Google provider) and sends the Firebase ID token.
   * - If that Google account already has a player → log into it.
   * - Else, if the request carries the current guest token → link Google to the guest (progress kept).
   * - Else → create a new player.
   */
  app.post('/v1/auth/google', authLimit, async req => {
    if (!deps.google) throw new HttpError(501, 'google_not_configured');
    const body = z.object({ idToken: z.string().min(20).max(8192) }).parse(req.body);
    let g;
    try { g = await deps.google.verify(body.idToken); } catch { throw new HttpError(401, 'invalid_google_token'); }

    const existing = await deps.users.byFirebaseUid(g.uid);
    if (existing) return { token: deps.tokens.sign(existing.id), user: existing, linked: false };

    const h = req.headers.authorization;
    const guestId = h?.startsWith('Bearer ') ? deps.tokens.verify(h.slice(7)) : null;
    const guest = guestId ? await deps.users.byId(guestId) : null;
    if (guest && !guest.hasGoogle) {
      const user = await deps.users.linkFirebase(guest.id, g.uid);
      return { token: deps.tokens.sign(user.id), user, linked: true };
    }
    const user = await deps.users.createFromFirebase(g.uid, cleanName(g.name));
    return { token: deps.tokens.sign(user.id), user, linked: false };
  });

  app.get('/v1/me', async req => {
    const user = await authUser(req);
    const room = await deps.rooms.activeRoomOf(user.id);
    return { user, activeRoom: room ? roomView(room) : null };
  });

  app.patch('/v1/me', async req => {
    const user = await authUser(req);
    const body = z.object({ name: z.string().optional(), avatar: z.number().int().min(0).max(11).optional() }).parse(req.body);
    const name = body.name === undefined ? undefined : cleanName(body.name);
    if (body.name !== undefined && !name) throw new HttpError(400, 'bad_name');
    const updated = await deps.users.updateProfile(user.id, { name: name ?? undefined, avatar: body.avatar });
    return { user: updated };
  });

  /** Right to erasure (DPDP Act 2023): deletes the account and all stats. */
  app.delete('/v1/me', async (req, reply) => {
    const user = await authUser(req);
    const room = await deps.rooms.activeRoomOf(user.id);
    if (room) await deps.rooms.leave(user.id, room.code);
    await deps.users.delete(user.id);
    return reply.status(204).send();
  });

  app.get('/v1/leaderboard', async () => ({ players: await deps.users.leaderboard(50) }));

  return app;
}
