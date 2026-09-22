import 'dart:io';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../bytes.dart';
import '../models.dart';
import '../scan.dart';
import '../theme.dart';
import '../widgets.dart';
import 'finds.dart';

// ═══════════════════════════════════════════════════════════════════════
// FOLDERS
//
// Drill down with real recursive sizes at every level, biggest first. The
// finders answer "what is junk"; this answers "what on earth is in there",
// which is the question you actually have when a folder you have never heard
// of is holding 11 GB.
//
// Folder totals come from the scan. The files inside one folder are read
// live when you open it, because keeping every path in memory costs more
// than one listing ever will.
// ═══════════════════════════════════════════════════════════════════════

class BrowseTab extends StatelessWidget {
  const BrowseTab({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState s = AppScope.of(context);

    if (!s.hasAllFiles) {
      return const TabPage(
          title: 'Folders',
          child: SingleChildScrollView(child: PermissionGate()));
    }
    if (s.scan == null) {
      return const TabPage(
        title: 'Folders',
        child: Empty(
          icon: Icons.folder_outlined,
          text: 'Nothing has been scanned yet.\nRun a scan from the Storage tab.',
        ),
      );
    }

    return const _FolderBody(path: kSharedRoot, asTab: true);
  }
}

class FolderScreen extends StatelessWidget {
  final String path;

  const FolderScreen({super.key, required this.path});

  @override
  Widget build(BuildContext context) {
    return _FolderBody(path: path, asTab: false);
  }
}

class _FolderBody extends StatefulWidget {
  final String path;
  final bool asTab;

  const _FolderBody({required this.path, required this.asTab});

  @override
  State<_FolderBody> createState() => _FolderBodyState();
}

class _FolderBodyState extends State<_FolderBody> {
  List<FileRec> _files = <FileRec>[];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  /// One non-recursive listing of this folder. Fast even in a folder with
  /// thousands of entries, and it keeps the browser honest about what is
  /// there right now rather than what was there at scan time.
  void _loadFiles() {
    final List<FileRec> out = <FileRec>[];
    try {
      for (final FileSystemEntity e
          in Directory(widget.path).listSync(followLinks: false)) {
        if (e is! File) {
          continue;
        }
        try {
          final FileStat st = e.statSync();
          out.add(FileRec(e.path, st.size, st.modified.millisecondsSinceEpoch));
        } catch (_) {
          // Gone between the listing and the stat.
        }
      }
    } catch (_) {
      // Unreadable folder. The empty list plus the note below says so.
    }
    out.sort((FileRec a, FileRec b) => b.size.compareTo(a.size));
    if (mounted) {
      setState(() {
        _files = out;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState s = AppScope.of(context);
    final ScanResult? r = s.scan;
    final List<DirRec> children =
        r == null ? <DirRec>[] : r.childrenOf(widget.path);
    final DirRec? here = r?.dirAt(widget.path);
    final int total = here?.bytes ?? r?.totalBytes ?? 0;

    final String subtitle = here == null
        ? '${_files.length} files here'
        : '${formatBytes(here.bytes)}, ${formatCount(here.files)} files';

    final Widget list = ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: children.length + _files.length + 1,
      itemBuilder: (BuildContext ctx, int i) {
        if (i < children.length) {
          final DirRec d = children[i];
          return _FolderRow(dir: d, total: total);
        }
        final int fi = i - children.length;
        if (fi < _files.length) {
          final FileRec f = _files[fi];
          final FindItem item =
              FindItem(path: f.path, size: f.size, mtime: f.mtime);
          return FileRow(
            path: f.path,
            size: f.size,
            note: formatAge(f.modified),
            selected: s.selection.has(f.path),
            onTap: () => s.selection.toggle(item),
          );
        }
        return _Footer(
            loaded: _loaded,
            empty: children.isEmpty && _files.isEmpty,
            path: widget.path);
      },
    );

    final Widget body = Column(
      children: <Widget>[
        Expanded(child: list),
        const SelectionBar(),
      ],
    );

    if (widget.asTab) {
      return TabPage(
          title: 'Folders', subtitle: subtitle, child: body);
    }
    return AppScaffold(
      title: basename(widget.path),
      subtitle: subtitle,
      body: Column(children: <Widget>[Expanded(child: list)]),
      bottomBar:
          s.selection.isEmpty ? null : const SelectionBar(inBar: true),
    );
  }
}

class _FolderRow extends StatelessWidget {
  final DirRec dir;
  final int total;

  const _FolderRow({required this.dir, required this.total});

  @override
  Widget build(BuildContext context) {
    final double f = total == 0 ? 0 : dir.bytes / total;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
                builder: (_) => FolderScreen(path: dir.path))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
          child: Row(
            children: <Widget>[
              const Icon(Icons.folder_rounded, size: 18, color: kAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(basename(dir.path),
                        style: sans(size: 13.5, weight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 5),
                    Bar(fraction: f, colour: kDim, height: 3),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(formatBytes(dir.bytes),
                      style: mono(size: 12, weight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(formatCount(dir.files),
                      style: mono(size: 10, color: kFaint)),
                ],
              ),
              const Icon(Icons.chevron_right_rounded, size: 17, color: kFaint),
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final bool loaded;
  final bool empty;
  final String path;

  const _Footer({required this.loaded, required this.empty, required this.path});

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
            child: SizedBox(
                width: 16,
                height: 16,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: kFaint))),
      );
    }
    if (empty) {
      final bool blocked = path.contains('/Android/data') ||
          path.contains('/Android/obb');
      return Empty(
        icon: blocked ? Icons.lock_outline_rounded : Icons.inbox_outlined,
        text: blocked
            ? 'Android does not let any app read this folder, including this '
                'one. The Apps tab measures what is inside it instead.'
            : 'This folder is empty.',
      );
    }
    return const SizedBox(height: 8);
  }
}
