import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/palette.dart';
import '../core/session.dart';
import '../widgets/common.dart';

class ProfileSheet extends StatefulWidget {
  const ProfileSheet({super.key});
  @override
  State<ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<ProfileSheet> {
  final s = Session.instance;
  late final _name = TextEditingController(text: s.displayName);
  late int _avatar = s.avatar;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'Please enter a name.');
      return;
    }
    setState(() => _busy = true);
    await s.updateProfile(name: name, avatar: _avatar);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _google() async {
    setState(() => _busy = true);
    try {
      await s.signInWithGoogle();
      if (mounted) showSnack(context, 'Google account linked. Your progress is safe.');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.isNetwork ? 'No internet connection.' : 'Google sign-in failed (${e.code}).');
    } catch (_) {
      if (mounted) showSnack(context, 'Google sign-in was cancelled.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context,
        title: 'Delete account?',
        message: 'This permanently deletes your online profile, coins, gems and stats from our server. This cannot be undone.',
        yes: 'Delete');
    if (!ok) return;
    try {
      await s.deleteAccount();
      if (mounted) {
        Navigator.pop(context);
        showSnack(context, 'Your account was deleted.');
      }
    } catch (_) {
      if (mounted) showSnack(context, 'Could not delete right now. Check your internet.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = s.profile;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const GoldTitle('PROFILE', size: 22),
      const SectionLabel('Avatar'),
      Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
        for (var i = 0; i < kAvatars.length; i++)
          GestureDetector(
            onTap: () => setState(() => _avatar = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0B1222),
                border: Border.all(color: i == _avatar ? Palette.gold2 : Palette.line, width: i == _avatar ? 3 : 1.5),
              ),
              child: Text(kAvatars[i], style: const TextStyle(fontSize: 26)),
            ),
          ),
      ]),
      const SectionLabel('Name'),
      TextField(
        controller: _name,
        maxLength: 14,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: const Color(0xFF020617),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Palette.line, width: 2)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Palette.line, width: 2)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Palette.gold2, width: 2)),
        ),
      ),
      if (p != null) ...[
        const SectionLabel('Online stats'),
        Row(children: [
          _stat('Played', '${p.gamesPlayed}'),
          _stat('Wins', '${p.wins}'),
          _stat('Captures', '${p.captures}'),
        ]),
      ],
      const SizedBox(height: 16),
      GoldButton('SAVE', busy: _busy, onPressed: _save),
      const SizedBox(height: 10),
      if (s.firebaseReady && !(p?.hasGoogle ?? false))
        GhostButton('Link Google account (keep progress on any phone)', onPressed: _busy ? null : _google),
      if (p?.hasGoogle ?? false)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('✓ Google account linked', textAlign: TextAlign.center, style: TextStyle(color: Palette.emerald, fontWeight: FontWeight.w700)),
        ),
      if (s.loggedIn)
        TextButton(
          onPressed: _delete,
          child: const Text('Delete my online account', style: TextStyle(color: Color(0xFFFCA5A5))),
        ),
    ]);
  }

  Widget _stat(String label, String value) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: const Color(0xFF0B1222), borderRadius: BorderRadius.circular(12), border: Border.all(color: Palette.line)),
          child: Column(children: [
            Text(value, style: const TextStyle(color: Palette.gold1, fontSize: 20, fontWeight: FontWeight.w900)),
            Text(label, style: const TextStyle(color: Palette.muted, fontSize: 12)),
          ]),
        ),
      );
}
