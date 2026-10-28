import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../engine/engine.dart';
import 'config.dart';
import 'session.dart';

class RoomMember {
  final String userId;
  final String name;
  final int avatar;
  final LudoColor? color;
  final bool connected;
  final bool left;
  final bool away;
  /// Consecutive turns this player let time out (3 = removed from the match).
  final int missed;
  const RoomMember(this.userId, this.name, this.avatar, this.color, this.connected, this.left, this.away, [this.missed = 0]);
}

class RoomResult {
  final List<(String userId, String name, LudoColor color)> ranking;
  final Map<String, (int coins, int gems)> rewards;
  final String reason;
  const RoomResult(this.ranking, this.rewards, this.reason);
}

class RoomInfo {
  final String code;
  final String hostId;
  final int maxPlayers;
  final String status; // lobby | playing | finished
  final List<RoomMember> members;
  final GameState? game;
  final int? deadline;
  final RoomResult? result;

  const RoomInfo(this.code, this.hostId, this.maxPlayers, this.status, this.members, this.game, this.deadline, this.result);

  factory RoomInfo.fromJson(Map<String, dynamic> j) {
    final res = j['result'] as Map<String, dynamic>?;
    return RoomInfo(
      j['code'] as String,
      j['hostId'] as String,
      (j['maxPlayers'] as num).toInt(),
      j['status'] as String,
      (j['members'] as List)
          .map((m) => RoomMember(
                m['userId'] as String,
                m['name'] as String,
                (m['avatar'] as num?)?.toInt() ?? 0,
                m['color'] == null ? null : colorFromName(m['color'] as String),
                m['connected'] as bool? ?? false,
                m['left'] as bool? ?? false,
                m['away'] as bool? ?? false,
                (m['missed'] as num?)?.toInt() ?? 0,
              ))
          .toList(),
      j['game'] == null ? null : GameState.fromJson(j['game'] as Map<String, dynamic>),
      (j['deadline'] as num?)?.toInt(),
      res == null
          ? null
          : RoomResult(
              (res['ranking'] as List)
                  .map((r) => (r['userId'] as String, r['name'] as String, colorFromName(r['color'] as String)))
                  .toList(),
              (res['rewards'] as Map<String, dynamic>).map((k, v) =>
                  MapEntry(k, (((v as Map)['coins'] as num).toInt(), (v['gems'] as num).toInt()))),
              res['reason'] as String,
            ),
    );
  }

  RoomMember? memberFor(LudoColor c) {
    for (final m in members) {
      if (m.color == c) return m;
    }
    return null;
  }
}

class GameEventsPayload {
  final List<GameEvent> events;
  final GameState game;
  final int? deadline;
  final bool auto;
  const GameEventsPayload(this.events, this.game, this.deadline, this.auto);
}

/// Room code from an invite link (website opened as …/?room=CODE). Consumed by the home screen.
String? pendingJoinCode;

/// Quick chat: fixed phrases only (no free text → nothing to moderate).
const Map<String, String> kChatPhrases = {
  'gg': 'Well played! 👏',
  'luck': 'Good luck! 🍀',
  'hurry': 'Hurry up! ⏰',
  'nice': 'Nice move! 😎',
  'oops': 'Oops! 😅',
  'six': 'Need a 6! 🎲',
  'wow': '😮',
  'laugh': '😂',
  'angry': '😤',
  'cool': '😎',
  'fire': '🔥',
  'crown': '👑',
};

/// Single socket connection to the server, shared by the lobby and the game screen.
class OnlineService extends ChangeNotifier {
  OnlineService._();
  static final instance = OnlineService._();

  io.Socket? _socket;
  bool connected = false;
  AppLifecycleListener? _lifecycle;

  /// Back from WhatsApp / a locked screen: reconnect right away and re-sync the room,
  /// instead of waiting for the socket's retry back-off.
  void _wake() {
    final s = _socket;
    if (s == null) return;
    if (!s.connected) {
      s.connect();
    } else if (room != null) {
      call('room:resume').then((res) {
        if (res['room'] != null) _setRoom(res['room'] as Map<String, dynamic>);
      }).catchError((_) {});
    }
  }
  RoomInfo? room;
  final _events = StreamController<GameEventsPayload>.broadcast();
  final _chat = StreamController<(String userId, String id)>.broadcast();
  Stream<GameEventsPayload> get events => _events.stream;
  Stream<(String, String)> get chat => _chat.stream;

  String? get myUserId => Session.instance.profile?.id;
  LudoColor? get myColor {
    final r = room;
    if (r == null) return null;
    for (final m in r.members) {
      if (m.userId == myUserId) return m.color;
    }
    return null;
  }

