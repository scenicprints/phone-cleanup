import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// ═══════════════════════════════════════════════════════════════════════
// LOOK
//
// Near-black, one accent, and figures in a monospace so byte counts line up
// in a column and can be compared by eye without reading them.
// ═══════════════════════════════════════════════════════════════════════

const Color kBg = Color(0xFF0B0C0E);
const Color kSurface = Color(0xFF141619);
const Color kSurfaceHi = Color(0xFF1B1E22);
const Color kLine = Color(0xFF262A2F);
const Color kText = Color(0xFFE8EAED);
const Color kDim = Color(0xFF9AA0A6);
const Color kFaint = Color(0xFF5F6672);
const Color kAccent = Color(0xFFE0A458);
const Color kDanger = Color(0xFFE05C4B);
const Color kGood = Color(0xFF6FBF8B);

/// Grey while there is room, amber when it is getting tight, red when it is
/// the problem. The gauge is the only place colour carries meaning.
Color pressureColour(double fraction) {
  if (fraction >= 0.90) {
    return kDanger;
  }
  if (fraction >= 0.75) {
    return kAccent;
  }
  return kDim;
}

TextStyle mono({
  double size = 13,
  Color color = kText,
  FontWeight weight = FontWeight.w500,
}) {
  return GoogleFonts.ibmPlexMono(
      fontSize: size, color: color, fontWeight: weight, height: 1.2);
}

TextStyle sans({
  double size = 14,
  Color color = kText,
  FontWeight weight = FontWeight.w500,
  double height = 1.35,
  double spacing = 0,
}) {
  return GoogleFonts.inter(
      fontSize: size,
      color: color,
      fontWeight: weight,
      height: height,
      letterSpacing: spacing);
}

TextStyle get kLabel => sans(
    size: 10, color: kFaint, weight: FontWeight.w700, spacing: 1.2, height: 1);

ThemeData buildTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: kBg,
    colorScheme: const ColorScheme.dark(
      surface: kBg,
      primary: kAccent,
      secondary: kAccent,
      error: kDanger,
    ),
    splashFactory: InkSparkle.splashFactory,
    dividerColor: kLine,
  );
}

/// Edge to edge, with both system bars drawn transparent over the app. Call
/// once at startup. The bars being transparent is exactly why every screen
/// below has to reserve room for them itself.
void applySystemChrome() {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false,
  ));
}

// ═══════════════════════════════════════════════════════════════════════
// INSETS: the one place the system bars are accounted for
//
// The app is edge to edge, so the gesture bar (or the three-button bar, which
// is twice as tall) sits ON TOP of the Flutter surface. Anything laid out to
// the raw bottom of the window is underneath it and cannot be tapped.
//
// Nothing in this app calls MediaQuery for bottom padding directly. Every
// screen is built through AppScaffold and every sheet through showAppSheet,
// and those two reserve the space as a real widget in the layout. That way a
// new screen cannot forget: there is no code path that reaches the bottom of
// the window at all.
// ═══════════════════════════════════════════════════════════════════════

class Insets {
  /// Height of the system navigation bar, gesture pill or buttons alike.
  static double navBar(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).bottom;

  /// Height of the keyboard when it is up, 0 when it is not.
  static double keyboard(BuildContext context) =>
      MediaQuery.viewInsetsOf(context).bottom;

  /// Status bar and camera cutout.
  static double statusBar(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).top;
}

/// Occupies the height of the system navigation bar. Painted in the app
/// background so it reads as the bottom of the screen and not as a gap.
class NavBarGap extends StatelessWidget {
  final Color colour;
  const NavBarGap({super.key, this.colour = kBg});

  @override
  Widget build(BuildContext context) {
    return Container(height: Insets.navBar(context), color: colour);
  }
}

