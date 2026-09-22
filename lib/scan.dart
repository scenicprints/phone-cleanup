import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'bytes.dart';
import 'finders.dart';
import 'models.dart';

// ═══════════════════════════════════════════════════════════════════════
// THE SCAN
//
// One walk of shared storage, on a background isolate, producing everything
// every screen needs. The UI isolate never touches the filesystem: at 95%
// full there are several hundred thousand files down there, and walking them
// on the main isolate freezes the app for a minute.
//
// The walk is iterative rather than recursive. A recursive walk dies on one
// unreadable directory and takes the whole scan with it; this one records the
// directory and carries on, which matters because Android/data is guaranteed
// to be unreadable on every phone this will ever run on.
// ═══════════════════════════════════════════════════════════════════════

const String kSharedRoot = '/storage/emulated/0';

/// Hard ceiling on how many files are held in memory at once. A phone with
/// more files than this gets a truncated scan and is told so, which beats
/// being killed by the OOM reaper halfway through.
const int kMaxFiles = 800000;

class _ScanArgs {
  final SendPort reply;
  final List<String> roots;
  final FinderOptions options;
  final Set<String> installedPackages;

  const _ScanArgs(this.reply, this.roots, this.options, this.installedPackages);
}

/// Runs a scan on its own isolate. [onProgress] fires back on the UI isolate.
Future<ScanResult> runScan({
  required FinderOptions options,
  required Set<String> installedPackages,
  void Function(ScanProgress)? onProgress,
  List<String> roots = const <String>[kSharedRoot],
}) async {
  final ReceivePort port = ReceivePort();
  // A scan of a nearly full phone is the most likely thing in this app to be
  // killed by the OOM reaper. Without these two the isolate would simply stop
  // and the future would never complete, leaving the spinner up forever.
  final ReceivePort errors = ReceivePort();
  final ReceivePort exits = ReceivePort();
  final Completer<ScanResult> done = Completer<ScanResult>();

  final Isolate iso = await Isolate.spawn<_ScanArgs>(
    _scanEntry,
    _ScanArgs(port.sendPort, roots, options, installedPackages),
    errorsAreFatal: true,
    onError: errors.sendPort,
    onExit: exits.sendPort,
    debugName: 'phone-cleanup-scan',
  );

  late final StreamSubscription<dynamic> sub;

  void finish() {
    unawaited(sub.cancel());
    port.close();
    errors.close();
    exits.close();
    iso.kill(priority: Isolate.immediate);
  }

  void fail(String why) {
    if (!done.isCompleted) {
      done.completeError(StateError(why));
    }
    finish();
  }

  errors.listen((dynamic e) {
    final String detail = e is List<dynamic> && e.isNotEmpty ? '${e.first}' : '$e';
    fail('The scan crashed. $detail');
  });

  // Fires on a clean exit too, which by then has already completed the future.
  exits.listen((dynamic _) {
    fail('The scan stopped before it finished. The phone may have run out of '
        'memory partway through.');
  });

  sub = port.listen((dynamic msg) {
    if (msg is ScanProgress) {
      onProgress?.call(msg);
    } else if (msg is ScanResult) {
      if (!done.isCompleted) {
        done.complete(msg);
      }
      finish();
    } else if (msg is List<dynamic> && msg.isNotEmpty && msg.first == 'error') {
      if (!done.isCompleted) {
        done.completeError(
            StateError(msg.length > 1 ? '${msg[1]}' : 'The scan failed.'));
      }
      finish();
    }
  });

  return done.future;
}

// ── The isolate body ──────────────────────────────────────────────────

