/// Constants and configuration for the YouTube WebView shell.
class AppConstants {
  /// Breakpoint width in logical pixels.
  /// Devices with width >= 768px (tablets, foldables unfolded, desktop windows)
  /// will receive the desktop experience (`www.youtube.com`).
  /// Devices with width < 768px (phones in portrait/compact mode)
  /// will receive the mobile experience (`m.youtube.com`).
  static const double desktopBreakpoint = 768.0;

  /// Default mobile entry point.
  static const String mobileUrl = 'https://m.youtube.com';

  /// Default desktop entry point.
  static const String desktopUrl = 'https://www.youtube.com';

  /// Modern Chrome Mobile User-Agent string.
  /// Omits embedded webview markers (`wv`, `Version/4.0`) to avoid unnecessary
  /// browser degradation and provide the full mobile web experience.
  static const String mobileUserAgent =
      'Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36';

  /// Modern Chrome Desktop User-Agent string.
  /// Presents as a standard macOS Chrome desktop client to unlock YouTube's
  /// full multi-column grid, sidebar, and desktop media player.
  static const String desktopUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

  /// YouTube Music entry point.
  static const String musicUrl = 'https://music.youtube.com';

  /// YouTube Kids entry point.
  static const String kidsUrl = 'https://www.youtubekids.com';

  /// Allowed host domains for top-level navigation.
  /// Restricts navigation strictly to YouTube, YouTube Music, YouTube Kids, and essential Google services.
  static const List<String> allowedHostDomains = [
    'youtube.com',
    'youtubekids.com',
    'youtu.be',
    'yt.be',
  ];

  /// Exact Google pages needed for authentication and consent. Keeping these
  /// exact prevents arbitrary Google-hosted/user-content pages from becoming
  /// an escape hatch in the top-level navigation allowlist.
  static const List<String> allowedExactHosts = [
    'google.com',
    'www.google.com',
    'accounts.google.com',
    'myaccount.google.com',
    'consent.google.com',
  ];
}

/// Checks whether the given host belongs to an allowed YouTube or Google domain.
bool isHostAllowed(String? host) {
  if (host == null || host.trim().isEmpty) return false;
  final cleanHost = host.trim().toLowerCase();
  if (AppConstants.allowedExactHosts.contains(cleanHost)) return true;
  for (final domain in AppConstants.allowedHostDomains) {
    if (cleanHost == domain || cleanHost.endsWith('.$domain')) {
      return true;
    }
  }
  return false;
}

/// Transforms a YouTube URL between mobile (`m.youtube.com`) and desktop (`www.youtube.com`),
/// preserving the path and query parameters (such as `/watch?v=...` or `/results?search_query=...`).
Uri switchYouTubeExperienceUri(Uri currentUri, {required bool toDesktop}) {
  final targetHost = toDesktop ? 'www.youtube.com' : 'm.youtube.com';
  final currentHost = currentUri.host.toLowerCase();

  if (currentHost == 'm.youtube.com' ||
      currentHost == 'www.youtube.com' ||
      currentHost == 'youtube.com') {
    return currentUri.replace(scheme: 'https', host: targetHost);
  }

  return Uri.parse(
    toDesktop ? AppConstants.desktopUrl : AppConstants.mobileUrl,
  );
}
