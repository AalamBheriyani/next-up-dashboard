// What the pages need from the outside world, in one place so tests can swap in fakes.
import 'package:next_up_core/calendar.dart';
import 'package:next_up_core/deadline_source.dart';
import 'package:next_up_core/hours.dart';
import 'package:next_up_core/sheets.dart';
import 'package:next_up_core/track.dart';
import 'package:next_up_core/worker_api.dart';

import 'web_auth.dart';

class Services {
  Services({
    required this.config,
    required this.deadlines,
    required this.calendar,
    required this.signedIn,
    required this.signIn,
    this.trackFactory,
    this.hoursFactory,
  });

  final ConfigSource config;
  final DeadlineSource deadlines;
  final CalendarSource calendar;
  final bool Function() signedIn;
  final Future<void> Function() signIn;
  /// Replaced in tests; the real ones read and write the person's own sheet.
  final TrackRepository Function(String sheetId)? trackFactory;
  final HoursRepository Function(String sheetId)? hoursFactory;

  TrackRepository? _trackCache;
  String _trackFor = '';
  TrackRepository trackFor(String sheetId) {
    if (_trackCache == null || _trackFor != sheetId) {
      _trackCache = trackFactory != null ? trackFactory!(sheetId) : SheetsTrackRepository(_sheets(sheetId));
      _trackFor = sheetId;
    }
    return _trackCache!;
  }

  HoursRepository hoursFor(String sheetId) => hoursFactory != null ? hoursFactory!(sheetId) : HoursRepository(_sheets(sheetId));

  SheetsApi? _api;
  String _apiFor = '';
  late final Future<String?> Function() _token;
  SheetsApi _sheets(String id) {
    if (_api == null || _apiFor != id) {
      _api = GoogleSheetsApi(_token, id);
      _apiFor = id;
    }
    return _api!;
  }

  /// The real services, all reading the signed-in person's token from [auth].
  factory Services.live(WebAuth auth, Future<void> Function() signIn) {
    final s = Services(
      config: WorkerConfigSource(auth.token),
      deadlines: WorkerDeadlineSource(auth.token),
      calendar: GoogleCalendarSource(auth.token),
      signedIn: () => auth.signedIn,
      signIn: signIn,
    );
    s._token = auth.token;
    return s;
  }
}
