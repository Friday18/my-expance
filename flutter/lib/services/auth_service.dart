import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config.dart';

/// Wraps Firebase Auth (Google, Apple, email). In DEV_AUTH mode it skips Firebase entirely
/// and uses a fixed user id, which the backend accepts when AUTH_MODE=dev.
class AuthService extends ChangeNotifier {
  AuthService({this.devMode = AppConfig.devAuth}) {
    if (devMode) {
      _ready = true;
    } else {
      _sub = FirebaseAuth.instance.authStateChanges().listen((u) {
        _user = u;
        _ready = true;
        notifyListeners();
      });
    }
  }

  final bool devMode;
  StreamSubscription<User?>? _sub;
  User? _user;
  bool _devSignedIn = false;
  bool _ready = false;

  GoogleSignIn get _google => GoogleSignIn(
        scopes: const ['email'],
        serverClientId: AppConfig.googleServerClientId.isEmpty ? null : AppConfig.googleServerClientId,
      );

  /// False until Firebase reports the restored session (avoids flashing the sign-in screen).
  bool get ready => _ready;
  bool get signedIn => devMode ? _devSignedIn : _user != null;
  String get email => devMode ? '${AppConfig.devUserId}@dev.local' : (_user?.email ?? '');
  String get displayName {
    if (devMode) return 'Developer';
    final name = _user?.displayName;
    if (name != null && name.trim().isNotEmpty) return name.trim();
    return email.split('@').first;
  }

  /// The bearer token for the API.
  Future<String> token({bool forceRefresh = false}) async {
    if (devMode) return AppConfig.devUserId;
    final user = _user ?? FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Not signed in');
    final t = await user.getIdToken(forceRefresh);
    if (t == null) throw StateError('No token');
    return t;
  }

  Future<void> devSignIn() async {
    _devSignedIn = true;
    notifyListeners();
  }

  /// Returns false if the user closed the Google sheet.
  Future<bool> signInWithGoogle() async {
    final account = await _google.signIn();
    if (account == null) return false;
    final auth = await account.authentication;
    final credential = GoogleAuthProvider.credential(idToken: auth.idToken, accessToken: auth.accessToken);
    await FirebaseAuth.instance.signInWithCredential(credential);
    return true;
  }

  Future<void> signInWithApple() async {
    final provider = AppleAuthProvider()
      ..addScope('email')
      ..addScope('name');
    await FirebaseAuth.instance.signInWithProvider(provider);
  }

  Future<void> signInWithEmail(String email, String password) =>
      FirebaseAuth.instance.signInWithEmailAndPassword(email: email.trim(), password: password);

  Future<void> registerWithEmail(String email, String password) =>
      FirebaseAuth.instance.createUserWithEmailAndPassword(email: email.trim(), password: password);

  Future<void> sendPasswordReset(String email) =>
      FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());

  Future<void> signOut() async {
    if (devMode) {
      _devSignedIn = false;
      notifyListeners();
      return;
    }
    try {
      await _google.signOut();
    } catch (_) {
      // Not signed in with Google; nothing to do.
    }
    await FirebaseAuth.instance.signOut();
  }

  /// Call after the backend has deleted the user's data. Removes the Firebase account too;
  /// if Firebase wants a fresh sign-in first, we just sign out (the data is already gone).
  Future<void> deleteFirebaseAccount() async {
    if (devMode) return signOut();
    try {
      await _user?.delete();
    } on FirebaseAuthException catch (_) {
      // requires-recent-login and similar
    }
    await signOut();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// Human-readable message for sign-in errors.
String authErrorMessage(Object e) {
  if (e is FirebaseAuthException) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email address looks wrong.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email or password is incorrect.';
      case 'email-already-in-use':
        return 'An account already exists for that email. Try signing in.';
      case 'weak-password':
        return 'Use at least 6 characters for the password.';
      case 'network-request-failed':
        return 'No internet connection.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'canceled':
      case 'web-context-canceled':
        return 'Sign-in was cancelled.';
    }
    return e.message ?? 'Sign-in failed.';
  }
  return 'Sign-in failed. Please try again.';
}
