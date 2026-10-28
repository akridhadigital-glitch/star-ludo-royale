import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'api.dart';
import 'storage.dart';

/// Who the player is. Offline play never needs the network; online features log in
/// as a guest automatically, and the player can link Google to keep progress across phones.
class Session extends ChangeNotifier {
  Session._();
  static final instance = Session._();

  final Api api = Api();
  PlayerProfile? profile;
  Map<String, dynamic>? activeRoom;
  bool firebaseReady = false;

  bool get loggedIn => api.token != null;
  String get displayName => profile?.name ?? Storage.instance.localName;
  int get avatar => profile?.avatar ?? Storage.instance.localAvatar;

  Future<void> init() async {
    api.token = Storage.instance.authToken;
    // Web build has no Firebase config; Google sign-in is a mobile feature for now.
    if (kIsWeb) {
      firebaseReady = false;
    } else {
      try {
      // Reads android/app/google-services.json / ios GoogleService-Info.plist.
      // Missing config just disables Google sign-in.
      await Firebase.initializeApp();
      firebaseReady = true;
      } catch (_) {
        firebaseReady = false;
      }
    }
    if (loggedIn) {
      refresh().catchError((_) {}); // offline is fine
    }
  }

  Future<void> refresh() async {
    try {
      final (p, room) = await api.me();
      profile = p;
      activeRoom = room;
      notifyListeners();
    } on ApiException catch (e) {
      if (e.status == 401) _clear();
      rethrow;
    }
  }

  /// Logs in as a guest if needed. Throws [ApiException] (network) if the server is unreachable.
  Future<PlayerProfile> ensureLoggedIn() async {
    if (loggedIn && profile != null) return profile!;
    if (loggedIn) {
      try {
        await refresh();
        if (profile != null) return profile!;
      } on ApiException catch (e) {
        if (e.status != 401) rethrow;
      }
    }
    // Only send a name the player chose; otherwise the server assigns a unique one (e.g. Player4821).
    final chosen = Storage.instance.localName;
    final (token, p) = await api.guestLogin(Storage.instance.deviceId, chosen == 'Player' ? null : chosen);
    _setAuth(token, p);
    if (Storage.instance.localAvatar != 0 && p.avatar != Storage.instance.localAvatar) {
      profile = await api.updateProfile(avatar: Storage.instance.localAvatar);
    }
    notifyListeners();
    return profile!;
  }

  /// Google sign-in through Firebase Auth. Links Google to the current guest account
  /// (keeping coins and stats), or switches to the player already linked to that Google account.
  Future<void> signInWithGoogle() async {
    if (!firebaseReady) throw ApiException(501, 'google_not_configured');
    try {
      await ensureLoggedIn(); // so Google can be linked to the existing guest progress
    } catch (_) {}
    final cred = await FirebaseAuth.instance.signInWithProvider(GoogleAuthProvider());
    final idToken = await cred.user?.getIdToken();
    if (idToken == null) throw ApiException(401, 'google_failed');
    final (token, p) = await api.googleLogin(idToken);
    _setAuth(token, p);
    notifyListeners();
  }

  Future<void> updateProfile({String? name, int? avatar}) async {
    if (name != null) Storage.instance.localName = name;
    if (avatar != null) Storage.instance.localAvatar = avatar;
    if (loggedIn) {
      try {
        profile = await api.updateProfile(name: name, avatar: avatar);
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    await api.deleteAccount();
    if (firebaseReady) await FirebaseAuth.instance.signOut().catchError((_) {});
    _clear();
  }

  void _setAuth(String token, PlayerProfile p) {
    api.token = token;
    Storage.instance.authToken = token;
    profile = p;
    Storage.instance.localName = p.name;
    Storage.instance.localAvatar = p.avatar;
  }

  void _clear() {
    api.token = null;
    Storage.instance.authToken = null;
    profile = null;
    activeRoom = null;
    notifyListeners();
  }
}
