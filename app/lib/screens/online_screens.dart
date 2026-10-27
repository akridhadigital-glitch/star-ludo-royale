import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/online.dart';
import '../core/palette.dart';
import '../core/session.dart';
import '../engine/engine.dart';
import '../game/game_screen.dart';
import '../game/match_controller.dart';
import '../widgets/common.dart';

/// Create or join a private room.
class OnlineMenuScreen extends StatefulWidget {
  const OnlineMenuScreen({super.key});
  @override
  State<OnlineMenuScreen> createState() => _OnlineMenuScreenState();
}

class _OnlineMenuScreenState extends State<OnlineMenuScreen> {
  final _code = TextEditingController();
  bool _connecting = true;
  String? _error;
  bool _busy = false;
  int _size = 2;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      await OnlineService.instance.connect();
      final room = await OnlineService.instance.resume();
      if (!mounted) return;
      setState(() => _connecting = false);
      if (room != null) _openRoom(room);
    } on ApiException catch (_) {
      if (mounted) setState(() => _error = 'Can\'t reach the game server. Check your internet and try again.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Can\'t reach the game server. Check your internet and try again.');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  void _openRoom(RoomInfo room) {
    final route = room.status == 'playing'
        ? MaterialPageRoute(builder: (_) => GameScreen(controller: OnlineMatchController.fromRoom(OnlineService.instance)))
        : MaterialPageRoute(builder: (_) => const LobbyScreen());
    Navigator.of(context).pushReplacement(route);
  }

  Future<void> _run(Future<RoomInfo> Function() f) async {
    setState(() => _busy = true);
    try {
      final room = await f();
      if (mounted) _openRoom(room);
    } on OnlineError catch (e) {
      if (mounted) showSnack(context, e.message);
    } catch (_) {
      if (mounted) showSnack(context, 'Connection problem. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RoyalBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back, color: Colors.white)),
                const Expanded(child: GoldTitle('PLAY ONLINE', size: 22)),
                const SizedBox(width: 48),
              ]),
              const SizedBox(height: 18),
              if (_connecting)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator(color: Palette.gold2)),
                )
              else if (_error != null) ...[
                const Text('📡', textAlign: TextAlign.center, style: TextStyle(fontSize: 48)),
                const SizedBox(height: 8),
                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 15)),
                const SizedBox(height: 16),
                GoldButton('TRY AGAIN', onPressed: _connect),
              ] else ...[
                _card(
                  title: 'Create a room',
                  subtitle: 'Get a code and share it with friends.',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const SectionLabel('Room size'),
                    Row(children: [
                      for (final n in [2, 3, 4])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              showCheckmark: false,
                              label: SizedBox(width: double.infinity, child: Text('$n players', textAlign: TextAlign.center)),
                              selected: _size == n,
                              onSelected: (_) => setState(() => _size = n),
                              selectedColor: Palette.gold2.withValues(alpha: 0.2),
                              backgroundColor: const Color(0xFF0B1222),
                              side: BorderSide(color: _size == n ? Palette.gold2 : Palette.line, width: 2),
                              labelStyle: TextStyle(color: _size == n ? Palette.gold1 : Colors.white, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 14),
                    GoldButton('CREATE ROOM', busy: _busy, onPressed: () => _run(() => OnlineService.instance.createRoom(_size))),
                  ]),
                ),
                const SizedBox(height: 16),
                _card(
                  title: 'Join a room',
                  subtitle: 'Enter the 6-character code from your friend.',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const SizedBox(height: 12),
                    TextField(
                      controller: _code,
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]'))],
                      style: const TextStyle(color: Palette.gold1, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 8),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: 'ABC123',
                        hintStyle: TextStyle(color: Palette.muted.withValues(alpha: 0.5), letterSpacing: 8),
                        filled: true,
                        fillColor: const Color(0xFF020617),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Palette.gold3, width: 2)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Palette.gold3, width: 2)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Palette.gold2, width: 2)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    GoldButton('JOIN ROOM', busy: _busy, onPressed: () {
                      if (_code.text.trim().length != 6) {
                        showSnack(context, 'Room codes have 6 characters.');
                        return;
                      }
                      _run(() => OnlineService.instance.joinRoom(_code.text));
                    }),
                  ]),
                ),
                const SizedBox(height: 14),
                Text('Signed in as ${Session.instance.displayName}', textAlign: TextAlign.center, style: const TextStyle(color: Palette.muted, fontSize: 12)),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _card({required String title, required String subtitle, required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Palette.panel2, Palette.panel]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Palette.gold2.withValues(alpha: 0.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
          Text(subtitle, style: const TextStyle(color: Palette.muted, fontSize: 13)),
          child,
        ]),
      );
}

