import 'bytes.dart';
import 'models.dart';

// ═══════════════════════════════════════════════════════════════════════
// THE FINDERS
//
// Each one answers a different question about the same list of files, and
// each one carries its own caution line, because "we found 4 GB" is only
// useful next to "and here is what you lose if we are wrong".
//
// Nothing here is pre-ticked. A finder proposes; the person disposes.
//
// Pure functions over plain data. No io except through the injected [hash],
// which is what makes the whole file unit testable.
// ═══════════════════════════════════════════════════════════════════════

typedef HashFn = String? Function(String path, {int? limit});
typedef ProgressFn = void Function(String phase, String where);

/// No single group may carry more than this. Sorted biggest first, so a cap
/// only ever cuts off rows that were not worth the scroll.
const int kMaxGroupItems = 3000;

/// Head bytes used for the cheap pass before a full content hash.
const int kFingerprintBytes = 256 * kKB;

List<FindGroup> runFinders({
  required List<FileRec> files,
  required List<String> emptyDirs,
  required Set<String> installedPackages,
  required FinderOptions options,
  required HashFn hash,
  required ProgressFn onProgress,
}) {
  final DateTime now = DateTime.now();
  final List<FindGroup> out = <FindGroup>[];

  onProgress('Comparing', 'looking for duplicates');
  out.add(_duplicates(files, options, hash, onProgress));

  onProgress('Checking', 'leftovers');
  out.add(_orphanAppMedia(files, installedPackages));
  out.add(_thumbnailsAndCaches(files));
  out.add(_trashed(files));
  out.add(_installers(files));
  out.add(_messengerSent(files));

  onProgress('Checking', 'the big and the old');
  out.add(_largeVideos(files, options));
  out.add(_biggestFiles(files, options));
  out.add(_oldScreenshots(files, options, now));
  out.add(_oldDownloads(files, options, now));
  out.add(_emptyFolders(emptyDirs));

  // A finder that found nothing is not worth a row on the screen.
  return out.where((FindGroup g) => g.items.isNotEmpty).toList();
}

// ── Duplicates ────────────────────────────────────────────────────────
//
// Three passes, cheapest first. Size is free and throws away almost
// everything. A 256 KB head hash throws away almost all of the rest. Only
// what survives both gets read end to end.
//
// The full read is not optional. Two different videos from the same camera
// share a size and a header often enough that head-matching alone would
// eventually delete something irreplaceable, and this is the one bug in this
// app that cannot be apologised for afterwards.

