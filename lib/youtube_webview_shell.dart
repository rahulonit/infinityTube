import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'ad_blocker.dart';
import 'constants.dart';
import 'services/app_settings_service.dart';
import 'services/queue_service.dart';
import 'services/smart_downloads_service.dart';
import 'services/watch_history_service.dart';
import 'services/youtube_downloader_service.dart';
import 'ui/download_bottom_sheet.dart';
import 'ui/downloads_screen.dart';
import 'ui/loading_skeleton.dart';
import 'ui/settings_screen.dart';

/// A full-screen, native-feeling YouTube WebView shell with:
/// - True OLED pitch-black theme (`#000000`).
/// - Auto-hiding frosted glass floating control pill (Home, Refresh, Back/Forward,
///   Desktop/Mobile manual toggle, live Ad-Block shield counter).
/// - Instant video ad blocking & web clutter removal ("Open in App" & "Premium" promos).
/// - Native double-tap 10s video skip gestures.
/// - Fullscreen video mode with immersive system bar auto-hiding.
/// - Shimmer loading skeleton for smooth transitions.
/// - Pull-to-refresh support.
/// - Strict navigation restriction to YouTube & Google domains.
class YouTubeWebViewShell extends StatefulWidget {
  const YouTubeWebViewShell({
    super.key,
    this.breakpoint = AppConstants.desktopBreakpoint,
  });

  /// The width breakpoint above which desktop YouTube is served by default.
  final double breakpoint;

  @override
  State<YouTubeWebViewShell> createState() => _YouTubeWebViewShellState();
}

class _YouTubeWebViewShellState extends State<YouTubeWebViewShell> {
  static const MethodChannel _platformPlaybackChannel = MethodChannel(
    'infinitytube/platform_playback',
  );

  late final WebViewController _controller;

  bool? _isDesktopMode;
  bool _isControllerInitialized = false;

  int _loadingProgress = 0;
  bool _isLoading = true;
  bool _hasError = false;
  WebResourceError? _lastError;

  bool _showSignInNotice = false;
  bool _isFullscreen = false;
  bool _isInNativePiP = false;
  bool _isVideoPlaying = false;
  int _videoWidth = 16;
  int _videoHeight = 9;

  String? _activeVideoId;
  bool _isActiveShort = false;
  int _currentNavIndex = 0;

  Widget? _customFullscreenWidget;

  void _log(String message) {
    if (kDebugMode && AppSettingsService.instance.diagnosticLoggingEnabled) {
      debugPrint(message);
    }
  }

