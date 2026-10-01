import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:youtube_app/main.dart';
import 'package:youtube_app/services/download_manager.dart';
import 'package:youtube_app/services/youtube_downloader_service.dart';
import 'package:youtube_app/ui/download_bottom_sheet.dart';
import 'package:youtube_app/ui/downloads_screen.dart';
import 'package:youtube_app/ui/floating_control_pill.dart';
import 'package:youtube_app/ui/loading_skeleton.dart';
import 'package:youtube_app/ui/settings_screen.dart';
import 'package:youtube_app/ui/splash_screen.dart';
import 'package:youtube_app/ui/web_platform_notice.dart';
import 'package:youtube_app/youtube_webview_shell.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class FakeWebViewController extends PlatformWebViewController {
  FakeWebViewController(super.params) : super.implementation();

  String? userAgent;
  String? _currentUrl;
  final bool _canGoBack = false;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate delegate,
  ) async {}

  @override
  Future<void> setUserAgent(String? userAgent) async {
    this.userAgent = userAgent;
  }

  @override
  Future<void> setOnPlatformPermissionRequest(
    void Function(PlatformWebViewPermissionRequest request)
    onPlatformPermissionRequest,
  ) async {}

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    _currentUrl = params.uri.toString();
  }

  @override
  Future<String?> currentUrl() async => _currentUrl;

  @override
  Future<bool> canGoBack() async => _canGoBack;

  @override
  Future<void> goBack() async {}

  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {}

  @override
  Future<bool> canGoForward() async => false;

  @override
  Future<void> goForward() async {}

  @override
  Future<void> setOnScrollPositionChange(
    void Function(ScrollPositionChange change)? onScrollPositionChange,
  ) async {}

  @override
  Future<void> reload() async {}

  @override
  Future<void> runJavaScript(String javaScript) async {}
}

class FakePlatformNavigationDelegate extends PlatformNavigationDelegate {
  FakePlatformNavigationDelegate(super.params) : super.implementation();

  @override
  Future<void> setOnProgress(void Function(int progress) onProgress) async {}

  @override
  Future<void> setOnPageStarted(
    void Function(String url) onPageStarted,
  ) async {}

  @override
  Future<void> setOnPageFinished(
    void Function(String url) onPageFinished,
  ) async {}

  @override
  Future<void> setOnWebResourceError(
    void Function(WebResourceError error) onWebResourceError,
  ) async {}

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {}

  @override
  Future<void> setOnUrlChange(
    void Function(UrlChange change) onUrlChange,
  ) async {}
}

class FakeWebViewWidget extends PlatformWebViewWidget {
  FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(key: Key('FakeWebViewPlatformWidget'));
  }
}

class FakeWebViewPlatform extends WebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    return FakeWebViewController(params);
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return FakePlatformNavigationDelegate(params);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return FakeWebViewWidget(params);
  }
}

