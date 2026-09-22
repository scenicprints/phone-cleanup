import 'package:flutter/material.dart';

import '../app_state.dart';
import '../bytes.dart';
import '../models.dart';
import '../selection.dart';
import '../theme.dart';
import '../widgets.dart';

// ═══════════════════════════════════════════════════════════════════════
// CLEAN
//
// Every finder's result, and the only place anything is deleted. Nothing is
// ticked when you arrive, and the running total at the bottom is the only
// promise the app makes about what a delete will free.
// ═══════════════════════════════════════════════════════════════════════

class FindsTab extends StatelessWidget {
  const FindsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState s = AppScope.of(context);
    final ScanResult? r = s.scan;

    return TabPage(
      title: 'Clean',
      subtitle: r == null
          ? null
          : '${r.groups.length} ${r.groups.length == 1 ? 'finder' : 'finders'}, '
              '${formatBytes(r.reclaimable)} in total',
      child: Column(
        children: <Widget>[
          Expanded(child: _body(context, s, r)),
          const SelectionBar(),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, AppState s, ScanResult? r) {
    if (!s.hasAllFiles) {
      return const SingleChildScrollView(child: PermissionGate());
    }
    if (r == null) {
      return const Empty(
        icon: Icons.search_rounded,
        text: 'Nothing has been scanned yet.\nRun a scan from the Storage tab.',
      );
    }
    if (r.groups.isEmpty) {
      return const Empty(
        icon: Icons.check_rounded,
        text: 'No finder turned anything up.\n\nThat is a real answer, not an '
            'empty screen: the space is going on files you chose to keep. The '
            'Folders and Apps tabs show where.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      itemCount: r.groups.length,
      itemBuilder: (BuildContext ctx, int i) {
        final FindGroup g = r.groups[i];
        final int ticked = s.selection.countIn(g);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Panel(
            onTap: () => Navigator.of(ctx).push<void>(MaterialPageRoute<void>(
                builder: (_) => GroupScreen(groupId: g.id))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(g.title,
                          style: sans(size: 15, weight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 10),
                    Text(formatBytes(g.bytes),
                        style: mono(
                            size: 13,
                            color: kAccent,
                            weight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 7),
                Text(g.why,
                    style: sans(size: 12, color: kDim, height: 1.5),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 11),
                Row(
                  children: <Widget>[
                    Text('${formatCount(g.count)} items',
                        style: sans(size: 11, color: kFaint)),
                    if (ticked > 0) ...<Widget>[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                            color: kAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(5)),
                        child: Text('$ticked ticked',
                            style: sans(
                                size: 10,
                                color: kAccent,
                                weight: FontWeight.w700)),
                      ),
                    ],
                    const Spacer(),
                    const Icon(Icons.chevron_right_rounded,
                        size: 18, color: kFaint),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── One finder's list ─────────────────────────────────────────────────

class GroupScreen extends StatefulWidget {
  final String groupId;

  const GroupScreen({super.key, required this.groupId});

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  @override
  Widget build(BuildContext context) {
    final AppState s = AppScope.of(context);
    final FindGroup? g = s.scan?.group(widget.groupId);

    if (g == null) {
      return AppScaffold(
        title: 'Gone',
        body: const Empty(
            icon: Icons.done_rounded,
            text: 'Everything this finder listed has been dealt with.'),
      );
    }

    final int ticked = s.selection.countIn(g);

    return AppScaffold(
      title: g.title,
      subtitle: '${formatCount(g.count)} items, ${formatBytes(g.bytes)}',
      actions: <Widget>[
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, size: 20),
          color: kSurfaceHi,
          onSelected: (String v) => _bulk(s, g, v),
          itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
                value: 'all',
                child: Text('Tick everything', style: sans(size: 13))),
            if (g.id == 'duplicates')
              PopupMenuItem<String>(
                  value: 'dupes',
                  child: Text('Tick all but the oldest of each set',
                      style: sans(size: 13))),
            PopupMenuItem<String>(
                value: 'none',
                child: Text('Untick everything', style: sans(size: 13))),
          ],
        ),
      ],
      bottomBar: ticked == 0 ? null : const _GroupBar(),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: g.items.length + 1,
        itemBuilder: (BuildContext ctx, int i) {
          if (i == 0) {
            return _Preamble(group: g);
          }
          final FindItem it = g.items[i - 1];
          return FileRow(
            path: it.path,
            size: it.size,
            note: it.note,
            isDir: it.isDir,
            selected: s.selection.has(it.path),
            onTap: () => s.selection.toggle(it),
          );
        },
      ),
    );
  }

  void _bulk(AppState s, FindGroup g, String what) {
    switch (what) {
      case 'all':
        s.selection.addAll(g.items);
      case 'none':
        s.selection.removeAll(g.items);
      case 'dupes':
        // Keep the first row of every set, which the finder sorted to be the
        // oldest and shortest-pathed copy, and tick the rest.
        final Set<String> seen = <String>{};
        final List<FindItem> rest = <FindItem>[];
        for (final FindItem i in g.items) {
          final String key = i.setKey ?? i.path;
          if (seen.add(key)) {
            continue; // the keeper
          }
          rest.add(i);
        }
        s.selection.addAll(rest);
    }
  }
}

class _Preamble extends StatelessWidget {
  final FindGroup group;

  const _Preamble({required this.group});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Panel(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(group.why, style: sans(size: 12.5, color: kDim, height: 1.55)),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                    group.risky
                        ? Icons.warning_amber_rounded
                        : Icons.info_outline_rounded,
                    size: 15,
                    color: group.risky ? kAccent : kFaint),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(group.caution,
                      style: sans(
                          size: 11.5,
                          color: group.risky ? kAccent : kFaint,
                          height: 1.55)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupBar extends StatelessWidget {
  const _GroupBar();

  @override
  Widget build(BuildContext context) {
    return const SelectionBar(inBar: true);
  }
}

// ── The running total, and the delete ─────────────────────────────────

class SelectionBar extends StatelessWidget {
  /// True when already inside AppScaffold's bottom bar, which has drawn the
  /// surface and reserved the gesture bar itself.
  final bool inBar;

  const SelectionBar({super.key, this.inBar = false});

  @override
  Widget build(BuildContext context) {
    final AppState s = AppScope.of(context);

    if (s.phase == Phase.deleting) {
      final double f = s.deleteTotal == 0 ? 0 : s.deleteDone / s.deleteTotal;
      final Widget body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Deleting ${s.deleteDone} of ${s.deleteTotal}',
              style: sans(size: 13, weight: FontWeight.w600)),
          const SizedBox(height: 9),
          Bar(fraction: f, colour: kDanger),
        ],
      );
      return inBar ? body : _wrap(context, body);
    }

    if (s.selection.isEmpty) {
      return const SizedBox.shrink();
    }

    final Widget body = Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(formatBytes(s.selection.bytes),
                  style: mono(
                      size: 17, weight: FontWeight.w700, color: kAccent)),
              const SizedBox(height: 2),
              Text(
                  '${formatCount(s.selection.count)} '
                  '${s.selection.count == 1 ? 'item' : 'items'} ticked',
                  style: sans(size: 11, color: kFaint)),
            ],
          ),
        ),
        TextButton(
          onPressed: s.selection.clear,
          child: Text('Clear',
              style: sans(size: 13, color: kDim, weight: FontWeight.w600)),
        ),
        const SizedBox(width: 6),
        ElevatedButton(
          onPressed: () => _delete(context, s),
          style: ElevatedButton.styleFrom(
            backgroundColor: kDanger,
            foregroundColor: Colors.black,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text('Delete',
              style: sans(
                  size: 13.5, weight: FontWeight.w700, color: Colors.black)),
        ),
      ],
    );

    return inBar ? body : _wrap(context, body);
  }

  Widget _wrap(BuildContext context, Widget child) {
    return Container(
      decoration: const BoxDecoration(
        color: kSurface,
        border: Border(top: BorderSide(color: kLine)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: child,
    );
  }

  Future<void> _delete(BuildContext context, AppState s) async {
    final List<FindGroup> groups = s.scan?.groups ?? <FindGroup>[];

    // Only warn about the finders the selection actually touches.
    final Set<String> touched = <String>{};
    for (final FindGroup g in groups) {
      if (s.selection.countIn(g) > 0) {
        touched.add(g.caution);
      }
    }

    final List<FindItem> lastCopies = s.selection.lastCopyWarnings(groups);

    final bool ok = await confirmDelete(
      context,
      count: s.selection.count,
      bytes: s.selection.bytes,
      cautions: touched.toList(),
      lastCopies: lastCopies,
    );
    if (!ok || !context.mounted) {
      return;
    }

    final DeleteReport report = await s.deleteSelected();
    if (!context.mounted) {
      return;
    }
    await showDeleteReport(
      context,
      deleted: report.deleted,
      freed: report.freed,
      failures: report.failures
          .map((DeleteFailure f) => '${basename(f.path)}, ${f.reason}')
          .toList(),
    );
  }
}