  @override
  void initState() {
    super.initState();
    WatchHistoryService.instance.addListener(_onServiceUpdate);
    QueueService.instance.addListener(_onServiceUpdate);
    SmartDownloadsService.instance.addListener(_onServiceUpdate);
    AppSettingsService.instance.addListener(_onSettingsUpdate);
    _platformPlaybackChannel.setMethodCallHandler(_handlePlatformPlaybackCall);
    _initializeWebViewController();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  void _onSettingsUpdate() {
    if (mounted) setState(() {});
    _syncNativePiPState();
  }

  @override
  void dispose() {
    WatchHistoryService.instance.removeListener(_onServiceUpdate);
    QueueService.instance.removeListener(_onServiceUpdate);
    SmartDownloadsService.instance.removeListener(_onServiceUpdate);
    AppSettingsService.instance.removeListener(_onSettingsUpdate);
    _platformPlaybackChannel.setMethodCallHandler(null);
    // Restore default system UI mode and all orientations
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  void _initializeWebViewController() {
    // 1. Initialize controller with default camera & microphone denial
    final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
      );
    } else if (WebViewPlatform.instance is AndroidWebViewController) {
      params = AndroidWebViewControllerCreationParams();
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _controller = WebViewController.fromPlatformCreationParams(
      params,
      onPermissionRequest: (WebViewPermissionRequest request) {
        _log('[Security] Denied permission request for: ${request.types}');
        request.deny();
      },
    );

    // 2. JavaScript & OLED Black Background
    _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    _controller.setBackgroundColor(Colors.black);

    // 3. JavaScript Channels for AdBlock & Fullscreen Communication
    _controller.addJavaScriptChannel(
      'AdBlockChannel',
      onMessageReceived: (JavaScriptMessage message) {
        _log('[AdBlock] Blocked advertisement.');
      },
    );

    _controller.addJavaScriptChannel(
      'FullscreenChannel',
      onMessageReceived: (JavaScriptMessage message) {
        final isEntering = message.message == 'fullscreen_enter';
        _handleFullscreenChange(isEntering);
      },
    );

    _controller.addJavaScriptChannel(
      'DownloadsChannel',
      onMessageReceived: (JavaScriptMessage message) {
        if (message.message == 'open_downloads') {
          _openDownloadsScreen();
        } else if (message.message == 'open_settings') {
          _openSettingsScreen();
        } else if (message.message == 'download_active_video') {
          _handleDownloadPressed();
        } else if (message.message == 'open_queue') {
          _showQueueSheet();
        } else if (message.message == 'open_premium') {
          _showPremiumFeaturesSheet();
        } else if (message.message == 'pip') {
          _handlePiP();
        } else if (message.message == 'jump_ahead') {
          _handleJumpAhead();
        }
      },
    );

    _controller.addJavaScriptChannel(
      'PlayerStateChannel',
      onMessageReceived: (JavaScriptMessage message) {
        _handlePlayerStateMessage(message.message);
      },
    );

    // 4. Platform specific customizations (DOM storage, inline media playback, custom view)
    if (_controller.platform is AndroidWebViewController) {
      final androidController =
          _controller.platform as AndroidWebViewController;
      androidController.setMediaPlaybackRequiresUserGesture(false);
      androidController.setCustomWidgetCallbacks(
        onShowCustomWidget:
            (Widget customWidget, void Function() onCustomWidgetHidden) {
              setState(() {
                _customFullscreenWidget = customWidget;
              });
              _handleFullscreenChange(true);
            },
        onHideCustomWidget: () {
          setState(() {
            _customFullscreenWidget = null;
          });
          _handleFullscreenChange(false);
        },
      );
    }

    // 6. Set NavigationDelegate for loading, errors, ad blocking, and domain restrictions
    _controller.setNavigationDelegate(
      NavigationDelegate(
        onProgress: (int progress) {
          if (!mounted) return;
          setState(() {
            _loadingProgress = progress;
            if (progress >= 100) {
              _isLoading = false;
            }
          });
          if (progress >= 20) {
            _injectAdBlocker();
          }
        },
        onPageStarted: (String url) {
          if (!mounted) return;
          setState(() {
            _isLoading = true;
            _hasError = false;
            _lastError = null;
          });
          _injectAdBlocker();
          _checkSignInUrl(url);
          _updateActiveVideoState(url);
        },
        onPageFinished: (String url) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
          });
          _injectAdBlocker();
          _checkSignInUrl(url);
          _updateActiveVideoState(url);
        },
        onWebResourceError: (WebResourceError error) {
          _log(
            '[WebView Error] Code: ${error.errorCode}, Type: ${error.errorType}, Desc: ${error.description}, URL: ${error.url}, isMainFrame: ${error.isForMainFrame}',
          );
          if (error.isForMainFrame ?? true) {
            if (!mounted) return;
            setState(() {
              _hasError = true;
              _lastError = error;
              _isLoading = false;
            });
          }
        },
        onNavigationRequest: (NavigationRequest request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null) {
            return NavigationDecision.prevent;
          }

          if (uri.scheme == 'about') {
            return NavigationDecision.navigate;
          }

          if (isHostAllowed(uri.host)) {
            _checkSignInUrl(request.url);
            _updateActiveVideoState(request.url);
            return NavigationDecision.navigate;
          }

          _log(
            '[Security] Blocked top-level navigation to unapproved host: ${uri.host}',
          );
          _showExternalLinkBlockedNotice(request.url);
          return NavigationDecision.prevent;
        },
        onUrlChange: (UrlChange change) {
          if (change.url != null) {
            _checkSignInUrl(change.url!);
            _injectAdBlocker();
            _updateActiveVideoState(change.url!);
          }
        },
      ),
    );
  }

  void _updateActiveVideoState(String? url) {
    final videoId = YouTubeDownloaderService.extractVideoId(url);
    final isShort = YouTubeDownloaderService.isShortsUrl(url);
    if (videoId != _activeVideoId || isShort != _isActiveShort) {
      if (mounted) {
        setState(() {
          _activeVideoId = videoId;
          _isActiveShort = isShort;
        });
      }
    }
    _syncNavIndexFromUrl(url);
  }

  void _syncNavIndexFromUrl(String? url) {
    if (url == null || !mounted) return;
    int? newIndex;
    if (YouTubeDownloaderService.isShortsUrl(url)) {
      newIndex = 1;
    } else if (url.endsWith('youtube.com/') ||
        url.endsWith('youtube.com') ||
        url.contains('/?app=')) {
      newIndex = 0;
    }
    if (newIndex != null && newIndex != _currentNavIndex) {
      setState(() {
        _currentNavIndex = newIndex!;
      });
    }
  }

  Future<void> _handleDownloadPressed() async {
    String? currentUrl = await _controller.currentUrl();
    try {
      final jsUrl = await _controller.runJavaScriptReturningResult(
        'window.location.href',
      );
      final jsUrlStr = jsUrl.toString().replaceAll('"', '').trim();
      if (jsUrlStr.isNotEmpty && jsUrlStr.startsWith('http')) {
        currentUrl = jsUrlStr;
      }
    } catch (_) {}

    final videoId =
        YouTubeDownloaderService.extractVideoId(currentUrl) ?? _activeVideoId;
    final isShort =
        YouTubeDownloaderService.isShortsUrl(currentUrl) || _isActiveShort;

    if (videoId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please open any video or YouTube Short to download.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF282828),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (!mounted) return;
    DownloadBottomSheet.show(context, videoId: videoId, isShort: isShort);
  }

  void _handleFullscreenChange(bool isEntering) {
    if (!mounted) return;
    setState(() {
      _isFullscreen = isEntering;
    });
    if (isEntering) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
  }

  Future<void> _injectAdBlocker() async {
    try {
      final configuration = jsonEncode(
        AppSettingsService.instance.toWebConfiguration(),
      );
      await _controller.runJavaScript(
        'window.__infinitySettings__ = $configuration;',
      );
      await _controller.runJavaScript(AdBlocker.injectionScript);
    } catch (_) {
      // Ignored if webview engine is not yet ready
    }
  }

  void _checkSignInUrl(String url) {
    final uri = Uri.tryParse(url);
    final isSignIn =
        uri != null &&
        (uri.host.contains('accounts.google.com') ||
            uri.path.contains('signin') ||
            uri.path.contains('ServiceLogin'));

    if (isSignIn != _showSignInNotice) {
      if (mounted) {
        setState(() {
          _showSignInNotice = isSignIn;
        });
      }
    }
  }

  void _handleResponsiveLayout(double availableWidth) {
    final preference = AppSettingsService.instance.preferredExperience;
    final bool shouldBeDesktop = switch (preference) {
      PreferredExperience.desktop => true,
      PreferredExperience.mobile => false,
      PreferredExperience.automatic => availableWidth >= widget.breakpoint,
    };

    if (!_isControllerInitialized) {
      _isControllerInitialized = true;
      _isDesktopMode = shouldBeDesktop;
      _loadInitialExperience(shouldBeDesktop);
    } else if (_isDesktopMode != shouldBeDesktop) {
      _isDesktopMode = shouldBeDesktop;
      _switchExperience(shouldBeDesktop);
    }
  }

  Future<void> _loadInitialExperience(bool isDesktop) async {
    final userAgent = isDesktop
        ? AppConstants.desktopUserAgent
        : AppConstants.mobileUserAgent;
    final initialUrl = isDesktop
        ? AppConstants.desktopUrl
        : AppConstants.mobileUrl;

    await _controller.setUserAgent(userAgent);
    await _controller.loadRequest(Uri.parse(initialUrl));
  }

  Future<void> _switchExperience(bool isDesktop) async {
    final userAgent = isDesktop
        ? AppConstants.desktopUserAgent
        : AppConstants.mobileUserAgent;
    await _controller.setUserAgent(userAgent);

    final currentUrlStr = await _controller.currentUrl();
    Uri targetUri;
    if (currentUrlStr != null && currentUrlStr.isNotEmpty) {
      final currentUri = Uri.tryParse(currentUrlStr);
      if (currentUri != null) {
        targetUri = switchYouTubeExperienceUri(
          currentUri,
          toDesktop: isDesktop,
        );
      } else {
        targetUri = Uri.parse(
          isDesktop ? AppConstants.desktopUrl : AppConstants.mobileUrl,
        );
      }
    } else {
      targetUri = Uri.parse(
        isDesktop ? AppConstants.desktopUrl : AppConstants.mobileUrl,
      );
    }

    await _controller.loadRequest(targetUri);
  }

  Future<void> _retry() async {
    setState(() {
      _hasError = false;
      _isLoading = true;
    });
    final currentUrl = await _controller.currentUrl();
    if (currentUrl != null && currentUrl.isNotEmpty) {
      await _controller.reload();
    } else {
      final url = (_isDesktopMode ?? false)
          ? AppConstants.desktopUrl
          : AppConstants.mobileUrl;
      await _controller.loadRequest(Uri.parse(url));
    }
  }

  Future<void> _navigateToHome() async {
    final homeUrl = (_isDesktopMode ?? false)
        ? AppConstants.desktopUrl
        : AppConstants.mobileUrl;
    await _controller.loadRequest(Uri.parse(homeUrl));
  }

  Future<void> _returnToYouTubeFeed() async {
    final canGoBack = await _controller.canGoBack();
    if (canGoBack) {
      await _controller.goBack();
    } else {
      await _navigateToHome();
    }
    if (mounted) {
      setState(() {
        _showSignInNotice = false;
      });
    }
  }

  void _showExternalLinkBlockedNotice(String blockedUrl) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'External link blocked. Only YouTube and Google hosts are allowed.',
          style: TextStyle(fontSize: 13),
        ),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF282828),
      ),
    );
  }

  void _handlePlayerStateMessage(String rawJson) {
    try {
      final data = jsonDecode(rawJson) as Map<String, dynamic>;
      final type = data['type'] as String?;
      if (type == 'playback') {
        _isVideoPlaying = data['playing'] as bool? ?? false;
        _videoWidth = (data['width'] as num?)?.toInt() ?? 16;
        _videoHeight = (data['height'] as num?)?.toInt() ?? 9;
        _syncNativePiPState();
      } else if (type == 'progress') {
        final url = data['url'] as String?;
        final videoId =
            YouTubeDownloaderService.extractVideoId(url) ?? _activeVideoId;
        final title = data['title'] as String? ?? '';
        final position = data['position'] as int? ?? 0;
        final duration = data['duration'] as int? ?? 0;
        if (videoId != null && duration > 0) {
          if (AppSettingsService.instance.continueWatchingEnabled) {
            WatchHistoryService.instance.saveProgress(
              videoId: videoId,
              title: title,
              positionSeconds: position,
              durationSeconds: duration,
            );
          }
          SmartDownloadsService.instance.processSmartDownloadForVideo(videoId);
        }
      } else if (type == 'ended') {
        final next = QueueService.instance.popNext();
        if (next != null) {
          _controller.loadRequest(Uri.parse(next.url));
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Playing next from queue: ${next.title}'),
                behavior: SnackBarBehavior.floating,
                backgroundColor: const Color(0xFF282828),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _handlePiP() async {
    if (!AppSettingsService.instance.pictureInPictureEnabled) {
      _showPiPUnavailableMessage();
      return;
    }
    var webPiPSupported = false;
    var webPiPEntered = false;
    try {
      final result = await _controller.runJavaScriptReturningResult(
        "(document.pictureInPictureEnabled === true && !!document.querySelector('video')?.requestPictureInPicture) ? 'supported' : 'unsupported'",
      );
      webPiPSupported =
          result.toString().contains('supported') &&
          !result.toString().contains('unsupported');
      if (webPiPSupported) {
        final toggled = await _controller.runJavaScriptReturningResult(
          '(async function(){ return window.__togglePiP__ ? await window.__togglePiP__() : false; })()',
        );
        webPiPEntered = toggled.toString().toLowerCase().contains('true');
      }
    } catch (_) {}

    // Chromium WebView commonly omits the page-level Picture-in-Picture API.
    // Fall back to Android's native activity PiP so the playing WebView itself
    // remains visible above other applications.
    if (Platform.isAndroid && !webPiPEntered) {
      try {
        final entered = await _platformPlaybackChannel.invokeMethod<bool>(
          'enterPiP',
          {'width': _videoWidth, 'height': _videoHeight},
        );
        if (entered != true && mounted) {
          _showPiPUnavailableMessage();
        }
      } on PlatformException {
        if (mounted) _showPiPUnavailableMessage();
      }
    } else if (!webPiPEntered && mounted) {
      _showPiPUnavailableMessage();
    }
  }

  Future<void> _syncNativePiPState() async {
    if (!Platform.isAndroid) return;
    final settings = AppSettingsService.instance;
    try {
      await _platformPlaybackChannel.invokeMethod<void>('updatePiPState', {
        'enabled': settings.pictureInPictureEnabled,
        'autoEnter': settings.autoEnterPictureInPicture,
        'playing': _isVideoPlaying,
        'width': _videoWidth,
        'height': _videoHeight,
      });
    } on PlatformException {
      // Older platform builds may not expose the enhanced PiP bridge yet.
    }
  }

  Future<dynamic> _handlePlatformPlaybackCall(MethodCall call) async {
    if (call.method != 'pipStateChanged') return;
    final isInPiP = call.arguments == true;
    if (mounted) setState(() => _isInNativePiP = isInPiP);
    try {
      await _controller.runJavaScript(
        'if (window.__setNativePiPMode__) window.__setNativePiPMode__(${isInPiP ? 'true' : 'false'});',
      );
    } catch (_) {}
  }

  void _showPiPUnavailableMessage() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Picture-in-Picture is unavailable on this device.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF282828),
      ),
    );
  }

  Future<void> _handleJumpAhead() async {
    try {
      await _controller.runJavaScript(
        'if (window.__jumpAhead__) window.__jumpAhead__();',
      );
    } catch (_) {}
  }

  Future<void> _handleMusicToggle() async {
    final currentUrl = await _controller.currentUrl() ?? '';
    if (currentUrl.contains('music.youtube.com')) {
      final target = (_isDesktopMode ?? false)
          ? AppConstants.desktopUrl
          : AppConstants.mobileUrl;
      await _controller.loadRequest(Uri.parse(target));
    } else {
      await _controller.loadRequest(Uri.parse(AppConstants.musicUrl));
    }
  }

  Future<void> _handleKidsToggle() async {
    final currentUrl = await _controller.currentUrl() ?? '';
    if (currentUrl.contains('youtubekids.com')) {
      final target = (_isDesktopMode ?? false)
          ? AppConstants.desktopUrl
          : AppConstants.mobileUrl;
      await _controller.loadRequest(Uri.parse(target));
    } else {
      await _controller.loadRequest(Uri.parse(AppConstants.kidsUrl));
    }
  }

  Future<void> _handleAddToQueue() async {
    final url = await _controller.currentUrl() ?? '';
    final videoId =
        YouTubeDownloaderService.extractVideoId(url) ?? _activeVideoId;
    if (videoId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Open a video first to add it to the queue.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF282828),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    String title = 'Video ($videoId)';
    try {
      final res = await _controller.runJavaScriptReturningResult(
        "(document.querySelector('h1.title, .slim-video-metadata-title, ytm-slim-video-metadata-section-renderer .title') || {}).textContent || ''",
      );
      final clean = res.toString().replaceAll('"', '').trim();
      if (clean.isNotEmpty) title = clean;
    } catch (_) {}

    QueueService.instance.addToQueue(
      QueuedVideo(
        videoId: videoId,
        title: title,
        url: url.isNotEmpty ? url : 'https://m.youtube.com/watch?v=$videoId',
      ),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added to Queue: $title'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF282828),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showQueueSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final queue = QueueService.instance.queue;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF0000)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.queue_music_rounded,
                            color: Color(0xFFFF0000),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Watch Queue (${queue.length})',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (queue.isNotEmpty)
                          TextButton(
                            onPressed: () {
                              QueueService.instance.clear();
                              setModalState(() {});
                              setState(() {});
                            },
                            child: const Text(
                              'Clear All',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_activeVideoId != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: OutlinedButton.icon(
                          onPressed: () {
                            _handleAddToQueue();
                            setModalState(() {});
                          },
                          icon: const Icon(
                            Icons.playlist_add_rounded,
                            size: 20,
                          ),
                          label: const Text('Add Current Video to Queue'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF3EA6FF),
                            side: const BorderSide(
                              color: Color(0xFF3EA6FF),
                              width: 1,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            minimumSize: const Size.fromHeight(42),
                          ),
                        ),
                      ),
                    if (queue.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'Queue is empty.\nAdd videos to watch them back-to-back without interruption.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: queue.length,
                          separatorBuilder: (context, index) =>
                              const Divider(color: Colors.white12, height: 1),
                          itemBuilder: (context, index) {
                            final item = queue[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Colors.white10,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                              title: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                'Up next #${index + 1}',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: Colors.white54,
                                  size: 20,
                                ),
                                onPressed: () {
                                  QueueService.instance.removeAt(index);
                                  setModalState(() {});
                                  setState(() {});
                                },
                              ),
                              onTap: () {
                                final selected = QueueService.instance.takeAt(
                                  index,
                                );
                                Navigator.of(context).pop();
                                if (selected != null) {
                                  _controller.loadRequest(
                                    Uri.parse(selected.url),
                                  );
                                }
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showPremiumFeaturesSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF0000)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.stars_rounded,
                          color: Color(0xFFFF0000),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'YouTube Premium Benefits',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'All core & extra features enabled',
                            style: TextStyle(
                              color: Color(0xFF00E676),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _buildFeatureTile(
                    icon: Icons.block_flipped,
                    iconColor: const Color(0xFF00E676),
                    title: 'Ad-Free Viewing',
                    subtitle:
                        'Commercial-free across YouTube, YouTube Kids & Music.',
                    statusBadge: 'Active',
                  ),
                  _buildFeatureTile(
                    icon: Icons.headphones_rounded,
                    iconColor: const Color(0xFF3EA6FF),
                    title: 'Background Play',
                    subtitle: 'Videos keep playing when you switch apps or lock your screen.',
                    statusBadge: 'Best effort',
                  ),
                  _buildFeatureTile(
                    icon: Icons.music_note_rounded,
                    iconColor: const Color(0xFFFF0000),
                    title: 'YouTube Music Premium',
                    subtitle:
                        'Stream 100M+ songs with 256kbps high-quality audio.',
                    actionLabel: 'Open Music',
                    onAction: () {
                      Navigator.of(context).pop();
                      _handleMusicToggle();
                    },
                  ),
                  _buildFeatureTile(
                    icon: Icons.child_care_rounded,
                    iconColor: Colors.amber,
                    title: 'YouTube Kids',
                    subtitle:
                        'Safe, curated, ad-free environment for children.',
                    actionLabel: 'Open Kids',
                    onAction: () {
                      Navigator.of(context).pop();
                      _handleKidsToggle();
                    },
                  ),
                  _buildFeatureTile(
                    icon: Icons.download_done_rounded,
                    iconColor: const Color(0xFF00E676),
                    title: 'Offline & Smart Downloads',
                    subtitle: 'Save videos & auto-cache recommendations for offline use.',
                    actionLabel: 'Downloads',
                    onAction: () {
                      Navigator.of(context).pop();
                      _openDownloadsScreen();
                    },
                  ),
                  _buildFeatureTile(
                    icon: Icons.picture_in_picture_alt_rounded,
                    iconColor: const Color(0xFF3EA6FF),
                    title: 'Picture-in-Picture & Jump Ahead',
                    subtitle: 'Pop out videos to float over apps and skip +30s to key moments.',
                    statusBadge: 'Ready',
                  ),
                  _buildFeatureTile(
                    icon: Icons.high_quality_rounded,
                    iconColor: const Color(0xFFFF5252),
                    title: 'Enhanced 1080p',
                    subtitle: 'Requests the best available 1080p profile from the player.',
                    statusBadge: 'Requested',
                  ),
                  _buildFeatureTile(
                    icon: Icons.queue_music_rounded,
                    iconColor: Colors.purpleAccent,
                    title: 'Queue & Continue Watching',
                    subtitle: 'Set up uninterrupted video queues and resume right where you left off.',
                    actionLabel: 'View Queue',
                    onAction: () {
                      Navigator.of(context).pop();
                      _showQueueSheet();
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFeatureTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    String? statusBadge,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          if (statusBadge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF00E676).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                statusBadge,
                style: const TextStyle(
                  color: Color(0xFF00E676),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF3EA6FF),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                actionLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContinueWatchingBanner() {
    if (!AppSettingsService.instance.continueWatchingEnabled) {
      return const SizedBox.shrink();
    }
    final lastCheckpoint = WatchHistoryService.instance.lastWatched;
    if (lastCheckpoint == null ||
        _activeVideoId != null ||
        _currentNavIndex != 0) {
      return const SizedBox.shrink();
    }

    return Positioned(
      bottom: 12,
      left: 14,
      right: 14,
      child: Material(
        color: Colors.transparent,
        elevation: 10,
        shadowColor: Colors.black87,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFFFF0000).withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFFFF0000),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'CONTINUE WATCHING',
                          style: TextStyle(
                            color: Color(0xFFFF4D4D),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '• ${lastCheckpoint.positionFormatted}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lastCheckpoint.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  final isDesktop = _isDesktopMode ?? false;
                  final base = isDesktop
                      ? 'https://www.youtube.com'
                      : 'https://m.youtube.com';
                  final url =
                      '$base/watch?v=${lastCheckpoint.videoId}&t=${lastCheckpoint.positionSeconds}s';
                  _controller.loadRequest(Uri.parse(url));
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF0000),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: const Text(
                  'Resume',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white54,
                  size: 18,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  WatchHistoryService.instance.dismissCheckpoint(
                    lastCheckpoint.videoId,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // If native Android custom view is showing (fullscreen video)
    if (_customFullscreenWidget != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: _customFullscreenWidget!,
      );
    }

    if (_isInNativePiP) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: _buildWebViewWidget(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _handleResponsiveLayout(constraints.maxWidth);

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (bool didPop, Object? result) async {
            if (didPop) return;

            final canGoBack = await _controller.canGoBack();
            if (canGoBack) {
              await _controller.goBack();
            } else {
              await SystemNavigator.pop();
            }
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            body: SafeArea(
              top: !_isFullscreen,
              bottom: false,
              child: Stack(
                children: [
                  // 1. Full-screen WebView with uninhibited native touch & scroll gestures
                  _buildWebViewWidget(),

                  // 2. Shimmer loading skeleton (smooth fade-out, non-blocking)
                  AnimatedOpacity(
                    opacity: (_isLoading && _loadingProgress < 60) ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: const IgnorePointer(
                      ignoring: true,
                      child: YouTubeLoadingSkeleton(),
                    ),
                  ),

                  // 3. Slim progress indicator at top
                  if (_isLoading)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: SizedBox(
                        height: 2.5,
                        child: LinearProgressIndicator(
                          value: _loadingProgress > 0
                              ? _loadingProgress / 100
                              : null,
                          backgroundColor: Colors.transparent,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFFFF0000),
                          ),
                        ),
                      ),
                    ),

                  // 4. Floating OAuth sign-in advisory banner
                  if (_showSignInNotice)
                    Positioned(
                      bottom: 24,
                      left: 16,
                      right: 16,
                      child: Material(
                        elevation: 8,
                        borderRadius: BorderRadius.circular(12),
                        color: const Color(0xFF212121),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info_outline,
                                color: Colors.amber,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Google may restrict sign-in in embedded views. You can browse YouTube freely as a guest.',
                                  style: TextStyle(
                                    color: Colors.grey.shade200,
                                    fontSize: 13,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: _returnToYouTubeFeed,
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF3EA6FF),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                ),
                                child: const Text('Back to Feed'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // 6. Full error overlay
                  if (_hasError)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.wifi_off_rounded,
                                  size: 56,
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(height: 24),
                              const Text(
                                'You\'re offline or connection failed',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _lastError?.description.isNotEmpty == true
                                    ? _lastError!.description
                                    : 'Check your internet connection and try again.',
                                style: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 28),
                              FilledButton.icon(
                                onPressed: _retry,
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  size: 18,
                                ),
                                label: const Text('Retry'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF3EA6FF),
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // 7. Continue watching checkpoint banner
                  _buildContinueWatchingBanner(),
                ],
              ),
            ),
            bottomNavigationBar: _isFullscreen
                ? null
                : _buildNativeBottomNavBar(),
          ),
        );
      },
    );
  }

  /// Builds the WebViewWidget with Hybrid Composition and uninhibited drag gestures
  Widget _buildWebViewWidget() {
    final gestureRecognizers = <Factory<OneSequenceGestureRecognizer>>{
      Factory<VerticalDragGestureRecognizer>(
        () => VerticalDragGestureRecognizer(),
      ),
      Factory<HorizontalDragGestureRecognizer>(
        () => HorizontalDragGestureRecognizer(),
      ),
    };

    if (WebViewPlatform.instance is AndroidWebViewPlatform) {
      return WebViewWidget.fromPlatformCreationParams(
        params: AndroidWebViewWidgetCreationParams(
          controller: _controller.platform,
          displayWithHybridComposition: true,
          gestureRecognizers: gestureRecognizers,
        ),
      );
    }

    return WebViewWidget.fromPlatformCreationParams(
      params: PlatformWebViewWidgetCreationParams(
        controller: _controller.platform,
        gestureRecognizers: gestureRecognizers,
      ),
    );
  }

  /// Opens the native offline downloads management screen
  void _openDownloadsScreen() {
    if (!mounted) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => const DownloadsScreen()));
  }

  Future<void> _openSettingsScreen() async {
    if (!mounted) return;
    setState(() => _currentNavIndex = 2);
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => const SettingsScreen()));
    if (!mounted) return;
    setState(() {
      _currentNavIndex = 0;
      _isControllerInitialized = false;
    });
    await _controller.reload();
  }

  /// Native 4-tab bottom navigation bar: [Home] [Shorts] [Settings] [Download]
  Widget _buildNativeBottomNavBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F0F),
        border: Border(top: BorderSide(color: Color(0x22FFFFFF), width: 0.8)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: Theme(
            data: Theme.of(context).copyWith(
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
            ),
            child: BottomNavigationBar(
              currentIndex: _currentNavIndex,
              onTap: _onBottomNavTapped,
              type: BottomNavigationBarType.fixed,
              backgroundColor: const Color(0xFF0F0F0F),
              selectedItemColor: Colors.white,
              unselectedItemColor: const Color(0xFFAAAAAA),
              selectedFontSize: 10,
              unselectedFontSize: 10,
              selectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.normal,
                height: 1.3,
              ),
              elevation: 0,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined, size: 24),
                  activeIcon: Icon(Icons.home_filled, size: 24),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.play_circle_outline_rounded, size: 24),
                  activeIcon: Icon(Icons.play_circle_fill_rounded, size: 24),
                  label: 'Shorts',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.settings_outlined, size: 24),
                  activeIcon: Icon(Icons.settings_rounded, size: 24),
                  label: 'Settings',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.download_rounded, size: 24),
                  activeIcon: Icon(Icons.download_done_rounded, size: 24),
                  label: 'Download',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onBottomNavTapped(int index) {
    if (index == 2) {
      _openSettingsScreen();
      return;
    }
    if (index == 3) {
      _openDownloadsScreen();
      return;
    }

    setState(() {
      _currentNavIndex = index;
    });

    String targetUrl;
    final bool isDesktop = _isDesktopMode == true;
    switch (index) {
      case 0:
        targetUrl = isDesktop
            ? 'https://www.youtube.com/'
            : 'https://m.youtube.com/';
        break;
      case 1:
        targetUrl = isDesktop
            ? 'https://www.youtube.com/shorts'
            : 'https://m.youtube.com/shorts';
        break;
      default:
        targetUrl = isDesktop
            ? 'https://www.youtube.com/'
            : 'https://m.youtube.com/';
    }

    _controller.loadRequest(Uri.parse(targetUrl));
  }
}
