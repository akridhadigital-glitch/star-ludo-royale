import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/online.dart';
import '../core/session.dart';
import '../core/sound.dart';
import '../core/storage.dart';
import '../engine/engine.dart';

enum SeatKind { me, human, bot, remote }

class Seat {
  final LudoColor color;
  String name;
  int avatar;
  SeatKind kind;
  bool connected;
  bool left;
  bool away;
  String? userId;
  Seat(this.color, this.name, this.avatar, this.kind, {this.connected = true, this.left = false, this.away = false, this.userId});
  bool get isBot => kind == SeatKind.bot;
}

class BoardToast {
  final String text;
  final LudoColor? color;
  const BoardToast(this.text, [this.color]);
}

class MatchResult {
  final List<LudoColor> ranking;
  final LudoColor winner;
  final bool iWon;
  final bool hasMe;
  final (int coins, int gems)? reward;
  final String reason;
  const MatchResult(this.ranking, this.winner, this.iWon, this.hasMe, this.reward, this.reason);
}

class _Batch {
  final List<GameEvent> events;
  final GameState after;
  final int? deadline;
  _Batch(this.events, this.after, this.deadline);
}

/// Everything the game screen needs, independent of offline/online.
/// Game logic produces (events, newState); this class animates the events,
/// then commits the new state. The UI only ever reads [shown] and [state].
abstract class MatchController extends ChangeNotifier {
  MatchController(this.state, this.seats) : shown = _copySteps(state);

  GameState state;
  Map<LudoColor, List<int>> shown;
  final List<Seat> seats;

  int shownDice = 6;
  bool rolling = false;
  bool animating = false;
  String hint = '';
  String bonusText = '';
  DateTime? deadline;
  MatchResult? result;
  bool disposed = false;

  /// Token key ("red-2") → hop counter; the token widget hops when it changes.
  final Map<String, int> hops = {};
  /// Tokens currently flying back to the yard after a capture (slower animation).
  final Set<String> flying = {};
  final _toasts = StreamController<BoardToast>.broadcast();
  Stream<BoardToast> get toasts => _toasts.stream;

  final Queue<_Batch> _queue = Queue();
  bool _draining = false;

  bool get isOnline;
  int get stepMs => 170;
  int get rollMs => 520;

  /// 1.0 = normal speed. When moves pile up (slow network, fast opponent) the backlog
  /// plays faster so the board catches up instead of lagging further behind.
  double tempo = 1.0;

  /// Duration the board uses to slide a token one square (follows [tempo]).
  int get animStepMs => (stepMs * tempo).round().clamp(40, 400);
  bool get isMyTurn;

  Seat seatOf(LudoColor c) => seats.firstWhere((s) => s.color == c);
  LudoColor get turnColor => state.current;

  bool get canRoll => !animating && !rolling && result == null && state.phase == Phase.roll && isMyTurn;

  List<int> get movable {
    if (animating || rolling || result != null || state.phase != Phase.move || !isMyTurn || state.dice == null) return const [];
    return movableTokens(state, state.current, state.dice!);
  }

  Future<void> roll();
  Future<void> move(int token);
  Future<void> leave();

  static Map<LudoColor, List<int>> _copySteps(GameState s) => {for (final c in s.players) c: List.of(s.tokens[c]!)};

  @protected
  void enqueue(List<GameEvent> events, GameState after, {int? deadlineMs}) {
    _queue.add(_Batch(events, after, deadlineMs));
    if (!_draining) _drain();
  }

  Future<void> _drain() async {
    _draining = true;
    while (_queue.isNotEmpty && !disposed) {
      final b = _queue.removeFirst();
      tempo = _queue.isNotEmpty ? 0.35 : 1.0; // more already waiting behind this one → catch up
      await _play(b);
      tempo = 1.0;
    }
    _draining = false;
    if (!disposed) onSettled();
  }

  void _hop(LudoColor c, int t) {
    final k = '${c.name}-$t';
    hops[k] = (hops[k] ?? 0) + 1;
  }

  Future<void> _wait(int ms) => Future.delayed(Duration(milliseconds: (ms * tempo).round()));

  void _notify() {
    if (!disposed) notifyListeners();
  }

