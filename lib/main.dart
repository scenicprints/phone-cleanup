import 'package:flutter/material.dart';

import 'app_state.dart';
import 'screens/apps.dart';
import 'screens/browse.dart';
import 'screens/finds.dart';
import 'screens/overview.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  applySystemChrome();
  runApp(const PhoneCleanupApp());
}

class PhoneCleanupApp extends StatefulWidget {
  const PhoneCleanupApp({super.key});

  @override
  State<PhoneCleanupApp> createState() => _PhoneCleanupAppState();
}

class _PhoneCleanupAppState extends State<PhoneCleanupApp> {
  final AppState _state = AppState();

  @override
  void initState() {
    super.initState();
    _state.init();
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      child: MaterialApp(
        title: 'Phone Cleanup',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const Shell(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SHELL
//
// Four tabs in an IndexedStack so a scan's scroll position survives a tab
// change. The nav bar is the last child of a Column and carries the system
// bar's height inside its own padding, so nothing on any tab can end up
// underneath the gesture pill.
// ═══════════════════════════════════════════════════════════════════════

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Granting All files access happens in Settings, which means leaving the
    // app. Re-check on the way back so the permission gate clears itself
    // instead of making the user work out that they need to pull to refresh.
    if (state == AppLifecycleState.resumed && mounted) {
      final AppState s = AppScope.read(context);
      s.refreshPermissions();
      s.refreshVolume();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState s = AppScope.of(context);

    if (s.phase == Phase.loading) {
      return const Scaffold(
        backgroundColor: kBg,
        body: Center(
            child: SizedBox(
                width: 22,
                height: 22,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: kFaint))),
      );
    }

    return Scaffold(
      backgroundColor: kBg,
      resizeToAvoidBottomInset: false,
      body: Column(
        children: <Widget>[
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: const <Widget>[
                OverviewTab(),
                FindsTab(),
                BrowseTab(),
                AppsTab(),
              ],
            ),
          ),
          _NavBar(
            index: _tab,
            selectedCount: s.selection.count,
            onTap: (int i) => setState(() => _tab = i),
          ),
        ],
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  final int index;
  final int selectedCount;
  final ValueChanged<int> onTap;

  const _NavBar(
      {required this.index, required this.selectedCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const List<_NavItem> items = <_NavItem>[
      _NavItem(Icons.pie_chart_outline_rounded, Icons.pie_chart_rounded, 'Storage'),
      _NavItem(Icons.checklist_rtl_rounded, Icons.checklist_rounded, 'Clean'),
      _NavItem(Icons.folder_outlined, Icons.folder_rounded, 'Folders'),
      _NavItem(Icons.apps_outlined, Icons.apps_rounded, 'Apps'),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: kSurface,
        border: Border(top: BorderSide(color: kLine)),
      ),
      // The bar paints behind the gesture pill; its contents sit clear of it.
      padding: EdgeInsets.only(top: 8, bottom: 8 + Insets.navBar(context)),
      child: Row(
        children: List<Widget>.generate(items.length, (int i) {
          final bool on = i == index;
          final _NavItem it = items[i];
          return Expanded(
            child: InkWell(
              onTap: () => onTap(i),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Stack(
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        Icon(on ? it.on : it.off,
                            size: 21, color: on ? kAccent : kFaint),
                        if (i == 1 && selectedCount > 0)
                          Positioned(
                            right: -7,
                            top: -4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                  color: kAccent,
                                  borderRadius: BorderRadius.circular(8)),
                              child: Text('$selectedCount',
                                  style: mono(
                                      size: 9,
                                      color: Colors.black,
                                      weight: FontWeight.w700)),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(it.label,
                        style: sans(
                            size: 10,
                            color: on ? kAccent : kFaint,
                            weight: on ? FontWeight.w700 : FontWeight.w500,
                            height: 1)),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _NavItem {
  final IconData off;
  final IconData on;
  final String label;

  const _NavItem(this.off, this.on, this.label);
}
