import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Thin wrapper over SharedPreferences. Everything here lives only on the device.
class Storage {
  Storage._(this._p);
  final SharedPreferences _p;

  static late Storage instance;

  static Future<void> init() async {
    instance = Storage._(await SharedPreferences.getInstance());
  }

  // Device id used for guest login (random, not tied to any hardware id).
  String get deviceId {
    var id = _p.getString('device_id');
    if (id == null) {
      final r = Random.secure();
      id = List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
      _p.setString('device_id', id);
    }
    return id;
  }

  String? get authToken => _p.getString('auth_token');
  set authToken(String? v) => v == null ? _p.remove('auth_token') : _p.setString('auth_token', v);

  String get localName => _p.getString('local_name') ?? 'Player';
  set localName(String v) => _p.setString('local_name', v);

  int get localAvatar => _p.getInt('local_avatar') ?? 0;
  set localAvatar(int v) => _p.setInt('local_avatar', v);

  bool get soundOn => _p.getBool('sound_on') ?? true;
  set soundOn(bool v) => _p.setBool('sound_on', v);

  bool get hapticsOn => _p.getBool('haptics_on') ?? true;
  set hapticsOn(bool v) => _p.setBool('haptics_on', v);

  bool get fastBots => _p.getBool('fast_bots') ?? false;
  set fastBots(bool v) => _p.setBool('fast_bots', v);

  bool get acceptedTerms => _p.getBool('accepted_terms_v1') ?? false;
  set acceptedTerms(bool v) => _p.setBool('accepted_terms_v1', v);

  Map<String, dynamic>? get savedMatch {
    final raw = _p.getString('saved_match');
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  set savedMatch(Map<String, dynamic>? v) =>
      v == null ? _p.remove('saved_match') : _p.setString('saved_match', jsonEncode(v));

  Map<String, dynamic> get lastSetup {
    final raw = _p.getString('last_setup');
    return raw == null ? {} : (jsonDecode(raw) as Map<String, dynamic>);
  }

  set lastSetup(Map<String, dynamic> v) => _p.setString('last_setup', jsonEncode(v));
}
