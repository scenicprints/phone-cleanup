import 'package:flutter/material.dart';

import 'bytes.dart';
import 'models.dart';
import 'native.dart';
import 'theme.dart';

// ═══════════════════════════════════════════════════════════════════════
// PARTS USED ON MORE THAN ONE SCREEN
// ═══════════════════════════════════════════════════════════════════════

/// Shown instead of content when All files access is off. Says what is missing,
/// what it is for, and opens the exact screen that grants it.
class PermissionGate extends StatelessWidget {
  const PermissionGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 20),
      child: Panel(
        border: kAccent.withValues(alpha: 0.3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.lock_outline_rounded, size: 18, color: kAccent),
                const SizedBox(width: 10),
                Text('All files access is off',
                    style: sans(size: 15, weight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Without it this app can see only its own folder, which is empty, '
              'so every number here would read zero. Android puts the switch in '
              'Special app access rather than in the normal permission list.',
              style: sans(size: 13, color: kDim, height: 1.55),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Open the setting',
              icon: Icons.open_in_new_rounded,
              onPressed: Native.openAllFilesAccess,
            ),
            const SizedBox(height: 10),
            Text(
              'Settings, Apps, Special app access, All files access, Phone Cleanup.',
              style: sans(size: 11, color: kFaint, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// One file or folder, with its size on the right where every row's size
/// lines up with every other row's.
class FileRow extends StatelessWidget {
  final String path;
  final int size;
  final String? note;
  final bool selected;
  final bool isDir;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool showCheckbox;

  const FileRow({
    super.key,
    required this.path,
    required this.size,
    this.note,
    this.selected = false,
    this.isDir = false,
    this.onTap,
    this.onLongPress,
    this.showCheckbox = true,
  });

  @override
  Widget build(BuildContext context) {
    final String name = basename(path);
    final String where = prettyPath(dirname(path));

    return Material(
      color: selected ? kSurfaceHi : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: EdgeInsets.fromLTRB(showCheckbox ? 8 : 16, 10, 16, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              if (showCheckbox)
                SizedBox(
                  width: 40,
                  child: Icon(
                    selected
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 21,
                    color: selected ? kAccent : kFaint,
                  ),
                ),
              if (!showCheckbox) ...<Widget>[
                Icon(isDir ? Icons.folder_rounded : Icons.insert_drive_file_outlined,
                    size: 17, color: kFaint),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(name,
                        style: sans(size: 13.5, weight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(note == null ? where : '$where  ·  $note',
                        style: sans(size: 11, color: kFaint, height: 1.3),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(isDir && size == 0 ? 'empty' : formatBytes(size),
                  style: mono(
                      size: 12,
                      color: size == 0 ? kFaint : kText,
                      weight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A named quantity with a proportion bar under it. The whole app's way of
/// saying "this much, out of that much".
class Meter extends StatelessWidget {
  final String label;
  final int bytes;
  final int total;
  final Color colour;
  final String? trailing;
  final VoidCallback? onTap;

  const Meter({
    super.key,
    required this.label,
    required this.bytes,
    required this.total,
    this.colour = kDim,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final double f = total == 0 ? 0 : bytes / total;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                    child: Text(label,
                        style: sans(size: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 10),
                Text(trailing ?? formatBytes(bytes),
                    style: mono(size: 12, color: kDim)),
                if (onTap != null) ...<Widget>[
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded,
                      size: 15, color: kFaint),
                ],
              ],
            ),
            const SizedBox(height: 7),
            Bar(fraction: f, colour: colour, height: 4),
          ],
        ),
      ),
    );
  }
}

/// The confirm sheet. Every delete in the app goes through this, and it always
/// states the count, the space, and what the finder warned about.
Future<bool> confirmDelete(
  BuildContext context, {
  required int count,
  required int bytes,
  required List<String> cautions,
  required List<FindItem> lastCopies,
}) async {
  final bool? ok = await showAppSheet<bool>(
    context,
    builder: (BuildContext ctx) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('Delete $count ${count == 1 ? 'item' : 'items'}',
                style: sans(size: 19, weight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('This frees ${formatBytes(bytes)} and cannot be undone.',
                style: sans(size: 13, color: kDim, height: 1.5)),
            if (lastCopies.isNotEmpty) ...<Widget>[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: kDanger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: kDanger.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Icon(Icons.error_outline_rounded,
                            size: 17, color: kDanger),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                              'You have ticked every copy of '
                              '${lastCopies.length} ${lastCopies.length == 1 ? 'file' : 'files'}',
                              style: sans(
                                  size: 13,
                                  weight: FontWeight.w700,
                                  color: kDanger)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                        'Those files will not exist anywhere afterwards. Leave '
                        'one copy of each ticked off if you meant to keep them.',
                        style: sans(size: 12, color: kDim, height: 1.5)),
                    const SizedBox(height: 10),
                    ...lastCopies.take(4).map((FindItem i) => Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(basename(i.path),
                              style: mono(size: 11, color: kDim),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        )),
                    if (lastCopies.length > 4)
                      Text('and ${lastCopies.length - 4} more',
                          style: sans(size: 11, color: kFaint)),
                  ],
                ),
              ),
            ],
            if (cautions.isNotEmpty) ...<Widget>[
              const SizedBox(height: 18),
              Text('WORTH KNOWING', style: kLabel),
              const SizedBox(height: 9),
              ...cautions.map((String c) => Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.only(top: 6, right: 9),
                          child: Container(
                              width: 3,
                              height: 3,
                              decoration: const BoxDecoration(
                                  color: kFaint, shape: BoxShape.circle)),
                        ),
                        Expanded(
                            child: Text(c,
                                style:
                                    sans(size: 12, color: kDim, height: 1.5))),
                      ],
                    ),
                  )),
            ],
            const SizedBox(height: 22),
            PrimaryButton(
              label: 'Delete ${formatBytes(bytes)}',
              colour: kDanger,
              icon: Icons.delete_outline_rounded,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12)),
                child: Text('Keep everything',
                    style:
                        sans(size: 13, color: kDim, weight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      );
    },
  );
  return ok ?? false;
}

/// Shown after a delete. Says what went and, if anything refused, what did not.
Future<void> showDeleteReport(
  BuildContext context, {
  required int deleted,
  required int freed,
  required List<String> failures,
}) {
  return showAppSheet<void>(
    context,
    builder: (BuildContext ctx) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(failures.isEmpty ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                    size: 20, color: failures.isEmpty ? kGood : kAccent),
                const SizedBox(width: 10),
                Text('${formatBytes(freed)} freed',
                    style: sans(size: 19, weight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 6),
            Text('$deleted ${deleted == 1 ? 'item' : 'items'} deleted.',
                style: sans(size: 13, color: kDim)),
            if (failures.isNotEmpty) ...<Widget>[
              const SizedBox(height: 18),
              Text('${failures.length} could not be removed'.toUpperCase(),
                  style: kLabel),
              const SizedBox(height: 9),
              ...failures.take(8).map((String f) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(f,
                        style: sans(size: 11.5, color: kDim, height: 1.4)),
                  )),
              if (failures.length > 8)
                Text('and ${failures.length - 8} more',
                    style: sans(size: 11, color: kFaint)),
            ],
            const SizedBox(height: 22),
            PrimaryButton(
                label: 'Done', onPressed: () => Navigator.of(ctx).pop()),
          ],
        ),
      );
    },
  );
}

/// A tab inside the shell. The shell already reserves the system nav bar
/// below, so a tab only has to clear the status bar at the top.
class TabPage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;

  const TabPage({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const <Widget>[],
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 10, 12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(title,
                          style: sans(
                              size: 22, weight: FontWeight.w700, height: 1.1)),
                      if (subtitle != null) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(subtitle!,
                            style: sans(size: 12, color: kFaint),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ),
                ),
                ...actions,
              ],
            ),
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
    );
  }
}
