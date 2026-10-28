import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/palette.dart';
import '../core/session.dart';
import '../core/storage.dart';
import '../widgets/common.dart';

/// Shown before the first online match: every online player needs a unique name,
/// so opponents never see a row of anonymous "Player"s.
/// Pops `true` once a name is saved, `false` if the player backs out.
class ChooseNameScreen extends StatefulWidget {
  const ChooseNameScreen({super.key});
  @override
  State<ChooseNameScreen> createState() => _ChooseNameScreenState();
}

enum _Check { idle, checking, available, problem }

class _ChooseNameScreenState extends State<ChooseNameScreen> {
  final s = Session.instance;
  late final TextEditingController _name;
  late int _avatar = s.avatar;
  Timer? _debounce;
  _Check _check = _Check.idle;
  String _message = '';
  bool _saving = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    // Suggest the nickname they typed offline, but never a placeholder like "Player12345".
    final local = Storage.instance.localName.trim();
    final suggested = RegExp(r'^player\d*$', caseSensitive: false).hasMatch(local) ? '' : local;
    _name = TextEditingController(text: suggested);
    if (suggested.isNotEmpty) _scheduleCheck();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    super.dispose();
  }

  void _scheduleCheck() {
    _debounce?.cancel();
    final text = _name.text.trim();
    if (text.length < 3) {
      setState(() {
        _check = text.isEmpty ? _Check.idle : _Check.problem;
        _message = text.isEmpty ? '' : 'At least 3 characters.';
      });
      return;
    }
    setState(() => _check = _Check.checking);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final mySeq = ++_seq;
      try {
        final (ok, reason) = await s.api.checkName(text);
        if (!mounted || mySeq != _seq) return; // a newer keystroke won
        setState(() {
          _check = ok ? _Check.available : _Check.problem;
          _message = ok ? 'Available!' : nameErrorText(reason ?? 'name_taken');
        });
      } on ApiException catch (e) {
        if (!mounted || mySeq != _seq) return;
        setState(() {
          _check = _Check.problem;
          _message = nameErrorText(e.isNetwork ? 'network' : e.code);
        });
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await s.updateProfile(name: _name.text.trim(), avatar: _avatar);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _check = _Check.problem;
        _message = nameErrorText(e.isNetwork ? 'network' : e.code);
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (_check) {
      _Check.available => Palette.emerald,
      _Check.problem => const Color(0xFFFCA5A5),
      _ => Palette.muted,
    };
    return Scaffold(
      body: RoyalBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                IconButton(onPressed: () => Navigator.pop(context, false), icon: const Icon(Icons.arrow_back, color: Colors.white)),
                const Expanded(child: GoldTitle('YOUR PLAYER NAME', size: 20)),
                const SizedBox(width: 48),
              ]),
              const SizedBox(height: 8),
              const Text(
                'Friends see this name in online games.\nIt must be unique, like a username.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 18),
              Center(
                child: Container(
                  width: 84,
                  height: 84,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Palette.gold2, Palette.gold3])),
                  child: Text(kAvatars[_avatar % kAvatars.length], style: const TextStyle(fontSize: 44)),
                ),
              ),
              const SectionLabel('Pick an avatar'),
              Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                for (var i = 0; i < kAvatars.length; i++)
                  GestureDetector(
                    onTap: () => setState(() => _avatar = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF0B1222),
                        border: Border.all(color: i == _avatar ? Palette.gold2 : Palette.line, width: i == _avatar ? 3 : 1.5),
                      ),
                      child: Text(kAvatars[i], style: const TextStyle(fontSize: 22)),
                    ),
                  ),
              ]),
              const SectionLabel('Name'),
              TextField(
                controller: _name,
                maxLength: 14,
                autofocus: _name.text.isEmpty,
                onChanged: (_) => _scheduleCheck(),
                onSubmitted: (_) {
                  if (_check == _Check.available && !_saving) _save();
                },
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'e.g. Rahul_07',
                  hintStyle: const TextStyle(color: Palette.muted),
                  filled: true,
                  fillColor: const Color(0xFF020617),
                  suffixIcon: switch (_check) {
                    _Check.checking => const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Palette.gold2)),
                      ),
                    _Check.available => const Icon(Icons.check_circle, color: Palette.emerald),
                    _Check.problem => const Icon(Icons.error, color: Color(0xFFFCA5A5)),
                    _ => null,
                  },
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Palette.line, width: 2)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: _check == _Check.idle ? Palette.line : color, width: 2)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: _check == _Check.idle ? Palette.gold2 : color, width: 2)),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _message.isNotEmpty ? _message : '3–14 letters or numbers. Space, _ . - allowed.',
                style: TextStyle(color: _message.isNotEmpty ? color : Palette.muted, fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 20),
              GoldButton('CONTINUE', busy: _saving, onPressed: _check == _Check.available ? _save : null),
            ]),
          ),
        ),
      ),
    );
  }
}
