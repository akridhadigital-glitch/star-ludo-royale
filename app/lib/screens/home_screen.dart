import 'package:flutter/material.dart';

import '../core/palette.dart';
import '../core/session.dart';
import '../core/storage.dart';
import '../engine/engine.dart';
import '../game/game_screen.dart';
import '../game/match_controller.dart';
import '../widgets/common.dart';
import 'leaderboard_screen.dart';
import 'legal_screen.dart';
import 'online_screens.dart';
import 'profile_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _float = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _firstLaunch());
  }

  Future<void> _firstLaunch() async {
    if (Storage.instance.acceptedTerms || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.panel2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: Palette.gold2, width: 2)),
        title: const Text('Welcome to Star Ludo Royale', style: TextStyle(color: Palette.gold2, fontWeight: FontWeight.w900)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('A free game for fun. No real money, no betting, no prizes. Coins and gems have no cash value.',
              style: TextStyle(color: Color(0xFFCBD5E1))),
          const SizedBox(height: 10),
          Wrap(children: [
            const Text('By playing you agree to the ', style: TextStyle(color: Color(0xFFCBD5E1))),
            GestureDetector(
              onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const LegalScreen(initialTab: 1))),
              child: const Text('Terms', style: TextStyle(color: Palette.gold1, decoration: TextDecoration.underline)),
            ),
            const Text(' and ', style: TextStyle(color: Color(0xFFCBD5E1))),
            GestureDetector(
              onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const LegalScreen(initialTab: 0))),
              child: const Text('Privacy Policy', style: TextStyle(color: Palette.gold1, decoration: TextDecoration.underline)),
            ),
            const Text('.', style: TextStyle(color: Color(0xFFCBD5E1))),
          ]),
        ]),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Palette.gold2, foregroundColor: const Color(0xFF1C1002)),
            onPressed: () {
              Storage.instance.acceptedTerms = true;
              Navigator.pop(ctx);
            },
            child: const Text('Let\'s play', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  Future<void> _openGame(MatchController c) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameScreen(controller: c)));
    if (mounted) setState(() {});
  }

  void _openSetup({required bool vsComputer}) {
    showRoyalSheet<MatchSetup>(context, builder: (_) => _SetupSheet(vsComputer: vsComputer)).then((setup) {
      if (setup != null && mounted) _openGame(LocalMatchController.newMatch(setup));
    });
  }

  @override
  Widget build(BuildContext context) {
    final saved = LocalMatchController.savedDescription();
    return Scaffold(
      body: RoyalBackground(
        child: ListenableBuilder(
          listenable: Session.instance,
          builder: (context, _) {
            final s = Session.instance;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), children: [
                  Row(children: [
                    GestureDetector(
                      onTap: () => showRoyalSheet(context, builder: (_) => const ProfileSheet()),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
                        decoration: BoxDecoration(color: Palette.panel.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(99), border: Border.all(color: Palette.line)),
                        child: Row(children: [
                          Container(
                            width: 34,
                            height: 34,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Palette.gold2, Palette.gold3])),
                            child: Text(kAvatars[s.avatar % kAvatars.length], style: const TextStyle(fontSize: 18)),
                          ),
                          const SizedBox(width: 8),
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 120),
                              child: Text(s.displayName, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                            ),
                            const Text('Profile ✏️', style: TextStyle(color: Palette.gold2, fontSize: 11)),
                          ]),
                        ]),
                      ),
                    ),
                    const Spacer(),
                    if (s.profile != null) ...[
                      _pill('🪙 ${_fmt(s.profile!.coins)}', const Color(0xFFFCD34D), const Color(0x8CF59E0B)),
                      const SizedBox(width: 6),
                      _pill('💎 ${s.profile!.gems}', Palette.emerald, const Color(0x8C10B981)),
                    ],
                  ]),
                  const SizedBox(height: 18),
                  AnimatedBuilder(
                    animation: _float,
                    builder: (context, child) => Transform.translate(offset: Offset(0, -6 * Curves.easeInOut.transform(_float.value)), child: child),
                    child: const Center(child: LogoBadge(size: 112)),
                  ),
                  const SizedBox(height: 10),
                  const GoldTitle('STAR LUDO', size: 36, subtitle: 'ROYALE'),
                  const SizedBox(height: 22),
                  if (saved != null) ...[
                    BigButton(
                      icon: '▶️',
                      title: 'Continue Match',
                      subtitle: saved,
                      dark: true,
                      colors: const [Color(0xFFFBBF24), Color(0xFFD97706), Color(0xFF92400E)],
                      onTap: () {
                        final c = LocalMatchController.resume();
                        if (c != null) {
                          _openGame(c);
                        } else {
                          setState(() {});
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                  ],
                  BigButton(
                    icon: '🤖',
                    title: 'vs Computer',
                    subtitle: 'Play against smart bots',
                    colors: const [Color(0xFF6366F1), Color(0xFF4338CA), Color(0xFF312E81)],
                    onTap: () => _openSetup(vsComputer: true),
                  ),
                  const SizedBox(height: 14),
                  BigButton(
                    icon: '👥',
                    title: 'Pass & Play',
                    subtitle: '2–4 friends on one phone',
                    colors: const [Color(0xFF22C55E), Color(0xFF15803D), Color(0xFF14532D)],
                    onTap: () => _openSetup(vsComputer: false),
                  ),
                  const SizedBox(height: 14),
                  BigButton(
                    icon: '🌐',
                    title: 'Play Online',
                    subtitle: 'Private rooms with friends anywhere',
                    colors: const [Color(0xFF0EA5E9), Color(0xFF0369A1), Color(0xFF0C4A6E)],
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OnlineMenuScreen())).then((_) {
                      if (mounted) setState(() {});
                    }),
                  ),
                  const SizedBox(height: 14),
                  BigButton(
                    icon: '🏆',
                    title: 'Leaderboard',
                    subtitle: 'Top players by online wins',
                    colors: const [Color(0xFFA855F7), Color(0xFF7E22CE), Color(0xFF4C1D95)],
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LeaderboardScreen())),
                  ),
                  const SizedBox(height: 18),
                  _SettingsRow(onChanged: () => setState(() {})),
                  const SizedBox(height: 14),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), border: Border.all(color: Palette.emerald.withValues(alpha: 0.5))),
                      child: const Text('100% free · No real money · No betting', style: TextStyle(color: Palette.emerald, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    TextButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LegalScreen(initialTab: 0))),
                      child: const Text('Privacy Policy', style: TextStyle(color: Palette.gold1, decoration: TextDecoration.underline, fontSize: 12)),
                    ),
                    const Text('·', style: TextStyle(color: Palette.muted)),
                    TextButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LegalScreen(initialTab: 1))),
                      child: const Text('Terms of Use', style: TextStyle(color: Palette.gold1, decoration: TextDecoration.underline, fontSize: 12)),
                    ),
                  ]),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }

  static String _fmt(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  Widget _pill(String text, Color fg, Color border) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: const Color(0xD9020617), borderRadius: BorderRadius.circular(99), border: Border.all(color: border)),
        child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 13)),
      );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.onChanged});
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final st = Storage.instance;
    Widget chip(String label, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.all(4),
          child: ActionChip(
            backgroundColor: Palette.panel.withValues(alpha: 0.85),
            side: const BorderSide(color: Palette.line),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
            label: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            onPressed: () {
              onTap();
              onChanged();
            },
          ),
        );
    return Wrap(alignment: WrapAlignment.center, children: [
      chip(st.soundOn ? '🔊 Sound On' : '🔇 Sound Off', () => st.soundOn = !st.soundOn),
      chip(st.hapticsOn ? '📳 Vibration On' : '📴 Vibration Off', () => st.hapticsOn = !st.hapticsOn),
      chip(st.fastBots ? '⚡ Bots: Fast' : '⚡ Bots: Normal', () => st.fastBots = !st.fastBots),
    ]);
  }
}

