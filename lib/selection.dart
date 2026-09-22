import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'native.dart';

// ═══════════════════════════════════════════════════════════════════════
// SELECTION AND DELETION
//
// The only code in the app that removes anything. It is deliberately small
// and deliberately dull, and it is the only place worth reading twice.
//
// Two rules it enforces on behalf of the person using it:
//
//   1. Nothing is ever ticked by default. A finder proposes, the person
//      disposes, and a scan that turns up 40 GB still starts at zero.
//   2. Selecting every copy of a duplicate set is allowed, but it is not
//      allowed to happen quietly. lastCopyWarnings names them so the confirm
//      sheet can say it out loud.
// ═══════════════════════════════════════════════════════════════════════

class Selection extends ChangeNotifier {
  final Set<String> _paths = <String>{};
  final Map<String, FindItem> _items = <String, FindItem>{};

  int get count => _paths.length;

  int get bytes {
    int t = 0;
    for (final FindItem i in _items.values) {
      t += i.size;
    }
    return t;
  }

  bool get isEmpty => _paths.isEmpty;

  bool has(String path) => _paths.contains(path);

  List<FindItem> get items => _items.values.toList();

  void toggle(FindItem item) {
    if (_paths.contains(item.path)) {
      _paths.remove(item.path);
      _items.remove(item.path);
    } else {
      _paths.add(item.path);
      _items[item.path] = item;
    }
    notifyListeners();
  }

  void addAll(Iterable<FindItem> items) {
    for (final FindItem i in items) {
      _paths.add(i.path);
      _items[i.path] = i;
    }
    notifyListeners();
  }

  void removeAll(Iterable<FindItem> items) {
    for (final FindItem i in items) {
      _paths.remove(i.path);
      _items.remove(i.path);
    }
    notifyListeners();
  }

  void clear() {
    _paths.clear();
    _items.clear();
    notifyListeners();
  }

  /// How many of [group]'s rows are currently ticked.
  int countIn(FindGroup group) {
    int n = 0;
    for (final FindItem i in group.items) {
      if (_paths.contains(i.path)) {
        n++;
      }
    }
    return n;
  }

  /// Duplicate sets where every single copy is ticked, which means the file
  /// itself is about to stop existing. Returns one representative row per set.
  List<FindItem> lastCopyWarnings(List<FindGroup> groups) {
    final Map<String, List<FindItem>> sets = <String, List<FindItem>>{};
    for (final FindGroup g in groups) {
      for (final FindItem i in g.items) {
        final String? k = i.setKey;
        if (k != null) {
          sets.putIfAbsent(k, () => <FindItem>[]).add(i);
        }
      }
    }
    final List<FindItem> out = <FindItem>[];
    sets.forEach((String _, List<FindItem> members) {
      if (members.length > 1 &&
          members.every((FindItem m) => _paths.contains(m.path))) {
        out.add(members.first);
      }
    });
    out.sort((FindItem a, FindItem b) => b.size.compareTo(a.size));
    return out;
  }
}

// ── Doing it ──────────────────────────────────────────────────────────

class DeleteFailure {
  final String path;
  final String reason;

  const DeleteFailure(this.path, this.reason);
}

class DeleteReport {
  final int deleted;
  final int freed;
  final List<DeleteFailure> failures;

  const DeleteReport(
      {required this.deleted, required this.freed, required this.failures});

  bool get clean => failures.isEmpty;
}

class Deleter {
  /// Deletes everything in [items]. Files first, then directories from the
  /// deepest up, so a folder is only removed once whatever was inside it has
  /// gone.
  ///
  /// A failure on one path never stops the rest: at 95% full the point is to
  /// free what can be freed, and the report says exactly what did not go.
  static Future<DeleteReport> run(
    List<FindItem> items, {
    void Function(int done, int total)? onProgress,
  }) async {
    final List<FindItem> fileRows =
        items.where((FindItem i) => !i.isDir).toList();
    final List<FindItem> dirRows = items.where((FindItem i) => i.isDir).toList()
      // Deepest first.
      ..sort((FindItem a, FindItem b) =>
          b.path.split('/').length.compareTo(a.path.split('/').length));

    final List<DeleteFailure> failures = <DeleteFailure>[];
    final List<String> gone = <String>[];
    int freed = 0;
    int done = 0;
    final int total = items.length;

    for (final FindItem i in fileRows) {
      try {
        final File f = File(i.path);
        if (f.existsSync()) {
          // Re-stat rather than trusting the scan: the file may have grown or
          // shrunk since, and the freed total should be what actually went.
          final int size = f.lengthSync();
          f.deleteSync();
          freed += size;
          gone.add(i.path);
        }
      } catch (e) {
        failures.add(DeleteFailure(i.path, _reason(e)));
      }
      done++;
      if (done % 25 == 0) {
        onProgress?.call(done, total);
        // Let the UI draw. Deleting is fast, but 3,000 of them in a row is
        // still long enough to look like a freeze.
        await Future<void>.delayed(Duration.zero);
      }
    }

    for (final FindItem i in dirRows) {
      try {
        final Directory d = Directory(i.path);
        if (d.existsSync()) {
          // Non-recursive on purpose. If something reappeared inside it since
          // the scan, the folder stays.
          d.deleteSync();
        }
      } catch (e) {
        failures.add(DeleteFailure(i.path, _reason(e)));
      }
      done++;
    }

    onProgress?.call(total, total);

    // Without this, Photos and Files go on showing grey tiles for files that
    // are already gone.
    await Native.rescanPaths(gone);

    return DeleteReport(
        deleted: gone.length, freed: freed, failures: failures);
  }

  static String _reason(Object e) {
    final String s = e.toString();
    if (s.contains('Permission denied') || s.contains('errno = 13')) {
      return 'Permission denied';
    }
    if (s.contains('No such file') || s.contains('errno = 2')) {
      return 'Already gone';
    }
    if (s.contains('Directory not empty') || s.contains('errno = 39')) {
      return 'Not empty any more';
    }
    return 'Could not delete';
  }
}
