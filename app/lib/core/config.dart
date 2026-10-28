/// Build-time configuration. Override with:
///   flutter run --dart-define=API_URL=https://api.yourdomain.com
class AppConfig {
  /// Default points the Android emulator at a server running on your computer.
  static const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:8080');
  static const turnSeconds = 15;

  /// Public website, used for invite links (…/?room=CODE opens the game and joins the room).
  static const webUrl = String.fromEnvironment('WEB_URL', defaultValue: 'https://akridhadigital-glitch.github.io/star-ludo-royale/');

  static String inviteLink(String code) => '$webUrl?room=$code';
}
