// Google sign-in for the native screens. Same SDK and scopes as the web view sign-in, so the Worker
// accepts the token the same way.
import 'package:google_sign_in/google_sign_in.dart';

class NativeAuth {
  NativeAuth(this.scopes);
  final List<String> scopes;

  GoogleSignInAccount? _account;
  String? _token;
  DateTime _expires = DateTime.fromMillisecondsSinceEpoch(0);

  bool get signedIn => _account != null;

  /// Restores a previous sign-in without showing UI. Returns whether one existed.
  Future<bool> restore() async {
    try {
      _account = await GoogleSignIn.instance.attemptLightweightAuthentication();
    } catch (_) {
      _account = null;
    }
    return _account != null;
  }

  /// Shows the Google account picker. Throws [GoogleSignInException] when cancelled or refused.
  Future<void> signIn() async {
    _account = await GoogleSignIn.instance.authenticate(scopeHint: scopes);
    _token = null;
  }

  Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    _account = null;
    _token = null;
  }

  /// A current access token, or null when signed out.
  Future<String?> token() async {
    final account = _account;
    if (account == null) return null;
    if (_token != null && DateTime.now().isBefore(_expires)) return _token;
    final client = account.authorizationClient;
    final auth = await client.authorizationForScopes(scopes) ?? await client.authorizeScopes(scopes);
    _token = auth.accessToken;
    // Google tokens last an hour; renew a little early.
    _expires = DateTime.now().add(const Duration(minutes: 50));
    return _token;
  }
}
