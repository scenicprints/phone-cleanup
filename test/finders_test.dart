import 'package:flutter_test/flutter_test.dart';
import 'package:phone_cleanup/bytes.dart';
import 'package:phone_cleanup/finders.dart';
import 'package:phone_cleanup/models.dart';

// The finders are pure functions over a list of records and an injected hash,
// which is the whole reason they are worth testing: the rules that decide what
// gets offered up for deletion can be checked without a phone.

const String root = '/storage/emulated/0';

FileRec f(String path, int size, {int daysOld = 0}) {
  return FileRec(
    '$root/$path',
    size,
    DateTime.now().subtract(Duration(days: daysOld)).millisecondsSinceEpoch,
  );
}

/// A hash that says two files match when their contents map says so.
HashFn fakeHash(Map<String, String> contents) {
  return (String path, {int? limit}) => contents[path];
}

List<FindGroup> run(
  List<FileRec> files, {
  Map<String, String> contents = const <String, String>{},
  Set<String> installed = const <String>{},
  List<String> emptyDirs = const <String>[],
  FinderOptions options = const FinderOptions(),
}) {
  return runFinders(
    files: files,
    emptyDirs: emptyDirs,
    installedPackages: installed,
    options: options,
    hash: fakeHash(contents),
    onProgress: (String _, String _) {},
  );
}

FindGroup? byId(List<FindGroup> groups, String id) {
  for (final FindGroup g in groups) {
    if (g.id == id) {
      return g;
    }
  }
  return null;
}

