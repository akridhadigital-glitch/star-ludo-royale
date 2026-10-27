import 'dart:math';

import 'package:flutter/material.dart';

import '../core/palette.dart';
import '../engine/engine.dart';

/// Board geometry in "cell units" (15 × 15 grid, origin top-left).
class BoardGeometry {
  static final List<Point<int>> mainPath = _buildPath();

  static List<Point<int>> _buildPath() {
    final p = <Point<int>>[];
    // (row, col) pairs, clockwise from red's start square. Mirrors the original web game.
    for (var c = 1; c <= 5; c++) {
      p.add(Point(6, c));
    }
    for (var r = 5; r >= 0; r--) {
      p.add(Point(r, 6));
    }
    p.add(const Point(0, 7));
    for (var r = 0; r <= 5; r++) {
      p.add(Point(r, 8));
    }
    for (var c = 9; c <= 14; c++) {
      p.add(Point(6, c));
    }
    p.add(const Point(7, 14));
    for (var c = 14; c >= 9; c--) {
      p.add(Point(8, c));
    }
    for (var r = 9; r <= 14; r++) {
      p.add(Point(r, 8));
    }
    p.add(const Point(14, 7));
    for (var r = 14; r >= 9; r--) {
      p.add(Point(r, 6));
    }
    for (var c = 5; c >= 0; c--) {
      p.add(Point(8, c));
    }
    p.add(const Point(7, 0));
    p.add(const Point(6, 0));
    return p; // Point(x: row, y: col)
  }

  static const Map<LudoColor, List<Point<int>>> homeRun = {
    LudoColor.red: [Point(7, 1), Point(7, 2), Point(7, 3), Point(7, 4), Point(7, 5)],
    LudoColor.green: [Point(1, 7), Point(2, 7), Point(3, 7), Point(4, 7), Point(5, 7)],
    LudoColor.yellow: [Point(7, 13), Point(7, 12), Point(7, 11), Point(7, 10), Point(7, 9)],
    LudoColor.blue: [Point(13, 7), Point(12, 7), Point(11, 7), Point(10, 7), Point(9, 7)],
  };

  /// Yard origin (row, col) of each 6×6 corner.
  static const Map<LudoColor, Point<int>> yardOrigin = {
    LudoColor.red: Point(0, 0),
    LudoColor.green: Point(0, 9),
    LudoColor.yellow: Point(9, 9),
    LudoColor.blue: Point(9, 0),
  };

  /// Where finished tokens rest: inside the colour's centre triangle (fractional cells).
  static const Map<LudoColor, Offset> finishSpot = {
    LudoColor.red: Offset(6.25, 7), // (col, row) as x, y
    LudoColor.green: Offset(7, 6.25),
    LudoColor.yellow: Offset(7.75, 7),
    LudoColor.blue: Offset(7, 7.75),
  };

  /// Top-left (x = col, y = row) of the cell a token occupies, in cell units.
  static Offset tokenCell(LudoColor color, int step, int tokenId) {
    if (step == kYard) {
      final o = yardOrigin[color]!;
      final dr = tokenId ~/ 2, dc = tokenId % 2;
      return Offset(o.y + 1.5 + dc * 2.0, o.x + 1.5 + dr * 2.0);
    }
    if (step <= kLastTrackStep) {
      final p = mainPath[trackIndex(color, step)];
      return Offset(p.y.toDouble(), p.x.toDouble());
    }
    if (step < kFinishStep) {
      final p = homeRun[color]![step - 51];
      return Offset(p.y.toDouble(), p.x.toDouble());
    }
    final f = finishSpot[color]!;
    return Offset(f.dx, f.dy);
  }
}

/// Paints the static board once (it never changes during a game).
class BoardPainter extends CustomPainter {
  const BoardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 15;
    Rect cell(num col, num row, [num w = 1, num h = 1]) => Rect.fromLTWH(col * u, row * u, w * u, h * u);
    final fill = Paint()..style = PaintingStyle.fill;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(0.6, u * 0.03)
      ..color = const Color(0xFFCBD5E1);

    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(u * 0.5)), fill..color = Colors.white);

    // Track + home-run cells
    for (final p in BoardGeometry.mainPath) {
      canvas.drawRect(cell(p.y, p.x), line);
    }
    BoardGeometry.homeRun.forEach((color, cells) {
      for (final p in cells) {
        canvas.drawRect(cell(p.y, p.x), fill..color = Palette.player[color]!);
        canvas.drawRect(cell(p.y, p.x), line);
      }
    });
    // Start squares in player colour
    for (final c in kOrder) {
      final p = BoardGeometry.mainPath[kStartIndex[c]!];
      canvas.drawRect(cell(p.y, p.x), fill..color = Palette.player[c]!);
      canvas.drawRect(cell(p.y, p.x), line);
    }
    // Safe stars
    for (final i in kSafeIndices) {
      final p = BoardGeometry.mainPath[i];
      final isStart = kStartIndex.values.contains(i);
      _star(canvas, cell(p.y, p.x).center, u * 0.34, isStart ? Colors.white : const Color(0xFFEAB308),
          isStart ? Colors.white.withValues(alpha: 0.0) : const Color(0xFFA16207));
    }

    // Yards
    for (final c in kOrder) {
      final o = BoardGeometry.yardOrigin[c]!;
      final outer = cell(o.y, o.x, 6, 6);
      final shade = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Palette.player[c]!, Palette.playerDark[c]!],
        ).createShader(outer);
      canvas.drawRRect(RRect.fromRectAndRadius(outer.deflate(u * 0.08), Radius.circular(u * 0.6)), shade);
      final inner = cell(o.y + 1, o.x + 1, 4, 4);
      canvas.drawRRect(RRect.fromRectAndRadius(inner, Radius.circular(u * 0.6)), fill..color = Colors.white);
      for (var t = 0; t < 4; t++) {
        final pos = BoardGeometry.tokenCell(c, kYard, t);
        final center = Offset((pos.dx + 0.5) * u, (pos.dy + 0.5) * u);
        canvas.drawCircle(center, u * 0.62, fill..color = Palette.playerLight[c]!);
        canvas.drawCircle(
            center,
            u * 0.62,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = u * 0.08
              ..color = Palette.player[c]!.withValues(alpha: 0.55));
      }
    }

    // Centre triangles
    final c0 = Offset(6 * u, 6 * u), c1 = Offset(9 * u, 6 * u), c2 = Offset(9 * u, 9 * u), c3 = Offset(6 * u, 9 * u);
    final mid = Offset(7.5 * u, 7.5 * u);
    void tri(Offset a, Offset b, Color col) {
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..lineTo(mid.dx, mid.dy)
        ..close();
      canvas.drawPath(path, fill..color = col);
    }

    tri(c0, c1, Palette.player[LudoColor.green]!);
    tri(c1, c2, Palette.player[LudoColor.yellow]!);
    tri(c2, c3, Palette.player[LudoColor.blue]!);
    tri(c3, c0, Palette.player[LudoColor.red]!);
    _star(canvas, mid, u * 0.55, Colors.white, const Color(0x33000000));

    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(u * 0.5)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = u * 0.12
          ..color = const Color(0xFF0F172A));
  }

  static void _star(Canvas canvas, Offset c, double r, Color color, Color stroke) {
    final path = Path();
    for (var k = 0; k < 10; k++) {
      final a = -pi / 2 + k * pi / 5;
      final rr = k.isEven ? r : r * 0.45;
      final p = Offset(c.dx + rr * cos(a), c.dy + rr * sin(a));
      k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.12
          ..strokeJoin = StrokeJoin.round
          ..color = stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
