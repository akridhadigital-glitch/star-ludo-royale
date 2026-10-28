import { randomInt } from 'node:crypto';
import {
  applyMove, applyRoll, chooseBotMove, createGame, currentColor, forceWin, movableTokens, ranking, RuleError, seatColors,
  type Color, type GameEvent, type GameState,
} from '../engine/engine.js';
import type { RoomStore } from './roomStore.js';

/**
 * Online rooms. The server is the referee: it rolls the dice (crypto RNG), validates
 * every move with the shared engine, runs the turn timer and auto-plays for players
 * who are away. Clients only send intents ("roll", "move token 2").
 */

export type RoomStatus = 'lobby' | 'playing' | 'finished';

export interface Member {
  userId: string;
  name: string;
  avatar: number;
  color: Color | null;
  connected: boolean;
  left: boolean;
  /** Consecutive turns that timed out. After 2, the player is treated as away and auto-played quickly. */
  missed: number;
}

export interface RoomResult {
  ranking: { userId: string; name: string; color: Color }[];
  rewards: Record<string, { coins: number; gems: number }>;
  reason: 'finished' | 'opponents_left';
}

export interface Room {
  code: string;
  hostId: string;
  maxPlayers: 2 | 3 | 4;
  status: RoomStatus;
  members: Member[];
  game: GameState | null;
  /** Epoch ms when the current turn auto-plays. */
  deadline: number | null;
  createdAt: number;
  startedAt: number | null;
  result: RoomResult | null;
  /** Demo mode: these players get favourable dice. Always shown to every player in the room. */
  demo?: { luckyUserIds: string[]; luckyNames: string[] } | null;
}

export interface PlayerRef { userId: string; name: string; avatar: number }

export interface RoomEmitter {
  roomUpdate(room: Room): void;
  gameEvents(code: string, payload: { events: GameEvent[]; game: GameState; deadline: number | null; actor: string | null; auto: boolean }): void;
  chat(code: string, payload: { userId: string; id: string }): void;
}

export interface MatchRecorder {
  (room: Room): Promise<void>;
}

export interface RoomManagerOptions {
  store: RoomStore;
  emitter: RoomEmitter;
  recordMatch: MatchRecorder;
  turnMs: number;
  /** Delay before auto-playing for a player who is disconnected / away. */
  awayMs?: number;
  rollDice?: () => number;
  /** DEMO ONLY: lower-cased names that get favourable dice (rooms show a visible banner). */
  demoLuckyNames?: string[];
  now?: () => number;
  log?: (msg: string, extra?: unknown) => void;
}

/** Consecutive timed-out turns before a player is removed (Ludo King style). */
export const KICK_AFTER_MISSES = { connected: 3, disconnected: 5 };

export const REWARDS = { winner: { coins: 2500, gems: 10 }, other: { coins: 250, gems: 0 } };
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const FINISHED_ROOM_TTL_MS = 10 * 60 * 1000;
export const CHAT_IDS = ['gg', 'luck', 'hurry', 'nice', 'oops', 'six', 'wow', 'laugh', 'angry', 'cool', 'fire', 'crown'];

export class RoomError extends Error {
  constructor(public code: string) { super(code); this.name = 'RoomError'; }
}

export class RoomManager {
  private rooms = new Map<string, Room>();
  private timers = new Map<string, NodeJS.Timeout>();
  private cleanup = new Map<string, NodeJS.Timeout>();
  private lastChat = new Map<string, number>();
  private readonly awayMs: number;
  private readonly rollDice: () => number;
  private readonly now: () => number;
  private readonly log: (msg: string, extra?: unknown) => void;

  constructor(private opts: RoomManagerOptions) {
    this.awayMs = opts.awayMs ?? 2500;
    this.rollDice = opts.rollDice ?? (() => randomInt(1, 7));
    this.now = opts.now ?? Date.now;
    this.log = opts.log ?? (() => {});
  }

  // ---------- lookup ----------

  private async get(code: string): Promise<Room | null> {
    const c = code.toUpperCase();
    let room = this.rooms.get(c) ?? null;
    if (!room) {
      room = await this.opts.store.load(c);
      if (room) {
        this.rooms.set(c, room);
        // Server restarted mid-game: everyone counts as disconnected until they reconnect.
        room.members.forEach(m => { m.connected = false; });
        if (room.status === 'playing') this.schedule(room);
      }
    }
    return room;
  }

  private async mustGet(code: string): Promise<Room> {
    const room = await this.get(code);
    if (!room) throw new RoomError('room_not_found');
    return room;
  }

