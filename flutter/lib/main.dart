import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config.dart';
import 'firebase_options.dart';
import 'screens/home_shell.dart';
import 'screens/sign_in_screen.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'state/expense_store.dart';
import 'state/settings_store.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!AppConfig.devAuth) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Crash reports from release builds only.
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  final settings = await SettingsStore.load();
  final auth = AuthService();
  final api = ApiClient(auth);
  final store = ExpenseStore(api);

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: auth),
      ChangeNotifierProvider.value(value: store),
    ],
    child: const MyExpanceApp(),
  ));
}

class MyExpanceApp extends StatelessWidget {
  const MyExpanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = context.select<SettingsStore, ThemeMode>((s) => s.themeMode);
    final futuristic = context.select<SettingsStore, bool>((s) => s.futuristic);
    return MaterialApp(
      title: 'My Expance',
      debugShowCheckedModeBanner: false,
      theme: futuristic ? AppTheme.calmLight() : AppTheme.light(),
      darkTheme: futuristic ? AppTheme.calmDark() : AppTheme.dark(),
      themeMode: mode,
      themeAnimationDuration: Motion.of(context, Motion.medium),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final Widget child;
    if (!auth.ready) {
      child = const Scaffold(key: ValueKey('splash'), body: Center(child: CircularProgressIndicator()));
    } else if (auth.signedIn) {
      child = const HomeShell(key: ValueKey('home'));
    } else {
      child = const SignInScreen(key: ValueKey('signin'));
    }
    return AnimatedSwitcher(duration: Motion.of(context, Motion.medium), child: child);
  }
}
