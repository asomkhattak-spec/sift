import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Sift's visual language: a clean, search-first surface built from white,
/// neutral greys and Google's blue accent family. The palette deliberately
/// keeps the original field names so screens can evolve without a risky
/// rename across the whole app.
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

  /// Google's brand colours, used only for the multicolour wordmark.
  static const wordmarkBlue = Color(0xFF4285F4);
  static const wordmarkRed = Color(0xFFEA4335);
  static const wordmarkYellow = Color(0xFFFBBC04);
  static const wordmarkGreen = Color(0xFF34A853);

  static const light = SiftPalette(
    paper: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF8F9FA),
    ink: Color(0xFF202124),
    inkSoft: Color(0xFF3C4043),
    muted: Color(0xFF5F6368),
    faint: Color(0xFF80868B),
    line: Color(0xFFDADCE0),
    lineStrong: Color(0xFFBDC1C6),
    moss: Color(0xFF1A73E8),
    mossDeep: Color(0xFF0B57D0),
    mossWash: Color(0xFFE8F0FE),
    clay: Color(0xFFEA4335),
    clayWash: Color(0xFFFCE8E6),
    gold: Color(0xFFFBBC04),
    danger: Color(0xFFD93025),
    browserChrome: Color(0xFFF8F9FA),
    isDark: false,
  );

  static const dark = SiftPalette(
    paper: Color(0xFF202124),
    surface: Color(0xFF202124),
    surfaceRaised: Color(0xFF303134),
    ink: Color(0xFFE8EAED),
    inkSoft: Color(0xFFBDC1C6),
    muted: Color(0xFF9AA0A6),
    faint: Color(0xFF80868B),
    line: Color(0xFF3C4043),
    lineStrong: Color(0xFF5F6368),
    moss: Color(0xFF8AB4F8),
    mossDeep: Color(0xFFAECBFA),
    mossWash: Color(0xFF283B57),
    clay: Color(0xFFF28B82),
    clayWash: Color(0xFF3C2523),
    gold: Color(0xFFFDD663),
    danger: Color(0xFFF28B82),
    browserChrome: Color(0xFF292A2D),
    isDark: true,
  );

  /// Derives the interactive colour family from a remote accent while keeping
  /// every other surface neutral. Light accents are pre-checked for contrast
  /// in [SiftUiConfig]; dark mode lifts them until links stay legible.
  SiftPalette withAccent(Color accent) {
    final hsl = HSLColor.fromColor(accent);
    final clamped = hsl.saturation < 0.08
        ? hsl
        : hsl.withSaturation(hsl.saturation.clamp(0.35, 0.95).toDouble());
    final Color strong;
    final Color deep;
    final Color wash;
    if (isDark) {
      strong = clamped.withLightness(0.74).toColor();
      deep = clamped.withLightness(0.84).toColor();
      wash = Color.alphaBlend(strong.withOpacity(0.18), paper);
    } else {
      strong = accent;
      deep = Color.alphaBlend(Colors.black.withOpacity(0.18), accent);
      wash = Color.alphaBlend(accent.withOpacity(0.10), paper);
    }
    return copyWith(moss: strong, mossDeep: deep, mossWash: wash);
  }

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

/// A four-pixel spacing rhythm with 16-pixel screen margins.
abstract final class SiftSpace {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
  static const page = 16.0;
}

abstract final class SiftRadius {
  static const xs = 8.0;
  static const sm = 10.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const pill = 999.0;
}

class SiftTheme {
  static ThemeData build(
    Brightness brightness, {
    double textScale = 1.0,
    bool useSerif = false,
    Color? accent,
  }) {
    final basePalette = brightness == Brightness.dark
        ? SiftPalette.dark
        : SiftPalette.light;
    final p = accent == null ? basePalette : basePalette.withAccent(accent);
    final base = brightness == Brightness.dark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);
    final displayFamily = useSerif ? 'Instrument Serif' : 'Roboto';
    final displayWeight = useSerif ? FontWeight.w400 : FontWeight.w500;

