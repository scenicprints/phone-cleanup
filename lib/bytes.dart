// ═══════════════════════════════════════════════════════════════════════
// BYTES, NAMES AND KINDS
//
// Pure functions, no Flutter, no io. Everything here is unit tested, because
// a wrong number here is the difference between deleting a duplicate and
// deleting the only copy.
// ═══════════════════════════════════════════════════════════════════════

const int kKB = 1024;
const int kMB = 1024 * 1024;
const int kGB = 1024 * 1024 * 1024;

/// Android reports storage in binary units and so does Settings, so this does
/// too. Two significant figures below 10, none above, because "14.27 GB" is
/// four digits of precision nobody acts on.
String formatBytes(int bytes) {
  if (bytes < 0) {
    return '0 B';
  }
  if (bytes < kKB) {
    return '$bytes B';
  }
  if (bytes < kMB) {
    return '${_trim(bytes / kKB)} KB';
  }
  if (bytes < kGB) {
    return '${_trim(bytes / kMB)} MB';
  }
  return '${_trim(bytes / kGB)} GB';
}

String _trim(double v) {
  if (v >= 100) {
    return v.toStringAsFixed(0);
  }
  if (v >= 10) {
    return v.toStringAsFixed(1);
  }
  return v.toStringAsFixed(2);
}

String formatCount(int n) {
  final String s = n.toString();
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) {
      out.write(',');
    }
    out.write(s[i]);
  }
  return out.toString();
}

/// "3 days ago", "7 months ago". Deliberately coarse: the exact timestamp is
/// never the reason to keep or delete something, the rough age is.
String formatAge(DateTime when, {DateTime? now}) {
  final DateTime n = now ?? DateTime.now();
  final int days = n.difference(when).inDays;
  if (days < 0) {
    return 'in the future';
  }
  if (days == 0) {
    return 'today';
  }
  if (days == 1) {
    return 'yesterday';
  }
  if (days < 30) {
    return '$days days ago';
  }
  if (days < 365) {
    final int m = (days / 30).floor();
    return m == 1 ? 'a month ago' : '$m months ago';
  }
  final int y = (days / 365).floor();
  return y == 1 ? 'a year ago' : '$y years ago';
}

String formatDate(DateTime d) {
  const List<String> months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

/// The last path segment.
String basename(String path) {
  final int i = path.lastIndexOf('/');
  return i < 0 ? path : path.substring(i + 1);
}

/// Everything but the last path segment.
String dirname(String path) {
  final int i = path.lastIndexOf('/');
  return i <= 0 ? '/' : path.substring(0, i);
}

String extensionOf(String path) {
  final String name = basename(path);
  final int i = name.lastIndexOf('.');
  if (i <= 0 || i == name.length - 1) {
    return '';
  }
  return name.substring(i + 1).toLowerCase();
}

/// A path with the shared-storage root stripped, which is noise on every
/// single row otherwise.
String prettyPath(String path) {
  const String root = '/storage/emulated/0/';
  if (path.startsWith(root)) {
    final String rest = path.substring(root.length);
    return rest.isEmpty ? 'Internal storage' : rest;
  }
  return path;
}

// ── Kinds ─────────────────────────────────────────────────────────────

enum Kind { image, video, audio, document, archive, apk, other }

const Map<Kind, String> kindNames = <Kind, String>{
  Kind.image: 'Images',
  Kind.video: 'Video',
  Kind.audio: 'Audio',
  Kind.document: 'Documents',
  Kind.archive: 'Archives',
  Kind.apk: 'Installers',
  Kind.other: 'Everything else',
};

const Set<String> _image = <String>{
  'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'bmp', 'dng',
  'raw', 'tiff', 'tif', 'avif', 'svg',
};
const Set<String> _video = <String>{
  'mp4', 'mkv', 'mov', 'avi', 'webm', '3gp', 'm4v', 'wmv', 'flv', 'mts', 'ts',
};
const Set<String> _audio = <String>{
  'mp3', 'm4a', 'aac', 'ogg', 'opus', 'flac', 'wav', 'wma', 'amr', 'mid',
};
const Set<String> _document = <String>{
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'rtf', 'odt',
  'csv', 'epub', 'mobi', 'md', 'json', 'xml', 'html',
};
const Set<String> _archive = <String>{
  'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'iso', 'cab',
};
const Set<String> _apk = <String>{'apk', 'apks', 'xapk', 'apkm', 'obb'};

Kind kindOf(String path) {
  final String e = extensionOf(path);
  if (_image.contains(e)) {
    return Kind.image;
  }
  if (_video.contains(e)) {
    return Kind.video;
  }
  if (_audio.contains(e)) {
    return Kind.audio;
  }
  if (_document.contains(e)) {
    return Kind.document;
  }
  if (_archive.contains(e)) {
    return Kind.archive;
  }
  if (_apk.contains(e)) {
    return Kind.apk;
  }
  return Kind.other;
}
