import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The Sift visual language: warm paper, dark ink, moss, and one clay accent.
///
/// It deliberately avoids the default Material purple, gradients, and
/// rounded-everything surfaces. Structure comes from hairlines, spacing and
/// type — not shadows.
@immutable
class SiftPalette extends ThemeExtension<SiftPalette> {
  const SiftPalette({
    required this.paper,
    required this.surface,
    required this.surfaceRaised,
    required this.ink,
    required this.inkSoft,
    required this.muted,
    required this.faint,
    required this.line,
    required this.lineStrong,
    required this.moss,
    required this.mossDeep,
    required this.mossWash,
    required this.clay,
    required this.clayWash,
    required this.gold,
    required this.danger,
    required this.browserChrome,
    required this.isDark,
  });

  final Color paper;
  final Color surface;
  final Color surfaceRaised;
  final Color ink;
  final Color inkSoft;
  final Color muted;
  final Color faint;
  final Color line;
  final Color lineStrong;
  final Color moss;
  final Color mossDeep;
  final Color mossWash;
  final Color clay;
  final Color clayWash;
  final Color gold;
  final Color danger;
  final Color browserChrome;
  final bool isDark;

  static const light = SiftPalette(
    paper: Color(0xFFF6F1E7),
    surface: Color(0xFFFCF9F2),
    surfaceRaised: Color(0xFFFFFDF8),
    ink: Color(0xFF1E2421),
    inkSoft: Color(0xFF364039),
    muted: Color(0xFF6B726A),
    faint: Color(0xFF949A90),
    line: Color(0xFFDED6C7),
    lineStrong: Color(0xFFC8BEAC),
    moss: Color(0xFF3F5A46),
    mossDeep: Color(0xFF2C4033),
    mossWash: Color(0xFFE7EDE4),
    clay: Color(0xFFB4552D),
    clayWash: Color(0xFFF3E3D8),
    gold: Color(0xFFB38B45),
    danger: Color(0xFF9C3B2F),
    browserChrome: Color(0xFFF0EADD),
    isDark: false,
  );

  static const dark = SiftPalette(
    paper: Color(0xFF121713),
    surface: Color(0xFF181E19),
    surfaceRaised: Color(0xFF202721),
    ink: Color(0xFFEDE8DC),
    inkSoft: Color(0xFFD0CBBE),
    muted: Color(0xFF9AA298),
    faint: Color(0xFF747C73),
    line: Color(0xFF303830),
    lineStrong: Color(0xFF455046),
    moss: Color(0xFFA8C2AC),
    mossDeep: Color(0xFFD3E3D4),
    mossWash: Color(0xFF253127),
    clay: Color(0xFFE39B79),
    clayWash: Color(0xFF3A2922),
    gold: Color(0xFFD8B97B),
    danger: Color(0xFFE7A297),
    browserChrome: Color(0xFF1B211C),
    isDark: true,
  );

