// Soak test: two players play a whole online game at human pace against a deployed server and
// report connection drops (with reasons), action latency, and how late the OTHER player sees
// each move. Usage: node scripts/soak.mjs https://your-server [maxMinutes]
import { io } from 'socket.io-client';
import { randomBytes } from 'node:crypto';

const base = (process.argv[2] || process.env.API_URL || '').replace(/\/$/, '');
const maxMs = (Number(process.argv[3]) || 12) * 60_000;
if (!base) { console.error('usage: soak.mjs <url> [minutes]'); process.exit(2); }
const sleep = ms => new Promise(r => setTimeout(r, ms));
const t0 = Date.now();
const at = () => ((Date.now() - t0) / 1000).toFixed(1) + 's';
const log = (...a) => console.log(at(), ...a);

async function http(method, path, body, token) {
  const res = await fetch(base + path, {
    method,
    headers: { ...(body ? { 'content-type': 'application/json' } : {}), ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${method} ${path} → ${res.status} ${text.slice(0, 160)}`);
  return text ? JSON.parse(text) : {};
}

for (let i = 0; i < 18; i++) {
  try { await http('GET', '/health'); break; } catch { log('waking server…'); await sleep(10_000); }
}

async function player(label) {
  const g = await http('POST', '/v1/auth/guest', { deviceId: 'smoke' + randomBytes(12).toString('hex') });
  const me = await http('PATCH', '/v1/me', { name: 'Soak' + label + randomBytes(2).toString('hex') }, g.token);
  const p = { label, id: me.user.id, token: g.token, room: null, game: null, seen: new Map(), drops: [], reconnects: 0, ack: [] };
  p.sock = io(base, { auth: { token: g.token }, transports: ['websocket'], reconnection: true, reconnectionDelay: 500 });
  p.sock.on('room:update', r => { p.room = r; if (r.game && (!p.game || r.game.moveNo >= p.game.moveNo)) p.game = r.game; });
  p.sock.on('game:events', e => {
    if (!p.seen.has(e.game.moveNo)) p.seen.set(e.game.moveNo, Date.now());
    if (!p.game || e.game.moveNo >= p.game.moveNo) p.game = e.game;
  });
  p.sock.on('disconnect', reason => { p.drops.push({ at: at(), reason }); log(`${label} DISCONNECTED: ${reason}`); });
  p.sock.io.on('reconnect', () => {
    p.reconnects++;
    log(`${label} reconnected`);
    p.sock.emit('room:resume', {}, r => { if (r?.room) { p.room = r.room; p.game = r.room.game; } });
  });
  await new Promise((res, rej) => { p.sock.once('connect', res); p.sock.once('connect_error', rej); });
  p.call = (ev, payload = {}) => new Promise(res => {
    const s = Date.now();
    p.sock.timeout(15_000).emit(ev, payload, (err, r) => { p.ack.push(Date.now() - s); res(err ? { ok: false, error: 'timeout' } : r); });
  });
  return p;
}

const A = await player('A'), B = await player('B');
const created = await A.call('room:create', { maxPlayers: 2 });
if (!created.ok) throw new Error('create: ' + created.error);
await B.call('room:join', { code: created.room.code });
await A.call('room:start');
log('match started in room', created.room.code);

const byColor = () => Object.fromEntries((A.room?.members ?? []).map(m => [m.color, m.userId === A.id ? A : B]));
const sent = new Map(); // moveNo → time the acting client sent it
let actions = 0, rejected = 0;
while (Date.now() - t0 < maxMs) {
  const g = A.game ?? B.game;
  if (A.room?.status === 'finished' || B.room?.status === 'finished') break;
  if (!g) { await sleep(200); continue; }
  const color = g.players[g.turn];
  const p = byColor()[color];
  if (!p || !p.sock.connected) { await sleep(300); continue; }
  const pg = p.game;
  if (!pg || pg.moveNo !== Math.max(A.game?.moveNo ?? 0, B.game?.moveNo ?? 0)) { await sleep(100); continue; }
  await sleep(600 + Math.random() * 900); // human thinking time
  const before = pg.moveNo;
  sent.set(before + 1, Date.now());
  let r;
  if (pg.phase === 'roll') r = await p.call('game:roll');
  else {
    const steps = pg.tokens[color];
    const t = steps.findIndex(st => (st === -1 && pg.dice === 6) || (st >= 0 && st < 56 && st + pg.dice <= 56));
    r = await p.call('game:move', { token: t });
  }
  if (r?.ok) actions++; else { rejected++; await sleep(300); }
  await sleep(250);
}

const pct = (arr, q) => { const s = [...arr].sort((a, b) => a - b); return s.length ? s[Math.min(s.length - 1, Math.floor(q * s.length))] : 0; };
// How late each client saw each move relative to when it was sent
const seenA = [], seenB = [];
for (const [mv, ts] of sent) {
  if (A.seen.has(mv)) seenA.push(A.seen.get(mv) - ts);
  if (B.seen.has(mv)) seenB.push(B.seen.get(mv) - ts);
}
const status = A.room?.status;
console.log('\n===== SOAK RESULT =====');
console.log(`duration ${at()}, status ${status}, actions ok ${actions}, rejected ${rejected}`);
console.log(`ack latency ms  p50 ${pct([...A.ack, ...B.ack], 0.5)}  p95 ${pct([...A.ack, ...B.ack], 0.95)}  max ${Math.max(0, ...A.ack, ...B.ack)}`);
console.log(`event delivery ms  A p50 ${pct(seenA, 0.5)} p95 ${pct(seenA, 0.95)} max ${Math.max(0, ...seenA)} | B p50 ${pct(seenB, 0.5)} p95 ${pct(seenB, 0.95)} max ${Math.max(0, ...seenB)}`);
console.log(`disconnects A ${A.drops.length} ${JSON.stringify(A.drops)} | B ${B.drops.length} ${JSON.stringify(B.drops)}`);
console.log(`reconnects A ${A.reconnects} B ${B.reconnects}`);
A.sock.close(); B.sock.close();
process.exit(0);
