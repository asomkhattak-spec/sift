import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/search/local_index.dart';
import 'core/search/search_engine.dart';
import 'core/services/http_service.dart';
import 'core/services/library_service.dart';
import 'core/services/native_bridge.dart';
import 'core/services/search_bus.dart';
import 'core/services/settings_service.dart';
import 'core/services/sift_core.dart';
import 'core/services/sift_scope.dart';
import 'core/services/tracker_blocker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  try {
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs);
    final core = SiftCore.instance;
    await core.initialize();

    final http = SiftHttp();
    final library = LibraryService(prefs, settings);
    final localIndex = LocalIndex(prefs, http, core: core);
    await localIndex.load();

    final native = NativeBridge()..initialize();
    final services = SiftServices(
      settings: settings,
      library: library,
      localIndex: localIndex,
      engine: SearchEngine(
        settings: settings,
        http: http,
        localIndex: localIndex,
        core: core,
      ),
      http: http,
      native: native,
      blocker: TrackerBlocker(),
      core: core,
      searchBus: SearchBus(),
    );

    runApp(SiftApp(services: services));
  } catch (error, stack) {
    debugPrint('Sift failed to start: $error\n$stack');
    runApp(SiftBootstrapError(error: error));
  }
}
