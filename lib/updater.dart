import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'theme.dart';

// ═══════════════════════════════════════════════════════════════════════
// IN-APP OTA UPDATER
//
// Checks the latest GitHub Release, compares its tag to the installed
// version, and downloads and installs the APK. The repo is public, so the
// releases API needs no token; GitHub allows 60 unauthenticated requests an
// hour per IP, which is plenty for one phone.
//
// It checks once, quietly, on launch, so a waiting update turns into a line
// at the top of the first screen rather than something you have to go
// looking for in Settings.
// ═══════════════════════════════════════════════════════════════════════

const String kRepoOwner = 'scenicprints';
const String kRepoName = 'phone-cleanup';

class ReleaseInfo {
  final String version;
  final String notes;
  final String apkUrl;

  const ReleaseInfo(
      {required this.version, required this.notes, required this.apkUrl});
}

class Updater {
  static String _current = '';

  static String get currentVersion => _current;

  static Future<String> loadCurrentVersion() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      _current = info.version;
    } catch (_) {
      _current = '';
    }
    return _current;
  }

  static Future<ReleaseInfo?> fetchLatest() async {
    try {
      final Uri uri = Uri.parse(
          'https://api.github.com/repos/$kRepoOwner/$kRepoName/releases/latest');
      final http.Response resp = await http
          .get(uri, headers: <String, String>{'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) {
        return null;
      }
      final Map<String, dynamic> data =
          jsonDecode(resp.body) as Map<String, dynamic>;
      final String tag = (data['tag_name'] as String?) ?? '';
      final String version = tag.replaceFirst(RegExp(r'^v'), '');
      final String notes = ((data['body'] as String?) ?? '').trim();

      String? apkUrl;
      for (final dynamic a in (data['assets'] as List<dynamic>? ?? <dynamic>[])) {
        final Map<String, dynamic> m = a as Map<String, dynamic>;
        final String name = (m['name'] as String?) ?? '';
        if (name.toLowerCase().endsWith('.apk')) {
          apkUrl = m['browser_download_url'] as String?;
          break;
        }
      }
      if (version.isEmpty || apkUrl == null) {
        return null;
      }
      return ReleaseInfo(version: version, notes: notes, apkUrl: apkUrl);
    } catch (_) {
      return null;
    }
  }

  /// A release worth telling the user about, or null. Safe to call on launch:
  /// it never throws and never blocks anything.
  static Future<ReleaseInfo?> checkQuietly() async {
    if (_current.isEmpty) {
      await loadCurrentVersion();
    }
    final ReleaseInfo? r = await fetchLatest();
    if (r == null) {
      return null;
    }
    return isNewer(r.version, _current) ? r : null;
  }

  /// True if [a] is a strictly higher semantic version than [b].
  static bool isNewer(String a, String b) {
    final List<int> pa = _parse(a), pb = _parse(b);
    for (int i = 0; i < 3; i++) {
      if (pa[i] != pb[i]) {
        return pa[i] > pb[i];
      }
    }
    return false;
  }

  static List<int> _parse(String v) {
    final List<String> parts = v.split('.');
    return List<int>.generate(
        3,
        (int i) => i < parts.length
            ? (int.tryParse(parts[i].split('+').first) ?? 0)
            : 0);
  }
}

enum _State { idle, checking, upToDate, available, downloading, error }

/// The full control, for Settings.
class UpdateCard extends StatefulWidget {
  final ReleaseInfo? known;

  const UpdateCard({super.key, this.known});

  @override
  State<UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<UpdateCard> {
  _State _s = _State.idle;
  ReleaseInfo? _release;
  String _msg = '';
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    if (widget.known != null) {
      _release = widget.known;
      _s = _State.available;
    }
  }

  Future<void> _check() async {
    setState(() {
      _s = _State.checking;
      _msg = '';
    });
    final ReleaseInfo? r = await Updater.fetchLatest();
    if (!mounted) {
      return;
    }
    if (r == null) {
      setState(() {
        _s = _State.error;
        _msg = 'Could not reach GitHub. Are you online?';
      });
      return;
    }
    if (Updater.isNewer(r.version, Updater.currentVersion)) {
      setState(() {
        _release = r;
        _s = _State.available;
      });
    } else {
      setState(() => _s = _State.upToDate);
    }
  }

