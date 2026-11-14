import 'package:flutter/widgets.dart';

import '../ota/remote_ui_service.dart';
import '../ota/update_service.dart';
import '../search/local_index.dart';
import '../search/search_engine.dart';
import 'http_service.dart';
import 'library_service.dart';
import 'native_bridge.dart';
import 'search_bus.dart';
import 'settings_service.dart';
import 'sift_core.dart';
import 'tracker_blocker.dart';

/// Services are created once in `main()` and exposed through one inherited
/// widget. Screens listen to the individual `ChangeNotifier`s they use, which
/// keeps rebuilds local and avoids a state-management dependency.
@immutable
class SiftServices {
  const SiftServices({
    required this.settings,
    required this.library,
    required this.localIndex,
    required this.engine,
    required this.http,
    required this.native,
    required this.blocker,
    required this.core,
    required this.searchBus,
    required this.remoteUi,
    required this.updates,
  });

  final SettingsService settings;
  final LibraryService library;
  final LocalIndex localIndex;
  final SearchEngine engine;
  final SiftHttp http;
  final NativeBridge native;
  final TrackerBlocker blocker;
  final SiftCore core;
  final SearchBus searchBus;
  final RemoteUiService remoteUi;
  final UpdateService updates;
}

class SiftScope extends InheritedWidget {
  const SiftScope({
    required this.services,
    required super.child,
    super.key,
  });

  final SiftServices services;

  static SiftScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SiftScope>();
    assert(scope != null, 'SiftScope is missing above this widget.');
    return scope!;
  }

  static SiftServices servicesOf(BuildContext context) => of(context).services;

  /// Non-subscribing lookup for `initState`, where registering an inherited
  /// dependency is not allowed. The service objects live for the whole app, so
  /// a screen can safely cache this value once.
  static SiftServices readServicesOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<SiftScope>();
    assert(scope != null, 'SiftScope is missing above this widget.');
    return scope!.services;
  }

  static SiftServices? maybeServicesOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SiftScope>()?.services;

  @override
  bool updateShouldNotify(SiftScope oldWidget) =>
      !identical(services, oldWidget.services);
}
