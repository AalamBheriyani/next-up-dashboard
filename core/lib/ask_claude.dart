// Ask Claude: a short chat that sees today's tasks and calendar. Three ways to answer, as on the current
// site: Claude through the server's API key, Claude Code on the owner's laptop through the relay, or (with
// neither) a Claude chat opened with the question and context filled in.
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'deadline_source.dart';

enum AskMode { api, relay, app }

AskMode askModeFor({required bool claudeApi, required bool relay}) => claudeApi ? AskMode.api : (relay ? AskMode.relay : AskMode.app);

class ChatTurn {
  const ChatTurn(this.role, this.text);
  final String role; // 'user' or 'assistant'
  final String text;
}

/// What Claude may do on the dashboard. The page supplies the real ones.
abstract class AskTools {
  Future<String> completeTask(String id); // returns the task's title
  int startTimer(int minutes, String label); // returns the minutes started
}

const planningRules = '''You are a planning coach built into the user's personal dashboard. Your job is to get them started on the right thing now and keep a sense of urgency without guilt.
Style: short and direct, at most 6 short lines unless asked for a plan. Lead with the one thing to do now and a concrete first step that takes under 2 minutes. Plain text, no headings. Never diagnose anything.''';

String systemPrompt({String name = '', String rules = ''}) => '$planningRules${name.isEmpty ? '' : "\nThe user's name is $name."}${rules.isEmpty ? '' : "\nTheir planning rules: $rules"}';

const apiToolNotes = '\nYou can call tools: complete_task to mark a task done (only when the user clearly says it is done), and start_timer to start the focus timer when the user agrees to start.';

const relayActions = '''
To act on the dashboard, put each action on its own last line, exactly like:
ACTION complete_task <task_id>   (only when the user clearly says the task is done)
ACTION start_timer <minutes> <optional label>   (when the user agrees to start)
Do not use any other tools.''';

const _toolDefs = [
  {
    'name': 'complete_task',
    'description': "Mark one of the user's TickTick tasks as done. Input: task_id from the task list (the value in square brackets). Returns {ok, title}.",
    'input_schema': {'type': 'object', 'properties': {'task_id': {'type': 'string'}}, 'required': ['task_id']},
  },
  {
    'name': 'start_timer',
    'description': "Start a pomodoro on the dashboard's focus timer. Input: minutes (1-60) and an optional short label. A short or long break follows. Returns the minutes started.",
    'input_schema': {'type': 'object', 'properties': {'minutes': {'type': 'number'}, 'label': {'type': 'string'}}, 'required': ['minutes']},
  },
];

class AskReply {
  const AskReply(this.text, {this.notes = const [], this.openUrl});
  final String text; // Claude's answer; empty when the answer is elsewhere
  final List<String> notes; // "Marked done: …", "Timer started: …"
  final String? openUrl; // app mode: a Claude chat to open
}

/// The calls the chat makes to the Worker, behind an interface so tests can fake them.
abstract class AskTransport {
  Future<Map<String, dynamic>> claude(Map<String, dynamic> body);
  Future<bool> relayOnline();
  Future<String> relayAsk(String prompt);
  Future<Map<String, dynamic>> relayAnswer(String id);
}

class WorkerAskTransport implements AskTransport {
  WorkerAskTransport(this.token);
  final Future<String?> Function() token;

  Future<Map<String, dynamic>> _call(String method, String path, {Object? body}) async {
    final t = await token();
    if (t == null) throw SourceException('Sign in to ask Claude.', signedOut: true);
    final headers = {'Authorization': 'Bearer $t', if (body != null) 'Content-Type': 'application/json'};
    final uri = Uri.parse(workerUrl + path);
    http.Response res;
    try {
      res = method == 'POST' ? await http.post(uri, headers: headers, body: jsonEncode(body)) : await http.get(uri, headers: headers);
    } on http.ClientException {
      throw SourceException("Can't reach Next Up. Check your connection.");
    }
    Map<String, dynamic> data = {};
    try {
      data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {}
    if (res.statusCode == 401) throw SourceException('Your sign-in expired. Sign in again.', signedOut: true);
    if (res.statusCode == 429) throw SourceException('Too many requests. Try again in a minute.');
    if (res.statusCode >= 400) {
      final e = data['error'];
      throw SourceException(e is Map ? '${e['message']}' : '${e ?? 'Something went wrong (${res.statusCode}).'}');
    }
    return data;
  }

  @override
  Future<Map<String, dynamic>> claude(Map<String, dynamic> body) => _call('POST', '/claude', body: body);
  @override
  Future<bool> relayOnline() async => (await _call('GET', '/relay/status'))['online'] == true;
  @override
  Future<String> relayAsk(String prompt) async => '${(await _call('POST', '/relay/ask', body: {'prompt': prompt}))['id']}';
  @override
  Future<Map<String, dynamic>> relayAnswer(String id) => _call('GET', '/relay/answer?id=${Uri.encodeQueryComponent(id)}');
}

class AskService {
  AskService({required this.transport, required this.mode, this.name = '', this.rules = '', this.pollEvery = const Duration(milliseconds: 1500), this.waitFor = const Duration(seconds: 170)});
  final AskTransport transport;
  final AskMode mode;
  final String name, rules;
  final Duration pollEvery, waitFor;

