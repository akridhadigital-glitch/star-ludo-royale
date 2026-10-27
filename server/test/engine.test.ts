import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import {
  applyMove, applyRoll, chooseBotMove, createGame, FINISH_STEP, movableTokens, RuleError,
  seatColors, trackIndex, isSafeIndex, type GameState, YARD,
} from '../src/engine/engine.js';

const withTokens = (s: GameState, t: Partial<Record<string, number[]>>) => ({ ...s, tokens: { ...s.tokens, ...t } }) as GameState;

describe('seating', () => {
  it('puts two players on opposite corners', () => {
    expect(seatColors(2)).toEqual(['red', 'yellow']);
    expect(seatColors(2, 'green')).toEqual(['green', 'blue']);
    expect(seatColors(3)).toEqual(['red', 'green', 'yellow']);
    expect(seatColors(4, 'blue')).toEqual(['blue', 'red', 'green', 'yellow']);
  });
  it('rejects bad counts', () => { expect(() => seatColors(1)).toThrow(RuleError); });
});

describe('rules', () => {
  it('needs a 6 to leave the yard; otherwise the turn passes', () => {
    const s = createGame(['red', 'yellow']);
    const t = applyRoll(s, 4);
    expect(t.events.map(e => e.type)).toEqual(['rolled', 'no_move', 'turn']);
    expect(t.state.turn).toBe(1);
  });

  it('a 6 brings a token out and gives a bonus roll', () => {
    let s = applyRoll(createGame(['red', 'yellow']), 6).state;
    expect(s.phase).toBe('move');
    const t = applyMove(s, 0);
    expect(t.state.tokens.red![0]).toBe(0);
    expect(t.state.turn).toBe(0);
    expect(t.events.at(-1)).toEqual({ type: 'bonus', color: 'red', reason: 'six' });
  });

  it('three 6s in a row forfeits the turn', () => {
    let s = createGame(['red', 'yellow']);
    s = applyMove(applyRoll(s, 6).state, 0).state;
    s = applyMove(applyRoll(s, 6).state, 0).state;
    const t = applyRoll(s, 6);
    expect(t.events.map(e => e.type)).toEqual(['rolled', 'three_sixes', 'turn']);
    expect(t.state.turn).toBe(1);
    expect(t.state.sixStreak).toBe(0);
  });

  it('captures on a normal square, sends victim home, and grants a bonus', () => {
    // red token at step 3 (index 3); yellow token at its step 29 → index (26+29)%52 = 3
    let s = withTokens(createGame(['red', 'yellow']), { red: [1, YARD, YARD, YARD], yellow: [29, YARD, YARD, YARD] });
    expect(trackIndex('yellow', 29)).toBe(3);
    s = applyRoll(s, 2).state;
    const t = applyMove(s, 0);
    expect(t.state.tokens.yellow![0]).toBe(YARD);
    expect(t.state.captures.red).toBe(1);
    expect(t.events.find(e => e.type === 'bonus')).toMatchObject({ reason: 'capture' });
    expect(t.state.turn).toBe(0);
  });

  it('never captures on a safe star', () => {
    expect(isSafeIndex(8)).toBe(true);
    // yellow step 34 → index 8
    let s = withTokens(createGame(['red', 'yellow']), { red: [5, YARD, YARD, YARD], yellow: [34, YARD, YARD, YARD] });
    s = applyRoll(s, 3).state;
    const t = applyMove(s, 0);
    expect(t.state.tokens.yellow![0]).toBe(34);
    expect(t.state.turn).toBe(1);
  });

  it('needs an exact roll to finish and gives a bonus for reaching home', () => {
    let s = withTokens(createGame(['red', 'yellow']), { red: [54, YARD, YARD, YARD] });
    expect(movableTokens(s, 'red', 3)).toEqual([]);
    s = applyRoll(s, 2).state;
    const t = applyMove(s, 0);
    expect(t.state.tokens.red![0]).toBe(FINISH_STEP);
    expect(t.events.find(e => e.type === 'bonus')).toMatchObject({ reason: 'home' });
  });

  it('declares a winner when all four tokens are home', () => {
    let s = withTokens(createGame(['red', 'yellow']), { red: [56, 56, 56, 55] });
    s = applyRoll(s, 1).state;
    const t = applyMove(s, 3);
    expect(t.state.phase).toBe('over');
    expect(t.state.winner).toBe('red');
    expect(t.events.at(-1)).toMatchObject({ type: 'over', winner: 'red', ranking: ['red', 'yellow'] });
    expect(() => applyRoll(t.state, 3)).toThrow(RuleError);
  });

  it('rejects illegal actions', () => {
    const s = createGame(['red', 'yellow']);
    expect(() => applyMove(s, 0)).toThrow(RuleError);
    expect(() => applyRoll(s, 7)).toThrow(RuleError);
    const r = applyRoll(s, 6).state;
    expect(() => applyRoll(r, 3)).toThrow(RuleError);
    expect(() => applyMove(r, 9)).toThrow(RuleError);
  });

  it('bot prefers capturing', () => {
    let s = withTokens(createGame(['red', 'yellow']), { red: [1, 10, YARD, YARD], yellow: [29, YARD, YARD, YARD] });
    s = applyRoll(s, 2).state;
    expect(chooseBotMove(s, () => 0.5)).toBe(0);
  });
});

describe('simulation invariants', () => {
  it('300 random bot games always finish with legal states', () => {
    let seed = 42;
    const rand = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff; };
    for (let g = 0; g < 300; g++) {
      let s = createGame(seatColors(2 + (g % 3)));
      let actions = 0;
      while (s.phase !== 'over') {
        s = s.phase === 'roll' ? applyRoll(s, 1 + Math.floor(rand() * 6)).state : applyMove(s, chooseBotMove(s, rand)).state;
        if (++actions > 20000) throw new Error('game did not finish');
        // No two different colours share a non-safe track square
        const seen = new Map<number, string>();
        for (const c of s.players) for (const st of s.tokens[c]!) {
          if (st < -1 || st > 56) throw new Error(`bad step ${st}`);
          const idx = trackIndex(c, st);
          if (idx >= 0 && !isSafeIndex(idx)) {
            const o = seen.get(idx);
            if (o && o !== c) throw new Error(`overlap at ${idx}`);
            seen.set(idx, c);
          }
        }
      }
      expect(s.winner).not.toBeNull();
      expect(s.tokens[s.winner!]!.every(st => st === 56)).toBe(true);
    }
  });
});

describe('shared fixtures', () => {
  it('engine reproduces every fixture step (same file the Dart engine is tested against)', () => {
    const fx = JSON.parse(readFileSync(new URL('../../shared/fixtures/engine-fixtures.json', import.meta.url), 'utf8'));
    for (const g of fx.games) {
      let s = createGame(g.players);
      for (const step of g.steps) {
        const t = step.a === 'roll' ? applyRoll(s, step.v) : applyMove(s, step.v);
        s = t.state;
        expect(t.events.map(e => e.type)).toEqual(step.events);
        expect({ turn: s.turn, phase: s.phase, dice: s.dice, sixStreak: s.sixStreak, winner: s.winner,
          tokens: s.players.map(c => s.tokens[c]), captures: s.players.map(c => s.captures[c]), moveNo: s.moveNo }).toEqual(step.s);
      }
    }
  });
});