FindGroup _duplicates(
  List<FileRec> files,
  FinderOptions o,
  HashFn hash,
  ProgressFn onProgress,
) {
  final Map<int, List<FileRec>> bySize = <int, List<FileRec>>{};
  for (final FileRec f in files) {
    if (f.size < o.dupMinBytes) {
      continue;
    }
    bySize.putIfAbsent(f.size, () => <FileRec>[]).add(f);
  }

  final List<FindItem> items = <FindItem>[];
  int examined = 0;

  for (final MapEntry<int, List<FileRec>> e in bySize.entries) {
    if (e.value.length < 2) {
      continue;
    }
    examined++;
    if (examined % 25 == 0) {
      onProgress('Comparing', '${formatBytes(e.key)} files');
    }

    // Small enough that the head pass would cost as much as the real one.
    final bool straightToFull = e.key <= 8 * kMB;
    final List<List<FileRec>> candidates = straightToFull
        ? <List<FileRec>>[e.value]
        : _groupBy(e.value, (FileRec f) => hash(f.path, limit: kFingerprintBytes))
            .where((List<FileRec> g) => g.length > 1)
            .toList();

    for (final List<FileRec> candidate in candidates) {
      if (candidate.length < 2) {
        continue;
      }
      for (final List<FileRec> set
          in _groupBy(candidate, (FileRec f) => hash(f.path))) {
        if (set.length < 2) {
          continue;
        }
        // Oldest first, then shortest path. The one most likely to be the
        // original sits at the top of its set.
        set.sort((FileRec a, FileRec b) {
          final int byTime = a.mtime.compareTo(b.mtime);
          return byTime != 0 ? byTime : a.path.length.compareTo(b.path.length);
        });
        final String key = '${e.key}:${set.first.path}';
        for (int i = 0; i < set.length; i++) {
          items.add(FindItem(
            path: set[i].path,
            size: set[i].size,
            mtime: set[i].mtime,
            setKey: key,
            note: i == 0
                ? 'Oldest of ${set.length} copies'
                : 'Copy ${i + 1} of ${set.length}',
          ));
        }
      }
    }
  }

  // Keep whole sets together and put the heaviest sets first.
  final Map<String, List<FindItem>> sets = <String, List<FindItem>>{};
  for (final FindItem i in items) {
    sets.putIfAbsent(i.setKey ?? i.path, () => <FindItem>[]).add(i);
  }
  final List<List<FindItem>> ordered = sets.values.toList()
    ..sort((List<FindItem> a, List<FindItem> b) {
      final int aw = a.first.size * (a.length - 1);
      final int bw = b.first.size * (b.length - 1);
      return bw.compareTo(aw);
    });

  final List<FindItem> flat = <FindItem>[];
  for (final List<FindItem> s in ordered) {
    if (flat.length + s.length > kMaxGroupItems) {
      break;
    }
    flat.addAll(s);
  }

  return FindGroup(
    id: 'duplicates',
    title: 'Duplicates',
    why:
        'Files whose contents are byte for byte identical. Every copy is listed, '
        'oldest first, so you can see which one you probably meant to keep.',
    caution:
        'These were matched on their full contents, not on their names, so the '
        'copies really are interchangeable. Deleting every copy of a set still '
        'loses the file, and the app will say so before it does.',
    items: flat,
  );
}

/// Groups by a key function, dropping anything the key function could not
/// compute. A null hash means the file could not be read, and an unreadable
/// file is never called a duplicate of anything.
List<List<FileRec>> _groupBy(List<FileRec> input, String? Function(FileRec) key) {
  final Map<String, List<FileRec>> m = <String, List<FileRec>>{};
  for (final FileRec f in input) {
    final String? k = key(f);
    if (k == null) {
      continue;
    }
    m.putIfAbsent(k, () => <FileRec>[]).add(f);
  }
  return m.values.toList();
}

// ── Leftovers ─────────────────────────────────────────────────────────

/// Android/media/<package> survives the uninstall of the app that made it.
/// This is where the multi-gigabyte WhatsApp folder sits after you have
/// already removed WhatsApp.
FindGroup _orphanAppMedia(List<FileRec> files, Set<String> installed) {
  const String marker = '/Android/media/';
  final List<FindItem> items = <FindItem>[];
  for (final FileRec f in files) {
    final int i = f.path.indexOf(marker);
    if (i < 0) {
      continue;
    }
    final String rest = f.path.substring(i + marker.length);
    final int slash = rest.indexOf('/');
    if (slash <= 0) {
      continue;
    }
    final String pkg = rest.substring(0, slash);
    if (installed.contains(pkg)) {
      continue;
    }
    items.add(FindItem(
        path: f.path, size: f.size, mtime: f.mtime, note: 'Left by $pkg'));
  }
  return _sized(
    id: 'orphan_media',
    title: 'Left behind by uninstalled apps',
    why:
        'Media folders belonging to apps that are no longer installed. Nothing '
        'on the phone can open these any more.',
    caution:
        'If you plan to reinstall one of these apps, its old media would have '
        'come back with it.',
    items: items,
  );
}