  Future<void> _play(_Batch b) async {
    animating = true;
    deadline = null;
    _notify();
    for (final e in b.events) {
      if (disposed) return;
      switch (e.type) {
        case EventType.rolled:
          await animateRoll(e.value, e.color);
        case EventType.threeSixes:
          hint = 'Three 6s in a row — turn lost!';
          if (!disposed) _toasts.add(const BoardToast('3 × SIX! 😵'));
          Sound.haptic(HapticKind.medium);
          _notify();
          await _wait(900);
        case EventType.noMove:
          hint = e.color == turnColorForHint && isMyTurn ? 'No move — need a 6' : '${seatOf(e.color).name}: no move';
          _notify();
          await _wait(550);
        case EventType.moved:
          final steps = shown[e.color]!;
          if (e.from == kYard) {
            steps[e.token] = 0;
            _hop(e.color, e.token);
            Sound.instance.play(Sfx.step);
            _notify();
            await _wait(320);
          } else {
            for (var s = e.from + 1; s <= e.to; s++) {
              if (disposed) return;
              steps[e.token] = s;
              _hop(e.color, e.token);
              Sound.instance.play(Sfx.step);
              _notify();
              await _wait(stepMs);
            }
          }
        case EventType.captured:
          for (final v in e.victims) {
            shown[v.color]![v.token] = kYard;
            flying.add('${v.color.name}-${v.token}');
          }
          Sound.instance.play(Sfx.capture);
          Sound.haptic(HapticKind.heavy);
          if (!disposed) _toasts.add(BoardToast('💥 CAPTURED!', e.color));
          hint = '${seatOf(e.color).name} captured ${seatOf(e.victims.first.color).name}!';
          _notify();
          await _wait(500);
          flying.clear();
        case EventType.home:
          Sound.instance.play(Sfx.home);
          Sound.haptic(HapticKind.medium);
          if (!disposed) _toasts.add(BoardToast('🏠 HOME!', e.color));
          _notify();
          await _wait(350);
        case EventType.bonus:
          bonusText = switch (e.reason) {
            'capture' => '💥 Bonus roll for capture',
            'home' => '🏠 Bonus roll for reaching home',
            _ => '🎉 Six! Roll again',
          };
        case EventType.turn:
          bonusText = '';
        case EventType.over:
          break;
      }
    }
    state = b.after;
    shown = _copySteps(state);
    if (b.deadline != null) deadline = DateTime.fromMillisecondsSinceEpoch(b.deadline!);
    animating = false;
    _notify();
  }

  LudoColor get turnColorForHint => state.current;

  Future<void> animateRoll(int value, LudoColor color, {int? ms}) async {
    rolling = true;
    Sound.instance.play(Sfx.roll);
    _notify();
    final rnd = Random();
    final frames = (((ms ?? rollMs) * tempo) / 70).ceil().clamp(1, 20);
    for (var i = 0; i < frames && !disposed; i++) {
      shownDice = 1 + rnd.nextInt(6);
      _notify();
      await _wait(70);
    }
    shownDice = value;
    rolling = false;
    if (value == 6) Sound.instance.play(Sfx.six);
    _notify();
    await _wait(160);
  }

  /// Called whenever the animation queue empties.
  @protected
  void onSettled() {
    _updateHint();
  }

  void _updateHint() {
    if (result != null) return;
    final seat = seatOf(state.current);
    if (isMyTurn) {
      final multiHuman = seats.where((s) => s.kind == SeatKind.me || s.kind == SeatKind.human).length > 1 && !isOnline;
      hint = state.phase == Phase.roll
          ? (multiHuman ? '${seat.name}\'s turn — tap the dice' : 'Your turn — tap the dice')
          : 'Tap a glowing token';
    } else {
      hint = seat.isBot ? '${seat.name} is thinking…' : '${seat.name}\'s turn…';
    }
    _notify();
  }

  @protected
  void emitToast(BoardToast t) {
    if (!disposed) _toasts.add(t);
  }

  /// Async work (network acks, timers) can finish after the screen closed; never notify then.
  @override
  void notifyListeners() {
    if (!disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    _toasts.close();
    super.dispose();
  }
}

// ============================================================================
// Offline: vs Computer and Pass & Play
// ============================================================================

class MatchSetup {
  final bool vsComputer;
  final int count;
  final LudoColor myColor;
  final Map<LudoColor, String> names;
  const MatchSetup({required this.vsComputer, required this.count, required this.myColor, this.names = const {}});

  Map<String, dynamic> toJson() => {
        'vsComputer': vsComputer,
        'count': count,
        'myColor': myColor.name,
        'names': names.map((k, v) => MapEntry(k.name, v)),
      };