void main() {
  test('a finder that found nothing does not become a row', () {
    final List<FindGroup> groups = run(<FileRec>[f('Documents/notes.txt', 400)]);
    expect(byId(groups, 'installers'), isNull);
    expect(byId(groups, 'duplicates'), isNull);
  });

  group('duplicates', () {
    test('matches on content, not on name or folder', () {
      final List<FileRec> files = <FileRec>[
        f('DCIM/Camera/IMG_1.jpg', 4 * kMB, daysOld: 100),
        f('Download/copy-of-photo.jpg', 4 * kMB, daysOld: 10),
        f('Pictures/unrelated.jpg', 4 * kMB, daysOld: 5),
      ];
      final List<FindGroup> groups = run(files, contents: <String, String>{
        '$root/DCIM/Camera/IMG_1.jpg': 'aaa',
        '$root/Download/copy-of-photo.jpg': 'aaa',
        '$root/Pictures/unrelated.jpg': 'bbb',
      });

      final FindGroup dupes = byId(groups, 'duplicates')!;
      expect(dupes.count, 2);
      expect(dupes.items.map((FindItem i) => i.path),
          isNot(contains('$root/Pictures/unrelated.jpg')));
    });

    test('puts the oldest copy first and labels the rest', () {
      final List<FileRec> files = <FileRec>[
        f('Download/new.bin', 2 * kMB, daysOld: 1),
        f('Documents/old.bin', 2 * kMB, daysOld: 400),
      ];
      final FindGroup dupes = byId(
          run(files, contents: <String, String>{
            '$root/Download/new.bin': 'x',
            '$root/Documents/old.bin': 'x',
          }),
          'duplicates')!;

      expect(dupes.items.first.path, '$root/Documents/old.bin');
      expect(dupes.items.first.note, 'Oldest of 2 copies');
      expect(dupes.items[1].note, 'Copy 2 of 2');
      // Both carry the same set key, which is what lets the confirm sheet
      // notice when every copy has been ticked.
      expect(dupes.items.first.setKey, dupes.items[1].setKey);
    });

    test('an unreadable file is never called a duplicate', () {
      final List<FileRec> files = <FileRec>[
        f('a/one.bin', 3 * kMB),
        f('b/two.bin', 3 * kMB),
      ];
      // No contents at all: both hashes come back null.
      expect(byId(run(files), 'duplicates'), isNull);
    });

    test('ignores files under the size floor', () {
      final List<FileRec> files = <FileRec>[
        f('a/tiny1.txt', 900),
        f('a/tiny2.txt', 900),
      ];
      final List<FindGroup> groups = run(files, contents: <String, String>{
        '$root/a/tiny1.txt': 'same',
        '$root/a/tiny2.txt': 'same',
      });
      expect(byId(groups, 'duplicates'), isNull);
    });
  });

  group('leftovers', () {
    test('Android/media of an uninstalled package is flagged, installed is not',
        () {
      final List<FileRec> files = <FileRec>[
        f('Android/media/com.gone.app/video.mp4', 50 * kMB),
        f('Android/media/com.here.app/video.mp4', 50 * kMB),
      ];
      final FindGroup g =
          byId(run(files, installed: <String>{'com.here.app'}), 'orphan_media')!;
      expect(g.count, 1);
      expect(g.items.first.path, contains('com.gone.app'));
      expect(g.items.first.note, 'Left by com.gone.app');
    });

    test('finds thumbnail and cache junk', () {
      final List<FileRec> files = <FileRec>[
        f('DCIM/.thumbnails/1234.jpg', 8 * kMB),
        f('SomeApp/cache/blob.dat', 12 * kMB),
        f('DCIM/Camera/keep.jpg', 5 * kMB),
      ];
      final FindGroup g = byId(run(files), 'thumbnails')!;
      expect(g.count, 2);
      expect(g.bytes, 20 * kMB);
    });

    test('finds files Android has already staged for deletion', () {
      final List<FileRec> files = <FileRec>[
        f('DCIM/Camera/.trashed-1700000000-IMG_9.jpg', 6 * kMB),
      ];
      final FindGroup g = byId(run(files), 'trashed')!;
      expect(g.count, 1);
      expect(g.risky, isTrue);
    });

    test('finds sent copies only inside the messaging apps', () {
      final List<FileRec> files = <FileRec>[
        f('WhatsApp/Media/WhatsApp Images/Sent/a.jpg', 2 * kMB),
        f('Telegram/Telegram Video/Sent/b.mp4', 30 * kMB),
        f('MyFolder/Sent/c.jpg', 2 * kMB),
      ];
      final FindGroup g = byId(run(files), 'messenger_sent')!;
      expect(g.count, 2);
    });
  });

  group('age and size rules', () {
    test('an old screenshot is caught and a fresh one is not', () {
      final List<FileRec> files = <FileRec>[
        f('Pictures/Screenshots/old.png', 900 * kKB, daysOld: 200),
        f('Pictures/Screenshots/new.png', 900 * kKB, daysOld: 3),
      ];
      final FindGroup g = byId(run(files), 'old_screenshots')!;
      expect(g.count, 1);
      expect(g.items.first.path, contains('old.png'));
    });

    test('the age threshold is honoured', () {
      final List<FileRec> files = <FileRec>[
        f('Download/thing.zip', 40 * kMB, daysOld: 45),
      ];
      expect(byId(run(files), 'old_downloads'), isNull);
      final FindGroup g = byId(
          run(files, options: const FinderOptions(downloadAgeDays: 30)),
          'old_downloads')!;
      expect(g.count, 1);
    });

    test('large videos and big files do not both claim the same file', () {
      final List<FileRec> files = <FileRec>[
        f('Movies/holiday.mp4', 900 * kMB),
        f('Download/backup.zip', 900 * kMB),
      ];
      final List<FindGroup> groups = run(files);
      expect(byId(groups, 'large_videos')!.count, 1);
      expect(byId(groups, 'biggest')!.count, 1);
      expect(byId(groups, 'biggest')!.items.first.path, contains('backup.zip'));
    });

    test('rows come back heaviest first', () {
      final List<FileRec> files = <FileRec>[
        f('Movies/small.mp4', 400 * kMB),
        f('Movies/huge.mp4', 2 * kGB),
        f('Movies/mid.mp4', 800 * kMB),
      ];
      final FindGroup g = byId(run(files), 'large_videos')!;
      expect(g.items.map((FindItem i) => i.size),
          <int>[2 * kGB, 800 * kMB, 400 * kMB]);
    });
  });

  test('empty folders are reported as directories worth no space', () {
    final FindGroup g = byId(
        run(<FileRec>[f('a/real.txt', 10)],
            emptyDirs: <String>['$root/Android/data/com.gone']),
        'empty_folders')!;
    expect(g.count, 1);
    expect(g.items.first.isDir, isTrue);
    expect(g.bytes, 0);
  });

  test('every group states what it costs to be wrong', () {
    final List<FindGroup> groups = run(<FileRec>[
      f('Movies/holiday.mp4', 900 * kMB),
      f('Download/old.apk', 80 * kMB, daysOld: 400),
      f('DCIM/.thumbnails/x.jpg', 3 * kMB),
    ]);
    expect(groups, isNotEmpty);
    for (final FindGroup g in groups) {
      expect(g.why.trim(), isNotEmpty, reason: '${g.id} has no explanation');
      expect(g.caution.trim(), isNotEmpty, reason: '${g.id} has no caution');
    }
  });
}
