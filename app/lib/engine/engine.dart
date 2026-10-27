// Star Ludo Royale — rules engine (Dart port).
//
// Line-for-line port of server/src/engine/engine.ts. Both are tested against
// shared/fixtures/engine-fixtures.json so offline play and the online referee
// always agree. Change the rules in BOTH files and regenerate the fixtures.
//
// Token "step": -1 yard, 0..50 shared track, 51..55 home run, 56 finished.

import 'dart:math';

enum LudoColor { red, green, yellow, blue }

const List<LudoColor> kOrder = [LudoColor.red, LudoColor.green, LudoColor.yellow, LudoColor.blue];
const Map<LudoColor, int> kStartIndex = {
  LudoColor.red: 0,
  LudoColor.green: 13,
  LudoColor.yellow: 26,
  LudoColor.blue: 39,
};
const Set<int> kSafeIndices = {0, 8, 13, 21, 26, 34, 39, 47};
const int kYard = -1;
const int kLastTrackStep = 50;
const int kFinishStep = 56;
const int kTrackLength = 52;

LudoColor colorFromName(String s) => LudoColor.values.firstWhere((c) => c.name == s);

enum Phase { roll, move, over }

Phase phaseFromName(String s) => Phase.values.firstWhere((p) => p.name == s);

class RuleError implements Exception {
  final String code;
  RuleError(this.code);
  @override
  String toString() => 'RuleError($code)';
}

class GameState {
  final List<LudoColor> players;
  final Map<LudoColor, List<int>> tokens;
  int turn;
  Phase phase;
  int? dice;
  int sixStreak;
  LudoColor? winner;
  final Map<LudoColor, int> captures;
  int moveNo;

  GameState({
    required this.players,
    required this.tokens,
    this.turn = 0,
    this.phase = Phase.roll,
    this.dice,
    this.sixStreak = 0,
    this.winner,
    required this.captures,
    this.moveNo = 0,
  });

  LudoColor get current => players[turn];

  GameState copy() => GameState(
        players: List.of(players),
        tokens: {for (final c in players) c: List.of(tokens[c]!)},
        turn: turn,
        phase: phase,
        dice: dice,
        sixStreak: sixStreak,
        winner: winner,
        captures: Map.of(captures),
        moveNo: moveNo,
      );

  Map<String, dynamic> toJson() => {
        'players': players.map((c) => c.name).toList(),
        'tokens': {for (final c in players) c.name: tokens[c]},
        'turn': turn,
        'phase': phase.name,
        'dice': dice,
        'sixStreak': sixStreak,
        'winner': winner?.name,
        'captures': {for (final c in players) c.name: captures[c] ?? 0},
        'moveNo': moveNo,
      };

  factory GameState.fromJson(Map<String, dynamic> j) {
    final players = (j['players'] as List).map((e) => colorFromName(e as String)).toList();
    final tok = j['tokens'] as Map<String, dynamic>;
    final cap = (j['captures'] as Map<String, dynamic>?) ?? {};
    return GameState(
      players: players,
      tokens: {for (final c in players) c: (tok[c.name] as List).map((e) => (e as num).toInt()).toList()},
      turn: (j['turn'] as num).toInt(),
      phase: phaseFromName(j['phase'] as String),
      dice: (j['dice'] as num?)?.toInt(),
      sixStreak: (j['sixStreak'] as num?)?.toInt() ?? 0,
      winner: j['winner'] == null ? null : colorFromName(j['winner'] as String),
      captures: {for (final c in players) c: ((cap[c.name] as num?) ?? 0).toInt()},
      moveNo: (j['moveNo'] as num?)?.toInt() ?? 0,
    );
  }
}

enum EventType { rolled, threeSixes, noMove, moved, captured, home, bonus, turn, over }

const Map<String, EventType> _eventNames = {
  'rolled': EventType.rolled,
  'three_sixes': EventType.threeSixes,
  'no_move': EventType.noMove,
  'moved': EventType.moved,
  'captured': EventType.captured,
  'home': EventType.home,
  'bonus': EventType.bonus,
  'turn': EventType.turn,
  'over': EventType.over,
};

String eventWireName(EventType t) => _eventNames.entries.firstWhere((e) => e.value == t).key;

