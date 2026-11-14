import 'package:flutter/material.dart';

/// A small, data-only interface bundle. It can change colour and home-screen
/// choices but can never introduce code, open a network endpoint, or touch
/// search/index settings.
@immutable
class SiftUiConfig {
  const SiftUiConfig({
    this.version = 0,
    this.accent,
    this.tagline = defaultTagline,
    this.starters = defaultStarters,
    this.showShortcuts = true,
    this.showPrivacyCard = true,
    this.compactHome = false,
  });

  static const String defaultTagline = 'No ads. No account. No profile.';

  static const List<String> defaultStarters = <String>[
    'Rust ownership',
    'How does a heat pump work?',
    'Open source maps',
    'Best time to visit Japan',
  ];

  /// Zero means the bundle compiled into the APK.
  final int version;

  /// An accessible accent hue, or null for the shipped blue.
  final Color? accent;
  final String tagline;
  final List<String> starters;
  final bool showShortcuts;
  final bool showPrivacyCard;
  final bool compactHome;

  static const SiftUiConfig builtIn = SiftUiConfig();

  /// Returns null when the document is not a usable interface bundle.
  /// Individual invalid fields fall back to their shipped values.
  static SiftUiConfig? fromJson(Map<String, dynamic> json) {
    final version = _intInRange(json['version'], 1, 1000000);
    if (version == null) return null;

    return SiftUiConfig(
      version: version,
      accent: _accent(json['accent']),
      tagline: _line(json['tagline'], 90) ?? defaultTagline,
      starters: _starters(json['starters']),
      showShortcuts: _bool(json['show_shortcuts'], fallback: true),
      showPrivacyCard: _bool(json['show_privacy_card'], fallback: true),
      compactHome: _bool(json['compact_home'], fallback: false),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': version,
        if (accent != null) 'accent': hexOf(accent!),
        'tagline': tagline,
        'starters': starters,
        'show_shortcuts': showShortcuts,
        'show_privacy_card': showPrivacyCard,
        'compact_home': compactHome,
      };

  static String hexOf(Color color) {
    final value = color.value & 0xFFFFFF;
    return '#${value.toRadixString(16).padLeft(6, '0')}';
  }

  static int? _intInRange(Object? raw, int low, int high) {
    if (raw is int) return raw >= low && raw <= high ? raw : null;
    if (raw is num && raw == raw.roundToDouble()) {
      final value = raw.toInt();
      return value >= low && value <= high ? value : null;
    }
    return null;
  }

  static bool _bool(Object? raw, {required bool fallback}) {
    return raw is bool ? raw : fallback;
  }

  static String? _line(Object? raw, int max) {
    if (raw is! String) return null;
    final clean = raw
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (clean.isEmpty) return null;
    if (clean.length <= max) return clean;
    final cut = clean.substring(0, max);
    final space = cut.lastIndexOf(' ');
    return (space > max * 0.6 ? cut.substring(0, space) : cut).trimRight();
  }

  static List<String> _starters(Object? raw) {
    if (raw is! List) return defaultStarters;
    final seen = <String>{};
    final result = <String>[];
    for (final item in raw) {
      final value = _line(item, 48);
      if (value == null) continue;
      if (!seen.add(value.toLowerCase())) continue;
      result.add(value);
      if (result.length == 4) break;
    }
    // An explicitly empty list hides the starter row; malformed material keeps
    // the shipped suggestions rather than producing an empty landing.
    return result.isEmpty && raw.isNotEmpty ? defaultStarters : result;
  }

  static Color? _accent(Object? raw) {
    if (raw is! String) return null;
    final match = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(raw.trim());
    if (match == null) return null;
    final value = int.parse(match.group(1)!, radix: 16);
    var color = Color(0xFF000000 | value);
    var hsl = HSLColor.fromColor(color);
    // Accent text and buttons sit on white. Darken low-contrast hues until
    // they remain readable instead of rejecting a whole bundle over colour.
    for (var step = 0; step < 18; step++) {
      if (_contrastOnWhite(color) >= 4.5) break;
      hsl = hsl.withLightness(
        (hsl.lightness - 0.035).clamp(0.0, 1.0).toDouble(),
      );
      color = hsl.toColor();
    }
    return color;
  }

  static double _contrastOnWhite(Color color) {
    final luminance = color.computeLuminance();
    return (1.05) / (luminance + 0.05);
  }
}