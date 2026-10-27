import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import 'storage.dart';

enum Sfx { roll, step, six, capture, home, turn, click, win, lose }

/// Low-latency sound effects with a small player pool so rapid steps can overlap.
class Sound {
  Sound._();
  static final instance = Sound._();

  final List<AudioPlayer> _pool = [];
  int _next = 0;
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    try {
      for (var i = 0; i < 5; i++) {
        final p = AudioPlayer();
        await p.setPlayerMode(PlayerMode.lowLatency);
        await p.setReleaseMode(ReleaseMode.stop);
        _pool.add(p);
      }
      _ready = true;
    } catch (_) {
      // Audio is a nice-to-have; never let it break the game.
    }
  }

  void play(Sfx s) {
    if (!_ready || !Storage.instance.soundOn) return;
    final p = _pool[_next];
    _next = (_next + 1) % _pool.length;
    p.play(AssetSource('sfx/${s.name}.wav'), volume: s == Sfx.step ? 0.6 : 1.0).catchError((_) {});
  }

  static void haptic([HapticKind kind = HapticKind.light]) {
    if (!Storage.instance.hapticsOn) return;
    switch (kind) {
      case HapticKind.light:
        HapticFeedback.lightImpact();
      case HapticKind.medium:
        HapticFeedback.mediumImpact();
      case HapticKind.heavy:
        HapticFeedback.heavyImpact();
    }
  }
}

enum HapticKind { light, medium, heavy }
