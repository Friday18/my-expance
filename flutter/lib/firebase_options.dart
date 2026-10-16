// PLACEHOLDER. Replace this file by running, from the flutter/ folder:
//
//   dart pub global activate flutterfire_cli
//   flutterfire configure --platforms=android,ios
//
// Until then, run the app with --dart-define=DEV_AUTH=true (no Firebase needed).

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    throw UnsupportedError(
      'Firebase is not configured yet. Run "flutterfire configure" in the flutter/ folder, '
      'or start the app with --dart-define=DEV_AUTH=true.',
    );
  }
}
