import 'package:flutter/foundation.dart';

/// Result of an account action.
class AuthResult {
  const AuthResult.ok([this.message]) : ok = true;
  const AuthResult.fail(this.message) : ok = false;
  final bool ok;
  final String? message;
}

/// What the account server has to provide. The App is ready for accounts:
/// connecting a real server (Firebase, Supabase, an Evohome server…) only
/// means writing another [AuthBackend] and giving it to [AccountStore].
abstract class AuthBackend {
  /// False while no server is connected: the forms are shown but say so.
  bool get available;
  Future<AuthResult> signIn(String email, String password);
  Future<AuthResult> signUp(String email, String password);
  Future<AuthResult> sendPasswordReset(String email);
  Future<void> signOut();
}

/// Used until a server is connected.
class NoAuthBackend implements AuthBackend {
  const NoAuthBackend();
  static const _msg = 'The account server is not connected yet, so this cannot be done. This feature will come in a later version.';

  @override
  bool get available => false;
  @override
  Future<AuthResult> signIn(String email, String password) async => const AuthResult.fail(_msg);
  @override
  Future<AuthResult> signUp(String email, String password) async => const AuthResult.fail(_msg);
  @override
  Future<AuthResult> sendPasswordReset(String email) async => const AuthResult.fail(_msg);
  @override
  Future<void> signOut() async {}
}

/// The signed-in account of the App.
class AccountStore extends ChangeNotifier {
  AccountStore([this.backend = const NoAuthBackend()]);
  final AuthBackend backend;

  /// Email of the signed-in account, null when signed out.
  String? email;
  bool busy = false;
  bool get signedIn => email != null;

  static final RegExp _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static bool validEmail(String v) => _emailRe.hasMatch(v.trim());
  static const int minPassword = 8;

  Future<AuthResult> _run(Future<AuthResult> Function() job, {String? signedInAs}) async {
    busy = true;
    notifyListeners();
    try {
      final r = await job();
      if (r.ok && signedInAs != null) email = signedInAs;
      return r;
    } catch (e) {
      return AuthResult.fail('Could not complete: $e');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<AuthResult> signIn(String e, String password) => _run(() => backend.signIn(e.trim(), password), signedInAs: e.trim());
  Future<AuthResult> signUp(String e, String password) => _run(() => backend.signUp(e.trim(), password), signedInAs: e.trim());
  Future<AuthResult> sendPasswordReset(String e) => _run(() => backend.sendPasswordReset(e.trim()));

  Future<void> signOut() async {
    await backend.signOut();
    email = null;
    notifyListeners();
  }
}
