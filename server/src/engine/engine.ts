/**
 * Star Ludo Royale — pure rules engine.
 *
 * This file is the single source of truth for the rules. The Flutter app has a
 * line-for-line Dart port (app/lib/engine/engine.dart); both are checked against
 * shared/fixtures/engine-fixtures.json so they can never drift apart.
 *
 * Token position is a single integer "step" per token:
 *   -1        in the yard (needs a 6 to come out)
 *    0..50    on the shared 52-square track (0 = the colour's start square)
 *   51..55    on the colour's private home run
 *   56        finished (reached the centre)
 *
 * Rules (Ludo King classic):
 *   - A 6 is needed to bring a token out; it lands on the start square.
 *   - Rolling a 6 gives another roll. Three 6s in a row forfeits the turn.
 *   - Landing on an opponent on a non-safe square sends it back to the yard and gives a bonus roll.
 *   - Bringing a token home gives a bonus roll. Exact roll needed to finish.
 *   - First player to bring all 4 tokens home wins.
 */

export type Color = 'red' | 'green' | 'yellow' | 'blue';
export const ORDER: readonly Color[] = ['red', 'green', 'yellow', 'blue'];
export const START_INDEX: Readonly<Record<Color, number>> = { red: 0, green: 13, yellow: 26, blue: 39 };
export const SAFE_INDICES: readonly number[] = [0, 8, 13, 21, 26, 34, 39, 47];
const SAFE = new Set(SAFE_INDICES);

export const YARD = -1;
export const LAST_TRACK_STEP = 50;
export const FINISH_STEP = 56;
export const TRACK_LENGTH = 52;

export type Phase = 'roll' | 'move' | 'over';

export interface GameState {
  players: Color[];
  tokens: Partial<Record<Color, number[]>>;
  turn: number;
  phase: Phase;
  dice: number | null;
  sixStreak: number;
  winner: Color | null;
  captures: Partial<Record<Color, number>>;
  moveNo: number;
}

export type BonusReason = 'six' | 'capture' | 'home';

export type GameEvent =
  | { type: 'rolled'; color: Color; value: number }
  | { type: 'three_sixes'; color: Color }
  | { type: 'no_move'; color: Color }
  | { type: 'moved'; color: Color; token: number; from: number; to: number }
  | { type: 'captured'; color: Color; victims: { color: Color; token: number; from: number }[] }
  | { type: 'home'; color: Color; token: number }
  | { type: 'bonus'; color: Color; reason: BonusReason }
  | { type: 'turn'; color: Color }
  | { type: 'over'; winner: Color; ranking: Color[] };

export interface Transition {
  state: GameState;
  events: GameEvent[];
}

export class RuleError extends Error {
  constructor(public code: string, message?: string) {
    super(message ?? code);
    this.name = 'RuleError';
  }
}

/** Seat colours for a match. Two players sit on opposite corners, like Ludo King. */
export function seatColors(count: number, first: Color = 'red'): Color[] {
  if (count < 2 || count > 4) throw new RuleError('bad_player_count');
  const i = ORDER.indexOf(first);
  if (count === 2) return [ORDER[i], ORDER[(i + 2) % 4]];
  return Array.from({ length: count }, (_, k) => ORDER[(i + k) % 4]);
}

export function trackIndex(color: Color, step: number): number {
  return step >= 0 && step <= LAST_TRACK_STEP ? (START_INDEX[color] + step) % TRACK_LENGTH : -1;
}

export function isSafeIndex(index: number): boolean {
  return SAFE.has(index);
}

export function createGame(players: Color[]): GameState {
  if (players.length < 2 || players.length > 4 || new Set(players).size !== players.length) {
    throw new RuleError('bad_players');
  }
  const tokens: Partial<Record<Color, number[]>> = {};
  const captures: Partial<Record<Color, number>> = {};
  for (const c of players) {
    tokens[c] = [YARD, YARD, YARD, YARD];
    captures[c] = 0;
  }
  return { players: [...players], tokens, turn: 0, phase: 'roll', dice: null, sixStreak: 0, winner: null, captures, moveNo: 0 };
}

export function currentColor(s: GameState): Color {
  return s.players[s.turn];
}

function clone(s: GameState): GameState {
  const tokens: Partial<Record<Color, number[]>> = {};
  for (const c of s.players) tokens[c] = [...s.tokens[c]!];
  return { ...s, players: [...s.players], tokens, captures: { ...s.captures } };
}

export function canMove(step: number, dice: number): boolean {
  if (step === YARD) return dice === 6;
  if (step === FINISH_STEP) return false;
  return step + dice <= FINISH_STEP;
}

export function movableTokens(s: GameState, color: Color, dice: number): number[] {
  const steps = s.tokens[color] ?? [];
  const out: number[] = [];
  steps.forEach((step, i) => { if (canMove(step, dice)) out.push(i); });
  return out;
}

function passTurn(n: GameState, events: GameEvent[]): void {
  n.turn = (n.turn + 1) % n.players.length;
  n.phase = 'roll';
  n.dice = null;
  n.sixStreak = 0;
  events.push({ type: 'turn', color: currentColor(n) });
}