  void _install() {
    final ReleaseInfo? r = _release;
    if (r == null) {
      return;
    }
    setState(() {
      _s = _State.downloading;
      _progress = 0;
    });
    try {
      OtaUpdate()
          .execute(r.apkUrl, destinationFilename: 'phone-cleanup-${r.version}.apk')
          .listen((OtaEvent event) {
        if (!mounted) {
          return;
        }
        switch (event.status) {
          case OtaStatus.DOWNLOADING:
            setState(() => _progress = int.tryParse(event.value ?? '0') ?? 0);
          case OtaStatus.INSTALLING:
          case OtaStatus.INSTALLATION_DONE:
            break; // The system installer has it from here.
          case OtaStatus.CANCELED:
            setState(() => _s = _State.available);
          case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
            setState(() {
              _s = _State.error;
              _msg = 'Allow "install unknown apps" for Phone Cleanup, then retry.';
            });
          case OtaStatus.ALREADY_RUNNING_ERROR:
            setState(() {
              _s = _State.error;
              _msg = 'An update is already downloading.';
            });
          case OtaStatus.DOWNLOAD_ERROR:
          case OtaStatus.CHECKSUM_ERROR:
          case OtaStatus.INSTALLATION_ERROR:
          case OtaStatus.INTERNAL_ERROR:
            setState(() {
              _s = _State.error;
              _msg = 'Download failed. ${event.value ?? ''}'.trim();
            });
        }
      });
    } catch (_) {
      setState(() {
        _s = _State.error;
        _msg = 'Could not start the update.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text('UPDATES', style: kLabel),
              Text(
                  Updater.currentVersion.isEmpty
                      ? ''
                      : 'v${Updater.currentVersion}',
                  style: mono(size: 11, color: kFaint)),
            ],
          ),
          const SizedBox(height: 12),
          _body(),
        ],
      ),
    );
  }

  Widget _body() {
    switch (_s) {
      case _State.checking:
        return Row(
          children: <Widget>[
            const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(strokeWidth: 2, color: kAccent)),
            const SizedBox(width: 12),
            Text('Checking GitHub', style: sans(size: 13, color: kDim)),
          ],
        );

      case _State.downloading:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Downloading, $_progress%',
                style: sans(size: 13, color: kText)),
            const SizedBox(height: 10),
            Bar(fraction: _progress / 100, colour: kAccent),
            const SizedBox(height: 10),
            Text('The installer opens by itself when it is ready.',
                style: sans(size: 11, color: kFaint)),
          ],
        );

      case _State.available:
        final ReleaseInfo r = _release!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('v${r.version} is ready',
                style: sans(size: 14, weight: FontWeight.w700, color: kAccent)),
            if (r.notes.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text(r.notes, style: sans(size: 13, color: kDim, height: 1.5)),
            ],
            const SizedBox(height: 14),
            PrimaryButton(
                label: 'Download and install',
                icon: Icons.download_rounded,
                onPressed: _install),
          ],
        );

      case _State.upToDate:
        return Row(
          children: <Widget>[
            const Icon(Icons.check_rounded, size: 17, color: kGood),
            const SizedBox(width: 10),
            Expanded(
                child: Text('This is the latest build.',
                    style: sans(size: 13, color: kDim))),
            GhostButton(label: 'Again', onPressed: _check),
          ],
        );

      case _State.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(_msg, style: sans(size: 13, color: kDanger, height: 1.4)),
            const SizedBox(height: 12),
            GhostButton(label: 'Retry', onPressed: _check),
          ],
        );

      case _State.idle:
        return Row(
          children: <Widget>[
            Expanded(
                child: Text('Pull the newest build from GitHub.',
                    style: sans(size: 13, color: kDim))),
            const SizedBox(width: 10),
            GhostButton(label: 'Check', onPressed: _check),
          ],
        );
    }
  }
}

/// One tappable line for the top of the first screen, so a waiting update is
/// impossible to miss and one tap from installed.
class UpdateBanner extends StatelessWidget {
  final ReleaseInfo release;
  final VoidCallback onTap;

  const UpdateBanner({super.key, required this.release, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Panel(
        onTap: onTap,
        border: kAccent.withValues(alpha: 0.35),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            const Icon(Icons.arrow_circle_down_rounded, size: 18, color: kAccent),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Version ${release.version} is ready to install',
                  style: sans(size: 13, weight: FontWeight.w600)),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18, color: kFaint),
          ],
        ),
      ),
    );
  }
}
