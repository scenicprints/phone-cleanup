import 'package:flutter_test/flutter_test.dart';
import 'package:phone_cleanup/bytes.dart';

void main() {
  group('formatBytes', () {
    test('stays in bytes below a kilobyte', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(999), '999 B');
    });

    test('loses precision as the number grows', () {
      expect(formatBytes(kKB), '1.00 KB');
      expect(formatBytes(15 * kMB), '15.0 MB');
      expect(formatBytes(150 * kMB), '150 MB');
    });

    test('uses binary units, the way Android Settings does', () {
      // 1 GB must read as 1.00 GB, not as 1.07.
      expect(formatBytes(kGB), '1.00 GB');
    });

    test('never returns a negative size', () {
      expect(formatBytes(-500), '0 B');
    });
  });

  group('formatCount', () {
    test('groups thousands', () {
      expect(formatCount(7), '7');
      expect(formatCount(1234), '1,234');
      expect(formatCount(987654), '987,654');
    });
  });

  group('formatAge', () {
    final DateTime now = DateTime(2026, 9, 21);

    test('names the recent days', () {
      expect(formatAge(now, now: now), 'today');
      expect(formatAge(now.subtract(const Duration(days: 1)), now: now),
          'yesterday');
      expect(formatAge(now.subtract(const Duration(days: 5)), now: now),
          '5 days ago');
    });

    test('rounds off once it is months', () {
      expect(formatAge(now.subtract(const Duration(days: 60)), now: now),
          '2 months ago');
      expect(formatAge(now.subtract(const Duration(days: 800)), now: now),
          '2 years ago');
    });
  });

  group('paths', () {
    test('splits a path', () {
      expect(basename('/storage/emulated/0/DCIM/a.jpg'), 'a.jpg');
      expect(dirname('/storage/emulated/0/DCIM/a.jpg'), '/storage/emulated/0/DCIM');
      expect(extensionOf('/a/b/photo.JPEG'), 'jpeg');
      expect(extensionOf('/a/b/noextension'), '');
      expect(extensionOf('/a/b/.hidden'), '');
    });

    test('strips the shared storage root, which is on every single row', () {
      expect(prettyPath('/storage/emulated/0/DCIM/Camera'), 'DCIM/Camera');
      expect(prettyPath('/storage/emulated/0/'), 'Internal storage');
      expect(prettyPath('/data/local/tmp'), '/data/local/tmp');
    });
  });

  group('kindOf', () {
    test('sorts the common extensions', () {
      expect(kindOf('a/b.jpg'), Kind.image);
      expect(kindOf('a/b.HEIC'), Kind.image);
      expect(kindOf('a/b.mp4'), Kind.video);
      expect(kindOf('a/b.flac'), Kind.audio);
      expect(kindOf('a/b.pdf'), Kind.document);
      expect(kindOf('a/b.zip'), Kind.archive);
      expect(kindOf('a/b.apk'), Kind.apk);
      expect(kindOf('a/b.obb'), Kind.apk);
      expect(kindOf('a/b.wat'), Kind.other);
    });
  });
}
