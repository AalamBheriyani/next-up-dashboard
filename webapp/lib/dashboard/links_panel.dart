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
      // Static page in this site (webapp/web/kana): draw kana and kanji with the Apple Pencil; the owner's word list loads after sign-in.
      const QuickLink('Kana practice', 'https://aalambheriyani.github.io/next-up-dashboard/kana/', note: 'draw kana and kanji'),
      if (c.sheetId.isNotEmpty) QuickLink('Time Tracker', sheetLinkFor(c.sheetId), note: 'plan vs actual'),
      if (c.questSheetId.isNotEmpty) QuickLink('XP Tracker', sheetLinkFor(c.questSheetId), note: 'Quest Log sheet'),
      // The owner's GitHub, as on the old site's list.
      if (c.owner) const QuickLink('GitHub', 'https://github.com/AalamBheriyani', note: 'your repos'),
      ...c.links,
    ];

class LinksPanel extends StatelessWidget {
  const LinksPanel({super.key, required this.links, this.open});
  final List<QuickLink> links;
  final void Function(Uri)? open; // tests replace the browser

  @override
  Widget build(BuildContext context) {
    // An even grid of matching tiles (icon, name, what it is for) rather than chips of different widths.
    return Panel(
      title: 'Jump to',
      child: LayoutBuilder(builder: (context, box) {
        const gap = 8.0;
        final cols = (box.maxWidth / 130).floor().clamp(2, 4);
        final w = ((box.maxWidth - gap * (cols - 1)) / cols).floorToDouble();
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final l in links) SizedBox(width: w, child: _Tile(link: l, onTap: () => (open ?? (u) => launchUrl(u, webOnlyWindowName: '_blank'))(Uri.parse(l.url)))),
        ]);
      }),
    );
  }
}

IconData _iconFor(String name) => switch (name.toLowerCase()) {
      'ticktick' => Icons.task_alt_rounded,
      'calendar' => Icons.calendar_today_rounded,
      'time tracker' => Icons.timer_outlined,
      'xp tracker' => Icons.emoji_events_outlined,
      'github' => Icons.code_rounded,
      'kana practice' => Icons.draw_rounded,
      _ => Icons.north_east_rounded,
    };

class _Tile extends StatelessWidget {
  const _Tile({required this.link, required this.onTap});
  final QuickLink link;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: link.url,
      child: Material(
        color: NextUpColors.raised,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(children: [
              Icon(_iconFor(link.name), size: 18, color: NextUpColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(link.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(link.note.isEmpty ? Uri.parse(link.url).host : link.note, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
