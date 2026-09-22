import 'dart:async';

import 'package:flutter/widgets.dart';

import 'history.dart';
import 'models.dart';
import 'native.dart';
import 'scan.dart';
import 'selection.dart';
import 'updater.dart';

// ═══════════════════════════════════════════════════════════════════════
// APP STATE
//
// One object, held above the whole tree. Small enough that a state package
// would be more code than the thing it manages.
// ═══════════════════════════════════════════════════════════════════════

enum Phase { loading, idle, scanning, deleting }

class AppState extends ChangeNotifier {
  Phase phase = Phase.loading;

  late Store store;
  VolumeInfo volume = VolumeInfo.empty;
  ScanResult? scan;
  ScanProgress? progress;
  String? scanError;

  List<AppEntry> apps = <AppEntry>[];
  bool appsLoaded = false;

  bool hasAllFiles = false;
  bool hasUsage = false;

  final Selection selection = Selection();
  ReleaseInfo? update;

  int deleteDone = 0;
  int deleteTotal = 0;

  FinderOptions get options => store.options;

  bool get everScanned => scan != null;

  Future<void> init() async {
    store = await Store.open();
    await Updater.loadCurrentVersion();
    await refreshPermissions();
    volume = await Native.volume();
    phase = Phase.idle;
    notifyListeners();

    // Never blocks the first paint, and never matters if it fails.
    unawaited(_checkUpdate());
  }

  Future<void> _checkUpdate() async {
    final ReleaseInfo? r = await Updater.checkQuietly();
    if (r != null) {
      update = r;
      notifyListeners();
    }
  }

  Future<void> refreshPermissions() async {
    hasAllFiles = await Native.hasAllFilesAccess();
    hasUsage = await Native.hasUsageAccess();
    notifyListeners();
  }

  Future<void> refreshVolume() async {
    volume = await Native.volume();
    notifyListeners();
  }

  Future<void> startScan() async {
    if (phase == Phase.scanning) {
      return;
    }
    await refreshPermissions();
    if (!hasAllFiles) {
      return;
    }
    phase = Phase.scanning;
    scanError = null;
    progress = null;
    selection.clear();
    notifyListeners();

    try {
      final Set<String> installed = await Native.installedPackages();
      final ScanResult r = await runScan(
        options: store.options,
        installedPackages: installed,
        onProgress: (ScanProgress p) {
          progress = p;
          notifyListeners();
        },
      );
      scan = r;
      volume = await Native.volume();
      await store.recordScan(r, volume.total, volume.free);
    } catch (e) {
      scanError = e.toString();
    }
    phase = Phase.idle;
    progress = null;
    notifyListeners();
  }

  Future<void> loadApps({bool force = false}) async {
    if (appsLoaded && !force) {
      return;
    }
    apps = await Native.apps();
    apps.sort((AppEntry a, AppEntry b) => b.total.compareTo(a.total));
    appsLoaded = true;
    notifyListeners();
  }

  Future<DeleteReport> deleteSelected() async {
    phase = Phase.deleting;
    deleteDone = 0;
    deleteTotal = selection.count;
    notifyListeners();

    final DeleteReport report = await Deleter.run(
      selection.items,
      onProgress: (int done, int total) {
        deleteDone = done;
        deleteTotal = total;
        notifyListeners();
      },
    );

    await store.recordDelete(report.deleted, report.freed);
    selection.clear();
    volume = await Native.volume();

    // Everything on screen was measured before the delete, so drop it rather
    // than leave rows pointing at files that are gone.
    _pruneScan();

    phase = Phase.idle;
    notifyListeners();
    return report;
  }

  /// Removes deleted paths from the in-memory scan so the lists stay honest
  /// without making the user sit through another full walk.
  void _pruneScan() {
    final ScanResult? r = scan;
    if (r == null) {
      return;
    }
    final Set<String> gone = <String>{};
    for (final FindItem i in selection.items) {
      gone.add(i.path);
    }
    if (gone.isEmpty) {
      return;
    }
    final List<FindGroup> groups = <FindGroup>[];
    for (final FindGroup g in r.groups) {
      final List<FindItem> kept =
          g.items.where((FindItem i) => !gone.contains(i.path)).toList();
      if (kept.isNotEmpty) {
        groups.add(FindGroup(
          id: g.id,
          title: g.title,
          why: g.why,
          caution: g.caution,
          items: kept,
          risky: g.risky,
        ));
      }
    }
    scan = ScanResult(
      startedMs: r.startedMs,
      finishedMs: r.finishedMs,
      totalFiles: r.totalFiles,
      totalBytes: r.totalBytes,
      byKind: r.byKind,
      dirs: r.dirs,
      biggest: r.biggest.where((FileRec f) => !gone.contains(f.path)).toList(),
      groups: groups,
      unreadable: r.unreadable,
      truncated: r.truncated,
    );
  }

  Future<void> setOptions(FinderOptions o) async {
    await store.setOptions(o);
    notifyListeners();
  }
}

/// Puts [AppState] in the tree and rebuilds anything that reads it.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) {
    final AppScope? scope =
        context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this widget.');
    return scope!.notifier!;
  }

  /// Reads the state without subscribing, for callbacks that only act on it.
  static AppState read(BuildContext context) {
    final AppScope? scope =
        context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this widget.');
    return scope!.notifier!;
  }
}