  Future<void> connect() async {
    if (_socket != null && connected) return;
    await Session.instance.ensureLoggedIn();
    _lifecycle ??= AppLifecycleListener(onResume: _wake, onShow: _wake);
    _socket?.dispose();
    final completer = Completer<void>();
    final s = io.io(
      AppConfig.apiUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': Session.instance.api.token})
          .enableReconnection()
          .disableAutoConnect()
          .enableForceNew()
          .build(),
    );
    _socket = s;
    s.onConnect((_) {
      connected = true;
      if (!completer.isCompleted) completer.complete();
      // After a network blip, re-attach to our room and get the latest state.
      if (room != null) {
        call('room:resume').then((res) {
          if (res['room'] != null) _setRoom(res['room'] as Map<String, dynamic>);
        }).catchError((_) {});
      }
      notifyListeners();
    });
    s.onDisconnect((_) {
      connected = false;
      notifyListeners();
    });
    s.onConnectError((err) {
      if (!completer.isCompleted) completer.completeError(Exception('connect_failed'));
    });
    s.on('room:update', (data) => _setRoom(_payload(data)));
    s.on('game:events', (data) {
      final j = _payload(data);
      _events.add(GameEventsPayload(
        (j['events'] as List).map((e) => GameEvent.fromJson(e as Map<String, dynamic>)).toList(),
        GameState.fromJson(j['game'] as Map<String, dynamic>),
        (j['deadline'] as num?)?.toInt(),
        j['auto'] as bool? ?? false,
      ));
    });
    s.on('chat:message', (data) {
      final j = _payload(data);
      _chat.add((j['userId'] as String, j['id'] as String));
    });
    s.connect();
    await completer.future.timeout(const Duration(seconds: 10));
  }

  void _setRoom(Map<String, dynamic> j) {
    room = RoomInfo.fromJson(_deepCast(j));
    notifyListeners();
  }

  /// Event payload: some servers append extra args (e.g. a recovery offset) and the
  /// Dart client then delivers a List. Always take the first Map.
  static Map<String, dynamic> _payload(dynamic data) {
    if (data is List) data = data.firstWhere((e) => e is Map, orElse: () => const {});
    return _deepCast(data as Map);
  }

  /// Socket.io JSON arrives as Map<dynamic, dynamic>; normalise the whole tree.
  static Map<String, dynamic> _deepCast(Map m) => m.map((k, v) => MapEntry(k.toString(), _cast(v)));
  static dynamic _cast(dynamic v) => v is Map ? _deepCast(v) : (v is List ? v.map(_cast).toList() : v);

  /// Emits an event and waits for the server's ack: { ok: true, ... } or { ok: false, error }.
  Future<Map<String, dynamic>> call(String event, [Map<String, dynamic> payload = const {}]) {
    final s = _socket;
    if (s == null || !connected) return Future.error(Exception('offline'));
    final c = Completer<Map<String, dynamic>>();
    s.emitWithAck(event, payload, ack: (dynamic res) {
      final data = res is List && res.isNotEmpty ? res.first : res;
      if (!c.isCompleted) c.complete(data is Map ? _deepCast(data) : <String, dynamic>{'ok': false, 'error': 'bad_reply'});
    });
    return c.future.timeout(const Duration(seconds: 10), onTimeout: () => {'ok': false, 'error': 'timeout'});
  }

  Future<RoomInfo> _roomCall(String event, [Map<String, dynamic> payload = const {}]) async {
    await connect();
    final res = await call(event, payload);
    if (res['ok'] != true) throw OnlineError(res['error'] as String? ?? 'error');
    _setRoom(res['room'] as Map<String, dynamic>);
    return room!;
  }

  Future<RoomInfo> createRoom(int maxPlayers) => _roomCall('room:create', {'maxPlayers': maxPlayers});
  Future<RoomInfo> joinRoom(String code) => _roomCall('room:join', {'code': code.trim().toUpperCase()});

  Future<RoomInfo?> resume() async {
    await connect();
    final res = await call('room:resume');
    if (res['ok'] != true || res['room'] == null) return null;
    _setRoom(res['room'] as Map<String, dynamic>);
    return room;
  }

  Future<void> start() async {
    final res = await call('room:start');
    if (res['ok'] != true) throw OnlineError(res['error'] as String? ?? 'error');
  }

  Future<void> leave() async {
    try {
      await call('room:leave');
    } catch (_) {}
    room = null;
    notifyListeners();
  }

  Future<void> sendChat(String id) async {
    await call('chat:send', {'id': id});
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
    connected = false;
    room = null;
    notifyListeners();
  }
}

class OnlineError implements Exception {
  final String code;
  OnlineError(this.code);

  String get message => switch (code) {
        'room_not_found' => 'Room not found. Check the code.',
        'room_full' => 'That room is full.',
        'game_already_started' => 'That game has already started.',
        'already_in_room' => 'You are already in another room.',
        'need_two_players' => 'Wait for at least one friend to join.',
        'not_host' => 'Only the host can start the game.',
        'name_required' => 'Choose your player name first.',
        'timeout' || 'offline' => 'Connection problem. Try again.',
        _ => 'Something went wrong ($code).',
      };

  @override
  String toString() => message;
}
