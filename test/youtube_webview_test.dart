import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_app/ad_blocker.dart';
import 'package:youtube_app/constants.dart';
import 'package:youtube_app/services/queue_service.dart';
import 'package:youtube_app/services/watch_history_service.dart';
import 'package:youtube_app/services/youtube_downloader_service.dart';

void main() {
  group('Security & Domain Allowlist Tests', () {
    test('Allows official YouTube domains and subdomains', () {
      expect(isHostAllowed('youtube.com'), isTrue);
      expect(isHostAllowed('www.youtube.com'), isTrue);
      expect(isHostAllowed('m.youtube.com'), isTrue);
      expect(isHostAllowed('music.youtube.com'), isTrue);
      expect(isHostAllowed('tv.youtube.com'), isTrue);
      expect(isHostAllowed('consent.youtube.com'), isTrue);
      expect(isHostAllowed('youtu.be'), isTrue);
      expect(isHostAllowed('yt.be'), isTrue);
    });

    test('Allows only exact Google authentication and consent hosts', () {
      expect(isHostAllowed('google.com'), isTrue);
      expect(isHostAllowed('accounts.google.com'), isTrue);
      expect(isHostAllowed('myaccount.google.com'), isTrue);
      expect(isHostAllowed('consent.google.com'), isTrue);
      expect(isHostAllowed('evil.google.com'), isFalse);
      expect(isHostAllowed('googleusercontent.com'), isFalse);
      expect(isHostAllowed('sites.google.com'), isFalse);
    });

    test('Strictly denies third-party and malicious domains', () {
      expect(isHostAllowed('facebook.com'), isFalse);
      expect(isHostAllowed('malicious-site.com'), isFalse);
      expect(isHostAllowed('notyoutube.com'), isFalse);
      expect(isHostAllowed('youtube.com.phishing.org'), isFalse);
      expect(isHostAllowed('fakegoogle.com'), isFalse);
      expect(isHostAllowed(''), isFalse);
      expect(isHostAllowed(null), isFalse);
    });
  });

  group('URL Experience Switching Tests', () {
    test(
      'Switches mobile YouTube URL to desktop while preserving path and query',
      () {
        final mobileUri = Uri.parse(
          'https://m.youtube.com/watch?v=dQw4w9WgXcQ&t=42s',
        );
        final desktopUri = switchYouTubeExperienceUri(
          mobileUri,
          toDesktop: true,
        );

        expect(desktopUri.scheme, equals('https'));
        expect(desktopUri.host, equals('www.youtube.com'));
        expect(desktopUri.path, equals('/watch'));
        expect(desktopUri.queryParameters['v'], equals('dQw4w9WgXcQ'));
        expect(desktopUri.queryParameters['t'], equals('42s'));
      },
    );

    test(
      'Switches desktop YouTube URL to mobile while preserving path and query',
      () {
        final desktopUri = Uri.parse(
          'https://www.youtube.com/results?search_query=flutter+tutorial',
        );
        final mobileUri = switchYouTubeExperienceUri(
          desktopUri,
          toDesktop: false,
        );

        expect(mobileUri.scheme, equals('https'));
        expect(mobileUri.host, equals('m.youtube.com'));
        expect(mobileUri.path, equals('/results'));
        expect(
          mobileUri.queryParameters['search_query'],
          equals('flutter tutorial'),
        );
      },
    );

    test('Fallback to base URLs if current URI is non-standard', () {
      final externalUri = Uri.parse('https://example.com/some/path');
      final desktopFallback = switchYouTubeExperienceUri(
        externalUri,
        toDesktop: true,
      );
      final mobileFallback = switchYouTubeExperienceUri(
        externalUri,
        toDesktop: false,
      );

      expect(desktopFallback.toString(), equals(AppConstants.desktopUrl));
      expect(mobileFallback.toString(), equals(AppConstants.mobileUrl));
    });
  });

  group('Breakpoint & User-Agent Configuration Tests', () {
    test('Breakpoint is configured to 768.0 logical pixels', () {
      expect(AppConstants.desktopBreakpoint, equals(768.0));
    });

    test('User agent strings are configured and differentiated', () {
      expect(AppConstants.mobileUserAgent, contains('Mobile Safari'));
      expect(AppConstants.mobileUserAgent, isNot(contains('wv')));
      expect(AppConstants.desktopUserAgent, isNot(contains('Mobile')));
      expect(AppConstants.desktopUserAgent, contains('Macintosh'));
      expect(
        AppConstants.mobileUserAgent,
        isNot(equals(AppConstants.desktopUserAgent)),
      );
    });
  });

  group('AdBlocker Implementation Tests', () {
    test('Script contains video ad placement and slot pruning', () {
      expect(AdBlocker.injectionScript, contains('cleanAdPlacements'));
      expect(AdBlocker.injectionScript, contains('delete obj.adPlacements'));
      expect(AdBlocker.injectionScript, contains('delete obj.adSlots'));
      expect(AdBlocker.injectionScript, contains('delete obj.playerAds'));
    });

    test(
      'Script intercepts ytInitialPlayerResponse and fetch/XHR player APIs',
      () {
        expect(AdBlocker.injectionScript, contains('ytInitialPlayerResponse'));
        expect(AdBlocker.injectionScript, contains('window.fetch'));
        expect(AdBlocker.injectionScript, contains('XMLHttpRequest'));
        expect(AdBlocker.injectionScript, contains('/youtubei/v1/player'));
      },
    );

    test(
      'Script implements instant video ad skipper and skip-button clicker',
      () {
        expect(AdBlocker.injectionScript, contains('.ad-showing'));
        expect(AdBlocker.injectionScript, contains('.ad-interrupting'));
        expect(AdBlocker.injectionScript, contains('v.playbackRate = 16.0'));
        expect(
          AdBlocker.injectionScript,
          contains('v.currentTime = v.duration'),
        );
        expect(AdBlocker.injectionScript, contains('.ytp-ad-skip-button'));
      },
    );

    test(
      'Script injects cosmetic CSS rules for sponsored banners and promos',
      () {
        expect(AdBlocker.injectionScript, contains('ytd-ad-slot-renderer'));
        expect(
          AdBlocker.injectionScript,
          contains('.ytp-ad-overlay-container'),
        );
        expect(AdBlocker.injectionScript, contains('#player-ads'));
        expect(AdBlocker.injectionScript, contains('display: none !important'));
      },
    );

    test('Script handles anti-adblock enforcement dialog dismissal', () {
      expect(
        AdBlocker.injectionScript,
        contains('ytd-enforcement-message-view-model'),
      );
      expect(AdBlocker.injectionScript, contains('dismiss-button'));
    });
  });

  group('YouTubeDownloaderService Video & Shorts Extraction Tests', () {
    test('Extracts video ID from standard desktop watch URL', () {
      final id = YouTubeDownloaderService.extractVideoId(
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
      expect(id, equals('dQw4w9WgXcQ'));
      expect(
        YouTubeDownloaderService.isShortsUrl(
          'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        ),
        isFalse,
      );
    });

    test('Extracts video ID from mobile watch URL with extra params', () {
      final id = YouTubeDownloaderService.extractVideoId(
        'https://m.youtube.com/watch?v=dQw4w9WgXcQ&list=abc&index=1',
      );
      expect(id, equals('dQw4w9WgXcQ'));
      expect(
        YouTubeDownloaderService.isShortsUrl(
          'https://m.youtube.com/watch?v=dQw4w9WgXcQ',
        ),
        isFalse,
      );
    });

    test('Extracts video ID from desktop and mobile YouTube Shorts URL', () {
      final idDesktop = YouTubeDownloaderService.extractVideoId(
        'https://www.youtube.com/shorts/abcd1234XYZ',
      );
      final idMobile = YouTubeDownloaderService.extractVideoId(
        'https://m.youtube.com/shorts/abcd1234XYZ?feature=share',
      );

      expect(idDesktop, equals('abcd1234XYZ'));
      expect(idMobile, equals('abcd1234XYZ'));
      expect(
        YouTubeDownloaderService.isShortsUrl(
          'https://m.youtube.com/shorts/abcd1234XYZ',
        ),
        isTrue,
      );
    });

    test('Extracts video ID from youtu.be shortened links', () {
      final id = YouTubeDownloaderService.extractVideoId(
        'https://youtu.be/dQw4w9WgXcQ?t=10',
      );
      expect(id, equals('dQw4w9WgXcQ'));
    });

    test('Extracts video ID from embed links', () {
      final id = YouTubeDownloaderService.extractVideoId(
        'https://www.youtube.com/embed/dQw4w9WgXcQ',
      );
      expect(id, equals('dQw4w9WgXcQ'));
    });

    test('Returns null for non-video URLs (home feed, channels, search)', () {
      expect(
        YouTubeDownloaderService.extractVideoId('https://www.youtube.com/'),
        isNull,
      );
      expect(
        YouTubeDownloaderService.extractVideoId(
          'https://m.youtube.com/results?search_query=flutter',
        ),
        isNull,
      );
      expect(
        YouTubeDownloaderService.extractVideoId(
          'https://www.youtube.com/@FlutterDev',
        ),
        isNull,
      );
      expect(YouTubeDownloaderService.extractVideoId(''), isNull);
      expect(YouTubeDownloaderService.extractVideoId(null), isNull);
    });
  });

  group('YouTube Navbar Integration Tests', () {
    test('AdBlocker script contains Home, Shorts, Settings, Download navbar ordering and channel wiring', () {
      final script = AdBlocker.injectionScript;
      expect(script.contains('setupYouTubeNavBar'), isTrue);
      expect(script.contains('__yt_downloads_pivot_tab__'), isTrue);
      expect(script.contains('homeItem'), isTrue);
      expect(script.contains('shortsItem'), isTrue);
      expect(script.contains('__yt_settings_pivot_tab__'), isTrue);
      expect(script.contains('open_settings'), isTrue);
      expect(script.contains('DownloadsChannel'), isTrue);
      expect(script.contains('open_downloads'), isTrue);
    });

    test('Injected controls comply with YouTube Trusted Types policy', () {
      final script = AdBlocker.injectionScript;
      expect(RegExp(r'\.innerHTML\s*=').hasMatch(script), isFalse);
      expect(RegExp(r'\.outerHTML\s*=').hasMatch(script), isFalse);
      expect(script.contains('createElementNS'), isTrue);
      expect(script.contains('createControlLabel'), isTrue);
    });
  });

  group('Video Action Bar Download & Like/Dislike Hiding Tests', () {
    test('AdBlocker script hides Like and Dislike buttons via CSS', () {
      final script = AdBlocker.injectionScript;
      expect(
        script.contains('ytm-segmented-like-dislike-button-renderer'),
        isTrue,
      );
      expect(
        script.contains('ytd-segmented-like-dislike-button-renderer'),
        isTrue,
      );
      expect(
        script.contains('segmented-like-dislike-button-view-model'),
        isTrue,
      );
      expect(script.contains('like-button-view-model'), isTrue);
      expect(script.contains('dislike-button-view-model'), isTrue);
      expect(
        script.contains('button[aria-label*="like this video" i]'),
        isTrue,
      );
      expect(
        script.contains('button[aria-label*="dislike this video" i]'),
        isTrue,
      );
    });

    test('AdBlocker script injects Download button into video player action bar and Shorts overlay', () {
      final script = AdBlocker.injectionScript;
      expect(script.contains('injectYouTubeCustomUI'), isTrue);
      expect(script.contains('__yt_video_action_download_btn__'), isTrue);
      expect(script.contains('__yt_shorts_action_download_btn__'), isTrue);
      expect(
        script.contains(
          "DownloadsChannel.postMessage('download_active_video')",
        ),
        isTrue,
      );
    });
  });

  group('Premium Features AdBlocker Injection Tests', () {
    test(
      'Script enables Background Play by capturing visibility and blur events',
      () {
        final script = AdBlocker.injectionScript;
        expect(
          script.contains("Object.defineProperty(document, 'hidden'"),
          isTrue,
        );
        expect(
          script.contains("Object.defineProperty(document, 'visibilityState'"),
          isTrue,
        );
        expect(script.contains('visibilitychange'), isTrue);
        expect(script.contains('pagehide'), isTrue);
      },
    );

    test(
      'Script provides PiP, Jump Ahead, Enhanced 1080p, and Player Monitoring',
      () {
        final script = AdBlocker.injectionScript;
        expect(script.contains('__togglePiP__'), isTrue);
        expect(script.contains('__setNativePiPMode__'), isTrue);
        expect(script.contains("type: 'playback'"), isTrue);
        expect(script.contains('video.videoWidth'), isTrue);
        expect(script.contains('__jumpAhead__'), isTrue);
        expect(script.contains('setEnhanced1080pQuality'), isTrue);
        expect(script.contains('setPlaybackQualityRange'), isTrue);
        expect(script.contains('setupPlayerMonitoring'), isTrue);
        expect(script.contains('PlayerStateChannel'), isTrue);
        expect(script.contains("DownloadsChannel.postMessage('pip')"), isTrue);
        expect(
          script.contains("DownloadsChannel.postMessage('jump_ahead')"),
          isTrue,
        );
        expect(
          script.contains("DownloadsChannel.postMessage('open_queue')"),
          isTrue,
        );
        expect(
          script.contains("setPlaybackQualityRange('hd1080', 'hd1080')"),
          isTrue,
        );
      },
    );
  });

  group('Watch Queue Service Tests', () {
    setUp(() {
      QueueService.instance.clear();
    });

    test('Adds videos to queue, pops next, and preserves FIFO order', () {
      final queue = QueueService.instance;
      expect(queue.isEmpty, isTrue);

      queue.addToQueue(
        const QueuedVideo(
          videoId: 'vid1',
          title: 'Video One',
          url: 'https://m.youtube.com/watch?v=vid1',
        ),
      );
      queue.addToQueue(
        const QueuedVideo(
          videoId: 'vid2',
          title: 'Video Two',
          url: 'https://m.youtube.com/watch?v=vid2',
        ),
      );

      expect(queue.length, equals(2));
      expect(queue.queue.first.title, equals('Video One'));

      // Play next inserts at front
      queue.playNext(
        const QueuedVideo(
          videoId: 'vid3',
          title: 'Video Three (Priority)',
          url: 'https://m.youtube.com/watch?v=vid3',
        ),
      );
      expect(queue.length, equals(3));
      expect(queue.queue.first.title, equals('Video Three (Priority)'));

      // Pop next
      final next = queue.popNext();
      expect(next?.videoId, equals('vid3'));
      expect(queue.length, equals(2));

      // Remove at
      queue.removeAt(0);
      expect(queue.length, equals(1));
      expect(queue.queue.first.videoId, equals('vid2'));

      // Clear
      queue.clear();
      expect(queue.isEmpty, isTrue);
    });

    test('Taking a selected queue item removes it before playback', () {
      final queue = QueueService.instance;
      queue.addToQueue(
        const QueuedVideo(
          videoId: 'selected',
          title: 'Selected',
          url: 'https://m.youtube.com/watch?v=selected',
        ),
      );
      final selected = queue.takeAt(0);
      expect(selected?.videoId, 'selected');
      expect(queue.isEmpty, isTrue);
    });
  });

  group('Watch History Checkpoint Tests', () {
    test(
      'VideoCheckpoint calculates progress and formats timestamp correctly',
      () {
        final cp = VideoCheckpoint(
          videoId: 'vid_test',
          title: 'Flutter Crash Course',
          positionSeconds: 125,
          durationSeconds: 600,
          lastWatched: DateTime.now(),
        );

        expect(cp.progress, closeTo(125 / 600, 0.01));
        expect(cp.positionFormatted, equals('2:05'));

        final json = cp.toJson();
        final restored = VideoCheckpoint.fromJson(json);
        expect(restored.videoId, equals('vid_test'));
        expect(restored.title, equals('Flutter Crash Course'));
        expect(restored.positionSeconds, equals(125));
      },
    );
  });
}
