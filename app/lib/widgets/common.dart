import 'dart:math';

import 'package:flutter/material.dart';

import '../core/palette.dart';
import '../core/sound.dart';

/// Original Star Ludo Royale logo: a gold badge with four colour quadrants and a centre star.
class LogoBadge extends StatelessWidget {
  const LogoBadge({super.key, this.size = 120, this.quadScale = const [1, 1, 1, 1], this.starScale = 1, this.starTurn = 0});
  final double size;
  final List<double> quadScale;
  final double starScale;
  final double starTurn;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _LogoPainter(quadScale, starScale, starTurn));
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.q, this.star, this.turn);
  final List<double> q;
  final double star;
  final double turn;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 120;
    canvas.scale(k);
    final rim = RRect.fromRectAndRadius(const Rect.fromLTWH(3, 3, 114, 114), const Radius.circular(28));
    canvas.drawShadow(Path()..addRRect(rim), Colors.black, 10, false);
    canvas.drawRRect(rim, Paint()..shader = Palette.goldGradient.createShader(rim.outerRect));
    canvas.drawRRect(
        rim,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0xFF713F12));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(11, 11, 98, 98), const Radius.circular(21)), Paint()..color = Palette.panel);

    const quads = [
      (Offset(15, 15), Color(0xFFE11D48)),
      (Offset(62, 15), Color(0xFF16A34A)),
      (Offset(15, 62), Color(0xFF2563EB)),
      (Offset(62, 62), Color(0xFFEAB308)),
    ];
    for (var i = 0; i < 4; i++) {
      final (o, col) = quads[i];
      final s = q[i].clamp(0.0, 1.3);
      if (s <= 0) continue;
      canvas.save();
      canvas.translate(o.dx + 21.5, o.dy + 21.5);
      canvas.scale(s);
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-21.5, -21.5, 43, 43), const Radius.circular(14)), Paint()..color = col);
      canvas.drawCircle(Offset.zero, 9, Paint()..color = Colors.white.withValues(alpha: 0.92));
      canvas.restore();
    }

    if (star > 0) {
      canvas.save();
      canvas.translate(60, 60);
      canvas.rotate(turn);
      canvas.scale(star);
      canvas.drawCircle(Offset.zero, 21, Paint()..color = Colors.white);
      canvas.drawCircle(
          Offset.zero,
          21,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = Palette.gold3);
      final path = Path();
      for (var i = 0; i < 10; i++) {
        final a = -pi / 2 + i * pi / 5;
        final r = i.isEven ? 17.0 : 7.2;
        final p = Offset(r * cos(a), r * sin(a));
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..shader = Palette.goldGradient.createShader(const Rect.fromLTWH(-17, -17, 34, 34)));
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0xFFA16207));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.star != star || old.turn != turn || old.q != q;
}

/// Gold embossed title text.
class GoldTitle extends StatelessWidget {
  const GoldTitle(this.text, {super.key, this.size = 34, this.subtitle});
  final String text;
  final double size;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: size, fontWeight: FontWeight.w900, letterSpacing: size * 0.08, height: 1.05, color: Colors.white);
    return ShaderMask(
      shaderCallback: (r) => Palette.goldGradient.createShader(r),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(text, textAlign: TextAlign.center, style: style.copyWith(shadows: const [Shadow(color: Colors.black54, offset: Offset(0, 3), blurRadius: 3)])),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(subtitle!, style: style.copyWith(fontSize: size * 0.4, letterSpacing: size * 0.22)),
          ),
      ]),
    );
  }
}

/// Royal gradient background used on every screen.
class RoyalBackground extends StatelessWidget {
  const RoyalBackground({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(gradient: Palette.background),
        child: SafeArea(child: child),
      );
}

/// Chunky 3D menu button (pressed state sinks).
class BigButton extends StatefulWidget {
  const BigButton({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.colors,
    required this.onTap,
    this.badge,
    this.dark = false,
  });
  final String icon;
  final String title;
  final String? subtitle;
  final List<Color> colors; // top, bottom, shadow
  final VoidCallback onTap;
  final String? badge;
  final bool dark;

