import 'package:flutter/material.dart';

const List<String> _monthsShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const List<String> _monthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

const List<String> _weekdaysLong = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

String greetingFor(DateTime now) {
  final hour = now.hour;
  if (hour < 5) return 'Still up?';
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  if (hour < 21) return 'Good evening';
  return 'Good night';
}

String longDate(DateTime date) {
  return '${_weekdaysLong[date.weekday - 1]}, ${_monthsLong[date.month - 1]} ${date.day}';
}

String fullDate(DateTime date) {
  return '${_monthsLong[date.month - 1]} ${date.day}, ${date.year}';
}

String shortDate(DateTime date) {
  final now = DateTime.now();
  if (date.year == now.year) {
    return '${_monthsShort[date.month - 1]} ${date.day}';
  }
  return '${_monthsShort[date.month - 1]} ${date.day}, ${date.year}';
}

String timeOfDayLabel(DateTime date) {
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  final suffix = date.hour < 12 ? 'am' : 'pm';
  return '$hour:$minute $suffix';
}

String relativeDate(DateTime? date, {DateTime? now}) {
  if (date == null) return '';
  final current = now ?? DateTime.now();
  final diff = current.difference(date);
  if (diff.isNegative) return 'just now';
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return shortDate(date);
}

String formatDuration(int? seconds) {
  if (seconds == null || seconds <= 0) return '';
  final minutes = seconds ~/ 60;
  final remaining = (seconds % 60).toString().padLeft(2, '0');
  if (minutes >= 60) {
    final hours = minutes ~/ 60;
    return '$hours:${(minutes % 60).toString().padLeft(2, '0')}:$remaining';
  }
  return '$minutes:$remaining';
}

String compactNumber(num value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(value >= 10000000 ? 0 : 1)}m';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}k';
  }
  return value.toString();
}

String pluralize(int count, String singular, [String? plural]) {
  return count == 1 ? singular : (plural ?? '${singular}s');
}

String firstLetter(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '·';
  return String.fromCharCode(trimmed.runes.first).toUpperCase();
}

/// A compact status line that does not pretend network anonymity.
String privacySummary({
  required bool privateMode,
  required bool blocking,
  required bool proxy,
}) {
  final parts = <String>[
    privateMode ? 'no saved activity' : 'history on this device',
    if (blocking) 'trackers filtered',
    if (proxy) 'proxy on',
  ];
  return parts.join(' · ');
}

TextStyle? monoStyle(BuildContext context) =>
    Theme.of(context).textTheme.labelMedium;
