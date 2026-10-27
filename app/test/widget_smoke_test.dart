import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_ludo_royale/core/storage.dart';
import 'package:star_ludo_royale/engine/engine.dart';
import 'package:star_ludo_royale/game/board.dart';
import 'package:star_ludo_royale/game/game_screen.dart';
import 'package:star_ludo_royale/game/match_controller.dart';
import 'package:star_ludo_royale/screens/legal_screen.dart';
import 'package:star_ludo_royale/widgets/common.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'accepted_terms_v1': true, 'sound_on': false, 'haptics_on': false});
    await Storage.init();
  });

  test('board geometry: every track/home-run cell is on the 15x15 grid and unique', () {
    final seen = <String>{};
    for (final c in kOrder) {
      for (var step = 0; step <= kFinishStep; step++) {
        final p = BoardGeometry.tokenCell(c, step, 0);
        expect(p.dx, inInclusiveRange(0, 14));
        expect(p.dy, inInclusiveRange(0, 14));
        if (step <= kLastTrackStep) seen.add('${trackIndex(c, step)}');
      }
    }
    expect(seen.length, 52);
    expect(BoardGeometry.mainPath.toSet().length, 52);
  });

  testWidgets('logo and legal screen render', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: LogoBadge(size: 120)))));
    expect(find.byType(LogoBadge), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: LegalScreen()));
    expect(find.text('Privacy Policy'), findsOneWidget);
  });

  testWidgets('an offline vs-computer match renders and the dice can be rolled', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final c = LocalMatchController.newMatch(const MatchSetup(vsComputer: true, count: 4, myColor: LudoColor.red));
    await tester.pumpWidget(MaterialApp(home: GameScreen(controller: c)));
    await tester.pump(const Duration(milliseconds: 50));
    expect(c.canRoll, isTrue);
    await c.roll();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(c.state.moveNo, greaterThan(0));
    // Leave the screen so timers are cancelled.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