FindGroup _thumbnailsAndCaches(List<FileRec> files) {
  final List<FindItem> items = <FindItem>[];
  for (final FileRec f in files) {
    final String p = f.path.toLowerCase();
    final bool isJunk = p.contains('/.thumbnails/') ||
        p.contains('/.thumbdata') ||
        p.contains('/cache/') ||
        p.contains('/.cache/') ||
        p.contains('/caches/') ||
        p.contains('/tmp/') ||
        p.contains('/.temp/') ||
        p.endsWith('.tmp');
    if (isJunk) {
      items.add(FindItem(path: f.path, size: f.size, mtime: f.mtime));
    }
  }
  return _sized(
    id: 'thumbnails',
    title: 'Thumbnails and caches',
    why:
        'Preview images and scratch files that apps rebuild by themselves the '
        'next time they need them.',
    caution:
        'Galleries will be slow to draw once, while they regenerate their '
        'previews. Nothing is permanently lost.',
    items: items,
  );
}

/// Android stages a deleted photo as .trashed-<timestamp>-<name> for 30 days
/// before actually removing it.
FindGroup _trashed(List<FileRec> files) {
  final List<FindItem> items = <FindItem>[];
  for (final FileRec f in files) {
    final String name = basename(f.path);
    if (name.startsWith('.trashed-') || name.startsWith('.pending-')) {
      items.add(FindItem(
          path: f.path,
          size: f.size,
          mtime: f.mtime,
          note: 'Already in the bin'));
    }
  }
  return _sized(
    id: 'trashed',
    title: 'Waiting in the bin',
    why:
        'Photos and videos you already deleted. Android keeps them for thirty '
        'days before removing them, and they take up room the whole time.',
    caution:
        'This is the last step of a delete you already asked for. Removing them '
        'here empties the bin early, so they stop being recoverable.',
    items: items,
    risky: true,
  );
}

FindGroup _installers(List<FileRec> files) {
  final List<FindItem> items = <FindItem>[];
  for (final FileRec f in files) {
    if (kindOf(f.path) == Kind.apk) {
      items.add(FindItem(path: f.path, size: f.size, mtime: f.mtime));
    }
  }
  return _sized(
    id: 'installers',
    title: 'Installer files',
    why:
        'APK and OBB files sitting in storage. Installing an app copies it '
        'elsewhere, so the installer itself is dead weight afterwards.',
    caution:
        'An OBB belonging to a game you still play is that game\'s data, not a '
        'leftover, and deleting it makes the game download it again.',
    items: items,
    risky: true,
  );
}

/// WhatsApp and Telegram keep a second copy of everything you forwarded or
/// sent, in a Sent folder beside the original.
FindGroup _messengerSent(List<FileRec> files) {
  final List<FindItem> items = <FindItem>[];
  for (final FileRec f in files) {
    final String p = f.path;
    final bool sent = p.contains('/Sent/') &&
        (p.contains('/WhatsApp/') ||
            p.contains('/WhatsApp Business/') ||
            p.contains('/Telegram/'));
    if (sent) {
      items.add(FindItem(
          path: p, size: f.size, mtime: f.mtime, note: 'Your sent copy'));
    }
  }
  return _sized(
    id: 'messenger_sent',
    title: 'Sent copies in messaging apps',
    why:
        'A second copy the app kept of everything you sent or forwarded. The '
        'thing you actually sent still exists wherever it came from.',
    caution:
        'If you sent a photo you had already deleted from the camera roll, the '
        'sent copy is the only one left.',
    items: items,
  );
}

// ── Big and old ───────────────────────────────────────────────────────

FindGroup _largeVideos(List<FileRec> files, FinderOptions o) {
  final List<FindItem> items = <FindItem>[];
  for (final FileRec f in files) {
    if (f.size >= o.largeVideoMinBytes && kindOf(f.path) == Kind.video) {
      items.add(FindItem(path: f.path, size: f.size, mtime: f.mtime));
    }
  }
  return _sized(
    id: 'large_videos',
    title: 'Large videos',
    why:
        'Every video over ${formatBytes(o.largeVideoMinBytes)}. Not junk, just '
        'the heaviest things you own, which makes this the fastest way to free '
        'real space.',
    caution: 'These are your own recordings. Nothing here is replaceable.',
    items: items,
    risky: true,
  );
}

