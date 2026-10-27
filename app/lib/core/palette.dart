import 'package:flutter/material.dart';
import '../engine/engine.dart';

class Palette {
  static const bg1 = Color(0xFF1E3A8A);
  static const bg2 = Color(0xFF0F172A);
  static const bg3 = Color(0xFF020617);
  static const panel = Color(0xFF0F172A);
  static const panel2 = Color(0xFF1E293B);
  static const line = Color(0xFF334155);
  static const muted = Color(0xFF94A3B8);
  static const gold1 = Color(0xFFFEF08A);
  static const gold2 = Color(0xFFFACC15);
  static const gold3 = Color(0xFFCA8A04);
  static const gold4 = Color(0xFF854D0E);
  static const emerald = Color(0xFF6EE7B7);

  static const Map<LudoColor, Color> player = {
    LudoColor.red: Color(0xFFE11D48),
    LudoColor.green: Color(0xFF16A34A),
    LudoColor.yellow: Color(0xFFEAB308),
    LudoColor.blue: Color(0xFF2563EB),
  };
  static const Map<LudoColor, Color> playerLight = {
    LudoColor.red: Color(0xFFFFE4E6),
    LudoColor.green: Color(0xFFDCFCE7),
    LudoColor.yellow: Color(0xFFFEF9C3),
    LudoColor.blue: Color(0xFFDBEAFE),
  };
  static const Map<LudoColor, Color> playerDark = {
    LudoColor.red: Color(0xFFBE123C),
    LudoColor.green: Color(0xFF15803D),
    LudoColor.yellow: Color(0xFFCA8A04),
    LudoColor.blue: Color(0xFF1D4ED8),
  };

  static const goldGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFEF9C3), gold2, gold3, gold4],
    stops: [0, 0.38, 0.72, 1],
  );

  static const background = RadialGradient(
    center: Alignment(0, -0.55),
    radius: 1.2,
    colors: [bg1, bg2, bg3],
    stops: [0, 0.58, 1],
  );
}

const Map<LudoColor, String> kColorLabel = {
  LudoColor.red: 'Red',
  LudoColor.green: 'Green',
  LudoColor.yellow: 'Yellow',
  LudoColor.blue: 'Blue',
};

/// Simple, original emoji avatars (index stored on the server as 0..11).
const List<String> kAvatars = ['👑', '🦁', '🐯', '🦊', '🐼', '🐸', '🦄', '🐲', '🚀', '⚡', '🔥', '🌟'];