  private member(room: Room, userId: string): Member | undefined {
    return room.members.find(m => m.userId === userId);
  }

  private memberForColor(room: Room, color: Color): Member | undefined {
    return room.members.find(m => m.color === color);
  }

  async activeRoomOf(userId: string): Promise<Room | null> {
    const code = await this.opts.store.getUserRoom(userId);
    if (!code) return null;
    const room = await this.get(code);
    const m = room && this.member(room, userId);
    if (!room || !m || m.left || room.status === 'finished') {
      await this.opts.store.setUserRoom(userId, null);
      return null;
    }
    return room;
  }

  // ---------- lobby ----------

  private async newCode(): Promise<string> {
    for (let i = 0; i < 20; i++) {
      const code = Array.from({ length: 6 }, () => CODE_ALPHABET[randomInt(CODE_ALPHABET.length)]).join('');
      if (!this.rooms.has(code) && !(await this.opts.store.load(code))) return code;
    }
    throw new RoomError('code_exhausted');
  }

  async create(p: PlayerRef, maxPlayers: number): Promise<Room> {
    if (![2, 3, 4].includes(maxPlayers)) throw new RoomError('bad_max_players');
    if (await this.activeRoomOf(p.userId)) throw new RoomError('already_in_room');
    const room: Room = {
      code: await this.newCode(), hostId: p.userId, maxPlayers: maxPlayers as 2 | 3 | 4, status: 'lobby',
      members: [{ ...p, color: null, connected: true, left: false, missed: 0 }],
      game: null, deadline: null, createdAt: this.now(), startedAt: null, result: null,
    };
    this.rooms.set(room.code, room);
    this.refreshDemo(room);
    await this.opts.store.setUserRoom(p.userId, room.code);
    await this.commit(room);
    return room;
  }

  async join(p: PlayerRef, code: string): Promise<Room> {
    const room = await this.mustGet(code);
    const existing = this.member(room, p.userId);
    if (existing && !existing.left) {
      existing.connected = true;
      await this.commit(room);
      return room;
    }
    const other = await this.activeRoomOf(p.userId);
    if (other && other.code !== room.code) throw new RoomError('already_in_room');
    if (room.status !== 'lobby') throw new RoomError('game_already_started');
    if (room.members.length >= room.maxPlayers) throw new RoomError('room_full');
    room.members.push({ ...p, color: null, connected: true, left: false, missed: 0 });
    this.refreshDemo(room);
    await this.opts.store.setUserRoom(p.userId, room.code);
    await this.commit(room);
    return room;
  }

  async start(userId: string, code: string): Promise<Room> {
    const room = await this.mustGet(code);
    if (room.hostId !== userId) throw new RoomError('not_host');
    if (room.status !== 'lobby') throw new RoomError('game_already_started');
    if (room.members.length < 2) throw new RoomError('need_two_players');
    const colors = seatColors(room.members.length);
    room.members.forEach((m, i) => { m.color = colors[i]; m.missed = 0; });
    room.game = createGame(colors);
    // Who goes first is random (crypto RNG) — the room creator gets no head start.
    room.game.turn = randomInt(colors.length);
    this.refreshDemo(room);
    room.status = 'playing';
    room.startedAt = this.now();
    this.schedule(room);
    await this.commit(room);
    return room;
  }

  async leave(userId: string, code: string): Promise<void> {
    const room = await this.get(code);
    await this.opts.store.setUserRoom(userId, null);
    if (!room) return;
    const m = this.member(room, userId);
    if (!m) return;

    if (room.status === 'lobby') {
      room.members = room.members.filter(x => x.userId !== userId);
      if (room.members.length === 0) { await this.destroy(room); return; }
      if (room.hostId === userId) room.hostId = room.members[0].userId;
      this.refreshDemo(room);
      await this.commit(room);
      return;
    }
    if (room.status === 'finished') return;

    m.left = true;
    m.connected = false;
    const stillIn = room.members.filter(x => !x.left);
    if (stillIn.length === 1 && room.game) {
      const t = forceWin(room.game, stillIn[0].color!);
      await this.finish(room, t.state, t.events, 'opponents_left');
      return;
    }
    if (stillIn.length === 0) { await this.destroy(room); return; }
    if (room.game && currentColor(room.game) === m.color) this.schedule(room);
    await this.commit(room);
  }

