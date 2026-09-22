import 'package:flutter/material.dart';

import '../app_state.dart';
import '../bytes.dart';
import '../history.dart';
import '../models.dart';
import '../theme.dart';
import '../updater.dart';
import '../widgets.dart';
import 'browse.dart';
import 'settings.dart';

// ═══════════════════════════════════════════════════════════════════════
// STORAGE
//
// The ledger. What the phone holds, what changed since last time, and the
// one button that goes and finds out.
// ═══════════════════════════════════════════════════════════════════════

class OverviewTab extends StatelessWidget {
  const OverviewTab({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState s = AppScope.of(context);

    return TabPage(
      title: 'Storage',
      subtitle: s.scan == null
          ? 'Not scanned yet'
          : 'Scanned ${formatAge(s.scan!.finished)}',
      actions: <Widget>[
        IconButton(
          onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                  builder: (_) => const SettingsScreen())),
          icon: const Icon(Icons.tune_rounded, size: 21),
          color: kDim,
          tooltip: 'Settings',
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: <Widget>[
          if (s.update != null)
            UpdateBanner(
              release: s.update!,
              onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                      builder: (_) => const SettingsScreen())),
            ),
          const _Gauge(),
          const SizedBox(height: 18),
          if (!s.hasAllFiles) const PermissionGate(),
          if (s.hasAllFiles) const _ScanControl(),
          if (s.scan != null) ...<Widget>[
            const _Findings(),
            const _Growth(),
            const _Kinds(),
            const _TopFolders(),
            const _ScanFootnotes(),
          ],
          const _FreedAllTime(),
        ],
      ),
    );
  }
}

// ── The gauge ─────────────────────────────────────────────────────────

class _Gauge extends StatelessWidget {
  const _Gauge();

  @override
  Widget build(BuildContext context) {
    final AppState s = AppScope.of(context);
    final VolumeInfoLike v = VolumeInfoLike(s.volume.total, s.volume.free);
    final Color c = pressureColour(v.fraction);

    return Panel(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text('FREE', style: kLabel),
                  const SizedBox(height: 7),
                  Text(v.total == 0 ? '...' : formatBytes(v.free),
                      style: mono(size: 30, weight: FontWeight.w600, color: c)),
                ],
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                    v.total == 0
                        ? ''
                        : '${(v.fraction * 100).round()}% full',
                    style: sans(size: 13, color: kDim, weight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Bar(fraction: v.fraction, colour: c, height: 7),
          const SizedBox(height: 10),
          Text(
              v.total == 0
                  ? 'Reading the volume'
                  : '${formatBytes(v.used)} used of ${formatBytes(v.total)}',
              style: sans(size: 12, color: kFaint)),
        ],
      ),
    );
  }
}

/// Small shim so the gauge does not depend on the native class shape.
class VolumeInfoLike {
  final int total;
  final int free;

  const VolumeInfoLike(this.total, this.free);

  int get used => total - free;

  double get fraction => total == 0 ? 0 : used / total;
}

// ── Scan ──────────────────────────────────────────────────────────────

class _ScanControl extends StatelessWidget {
  const _ScanControl();

  @override
  Widget build(BuildContext context) {
    final AppState s = AppScope.of(context);

    if (s.phase == Phase.scanning) {
      final ScanProgress? p = s.progress;
      return Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: kAccent)),
                const SizedBox(width: 12),
                Text(p?.phase ?? 'Starting',
                    style: sans(size: 14, weight: FontWeight.w600)),
                const Spacer(),
                Text(p == null ? '' : formatCount(p.files),
                    style: mono(size: 12, color: kDim)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
                p == null || p.where.isEmpty
                    ? 'Walking shared storage'
                    : prettyPath(p.where),
                style: mono(size: 10.5, color: kFaint),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      );
    }

    if (s.scanError != null) {
      return Panel(
        border: kDanger.withValues(alpha: 0.35),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('The scan stopped',
                style: sans(
                    size: 14, weight: FontWeight.w700, color: kDanger)),
            const SizedBox(height: 8),
            Text(s.scanError!,
                style: mono(size: 11, color: kDim), maxLines: 4),
            const SizedBox(height: 14),
            PrimaryButton(label: 'Try again', onPressed: s.startScan),
          ],
        ),
      );
    }

    return PrimaryButton(
      label: s.scan == null ? 'Scan storage' : 'Scan again',
      icon: Icons.search_rounded,
      onPressed: s.startScan,
    );
  }
}

