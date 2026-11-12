import 'package:flutter_test/flutter_test.dart';
import 'package:sift/core/utils/formatters.dart';

void main() {
  test('greetingFor maps the day into human buckets', () {
    expect(greetingFor(DateTime(2026, 1, 1, 3)), 'Still up?');
    expect(greetingFor(DateTime(2026, 1, 1, 9)), 'Good morning');
    expect(greetingFor(DateTime(2026, 1, 1, 14)), 'Good afternoon');
    expect(greetingFor(DateTime(2026, 1, 1, 19)), 'Good evening');
    expect(greetingFor(DateTime(2026, 1, 1, 22)), 'Good night');
  });

  test('dates render without locale surprises', () {
    final date = DateTime(2026, 3, 7, 15, 5);
    expect(longDate(date), 'Saturday, March 7');
    expect(fullDate(date), 'March 7, 2026');
    expect(timeOfDayLabel(date), '3:05 pm');
    expect(timeOfDayLabel(DateTime(2026, 3, 7, 0, 1)), '12:01 am');
    final thisYear = DateTime(DateTime.now().year, 3, 7);
    expect(shortDate(thisYear), 'Mar 7');
  });

  test('relativeDate covers recent and older values', () {
    final now = DateTime(2026, 3, 7, 12);
    expect(relativeDate(null, now: now), '');
    expect(relativeDate(now, now: now), 'just now');
    expect(relativeDate(now.subtract(const Duration(minutes: 9)), now: now), '9m ago');
    expect(relativeDate(now.subtract(const Duration(hours: 4)), now: now), '4h ago');
    expect(relativeDate(now.subtract(const Duration(days: 1)), now: now), 'yesterday');
    expect(relativeDate(now.subtract(const Duration(days: 3)), now: now), '3d ago');
  });

  test('formatDuration handles nulls, minutes and hours', () {
    expect(formatDuration(null), '');
    expect(formatDuration(0), '');
    expect(formatDuration(75), '1:15');
    expect(formatDuration(3671), '1:01:11');
  });

  test('compactNumber shortens large values', () {
    expect(compactNumber(42), '42');
    expect(compactNumber(1200), '1.2k');
    expect(compactNumber(12500), '13k');
    expect(compactNumber(1500000), '1.5m');
    expect(compactNumber(12000000), '12m');
  });

  test('pluralize and firstLetter are predictable', () {
    expect(pluralize(1, 'tab'), 'tab');
    expect(pluralize(2, 'tab'), 'tabs');
    expect(pluralize(2, 'match', 'matches'), 'matches');
    expect(firstLetter('  sift'), 'S');
    expect(firstLetter(''), '·');
  });

  test('privacySummary never promises anonymity', () {
    final summary = privacySummary(privateMode: true, blocking: true, proxy: false);
    expect(summary, contains('no saved activity'));
    expect(summary, contains('trackers filtered'));
    expect(summary, isNot(contains('anonymous')));
  });
}