void main() {
  setUpAll(() {
    WebViewPlatform.instance = FakeWebViewPlatform();
  });

  testWidgets(
    'YouTubeApp shows SplashScreen then transitions to YouTubeWebViewShell',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const YouTubeApp());
      await tester.pump();

      // Initially shows SplashScreen
      expect(find.byType(SplashScreen), findsOneWidget);

      // Fast-forward past splash timer (1800ms) + fade transition (500ms)
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byType(YouTubeWebViewShell), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is PopScope), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Shorts'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
      expect(find.byIcon(Icons.download_rounded), findsOneWidget);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text('Playback'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Smart Downloads'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Smart Downloads'), findsOneWidget);
      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Tapping Download tab opens DownloadsScreen
      await tester.tap(find.text('Download'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(DownloadsScreen), findsOneWidget);
    },
  );

  testWidgets('Renders properly on tablet/desktop sized screens', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const YouTubeApp());
    await tester.pump();

    // Fast-forward past splash timer
    await tester.pump(const Duration(milliseconds: 2000));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(YouTubeWebViewShell), findsOneWidget);
  });

  testWidgets('SplashScreen renders badge and brand text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
    await tester.pump();

    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('InfinityTube'), findsOneWidget);
    expect(find.text('PREMIUM'), findsOneWidget);

    // Pump to clean up timer
    await tester.pump(const Duration(milliseconds: 2000));
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets(
    'FloatingControlPill renders all controls and reacts to interaction',
    (WidgetTester tester) async {
      bool homeClicked = false;
      bool refreshClicked = false;
      bool toggleClicked = false;
      bool downloadClicked = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FloatingControlPill(
              isDesktopMode: false,
              adsBlockedCount: 5,
              canGoBack: true,
              canGoForward: true,
              hasActiveVideo: true,
              onHomePressed: () => homeClicked = true,
              onRefreshPressed: () => refreshClicked = true,
              onBackPressed: () {},
              onForwardPressed: () {},
              onToggleModePressed: () => toggleClicked = true,
              onShieldPressed: () {},
              onDownloadPressed: () => downloadClicked = true,
            ),
          ),
        ),
      );

      // Verify icons
      expect(find.byIcon(Icons.shield_rounded), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.byIcon(Icons.home_rounded), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      expect(find.byIcon(Icons.download_rounded), findsOneWidget);
      expect(find.byIcon(Icons.smartphone_rounded), findsOneWidget);

      // Tap download
      await tester.tap(find.byIcon(Icons.download_rounded));
      expect(downloadClicked, isTrue);

      // Tap home
      await tester.tap(find.byIcon(Icons.home_rounded));
      expect(homeClicked, isTrue);

      // Tap refresh
      await tester.tap(find.byIcon(Icons.refresh_rounded));
      expect(refreshClicked, isTrue);

      // Tap toggle mode
      await tester.tap(find.byIcon(Icons.smartphone_rounded));
      expect(toggleClicked, isTrue);
    },
  );

  testWidgets('YouTubeLoadingSkeleton renders cleanly without crashing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: YouTubeLoadingSkeleton())),
    );

    expect(find.byType(YouTubeLoadingSkeleton), findsOneWidget);
  });

  testWidgets('DownloadsScreen renders cleanly and displays empty state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: DownloadsScreen(initialItems: [])),
    );
    await tester.pump();

    expect(find.byType(DownloadsScreen), findsOneWidget);
    expect(find.text('Downloads'), findsOneWidget);
    expect(find.text('No Downloads Yet'), findsOneWidget);
    expect(find.text('Browse YouTube'), findsOneWidget);
  });

  testWidgets('DownloadsScreen renders populated items with replay button', (
    WidgetTester tester,
  ) async {
    final sampleItem = DownloadedMediaItem(
      file: File('/tmp/sample_video.mp4'),
      title: 'Amazing Nature Documentary',
      quality: '1080p',
      format: 'MP4',
      sizeBytes: 1024 * 1024 * 45,
      modified: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(home: DownloadsScreen(initialItems: [sampleItem])),
    );
    await tester.pump();

    expect(find.text('Amazing Nature Documentary'), findsOneWidget);
    expect(find.text('1080p'), findsOneWidget);
    expect(find.text('45.0 MB'), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
  });

  testWidgets(
    'DownloadsScreen renders in-progress download with pause and resume controls',
    (WidgetTester tester) async {
      final task = DownloadTask(
        id: 'task_in_progress_1',
        videoId: 'vid999',
        title: 'Active In-Flight Video',
        author: 'Flutter Team',
        durationText: '10:00',
        thumbnailUrl: '',
        qualityLabel: '1080p MP4 (Video Only)',
        format: 'MP4',
        isAudioOnly: false,
        isShort: false,
        streamInfo: FakeStreamInfo(),
        targetFile: File('/tmp/active_test.mp4'),
        tempFile: File('/tmp/active_test.mp4.download'),
        totalBytes: 50 * 1024 * 1024,
        status: DownloadStatus.downloading,
        receivedBytes: 25 * 1024 * 1024,
        progress: 0.5,
        progressText: '25.0 / 50.0 MB (50%)',
      );

      // Register task in DownloadManager
      DownloadManager.instance.addTask(task);

      await tester.pumpWidget(
        const MaterialApp(home: DownloadsScreen(initialItems: [])),
      );
      await tester.pump();

      expect(find.text('Active In-Flight Video'), findsOneWidget);
      expect(find.text('1080p MP4 (Video Only)'), findsOneWidget);
      expect(find.text('25.0 / 50.0 MB (50%)'), findsOneWidget);
      expect(find.byIcon(Icons.pause_circle_filled_rounded), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      // Clean up task
      DownloadManager.instance.removeTask('task_in_progress_1');
    },
  );

  testWidgets(
    'DownloadBottomSheet displays video metadata and separate quality options without duplicate progress',
    (WidgetTester tester) async {
      final metadata = VideoDownloadMetadata(
        id: 'abc12345',
        title: 'Flutter in 100 Seconds',
        author: 'Fireship',
        durationText: '01:40',
        thumbnailUrl: 'https://i.ytimg.com/vi/abc12345/hqdefault.jpg',
        isShort: false,
        videoOptions: [
          DownloadQualityOption(
            id: 'video_1080p_mp4_1',
            label: '1080p (High-Res)',
            format: 'MP4',
            sizeText: '25.4 MB',
            totalBytes: 25400000,
            hasAudio: false,
            isAudioOnly: false,
            streamInfo: FakeStreamInfo(),
          ),
          DownloadQualityOption(
            id: 'video_720p_mp4_2',
            label: '720p (HD)',
            format: 'MP4',
            sizeText: '14.2 MB',
            totalBytes: 14200000,
            hasAudio: true,
            isAudioOnly: false,
            streamInfo: FakeStreamInfo(),
          ),
        ],
        audioOptions: [
          DownloadQualityOption(
            id: 'audio_m4a_3',
            label: 'Audio (128 kbps)',
            format: 'M4A',
            sizeText: '3.1 MB',
            totalBytes: 3100000,
            hasAudio: true,
            isAudioOnly: true,
            streamInfo: FakeStreamInfo(),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DownloadBottomSheet(
              videoId: 'abc12345',
              initialMetadata: metadata,
            ),
          ),
        ),
      );
      await tester.pump();

      // Verify header details
      expect(find.text('Flutter in 100 Seconds'), findsOneWidget);
      expect(find.text('Fireship'), findsOneWidget);
      expect(find.text('01:40'), findsOneWidget);

      // Verify video quality options
      expect(find.text('1080p (High-Res)'), findsOneWidget);
      expect(find.text('720p (HD)'), findsOneWidget);
      expect(find.text('25.4 MB'), findsOneWidget);
      expect(find.text('14.2 MB'), findsOneWidget);

      // Verify top bar download manager folder shortcut
      expect(find.byIcon(Icons.folder_open_rounded), findsOneWidget);

      // Switch to Audio tab
      await tester.tap(find.text('Audio Only (1)'));
      await tester.pump();

      expect(find.text('Audio (128 kbps)'), findsOneWidget);
      expect(find.text('3.1 MB'), findsOneWidget);
    },
  );

  testWidgets('DownloadsScreen opens the centralized Settings screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: DownloadsScreen(initialItems: [])),
    );
    await tester.pump();

    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('Playback'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Smart Downloads'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Smart Downloads'), findsOneWidget);
    expect(find.text('Smart Download limit'), findsOneWidget);
  });

  testWidgets('Smart settings fit a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      const MaterialApp(home: DownloadsScreen(initialItems: [])),
    );
    await tester.tap(find.byIcon(Icons.settings_rounded));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Smart Download limit'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Smart Download limit'), findsOneWidget);
  });

  testWidgets('Downloads expose storage, search, sort, and sharing', (
    tester,
  ) async {
    final item = DownloadedMediaItem(
      file: File('/tmp/share_sample.mp4'),
      title: 'Searchable sample',
      quality: '720p',
      format: 'MP4',
      sizeBytes: 1024,
      modified: DateTime.now(),
    );
    await tester.pumpWidget(
      MaterialApp(home: DownloadsScreen(initialItems: [item])),
    );
    await tester.pump();
    expect(find.text('Device storage'), findsOneWidget);
    expect(find.text('Search downloads'), findsOneWidget);
    expect(find.byIcon(Icons.sort_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Share File'), findsOneWidget);
  });

  testWidgets('Active quality shows pause instead of premature Replay', (
    tester,
  ) async {
    final option = DownloadQualityOption(
      id: 'active_option',
      label: '720p MP4 (Video + Audio)',
      format: 'MP4',
      sizeText: '10 MB',
      totalBytes: 10 * 1024 * 1024,
      hasAudio: true,
      isAudioOnly: false,
      streamInfo: FakeStreamInfo(),
    );
    final task = DownloadTask(
      id: 'active_video_active_option',
      videoId: 'active_video',
      title: 'Active video',
      author: 'Author',
      durationText: '1:00',
      thumbnailUrl: '',
      qualityLabel: option.label,
      format: option.format,
      isAudioOnly: false,
      isShort: false,
      streamInfo: option.streamInfo,
      targetFile: File('/tmp/not_finished.mp4'),
      tempFile: File('/tmp/not_finished.mp4.download'),
      totalBytes: option.totalBytes,
      status: DownloadStatus.downloading,
      progress: 0.4,
    );
    DownloadManager.instance.addTask(task);
    addTearDown(() => DownloadManager.instance.removeTask(task.id));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DownloadBottomSheet(
            videoId: 'active_video',
            initialMetadata: VideoDownloadMetadata(
              id: 'active_video',
              title: 'Active video',
              author: 'Author',
              durationText: '1:00',
              thumbnailUrl: '',
              isShort: false,
              videoOptions: [option],
              audioOptions: const [],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.pause_circle_filled_rounded), findsOneWidget);
    expect(find.text('Replay'), findsNothing);
  });

  testWidgets('Web fallback is usable instead of crashing', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WebPlatformNotice()));
    expect(find.text('InfinityTube for Web'), findsOneWidget);
    expect(find.text('Native mobile release required'), findsOneWidget);
  });

  testWidgets(
    'YouTubeWebViewShell renders cleanly without floating top bar and has bottom navbar',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: YouTubeWebViewShell()));
      await tester.pump();

      // Verify clean layout: BottomNavigationBar exists with Download tab
      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Shorts'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
      expect(find.byIcon(Icons.download_rounded), findsOneWidget);

      // Verify the old floating top action bar is removed for a professional look
      expect(find.text('Premium'), findsNothing);
      expect(find.byIcon(Icons.stars_rounded), findsNothing);
    },
  );
}

class FakeStreamInfo implements StreamInfo {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
