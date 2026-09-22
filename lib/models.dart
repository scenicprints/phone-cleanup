import 'bytes.dart';

// ═══════════════════════════════════════════════════════════════════════
// MODELS
//
// Shared by the scanner and the finders so neither has to import the other.
// Everything here is plain data: it crosses an isolate boundary by copy, so
// no closures, no handles, nothing that holds a file open.
// ═══════════════════════════════════════════════════════════════════════

class FileRec {
  final String path;
  final int size;
  final int mtime;

  const FileRec(this.path, this.size, this.mtime);

  DateTime get modified => DateTime.fromMillisecondsSinceEpoch(mtime);
}

class DirRec {
  final String path;
  final int bytes;
  final int files;

  const DirRec(this.path, this.bytes, this.files);
}

class ScanProgress {
  final int files;
  final int bytes;
  final String phase;
  final String where;

  const ScanProgress(this.files, this.bytes, this.phase, this.where);
}

// ── Findings ──────────────────────────────────────────────────────────

class FindItem {
  final String path;
  final int size;
  final int mtime;

  /// Why this row is here, in the row's own words. For a duplicate that is
  /// which copy it is and where the others are.
  final String? note;

  /// Duplicates only: the hash that ties a set of copies together.
  final String? setKey;

  /// Empty-folder rows are directories. They free nothing and are deleted by
  /// a different call, so the delete executor has to be able to tell.
  final bool isDir;

  const FindItem({
    required this.path,
    required this.size,
    required this.mtime,
    this.note,
    this.setKey,
    this.isDir = false,
  });

  DateTime get modified => DateTime.fromMillisecondsSinceEpoch(mtime);
}

class FindGroup {
  final String id;
  final String title;

  /// One line: what these files are.
  final String why;

  /// One line: what it costs you if this finder is wrong about a file. Shown
  /// on the confirm sheet, never hidden behind a tap.
  final String caution;

  final List<FindItem> items;

  /// True when the group can contain something irreplaceable. Changes the
  /// confirm wording, nothing else: everything is confirmed either way.
  final bool risky;

  const FindGroup({
    required this.id,
    required this.title,
    required this.why,
    required this.caution,
    required this.items,
    this.risky = false,
  });

  int get bytes {
    int t = 0;
    for (final FindItem i in items) {
      t += i.size;
    }
    return t;
  }

  int get count => items.length;

  bool get isEmpty => items.isEmpty;
}

/// The thresholds every finder works to. Exposed in Settings because the right
/// number for "an old download" is a matter of how you use the phone, not
/// something an app gets to decide for you.
class FinderOptions {
  final int dupMinBytes;
  final int bigFileMinBytes;
  final int largeVideoMinBytes;
  final int screenshotAgeDays;
  final int downloadAgeDays;

  const FinderOptions({
    this.dupMinBytes = 1 * kMB,
    this.bigFileMinBytes = 100 * kMB,
    this.largeVideoMinBytes = 300 * kMB,
    this.screenshotAgeDays = 90,
    this.downloadAgeDays = 60,
  });

  FinderOptions copyWith({
    int? dupMinBytes,
    int? bigFileMinBytes,
    int? largeVideoMinBytes,
    int? screenshotAgeDays,
    int? downloadAgeDays,
  }) {
    return FinderOptions(
      dupMinBytes: dupMinBytes ?? this.dupMinBytes,
      bigFileMinBytes: bigFileMinBytes ?? this.bigFileMinBytes,
      largeVideoMinBytes: largeVideoMinBytes ?? this.largeVideoMinBytes,
      screenshotAgeDays: screenshotAgeDays ?? this.screenshotAgeDays,
      downloadAgeDays: downloadAgeDays ?? this.downloadAgeDays,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'dupMinBytes': dupMinBytes,
        'bigFileMinBytes': bigFileMinBytes,
        'largeVideoMinBytes': largeVideoMinBytes,
        'screenshotAgeDays': screenshotAgeDays,
        'downloadAgeDays': downloadAgeDays,
      };

  factory FinderOptions.fromJson(Map<String, dynamic> j) {
    int pick(String k, int fallback) {
      final dynamic v = j[k];
      return v is int ? v : (v is num ? v.toInt() : fallback);
    }

    return FinderOptions(
      dupMinBytes: pick('dupMinBytes', 1 * kMB),
      bigFileMinBytes: pick('bigFileMinBytes', 100 * kMB),
      largeVideoMinBytes: pick('largeVideoMinBytes', 300 * kMB),
      screenshotAgeDays: pick('screenshotAgeDays', 90),
      downloadAgeDays: pick('downloadAgeDays', 60),
    );
  }
}

// ── The scan as a whole ───────────────────────────────────────────────

class ScanResult {
  final int startedMs;
  final int finishedMs;
  final int totalFiles;
  final int totalBytes;
  final Map<Kind, int> byKind;

  /// Every directory with its recursive totals, biggest first.
  final List<DirRec> dirs;

  /// The largest individual files, capped.
  final List<FileRec> biggest;

  final List<FindGroup> groups;

  /// Directories that could not be read. Android/data and Android/obb are
  /// always here on Android 11 and up, and that is not an error.
  final List<String> unreadable;

  final bool truncated;

  const ScanResult({
    required this.startedMs,
    required this.finishedMs,
    required this.totalFiles,
    required this.totalBytes,
    required this.byKind,
    required this.dirs,
    required this.biggest,
    required this.groups,
    required this.unreadable,
    required this.truncated,
  });

  DateTime get finished => DateTime.fromMillisecondsSinceEpoch(finishedMs);

  Duration get took =>
      Duration(milliseconds: (finishedMs - startedMs).clamp(0, 1 << 40).toInt());

  /// Everything the finders turned up, with no file counted twice even when
  /// two finders both name it.
  int get reclaimable {
    final Set<String> seen = <String>{};
    int total = 0;
    for (final FindGroup g in groups) {
      for (final FindItem i in g.items) {
        if (seen.add(i.path)) {
          total += i.size;
        }
      }
    }
    return total;
  }

  FindGroup? group(String id) {
    for (final FindGroup g in groups) {
      if (g.id == id) {
        return g;
      }
    }
    return null;
  }

  /// Immediate children of [path], as directories with their own totals.
  List<DirRec> childrenOf(String path) {
    final String prefix = path.endsWith('/') ? path : '$path/';
    final List<DirRec> out = <DirRec>[];
    for (final DirRec d in dirs) {
      if (!d.path.startsWith(prefix)) {
        continue;
      }
      final String rest = d.path.substring(prefix.length);
      if (!rest.contains('/')) {
        out.add(d);
      }
    }
    out.sort((DirRec a, DirRec b) => b.bytes.compareTo(a.bytes));
    return out;
  }

  DirRec? dirAt(String path) {
    for (final DirRec d in dirs) {
      if (d.path == path) {
        return d;
      }
    }
    return null;
  }
}
