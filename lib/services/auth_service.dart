import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase Authentication wrapper used to attach orders to one account
/// that can be signed in on every device (web/Chrome and Android).
///
/// The same email + password on both platforms resolves to the same
/// `uid`, which is what lets Firestore return the same order history.
class AuthService {
  AuthService._();

  static const String collectionField = 'user_id';

  /// False in unit tests and during a cold start before Firebase is ready.
  static bool get isAvailable => Firebase.apps.isNotEmpty;

  static FirebaseAuth? get _auth {
    if (!isAvailable) return null;

    return FirebaseAuth.instance;
  }

  static User? get currentUser => _auth?.currentUser;

  static String? get uid => currentUser?.uid;

  static bool get isSignedIn => currentUser != null;

  static String get email => currentUser?.email ?? '';

  static Stream<User?> authStateChanges() {
    final auth = _auth;

    if (auth == null) return const Stream<User?>.empty();

    return auth.authStateChanges();
  }

  /// Signed-in state as a simple stream, so widgets need no Firebase types.
  static Stream<bool> signedInChanges() {
    return authStateChanges().map((user) => user != null);
  }

  /// Keeps the session across app restarts and new browser tabs.
  ///
  /// The web plugin already defaults to local persistence; this makes it
  /// explicit and is a no-op on Android.
  static Future<void> preparePersistence() async {
    final auth = _auth;

    if (auth == null || !kIsWeb) return;

    try {
      await auth.setPersistence(Persistence.LOCAL);
    } catch (error) {
      debugPrint('Unable to set auth persistence: $error');
    }
  }

  static Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    final auth = _requireAuth();

    return auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  static Future<UserCredential> signUp({
    required String email,
    required String password,
  }) async {
    final auth = _requireAuth();

    return auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  static Future<void> signOut() async {
    await _auth?.signOut();
  }

  static Future<void> sendPasswordReset(String email) async {
    final auth = _requireAuth();

    await auth.sendPasswordResetEmail(email: email.trim());
  }

  static FirebaseAuth _requireAuth() {
    final auth = _auth;

    if (auth == null) {
      throw FirebaseAuthException(
        code: 'auth-unavailable',
        message: 'Sign-in is not available right now.',
      );
    }

    return auth;
  }

  /// Turns Firebase error codes into messages a shopper can act on.
  static String friendlyMessage(Object error) {
    if (error is! FirebaseAuthException) {
      return 'Something went wrong. Please try again.';
    }

    switch (error.code) {
      case 'invalid-email':
        return 'That email address looks incomplete.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email or password is incorrect.';
      case 'email-already-in-use':
        return 'An account already uses this email. Try signing in.';
      case 'weak-password':
        return 'Use a password with at least 6 characters.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and retry.';
      case 'network-request-failed':
        return 'No connection. Check your internet and try again.';
      case 'operation-not-allowed':
        return 'Email sign-in is not enabled for this project yet.';
      case 'auth-unavailable':
        return error.message ??
            'Sign-in is not available right now.';
      default:
        return error.message ?? 'Sign-in failed. Please try again.';
    }
  }
}