// ── What the scan found ───────────────────────────────────────────────

class _Findings extends StatelessWidget {
  const _Findings();

  @override
  Widget build(BuildContext context) {
    final AppState s = AppScope.of(context);
    final ScanResult r = s.scan!;
    final int reclaimable = r.reclaimable;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 18),
        Panel(
          border: reclaimable > 0 ? kAccent.withValues(alpha: 0.3) : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('WORTH A LOOK', style: kLabel),
              const SizedBox(height: 10),
              Text(reclaimable == 0 ? 'Nothing found' : formatBytes(reclaimable),
                  style: mono(
                      size: 26,
                      weight: FontWeight.w600,
                      color: reclaimable > 0 ? kAccent : kDim)),
              const SizedBox(height: 8),
              Text(
                reclaimable == 0
                    ? 'None of the finders turned anything up. That is a real '
                        'result: the space is going on things you chose to keep.'
                    : 'Across ${r.groups.length} ${r.groups.length == 1 ? 'finder' : 'finders'}, '
                        'counting nothing twice. Open Clean to go through it.',
                style: sans(size: 12.5, color: kDim, height: 1.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Growth extends StatelessWidget {
  const _Growth();

  @override
  Widget build(BuildContext context) {
    final AppState s = AppScope.of(context);
    final List<Growth> growth = s.store.growthSincePrevious();
    final Snapshot? prev = s.store.previous;
    if (growth.isEmpty || prev == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionLabel('Grown since ${formatDate(prev.when)}'),
        Panel(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
          child: Column(
            children: growth.take(6).map((Growth g) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(prettyPath(g.path),
                          style: sans(size: 12.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 10),
                    Text('+${formatBytes(g.delta)}',
                        style: mono(
                            size: 12, color: kAccent, weight: FontWeight.w600)),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _Kinds extends StatelessWidget {
  const _Kinds();

  @override
  Widget build(BuildContext context) {
    final AppState s = AppScope.of(context);
    final ScanResult r = s.scan!;
    final List<MapEntry<Kind, int>> entries = r.byKind.entries.toList()
      ..sort((MapEntry<Kind, int> a, MapEntry<Kind, int> b) =>
          b.value.compareTo(a.value));
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionLabel('By kind'),
        Panel(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Column(
            children: entries
                .map((MapEntry<Kind, int> e) => Meter(
                      label: kindNames[e.key] ?? e.key.name,
                      bytes: e.value,
                      total: r.totalBytes,
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _TopFolders extends StatelessWidget {
  const _TopFolders();

  @override
  Widget build(BuildContext context) {
    final AppState s = AppScope.of(context);
    final ScanResult r = s.scan!;
    final List<DirRec> top = r.dirs.take(8).toList();
    if (top.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionLabel('Heaviest folders'),
        Panel(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Column(
            children: top
                .map((DirRec d) => Meter(
                      label: prettyPath(d.path),
                      bytes: d.bytes,
                      total: r.totalBytes,
                      onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                              builder: (_) => FolderScreen(path: d.path))),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _ScanFootnotes extends StatelessWidget {
  const _ScanFootnotes();

  @override
  Widget build(BuildContext context) {
    final AppState s = AppScope.of(context);
    final ScanResult r = s.scan!;
    final List<String> notes = <String>[
      '${formatCount(r.totalFiles)} files, ${formatBytes(r.totalBytes)}, '
          'read in ${r.took.inSeconds}s.',
      if (r.unreadable.isNotEmpty)
        '${r.unreadable.length} folders could not be read. Android blocks '
            'Android/data and Android/obb for every app, so the private data of '
            'other apps is not counted here. The Apps tab measures that instead.',
      if (r.truncated)
        'This phone holds more files than one scan can carry, so the tail of '
            'the walk was dropped. The numbers above are a floor, not a total.',
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: notes
            .map((String n) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(n,
                      style: sans(size: 11, color: kFaint, height: 1.55)),
                ))
            .toList(),
      ),
    );
  }
}

class _FreedAllTime extends StatelessWidget {
  const _FreedAllTime();

  @override
  Widget build(BuildContext context) {
    final AppState s = AppScope.of(context);
    final int freed = s.store.freedAllTime;
    if (freed <= 0) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Text('${formatBytes(freed)} freed with this app so far.',
          style: sans(size: 11, color: kFaint)),
    );
  }
}
