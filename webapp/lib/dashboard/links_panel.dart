// "Jump to": quick links to the places the day happens, as on the current site. TickTick and Calendar for
// everyone, your own sheets when you've added them, and the owner's own links from the Worker.
import 'package:flutter/material.dart';
import 'package:next_up_core/theme.dart';
import 'package:next_up_core/worker_api.dart';
import 'package:url_launcher/url_launcher.dart';

import '../pages/settings_screen.dart' show sheetLinkFor;
import 'panel.dart';

List<QuickLink> quickLinks(AppConfig c) => [
      const QuickLink('TickTick', 'https://ticktick.com/webapp/', note: 'main task list'),
      const QuickLink('Calendar', 'https://calendar.google.com/calendar/r/day', note: "today's blocks"),
      if (c.sheetId.isNotEmpty) QuickLink('Time Tracker', sheetLinkFor(c.sheetId), note: 'plan vs actual'),
      if (c.questSheetId.isNotEmpty) QuickLink('XP Tracker', sheetLinkFor(c.questSheetId), note: 'Quest Log sheet'),
      ...c.links,
    ];

class LinksPanel extends StatelessWidget {
  const LinksPanel({super.key, required this.links, this.open});
  final List<QuickLink> links;
  final void Function(Uri)? open; // tests replace the browser

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'Jump to',
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final l in links)
          Tooltip(
            message: l.note.isEmpty ? l.url : l.note,
            child: ActionChip(
              avatar: Icon(Icons.north_east_rounded, size: 14, color: NextUpColors.accent),
              label: Text(l.name),
              backgroundColor: NextUpColors.raised,
              side: BorderSide.none,
              onPressed: () => (open ?? (u) => launchUrl(u, webOnlyWindowName: '_blank'))(Uri.parse(l.url)),
            ),
          ),
      ]),
    );
  }
}