class Victim {
  final LudoColor color;
  final int token;
  final int from;
  const Victim(this.color, this.token, this.from);
}

class GameEvent {
  final EventType type;
  final LudoColor color;
  final int value; // dice value for `rolled`
  final int token;
  final int from;
  final int to;
  final List<Victim> victims;
  final String reason; // bonus reason: six | capture | home
  final List<LudoColor> ranking;

  const GameEvent(
    this.type,
    this.color, {
    this.value = 0,
    this.token = -1,
    this.from = 0,
    this.to = 0,
    this.victims = const [],
    this.reason = '',
    this.ranking = const [],
  });

  factory GameEvent.fromJson(Map<String, dynamic> j) {
    final type = _eventNames[j['type']]!;
    final color = colorFromName((j['color'] ?? j['winner']) as String);
    return GameEvent(
      type,
      color,
      value: (j['value'] as num?)?.toInt() ?? 0,
      token: (j['token'] as num?)?.toInt() ?? -1,
      from: (j['from'] as num?)?.toInt() ?? 0,
      to: (j['to'] as num?)?.toInt() ?? 0,
      victims: ((j['victims'] as List?) ?? const [])
          .map((v) => Victim(colorFromName(v['color'] as String), (v['token'] as num).toInt(), (v['from'] as num).toInt()))
          .toList(),
      reason: (j['reason'] as String?) ?? '',
      ranking: ((j['ranking'] as List?) ?? const []).map((e) => colorFromName(e as String)).toList(),
    );
  }
}

class Transition {
  final GameState state;
  final List<GameEvent> events;
  const Transition(this.state, this.events);
}

List<LudoColor> seatColors(int count, [LudoColor first = LudoColor.red]) {
  if (count < 2 || count > 4) throw RuleError('bad_player_count');
  final i = kOrder.indexOf(first);
  if (count == 2) return [kOrder[i], kOrder[(i + 2) % 4]];
  return List.generate(count, (k) => kOrder[(i + k) % 4]);
}

int trackIndex(LudoColor color, int step) =>
    step >= 0 && step <= kLastTrackStep ? (kStartIndex[color]! + step) % kTrackLength : -1;

bool isSafeIndex(int index) => kSafeIndices.contains(index);

GameState createGame(List<LudoColor> players) {
  if (players.length < 2 || players.length > 4 || players.toSet().length != players.length) {
    throw RuleError('bad_players');
  }
  return GameState(
    players: List.of(players),
    tokens: {for (final c in players) c: [kYard, kYard, kYard, kYard]},
    captures: {for (final c in players) c: 0},
  );
}

bool canMove(int step, int dice) {
  if (step == kYard) return dice == 6;
  if (step == kFinishStep) return false;
  return step + dice <= kFinishStep;
}

List<int> movableTokens(GameState s, LudoColor color, int dice) {
  final steps = s.tokens[color] ?? const <int>[];
  return [for (var i = 0; i < steps.length; i++) if (canMove(steps[i], dice)) i];
}

void _passTurn(GameState n, List<GameEvent> events) {
  n.turn = (n.turn + 1) % n.players.length;
  n.phase = Phase.roll;
  n.dice = null;
  n.sixStreak = 0;
  events.add(GameEvent(EventType.turn, n.current));
}

Transition applyRoll(GameState s, int value) {
  if (s.phase != Phase.roll) throw RuleError('not_roll_phase');
  if (value < 1 || value > 6) throw RuleError('bad_dice');
  final n = s.copy();
  final color = n.current;
  final events = <GameEvent>[GameEvent(EventType.rolled, color, value: value)];
  n.dice = value;
  n.moveNo++;
  n.sixStreak = value == 6 ? n.sixStreak + 1 : 0;

  if (n.sixStreak >= 3) {
    events.add(GameEvent(EventType.threeSixes, color));
    _passTurn(n, events);
    return Transition(n, events);
  }
  if (movableTokens(n, color, value).isEmpty) {
    events.add(GameEvent(EventType.noMove, color));
    _passTurn(n, events);
    return Transition(n, events);
  }
  n.phase = Phase.move;
  return Transition(n, events);
}