  factory MatchSetup.fromJson(Map<String, dynamic> j) => MatchSetup(
        vsComputer: j['vsComputer'] as bool,
        count: (j['count'] as num).toInt(),
        myColor: colorFromName(j['myColor'] as String),
        names: ((j['names'] as Map<String, dynamic>?) ?? {}).map((k, v) => MapEntry(colorFromName(k), v as String)),
      );
}

class LocalMatchController extends MatchController {
  LocalMatchController._(super.state, super.seats, this.setup);

  final MatchSetup setup;
  final Random _rng = Random();
  Timer? _botTimer;
  Timer? _turnTimer;

  static List<Seat> _seats(MatchSetup s, List<LudoColor> colors) {
    var bot = 0;
    return [
      for (var i = 0; i < colors.length; i++)
        if (s.vsComputer && i > 0)
          Seat(colors[i], colors.length > 2 ? 'Bot ${++bot}' : 'Computer', 7 + i, SeatKind.bot)
        else if (s.vsComputer)
          Seat(colors[i], Session.instance.displayName, Session.instance.avatar, SeatKind.me)
        else
          Seat(colors[i], (s.names[colors[i]]?.trim().isNotEmpty ?? false) ? s.names[colors[i]]!.trim() : '${_label(colors[i])} Player',
              i, SeatKind.human),
    ];
  }

  static String _label(LudoColor c) => c.name[0].toUpperCase() + c.name.substring(1);

  factory LocalMatchController.newMatch(MatchSetup setup) {
    final colors = seatColors(setup.count, setup.myColor);
    final c = LocalMatchController._(createGame(colors), _seats(setup, colors), setup);
    c._save();
    c.onSettled();
    return c;
  }

  static LocalMatchController? resume() {
    final saved = Storage.instance.savedMatch;
    if (saved == null) return null;
    try {
      final setup = MatchSetup.fromJson(saved['setup'] as Map<String, dynamic>);
      final state = GameState.fromJson(saved['state'] as Map<String, dynamic>);
      if (state.phase == Phase.over) return null;
      // Resume at the start of the current turn so nobody gets a free re-roll mid-move.
      if (state.phase == Phase.move) {
        state.phase = Phase.roll;
        state.dice = null;
      }
      final c = LocalMatchController._(state, _seats(setup, state.players), setup);
      c.onSettled();
      return c;
    } catch (_) {
      Storage.instance.savedMatch = null;
      return null;
    }
  }

  static String? savedDescription() {
    final saved = Storage.instance.savedMatch;
    if (saved == null) return null;
    try {
      final setup = MatchSetup.fromJson(saved['setup'] as Map<String, dynamic>);
      return '${setup.vsComputer ? 'vs Computer' : 'Pass & Play'} · ${setup.count} players';
    } catch (_) {
      return null;
    }
  }

  @override
  bool get isOnline => false;

  @override
  int get stepMs => seatOf(state.current).isBot && Storage.instance.fastBots ? 95 : 170;

  @override
  int get rollMs => seatOf(state.current).isBot ? (Storage.instance.fastBots ? 260 : 460) : 520;

  @override
  bool get isMyTurn => !seatOf(state.current).isBot;

  int get _thinkMs => Storage.instance.fastBots ? 160 : 420;

  @override
  Future<void> roll() async {
    if (!canRoll) return;
    _apply(applyRoll(state, 1 + _rng.nextInt(6)));
    Sound.haptic();
  }

  @override
  Future<void> move(int token) async {
    if (!movable.contains(token)) return;
    _apply(applyMove(state, token));
  }

  void _apply(Transition t) {
    _turnTimer?.cancel();
    deadline = null;
    enqueue(t.events, t.state);
  }

