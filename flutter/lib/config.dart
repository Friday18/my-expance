import 'dart:io' show Platform;

/// Build-time settings, passed with --dart-define.
///
///   flutter run --dart-define=DEV_AUTH=true
///   flutter build appbundle --dart-define=API_BASE_URL=https://your-api.onrender.com
class AppConfig {
  AppConfig._();

  /// Skip Firebase and sign in as [devUserId]. Only works against a backend with AUTH_MODE=dev.
  static const bool devAuth = bool.fromEnvironment('DEV_AUTH');
  static const String devUserId = String.fromEnvironment('DEV_USER', defaultValue: 'dev-user');

  static const String _apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const String supportEmail = String.fromEnvironment('SUPPORT_EMAIL', defaultValue: 'support@example.com');

  /// Web client ID from Firebase, only needed if Google sign-in fails on Android.
  static const String googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  /// The API. Without API_BASE_URL, debug builds talk to the Flask server on your laptop
  /// (the Android emulator reaches the host machine at 10.0.2.2).
  static String get apiBaseUrl {
    if (_apiBaseUrl.isNotEmpty) return _apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    return Platform.isAndroid ? 'http://10.0.2.2:5001' : 'http://localhost:5001';
  }

  static String get privacyUrl => '$apiBaseUrl/privacy';
  static String get accountDeletionUrl => '$apiBaseUrl/account-deletion';
}