class _SetupSheet extends StatefulWidget {
  const _SetupSheet({required this.vsComputer});
  final bool vsComputer;
  @override
  State<_SetupSheet> createState() => _SetupSheetState();
}

class _SetupSheetState extends State<_SetupSheet> {
  late int count;
  late LudoColor color;
  final Map<LudoColor, TextEditingController> names = {for (final c in kOrder) c: TextEditingController()};

  @override
  void initState() {
    super.initState();
    final last = Storage.instance.lastSetup;
    count = (last['count'] as int?) ?? (widget.vsComputer ? 4 : 2);
    color = widget.vsComputer && last['color'] != null ? colorFromName(last['color'] as String) : LudoColor.red;
    final saved = (last['names'] as Map<String, dynamic>?) ?? {};
    for (final c in kOrder) {
      names[c]!.text = (saved[c.name] as String?) ?? '';
    }
  }

  @override
  void dispose() {
    for (final t in names.values) {
      t.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seats = seatColors(count, color);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GoldTitle(widget.vsComputer ? 'vs Computer' : 'Pass & Play', size: 22),
      const SectionLabel('Players'),
      Row(children: [
        for (final n in [2, 3, 4])
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () => setState(() => count = n),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: n == count ? Palette.gold2.withValues(alpha: 0.16) : const Color(0xFF0B1222),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: n == count ? Palette.gold2 : Palette.line, width: 2),
                  ),
                  child: Text('$n', style: TextStyle(color: n == count ? Palette.gold1 : Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ),
      ]),
      if (widget.vsComputer) ...[
        const SectionLabel('Your colour'),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          for (final c in kOrder)
            GestureDetector(
              onTap: () => setState(() => color = c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Palette.player[c],
                  shape: BoxShape.circle,
                  border: Border.all(color: c == color ? Colors.white : Colors.white24, width: 3),
                  boxShadow: c == color ? [BoxShadow(color: Palette.player[c]!, blurRadius: 16)] : const [],
                ),
                child: c == color ? const Icon(Icons.check, color: Colors.white) : null,
              ),
            ),
        ]),
      ] else ...[
        const SectionLabel('Player names'),
        for (final c in seats)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Container(width: 24, height: 24, decoration: BoxDecoration(color: Palette.player[c], shape: BoxShape.circle, border: Border.all(color: Colors.white54, width: 2))),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: names[c],
                  maxLength: 14,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '${kColorLabel[c]} Player',
                    hintStyle: const TextStyle(color: Palette.muted),
                    filled: true,
                    fillColor: const Color(0xFF020617),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Palette.line, width: 2)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Palette.line, width: 2)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Palette.gold2, width: 2)),
                  ),
                ),
              ),
            ]),
          ),
      ],
      const SizedBox(height: 12),
      Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < seats.length; i++)
          Container(
            padding: const EdgeInsets.fromLTRB(5, 4, 10, 4),
            decoration: BoxDecoration(color: const Color(0xFF0B1222), borderRadius: BorderRadius.circular(99), border: Border.all(color: Palette.line)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 18, height: 18, decoration: BoxDecoration(color: Palette.player[seats[i]], shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(widget.vsComputer ? (i == 0 ? 'You' : '🤖 Computer') : '👤 Player ${i + 1}',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ),
      ]),
      const SizedBox(height: 18),
      GoldButton('START GAME', onPressed: () {
        final nameMap = {for (final c in kOrder) c: names[c]!.text.trim()};
        Storage.instance.lastSetup = {
          'count': count,
          'color': color.name,
          'names': {for (final e in nameMap.entries) e.key.name: e.value},
        };
        Navigator.pop(context, MatchSetup(vsComputer: widget.vsComputer, count: count, myColor: color, names: nameMap));
      }),
    ]);
  }
}
