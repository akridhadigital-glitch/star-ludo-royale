import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../core/online.dart';
import '../core/palette.dart';
import '../core/sound.dart';
import '../core/storage.dart';
import '../engine/engine.dart';
import '../widgets/common.dart';
import 'board.dart';
import 'match_controller.dart';
import 'pieces.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.controller});
  final MatchController controller;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  MatchController get c => widget.controller;
  StreamSubscription<BoardToast>? _toastSub;
  StreamSubscription<(LudoColor, String)>? _chatSub;
  BoardToast? _toast;
  int _toastId = 0;
  final Map<LudoColor, (String, int)> _bubbles = {};
  bool _resultShown = false;

  @override
  void initState() {
    super.initState();
    _toastSub = c.toasts.listen((t) {
      setState(() {
        _toast = t;
        _toastId++;
      });
    });
    final ctl = c;
    if (ctl is OnlineMatchController) {
      _chatSub = ctl.chatBubbles.listen((m) {
        final id = DateTime.now().microsecondsSinceEpoch;
        setState(() => _bubbles[m.$1] = (m.$2, id));
        Sound.instance.play(Sfx.click);
        Future.delayed(const Duration(milliseconds: 2600), () {
          if (mounted && _bubbles[m.$1]?.$2 == id) setState(() => _bubbles.remove(m.$1));
        });
      });
    }
    c.addListener(_onChange);
  }

  void _onChange() {
    if (c.result != null && !_resultShown) {
      _resultShown = true;
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) _showResult();
      });
    }
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    _toastSub?.cancel();
    _chatSub?.cancel();
    c.dispose();
    super.dispose();
  }

  Future<void> _leave() async {
    if (c.result != null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final ok = await confirmDialog(
      context,
      title: 'Leave match?',
      message: c.isOnline
          ? 'Leaving an online match counts as a loss and your opponents keep playing.'
          : 'Your progress is saved. Continue anytime from the home screen.',
      yes: 'Leave',
      no: 'Stay',
    );
    if (!ok || !mounted) return;
    await c.leave();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _showResult() async {
    final r = c.result!;
    final again = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ResultDialog(controller: c, result: r),
    );
    if (!mounted) return;
    if (again == true && c is LocalMatchController) {
      final setup = (c as LocalMatchController).setup;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => GameScreen(controller: LocalMatchController.newMatch(setup))));
    } else {
      Navigator.of(context).pop();
    }
  }

  void _openChat() {
    final ctl = c;
    if (ctl is! OnlineMatchController) return;
    showRoyalSheet(context, builder: (ctx) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Quick chat', textAlign: TextAlign.center, style: TextStyle(color: Palette.gold2, fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
          for (final e in kChatPhrases.entries)
            ActionChip(
              backgroundColor: const Color(0xFF0B1222),
              side: const BorderSide(color: Palette.line),
              label: Text(e.value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              onPressed: () {
                ctl.sendChat(e.key);
                Navigator.pop(ctx);
              },
            ),
        ]),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        body: RoyalBackground(
          child: ListenableBuilder(
            listenable: c,
            builder: (context, _) => LayoutBuilder(builder: (context, box) {
              final boardSize = min(box.maxWidth - 24, box.maxHeight - 250).clamp(240.0, 560.0);
              return Center(
                child: SizedBox(
                  width: boardSize + 8,
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _topBar(),
                    const SizedBox(height: 8),
                    _podRow(LudoColor.red, LudoColor.green),
                    const SizedBox(height: 8),
                    _boardFrame(boardSize),
                    const SizedBox(height: 8),
                    _podRow(LudoColor.blue, LudoColor.yellow),
                    const SizedBox(height: 8),
                    _statusBar(),
                  ]),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Row(children: [
      _iconBtn('←', _leave),
      const Expanded(child: Center(child: GoldTitle('STAR LUDO ROYALE', size: 16))),
      if (c.isOnline) ...[_iconBtn('💬', _openChat), const SizedBox(width: 6)],
      _iconBtn(Storage.instance.soundOn ? '🔊' : '🔇', () => setState(() => Storage.instance.soundOn = !Storage.instance.soundOn)),
    ]);
  }

  Widget _iconBtn(String icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Palette.panel.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(14), border: Border.all(color: Palette.line)),
          child: Text(icon, style: const TextStyle(fontSize: 18, color: Colors.white)),
        ),
      );

  Widget _podRow(LudoColor left, LudoColor right) => Row(children: [
        Expanded(child: _pod(left, false)),
        const SizedBox(width: 8),
        Expanded(child: _pod(right, true)),
      ]);

  Widget _pod(LudoColor color, bool mirrored) {
    final playing = c.state.players.contains(color);
    if (!playing) return const SizedBox(height: 60);
    final seat = c.seatOf(color);
    final active = c.state.current == color && c.result == null;
    final pc = Palette.player[color]!;
    final finished = c.shown[color]!.where((s) => s == kFinishStep).length;
    final status = seat.left
        ? 'Left'
        : !seat.connected && c.isOnline
            ? 'Reconnecting…'
            : seat.away
                ? '⏰ Missed turn'
                : '🏠 $finished/4';
    final avatar = TimerRing(
      size: 42,
      deadline: active ? c.deadline : null,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(center: const Alignment(-0.3, -0.4), colors: [Color.lerp(pc, Colors.white, 0.35)!, pc]),
          border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 2),
        ),
        alignment: Alignment.center,
        child: Text(seat.isBot ? '🤖' : kAvatars[seat.avatar % kAvatars.length], style: const TextStyle(fontSize: 20)),
      ),
    );
    final info = Expanded(
      child: Column(crossAxisAlignment: mirrored ? CrossAxisAlignment.end : CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: mirrored ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(seat.name, maxLines: 1, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
        ),
        Text(seat.kind == SeatKind.me && c.isOnline ? 'You · $status' : status,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Palette.muted, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
    final dice = SizedBox(
      width: 52,
      height: 52,
      child: active
          ? Center(
              child: DiceView(
                value: c.shownDice,
                rolling: c.rolling,
                size: 44,
                glow: c.canRoll ? pc : null,
                onTap: c.canRoll ? c.roll : null,
              ),
            )
          : null,
    );
    final children = <Widget>[avatar, const SizedBox(width: 8), info, const SizedBox(width: 4), dice];
    final bubble = _bubbles[color];
    return GestureDetector(
      onTap: active && c.canRoll ? c.roll : null,
      child: Stack(clipBehavior: Clip.none, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Palette.panel2, Palette.panel]),
            border: Border.all(color: active ? pc : Palette.line, width: 2),
            boxShadow: active ? [BoxShadow(color: pc.withValues(alpha: 0.55), blurRadius: 18, spreadRadius: -2)] : const [],
          ),
          child: Opacity(
            opacity: active || seat.left ? (seat.left ? 0.45 : 1) : 0.75,
            child: Row(children: mirrored ? children.reversed.toList() : children),
          ),
        ),
        if (bubble != null)
          Positioned(
            top: -30,
            left: mirrored ? null : 8,
            right: mirrored ? 8 : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)]),
              child: Text(bubble.$1, style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w800, fontSize: 12)),
            ),
          ),
      ]),
    );
  }

  Widget _boardFrame(double size) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Palette.gold3, Palette.gold4, Palette.gold3]),
        border: Border.all(color: Palette.gold2, width: 4),
        boxShadow: const [BoxShadow(color: Color(0xE6000000), blurRadius: 30, offset: Offset(0, 16), spreadRadius: -8)],
      ),
      child: SizedBox(width: size - 18, height: size - 18, child: _board(size - 18)),
    );
  }

  Widget _board(double size) {
    final u = size / 15;
    final movable = c.movable.toSet();
    final current = c.state.current;

    // Group tokens by square so stacks spread out instead of hiding each other.
    final groups = <String, List<(LudoColor, int)>>{};
    for (final color in c.state.players) {
      final steps = c.shown[color]!;
      for (var t = 0; t < 4; t++) {
        final p = BoardGeometry.tokenCell(color, steps[t], t);
        groups.putIfAbsent('${p.dx.toStringAsFixed(2)},${p.dy.toStringAsFixed(2)}', () => []).add((color, t));
      }
    }
    const stack = {
      1: [(0.0, 0.0, 1.0)],
      2: [(-0.2, 0.0, 0.8), (0.2, 0.0, 0.8)],
      3: [(-0.2, -0.18, 0.68), (0.2, -0.18, 0.68), (0.0, 0.2, 0.68)],
      4: [(-0.22, -0.22, 0.62), (0.22, -0.22, 0.62), (-0.22, 0.22, 0.62), (0.22, 0.22, 0.62)],
    };
    final pieces = <(Widget, int)>[];
    for (final g in groups.values) {
      final pat = stack[min(g.length, 4)]!;
      for (var i = 0; i < g.length; i++) {
        final (color, t) = g[i];
        final key = '${color.name}-$t';
        final base = BoardGeometry.tokenCell(color, c.shown[color]![t], t);
        final (dx, dy, s0) = pat[i % pat.length];
        final scale = g.length > 4 ? 0.55 : s0;
        final isMovable = color == current && movable.contains(t);
        final flying = c.flying.contains(key);
        final hit = u * 1.4; // generous tap target
        final left = (base.dx + dx) * u - (hit - u) / 2;
        final top = (base.dy + dy) * u - (hit - u) / 2;
        final z = isMovable ? 3 : (color == current ? 2 : 1);
        pieces.add((
          AnimatedPositioned(
            key: ValueKey(key),
            duration: Duration(milliseconds: flying ? 480 : c.stepMs),
            curve: flying ? Curves.easeInOutCubic : Curves.easeOutCubic,
            left: left,
            top: top,
            width: hit,
            height: hit,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: isMovable ? () => c.move(t) : null,
              child: Center(
                child: SizedBox(
                  width: u * scale,
                  height: u * scale,
                  child: TokenPiece(color: color, hop: c.hops[key] ?? 0, movable: isMovable, hopMs: c.stepMs),
                ),
              ),
            ),
          ),
          z
        ));
      }
    }
    pieces.sort((a, b) => a.$2.compareTo(b.$2));

    final yard = BoardGeometry.yardOrigin[current]!;
    return Stack(clipBehavior: Clip.none, children: [
      const Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: BoardPainter()))),
      Positioned(
        left: yard.y * u,
        top: yard.x * u,
        width: 6 * u,
        height: 6 * u,
        child: IgnorePointer(child: _YardGlow(color: Palette.player[current]!, active: c.result == null)),
      ),
      ...pieces.map((p) => p.$1),
      if (_toast != null)
        Positioned.fill(
          child: IgnorePointer(
            child: Center(child: _BoardToastView(key: ValueKey(_toastId), toast: _toast!)),
          ),
        ),
    ]);
  }

  Widget _statusBar() {
    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Palette.panel.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Palette.gold2.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (c.isOnline && !OnlineService.instance.connected)
              const Text('📡 Reconnecting… your turn is kept', style: TextStyle(color: Color(0xFFFCA5A5), fontWeight: FontWeight.w700, fontSize: 13)),
            Text(c.hint, style: const TextStyle(color: Palette.gold1, fontWeight: FontWeight.w700, fontSize: 15)),
            if (c.bonusText.isNotEmpty)
              Text(c.bonusText, style: const TextStyle(color: Palette.emerald, fontWeight: FontWeight.w600, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }
}

class _YardGlow extends StatefulWidget {
  const _YardGlow({required this.color, required this.active});
  final Color color;
  final bool active;
  @override
  State<_YardGlow> createState() => _YardGlowState();
}

class _YardGlowState extends State<_YardGlow> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    return FadeTransition(
      opacity: Tween(begin: 0.3, end: 1.0).animate(_a),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: widget.color, width: 3),
          boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.6), blurRadius: 16)],
        ),
      ),
    );
  }
}

