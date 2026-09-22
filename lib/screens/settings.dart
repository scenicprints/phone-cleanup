import 'package:flutter/material.dart';

import '../app_state.dart';
import '../bytes.dart';
import '../history.dart';
import '../models.dart';
import '../native.dart';
import '../theme.dart';
import '../updater.dart';

// ═══════════════════════════════════════════════════════════════════════
// SETTINGS
//
// Updates, the two permissions, the numbers the finders work to, and a short
// record of past scans so "it is filling up again" has evidence behind it.
// ═══════════════════════════════════════════════════════════════════════

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState s = AppScope.of(context);

    return AppScaffold(
      title: 'Settings',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
        children: <Widget>[
          UpdateCard(known: s.update),
          const SectionLabel('Permissions'),
          _Permission(
            label: 'All files access',
            granted: s.hasAllFiles,
            explains: 'Lets the scanner see shared storage. Without it every '
                'number in the app reads zero.',
            onOpen: Native.openAllFilesAccess,
          ),
          const SizedBox(height: 10),
          _Permission(
            label: 'Usage access',
            granted: s.hasUsage,
            explains: 'Lets the Apps tab read how much room each app is using, '
                'the same figures Settings shows.',
            onOpen: Native.openUsageAccess,
          ),
          const SectionLabel('What the finders count as old or large'),
          _Thresholds(state: s),
          const SectionLabel('Past scans'),
          const _Historic(),
          const SectionLabel('What this app cannot do'),
          const _Limits(),
        ],
      ),
    );
  }
}

class _Permission extends StatelessWidget {
  final String label;
  final bool granted;
  final String explains;
  final VoidCallback onOpen;

  const _Permission({
    required this.label,
    required this.granted,
    required this.explains,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
                granted ? Icons.check_circle_rounded : Icons.cancel_outlined,
                size: 18,
                color: granted ? kGood : kDanger),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: sans(size: 14, weight: FontWeight.w700)),
                const SizedBox(height: 5),
                Text(explains,
                    style: sans(size: 12, color: kDim, height: 1.5)),
                if (!granted) ...<Widget>[
                  const SizedBox(height: 12),
                  GhostButton(label: 'Grant it', onPressed: onOpen),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Thresholds extends StatelessWidget {
  final AppState state;

  const _Thresholds({required this.state});

  @override
  Widget build(BuildContext context) {
    final FinderOptions o = state.options;
    return Panel(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
      child: Column(
        children: <Widget>[
          _Choice<int>(
            label: 'A large video is over',
            value: o.largeVideoMinBytes,
            options: const <int>[100 * kMB, 200 * kMB, 300 * kMB, 500 * kMB, kGB],
            render: formatBytes,
            onChanged: (int v) =>
                state.setOptions(o.copyWith(largeVideoMinBytes: v)),
          ),
          _Choice<int>(
            label: 'A big file is over',
            value: o.bigFileMinBytes,
            options: const <int>[50 * kMB, 100 * kMB, 250 * kMB, 500 * kMB],
            render: formatBytes,
            onChanged: (int v) =>
                state.setOptions(o.copyWith(bigFileMinBytes: v)),
          ),
          _Choice<int>(
            label: 'A screenshot is old after',
            value: o.screenshotAgeDays,
            options: const <int>[30, 60, 90, 180, 365],
            render: (int d) => d >= 365 ? 'a year' : '$d days',
            onChanged: (int v) =>
                state.setOptions(o.copyWith(screenshotAgeDays: v)),
          ),
          _Choice<int>(
            label: 'A download is old after',
            value: o.downloadAgeDays,
            options: const <int>[14, 30, 60, 120, 365],
            render: (int d) => d >= 365 ? 'a year' : '$d days',
            onChanged: (int v) =>
                state.setOptions(o.copyWith(downloadAgeDays: v)),
          ),
          _Choice<int>(
            label: 'Compare files for duplicates from',
            value: o.dupMinBytes,
            options: const <int>[256 * kKB, kMB, 5 * kMB, 20 * kMB],
            render: formatBytes,
            onChanged: (int v) => state.setOptions(o.copyWith(dupMinBytes: v)),
          ),
          const SizedBox(height: 8),
          Text('Changes take effect on the next scan.',
              style: sans(size: 11, color: kFaint)),
        ],
      ),
    );
  }
}

class _Choice<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> options;
  final String Function(T) render;
  final ValueChanged<T> onChanged;

  const _Choice({
    required this.label,
    required this.value,
    required this.options,
    required this.render,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: sans(size: 13)),
          const SizedBox(height: 9),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: options.map((T o) {
              final bool on = o == value;
              return InkWell(
                onTap: () => onChanged(o),
                borderRadius: BorderRadius.circular(7),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: on ? kAccent.withValues(alpha: 0.16) : kSurfaceHi,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: on ? kAccent : kLine),
                  ),
                  child: Text(render(o),
                      style: mono(
                          size: 11.5,
                          color: on ? kAccent : kDim,
                          weight: on ? FontWeight.w700 : FontWeight.w500)),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _Historic extends StatelessWidget {
  const _Historic();

  @override
  Widget build(BuildContext context) {
    final AppState s = AppScope.of(context);
    final List<Snapshot> snaps = s.store.snapshots.reversed.take(10).toList();

    if (snaps.isEmpty) {
      return Panel(
        child: Text(
            'Nothing recorded yet. After the second scan this becomes a record '
            'of what changed between them.',
            style: sans(size: 12.5, color: kDim, height: 1.55)),
      );
    }

    return Panel(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Column(
        children: snaps.map((Snapshot snap) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(formatDate(snap.when), style: sans(size: 12.5)),
                      const SizedBox(height: 2),
                      Text(
                          '${formatCount(snap.scannedFiles)} files scanned',
                          style: sans(size: 10.5, color: kFaint)),
                    ],
                  ),
                ),
                Text('${formatBytes(snap.volumeFree)} free',
                    style: mono(
                        size: 12,
                        color: pressureColour(snap.volumeTotal == 0
                            ? 0
                            : snap.volumeUsed / snap.volumeTotal))),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _Limits extends StatelessWidget {
  const _Limits();

  @override
  Widget build(BuildContext context) {
    const List<List<String>> rows = <List<String>>[
      <String>[
        'Clear another app\'s cache',
        'Android removed that for every app in version 11. The Apps tab '
            'measures each cache and takes you to the button that clears it.',
      ],
      <String>[
        'Read inside Android/data and Android/obb',
        'Blocked for every app, All files access or not. Whatever is in there '
            'is counted by the Apps tab instead, through a different API.',
      ],
      <String>[
        'Delete anything on its own',
        'By design, not by limitation. Nothing is ticked for you and nothing '
            'goes without a confirmation naming the count and the space.',
      ],
      <String>[
        'Recover what it deleted',
        'There is no undo and no holding area. A holding area would free no '
            'space, which is the whole reason you opened this.',
      ],
    ];

    return Panel(
      child: Column(
        children: rows.map((List<String> r) {
          final bool last = r == rows.last;
          return Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(r[0], style: sans(size: 13, weight: FontWeight.w700)),
                const SizedBox(height: 5),
                Text(r[1], style: sans(size: 12, color: kDim, height: 1.55)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
