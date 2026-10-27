import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:star_ludo_royale/engine/engine.dart';

Map<String, dynamic> snap(GameState s) => {
      'turn': s.turn,
      'phase': s.phase.name,
      'dice': s.dice,
      'sixStreak': s.sixStreak,
      'winner': s.winner?.name,
      'tokens': s.players.map((c) => s.tokens[c]).toList(),
      'captures': s.players.map((c) => s.captures[c]).toList(),
      'moveNo': s.moveNo,
    };

void main() {
  test('seat colours match the server', () {
    expect(seatColors(2), [LudoColor.red, LudoColor.yellow]);
    expect(seatColors(3), [LudoColor.red, LudoColor.green, LudoColor.yellow]);
    expect(seatColors(4, LudoColor.blue), [LudoColor.blue, LudoColor.red, LudoColor.green, LudoColor.yellow]);
  });

  test('Dart engine reproduces every shared fixture step exactly', () {
    final file = File('../shared/fixtures/engine-fixtures.json');
    final fx = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    var count = 0;
    for (final g in fx['games'] as List) {
      var s = createGame((g['players'] as List).map((e) => colorFromName(e as String)).toList());
      for (final step in g['steps'] as List) {
        final t = step['a'] == 'roll' ? applyRoll(s, step['v'] as int) : applyMove(s, step['v'] as int);
        s = t.state;
        expect(t.events.map((e) => eventWireName(e.type)).toList(), step['events'], reason: 'events at step $count');
        expect(jsonDecode(jsonEncode(snap(s))), step['s'], reason: 'state at step $count');
        count++;
      }
    }
    expect(count, greaterThan(1000));
  });

  test('state survives a JSON round trip (save / resume and online sync)', () {
    var s = createGame(seatColors(4));
    final rng = Random(3);
    for (var i = 0; i < 300 && s.phase != Phase.over; i++) {
      s = s.phase == Phase.roll ? applyRoll(s, 1 + rng.nextInt(6)).state : applyMove(s, chooseBotMove(s, rng)).state;
    }
    final back = GameState.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    expect(snap(back), snap(s));
  });

  test('bot games always finish', () {
    final rng = Random(11);
    for (var g = 0; g < 100; g++) {
      var s = createGame(seatColors(2 + g % 3));
      var n = 0;
      while (s.phase != Phase.over) {
        s = s.phase == Phase.roll ? applyRoll(s, 1 + rng.nextInt(6)).state : applyMove(s, chooseBotMove(s, rng)).state;
        expect(++n, lessThan(20000));
      }
      expect(s.tokens[s.winner]!.every((t) => t == kFinishStep), isTrue);
    }
  });

  test('parses server events', () {
    final e = GameEvent.fromJson({
      'type': 'captured',
      'color': 'red',
      'victims': [
        {'color': 'yellow', 'token': 2, 'from': 29}
      ]
    });
    expect(e.type, EventType.captured);
    expect(e.victims.single.color, LudoColor.yellow);
    final over = GameEvent.fromJson({'type': 'over', 'winner': 'blue', 'ranking': ['blue', 'red']});
    expect(over.color, LudoColor.blue);
    expect(over.ranking, [LudoColor.blue, LudoColor.red]);
  });
}
