// Google Sheets over REST with the person's access token: the few calls Track, Adherence and Rate need.
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'deadline_source.dart';

abstract class SheetsApi {
  /// Cell values as text, rows of columns. Empty cells at the end of a row are left out, like Google does.
  Future<List<List<String>>> get(String range);
  Future<void> putRaw(String range, List<List<String>> values);
  Future<void> put(String range, List<List<Object>> values); // USER_ENTERED, so numbers stay numbers
  /// Appends rows after the table in [range] and returns the 1-based first row they landed on (0 if unknown).
  Future<int> append(String range, List<List<String>> values);
  Future<List<String>> tabs();
  Future<void> addTab(String title);
}

class GoogleSheetsApi implements SheetsApi {
  GoogleSheetsApi(this.token, this.sheetId);
  final Future<String?> Function() token;
  final String sheetId;

  Uri _uri(String path, [Map<String, String>? q]) =>
      Uri.https('sheets.googleapis.com', '/v4/spreadsheets/$sheetId$path', q);

  Future<Map<String, dynamic>> _call(String method, Uri uri, {Object? body}) async {
    if (sheetId.isEmpty) throw SourceException('Add your Time Tracker sheet in Settings first.');
    final t = await token();
    if (t == null) throw SourceException('Sign in to use your sheets.', signedOut: true);
    final h = {'Authorization': 'Bearer $t', if (body != null) 'Content-Type': 'application/json'};
    http.Response res;
    try {
      res = switch (method) {
        'GET' => await http.get(uri, headers: h),
        'PUT' => await http.put(uri, headers: h, body: jsonEncode(body)),
        _ => await http.post(uri, headers: h, body: jsonEncode(body)),
      };
    } on http.ClientException {
      throw SourceException("Can't reach Google Sheets. Check your connection.");
    }
    if (res.statusCode == 401) throw SourceException('Your sign-in expired. Sign in again.', signedOut: true);
    if (res.statusCode == 403) throw SourceException('Google blocked access to that sheet. Sign in again and allow Sheets, or ask the owner to share it with you.', signedOut: true);
    if (res.statusCode == 404) throw SourceException("That sheet wasn't found. Check the link in Settings.");
    if (res.statusCode >= 400) throw SourceException('Sheets failed (${res.statusCode}).');
    final text = utf8.decode(res.bodyBytes);
    return text.isEmpty ? {} : jsonDecode(text) as Map<String, dynamic>;
  }

  @override
  Future<List<List<String>>> get(String range) async {
    final d = await _call('GET', _uri('/values/${Uri.encodeComponent(range)}'));
    return [
      for (final r in (d['values'] as List? ?? const [])) [for (final c in (r as List)) '$c'],
    ];
  }

  @override
  Future<void> putRaw(String range, List<List<String>> values) =>
      _call('PUT', _uri('/values/${Uri.encodeComponent(range)}', {'valueInputOption': 'RAW'}), body: {'range': range, 'values': values});

  @override
  Future<void> put(String range, List<List<Object>> values) =>
      _call('PUT', _uri('/values/${Uri.encodeComponent(range)}', {'valueInputOption': 'USER_ENTERED'}), body: {'range': range, 'values': values});

  @override
  Future<int> append(String range, List<List<String>> values) async {
    final d = await _call('POST', _uri('/values/${Uri.encodeComponent(range)}:append', {'valueInputOption': 'RAW', 'insertDataOption': 'INSERT_ROWS'}), body: {'values': values});
    final r = (d['updates'] as Map?)?['updatedRange'] as String?;
    final m = RegExp(r'![A-Z]+(\d+)').firstMatch(r ?? '');
    return m == null ? 0 : int.parse(m[1]!);
  }

  @override
  Future<List<String>> tabs() async {
    final d = await _call('GET', _uri('', {'fields': 'sheets.properties.title'}));
    return [for (final s in (d['sheets'] as List? ?? const [])) '${((s as Map)['properties'] as Map)['title']}'];
  }

  @override
  Future<void> addTab(String title) => _call('POST', _uri(':batchUpdate'), body: {
        'requests': [
          {'addSheet': {'properties': {'title': title}}}
        ]
      });
}
