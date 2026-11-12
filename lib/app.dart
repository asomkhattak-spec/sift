import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'core/services/settings_service.dart';
import 'core/services/sift_scope.dart';
import 'core/theme/sift_theme.dart';
import 'screens/root_shell.dart';
import 'widgets/sift_ui.dart';

class SiftApp extends StatefulWidget {
  const SiftApp({required this.services, super.key});

  final SiftServices services;

  @override
  State<SiftApp> createState() => _SiftAppState();
}

class _SiftAppState extends State<SiftApp> {
  SettingsService get _settings => widget.services.settings;
  String? _webViewProxyKey;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_applySystemSettings);
    _applySystemSettings();
  }

  @override
  void dispose() {
    _settings.removeListener(_applySystemSettings);
    super.dispose();
  }

  void _applySystemSettings() {
    final settings = _settings;
    widget.services.http.setProxy(
      enabled: settings.proxyEnabled,
      host: settings.proxyHost,
      port: settings.proxyPort,
    );
    widget.services.native.setSecureScreen(settings.secureScreen);
    unawaited(_applyWebViewProxy());
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );
  }

  /// Android applies a proxy to the whole WebView process, not one tab, so
  /// keep it in step with the same endpoint used by the feed client.
  Future<void> _applyWebViewProxy() async {
    if (!Platform.isAndroid) return;
    final settings = _settings;
    final key = settings.proxyEnabled
        ? '${settings.proxyHost}:${settings.proxyPort}'
        : '';
    if (key == _webViewProxyKey) return;
    _webViewProxyKey = key;
    try {
      final controller = ProxyController.instance();
      if (!settings.proxyEnabled) {
        await controller.clearProxyOverride();
        return;
      }
      final host = settings.proxyHost
          .replaceFirst(RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://'), '')
          .replaceAll(RegExp(r'/+$'), '');
      await controller.setProxyOverride(
        settings: ProxySettings(
          proxyRules: [ProxyRule(url: '$host:${settings.proxyPort}')],
          bypassRules: const ['localhost', '127.0.0.1', '[::1]'],
          bypassSimpleHostnames: true,
        ),
      );
    } catch (_) {
      // ProxyController needs Android WebView 10+ and a recent WebView build.
      // The app still works directly when the platform cannot honour it.
      _webViewProxyKey = null;
    }
  }

  ThemeMode get _themeMode => switch (_settings.themeMode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  @override
  Widget build(BuildContext context) {
    return SiftScope(
      services: widget.services,
      child: AnimatedBuilder(
        animation: _settings,
        builder: (context, _) {
          return MaterialApp(
            title: 'Sift',
            debugShowCheckedModeBanner: false,
            themeMode: _themeMode,
            theme: SiftTheme.build(
              Brightness.light,
              useSerif: _settings.serifHeadings,
            ),
            darkTheme: SiftTheme.build(
              Brightness.dark,
              useSerif: _settings.serifHeadings,
            ),
            scrollBehavior: const _SiftScrollBehavior(),
            builder: (context, child) {
              final media = MediaQuery.of(context);
              final factor =
                  media.textScaler.scale(16) / 16 * _settings.textScale;
              return MediaQuery(
                data: media.copyWith(
                  textScaler: TextScaler.linear(factor),
                ),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: const RootShell(),
          );
        },
      ),
    );
  }
}

class _SiftScrollBehavior extends MaterialScrollBehavior {
  const _SiftScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // Stretch and glow indicators both fight the paper-like surfaces.
    return child;
  }
}

/// Shown only when the platform services cannot start at all.
class SiftBootstrapError extends StatelessWidget {
  const SiftBootstrapError({required this.error, super.key});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: SiftTheme.build(Brightness.light),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SiftWordmark(size: 34),
                    const SizedBox(height: 28),
                    Text(
                      'Sift could not open its local store.',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No search was sent anywhere. Restart the app; if this '
                      'continues, clearing app storage will rebuild the local '
                      'settings and index.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    SelectableText(
                      '$error',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