  @override
  SiftPalette copyWith({
    Color? paper,
    Color? surface,
    Color? surfaceRaised,
    Color? ink,
    Color? inkSoft,
    Color? muted,
    Color? faint,
    Color? line,
    Color? lineStrong,
    Color? moss,
    Color? mossDeep,
    Color? mossWash,
    Color? clay,
    Color? clayWash,
    Color? gold,
    Color? danger,
    Color? browserChrome,
    bool? isDark,
  }) {
    return SiftPalette(
      paper: paper ?? this.paper,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      ink: ink ?? this.ink,
      inkSoft: inkSoft ?? this.inkSoft,
      muted: muted ?? this.muted,
      faint: faint ?? this.faint,
      line: line ?? this.line,
      lineStrong: lineStrong ?? this.lineStrong,
      moss: moss ?? this.moss,
      mossDeep: mossDeep ?? this.mossDeep,
      mossWash: mossWash ?? this.mossWash,
      clay: clay ?? this.clay,
      clayWash: clayWash ?? this.clayWash,
      gold: gold ?? this.gold,
      danger: danger ?? this.danger,
      browserChrome: browserChrome ?? this.browserChrome,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  SiftPalette lerp(covariant SiftPalette? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return SiftPalette(
      paper: mix(paper, other.paper),
      surface: mix(surface, other.surface),
      surfaceRaised: mix(surfaceRaised, other.surfaceRaised),
      ink: mix(ink, other.ink),
      inkSoft: mix(inkSoft, other.inkSoft),
      muted: mix(muted, other.muted),
      faint: mix(faint, other.faint),
      line: mix(line, other.line),
      lineStrong: mix(lineStrong, other.lineStrong),
      moss: mix(moss, other.moss),
      mossDeep: mix(mossDeep, other.mossDeep),
      mossWash: mix(mossWash, other.mossWash),
      clay: mix(clay, other.clay),
      clayWash: mix(clayWash, other.clayWash),
      gold: mix(gold, other.gold),
      danger: mix(danger, other.danger),
      browserChrome: mix(browserChrome, other.browserChrome),
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

extension SiftContext on BuildContext {
  SiftPalette get sift => Theme.of(this).extension<SiftPalette>()!;
}

/// Four-pixel spacing rhythm. Screens use a little more air than the default.
abstract final class SiftSpace {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
  static const page = 20.0;
}

abstract final class SiftRadius {
  static const xs = 3.0;
  static const sm = 6.0;
  static const md = 10.0;
  static const lg = 16.0;
  static const pill = 999.0;
}

class SiftTheme {
  static ThemeData build(
    Brightness brightness, {
    double textScale = 1.0,
    bool useSerif = true,
  }) {
    final p = brightness == Brightness.dark
        ? SiftPalette.dark
        : SiftPalette.light;
    final base = brightness == Brightness.dark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);
    final displayFamily = useSerif ? 'Instrument Serif' : 'IBM Plex Sans';
    final displayWeight = useSerif ? FontWeight.w400 : FontWeight.w600;

    final body = TextTheme(
      displayLarge: TextStyle(
        fontFamily: displayFamily,
        fontSize: 58 * textScale,
        height: 0.96,
        letterSpacing: -1.2,
        color: p.ink,
        fontWeight: displayWeight,
      ),
      displayMedium: TextStyle(
        fontFamily: displayFamily,
        fontSize: 44 * textScale,
        height: 1.0,
        letterSpacing: -0.8,
        color: p.ink,
        fontWeight: displayWeight,
      ),
      displaySmall: TextStyle(
        fontFamily: displayFamily,
        fontSize: 34 * textScale,
        height: 1.08,
        letterSpacing: -0.4,
        color: p.ink,
        fontWeight: displayWeight,
      ),
      headlineLarge: TextStyle(
        fontFamily: displayFamily,
        fontSize: 30 * textScale,
        height: 1.12,
        letterSpacing: -0.3,
        color: p.ink,
      ),
      headlineMedium: TextStyle(
        fontFamily: displayFamily,
        fontSize: 26 * textScale,
        height: 1.15,
        color: p.ink,
      ),
      headlineSmall: TextStyle(
        fontFamily: displayFamily,
        fontSize: 22 * textScale,
        height: 1.2,
        color: p.ink,
      ),
      titleLarge: TextStyle(
        fontFamily: 'IBM Plex Sans',
        fontSize: 19 * textScale,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: p.ink,
      ),
      titleMedium: TextStyle(
        fontFamily: 'IBM Plex Sans',
        fontSize: 16 * textScale,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: p.ink,
      ),
      titleSmall: TextStyle(
        fontFamily: 'IBM Plex Sans',
        fontSize: 14 * textScale,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: p.ink,
      ),
      bodyLarge: TextStyle(
        fontFamily: 'IBM Plex Sans',
        fontSize: 16 * textScale,
        height: 1.55,
        color: p.inkSoft,
      ),
      bodyMedium: TextStyle(
        fontFamily: 'IBM Plex Sans',
        fontSize: 14.5 * textScale,
        height: 1.5,
        color: p.inkSoft,
      ),
      bodySmall: TextStyle(
        fontFamily: 'IBM Plex Sans',
        fontSize: 12.5 * textScale,
        height: 1.45,
        color: p.muted,
      ),
      labelLarge: TextStyle(
        fontFamily: 'IBM Plex Sans',
        fontSize: 14 * textScale,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: p.ink,
      ),
      labelMedium: TextStyle(
        fontFamily: 'IBM Plex Mono',
        fontSize: 11 * textScale,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.9,
        color: p.muted,
      ),
      labelSmall: TextStyle(
        fontFamily: 'IBM Plex Mono',
        fontSize: 10 * textScale,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.7,
        color: p.faint,
      ),
    );

    final scheme = ColorScheme(
      brightness: brightness,
      primary: p.moss,
      onPrimary: p.isDark ? const Color(0xFF142016) : const Color(0xFFF9F6EE),
      primaryContainer: p.mossWash,
      onPrimaryContainer: p.mossDeep,
      secondary: p.clay,
      onSecondary: const Color(0xFFFFF8F2),
      secondaryContainer: p.clayWash,
      onSecondaryContainer: p.ink,
      tertiary: p.gold,
      onTertiary: p.ink,
      error: p.danger,
      onError: const Color(0xFFFFF8F4),
      surface: p.paper,
      onSurface: p.ink,
      surfaceContainerHighest: p.surfaceRaised,
      onSurfaceVariant: p.muted,
      outline: p.line,
      outlineVariant: p.line,
      shadow: const Color(0x33000000),
      scrim: const Color(0x66000000),
      inverseSurface: p.ink,
      onInverseSurface: p.paper,
      inversePrimary: p.mossDeep,
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: p.paper,
      canvasColor: p.paper,
      cardColor: p.surface,
      dividerColor: p.line,
      shadowColor: const Color(0x1A000000),
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      textTheme: body.apply(
        bodyColor: p.inkSoft,
        displayColor: p.ink,
      ),
      primaryTextTheme: body,
      extensions: [p],
      appBarTheme: AppBarTheme(
        backgroundColor: p.paper,
        foregroundColor: p.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: SiftSpace.page,
        titleTextStyle: body.titleMedium,
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: p.paper,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: p.paper,
              ),
      ),
      dividerTheme: DividerThemeData(
        color: p.line,
        thickness: 1,
        space: 1,
      ),
      iconTheme: IconThemeData(color: p.ink, size: 22),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        isDense: true,
        hintStyle: body.bodyMedium?.copyWith(color: p.faint),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.moss,
        selectionColor: p.moss.withOpacity(0.22),
        selectionHandleColor: p.moss,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.isDark ? p.surfaceRaised : p.mossDeep,
        contentTextStyle: body.bodyMedium?.copyWith(
          color: p.isDark ? p.ink : const Color(0xFFF6F1E7),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SiftRadius.sm),
        ),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        elevation: 0,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: p.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        showDragHandle: true,
        dragHandleColor: p.lineStrong,
      ),
      dialogTheme: DialogTheme(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SiftRadius.lg),
        ),
        titleTextStyle: body.headlineSmall,
        contentTextStyle: body.bodyMedium,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.muted,
        textColor: p.ink,
        contentPadding: const EdgeInsets.symmetric(horizontal: SiftSpace.page),
        minLeadingWidth: 24,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith(
          (states) => states.contains(MaterialState.selected) ? p.surface : p.muted,
        ),
        trackColor: MaterialStateProperty.resolveWith(
          (states) => states.contains(MaterialState.selected) ? p.moss : p.line,
        ),
        trackOutlineColor: MaterialStateProperty.all(Colors.transparent),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// Small mono kicker used above sections and results.
class SiftKicker extends StatelessWidget {
  const SiftKicker(this.text, {super.key, this.color, this.trailing});

  final String text;
  final Color? color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Row(
      children: [
        Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color ?? p.muted,
                letterSpacing: 1.4,
                fontSize: 10,
              ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ],
      ],
    );
  }
}
