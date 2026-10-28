/**
 * End-to-end tests against real Postgres + Redis over real sockets.
 * Requires TEST_DATABASE_URL and TEST_REDIS_URL (CI provides them as services).
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { io as ioc, type Socket } from 'socket.io-client';
import { randomBytes } from 'node:crypto';
import { startServer } from '../src/index.js';
import { loadConfig } from '../src/config.js';
import { currentColor, movableTokens, type GameState } from '../src/engine/engine.js';

const DB = process.env.TEST_DATABASE_URL;
const REDIS = process.env.TEST_REDIS_URL;
const run = DB && REDIS ? describe : describe.skip;

type Srv = Awaited<ReturnType<typeof startServer>>;
let srv: Srv;
let base = '';

const fakeGoogle = {
  async verify(idToken: string) {
    if (!idToken.startsWith('google-ok-')) throw new Error('bad');
    return { uid: idToken.slice('google-ok-'.length), name: 'Google Person' };
  },
};

async function boot(overrides: Parameters<typeof startServer>[1] = {}) {
  const config = loadConfig({ DATABASE_URL: DB!, REDIS_URL: REDIS!, JWT_SECRET: 'x'.repeat(40), PORT: '0', NODE_ENV: 'test' } as any);
  const s = await startServer(config, { google: fakeGoogle, turnMs: 600, awayMs: 30, authRateLimit: 1000, ...overrides });
  const addr = s.http.server.address() as { port: number };
  return { s, url: `http://127.0.0.1:${addr.port}` };
}

async function api(path: string, opts: { method?: string; token?: string; body?: unknown } = {}) {
  const res = await fetch(base + path, {
    method: opts.method ?? (opts.body ? 'POST' : 'GET'),
    headers: { ...(opts.body ? { 'content-type': 'application/json' } : {}), ...(opts.token ? { authorization: `Bearer ${opts.token}` } : {}) },
    body: opts.body ? JSON.stringify(opts.body) : undefined,
  });
  const text = await res.text();
  return { status: res.status, json: text ? JSON.parse(text) : null };
}

/** A guest who has chosen a unique name (required for online play). */
async function guest(name: string) {
  const r = await api('/v1/auth/guest', { body: { deviceId: randomBytes(16).toString('hex') } });
  expect(r.status).toBe(200);
  const unique = `${name}${randomBytes(2).toString('hex')}`;
  const p = await api('/v1/me', { method: 'PATCH', token: r.json.token, body: { name: unique } });
  expect(p.status).toBe(200);
  return { token: r.json.token as string, user: p.json.user as { id: string; name: string } };
}

interface Client {
  sock: Socket;
  userId: string;
  room: any;
  game: GameState | null;
  events: any[];
  emit: (ev: string, p?: unknown) => Promise<any>;
}

async function connect(token: string, userId: string): Promise<Client> {
  const sock = ioc(base, { auth: { token }, transports: ['websocket'], forceNew: true, reconnection: false });
  const c: Client = {
    sock, userId, room: null, game: null, events: [],
    emit: (ev, p = {}) => new Promise(res => sock.emit(ev, p, res)),
  };
  sock.on('room:update', r => { c.room = r; c.game = r.game; });
  sock.on('game:events', e => { c.events.push({ ...e, at: Date.now() }); c.game = e.game; });
  await new Promise<void>((res, rej) => { sock.on('connect', () => res()); sock.on('connect_error', rej); });
  return c;
}

const waitFor = async (cond: () => boolean, ms = 15000) => {
  const start = Date.now();
  while (!cond()) {
    if (Date.now() - start > ms) throw new Error('timeout waiting for condition');
    await new Promise(r => setTimeout(r, 10));
  }
};

/** Plays a client's turns (roll, then the first legal token) until the game ends. */
function autoplay(c: Client) {
  let busy = false;
  const tick = async () => {
    if (busy || !c.game || c.game.phase === 'over' || !c.room) return;
    const me = c.room.members.find((m: any) => m.userId === c.userId);
    if (!me || currentColor(c.game) !== me.color) return;
    busy = true;
    try {
      if (c.game.phase === 'roll') await c.emit('game:roll');
      else if (c.game.phase === 'move') await c.emit('game:move', { token: movableTokens(c.game, me.color, c.game.dice!)[0] });
    } finally { busy = false; }
  };
  const iv = setInterval(() => { void tick(); }, 5);
  return () => clearInterval(iv);
}

