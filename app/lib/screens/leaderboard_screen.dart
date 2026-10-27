import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/palette.dart';
import '../core/session.dart';
import '../widgets/common.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});
  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  late Future<List<LeaderRow>> _rows = Session.instance.api.leaderboard();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RoyalBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back, color: Colors.white)),
                  const Expanded(child: GoldTitle('LEADERBOARD', size: 22)),
                  const SizedBox(width: 48),
                ]),
              ),
              Expanded(
                child: FutureBuilder<List<LeaderRow>>(
                  future: _rows,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator(color: Palette.gold2));
                    }
                    if (snap.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Text('Can\'t load the leaderboard right now.', style: TextStyle(color: Colors.white70)),
                            const SizedBox(height: 12),
                            GoldButton('RETRY', onPressed: () => setState(() => _rows = Session.instance.api.leaderboard())),
                          ]),
                        ),
                      );
                    }
                    final rows = snap.data!;
                    if (rows.isEmpty) {
                      return const Center(child: Text('No online matches yet. Be the first!', style: TextStyle(color: Colors.white70)));
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final r = rows[i];
                        final medal = r.rank <= 3 ? ['🥇', '🥈', '🥉'][r.rank - 1] : '#${r.rank}';
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: r.rank == 1 ? Palette.gold2.withValues(alpha: 0.12) : Palette.panel2,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: r.rank == 1 ? Palette.gold2 : Palette.line),
                          ),
                          child: Row(children: [
                            SizedBox(width: 40, child: Text(medal, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900))),
                            Text(kAvatars[r.avatar % kAvatars.length], style: const TextStyle(fontSize: 22)),
                            const SizedBox(width: 10),
                            Expanded(child: Text(r.name, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
                            Text('${r.wins} wins', style: const TextStyle(color: Palette.gold1, fontWeight: FontWeight.w800)),
                            const SizedBox(width: 8),
                            Text('/ ${r.gamesPlayed}', style: const TextStyle(color: Palette.muted, fontSize: 12)),
                          ]),
                        );
                      },
                    );
                  },
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
