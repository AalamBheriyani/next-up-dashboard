import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_core/sheets.dart';

void main() {
  test('ranges are encoded once, so Google can read them', () {
    expect(sheetsUri('abc', '/values/Log!A2:J600').toString(), 'https://sheets.googleapis.com/v4/spreadsheets/abc/values/Log!A2:J600');
    expect(sheetsUri('abc', '/values/Track!A1:E1:append', {'valueInputOption': 'RAW'}).toString(),
        'https://sheets.googleapis.com/v4/spreadsheets/abc/values/Track!A1:E1:append?valueInputOption=RAW');
    expect(sheetsUri('abc', '/values/My Log!A1').toString(), 'https://sheets.googleapis.com/v4/spreadsheets/abc/values/My%20Log!A1');
    expect(sheetsUri('abc', ':batchUpdate').toString(), 'https://sheets.googleapis.com/v4/spreadsheets/abc:batchUpdate');
    expect(sheetsUri('abc', '', {'fields': 'sheets.properties.title'}).toString(), 'https://sheets.googleapis.com/v4/spreadsheets/abc?fields=sheets.properties.title');
  });
}
