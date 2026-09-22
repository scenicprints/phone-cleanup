import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../bytes.dart';
import '../native.dart';
import '../theme.dart';
import '../widgets.dart';

// ═══════════════════════════════════════════════════════════════════════
// APPS
//
// The honest half of the app.
//
// No app has been able to clear another app's cache since Android 11. Any
// cleaner that claims to is clearing its own, or nothing. What is still
// possible is reading the exact numbers Settings reads, through
// StorageStatsManager, and putting you one tap from the button that does the
// clearing. So this tab measures, ranks, and hands off. It never pretends.
// ═══════════════════════════════════════════════════════════════════════

class AppsTab extends StatefulWidget {
  const AppsTab({super.key});

  @override
  State<AppsTab> createState() => _AppsTabState();
}

class _AppsTabState extends State<AppsTab> {
  bool _systemToo = false;

  @override
  Widget build(BuildContext context) {
    final AppState s = AppScope.of(context);

    if (!s.hasUsage) {
      return const TabPage(
          title: 'Apps', child: SingleChildScrollView(child: _UsageGate()));
    }

    if (!s.appsLoaded) {
      // After the frame, never during it: loadApps notifies listeners and a
      // notify inside build throws.
      WidgetsBinding.instance.addPostFrameCallback((_) => s.loadApps());
      return const TabPage(
        title: 'Apps',
        child: Center(
            child: SizedBox(
                width: 20,
                height: 20,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: kFaint))),
      );
    }

    final List<AppEntry> shown = s.apps
        .where((AppEntry a) => (_systemToo || !a.system) && a.total > 0)
        .toList();
    final int biggest = shown.isEmpty ? 0 : shown.first.total;
    final int cacheTotal =
        shown.fold<int>(0, (int t, AppEntry a) => t + a.cacheBytes);

    return TabPage(
      title: 'Apps',
      subtitle: '${shown.length} apps, '
          '${formatBytes(shown.fold<int>(0, (int t, AppEntry a) => t + a.total))}',
      actions: <Widget>[
        IconButton(
          onPressed: () {
            setState(() => _systemToo = !_systemToo);
          },
          icon: Icon(
              _systemToo
                  ? Icons.filter_alt_rounded
                  : Icons.filter_alt_outlined,
              size: 20),
          color: _systemToo ? kAccent : kDim,
          tooltip: _systemToo ? 'Hide system apps' : 'Show system apps',
        ),
        IconButton(
          onPressed: () => s.loadApps(force: true),
          icon: const Icon(Icons.refresh_rounded, size: 20),
          color: kDim,
          tooltip: 'Re-measure',
        ),
      ],
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 20),
        itemCount: shown.length + 1,
        itemBuilder: (BuildContext ctx, int i) {
          if (i == 0) {
            return _CacheNote(cacheTotal: cacheTotal);
          }
          final AppEntry a = shown[i - 1];
          return _AppRow(app: a, biggest: biggest);
        },
      ),
    );
  }
}

class _UsageGate extends StatelessWidget {
  const _UsageGate();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Panel(
        border: kAccent.withValues(alpha: 0.3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.bar_chart_rounded, size: 18, color: kAccent),
                const SizedBox(width: 10),
                Text('Usage access is off',
                    style: sans(size: 15, weight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'This is a separate grant from All files access, on a different '
              'settings screen. Without it Android will not tell any app how '
              'much room another app is using, and this tab can only see the '
              'size of the installed package, not its data or its cache.',
              style: sans(size: 13, color: kDim, height: 1.55),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Open the setting',
              icon: Icons.open_in_new_rounded,
              onPressed: Native.openUsageAccess,
            ),
            const SizedBox(height: 10),
            Text('Settings, Apps, Special app access, Usage access, Phone Cleanup.',
                style: sans(size: 11, color: kFaint, height: 1.5)),
          ],
        ),
      ),
    );
  }
}

class _CacheNote extends StatelessWidget {
  final int cacheTotal;