class _BoardToastView extends StatefulWidget {
  const _BoardToastView({super.key, required this.toast});
  final BoardToast toast;
  @override
  State<_BoardToastView> createState() => _BoardToastViewState();
}

class _BoardToastViewState extends State<_BoardToastView> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();
  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.toast.color == null ? const Color(0xFFF59E0B) : Palette.player[widget.toast.color]!;
    return AnimatedBuilder(
      animation: _a,
      builder: (context, child) {
        final t = _a.value;
        final scale = t < 0.18 ? 0.5 + (t / 0.18) * 0.6 : (t < 0.3 ? 1.1 - ((t - 0.18) / 0.12) * 0.1 : 1.0);
        final opacity = t < 0.15 ? t / 0.15 : (t > 0.78 ? (1 - (t - 0.78) / 0.22) : 1.0);
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, t > 0.78 ? -(t - 0.78) * 60 : 0), child: Transform.scale(scale: scale, child: child)),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 10))],
        ),
        child: Text(widget.toast.text, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
      ),
    );
  }
}

class _ResultDialog extends StatelessWidget {
  const _ResultDialog({required this.controller, required this.result});
  final MatchController controller;
  final MatchResult result;

  @override
  Widget build(BuildContext context) {
    final medals = ['🥇', '🥈', '🥉', '🎖'];
    final winnerSeat = controller.seatOf(result.winner);
    final title = result.reason == 'removed'
        ? 'Removed from match'
        : result.hasMe
            ? (result.iWon ? 'You Win!' : '${winnerSeat.name} Wins!')
            : '${winnerSeat.name} Wins!';
    final reward = result.reward;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Palette.panel2, Palette.panel]),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Palette.gold2, width: 2),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(result.hasMe && !result.iWon ? '🎲' : '👑', textAlign: TextAlign.center, style: const TextStyle(fontSize: 54)),
          GoldTitle(title, size: 24),
          if (result.reason == 'removed')
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('You missed 3 turns in a row, so the game continued without you.',
                  textAlign: TextAlign.center, style: TextStyle(color: Palette.muted)),
            ),
          if (result.reason == 'opponents_left')
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Your opponents left the match.', textAlign: TextAlign.center, style: TextStyle(color: Palette.muted)),
            ),
          const SizedBox(height: 12),
          for (var i = 0; i < result.ranking.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: i == 0 ? Palette.gold2.withValues(alpha: 0.12) : const Color(0xFF0B1222),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: i == 0 ? Palette.gold2 : Palette.line),
              ),
              child: Row(children: [
                SizedBox(width: 30, child: Text(medals[i], style: const TextStyle(fontSize: 22))),
                Container(width: 16, height: 16, decoration: BoxDecoration(color: Palette.player[result.ranking[i]], shape: BoxShape.circle)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(controller.seatOf(result.ranking[i]).name,
                      overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
                Text('${controller.state.tokens[result.ranking[i]]!.where((s) => s == kFinishStep).length}/4 home',
                    style: const TextStyle(color: Palette.muted, fontSize: 12)),
              ]),
            ),
          if (reward != null && (reward.$1 > 0 || reward.$2 > 0))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('+${reward.$1} 🪙   +${reward.$2} 💎', textAlign: TextAlign.center, style: const TextStyle(color: Palette.emerald, fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: GhostButton('Home', onPressed: () => Navigator.pop(context, false))),
            if (!controller.isOnline) ...[
              const SizedBox(width: 10),
              Expanded(child: GoldButton('PLAY AGAIN', onPressed: () => Navigator.pop(context, true))),
            ],
          ]),
        ]),
      ),
    );
  }
}