    TextStyle display(double size, double height, double spacing) {
      return TextStyle(
        fontFamily: displayFamily,
        fontSize: size * textScale,
        height: height,
        letterSpacing: spacing,
        color: p.ink,
        fontWeight: displayWeight,
      );
    }

    TextStyle sans(
      double size,
      double height, {
      FontWeight weight = FontWeight.w400,
      Color? color,
      double spacing = 0,
    }) {
      return TextStyle(
        fontFamily: 'Roboto',
        fontSize: size * textScale,
        height: height,
        letterSpacing: spacing,
        color: color ?? p.inkSoft,
        fontWeight: weight,
      );
    }

    final body = TextTheme(
      displayLarge: display(46, 1.05, -0.8),
      displayMedium: display(36, 1.1, -0.5),
      displaySmall: display(28, 1.15, -0.2),
      headlineLarge: display(26, 1.2, -0.1),
      headlineMedium: display(23, 1.22, 0),
      headlineSmall: display(20, 1.28, 0),
      titleLarge: sans(18, 1.35, weight: FontWeight.w500),
      titleMedium: sans(16, 1.4, weight: FontWeight.w500),
      titleSmall: sans(14, 1.4, weight: FontWeight.w500),
      bodyLarge: sans(16, 1.5),
      bodyMedium: sans(14.5, 1.5),
      bodySmall: sans(12.5, 1.45, color: p.muted),
      labelLarge: sans(14, 1.25, weight: FontWeight.w500, spacing: 0.1),
      labelMedium: sans(12, 1.3, weight: FontWeight.w500, color: p.muted),
      labelSmall: sans(11, 1.3, weight: FontWeight.w400, color: p.faint),
    );

    final scheme = ColorScheme(
      brightness: brightness,
      primary: p.moss,
      onPrimary: Colors.white,
      primaryContainer: p.mossWash,
      onPrimaryContainer: p.mossDeep,
      secondary: p.clay,
      onSecondary: Colors.white,
      secondaryContainer: p.clayWash,
      onSecondaryContainer: p.ink,
      tertiary: p.gold,
      onTertiary: const Color(0xFF202124),
      error: p.danger,
      onError: Colors.white,
      surface: p.paper,
      onSurface: p.ink,
      surfaceContainerHighest: p.surfaceRaised,
      onSurfaceVariant: p.muted,
      outline: p.line,
      outlineVariant: p.line,
      shadow: const Color(0x1F000000),
      scrim: const Color(0x66000000),
      inverseSurface: p.ink,
      onInverseSurface: p.paper,
      inversePrimary: p.mossDeep,
    );

    return base.copyWith(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: p.paper,
      canvasColor: p.paper,
      cardColor: p.surface,
      dividerColor: p.line,
      shadowColor: const Color(0x1F000000),
      splashFactory: InkRipple.splashFactory,
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
        titleTextStyle: body.titleLarge,
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
      cardTheme: CardTheme(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SiftRadius.lg),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: p.line,
        thickness: 1,
        space: 1,
      ),
      iconTheme: IconThemeData(color: p.muted, size: 22),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceRaised,
        isDense: true,
        hintStyle: body.bodyMedium?.copyWith(color: p.faint),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SiftRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SiftRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SiftRadius.md),
          borderSide: BorderSide(color: p.moss, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SiftRadius.md),
          borderSide: BorderSide(color: p.danger),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.moss,
        selectionColor: p.moss.withOpacity(0.2),
        selectionHandleColor: p.moss,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.isDark ? p.surfaceRaised : p.ink,
        contentTextStyle: body.bodyMedium?.copyWith(
          color: p.isDark ? p.ink : Colors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SiftRadius.sm),
        ),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        elevation: 2,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: p.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: false,
        dragHandleColor: p.lineStrong,
      ),
      dialogTheme: DialogTheme(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SiftRadius.xl),
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
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.moss,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: body.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SiftRadius.pill),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.moss,
          side: BorderSide(color: p.line),
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: body.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SiftRadius.pill),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.moss,
          textStyle: body.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SiftRadius.pill),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: p.muted,
          highlightColor: p.surfaceRaised,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.white : p.muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? p.moss : p.line,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
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