  @override
  State<BigButton> createState() => _BigButtonState();
}

class _BigButtonState extends State<BigButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final fg = widget.dark ? const Color(0xFF1C1002) : Colors.white;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        Sound.instance.play(Sfx.click);
        Sound.haptic();
        widget.onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        transform: Matrix4.translationValues(0, _down ? 4 : 0, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [widget.colors[0], widget.colors[1]]),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 2),
          boxShadow: [
            BoxShadow(color: widget.colors[2], offset: Offset(0, _down ? 2 : 6)),
            const BoxShadow(color: Color(0x73000000), offset: Offset(0, 12), blurRadius: 20),
          ],
        ),
        child: Stack(clipBehavior: Clip.none, children: [
          Row(children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(16)),
              child: Text(widget.icon, style: const TextStyle(fontSize: 28)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.title, style: TextStyle(color: fg, fontSize: 20, fontWeight: FontWeight.w800)),
                if (widget.subtitle != null)
                  Text(widget.subtitle!, style: TextStyle(color: fg.withValues(alpha: 0.9), fontSize: 13, fontWeight: FontWeight.w500)),
              ]),
            ),
          ]),
          if (widget.badge != null)
            Positioned(
              right: 0,
              top: -24,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFF43F5E), borderRadius: BorderRadius.circular(99), border: Border.all(color: Colors.white, width: 2)),
                child: Text(widget.badge!, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Gold call-to-action button.
class GoldButton extends StatelessWidget {
  const GoldButton(this.label, {super.key, required this.onPressed, this.busy = false});
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GestureDetector(
        onTap: enabled
            ? () {
                Sound.instance.play(Sfx.click);
                Sound.haptic();
                onPressed!();
              }
            : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 15),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFDE047), Color(0xFFF59E0B)]),
            border: Border.all(color: Palette.gold1, width: 2),
            boxShadow: const [BoxShadow(color: Color(0xFFB45309), offset: Offset(0, 5)), BoxShadow(color: Color(0x66000000), offset: Offset(0, 10), blurRadius: 18)],
          ),
          child: busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF1C1002)))
              : Text(label, style: const TextStyle(color: Color(0xFF1C1002), fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
        ),
      ),
    );
  }
}

class GhostButton extends StatelessWidget {
  const GhostButton(this.label, {super.key, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Palette.line, width: 2),
          backgroundColor: const Color(0xFF0B1222),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        onPressed: onPressed,
        child: Text(label),
      );
}

/// Bottom sheet in the game's style.
Future<T?> showRoyalSheet<T>(BuildContext context, {required WidgetBuilder builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.9),
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Palette.panel2, Palette.panel]),
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          border: Border(top: BorderSide(color: Palette.gold2, width: 2)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: Container(width: 44, height: 5, margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: const Color(0xFF475569), borderRadius: BorderRadius.circular(9)))),
              builder(ctx),
            ]),
          ),
        ),
      ),
    ),
  );
}

Future<bool> confirmDialog(BuildContext context, {required String title, required String message, String yes = 'Yes', String no = 'Cancel'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Palette.panel2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: Palette.gold2, width: 2)),
      title: Text(title, style: const TextStyle(color: Palette.gold2, fontWeight: FontWeight.w900)),
      content: Text(message, style: const TextStyle(color: Color(0xFFCBD5E1))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(no, style: const TextStyle(color: Colors.white70))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Palette.gold2, foregroundColor: const Color(0xFF1C1002)),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(yes, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );
  return r ?? false;
}

void showSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      behavior: SnackBarBehavior.floating,
      backgroundColor: Palette.panel2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Palette.gold2)),
    ));
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Text(text.toUpperCase(), style: const TextStyle(color: Palette.muted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
      );
}
