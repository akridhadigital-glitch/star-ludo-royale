/**
 * Generates shared/fixtures/engine-fixtures.json: scripted games (dice + chosen tokens)
 * with the expected state after every action. The Dart engine test replays these.
 */
import { writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { applyMove, applyRoll, chooseBotMove, createGame, seatColors, type GameState } from '../src/engine/engine.js';

function rng(seed: number) {
  return () => { seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 2 ** 32; };
}
const snap = (s: GameState) => ({
  turn: s.turn, phase: s.phase, dice: s.dice, sixStreak: s.sixStreak, winner: s.winner,
  tokens: s.players.map(c => s.tokens[c]), captures: s.players.map(c => s.captures[c]), moveNo: s.moveNo,
});

const games = [];
for (let g = 0; g < 24; g++) {
  const rand = rng(1000 + g);
  const players = seatColors(2 + (g % 3), (['red', 'green', 'yellow', 'blue'] as const)[g % 4]);
  let s = createGame(players);
  const steps: unknown[] = [];
  // Bias towards 6s in some games to exercise three-sixes and captures
  const biasSix = g % 4 === 3 ? 0.35 : 0;
  while (s.phase !== 'over' && steps.length < 4000) {
    if (s.phase === 'roll') {
      const v = rand() < biasSix ? 6 : 1 + Math.floor(rand() * 6);
      const t = applyRoll(s, v); s = t.state;
      steps.push({ a: 'roll', v, events: t.events.map(e => e.type), s: snap(s) });
    } else {
      const tok = chooseBotMove(s, rand);
      const t = applyMove(s, tok); s = t.state;
      steps.push({ a: 'move', v: tok, events: t.events.map(e => e.type), s: snap(s) });
    }
  }
  games.push({ players, steps });
}
const out = resolve(dirname(fileURLToPath(import.meta.url)), '../../shared/fixtures/engine-fixtures.json');
writeFileSync(out, JSON.stringify({ version: 1, games }));
console.log(`wrote ${games.length} games, ${games.reduce((n, g) => n + g.steps.length, 0)} steps -> ${out}`);