void _scanEntry(_ScanArgs args) {
  final SendPort reply = args.reply;
  try {
    final int started = DateTime.now().millisecondsSinceEpoch;

    final List<FileRec> files = <FileRec>[];
    final Map<String, int> dirBytes = <String, int>{};
    final Map<String, int> dirFiles = <String, int>{};
    final Map<Kind, int> byKind = <Kind, int>{};
    final List<String> unreadable = <String>[];
    final Set<String> seenDirs = <String>{};
    int totalBytes = 0;
    bool truncated = false;

    final List<String> stack = List<String>.from(args.roots);
    final int rootLen = args.roots.isEmpty ? 0 : args.roots.first.length;
    int sinceReport = 0;

    while (stack.isNotEmpty) {
      final String dir = stack.removeLast();
      seenDirs.add(dir);

      List<FileSystemEntity> entries;
      try {
        entries = Directory(dir).listSync(followLinks: false);
      } catch (_) {
        // Android/data and Android/obb land here on every modern phone, as do
        // the odd permission-stripped folder and any race with a delete.
        unreadable.add(dir);
        continue;
      }

      for (final FileSystemEntity e in entries) {
        if (e is Directory) {
          stack.add(e.path);
          continue;
        }
        if (e is! File) {
          continue; // Links are not followed and are not counted.
        }
        if (files.length >= kMaxFiles) {
          truncated = true;
          continue;
        }
        FileStat st;
        try {
          st = e.statSync();
        } catch (_) {
          continue;
        }
        final int size = st.size;
        if (size < 0) {
          continue;
        }
        files.add(FileRec(e.path, size, st.modified.millisecondsSinceEpoch));
        totalBytes += size;
        final Kind k = kindOf(e.path);
        byKind[k] = (byKind[k] ?? 0) + size;
        _addUp(e.path, size, dirBytes, dirFiles, rootLen);

        sinceReport++;
        if (sinceReport >= 2000) {
          sinceReport = 0;
          reply.send(ScanProgress(files.length, totalBytes, 'Reading', dir));
        }
      }
    }

    reply.send(ScanProgress(files.length, totalBytes, 'Sorting', ''));

    final List<DirRec> dirs = <DirRec>[];
    dirBytes.forEach((String path, int bytes) {
      dirs.add(DirRec(path, bytes, dirFiles[path] ?? 0));
    });
    dirs.sort((DirRec a, DirRec b) => b.bytes.compareTo(a.bytes));

    final List<FileRec> bySize = List<FileRec>.from(files)
      ..sort((FileRec a, FileRec b) => b.size.compareTo(a.size));
    final List<FileRec> topFiles = bySize.take(400).toList(growable: false);

    // Directories holding no file at any depth below them.
    final List<String> emptyDirs = seenDirs
        .where((String d) => (dirFiles[d] ?? 0) == 0 && d.length > rootLen)
        .toList()
      ..sort();

    final List<FindGroup> groups = runFinders(
      files: files,
      emptyDirs: emptyDirs,
      installedPackages: args.installedPackages,
      options: args.options,
      hash: hashFile,
      onProgress: (String phase, String where) =>
          reply.send(ScanProgress(files.length, totalBytes, phase, where)),
    );

    reply.send(ScanResult(
      startedMs: started,
      finishedMs: DateTime.now().millisecondsSinceEpoch,
      totalFiles: files.length,
      totalBytes: totalBytes,
      byKind: byKind,
      dirs: dirs,
      biggest: topFiles,
      groups: groups,
      unreadable: unreadable,
      truncated: truncated,
    ));
  } catch (e) {
    reply.send(<dynamic>['error', e.toString()]);
  }
}

/// Adds one file's weight to every directory above it, stopping at the root.
void _addUp(String path, int size, Map<String, int> bytes,
    Map<String, int> files, int rootLen) {
  int i = path.lastIndexOf('/');
  while (i > 0) {
    final String d = path.substring(0, i);
    if (d.length < rootLen) {
      return;
    }
    bytes[d] = (bytes[d] ?? 0) + size;
    files[d] = (files[d] ?? 0) + 1;
    i = d.lastIndexOf('/');
  }
}

/// Collects a Digest out of a chunked conversion. package:crypto does not
/// export a sink that does this, and it is four lines.
class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}

/// Full SHA-1 of a file, read a megabyte at a time so a 4 GB video does not
/// have to fit in memory. Returns null when the file cannot be read, and a
/// null hash is never treated as a match by anything downstream.
String? hashFile(String path, {int? limit}) {
  RandomAccessFile? raf;
  try {
    raf = File(path).openSync();
    final _DigestSink out = _DigestSink();
    final ByteConversionSink input = sha1.startChunkedConversion(out);
    final Uint8List buf = Uint8List(1 << 20);
    int read = 0;
    while (true) {
      if (limit != null && read >= limit) {
        break;
      }
      final int n = raf.readIntoSync(buf);
      if (n <= 0) {
        break;
      }
      input.add(n == buf.length ? buf : Uint8List.sublistView(buf, 0, n));
      read += n;
    }
    input.close();
    return out.value?.toString();
  } catch (_) {
    return null;
  } finally {
    try {
      raf?.closeSync();
    } catch (_) {
      // Already closed, or the file went away underneath us.
    }
  }
}