export function applyRoll(s: GameState, value: number): Transition {
  if (s.phase !== 'roll') throw new RuleError('not_roll_phase');
  if (!Number.isInteger(value) || value < 1 || value > 6) throw new RuleError('bad_dice');
  const n = clone(s);
  const color = currentColor(n);
  const events: GameEvent[] = [{ type: 'rolled', color, value }];
  n.dice = value;
  n.moveNo++;
  n.sixStreak = value === 6 ? n.sixStreak + 1 : 0;

  if (n.sixStreak >= 3) {
    events.push({ type: 'three_sixes', color });
    passTurn(n, events);
    return { state: n, events };
  }
  if (movableTokens(n, color, value).length === 0) {
    events.push({ type: 'no_move', color });
    passTurn(n, events);
    return { state: n, events };
  }
  n.phase = 'move';
  return { state: n, events };
}

export function applyMove(s: GameState, token: number): Transition {
  if (s.phase !== 'move' || s.dice === null) throw new RuleError('not_move_phase');
  const color = currentColor(s);
  const dice = s.dice;
  if (!Number.isInteger(token) || !movableTokens(s, color, dice).includes(token)) throw new RuleError('illegal_move');

  const n = clone(s);
  n.moveNo++;
  const steps = n.tokens[color]!;
  const from = steps[token];
  const to = from === YARD ? 0 : from + dice;
  steps[token] = to;
  const events: GameEvent[] = [{ type: 'moved', color, token, from, to }];

  let bonus: BonusReason | null = null;

  if (to <= LAST_TRACK_STEP) {
    const idx = trackIndex(color, to);
    if (!SAFE.has(idx)) {
      const victims: { color: Color; token: number; from: number }[] = [];
      for (const other of n.players) {
        if (other === color) continue;
        n.tokens[other]!.forEach((st, i) => {
          if (trackIndex(other, st) === idx) {
            victims.push({ color: other, token: i, from: st });
            n.tokens[other]![i] = YARD;
          }
        });
      }
      if (victims.length) {
        n.captures[color] = (n.captures[color] ?? 0) + victims.length;
        events.push({ type: 'captured', color, victims });
        bonus = 'capture';
      }
    }
  }

  if (to === FINISH_STEP) {
    events.push({ type: 'home', color, token });
    bonus = bonus ?? 'home';
    if (steps.every(st => st === FINISH_STEP)) {
      n.phase = 'over';
      n.winner = color;
      n.dice = null;
      events.push({ type: 'over', winner: color, ranking: ranking(n) });
      return { state: n, events };
    }
  }

  if (!bonus && dice === 6) bonus = 'six';

  if (bonus) {
    n.phase = 'roll';
    n.dice = null;
    events.push({ type: 'bonus', color, reason: bonus });
  } else {
    passTurn(n, events);
  }
  return { state: n, events };
}

/** Progress score used for ranking non-winners: each token contributes (step + 1), finished = 57. */
export function progress(s: GameState, color: Color): number {
  return (s.tokens[color] ?? []).reduce((sum, st) => sum + (st + 1), 0);
}

export function ranking(s: GameState): Color[] {
  return [...s.players].sort((a, b) => {
    if (s.winner === a) return -1;
    if (s.winner === b) return 1;
    return progress(s, b) - progress(s, a) || s.players.indexOf(a) - s.players.indexOf(b);
  });
}

/** End the game early (e.g. every other human left an online room). */
export function forceWin(s: GameState, winner: Color): Transition {
  const n = clone(s);
  n.phase = 'over';
  n.winner = winner;
  n.dice = null;
  n.moveNo++;
  return { state: n, events: [{ type: 'over', winner, ranking: ranking(n) }] };
}

/**
 * Bot / auto-play move choice. Deterministic given `rand`.
 * Priorities: finish > capture > leave yard > reach safety > advance, avoiding danger.
 */
export function chooseBotMove(s: GameState, rand: () => number = Math.random): number {
  const color = currentColor(s);
  const dice = s.dice;
  if (dice === null) throw new RuleError('not_move_phase');
  const legal = movableTokens(s, color, dice);
  if (legal.length === 0) throw new RuleError('no_legal_move');
  if (legal.length === 1) return legal[0];

  const opponents = s.players.filter(c => c !== color);
  const occupied = (idx: number) =>
    opponents.some(o => s.tokens[o]!.some(st => trackIndex(o, st) === idx));
  const threatened = (idx: number) =>
    opponents.some(o => s.tokens[o]!.some(st => {
      const oi = trackIndex(o, st);
      if (oi < 0) return false;
      const dist = (idx - oi + TRACK_LENGTH) % TRACK_LENGTH;
      return dist >= 1 && dist <= 6;
    }));

  let best = legal[0];
  let bestScore = -Infinity;
  for (const t of legal) {
    const from = s.tokens[color]![t];
    const to = from === YARD ? 0 : from + dice;
    let score = 0;
    if (to === FINISH_STEP) score += 1200;
    else if (from === YARD) score += 650;
    else if (to <= LAST_TRACK_STEP) {
      const idx = trackIndex(color, to);
      const safe = SAFE.has(idx);
      if (!safe && occupied(idx)) score += 900;
      if (safe) score += 400;
      else if (threatened(idx)) score -= 250;
      const fromIdx = trackIndex(color, from);
      if (fromIdx >= 0 && !SAFE.has(fromIdx) && threatened(fromIdx)) score += 150; // escape danger
      score += to * 8;
    } else {
      score += 500 + to * 10; // entering / moving inside the home run is permanently safe
    }
    score += rand() * 20;
    if (score > bestScore) { bestScore = score; best = t; }
  }
  return best;
}