/// Waiting room: shows the code, who has joined, and lets the host start.
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});
  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final online = OnlineService.instance;
  bool _starting = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    online.addListener(_onRoom);
  }

  @override
  void dispose() {
    online.removeListener(_onRoom);
    super.dispose();
  }

  void _onRoom() {
    final room = online.room;
    if (_navigated || !mounted) return;
    if (room == null) {
      _navigated = true;
      Navigator.of(context).pop();
      return;
    }
    if (room.status == 'playing' && room.game != null) {
      _navigated = true;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => GameScreen(controller: OnlineMatchController.fromRoom(online))));
    }
  }

  Future<void> _leave() async {
    _navigated = true;
    await online.leave();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        body: RoyalBackground(
          child: ListenableBuilder(
            listenable: online,
            builder: (context, _) {
              final room = online.room;
              if (room == null) return const SizedBox.shrink();
              final isHost = room.hostId == online.myUserId;
              final colors = seatColors(room.maxPlayers);
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    Row(children: [
                      IconButton(onPressed: _leave, icon: const Icon(Icons.close, color: Colors.white)),
                      const Expanded(child: GoldTitle('WAITING ROOM', size: 22)),
                      const SizedBox(width: 48),
                    ]),
                    const SizedBox(height: 20),
                    const Text('Room code', textAlign: TextAlign.center, style: TextStyle(color: Palette.muted, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: room.code));
                        showSnack(context, 'Code ${room.code} copied');
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF020617),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Palette.gold2, width: 2),
                        ),
                        child: Column(children: [
                          Text(room.code, style: const TextStyle(color: Palette.gold1, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: 10)),
                          const Text('Tap to copy · share it with friends', style: TextStyle(color: Palette.muted, fontSize: 12)),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 20),
                    for (var i = 0; i < room.maxPlayers; i++) _slot(room, i, colors),
                    const SizedBox(height: 16),
                    if (!online.connected)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: Text('Reconnecting…', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFFCA5A5))),
                      ),
                    if (isHost)
                      GoldButton(
                        room.members.length < 2 ? 'WAITING FOR PLAYERS…' : 'START GAME (${room.members.length} players)',
                        busy: _starting,
                        onPressed: room.members.length < 2
                            ? null
                            : () async {
                                setState(() => _starting = true);
                                try {
                                  await online.start();
                                } on OnlineError catch (e) {
                                  if (context.mounted) showSnack(context, e.message);
                                } catch (_) {
                                  if (context.mounted) showSnack(context, 'Connection problem. Try again.');
                                } finally {
                                  if (mounted) setState(() => _starting = false);
                                }
                              },
                      )
                    else
                      const Text('Waiting for the host to start…', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 15)),
                    const SizedBox(height: 8),
                    if (isHost && room.members.length < room.maxPlayers && room.members.length >= 2)
                      const Text('You can start now, or wait for everyone.', textAlign: TextAlign.center, style: TextStyle(color: Palette.muted, fontSize: 12)),
                  ]),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _slot(RoomInfo room, int i, List<LudoColor> colors) {
    final m = i < room.members.length ? room.members[i] : null;
    final color = Palette.player[colors[i]]!;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: m == null ? const Color(0x990F172A) : Palette.panel2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: m == null ? Palette.line : color, width: 2),
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: m == null ? const Color(0xFF1E293B) : color),
          child: Text(m == null ? '?' : kAvatars[m.avatar % kAvatars.length], style: const TextStyle(fontSize: 20, color: Colors.white)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            m == null ? 'Waiting for player…' : '${m.name}${m.userId == online.myUserId ? ' (you)' : ''}',
            style: TextStyle(color: m == null ? Palette.muted : Colors.white, fontWeight: FontWeight.w800),
          ),
        ),
        if (m != null && m.userId == room.hostId)
          const Text('HOST', style: TextStyle(color: Palette.gold2, fontWeight: FontWeight.w900, fontSize: 12)),
        if (m != null && !m.connected) const Padding(padding: EdgeInsets.only(left: 8), child: Text('offline', style: TextStyle(color: Palette.muted, fontSize: 12))),
      ]),
    );
  }
}