run('online play (Postgres + Redis)', () => {
  beforeAll(async () => {
    const b = await boot();
    srv = b.s; base = b.url;
    await srv.db.query('TRUNCATE users, matches CASCADE');
  });
  afterAll(async () => { await srv?.close(); });
  beforeEach(async () => { await srv.redis.flushdb(); });

  it('guest login is idempotent per device and profile can be edited', async () => {
    const deviceId = randomBytes(16).toString('hex');
    const a = await api('/v1/auth/guest', { body: { deviceId, name: 'ignored' } });
    const b = await api('/v1/auth/guest', { body: { deviceId } });
    expect(a.json.user.id).toBe(b.json.user.id);
    expect(a.json.user.name).toMatch(/^Player\d{5}$/); // placeholder until they choose
    expect(a.json.user.nameSet).toBe(false);
    expect(a.json.user.coins).toBe(25000);
    const p = await api('/v1/me', { method: 'PATCH', token: a.json.token, body: { name: '  Raja  ', avatar: 3 } });
    expect(p.json.user).toMatchObject({ name: 'Raja', avatar: 3, nameSet: true });
    expect((await api('/v1/me')).status).toBe(401);
    expect((await api('/v1/auth/guest', { body: { deviceId: 'short' } })).status).toBe(400);
  });

  it('plays a full 2-player online match to the end and pays rewards', async () => {
    const A = await guest('Alice'); const B = await guest('Bob');
    const a = await connect(A.token, A.user.id); const b = await connect(B.token, B.user.id);

    const created = await a.emit('room:create', { maxPlayers: 2 });
    expect(created.ok).toBe(true);
    const code = created.room.code;
    expect(code).toMatch(/^[A-Z0-9]{6}$/);

    expect((await b.emit('room:join', { code: code.toLowerCase() })).ok).toBe(true);
    expect((await b.emit('room:start')).error).toBe('not_host');
    expect((await a.emit('room:start')).ok).toBe(true);
    await waitFor(() => a.room?.status === 'playing' && b.room?.status === 'playing');
    expect(a.room.members.map((m: any) => m.color)).toEqual(['red', 'yellow']);

    // Out-of-turn actions are rejected by the referee
    expect((await b.emit('game:roll')).error).toBe('not_your_turn');
    expect((await a.emit('game:move', { token: 0 })).error).toBe('not_move_phase');

    const stopA = autoplay(a), stopB = autoplay(b);
    await waitFor(() => a.room?.status === 'finished' && b.room?.status === 'finished', 60000);
    stopA(); stopB();

    const res = a.room.result;
    expect(res.reason).toBe('finished');
    const winnerId = res.ranking[0].userId;
    expect(res.rewards[winnerId]).toEqual({ coins: 2500, gems: 10 });

    const meW = await api('/v1/me', { token: winnerId === A.user.id ? A.token : B.token });
    expect(meW.json.user.wins).toBe(1);
    expect(meW.json.user.coins).toBe(27500);
    expect(meW.json.activeRoom).toBeNull();
    const lb = await api('/v1/leaderboard');
    expect(lb.json.players[0]).toMatchObject({ rank: 1, wins: 1 });
    const { rows } = await srv.db.query('SELECT count(*)::int AS n FROM matches WHERE room_code = $1', [code]);
    expect(rows[0].n).toBe(1);
    a.sock.close(); b.sock.close();
  }, 70000);

  it('handles full rooms, bad codes and double-joining', async () => {
    const [A, B, C] = await Promise.all([guest('A'), guest('B'), guest('C')]);
    const a = await connect(A.token, A.user.id), b = await connect(B.token, B.user.id), c = await connect(C.token, C.user.id);
    const { room } = await a.emit('room:create', { maxPlayers: 2 });
    expect((await a.emit('room:create', { maxPlayers: 2 })).error).toBe('already_in_room');
    expect((await b.emit('room:join', { code: 'ZZZZZZ' })).error).toBe('room_not_found');
    expect((await b.emit('room:join', { code: 'bad' })).error).toBe('bad_request');
    expect((await b.emit('room:join', { code: room.code })).ok).toBe(true);
    expect((await c.emit('room:join', { code: room.code })).error).toBe('room_full');
    expect((await a.emit('room:create', { maxPlayers: 5 })).error).toBe('bad_max_players');
    // Host leaves lobby → host passes to B
    await a.emit('room:leave');
    await waitFor(() => b.room?.hostId === B.user.id && b.room.members.length === 1);
    [a, b, c].forEach(x => x.sock.close());
  });

  it('auto-plays for a disconnected player and lets them rejoin the same match', async () => {
    const A = await guest('Ann'); const B = await guest('Ben');
    const a = await connect(A.token, A.user.id); let b = await connect(B.token, B.user.id);
    const { room } = await a.emit('room:create', { maxPlayers: 2 });
    await b.emit('room:join', { code: room.code });
    await a.emit('room:start');
    await waitFor(() => a.room?.status === 'playing');

    b.sock.close(); // Ben's phone loses network
    await waitFor(() => a.room.members.find((m: any) => m.userId === B.user.id)?.connected === false);

    const stopA = autoplay(a);
    // Ben's turns get auto-played while he is away
    await waitFor(() => a.events.some(e => e.auto && e.events[0]?.color === 'yellow'), 20000);

    const me = await api('/v1/me', { token: B.token });
    expect(me.json.activeRoom?.code).toBe(room.code);

    b = await connect(B.token, B.user.id);
    const resumed = await b.emit('room:resume');
    expect(resumed.ok).toBe(true);
    expect(resumed.room.code).toBe(room.code);
    expect(resumed.room.status).toBe('playing');
    await waitFor(() => a.room.members.find((m: any) => m.userId === B.user.id)?.connected === true);
    stopA();
    a.sock.close(); b.sock.close();
  }, 30000);

  it('times out an idle player and auto-plays their turn', async () => {
    const A = await guest('Idle'); const B = await guest('Busy');
    const a = await connect(A.token, A.user.id); const b = await connect(B.token, B.user.id);
    const { room } = await a.emit('room:create', { maxPlayers: 2 });
    await b.emit('room:join', { code: room.code });
    await a.emit('room:start');
    await waitFor(() => !!b.room?.deadline);
    expect(b.room.deadline).toBeGreaterThan(Date.now());
    // Nobody acts: after turnMs (600ms) the server rolls for red
    await waitFor(() => b.events.some(e => e.auto && e.events[0]?.type === 'rolled'), 5000);
    a.sock.close(); b.sock.close();
  });

  it('never speeds up for a present player, and removes them after 3 missed turns', async () => {
    const A = await guest('Active'); const B = await guest('Idle');
    const a = await connect(A.token, A.user.id); const b = await connect(B.token, B.user.id);
    const { room } = await a.emit('room:create', { maxPlayers: 2 });
    await b.emit('room:join', { code: room.code });
    await a.emit('room:start');
    await waitFor(() => a.room?.status === 'playing');

    const stopA = autoplay(a); // A plays normally; B is connected but never taps
    await waitFor(() => a.room?.status === 'finished', 25000);
    stopA();

    expect(a.room.result.reason).toBe('opponents_left');
    expect(a.room.result.ranking[0].userId).toBe(A.user.id);
    // B timed out on 3 turns: the first two were auto-played, the third removed them.
    const autoRolls = a.events.filter(e => e.auto && e.events[0]?.type === 'rolled' && e.events[0].color === 'yellow');
    expect(autoRolls.length).toBe(2);
    // Every one of B's auto-rolls waited the FULL turn (600 ms in tests), never the quick 30 ms.
    for (const r of autoRolls) {
      const prev = a.events.filter(e => e.at < r.at).at(-1);
      expect(r.at - prev.at).toBeGreaterThanOrEqual(550);
    }
    a.sock.close(); b.sock.close();
  }, 30000);

  it('leaving a 2-player match forfeits it to the opponent', async () => {
    const A = await guest('Stay'); const B = await guest('Quit');
    const a = await connect(A.token, A.user.id); const b = await connect(B.token, B.user.id);
    const { room } = await a.emit('room:create', { maxPlayers: 2 });
    await b.emit('room:join', { code: room.code });
    await a.emit('room:start');
    await waitFor(() => a.room?.status === 'playing');
    await b.emit('room:leave');
    await waitFor(() => a.room?.status === 'finished');
    expect(a.room.result.reason).toBe('opponents_left');
    expect(a.room.result.ranking[0].userId).toBe(A.user.id);
    expect(a.room.result.rewards[B.user.id]).toEqual({ coins: 0, gems: 0 });
    a.sock.close(); b.sock.close();
  });

  it('a 4-player room seats all colours and keeps going when one player quits', async () => {
    const gs = await Promise.all(['P1', 'P2', 'P3', 'P4'].map(guest));
    const cs = await Promise.all(gs.map(g => connect(g.token, g.user.id)));
    const { room } = await cs[0].emit('room:create', { maxPlayers: 4 });
    for (const c of cs.slice(1)) expect((await c.emit('room:join', { code: room.code })).ok).toBe(true);
    await cs[0].emit('room:start');
    await waitFor(() => cs.every(c => c.room?.status === 'playing'));
    expect(cs[0].room.members.map((m: any) => m.color)).toEqual(['red', 'green', 'yellow', 'blue']);
    await cs[3].emit('room:leave');
    await waitFor(() => cs[0].room.members[3].left === true);
    expect(cs[0].room.status).toBe('playing');
    cs.forEach(c => c.sock.close());
  });

  it('survives a server restart: rooms resume from Redis', async () => {
    const A = await guest('Before'); const B = await guest('After');
    const a = await connect(A.token, A.user.id); const b = await connect(B.token, B.user.id);
    const { room } = await a.emit('room:create', { maxPlayers: 2 });
    await b.emit('room:join', { code: room.code });
    await a.emit('room:start');
    await waitFor(() => a.room?.status === 'playing');
    a.sock.close(); b.sock.close();

    await srv.close();
    const b2 = await boot();
    srv = b2.s; base = b2.url;

    const a2 = await connect(A.token, A.user.id);
    const r = await a2.emit('room:resume');
    expect(r.ok).toBe(true);
    expect(r.room.code).toBe(room.code);
    expect(r.room.status).toBe('playing');
    a2.sock.close();
  }, 30000);

  it('links Google to a guest account without losing progress', async () => {
    const g = await guest('Linky');
    expect((await api('/v1/auth/google', { body: { idToken: 'nope-nope-nope-nope-nope' } })).status).toBe(401);
    const linked = await api('/v1/auth/google', { token: g.token, body: { idToken: 'google-ok-uid-123-abcdefghij' } });
    expect(linked.json.linked).toBe(true);
    expect(linked.json.user.id).toBe(g.user.id);
    expect(linked.json.user.hasGoogle).toBe(true);
    // On a new phone: same Google account → same player
    const again = await api('/v1/auth/google', { body: { idToken: 'google-ok-uid-123-abcdefghij' } });
    expect(again.json.user.id).toBe(g.user.id);
  });

  it('lets the website (another origin) edit the profile and delete the account', async () => {
    const res = await fetch(base + '/v1/me', {
      method: 'OPTIONS',
      headers: { origin: 'https://example.github.io', 'access-control-request-method': 'PATCH', 'access-control-request-headers': 'authorization,content-type' },
    });
    const allowed = (res.headers.get('access-control-allow-methods') ?? '').split(',').map(m => m.trim());
    expect(allowed).toEqual(expect.arrayContaining(['PATCH', 'DELETE']));
  });

  it('uses the latest profile name when creating a room', async () => {
    const g = await guest('OldName');
    const c = await connect(g.token, g.user.id); // socket connects with the old name
    await api('/v1/me', { method: 'PATCH', token: g.token, body: { name: 'NewName' } });
    const r = await c.emit('room:create', { maxPlayers: 2 });
    expect(r.room.members[0].name).toBe('NewName');
    await c.emit('room:leave');
    c.sock.close();
  });

  it('requires a unique chosen name before playing online', async () => {
    const r = await api('/v1/auth/guest', { body: { deviceId: randomBytes(16).toString('hex') } });
    const c = await connect(r.json.token, r.json.user.id);
    expect((await c.emit('room:create', { maxPlayers: 2 })).error).toBe('name_required');

    const name = 'Rahul' + randomBytes(2).toString('hex');
    expect((await api('/v1/me', { method: 'PATCH', token: r.json.token, body: { name } })).status).toBe(200);
    const ok = await c.emit('room:create', { maxPlayers: 2 });
    expect(ok.ok).toBe(true);
    expect(ok.room.members[0].name).toBe(name);
    await c.emit('room:leave');

    // Names are unique regardless of case
    const other = await api('/v1/auth/guest', { body: { deviceId: randomBytes(16).toString('hex') } });
    const taken = await api('/v1/me', { method: 'PATCH', token: other.json.token, body: { name: name.toUpperCase() } });
    expect(taken.status).toBe(409);
    expect(taken.json.error).toBe('name_taken');
    // Re-saving your own name (any case) is fine
    expect((await api('/v1/me', { method: 'PATCH', token: r.json.token, body: { name: name.toUpperCase() } })).status).toBe(200);

    // Live check endpoint
    expect((await api('/v1/names/check?name=' + encodeURIComponent(name.toLowerCase()))).json).toMatchObject({ available: false, reason: 'name_taken' });
    expect((await api('/v1/names/check?name=' + encodeURIComponent(name), { token: r.json.token })).json.available).toBe(true); // it's mine
    expect((await api('/v1/names/check?name=ab')).json).toMatchObject({ available: false, reason: 'name_invalid' });
    expect((await api('/v1/names/check?name=Player123')).json).toMatchObject({ available: false, reason: 'name_reserved' });
    expect((await api('/v1/names/check?name=' + encodeURIComponent('राहुल_07'))).json.available).toBe(true); // Hindi works
    expect((await api('/v1/me', { method: 'PATCH', token: other.json.token, body: { name: '@@@' } })).status).toBe(400);
    c.sock.close();
  });

  it('deletes an account on request', async () => {
    const g = await guest('Bye');
    expect((await api('/v1/me', { method: 'DELETE', token: g.token })).status).toBe(204);
    expect((await api('/v1/me', { token: g.token })).status).toBe(401);
  });

  it('rejects sockets without a valid token', async () => {
    const sock = ioc(base, { auth: { token: 'garbage' }, transports: ['websocket'], forceNew: true, reconnection: false });
    const err = await new Promise<Error>(res => sock.on('connect_error', res));
    expect(err.message).toBe('unauthorized');
    sock.close();
  });
});
