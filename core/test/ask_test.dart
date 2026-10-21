import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_core/ask_claude.dart';

class _Tools implements AskTools {
  final done = <String>[];
  final timers = <String>[];
  @override
  Future<String> completeTask(String id) async {
    done.add(id);
    return 'Chem quiz';
  }

  @override
  int startTimer(int minutes, String label) {
    timers.add('$minutes $label');
    return minutes;
  }
}

class _Transport implements AskTransport {
  _Transport({this.replies = const [], this.online = true, this.answers = const []});
  final List<Map<String, dynamic>> replies;
  final List<Map<String, dynamic>> answers;
  final bool online;
  final bodies = <Map<String, dynamic>>[];
  final prompts = <String>[];
  @override
  Future<Map<String, dynamic>> claude(Map<String, dynamic> body) async {
    bodies.add(body);
    return replies[bodies.length - 1];
  }

  @override
  Future<bool> relayOnline() async => online;
  @override
  Future<String> relayAsk(String prompt) async {
    prompts.add(prompt);
    return 'q1';
  }

  @override
  Future<Map<String, dynamic>> relayAnswer(String id) async => answers.removeAt(0);
}

void main() {
  test('api mode runs the tools Claude asks for, then returns its answer', () async {
    final t = _Transport(replies: [
      {'stop_reason': 'tool_use', 'content': [{'type': 'tool_use', 'id': 'x', 'name': 'complete_task', 'input': {'task_id': 'abc'}}]},
      {'stop_reason': 'end_turn', 'content': [{'type': 'text', 'text': 'Done. Next: Math.'}]},
    ]);
    final tools = _Tools();
    final r = await AskService(transport: t, mode: AskMode.api).ask('I finished the quiz', [], 'SNAPSHOT', tools);
    expect(tools.done, ['abc']);
    expect(r.text, 'Done. Next: Math.');
    expect(r.notes, ['Marked done: Chem quiz']);
    expect((t.bodies.first['system'] as String).contains('SNAPSHOT'), isTrue);
    expect((t.bodies.last['messages'] as List).length, 3); // question, tool call, tool result
  });

  test('relay mode strips ACTION lines and runs them', () async {
    final t = _Transport(answers: [
      {'state': 'working'},
      {'state': 'done', 'text': 'Start now.\nACTION start_timer 25 chem notes', 'error': ''},
    ]);
    final tools = _Tools();
    final r = await AskService(transport: t, mode: AskMode.relay, pollEvery: Duration.zero).ask('help', const [ChatTurn('user', 'hi')], 'SNAP', tools);
    expect(r.text, 'Start now.');
    expect(tools.timers, ['25 chem notes']);
    expect(t.prompts.single, contains('Earlier in this chat:\nUser: hi'));
  });

  test('an offline relay falls back to opening Claude with the context', () async {
    final r = await AskService(transport: _Transport(online: false), mode: AskMode.relay).ask('plan my day', [], 'TASKS', _Tools());
    expect(r.openUrl, startsWith('https://claude.ai/new?q='));
    expect(Uri.decodeQueryComponent(r.openUrl!), contains('TASKS'));
    expect(r.notes.single, contains('offline'));
  });

  test('app mode needs no server at all', () async {
    final r = await AskService(transport: _Transport(), mode: AskMode.app).ask('hi', [], 'S', _Tools());
    expect(r.openUrl, isNotNull);
    expect(r.notes, isEmpty);
  });
}