FindGroup _biggestFiles(List<FileRec> files, FinderOptions o) {
  final List<FindItem> items = <FindItem>[];
  for (final FileRec f in files) {
    if (f.size >= o.bigFileMinBytes && kindOf(f.path) != Kind.video) {
      items.add(FindItem(path: f.path, size: f.size, mtime: f.mtime));
    }
  }
  return _sized(
    id: 'biggest',
    title: 'Biggest single files',
    why:
        'Everything over ${formatBytes(o.bigFileMinBytes)} that is not a video. '
        'Usually an archive, a backup or a game download you forgot about.',
    caution:
        'This finder has no opinion about what these files are. Read the paths '
        'before ticking anything.',
    items: items,
    risky: true,
  );
}

FindGroup _oldScreenshots(List<FileRec> files, FinderOptions o, DateTime now) {
  final int cutoff =
      now.subtract(Duration(days: o.screenshotAgeDays)).millisecondsSinceEpoch;
  final List<FindItem> items = <FindItem>[];
  for (final FileRec f in files) {
    final String p = f.path;
    final bool isShot = p.contains('/Screenshots/') ||
        p.contains('/Screen Recordings/') ||
        basename(p).toLowerCase().startsWith('screenshot');
    if (isShot && f.mtime < cutoff) {
      items.add(FindItem(
          path: p,
          size: f.size,
          mtime: f.mtime,
          note: formatAge(f.modified, now: now)));
    }
  }
  return _sized(
    id: 'old_screenshots',
    title: 'Screenshots over ${o.screenshotAgeDays} days old',
    why:
        'Screenshots are almost always taken to be used within the hour. These '
        'have been sitting for months.',
    caution:
        'A screenshot can be a receipt, a booking reference or a password. '
        'Worth a look down the list before ticking the lot.',
    items: items,
    risky: true,
  );
}

FindGroup _oldDownloads(List<FileRec> files, FinderOptions o, DateTime now) {
  final int cutoff =
      now.subtract(Duration(days: o.downloadAgeDays)).millisecondsSinceEpoch;
  final List<FindItem> items = <FindItem>[];
  for (final FileRec f in files) {
    if (f.path.contains('/Download/') && f.mtime < cutoff) {
      items.add(FindItem(
          path: f.path,
          size: f.size,
          mtime: f.mtime,
          note: formatAge(f.modified, now: now)));
    }
  }
  return _sized(
    id: 'old_downloads',
    title: 'Downloads over ${o.downloadAgeDays} days old',
    why:
        'The download folder is where files go to be forgotten. These have not '
        'been touched in months.',
    caution:
        'Some apps save real work into Download rather than into their own '
        'folder, so this is not automatically a junk drawer.',
    items: items,
    risky: true,
  );
}

FindGroup _emptyFolders(List<String> dirs) {
  final List<FindItem> items = <FindItem>[];
  for (final String d in dirs) {
    items.add(FindItem(path: d, size: 0, mtime: 0, isDir: true));
  }
  if (items.length > kMaxGroupItems) {
    items.removeRange(kMaxGroupItems, items.length);
  }
  return FindGroup(
    id: 'empty_folders',
    title: 'Empty folders',
    why:
        'Folders with nothing in them at any depth, left behind by apps you '
        'have removed. They free no space at all, they just make the file '
        'browser hard to read.',
    caution:
        'An app that is still installed may recreate its folder the next time '
        'you open it.',
    items: items,
  );
}

// ── Shared tail ───────────────────────────────────────────────────────

FindGroup _sized({
  required String id,
  required String title,
  required String why,
  required String caution,
  required List<FindItem> items,
  bool risky = false,
}) {
  items.sort((FindItem a, FindItem b) => b.size.compareTo(a.size));
  if (items.length > kMaxGroupItems) {
    items.removeRange(kMaxGroupItems, items.length);
  }
  return FindGroup(
    id: id,
    title: title,
    why: why,
    caution: caution,
    items: items,
    risky: risky,
  );
}