  async setConnected(userId: string, code: string, connected: boolean): Promise<void> {
    const room = this.rooms.get(code);
    const m = room && this.member(room, userId);
    if (!room || !m || m.left) return;
    if (m.connected === connected) return;
    m.connected = connected;
    if (connected) m.missed = 0;
    if (room.status === 'playing' && room.game && currentColor(room.game) === m.color) this.schedule(room);
    await this.commit(room);
  }

  /** Demo mode is visible from the lobby on, so players see it before agreeing to start. */
  private refreshDemo(room: Room): void {
    const lucky = room.members.filter(m => !m.left && this.opts.demoLuckyNames?.includes(m.name.toLowerCase()));
    room.demo = lucky.length ? { luckyUserIds: lucky.map(m => m.userId), luckyNames: lucky.map(m => m.name) } : null;
  }

  // ---------- gameplay ----------

  private assertTurn(room: Room, userId: string): Member {
    if (room.status !== 'playing' || !room.game) throw new RoomError('not_playing');
    const m = this.member(room, userId);
    if (!m || m.left) throw new RoomError('not_in_room');
    if (currentColor(room.game) !== m.color) throw new RoomError('not_your_turn');
    return m;
  }

  async roll(userId: string, code: string): Promise<void> {
    const room = await this.mustGet(code);
    const m = this.assertTurn(room, userId);
    m.missed = 0;
    m.connected = true;
    await this.doRoll(room, userId, false);
  }

  async move(userId: string, code: string, token: number): Promise<void> {
    const room = await this.mustGet(code);
    const m = this.assertTurn(room, userId);
    m.missed = 0;
    m.connected = true;
    await this.doMove(room, token, userId, false);
  }

  async chat(userId: string, code: string, id: string): Promise<void> {
    if (!CHAT_IDS.includes(id)) throw new RoomError('bad_chat');
    const room = await this.mustGet(code);
    if (!this.member(room, userId)) throw new RoomError('not_in_room');
    const key = `${code}:${userId}`;
    const last = this.lastChat.get(key) ?? 0;
    if (this.now() - last < 1500) throw new RoomError('slow_down');
    this.lastChat.set(key, this.now());
    this.opts.emitter.chat(code, { userId, id });
  }

  private async doRoll(room: Room, actor: string | null, auto: boolean): Promise<void> {
    const game = room.game!;
    let t;
    const roller = this.memberForColor(room, currentColor(game));
    const value = roller && room.demo?.luckyUserIds.includes(roller.userId) ? luckyRoll(game) : this.rollDice();
    try { t = applyRoll(game, value); } catch (e) { throw this.wrap(e); }
    room.game = t.state;
    this.schedule(room, auto && t.state.phase === 'move' ? 700 : undefined);
    this.opts.emitter.gameEvents(room.code, { events: t.events, game: t.state, deadline: room.deadline, actor, auto });
    await this.commit(room, false);
  }

  private async doMove(room: Room, token: number, actor: string | null, auto: boolean): Promise<void> {
    let t;
    try { t = applyMove(room.game!, token); } catch (e) { throw this.wrap(e); }
    if (t.state.phase === 'over') {
      await this.finish(room, t.state, t.events, 'finished', actor, auto);
      return;
    }
    room.game = t.state;
    this.schedule(room);
    this.opts.emitter.gameEvents(room.code, { events: t.events, game: t.state, deadline: room.deadline, actor, auto });
    await this.commit(room, false);
  }

  private wrap(e: unknown): Error {
    return e instanceof RuleError ? new RoomError(e.code) : (e as Error);
  }

  /**
   * Turn timer. A player who is in the game ALWAYS gets the full turn time; the server only
   * acts when it runs out. Quick auto-play is only for players who left, or who are disconnected
   * and already missed a turn (so the others aren't kept waiting).
   */
  private schedule(room: Room, overrideMs?: number): void {
    const prev = this.timers.get(room.code);
    if (prev) clearTimeout(prev);
    this.timers.delete(room.code);
    room.deadline = null;
    if (room.status !== 'playing' || !room.game || room.game.phase === 'over') return;

    const m = this.memberForColor(room, currentColor(room.game));
    const quick = !m || m.left || (!m.connected && m.missed >= 1);
    const delay = overrideMs ?? (quick ? this.awayMs : this.opts.turnMs);
    // Only a real timeout counts as a missed turn — not the server finishing a move it rolled itself.
    const countsAsMiss = overrideMs === undefined;
    room.deadline = this.now() + delay;
    const code = room.code;
    const moveNo = room.game.moveNo;
    this.timers.set(code, setTimeout(() => {
      this.autoPlay(code, moveNo, countsAsMiss).catch(err => this.log('autoPlay failed', err));
    }, delay));
  }

