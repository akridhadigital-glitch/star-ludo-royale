/// Build-time configuration. Override with:
///   flutter run --dart-define=API_URL=https://api.yourdomain.com
class AppConfig {
  /// Default points the Android emulator at a server running on your computer.
  static const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:8080');
  static const turnSeconds = 15;
}
