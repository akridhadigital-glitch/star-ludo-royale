import 'dart:math';

import 'package:flutter/material.dart';

import '../core/palette.dart';
import '../core/session.dart';
import '../core/sound.dart';
import '../widgets/common.dart';
import 'home_screen.dart';

/// Animated logo intro while the app warms up (prefs, audio, Firebase, session refresh).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..forward();

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await Future.wait([
      Session.instance.init().timeout(const Duration(seconds: 4), onTimeout: () {}),
      Sound.instance.init(),
      Future.delayed(const Duration(milliseconds: 2700)),
    ]);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 450),
      pageBuilder: (_, __, ___) => const HomeScreen(),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    ));
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  double _iv(double begin, double end, Curve curve) {
    final t = ((_a.value - begin) / (end - begin)).clamp(0.0, 1.0);
    return curve.transform(t);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RoyalBackground(
        child: Center(
          child: AnimatedBuilder(
            animation: _a,
            builder: (context, _) {
              final badge = _iv(0, 0.27, Curves.elasticOut);
              final quads = [for (var i = 0; i < 4; i++) _iv(0.1 + i * 0.04, 0.27 + i * 0.04, Curves.easeOutBack)];
              final star = _iv(0.27, 0.58, Curves.elasticOut);
              final title = _iv(0.35, 0.58, Curves.easeOut);
              final bar = _iv(0.42, 1.0, Curves.easeInOutCubic);
              return Column(mainAxisSize: MainAxisSize.min, children: [
                Transform.rotate(
                  angle: (1 - badge) * -0.45,
                  child: Transform.scale(
                    scale: 0.2 + 0.8 * badge,
                    child: Opacity(
                      opacity: _iv(0, 0.1, Curves.linear),
                      child: LogoBadge(size: 150, quadScale: quads, starScale: star, starTurn: (1 - star) * -pi),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Opacity(
                  opacity: title,
                  child: Transform.translate(
                    offset: Offset(0, (1 - title) * 14),
                    child: const GoldTitle('STAR LUDO', size: 40, subtitle: 'ROYALE'),
                  ),
                ),
                const SizedBox(height: 26),
                Opacity(
                  opacity: _iv(0.4, 0.5, Curves.linear),
                  child: Container(
                    width: 220,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: Palette.gold2.withValues(alpha: 0.35)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: bar,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [
                                Palette.player.values.elementAt(0),
                                Palette.player.values.elementAt(1),
                                Palette.player.values.elementAt(2),
                                Palette.player.values.elementAt(3),
                              ]),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Opacity(
                  opacity: _iv(0.45, 0.55, Curves.linear),
                  child: const Text('LOADING', style: TextStyle(color: Palette.muted, letterSpacing: 4, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}