  @override
  void onSettled() {
    super.onSettled();
    _save();
    _botTimer?.cancel();
    _turnTimer?.cancel();
    if (state.phase == Phase.over) {
      _finish();
      return;
    }
    final seat = seatOf(state.current);
    if (seat.isBot) {
      _botTimer = Timer(Duration(milliseconds: _thinkMs), () {
        if (disposed || animating) return;
        if (state.phase == Phase.roll) {
          _apply(applyRoll(state, 1 + _rng.nextInt(6)));
        } else {
          _apply(applyMove(state, chooseBotMove(state, _rng)));
        }
      });
      return;
    }
    // Human: auto-move a single option, otherwise start the turn timer.
    final options = movable;
    if (state.phase == Phase.move && options.length == 1) {
      hint = 'Moving your only option…';
      notifyListeners();
      _botTimer = Timer(const Duration(milliseconds: 380), () {
        if (!disposed && !animating && state.phase == Phase.move) _apply(applyMove(state, options.first));
      });
      return;
    }
    if (state.phase == Phase.roll && seats.where((s) => !s.isBot).length == 1) Sound.instance.play(Sfx.turn);
    deadline = DateTime.now().add(const Duration(seconds: 15));
    notifyListeners();
    _turnTimer = Timer(const Duration(seconds: 15), () {
      if (disposed || animating) return;
      hint = '⏰ Time up! Auto-playing…';
      if (state.phase == Phase.roll) {
        _apply(applyRoll(state, 1 + _rng.nextInt(6)));
      } else if (state.phase == Phase.move) {
        _apply(applyMove(state, chooseBotMove(state, _rng)));
      }
    });
  }

  void _finish() {
    Storage.instance.savedMatch = null;
    final winner = state.winner!;
    final me = seats.where((s) => s.kind == SeatKind.me);
    final iWon = me.isNotEmpty && me.first.color == winner;
    Sound.instance.play(me.isEmpty || iWon ? Sfx.win : Sfx.lose);
    Sound.haptic(HapticKind.heavy);
    result = MatchResult(ranking(state), winner, iWon, me.isNotEmpty, null, 'finished');
    notifyListeners();
  }

  void _save() {
    if (state.phase == Phase.over) return;
    Storage.instance.savedMatch = {'setup': setup.toJson(), 'state': state.toJson()};
  }

  @override
  Future<void> leave() async {
    _save();
  }

  @override
  void dispose() {
    _botTimer?.cancel();
    _turnTimer?.cancel();
    super.dispose();
  }
}

// ============================================================================
// Online: the server is the referee; we send intents and animate its events.
// ============================================================================

class OnlineMatchController extends MatchController {
  OnlineMatchController._(super.state, super.seats, this.online) {
    _eventsSub = online.events.listen(_onEvents);
    _chatSub = online.chat.listen((m) {
      for (final s in seats) {
        if (s.userId == m.$1) _chat.add((s.color, kChatPhrases[m.$2] ?? ''));
      }
    });
    online.addListener(_onRoom);
    _lastMoveNo = state.moveNo;
    if (state.moveNo == 0) {
      // Fresh match: say who the server randomly picked to start.
      Future.delayed(const Duration(milliseconds: 700), () {
        if (!disposed) emitToast(BoardToast('🎲 ${seatOf(state.current).name} goes first!', state.current));
      });
    }
    final d = online.room?.deadline;
    if (d != null) deadline = DateTime.fromMillisecondsSinceEpoch(d);
    onSettled();
  }

  factory OnlineMatchController.fromRoom(OnlineService online) {
    final room = online.room!;
    final game = room.game!;
    final seats = <Seat>[
      for (final c in game.players) _seatFor(room, c, online.myUserId),
    ];
    return OnlineMatchController._(game, seats, online);
  }

  static Seat _seatFor(RoomInfo room, LudoColor c, String? me) {
    final m = room.memberFor(c);
    return Seat(c, m?.name ?? '?', m?.avatar ?? 0, m?.userId == me ? SeatKind.me : SeatKind.remote,
        connected: m?.connected ?? false, left: m?.left ?? false, away: m?.away ?? false, userId: m?.userId);
  }

  final OnlineService online;
  late final StreamSubscription<GameEventsPayload> _eventsSub;
  int _lastMoveNo = 0;
  bool _sending = false;
  bool _optimisticRoll = false;
  final _chat = StreamController<(LudoColor, String)>.broadcast();
  Stream<(LudoColor, String)> get chatBubbles => _chat.stream;
  late final StreamSubscription<(String, String)> _chatSub;

  @override
  bool get isOnline => true;

  @override
  int get stepMs => 150;

  LudoColor? get myColor => online.myColor;

  @override
  bool get isMyTurn => myColor != null && state.current == myColor;

  @override
  bool get canRoll => super.canRoll && !_sending;

  bool _missedNotice = false;

  void _onEvents(GameEventsPayload p) {
    if (p.game.moveNo <= _lastMoveNo) return; // already have it (e.g. after a resume)
    _lastMoveNo = p.game.moveNo;
    // My timer ran out and the server rolled for me: tell the player clearly.
    if (p.auto && p.events.isNotEmpty && p.events.first.type == EventType.rolled && p.events.first.color == myColor) {
      _missedNotice = true;
      emitToast(BoardToast('⏰ Time up!', myColor));
    }
    enqueue(p.events, p.game, deadlineMs: p.deadline);
  }