  private async autoPlay(code: string, moveNo: number, countsAsMiss = true): Promise<void> {
    const room = this.rooms.get(code);
    if (!room || room.status !== 'playing' || !room.game || room.game.moveNo !== moveNo) return;
    const m = this.memberForColor(room, currentColor(room.game));
    if (m && !m.left && countsAsMiss) {
      m.missed++;
      const limit = m.connected ? KICK_AFTER_MISSES.connected : KICK_AFTER_MISSES.disconnected;
      if (m.missed >= limit) {
        // Inactive too long: remove them (counts as leaving). If one player remains, they win.
        await this.leave(m.userId, code);
        return;
      }
    }
    if (room.game.phase === 'roll') await this.doRoll(room, null, true);
    else if (room.game.phase === 'move') await this.doMove(room, chooseBotMove(room.game), null, true);
  }

  private async finish(room: Room, state: GameState, events: GameEvent[], reason: RoomResult['reason'], actor: string | null = null, auto = false): Promise<void> {
    const prev = this.timers.get(room.code);
    if (prev) clearTimeout(prev);
    this.timers.delete(room.code);
    room.game = state;
    room.status = 'finished';
    room.deadline = null;

    const order = ranking(state);
    const result: RoomResult = { ranking: [], rewards: {}, reason };
    for (const color of order) {
      const m = this.memberForColor(room, color);
      if (!m) continue;
      result.ranking.push({ userId: m.userId, name: m.name, color });
      result.rewards[m.userId] = color === state.winner ? { ...REWARDS.winner } : (m.left ? { coins: 0, gems: 0 } : { ...REWARDS.other });
    }
    room.result = result;

    this.opts.emitter.gameEvents(room.code, { events, game: state, deadline: null, actor, auto });
    for (const m of room.members) await this.opts.store.setUserRoom(m.userId, null);
    try {
      await this.opts.recordMatch(room);
    } catch (e) {
      this.log('recordMatch failed', e);
    }
    await this.commit(room);
    this.cleanup.set(room.code, setTimeout(() => { void this.destroy(room); }, FINISHED_ROOM_TTL_MS));
  }

  private async destroy(room: Room): Promise<void> {
    const t = this.timers.get(room.code);
    if (t) clearTimeout(t);
    this.timers.delete(room.code);
    const c = this.cleanup.get(room.code);
    if (c) clearTimeout(c);
    this.cleanup.delete(room.code);
    this.rooms.delete(room.code);
    for (const m of room.members) {
      if ((await this.opts.store.getUserRoom(m.userId)) === room.code) await this.opts.store.setUserRoom(m.userId, null);
    }
    await this.opts.store.delete(room.code);
  }

  private async commit(room: Room, broadcast = true): Promise<void> {
    await this.opts.store.save(room);
    if (broadcast) this.opts.emitter.roomUpdate(room);
  }

  /** Stop all timers (graceful shutdown / tests). Room state stays in the store. */
  shutdown(): void {
    for (const t of this.timers.values()) clearTimeout(t);
    for (const t of this.cleanup.values()) clearTimeout(t);
    this.timers.clear();
    this.cleanup.clear();
  }
}

/**
 * DEMO MODE ONLY: picks the dice value that helps the current player most
 * (win > capture > reach home > leave the yard > progress; never a third six).
 * Used only for players listed in DEMO_LUCKY_NAMES, in rooms that show a demo banner.
 */
export function luckyRoll(game: GameState): number {
  let best = 1, bestScore = -Infinity;
  for (let v = 1; v <= 6; v++) {
    if (v === 6 && game.sixStreak >= 2) continue;
    const r = applyRoll(game, v);
    let score = -1000; // no move possible
    if (r.state.phase === 'move') {
      for (const tok of movableTokens(r.state, currentColor(game), v)) {
        const m = applyMove(r.state, tok);
        const types = new Set(m.events.map(e => e.type));
        let sc = 0;
        if (types.has('over')) sc += 100000;
        if (types.has('captured')) sc += 800;
        if (types.has('home')) sc += 600;
        const before = game.tokens[currentColor(game)]![tok];
        if (before === -1) sc += 500;
        sc += m.state.tokens[currentColor(game)]!.reduce((a, s) => a + s + 1, 0);
        if (types.has('bonus')) sc += 150;
        score = Math.max(score, sc);
      }
    }
    if (score > bestScore) { bestScore = score; best = v; }
  }
  return best;
}
