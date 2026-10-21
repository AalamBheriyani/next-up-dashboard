import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:next_up_core/session.dart';

void main() {
  WorkerSession with_(Future<http.Response> Function(http.Request) h) => WorkerSession(base: 'https://w', client: MockClient(h));

  test('a session is swapped for an access token', () async {
    final s = with_((r) async {
      expect(r.url.path, '/auth/token');
      expect(r.headers['Authorization'], 'Bearer nu_abc');
      return http.Response(jsonEncode({'access_token': 'tok', 'expires_in': 3599}), 200);
    });
    final e = await s.exchange('nu_abc');
    expect((e.token, e.expiresIn, e.expired), ('tok', 3599, false));
  });

  test('a rejected session is expired; a down Worker is not', () async {
    expect((await with_((_) async => http.Response('no', 401)).exchange('x')).expired, isTrue);
    final down = await with_((_) async => throw Exception('offline')).exchange('x');
    expect((down.token, down.expired), (null, false));
    expect((await with_((_) async => http.Response('', 500)).exchange('x')).expired, isFalse);
  });

  test('permanent sign-in is reported by the Worker, and false when it cannot be reached', () async {
    expect(await with_((_) async => http.Response('{"permanent":true}', 200)).permanent(), isTrue);
    expect(await with_((_) async => http.Response('{"permanent":false}', 200)).permanent(), isFalse);
    expect(await with_((_) async => throw Exception('x')).permanent(), isFalse);
    expect(with_((_) async => http.Response('', 200)).startUrl(), 'https://w/auth/start');
  });
}
