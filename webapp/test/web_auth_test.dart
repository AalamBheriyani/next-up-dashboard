import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:next_up_core/session.dart';
import 'package:next_up_web/platform/platform_base.dart';
import 'package:next_up_web/web_auth.dart';

void main() {
  late MemoryStore store;
  late List<String> calls;
  late int status;
  late bool permanent;
  late List<String> navigated;
  var cleared = 0;

  WorkerSession worker() => WorkerSession(base: 'https://w', client: MockClient((r) async {
        calls.add('${r.method} ${r.url.path}');
        if (r.url.path == '/auth/info') return http.Response(jsonEncode({'permanent': permanent}), 200);
        if (r.url.path == '/auth/token') return status == 200 ? http.Response(jsonEncode({'access_token': 'tok${calls.length}', 'expires_in': 3599}), 200) : http.Response('no', status);
        return http.Response('{}', 200);
      }));

  WebAuth auth({String hash = ''}) => WebAuth(store: store, server: worker(), readHash: () => hash, clearAddressHash: () => cleared++, navigate: navigated.add);

  setUp(() {
    store = MemoryStore();
    calls = [];
    status = 200;
    permanent = true;
    navigated = [];
    cleared = 0;
  });

  test('coming back from sign-in saves the session and tidies the address', () async {
    final a = auth(hash: '#nu_session=nu_0123abcd');
    expect(store.get('nu.web.session'), 'nu_0123abcd');
    expect(cleared, 1);
    expect(a.signedIn, isTrue);
  });

  test('a reload keeps you signed in: the saved session is traded for a token once, then reused', () async {
    store.set('nu.web.session', 'nu_aa');
    final a = auth();
    expect(a.signedIn, isTrue, reason: 'signed in before any network call');
    final t1 = await Future.wait([a.token(), a.token()]);
    expect(t1, everyElement(startsWith('tok')));
    expect(calls.where((c) => c == 'POST /auth/token'), hasLength(1), reason: 'concurrent calls share one exchange');
    expect(await a.token(), t1.first, reason: 'a fresh token is reused');
  });

  test('an expired session signs you out; an unreachable Worker does not', () async {
    store.set('nu.web.session', 'nu_aa');
    status = 500;
    final a = auth();
    expect(await a.token(), isNull);
    expect(a.signedIn, isTrue, reason: 'the session is kept for next time');
    status = 401;
    expect(await a.token(), isNull);
    expect(a.signedIn, isFalse);
    expect(store.get('nu.web.session'), '');
  });

  test('signing in goes to the Worker when it can keep you signed in', () async {
    final a = auth();
    a.signIn(); // never completes: the page leaves
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(navigated, ['https://w/auth/start?return=beta']);
  });

  test('signing out forgets the session and tells the Worker', () async {
    store.set('nu.web.session', 'nu_aa');
    final a = auth()..signOut();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(a.signedIn, isFalse);
    expect(store.get('nu.web.session'), '');
    expect(calls, contains('POST /auth/logout'));
  });
}
