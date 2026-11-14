// Visual capture harness. This file is intentionally not named `*_test.dart`,
// so the normal `flutter test` run in CI does not depend on golden files. Run it
// explicitly to render the interface to PNGs:
//
//   flutter test --update-goldens test/visual/render_screens.dart
//
// The images land in test/visual/goldens and are uploaded by the optional
// `screenshots` job in the build workflow.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sift/app.dart';
import 'package:sift/core/search/local_index.dart';
import 'package:sift/core/search/search_engine.dart';
import 'package:sift/core/services/http_service.dart';
import 'package:sift/core/services/library_service.dart';
import 'package:sift/core/services/native_bridge.dart';
import 'package:sift/core/services/search_bus.dart';
import 'package:sift/core/services/settings_service.dart';
import 'package:sift/core/services/sift_core.dart';
import 'package:sift/core/services/sift_scope.dart';
import 'package:sift/core/services/tracker_blocker.dart';

const _rss = '''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel>
  <item><title>Rust ownership, explained</title>
    <link>https://example.org/rust-ownership</link>
    <description>A practical tour of borrow checking and lifetimes.</description>
    <pubDate>Wed, 11 Nov 2026 08:00:00 GMT</pubDate></item>
  <item><title>How a heat pump actually works</title>
    <link>https://example.org/heat-pump</link>
    <description>Why the efficiency number is not a mistake.</description>
    <pubDate>Tue, 10 Nov 2026 10:30:00 GMT</pubDate></item>
  <item><title>The quiet return of gemini</title>
    <link>https://example.org/gemini</link>
    <description>Small protocols, small pages, small servers.</description>
    <pubDate>Mon, 09 Nov 2026 09:15:00 GMT</pubDate></item>
</channel></rss>
''';

const _wikipedia = '''
{"query":{"pages":{
  "1":{"index":1,"pageid":1,"title":"Rust (programming language)",
    "extract":"Rust is a multi-paradigm, memory-safe systems programming language.",
    "thumbnail":{"source":"https://example.org/rust.png"}},
  "2":{"index":2,"pageid":2,"title":"Heat pump",
    "extract":"A heat pump moves thermal energy against the temperature gradient."}
}}}
''';

const _hn = '''
{"hits":[
  {"objectID":"1","title":"Ask HN: how do you search privately?","url":"https://news.ycombinator.com/item?id=1","points":128,"num_comments":64,"author":"quiet","created_at":"2026-11-11T09:00:00Z"},
  {"objectID":"2","title":"The cost of an advertising-supported web","url":"https://example.org/ads","points":97,"num_comments":41,"author":"fewer","created_at":"2026-11-10T18:00:00Z"},
  {"objectID":"3","title":"A tiny full-text index on a phone","url":"https://example.org/index","points":54,"num_comments":12,"author":"shelf","created_at":"2026-11-09T12:00:00Z"}
]}
''';

const _openverse = '''
{"results":[
  {"title":"Morning light","url":"https://images.example.org/1.jpg","thumbnail":"https://images.example.org/1-t.jpg","foreign_landing_url":"https://example.org/light","license":"by","creator":"A. Photographer","provider":"flickr","width":1600,"height":1067},
  {"title":"Concrete geometry","url":"https://images.example.org/2.jpg","thumbnail":"https://images.example.org/2-t.jpg","foreign_landing_url":"https://example.org/concrete","license":"cc0","creator":"B. Builder","provider":"museum","width":1200,"height":1500}
]}
''';

class _FakeHttp extends SiftHttp {
  @override
  Future<String> getString(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 9),
    int cacheSeconds = 0,
  }) async {
    final value = url.toLowerCase();
    if (value.contains('wikipedia')) return _wikipedia;
    if (value.contains('hn.algolia')) return _hn;
    if (value.contains('openverse')) return _openverse;
    if (value.contains('bing.com') || value.contains('news.google')) return _rss;
    return '{}';
  }

  @override
  Future<Map<String, dynamic>> getJson(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 9),
    int cacheSeconds = 0,
  }) async {
    final decoded = jsonDecode(await getString(url, headers: headers));
    return decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
  }
}

Future<void> _loadFonts() async {
  final families = <String, List<String>>{
    'Roboto': [
      'assets/fonts/Roboto-Regular.ttf',
      'assets/fonts/Roboto-Medium.ttf',
      'assets/fonts/Roboto-Bold.ttf',
    ],
    'Instrument Serif': [
      'assets/fonts/InstrumentSerif-Regular.ttf',
      'assets/fonts/InstrumentSerif-Italic.ttf',
    ],
    'IBM Plex Sans': [
      'assets/fonts/IBMPlexSans-Regular.ttf',
      'assets/fonts/IBMPlexSans-Medium.ttf',
      'assets/fonts/IBMPlexSans-SemiBold.ttf',
    ],
    'IBM Plex Mono': [
      'assets/fonts/IBMPlexMono-Regular.ttf',
      'assets/fonts/IBMPlexMono-Medium.ttf',
    ],
  };
  for (final entry in families.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      loader.addFont(rootBundle.load(path));
    }
    await loader.load();
  }

  // The icon font ships inside the Flutter SDK but is not part of the app's
  // asset bundle, so widget-test renders draw empty boxes without this.
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final iconFile = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (await iconFile.exists()) {
      final bytes = await iconFile.readAsBytes();
      final icons = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await icons.load();
    }
  }
}

Future<SiftServices> _services() async {
  SharedPreferences.setMockInitialValues({'sift.firstRun': false});
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsService(prefs);
  final http = _FakeHttp();
  final library = LibraryService(prefs, settings);
  final index = LocalIndex(prefs, http);
  await index.load();
  return SiftServices(
    settings: settings,
    library: library,
    localIndex: index,
    engine: SearchEngine(settings: settings, http: http, localIndex: index),
    http: http,
    native: NativeBridge(),
    blocker: TrackerBlocker(),
    core: SiftCore.instance,
    searchBus: SearchBus(),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  testWidgets('captures the primary screens', (tester) async {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.library == 'image resource service' ||
          details.exception.toString().contains('NetworkImageLoadException')) {
        return;
      }
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    await tester.binding.setSurfaceSize(const Size(393, 851));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final services = await _services();
    await tester.pumpWidget(SiftApp(services: services));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(SiftApp),
      matchesGoldenFile('goldens/01_search.png'),
    );

    await tester.tap(find.byKey(const ValueKey('nav-Discover')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(SiftApp),
      matchesGoldenFile('goldens/02_discover.png'),
    );

    await tester.tap(find.byKey(const ValueKey('nav-My Search')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(SiftApp),
      matchesGoldenFile('goldens/03_my_search.png'),
    );

    await tester.tap(find.byKey(const ValueKey('nav-Library')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(SiftApp),
      matchesGoldenFile('goldens/04_library.png'),
    );

    await tester.tap(find.byKey(const ValueKey('nav-Search')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'rust programming');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(SiftApp),
      matchesGoldenFile('goldens/05_results.png'),
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/06_settings.png'),
    );

    services.native.dispose();
  });
}
