import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../screens/browser/browser_screen.dart';
import '../../widgets/sift_ui.dart';
import '../services/sift_scope.dart';
import 'text_utils.dart';

/// Opens links according to the user's browser preference, strips known
/// tracking parameters when that setting is on, and records a visit only when
/// the library's own privacy checks allow it.
Future<void> openSiftUrl(
  BuildContext context,
  String rawUrl, {
  String title = '',
  bool? forceInApp,
}) async {
  final services = SiftScope.servicesOf(context);
  final settings = services.settings;
  final cleaned = settings.stripTrackingParams
      ? stripTrackingParams(rawUrl)
      : rawUrl;
  final uri = Uri.tryParse(cleaned);
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
    showSiftToast(context, 'That link is not a web address.', error: true);
    return;
  }

  await services.library.recordVisit(
    url: cleaned,
    title: title.isEmpty ? compactHostTitle(cleaned) : title,
  );

  final inApp = forceInApp ?? settings.openInApp;
  if (!context.mounted) return;
  if (inApp) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BrowserScreen(
          initialUrl: cleaned,
          initialTitle: title,
        ),
      ),
    );
    return;
  }

  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }
  if (!opened) opened = await services.native.openExternal(cleaned);
  if (!opened && context.mounted) {
    showSiftToast(context, 'No app on this device could open that link.',
        error: true);
  }
}

/// Sends a query to the Search tab and returns to the root route.
void startSiftSearch(BuildContext context, String query) {
  final clean = normalizeQuery(query);
  if (clean.isEmpty) return;
  final services = SiftScope.servicesOf(context);
  services.searchBus.submit(clean);
  Navigator.of(context).popUntil((route) => route.isFirst);
}

Future<bool> shareSiftText(
  BuildContext context, {
  required String text,
  String? title,
  String? url,
}) async {
  final services = SiftScope.servicesOf(context);
  final body = [text, if (url != null && url.isNotEmpty) url].join('\n\n');
  final shared = await services.native.shareText(
    text: body,
    title: title,
    url: url,
  );
  if (!shared && context.mounted) {
    copyText(context, body);
    return false;
  }
  return true;
}
