// Next Up for Android and iOS: the dashboard site in a full-screen web view, with the parts a web page
// can't do well handled natively: Google sign-in (Google blocks sign-in inside embedded web views),
// timer notifications that fire with the app closed, and opening other sites in the real browser.
//
// The page talks to the app through the `NextUpNative` channel (see docs/index.html):
//   {type: "signin"}            -> native Google sign-in, answered with window.nextUpNativeAuth(token, expiresIn, error)
//   {type: "signout"}           -> sign out of Google on the device
//   {type: "timer", end, title, body} -> schedule (end > 0) or cancel the "session finished" notification
//   {type: "open", url}         -> open a link in the browser
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

// Public values, same as docs/config.js. Override at build time with --dart-define if you fork this.
const siteUrl = String.fromEnvironment('SITE_URL', defaultValue: 'https://aalambheriyani.github.io/next-up-dashboard/');
// The web OAuth client: Android needs it as the "server client" to issue tokens.
const webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID',
    defaultValue: '385720599418-u8qoimd49q4s9rpb612fteug3ocpkk27.apps.googleusercontent.com');
// The iOS OAuth client (empty until one is created in Google Cloud; Android needs no client id here).
const iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

const scopes = <String>[
  'openid',
  'email',
  'https://www.googleapis.com/auth/calendar.readonly',
  'https://www.googleapis.com/auth/spreadsheets',
];

// Sites that stay inside the app; everything else opens in the browser.
bool _staysInApp(Uri u) {
  final site = Uri.parse(siteUrl);
  return (u.host == site.host && u.path.startsWith(site.path)) ||
      u.host.endsWith('.workers.dev') ||
      u.host == 'ticktick.com' ||
      u.host.endsWith('.ticktick.com') ||
      u.scheme == 'about' ||
      u.scheme == 'data';
}

final _notifications = FlutterLocalNotificationsPlugin();
const _timerNotificationId = 1;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  try {
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));
  } catch (_) {
    // Falls back to UTC; notification times are absolute instants, so this only affects logging.
  }
  await _notifications.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
  );
  await GoogleSignIn.instance.initialize(
    clientId: iosClientId.isEmpty ? null : iosClientId,
    serverClientId: webClientId,
  );
  runApp(const NextUpApp());
}

class NextUpApp extends StatelessWidget {
  const NextUpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Next Up',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFFF2B33D), useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: const Color(0xFFF2B33D), brightness: Brightness.dark, useMaterial3: true),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final WebViewController _web;
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('NextUpNative', onMessageReceived: (m) => _onMessage(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (req) {
          final uri = Uri.tryParse(req.url);
          if (uri == null || _staysInApp(uri)) return NavigationDecision.navigate;
          _openExternal(uri);
          return NavigationDecision.prevent;
        },
        onPageFinished: (_) => setState(() => _loading = false),
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? true) setState(() => _loadError = e.description);
        },
      ))
      ..loadRequest(Uri.parse(siteUrl));
  }

  Future<void> _onMessage(String raw) async {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (msg['type']) {
      case 'signin':
        await _signIn();
      case 'signout':
        await GoogleSignIn.instance.signOut();
      case 'timer':
        await _scheduleTimer((msg['end'] as num?)?.toInt() ?? 0, '${msg['title'] ?? 'Next Up'}', '${msg['body'] ?? ''}');
      case 'open':
        final uri = Uri.tryParse('${msg['url'] ?? ''}');
        if (uri != null) await _openExternal(uri);
    }
  }

  // Google sign-in, then an access token for Calendar and Sheets, handed to the page.
  Future<void> _signIn() async {
    try {
      final account = await GoogleSignIn.instance.authenticate(scopeHint: scopes);
      final client = account.authorizationClient;
      final auth = await client.authorizationForScopes(scopes) ?? await client.authorizeScopes(scopes);
      // Google access tokens last an hour; the page treats them as expiring a little earlier.
      await _web.runJavaScript('window.nextUpNativeAuth(${jsonEncode(auth.accessToken)}, 3300)');
    } on GoogleSignInException catch (e) {
      final text = e.code == GoogleSignInExceptionCode.canceled ? 'Sign-in was cancelled.' : 'Sign-in failed: ${e.description ?? e.code.name}';
      await _web.runJavaScript('window.nextUpNativeAuth(null, 0, ${jsonEncode(text)})');
    } catch (e) {
      await _web.runJavaScript('window.nextUpNativeAuth(null, 0, ${jsonEncode('Sign-in failed: $e')})');
    }
  }

  Future<void> _scheduleTimer(int endMs, String title, String body) async {
    await _notifications.cancel(id: _timerNotificationId);
    if (endMs <= DateTime.now().millisecondsSinceEpoch) return;
    final android = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    final ios = _notifications.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(alert: true, sound: true);
    await _notifications.zonedSchedule(
      id: _timerNotificationId,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.fromMillisecondsSinceEpoch(tz.local, endMs),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails('timer', 'Focus timer',
            channelDescription: 'When a pomodoro or break ends', importance: Importance.high, priority: Priority.high),
        iOS: DarwinNotificationDetails(presentSound: true),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> _openExternal(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await Clipboard.setData(ClipboardData(text: uri.toString()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _web.canGoBack()) {
          await _web.goBack();
        } else {
          await SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(children: [
            WebViewWidget(controller: _web),
            if (_loading) const LinearProgressIndicator(),
            if (_loadError != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text("Couldn't load Next Up: $_loadError", textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () {
                        setState(() => _loadError = null);
                        _web.reload();
                      },
                      child: const Text('Try again'),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
