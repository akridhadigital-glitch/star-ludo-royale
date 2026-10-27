import 'dart:math';

import 'package:flutter/material.dart';

import '../core/palette.dart';
import '../engine/engine.dart';

/// A glossy pawn. Hops when [hop] changes; bounces + shows a ring when [movable].
class TokenPiece extends StatefulWidget {
  const TokenPiece({super.key, required this.color, required this.hop, required this.movable, required this.hopMs});
  final LudoColor color;
  final int hop;
  final bool movable;
  final int hopMs;

  @override
  State<TokenPiece> createState() => _TokenPieceState();
}

class _TokenPieceState extends State<TokenPiece> with TickerProviderStateMixin {
  late final AnimationController _hop = AnimationController(vsync: this, duration: Duration(milliseconds: widget.hopMs));
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    if (widget.movable) _pulse.repeat();
  }

  @override
  void didUpdateWidget(TokenPiece old) {
    super.didUpdateWidget(old);
    if (widget.hop != old.hop) {
      _hop.duration = Duration(milliseconds: widget.hopMs);
      _hop.forward(from: 0);
    }
    if (widget.movable && !_pulse.isAnimating) _pulse.repeat();
    if (!widget.movable && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _hop.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Palette.player[widget.color]!;
    return LayoutBuilder(builder: (context, box) {
      final s = box.maxWidth;
      return AnimatedBuilder(
        animation: Listenable.merge([_hop, _pulse]),
        builder: (context, _) {
          final h = _hop.isAnimating ? sin(_hop.value * pi) : 0.0;
          final p = widget.movable ? (sin(_pulse.value * 2 * pi) * 0.5 + 0.5) : 0.0;
          final lift = -(h * 0.42 + p * 0.16) * s;
          final scale = 1 + h * 0.14 + p * 0.1;
          return Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            if (widget.movable)
              Opacity(
                opacity: (1 - _pulse.value).clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 0.8 + _pulse.value * 0.7,
                  child: Container(
                    width: s * 0.86,
                    height: s * 0.86,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFFDE047), width: 2),
                      boxShadow: const [BoxShadow(color: Color(0xCCFACC15), blurRadius: 10, spreadRadius: 1)],
                    ),
                  ),
                ),
              ),
            Transform.translate(
              offset: Offset(0, lift),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: s * 0.78,
                  height: s * 0.78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: max(1.5, s * 0.07)),
                    gradient: RadialGradient(
                      center: const Alignment(-0.35, -0.4),
                      colors: [Color.lerp(base, Colors.white, 0.35)!, base, Palette.playerDark[widget.color]!],
                      stops: const [0, 0.55, 1],
                    ),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 4, offset: Offset(0, 2 + h * 4))],
                  ),
                  alignment: Alignment.center,
                  child: Container(
                    width: s * 0.3,
                    height: s * 0.3,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [Colors.white, Color(0x99FFFFFF), Color(0x33FFFFFF)]),
                    ),
                  ),
                ),
              ),
            ),
          ]);
        },
      );
    });
  }
}

/// 3D-ish dice. Tumbles while [rolling]; glows in [glow] colour when it's your turn to roll.
class DiceView extends StatefulWidget {
  const DiceView({super.key, required this.value, required this.rolling, this.glow, this.size = 46, this.onTap});
  final int value;
  final bool rolling;
  final Color? glow;
  final double size;
  final VoidCallback? onTap;

  @override
  State<DiceView> createState() => _DiceViewState();
}

class _DiceViewState extends State<DiceView> with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late final AnimationController _glow = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(DiceView old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.rolling && !_spin.isAnimating) _spin.repeat();
    if (!widget.rolling && _spin.isAnimating) _spin.animateTo(1, duration: const Duration(milliseconds: 120)).then((_) {
      if (mounted) _spin.value = 0;
    });
    if (widget.glow != null && !_glow.isAnimating) _glow.repeat(reverse: true);
    if (widget.glow == null && _glow.isAnimating) _glow.stop();
  }

  @override
  void dispose() {
    _spin.dispose();
    _glow.dispose();
    super.dispose();
  }

  static const _pips = {
    1: [4],
    2: [2, 6],
    3: [2, 4, 6],
    4: [0, 2, 6, 8],
    5: [0, 2, 4, 6, 8],
    6: [0, 2, 3, 5, 6, 8],
  };

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final on = _pips[widget.value] ?? const [4];
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: Listenable.merge([_spin, _glow]),
        builder: (context, _) {
          final t = _spin.value;
          return Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            if (widget.glow != null)
              Container(
                width: s + 14,
                height: s + 14,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(s * 0.36),
                  border: Border.all(color: widget.glow!.withValues(alpha: 0.3 + 0.7 * _glow.value), width: 3),
                  boxShadow: [BoxShadow(color: widget.glow!.withValues(alpha: 0.6 * _glow.value), blurRadius: 14)],
                ),
              ),
            Transform.translate(
              offset: Offset(0, widget.rolling ? -sin(t * pi) * s * 0.25 : 0),
              child: Transform.rotate(
                angle: t * 2 * pi,
                child: Container(
                  width: s,
                  height: s,
                  padding: EdgeInsets.all(s * 0.12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(s * 0.24),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.white, Color(0xFFF1F5F9), Color(0xFFCBD5E1)],
                    ),
                    boxShadow: const [
                      BoxShadow(color: Color(0xFF94A3B8), offset: Offset(0, 4)),
                      BoxShadow(color: Color(0x73000000), offset: Offset(0, 8), blurRadius: 12),
                    ],
                  ),
                  child: GridView.count(
                    crossAxisCount: 3,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    children: [
                      for (var i = 0; i < 9; i++)
                        Center(
                          child: on.contains(i)
                              ? Container(
                                  width: s * (widget.value == 1 ? 0.26 : 0.16),
                                  height: s * (widget.value == 1 ? 0.26 : 0.16),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      center: const Alignment(-0.3, -0.3),
                                      colors: widget.value == 1
                                          ? const [Color(0xFFFB7185), Color(0xFFE11D48), Color(0xFF9F1239)]
                                          : const [Color(0xFF475569), Color(0xFF0F172A)],
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

/// Avatar with an optional countdown ring.
class TimerRing extends StatefulWidget {
  const TimerRing({super.key, required this.deadline, required this.child, required this.size, this.totalSeconds = 15});
  final DateTime? deadline;
  final Widget child;
  final double size;
  final int totalSeconds;

  @override
  State<TimerRing> createState() => _TimerRingState();
}

class _TimerRingState extends State<TimerRing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        double? frac;
        final d = widget.deadline;
        if (d != null) {
          final left = d.difference(DateTime.now()).inMilliseconds / 1000;
          frac = (left / widget.totalSeconds).clamp(0.0, 1.0);
        }
        return CustomPaint(
          foregroundPainter: frac == null ? null : _RingPainter(frac),
          child: SizedBox(width: widget.size, height: widget.size, child: child),
        );
      },
      child: widget.child,
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.frac);
  final double frac;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).inflate(4);
    final color = frac > 0.5
        ? Color.lerp(const Color(0xFFFACC15), const Color(0xFF4ADE80), (frac - 0.5) * 2)!
        : Color.lerp(const Color(0xFFEF4444), const Color(0xFFFACC15), frac * 2)!;
    canvas.drawArc(
        rect,
        -pi / 2,
        2 * pi * frac,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round
          ..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.frac != frac;
}
