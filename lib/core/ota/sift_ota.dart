/// The two update channels Sift uses.
///
/// The interface channel carries a tiny JSON document describing colour and
/// home-screen choices. The release channel points at a signed-by-checksum APK
/// on GitHub Releases. Neither channel can replace code silently: the interface
/// bundle is data only, and Android always asks before installing an APK.
abstract final class SiftOta {
  static const String baseUrl = String.fromEnvironment(
    'SIFT_OTA_BASE',
    defaultValue: 'https://sift-ota.vercel.app',
  );

  static const Duration requestTimeout = Duration(seconds: 5);
  static const int maxUiBytes = 16 * 1024;
  static const int maxUpdateBytes = 8 * 1024;

  static Uri get uiEndpoint => _endpoint('/api/ui');
  static Uri get updateEndpoint => _endpoint('/api/update');

  static String get serviceHost => _endpoint('/').host;

  static Uri _endpoint(String path) {
    final parsed = Uri.tryParse(baseUrl);
    if (parsed == null || parsed.scheme != 'https' || parsed.host.isEmpty) {
      return Uri.parse('https://sift-ota.vercel.app$path');
    }
    final prefix = parsed.path.replaceFirst(RegExp(r'/+$'), '');
    return parsed.replace(
      path: '$prefix$path',
      query: null,
      fragment: null,
    );
  }

  /// Update APKs must come from Sift's service or GitHub's release CDN.
  static bool isTrustedApkUrl(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return false;
    final host = uri.host.toLowerCase();
    if (host == serviceHost.toLowerCase()) return true;
    if (host == 'github.com') return true;
    return host.endsWith('.githubusercontent.com');
  }
}