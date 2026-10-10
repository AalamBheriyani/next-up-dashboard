// Google sign-in on the web: the same access-token flow the current website uses, through the Google
// Identity Services pop-up. It must start from a button press, or the browser blocks the pop-up.
import 'package:google_sign_in/google_sign_in.dart';

/// The web OAuth client; same public value as docs/config.js.
const webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID',
    defaultValue: '385720599418-u8qoimd49q4s9rpb612fteug3ocpkk27.apps.googleusercontent.com');

// Only what the deadline screens need; Calendar and Sheets scopes come with the pages that use them.
const webScopes = <String>['openid', 'email'];

class WebAuth {
  String? _token;
  DateTime _expires = DateTime.fromMillisecondsSinceEpoch(0);

  // Started at launch but never awaited before the first frame: if Google's script is blocked or slow
  // the page still shows, and signing in reports the failure.
  static final Future<void> ready = GoogleSignIn.instance.initialize(clientId: webClientId);

  bool get signedIn => _token != null && DateTime.now().isBefore(_expires);

  Future<void> signIn() async {
    await ready;
    final auth = await GoogleSignIn.instance.authorizationClient.authorizeScopes(webScopes);
    _token = auth.accessToken;
    _expires = DateTime.now().add(const Duration(minutes: 50)); // Google tokens last an hour
  }

  void signOut() {
    _token = null;
  }

  /// A current token, or null when signed out or expired (the screen then asks to sign in again).
  Future<String?> token() async => signedIn ? _token : null;
}