  @override
  Future<void> animateRoll(int value, LudoColor color, {int? ms}) {
    if (_optimisticRoll) {
      _optimisticRoll = false;
      return super.animateRoll(value, color, ms: 220);
    }
    return super.animateRoll(value, color, ms: 380);
  }

  void _onRoom() {
    final room = online.room;
    if (room == null || disposed) return;
    for (final s in seats) {
      final m = room.memberFor(s.color);
      if (m == null) continue;
      s.connected = m.connected;
      s.left = m.left;
      s.away = m.away;
    }
    final g = room.game;
    // Missed events (e.g. app was in background): jump straight to the server state.
    if (g != null && g.moveNo > _lastMoveNo && !animating) {
      _lastMoveNo = g.moveNo;
      state = g;
      shown = {for (final c in g.players) c: List.of(g.tokens[c]!)};
      if (room.deadline != null) deadline = DateTime.fromMillisecondsSinceEpoch(room.deadline!);
    }
    if (room.status == 'finished' && room.result != null && result == null) {
      _scheduleResult(room);
    }
    // Removed after 3 missed turns while the others play on: end the game for this player.
    final me = seats.where((s) => s.kind == SeatKind.me);
    if (room.status == 'playing' && result == null && me.isNotEmpty && me.first.left) {
      final order = ranking(state);
      result = MatchResult(order, order.first, false, true, null, 'removed');
      deadline = null;
      Sound.instance.play(Sfx.lose);
    }
    notifyListeners();
  }

  void _scheduleResult(RoomInfo room) {
    // Let the final move animation finish first.
    Future.doWhile(() async {
      if (disposed) return false;
      if (!animating && _queueIdle) {
        _setResult(room);
        return false;
      }
      await Future.delayed(const Duration(milliseconds: 100));
      return true;
    });
  }

  bool get _queueIdle => !animating;

  void _setResult(RoomInfo room) {
    final r = room.result!;
    final winner = r.ranking.first.$3;
    final me = online.myUserId;
    final iWon = r.ranking.first.$1 == me;
    final reward = me == null ? null : r.rewards[me];
    Sound.instance.play(iWon ? Sfx.win : Sfx.lose);
    Sound.haptic(HapticKind.heavy);
    result = MatchResult(r.ranking.map((e) => e.$3).toList(), winner, iWon, true, reward, r.reason);
    deadline = null;
    Session.instance.refresh().catchError((_) {});
    notifyListeners();
  }

  @override
  Future<void> roll() async {
    if (!canRoll) return;
    _sending = true;
    _optimisticRoll = true;
    rolling = true; // spin immediately; the server's result lands a moment later
    Sound.haptic();
    notifyListeners();
    try {
      final res = await online.call('game:roll');
      if (res['ok'] != true) {
        _optimisticRoll = false;
        rolling = false;
        hint = 'Could not roll (${res['error']})';
      }
    } catch (_) {
      _optimisticRoll = false;
      rolling = false;
      hint = 'Connection problem — retrying…';
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  @override
  Future<void> move(int token) async {
    if (!movable.contains(token) || _sending) return;
    _sending = true;
    notifyListeners();
    try {
      final res = await online.call('game:move', {'token': token});
      if (res['ok'] != true) hint = 'Move rejected (${res['error']})';
    } catch (_) {
      hint = 'Connection problem — retrying…';
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  Future<void> sendChat(String id) => online.sendChat(id).catchError((_) {});

  @override
  void onSettled() {
    super.onSettled();
    if (_missedNotice) {
      _missedNotice = false;
      var missed = 1;
      for (final m in online.room?.members ?? const <RoomMember>[]) {
        if (m.userId == online.myUserId) missed = m.missed;
      }
      hint = '⏰ Time ran out — turn auto-played ($missed/3). Miss 3 and you\'re out.';
      notifyListeners();
    }
    if (state.phase == Phase.roll && isMyTurn) Sound.instance.play(Sfx.turn);
    if (online.room?.status == 'finished' && online.room?.result != null && result == null) _setResult(online.room!);
  }

  @override
  Future<void> leave() => online.leave();

  @override
  void dispose() {
    _eventsSub.cancel();
    _chatSub.cancel();
    _chat.close();
    online.removeListener(_onRoom);
    super.dispose();
  }
}