/// Every screen in the app. [body] never reaches the system bars because the
/// header, the optional [bottomBar] and the NavBarGap are siblings in a
/// Column, not overlays.
class AppScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget body;
  final Widget? bottomBar;
  final bool showBack;

  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.actions = const <Widget>[],
    this.bottomBar,
    this.showBack = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      // The Column below already reserves the bars. Letting Scaffold resize for
      // the keyboard as well would double-count and jump the layout.
      resizeToAvoidBottomInset: false,
      body: Column(
        children: <Widget>[
          // Top bar only. bottom: false because the bottom is handled below,
          // and a SafeArea doing both would eat the padding this Column needs.
          SafeArea(
            bottom: false,
            child: _Header(
                title: title,
                subtitle: subtitle,
                actions: actions,
                showBack: showBack),
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              removeBottom: true,
              child: body,
            ),
          ),
          if (bottomBar != null)
            Container(
              decoration: const BoxDecoration(
                color: kSurface,
                border: Border(top: BorderSide(color: kLine)),
              ),
              // The bar paints behind the gesture pill, its contents sit above it.
              padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + Insets.navBar(context)),
              child: bottomBar,
            )
          else
            const NavBarGap(),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool showBack;

  const _Header({
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.showBack,
  });

  @override
  Widget build(BuildContext context) {
    final bool canPop = showBack && Navigator.of(context).canPop();
    return Container(
      padding: EdgeInsets.fromLTRB(canPop ? 4 : 20, 10, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          if (canPop)
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded, size: 22),
              color: kDim,
              tooltip: 'Back',
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(title,
                    style: sans(size: 19, weight: FontWeight.w700, height: 1.1),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 3),
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
    );
  }
}

/// A bottom sheet that clears the gesture bar and the keyboard. The only
/// sheet helper in the app, for the same reason AppScaffold is the only
/// scaffold.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext) builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: kSurface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (BuildContext ctx) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: Insets.keyboard(ctx) + Insets.navBar(ctx),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 34,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                  color: kLine, borderRadius: BorderRadius.circular(2)),
            ),
            Flexible(child: builder(ctx)),
          ],
        ),
      );
    },
  );
}

// ═══════════════════════════════════════════════════════════════════════
// SMALL PARTS
// ═══════════════════════════════════════════════════════════════════════

class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? border;

  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final Widget box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border ?? kLine),
      ),
      child: child,
    );
    if (onTap == null) {
      return box;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: box,
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(text.toUpperCase(), style: kLabel)),
          ?trailing,
        ],
      ),
    );
  }
}

/// A horizontal proportion bar. Used for the volume gauge and for every
/// "this folder is 12% of your storage" line, so the same visual language
/// means the same thing everywhere.
class Bar extends StatelessWidget {
  final double fraction;
  final Color colour;
  final double height;

  const Bar(
      {super.key,
      required this.fraction,
      required this.colour,
      this.height = 5});

  @override
  Widget build(BuildContext context) {
    final double f = fraction.isNaN ? 0 : fraction.clamp(0.0, 1.0).toDouble();
    // Laid out against a measured width rather than a FractionallySizedBox,
    // which does not reliably fill inside a Stack.
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: LayoutBuilder(
        builder: (BuildContext ctx, BoxConstraints c) {
          final double w = c.maxWidth.isFinite ? c.maxWidth : 0;
          return Stack(
            children: <Widget>[
              Container(height: height, width: w, color: kSurfaceHi),
              Container(height: height, width: w * f, color: colour),
            ],
          );
        },
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color colour;
  final IconData? icon;

  const PrimaryButton(
      {super.key,
      required this.label,
      required this.onPressed,
      this.colour = kAccent,
      this.icon});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: colour,
          foregroundColor: Colors.black,
          disabledBackgroundColor: kSurfaceHi,
          disabledForegroundColor: kFaint,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 17),
              const SizedBox(width: 8),
            ],
            Text(label,
                style: sans(
                    size: 14,
                    weight: FontWeight.w700,
                    color: onPressed == null ? kFaint : Colors.black)),
          ],
        ),
      ),
    );
  }
}

class GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color colour;

  const GhostButton(
      {super.key,
      required this.label,
      required this.onPressed,
      this.colour = kAccent});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: colour,
        side: BorderSide(color: colour.withValues(alpha: 0.4)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      child:
          Text(label, style: sans(size: 13, weight: FontWeight.w700, color: colour)),
    );
  }
}

/// Used wherever a list is empty. Says why it is empty, never just "nothing
/// here", because an empty finder is a result and not a failure.
class Empty extends StatelessWidget {
  final IconData icon;
  final String text;
  const Empty({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 30, color: kFaint),
          const SizedBox(height: 14),
          Text(text,
              textAlign: TextAlign.center,
              style: sans(size: 13, color: kFaint, height: 1.5)),
        ],
      ),
    );
  }
}
