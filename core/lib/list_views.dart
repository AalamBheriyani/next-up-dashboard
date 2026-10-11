// Ways to look at the same deadlines: by urgency and importance, by priority, by due date, by list.
// Each view is a few titled groups; the screen decides how to draw them.
import 'deadline.dart';

class ListGroup {
  const ListGroup(this.title, this.items, {this.hint = ''});
  final String title;
  final String hint; // one short line that says what belongs here
  final List<Deadline> items;
}

enum ListViewKind { matrix, priority, due, list }

const listViewNames = {ListViewKind.matrix: 'Urgent / Important', ListViewKind.priority: 'Priority', ListViewKind.due: 'Due date', ListViewKind.list: 'By list'};

/// Urgent means late or due within two days.
bool isUrgent(Deadline d, DateTime now) => d.due.difference(now) < const Duration(hours: 48);

/// Important means TickTick priority medium or high.
bool isImportant(Deadline d) => d.priority >= 3;

List<Deadline> _byDue(Iterable<Deadline> xs) => xs.toList()..sort((a, b) => a.due.compareTo(b.due));

List<ListGroup> groupsFor(ListViewKind kind, List<Deadline> all, DateTime now) {
  switch (kind) {
    case ListViewKind.matrix:
      List<Deadline> pick(bool urgent, bool important) => _byDue(all.where((d) => isUrgent(d, now) == urgent && isImportant(d) == important));
      return [
        ListGroup('Do first', pick(true, true), hint: 'Urgent and important'),
        ListGroup('Schedule', pick(false, true), hint: 'Important, not urgent'),
        ListGroup('Quick wins', pick(true, false), hint: 'Urgent, not important'),
        ListGroup('Later', pick(false, false), hint: 'Not urgent, not important'),
      ];
    case ListViewKind.priority:
      List<Deadline> p(bool Function(int) f) => _byDue(all.where((d) => f(d.priority)));
      return [
        ListGroup('High', p((x) => x >= 5)),
        ListGroup('Medium', p((x) => x >= 3 && x < 5)),
        ListGroup('Low', p((x) => x > 0 && x < 3)),
        ListGroup('No priority', p((x) => x <= 0)),
      ];
    case ListViewKind.due:
      final g = DeadlineGroups(all, now);
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      bool isTomorrow(Deadline d) => d.due.year == tomorrow.year && d.due.month == tomorrow.month && d.due.day == tomorrow.day;
      final week = g.thisWeek(now);
      return [
        ListGroup('Overdue', g.overdue, hint: 'Oldest first'),
        ListGroup('Today', g.today(now)),
        ListGroup('Tomorrow', g.upcoming.where(isTomorrow).toList()),
        ListGroup('This week', week.where((d) => !isTomorrow(d)).toList()),
        ListGroup('Later', g.later(now)),
      ];
    case ListViewKind.list:
      final names = <String>[];
      for (final d in _byDue(all)) {
        final n = d.list.isEmpty ? 'No list' : d.list;
        if (!names.contains(n)) names.add(n);
      }
      names.sort((a, b) => a == 'No list' ? 1 : b == 'No list' ? -1 : a.toLowerCase().compareTo(b.toLowerCase()));
      return [for (final n in names) ListGroup(n, _byDue(all.where((d) => (d.list.isEmpty ? 'No list' : d.list) == n)))];
  }
}