  const _CacheNote({required this.cacheTotal});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Panel(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text('CACHED DATA', style: kLabel),
                const Spacer(),
                Text(formatBytes(cacheTotal),
                    style: mono(
                        size: 13, color: kAccent, weight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Android has not let one app clear another app\'s cache since '
              'version 11, so this app cannot free that for you and will not '
              'pretend otherwise. It can ask the system to do it, and the '
              'system asks you.',
              style: sans(size: 12, color: kDim, height: 1.55),
            ),
            const SizedBox(height: 14),
            GhostButton(
              label: 'Ask Android to clear cached data',
              onPressed: () async {
                final bool ok = await Native.clearAllCaches();
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    backgroundColor: kSurfaceHi,
                    content: Text(
                        'This phone does not carry that screen. Clear caches '
                        'one app at a time from the rows below.',
                        style: sans(size: 12.5)),
                  ));
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  final AppEntry app;
  final int biggest;

  const _AppRow({required this.app, required this.biggest});

  @override
  Widget build(BuildContext context) {
    final double f = biggest == 0 ? 0 : app.total / biggest;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _sheet(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
          child: Row(
            children: <Widget>[
              _Icon(package: app.package),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(app.label,
                        style: sans(size: 13.5, weight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 5),
                    Bar(fraction: f, colour: kDim, height: 3),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(formatBytes(app.total),
                      style: mono(size: 12, weight: FontWeight.w600)),
                  if (app.cacheBytes > 0) ...<Widget>[
                    const SizedBox(height: 3),
                    Text('${formatBytes(app.cacheBytes)} cache',
                        style: mono(size: 10, color: kAccent)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _sheet(BuildContext context) {
    showAppSheet<void>(
      context,
      builder: (BuildContext ctx) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  _Icon(package: app.package, size: 34),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(app.label,
                            style: sans(size: 17, weight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text(app.package,
                            style: mono(size: 10.5, color: kFaint),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _Line('The app itself', app.appBytes, app.total),
              _Line('Its data', app.dataBytes, app.total),
              _Line('Its cache', app.cacheBytes, app.total, colour: kAccent),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Text('Total', style: sans(size: 13, weight: FontWeight.w700)),
                  const Spacer(),
                  Text(formatBytes(app.total),
                      style: mono(size: 14, weight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 22),
              PrimaryButton(
                label: 'Open its storage page',
                icon: Icons.open_in_new_rounded,
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Native.openAppStorage(app.package);
                },
              ),
              const SizedBox(height: 10),
              Text(
                'Clear cache and Clear storage live on that page. Clearing the '
                'cache is safe. Clearing storage signs you out and resets the '
                'app to how it was when you installed it.',
                style: sans(size: 11.5, color: kFaint, height: 1.55),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Line extends StatelessWidget {
  final String label;
  final int bytes;
  final int total;
  final Color colour;

  const _Line(this.label, this.bytes, this.total, {this.colour = kDim});

  @override
  Widget build(BuildContext context) {
    return Meter(label: label, bytes: bytes, total: total, colour: colour);
  }
}

/// The launcher icon, fetched once per row. Android caches these internally,
/// so the per-row channel call is cheap enough not to need a layer here.
class _Icon extends StatefulWidget {
  final String package;
  final double size;

  const _Icon({required this.package, this.size = 26});

  @override
  State<_Icon> createState() => _IconState();
}

class _IconState extends State<_Icon> {
  static final Map<String, Uint8List?> _cache = <String, Uint8List?>{};
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    if (_cache.containsKey(widget.package)) {
      _bytes = _cache[widget.package];
    } else {
      Native.appIcon(widget.package).then((Uint8List? b) {
        _cache[widget.package] = b;
        if (mounted) {
          setState(() => _bytes = b);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes == null) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Container(
          decoration: BoxDecoration(
              color: kSurfaceHi, borderRadius: BorderRadius.circular(6)),
        ),
      );
    }
    return Image.memory(_bytes!,
        width: widget.size, height: widget.size, filterQuality: FilterQuality.medium);
  }
}