Transition applyMove(GameState s, int token) {
  if (s.phase != Phase.move || s.dice == null) throw RuleError('not_move_phase');
  final color = s.current;
  final dice = s.dice!;
  if (!movableTokens(s, color, dice).contains(token)) throw RuleError('illegal_move');

  final n = s.copy();
  n.moveNo++;
  final steps = n.tokens[color]!;
  final from = steps[token];
  final to = from == kYard ? 0 : from + dice;
  steps[token] = to;
  final events = <GameEvent>[GameEvent(EventType.moved, color, token: token, from: from, to: to)];

  String? bonus;

  if (to <= kLastTrackStep) {
    final idx = trackIndex(color, to);
    if (!kSafeIndices.contains(idx)) {
      final victims = <Victim>[];
      for (final other in n.players) {
        if (other == color) continue;
        final ot = n.tokens[other]!;
        for (var i = 0; i < ot.length; i++) {
          if (trackIndex(other, ot[i]) == idx) {
            victims.add(Victim(other, i, ot[i]));
            ot[i] = kYard;
          }
        }
      }
      if (victims.isNotEmpty) {
        n.captures[color] = (n.captures[color] ?? 0) + victims.length;
        events.add(GameEvent(EventType.captured, color, victims: victims));
        bonus = 'capture';
      }
    }
  }

  if (to == kFinishStep) {
    events.add(GameEvent(EventType.home, color, token: token));
    bonus ??= 'home';
    if (steps.every((st) => st == kFinishStep)) {
      n.phase = Phase.over;
      n.winner = color;
      n.dice = null;
      events.add(GameEvent(EventType.over, color, ranking: ranking(n)));
      return Transition(n, events);
    }
  }

  if (bonus == null && dice == 6) bonus = 'six';

  if (bonus != null) {
    n.phase = Phase.roll;
    n.dice = null;
    events.add(GameEvent(EventType.bonus, color, reason: bonus));
  } else {
    _passTurn(n, events);
  }
  return Transition(n, events);
}

int progress(GameState s, LudoColor color) => (s.tokens[color] ?? const <int>[]).fold(0, (sum, st) => sum + st + 1);

List<LudoColor> ranking(GameState s) {
  final list = List.of(s.players);
  list.sort((a, b) {
    if (s.winner == a) return -1;
    if (s.winner == b) return 1;
    final d = progress(s, b) - progress(s, a);
    return d != 0 ? d : s.players.indexOf(a) - s.players.indexOf(b);
  });
  return list;
}

/// Same scoring as the server's chooseBotMove.
int chooseBotMove(GameState s, [Random? rng]) {
  final r = rng ?? Random();
  final color = s.current;
  final dice = s.dice;
  if (dice == null) throw RuleError('not_move_phase');
  final legal = movableTokens(s, color, dice);
  if (legal.isEmpty) throw RuleError('no_legal_move');
  if (legal.length == 1) return legal.first;

  final opponents = s.players.where((c) => c != color).toList();
  bool occupied(int idx) => opponents.any((o) => s.tokens[o]!.any((st) => trackIndex(o, st) == idx));
  bool threatened(int idx) => opponents.any((o) => s.tokens[o]!.any((st) {
        final oi = trackIndex(o, st);
        if (oi < 0) return false;
        final dist = (idx - oi + kTrackLength) % kTrackLength;
        return dist >= 1 && dist <= 6;
      }));

  var best = legal.first;
  var bestScore = double.negativeInfinity;
  for (final t in legal) {
    final from = s.tokens[color]![t];
    final to = from == kYard ? 0 : from + dice;
    double score = 0;
    if (to == kFinishStep) {
      score += 1200;
    } else if (from == kYard) {
      score += 650;
    } else if (to <= kLastTrackStep) {
      final idx = trackIndex(color, to);
      final safe = kSafeIndices.contains(idx);
      if (!safe && occupied(idx)) score += 900;
      if (safe) {
        score += 400;
      } else if (threatened(idx)) {
        score -= 250;
      }
      final fromIdx = trackIndex(color, from);
      if (fromIdx >= 0 && !kSafeIndices.contains(fromIdx) && threatened(fromIdx)) score += 150;
      score += to * 8;
    } else {
      score += 500 + to * 10;
    }
    score += r.nextDouble() * 20;
    if (score > bestScore) {
      bestScore = score;
      best = t;
    }
  }
  return best;
}
