// Live smoke test against a deployed server: node scripts/live-smoke.mjs https://your-server
import { io } from 'socket.io-client';
import { randomBytes } from 'node:crypto';

const base = (process.argv[2] || process.env.API_URL || '').replace(/\/$/, '');
if (!base) { console.error('usage: live-smoke.mjs <url>'); process.exit(2); }
const log = (...a) => console.log('•', ...a);
const sleep = ms => new Promise(r => setTimeout(r, ms));

async function api(path, body, token) {
  const res = await fetch(base + path, {
    method: body ? 'POST' : 'GET',
    headers: { ...(body ? { 'content-type': 'application/json' } : {}), ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${path} → HTTP ${res.status} ${text.slice(0, 200)}`);
  return JSON.parse(text);
}

// Free Render instances sleep; give it up to ~3 minutes to wake.
let up = false;
for (let i = 0; i < 18 && !up; i++) {
  try { const h = await api('/health'); up = h.ok === true; } catch (e) { log(`waiting for server (${e.message.slice(0, 60)})`); await sleep(10000); }
}
if (!up) throw new Error('server did not become healthy');
log('health OK');

const guest = name => api('/v1/auth/guest', { deviceId: 'smoke' + randomBytes(12).toString('hex'), name });
const A = await guest('SmokeA'), B = await guest('SmokeB');
log('guest login OK', A.user.name, B.user.name);

const connect = token => new Promise((res, rej) => {
  const s = io(base, { auth: { token }, transports: ['websocket'], reconnection: false });
  s.on('connect', () => res(s)); s.on('connect_error', rej);
});
const call = (s, ev, p = {}) => new Promise(r => s.emit(ev, p, r));
const a = await connect(A.token), b = await connect(B.token);
log('sockets connected');

let room = null;
const onUpdate = r => { room = r; };
a.on('room:update', onUpdate);
a.on('game:events', e => { if (room) room.game = e.game; });

const created = await call(a, 'room:create', { maxPlayers: 2 });
if (!created.ok) throw new Error('create failed: ' + created.error);
log('room created', created.room.code);
const joined = await call(b, 'room:join', { code: created.room.code });
if (!joined.ok) throw new Error('join failed: ' + joined.error);
log('second player joined');
const started = await call(a, 'room:start');
if (!started.ok) throw new Error('start failed: ' + started.error);
log('match started');

// Play a few turns with whoever's turn it is
const socks = { [A.user.id]: a, [B.user.id]: b };
let actions = 0;
for (let i = 0; i < 40 && actions < 12; i++) {
  await sleep(250);
  const g = room?.game;
  if (!g) continue;
  const color = g.players[g.turn];
  const m = room.members.find(x => x.color === color);
  const s = socks[m.userId];
  if (g.phase === 'roll') { const r = await call(s, 'game:roll'); if (r.ok) actions++; }
  else if (g.phase === 'move') {
    const steps = g.tokens[color];
    const t = steps.findIndex(st => (st === -1 && g.dice === 6) || (st >= 0 && st < 56 && st + g.dice <= 56));
    const r = await call(s, 'game:move', { token: t }); if (r.ok) actions++;
  }
}
if (actions < 4) throw new Error('too few game actions succeeded: ' + actions);
log(`played ${actions} actions (dice rolled by the server)`);

await call(b, 'room:leave');
await sleep(800);
log('forfeit handled, room status:', room?.status);
const lb = await api('/v1/leaderboard');
log('leaderboard OK, players listed:', lb.players.length);
a.close(); b.close();
console.log('LIVE SMOKE TEST PASSED');
process.exit(0);
