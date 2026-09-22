import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'bytes.dart';
import 'models.dart';

// ═══════════════════════════════════════════════════════════════════════
// HISTORY
//
// The half of the app that makes it worth keeping installed. A one-off
// scanner tells you what is there; a record of past scans tells you what
// has changed, which is the only thing that answers "why is it full again".
//
// Deliberately tiny: a few hundred bytes per scan, a couple of dozen kept.
// An app about storage that grows its own file without limit would be a joke.
// ═══════════════════════════════════════════════════════════════════════

const int kMaxSnapshots = 40;
const int kTopDirsKept = 25;

class Snapshot {
  final int whenMs;
  final int volumeTotal;
  final int volumeFree;
  final int scannedBytes;
  final int scannedFiles;
  final Map<Kind, int> byKind;

  /// The heaviest folders at the time, so growth can be attributed later.
  final Map<String, int> topDirs;

  const Snapshot({
    required this.whenMs,
    required this.volumeTotal,
    required this.volumeFree,
    required this.scannedBytes,
    required this.scannedFiles,
    required this.byKind,
    required this.topDirs,
  });

  DateTime get when => DateTime.fromMillisecondsSinceEpoch(whenMs);

  int get volumeUsed => volumeTotal - volumeFree;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'when': whenMs,
        'total': volumeTotal,
        'free': volumeFree,
        'bytes': scannedBytes,
        'files': scannedFiles,
        'kinds': byKind.map<String, int>(
            (Kind k, int v) => MapEntry<String, int>(k.name, v)),
        'dirs': topDirs,
      };

  factory Snapshot.fromJson(Map<String, dynamic> j) {
    final Map<Kind, int> kinds = <Kind, int>{};
    final dynamic rawKinds = j['kinds'];
    if (rawKinds is Map<dynamic, dynamic>) {
      rawKinds.forEach((dynamic k, dynamic v) {
        for (final Kind kind in Kind.values) {
          if (kind.name == k) {
            kinds[kind] = v is int ? v : 0;
          }
        }
      });
    }
    final Map<String, int> dirs = <String, int>{};
    final dynamic rawDirs = j['dirs'];
    if (rawDirs is Map<dynamic, dynamic>) {
      rawDirs.forEach((dynamic k, dynamic v) {
        if (k is String && v is int) {
          dirs[k] = v;
        }
      });
    }
    return Snapshot(
      whenMs: _int(j['when']),
      volumeTotal: _int(j['total']),
      volumeFree: _int(j['free']),
      scannedBytes: _int(j['bytes']),
      scannedFiles: _int(j['files']),
      byKind: kinds,
      topDirs: dirs,
    );
  }
}

class DeleteRecord {
  final int whenMs;
  final int count;
  final int freed;

  const DeleteRecord(
      {required this.whenMs, required this.count, required this.freed});

  DateTime get when => DateTime.fromMillisecondsSinceEpoch(whenMs);

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'when': whenMs, 'count': count, 'freed': freed};

  factory DeleteRecord.fromJson(Map<String, dynamic> j) => DeleteRecord(
        whenMs: _int(j['when']),
        count: _int(j['count']),
        freed: _int(j['freed']),
      );
}

/// One folder that got heavier between two scans.
class Growth {
  final String path;
  final int before;
  final int after;

  const Growth(this.path, this.before, this.after);

  int get delta => after - before;
}

class Store {
  Store._(this._file, this.snapshots, this.deletes, this.options);

  final File _file;
  List<Snapshot> snapshots;
  List<DeleteRecord> deletes;
  FinderOptions options;

  static Future<Store> open() async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File f = File('${dir.path}/history.json');
    List<Snapshot> snaps = <Snapshot>[];
    List<DeleteRecord> dels = <DeleteRecord>[];
    FinderOptions opts = const FinderOptions();
    try {
      if (f.existsSync()) {
        final Map<String, dynamic> j =
            jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        snaps = (j['snapshots'] as List<dynamic>? ?? <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(Snapshot.fromJson)
            .toList();
        dels = (j['deletes'] as List<dynamic>? ?? <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(DeleteRecord.fromJson)
            .toList();
        final dynamic o = j['options'];
        if (o is Map<String, dynamic>) {
          opts = FinderOptions.fromJson(o);
        }
      }
    } catch (_) {
      // A corrupt history is not worth refusing to start over. Begin again.
      snaps = <Snapshot>[];
      dels = <DeleteRecord>[];
    }
    return Store._(f, snaps, dels, opts);
  }

  Future<void> _save() async {
    try {
      await _file.writeAsString(jsonEncode(<String, dynamic>{
        'snapshots': snapshots.map((Snapshot s) => s.toJson()).toList(),
        'deletes': deletes.map((DeleteRecord d) => d.toJson()).toList(),
        'options': options.toJson(),
      }));
    } catch (_) {
      // Losing the history is a nuisance, never a reason to fail the action
      // that produced it.
    }
  }

  Future<void> setOptions(FinderOptions o) async {
    options = o;
    await _save();
  }

  Future<void> recordScan(ScanResult r, int volumeTotal, int volumeFree) async {
    final Map<String, int> top = <String, int>{};
    for (final DirRec d in r.dirs.take(kTopDirsKept)) {
      top[d.path] = d.bytes;
    }
    snapshots.add(Snapshot(
      whenMs: r.finishedMs,
      volumeTotal: volumeTotal,
      volumeFree: volumeFree,
      scannedBytes: r.totalBytes,
      scannedFiles: r.totalFiles,
      byKind: r.byKind,
      topDirs: top,
    ));
    if (snapshots.length > kMaxSnapshots) {
      snapshots.removeRange(0, snapshots.length - kMaxSnapshots);
    }
    await _save();
  }

  Future<void> recordDelete(int count, int freed) async {
    deletes.add(DeleteRecord(
        whenMs: DateTime.now().millisecondsSinceEpoch,
        count: count,
        freed: freed));
    if (deletes.length > 200) {
      deletes.removeRange(0, deletes.length - 200);
    }
    await _save();
  }

  Snapshot? get latest => snapshots.isEmpty ? null : snapshots.last;

  Snapshot? get previous =>
      snapshots.length < 2 ? null : snapshots[snapshots.length - 2];

  /// Total freed by every delete this app has done.
  int get freedAllTime {
    int t = 0;
    for (final DeleteRecord d in deletes) {
      t += d.freed;
    }
    return t;
  }

  /// Which folders got heavier since the scan before last. This is the
  /// question "what is filling my phone up again" in its literal form.
  List<Growth> growthSincePrevious() {
    final Snapshot? a = previous;
    final Snapshot? b = latest;
    if (a == null || b == null) {
      return <Growth>[];
    }
    final List<Growth> out = <Growth>[];
    b.topDirs.forEach((String path, int after) {
      final int before = a.topDirs[path] ?? 0;
      if (after - before > 50 * kMB) {
        out.add(Growth(path, before, after));
      }
    });
    out.sort((Growth x, Growth y) => y.delta.compareTo(x.delta));
    return out;
  }
}

int _int(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);
