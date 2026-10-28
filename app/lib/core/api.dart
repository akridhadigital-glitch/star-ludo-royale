import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';

class ApiException implements Exception {
  final int status;
  final String code;
  ApiException(this.status, this.code);
  bool get isNetwork => status == 0;
  @override
  String toString() => 'ApiException($status, $code)';
}

class PlayerProfile {
  final String id;
  final String name;
  final int avatar;
  final int coins;
  final int gems;
  final int gamesPlayed;
  final int wins;
  final int captures;
  final bool hasGoogle;
  /// The player has chosen their own unique name (required for online play).
  final bool nameSet;

  /// Short public ID shown in the profile, e.g. #A1B2C3.
  String get shortId => '#${id.replaceAll('-', '').substring(0, 6).toUpperCase()}';

  const PlayerProfile({
    required this.id,
    required this.name,
    required this.avatar,
    required this.coins,
    required this.gems,
    required this.gamesPlayed,
    required this.wins,
    required this.captures,
    required this.hasGoogle,
    this.nameSet = false,
  });

  factory PlayerProfile.fromJson(Map<String, dynamic> j) => PlayerProfile(
        id: j['id'] as String,
        name: j['name'] as String,
        avatar: (j['avatar'] as num).toInt(),
        coins: (j['coins'] as num).toInt(),
        gems: (j['gems'] as num).toInt(),
        gamesPlayed: (j['gamesPlayed'] as num).toInt(),
        wins: (j['wins'] as num).toInt(),
        captures: (j['captures'] as num).toInt(),
        hasGoogle: j['hasGoogle'] as bool? ?? false,
        nameSet: j['nameSet'] as bool? ?? false,
      );
}

class LeaderRow {
  final int rank;
  final String name;
  final int avatar;
  final int wins;
  final int gamesPlayed;
  const LeaderRow(this.rank, this.name, this.avatar, this.wins, this.gamesPlayed);
}

/// REST client for the Star Ludo Royale server.
class Api {
  Api({String? baseUrl}) : base = baseUrl ?? AppConfig.apiUrl;
  final String base;
  String? token;

  Future<Map<String, dynamic>> _send(String method, String path, [Object? body]) async {
    final uri = Uri.parse('$base$path');
    final headers = <String, String>{
      if (body != null) 'content-type': 'application/json',
      if (token != null) 'authorization': 'Bearer $token',
    };
    http.Response res;
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      res = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 10)));
    } catch (_) {
      throw ApiException(0, 'network');
    }
    final data = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) throw ApiException(res.statusCode, (data['error'] as String?) ?? 'error');
    return data;
  }

  Future<(String, PlayerProfile)> guestLogin(String deviceId, String? name) async {
    final j = await _send('POST', '/v1/auth/guest', {'deviceId': deviceId, if (name != null) 'name': name});
    return (j['token'] as String, PlayerProfile.fromJson(j['user'] as Map<String, dynamic>));
  }

  Future<(String, PlayerProfile)> googleLogin(String firebaseIdToken) async {
    final j = await _send('POST', '/v1/auth/google', {'idToken': firebaseIdToken});
    return (j['token'] as String, PlayerProfile.fromJson(j['user'] as Map<String, dynamic>));
  }

  Future<(PlayerProfile, Map<String, dynamic>?)> me() async {
    final j = await _send('GET', '/v1/me');
    return (PlayerProfile.fromJson(j['user'] as Map<String, dynamic>), j['activeRoom'] as Map<String, dynamic>?);
  }

  Future<PlayerProfile> updateProfile({String? name, int? avatar}) async {
    final j = await _send('PATCH', '/v1/me', {if (name != null) 'name': name, if (avatar != null) 'avatar': avatar});
    return PlayerProfile.fromJson(j['user'] as Map<String, dynamic>);
  }

  Future<void> deleteAccount() => _send('DELETE', '/v1/me');

  /// Live availability: (available, reason) where reason is name_taken / name_invalid / name_reserved.
  Future<(bool, String?)> checkName(String name) async {
    final j = await _send('GET', '/v1/names/check?name=${Uri.encodeQueryComponent(name)}');
    return (j['available'] as bool? ?? false, j['reason'] as String?);
  }

  Future<List<LeaderRow>> leaderboard() async {
    final j = await _send('GET', '/v1/leaderboard');
    return (j['players'] as List)
        .map((p) => LeaderRow((p['rank'] as num).toInt(), p['name'] as String, (p['avatar'] as num).toInt(),
            (p['wins'] as num).toInt(), (p['gamesPlayed'] as num).toInt()))
        .toList();
  }
}

/// Friendly text for name errors from the server.
String nameErrorText(String code) => switch (code) {
      'name_taken' => 'That name is taken — try another.',
      'name_reserved' => 'That name is reserved — pick your own.',
      'name_invalid' || 'bad_request' => 'Use 3–14 letters or numbers (space, _ . - allowed).',
      'network' => 'No internet connection.',
      _ => 'Could not save the name ($code).',
    };
