import 'package:flutter/services.dart';

// ═══════════════════════════════════════════════════════════════════════
// THE NATIVE CHANNEL
//
// Thin wrapper over MainActivity.kt. Every call can fail (a revoked
// permission, an OEM that does not carry a settings screen), and a failure
// here must never take the app down, so everything returns a usable empty
// value instead of throwing.
// ═══════════════════════════════════════════════════════════════════════

const MethodChannel _ch = MethodChannel('phone_cleanup/native');

class VolumeInfo {
  final int total;
  final int free;
  final int used;

  const VolumeInfo({required this.total, required this.free, required this.used});

  static const VolumeInfo empty = VolumeInfo(total: 0, free: 0, used: 0);

  double get fraction => total == 0 ? 0 : used / total;

  bool get isEmpty => total == 0;
}

class AppEntry {
  final String package;
  final String label;
  final int appBytes;
  final int dataBytes;
  final int cacheBytes;
  final int total;
  final bool system;

  /// False when usage access is off, in which case only [appBytes] is real
  /// and the UI must not present the total as the truth.
  final bool measured;

  const AppEntry({
    required this.package,
    required this.label,
    required this.appBytes,
    required this.dataBytes,
    required this.cacheBytes,
    required this.total,
    required this.system,
    required this.measured,
  });

  factory AppEntry.fromMap(Map<dynamic, dynamic> m) {
    return AppEntry(
      package: (m['package'] as String?) ?? '',
      label: (m['label'] as String?) ?? '',
      appBytes: _int(m['app']),
      dataBytes: _int(m['data']),
      cacheBytes: _int(m['cache']),
      total: _int(m['total']),
      system: (m['system'] as bool?) ?? false,
      measured: (m['measured'] as bool?) ?? false,
    );
  }

  static int _int(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);
}

class Native {
  static Future<VolumeInfo> volume() async {
    try {
      final Map<dynamic, dynamic>? m =
          await _ch.invokeMethod<Map<dynamic, dynamic>>('volume');
      if (m == null) {
        return VolumeInfo.empty;
      }
      return VolumeInfo(
        total: AppEntry._int(m['total']),
        free: AppEntry._int(m['free']),
        used: AppEntry._int(m['used']),
      );
    } catch (_) {
      return VolumeInfo.empty;
    }
  }

  static Future<bool> hasAllFilesAccess() async {
    try {
      return await _ch.invokeMethod<bool>('hasAllFilesAccess') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openAllFilesAccess() => _quiet('openAllFilesAccess');

  static Future<bool> hasUsageAccess() async {
    try {
      return await _ch.invokeMethod<bool>('hasUsageAccess') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openUsageAccess() => _quiet('openUsageAccess');

  static Future<List<AppEntry>> apps() async {
    try {
      final List<dynamic>? raw = await _ch.invokeMethod<List<dynamic>>('apps');
      if (raw == null) {
        return <AppEntry>[];
      }
      return raw
          .whereType<Map<dynamic, dynamic>>()
          .map(AppEntry.fromMap)
          .toList();
    } catch (_) {
      return <AppEntry>[];
    }
  }

  static Future<Set<String>> installedPackages() async {
    try {
      final List<dynamic>? raw =
          await _ch.invokeMethod<List<dynamic>>('installedPackages');
      return (raw ?? <dynamic>[]).whereType<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<Uint8List?> appIcon(String package) async {
    try {
      return await _ch.invokeMethod<Uint8List>(
          'appIcon', <String, dynamic>{'package': package});
    } catch (_) {
      return null;
    }
  }

  static Future<void> openAppStorage(String package) async {
    try {
      await _ch.invokeMethod<void>(
          'openAppStorage', <String, dynamic>{'package': package});
    } catch (_) {
      // Nothing to do: the settings screen simply does not exist here.
    }
  }

  /// Asks the system to run its own "clear cached data" prompt. Returns false
  /// when the OEM does not carry that screen, which the UI has to say out loud
  /// rather than silently doing nothing.
  static Future<bool> clearAllCaches() async {
    try {
      return await _ch.invokeMethod<bool>('clearAllCaches') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Tell MediaStore about files that are now gone.
  static Future<void> rescanPaths(List<String> paths) async {
    if (paths.isEmpty) {
      return;
    }
    try {
      // Batched: handing the scanner 20,000 paths at once wedges it.
      for (int i = 0; i < paths.length; i += 400) {
        final List<String> slice =
            paths.sublist(i, i + 400 > paths.length ? paths.length : i + 400);
        await _ch.invokeMethod<void>(
            'rescanPaths', <String, dynamic>{'paths': slice});
      }
    } catch (_) {
      // A stale MediaStore row is cosmetic. Never fail a delete over it.
    }
  }

  static Future<void> _quiet(String method) async {
    try {
      await _ch.invokeMethod<void>(method);
    } catch (_) {
      // Same reasoning as openAppStorage.
    }
  }
}