  /// Answers [text] given [history] (earlier turns, not including this one) and the page [snapshot].
  Future<AskReply> ask(String text, List<ChatTurn> history, String snapshot, AskTools tools) async {
    var m = mode;
    if (m == AskMode.relay && !await transport.relayOnline().catchError((_) => false)) m = AskMode.app;
    switch (m) {
      case AskMode.app:
        return AskReply('', openUrl: appUrl(text, snapshot), notes: [if (mode == AskMode.relay) 'Your laptop relay is offline, so this opens in Claude instead.']);
      case AskMode.relay:
        return _relay(text, history, snapshot, tools);
      case AskMode.api:
        return _api(text, history, snapshot, tools);
    }
  }

  /// A claude.ai chat prefilled with the question and the same context, trimmed to a link-friendly size.
  String appUrl(String text, String snapshot) {
    final intro = '${systemPrompt(name: name, rules: rules)}\nIf the user says a task is done, complete it with the TickTick connector. Task ids are in square brackets.';
    var prompt = '$text\n\n---\nContext from my Next Up dashboard:\n$intro\n\n$snapshot';
    if (prompt.length > 7000) prompt = '${prompt.substring(0, 7000)}\n(trimmed)';
    return 'https://claude.ai/new?q=${Uri.encodeQueryComponent(prompt)}';
  }

  Future<AskReply> _api(String text, List<ChatTurn> history, String snapshot, AskTools tools) async {
    final msgs = <Map<String, dynamic>>[
      for (final t in history) {'role': t.role, 'content': t.text},
      {'role': 'user', 'content': text},
    ];
    final notes = <String>[];
    var finalText = '';
    for (var round = 0; round < 5; round++) {
      final r = await transport.claude({'system': '${systemPrompt(name: name, rules: rules)}$apiToolNotes\n\n$snapshot', 'messages': msgs, 'tools': _toolDefs});
      final content = (r['content'] as List? ?? const []).whereType<Map>().toList();
      final texts = content.where((b) => b['type'] == 'text').map((b) => '${b['text']}').join('\n').trim();
      if (texts.isNotEmpty) finalText = texts;
      if (r['stop_reason'] == 'refusal') return AskReply(finalText.isEmpty ? "Claude couldn't answer that one. Try rephrasing." : finalText, notes: notes);
      if (r['stop_reason'] != 'tool_use') break;
      msgs.add({'role': 'assistant', 'content': content});
      final results = <Map<String, dynamic>>[];
      for (final b in content.where((x) => x['type'] == 'tool_use')) {
        try {
          final out = await _run('${b['name']}', (b['input'] as Map?)?.cast<String, dynamic>() ?? {}, tools, notes);
          results.add({'type': 'tool_result', 'tool_use_id': b['id'], 'content': jsonEncode(out)});
        } catch (e) {
          results.add({'type': 'tool_result', 'tool_use_id': b['id'], 'content': '$e', 'is_error': true});
        }
      }
      msgs.add({'role': 'user', 'content': results});
    }
    if (finalText.isEmpty) throw SourceException("Claude didn't reply. Send it again.");
    return AskReply(finalText, notes: notes);
  }

  Future<Map<String, Object?>> _run(String tool, Map<String, dynamic> input, AskTools tools, List<String> notes) async {
    switch (tool) {
      case 'complete_task':
        final title = await tools.completeTask('${input['task_id']}');
        notes.add('Marked done: $title');
        return {'ok': true, 'title': title};
      case 'start_timer':
        final label = input['label'] == null ? '' : '${input['label']}';
        final mins = tools.startTimer((input['minutes'] as num?)?.round() ?? 25, label);
        notes.add('Timer started: $mins min');
        return {'started': true, 'minutes': mins};
    }
    throw SourceException('Unknown tool $tool');
  }

  Future<AskReply> _relay(String text, List<ChatTurn> history, String snapshot, AskTools tools) async {
    final hist = history.map((t) => '${t.role == 'user' ? 'User' : 'You'}: ${t.text}').join('\n');
    final prompt = '${systemPrompt(name: name, rules: rules)}\n$relayActions\n\n$snapshot${hist.isEmpty ? '' : '\n\nEarlier in this chat:\n$hist'}\n\nUser: $text';
    final id = await transport.relayAsk(prompt);
    final until = DateTime.now().add(waitFor);
    while (DateTime.now().isBefore(until)) {
      await Future<void>.delayed(pollEvery);
      final a = await transport.relayAnswer(id);
      if (a['state'] == 'gone') throw SourceException("The laptop didn't pick up the question.");
      if (a['state'] != 'done') continue;
      if ('${a['error'] ?? ''}'.isNotEmpty) throw SourceException('Claude on the laptop failed: ${a['error']}');
      final keep = <String>[], notes = <String>[];
      for (final line in '${a['text']}'.split('\n')) {
        final m = RegExp(r'^ACTION\s+(complete_task|start_timer)\s+(\S+)\s*(.*)$').firstMatch(line.trim());
        if (m == null) {
          keep.add(line);
          continue;
        }
        try {
          await _run(m[1]!, m[1] == 'complete_task' ? {'task_id': m[2]} : {'minutes': double.tryParse(m[2]!) ?? 25, 'label': m[3]}, tools, notes);
        } catch (e) {
          notes.add('$e');
        }
      }
      return AskReply(keep.join('\n').trim(), notes: notes);
    }
    throw SourceException('The laptop is taking too long. Try again.');
  }
}
