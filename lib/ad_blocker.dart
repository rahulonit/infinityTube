/// Comprehensive YouTube ad blocking and UI enhancement script.
///
/// Multi-layered architecture:
/// 1. Network / JSON Response Pruning:
///    Intercepts `fetch`, `XMLHttpRequest`, and `JSON.parse` for `/youtubei/v1/player`
///    to delete `adPlacements`, `adSlots`, and `playerAds` before the player can initialize
///    pre-roll (starting) or mid-roll video ads.
/// 2. Global State Interception:
///    Hooks `window.ytInitialPlayerResponse` on initial page loads to strip ad cue points.
/// 3. Instant Video Ad Terminator:
///    Continuously watches for `.ad-showing` / `.ad-interrupting` states. If a video ad ever
///    attempts to display, immediately mutes, boosts playback to 16x, advances `currentTime`
///    to `duration`, and clicks any skip buttons.
/// 4. Cosmetic Filtering & OLED Pitch-Black Theme:
///    Injects true `#000000` pitch black background and hides all display ads, sponsored
///    videos, "Open in App" nag banners, and "Try YouTube Premium" promos.
/// 5. Native-like Double-Tap Skip Gestures:
///    Double-tap left/right on video skips 10s backward/forward with visual animated badges.
/// 6. Flutter Communication Bridge:
///    Notifies Flutter via `AdBlockChannel` and `FullscreenChannel`.
class AdBlocker {
  static const String injectionScript = r'''
(function() {
  if (window.__yt_adblock_installed__) return;
  window.__yt_adblock_installed__ = true;
  const infinitySettings = Object.assign({
    adBlocking: true,
    trackerBlocking: true,
    cosmeticFiltering: true,
    backgroundPlayback: true,
    pictureInPicture: true,
    enhanced1080: true,
    seekSeconds: 10
  }, window.__infinitySettings__ || {});

  // 1. Helper to notify Flutter when an ad is blocked
  function notifyAdBlocked() {
    try {
      if (window.AdBlockChannel) {
        window.AdBlockChannel.postMessage('ad_blocked');
      }
    } catch(e) {}
  }

  // 2. Helper to clean ad placements and ad configurations
  function cleanAdPlacements(obj) {
    if (!infinitySettings.adBlocking) return false;
    if (!obj || typeof obj !== 'object') return false;
    let modified = false;
    try {
      if (obj.adPlacements) { delete obj.adPlacements; modified = true; }
      if (obj.adSlots) { delete obj.adSlots; modified = true; }
      if (obj.playerAds) { delete obj.playerAds; modified = true; }
      if (obj.adBreakHeartbeatParams) { delete obj.adBreakHeartbeatParams; modified = true; }
      if (obj.playerConfig && obj.playerConfig.adPlacements) {
        delete obj.playerConfig.adPlacements;
        modified = true;
      }
      if (obj.playerResponse) {
        if (cleanAdPlacements(obj.playerResponse)) modified = true;
      }
    } catch(e) {}
    if (modified) {
      notifyAdBlocked();
    }
    return modified;
  }

  const blockedTrackerHosts = [
    'doubleclick.net',
    'googleadservices.com',
    'googlesyndication.com',
    'pagead2.googlesyndication.com',
    '/pagead/',
    '/ptracking',
    '/api/stats/ads'
  ];

  function isBlockedTrackerUrl(url) {
    if (!infinitySettings.trackerBlocking) return false;
    if (!url || typeof url !== 'string') return false;
    const normalized = url.toLowerCase();
    return blockedTrackerHosts.some(pattern => normalized.includes(pattern));
  }

  // 3. Intercept window.ytInitialPlayerResponse (initial cold load)
  let _ytInitialPlayerResponse = window.ytInitialPlayerResponse;
  cleanAdPlacements(_ytInitialPlayerResponse);
  try {
    Object.defineProperty(window, 'ytInitialPlayerResponse', {
      get() { return _ytInitialPlayerResponse; },
      set(val) {
        cleanAdPlacements(val);
        _ytInitialPlayerResponse = val;
      },
      configurable: true
    });
  } catch(e) {}

  // 4. Hook JSON.parse to prune ad responses globally
  try {
    const origParse = JSON.parse;
    JSON.parse = function(...args) {
      const res = origParse.apply(this, args);
      if (res && typeof res === 'object') {
        cleanAdPlacements(res);
      }
      return res;
    };
  } catch(e) {}

  // 5. Hook window.fetch for /youtubei/v1/player (SPA video navigations)
  try {
    const origFetch = window.fetch;
    window.fetch = async function(...args) {
      const url = typeof args[0] === 'string'
        ? args[0]
        : (args[0] && args[0].url ? args[0].url : '');

      if (isBlockedTrackerUrl(url)) {
        notifyAdBlocked();
        return new Response('', { status: 204, statusText: 'Blocked' });
      }

      const response = await origFetch.apply(this, args);

      if (url && (url.includes('/youtubei/v1/player') || url.includes('/get_midroll_info'))) {
        try {
          const clone = response.clone();
          const data = await clone.json();
          cleanAdPlacements(data);
          return new Response(JSON.stringify(data), {
            status: response.status,
            statusText: response.statusText,
            headers: response.headers
          });
        } catch(e) {
          return response;
        }
      }
      return response;
    };
  } catch(e) {}

  // 6. Hook XMLHttpRequest for player requests
  try {
    const origOpen = XMLHttpRequest.prototype.open;
    const origSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function(method, url, ...rest) {
      this._isBlockedTracker = isBlockedTrackerUrl(url);
      this._isPlayerUrl = typeof url === 'string' &&
        (url.includes('/youtubei/v1/player') || url.includes('/get_midroll_info'));
      return origOpen.apply(this, [method, url, ...rest]);
    };
    XMLHttpRequest.prototype.send = function(...args) {
      if (this._isBlockedTracker) {
        notifyAdBlocked();
        try { this.abort(); } catch(e) {}
        return;
      }
      if (this._isPlayerUrl) {
        this.addEventListener('readystatechange', function() {
          if (this.readyState === 4 && this.status === 200) {
            try {
              const data = JSON.parse(this.responseText);
              cleanAdPlacements(data);
              Object.defineProperty(this, 'responseText', {
                value: JSON.stringify(data),
                configurable: true
              });
              Object.defineProperty(this, 'response', {
                value: JSON.stringify(data),
                configurable: true
              });
            } catch(e) {}
          }
        }, false);
      }
      return origSend.apply(this, args);
    };
  } catch(e) {}

  // 7. Fast Video Ad Terminator (for starting / in-video ads that reach the DOM)
  let adWasActive = false;
  const mediaStateBeforeAd = new Map();

  function killVideoAds() {
    if (!infinitySettings.adBlocking) return;
    const player = document.querySelector('#movie_player') ||
                   document.querySelector('.html5-video-player') ||
                   document.querySelector('.video-stream');

    const isAdShowing = document.querySelector('.ad-showing') ||
                        document.querySelector('.ad-interrupting') ||
                        document.querySelector('.ytp-ad-player-overlay') ||
                        document.querySelector('.video-ads.ytp-ad-module:not(:empty)') ||
                        (player && (player.classList.contains('ad-showing') || player.classList.contains('ad-interrupting')));

    if (isAdShowing) {
      notifyAdBlocked();
      const videos = document.querySelectorAll('video');
      videos.forEach(v => {
        try {
          if (!adWasActive) {
            mediaStateBeforeAd.set(v, {
              muted: v.muted,
              playbackRate: v.playbackRate
            });
          }
          v.muted = true;
          v.playbackRate = 16.0;
          if (v.duration && isFinite(v.duration) && v.duration > 0) {
            v.currentTime = v.duration;
          } else {
            v.currentTime = 99999;
          }
        } catch(e) {}
      });
      adWasActive = true;

      // Click all variations of skip buttons (mobile & desktop)
      const skipButtons = document.querySelectorAll(
        '.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button, ' +
        '.videoAdUiSkipButton, button.ytp-ad-skip-button-modern, ' +
        '.ytp-ad-skip-button-container button, [id^="skip-button:"] button, ' +
        '.ytm-skip-ad-button, .ytp-ad-overlay-close-button'
      );
      skipButtons.forEach(btn => {
        try { btn.click(); } catch(e) {}
      });
    } else if (adWasActive) {
      // Restore each video's exact pre-ad mute and playback-rate state.
      mediaStateBeforeAd.forEach((state, video) => {
        try {
          video.playbackRate = state.playbackRate;
          video.muted = state.muted;
        } catch(e) {}
      });
      mediaStateBeforeAd.clear();
      adWasActive = false;
    }

    // Dismiss any anti-adblock enforcement dialogs
    const enforcementPopups = document.querySelectorAll(
      'tp-yt-iron-overlay-backdrop, ytd-enforcement-message-view-model, ' +
      'ytd-popup-container:has(ytd-enforcement-message-view-model)'
    );
    if (enforcementPopups.length > 0) {
      enforcementPopups.forEach(p => p.remove());
      const dismissBtn = document.getElementById('dismiss-button');
      if (dismissBtn) dismissBtn.click();
      const video = document.querySelector('video');
      if (video && video.paused) {
        try { video.play(); } catch(e) {}
      }
    }
  }

  setInterval(killVideoAds, 50);

  // 8. OLED Pitch-Black Theme & Web Clutter / Nag Removal CSS
  function injectOledAndClutterRemovalStyles() {
    if (!infinitySettings.cosmeticFiltering) return;
    if (document.getElementById('__yt_oled_clutter_css__')) return;
    const style = document.createElement('style');
    style.id = '__yt_oled_clutter_css__';
    style.textContent = `
      /* OLED Pitch Black Background & Smooth Native Touch Scrolling */
      html, body {
        overflow-y: auto !important;
        overflow-x: hidden !important;
        -webkit-overflow-scrolling: touch !important;
        touch-action: pan-y !important;
        height: auto !important;
      }

      html, body, #content, ytd-app, ytm-app, #page-manager, ytd-page-manager,
      #player-container-id, .player-container, #background, #guide-content,
      ytd-mini-guide-renderer, ytd-masthead, #masthead, ytm-mobile-topbar-renderer,
      ytd-watch-flexy, ytm-watch, #columns, #primary, #secondary,
      .watch-while-container, ytd-browse, ytm-browse {
        background-color: #000000 !important;
        background: #000000 !important;
      }

      /* Ensure backdrops and polymer dialog backdrops never lock touch input */
      tp-yt-iron-overlay-backdrop,
      iron-overlay-backdrop,
      tp-yt-paper-dialog-behavior-backdrop {
        display: none !important;
        pointer-events: none !important;
      }

      /* Cosmetic Ad Removal */
      .ytp-ad-overlay-container,
      .ytp-ad-message-container,
      .ytp-ad-progress-list,
      .ytp-ad-player-overlay,
      ytd-ad-slot-renderer,
      ytd-in-feed-ad-layout-renderer,
      ytd-banner-promo-renderer,
      ytd-promoted-video-renderer,
      ytd-display-ad-renderer,
      ytm-promoted-sparkles-web-renderer,
      ytm-companion-ad-renderer,
      #player-ads,
      #masthead-ad,
      ytd-rich-item-renderer:has(ytd-ad-slot-renderer),
      ytd-video-masthead-ad-v3-renderer,
      .ad-showing .ytp-ad-player-overlay,

      /* Remove Web Clutter: "Open App", "Try Premium", Nag Banners */
      ytm-app-banner,
      ytm-pivot-bar-renderer:has(ytm-open-app-button),
      .mobile-topbar-header-sign-in-button,
      a.mobile-topbar-header-endpoint[href*="app"],
      ytm-open-app-button,
      yt-mealbar-promo-renderer,
      ytd-statement-banner-renderer,
      yt-upsell-dialog-renderer,
      ytd-primetime-promo-renderer,
      ytd-clarification-renderer,
      #clarify-box,
      tp-yt-paper-dialog:has(#feedback),
      .ytm-promoted-sparkles-text-search-renderer {
        display: none !important;
        visibility: hidden !important;
        height: 0 !important;
        width: 0 !important;
        pointer-events: none !important;
      }

      /* Hide Like, Dislike, and native non-functional download buttons */
      ytm-segmented-like-dislike-button-renderer,
      ytd-segmented-like-dislike-button-renderer,
      segmented-like-dislike-button-view-model,
      #segmented-like-dislike-button,
      .yt-spec-segmented-like-dislike-button,
      ytm-like-button-renderer,
      ytm-dislike-button-renderer,
      ytd-like-button-renderer,
      ytd-dislike-button-renderer,
      like-button-view-model,
      dislike-button-view-model,
      ytm-download-button-renderer,
      ytd-download-button-renderer,
      button[aria-label*="like this video" i],
      button[aria-label*="dislike this video" i],
      button[aria-label*="like this short" i],
      button[aria-label*="dislike this short" i],
      button[aria-label*="I like this" i],
      button[aria-label*="I dislike this" i],
      .shorts-overlay-actions ytm-like-button-renderer,
      .shorts-overlay-actions ytm-dislike-button-renderer,
      .shorts-overlay-actions like-button-view-model,
      .shorts-overlay-actions dislike-button-view-model {
        display: none !important;
        visibility: hidden !important;
        height: 0 !important;
        width: 0 !important;
        margin: 0 !important;
        padding: 0 !important;
        pointer-events: none !important;
      }

      /* Always ensure custom InfinityTube action buttons and masthead button are visible */
      #__yt_custom_actions_group__,
      #__yt_custom_actions_group__ *,
      #__yt_video_action_download_btn__,
      #__yt_video_action_download_btn__ *,
      #__yt_video_action_pip_btn__,
      #__yt_video_action_pip_btn__ *,
      #__yt_video_action_jump_btn__,
      #__yt_video_action_jump_btn__ *,
      #__yt_video_action_queue_btn__,
      #__yt_video_action_queue_btn__ *,
      #__yt_shorts_action_download_btn__,
      #__yt_shorts_action_download_btn__ *,
      #__yt_shorts_action_pip_btn__,
      #__yt_shorts_action_pip_btn__ *,
      #__yt_shorts_action_queue_btn__,
      #__yt_shorts_action_queue_btn__ *,
      #__yt_masthead_premium_btn__,
      #__yt_masthead_premium_btn__ * {
        visibility: visible !important;
        opacity: 1 !important;
        pointer-events: auto !important;
      }

      /* Keep native actions usable instead of overflowing on narrow phones. */
      ytm-slim-video-action-bar-renderer,
      ytm-video-action-bar-renderer,
      #top-level-buttons-computed {
        overflow-x: auto !important;
        scrollbar-width: none !important;
      }
      @media (max-width: 480px) {
        #__yt_video_action_download_btn__,
        #__yt_video_action_pip_btn__ {
          min-width: 48px !important;
          width: 48px !important;
          padding: 0 12px !important;
        }
        #__yt_video_action_download_btn__ span,
        #__yt_video_action_pip_btn__ span {
          display: none !important;
        }
        #__yt_video_action_jump_btn__,
        #__yt_video_action_queue_btn__ {
          min-width: 60px !important;
          padding: 0 8px !important;
        }
      }

      /* Hide YouTube web bottom pivot bar because native 4-tab Flutter navbar is active */
      ytm-pivot-bar-renderer,
      .pivot-bar-item-tab {
        display: none !important;
        visibility: hidden !important;
        height: 0 !important;
        pointer-events: none !important;
      }
    `;
    (document.head || document.documentElement).appendChild(style);
  }

  injectOledAndClutterRemovalStyles();
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', injectOledAndClutterRemovalStyles);
  }

  // 9. Native Double-Tap 10s Skip Gesture Implementation
  function showGestureFeedback(text, x, y) {
    let badge = document.getElementById('__yt_gesture_badge__');
    if (!badge) {
      badge = document.createElement('div');
      badge.id = '__yt_gesture_badge__';
      badge.style.cssText = `
        position: fixed;
        background: rgba(0, 0, 0, 0.75);
        color: #fff;
        padding: 8px 16px;
        border-radius: 20px;
        font-family: sans-serif;
        font-size: 14px;
        font-weight: 600;
        pointer-events: none;
        z-index: 999999;
        transition: opacity 0.3s ease, transform 0.3s ease;
        transform: translate(-50%, -50%) scale(1);
        opacity: 0;
      `;
      document.body.appendChild(badge);
    }
    badge.textContent = text;
    badge.style.left = x + 'px';
    badge.style.top = y + 'px';
    badge.style.opacity = '1';
    badge.style.transform = 'translate(-50%, -50%) scale(1.1)';

    clearTimeout(badge._timer);
    badge._timer = setTimeout(() => {
      badge.style.opacity = '0';
      badge.style.transform = 'translate(-50%, -50%) scale(0.9)';
    }, 450);
  }

  function installDoubleTapGestures() {
    const player = document.querySelector('#movie_player') ||
                   document.querySelector('.html5-video-player') ||
                   document.querySelector('video');
    if (!player || player.__dt_installed__) return;
    player.__dt_installed__ = true;

    let lastTapTime = 0;
    let lastTapX = 0;

    player.addEventListener('touchend', (e) => {
      const touch = e.changedTouches && e.changedTouches[0];
      if (!touch) return;
      const now = Date.now();
      const rect = player.getBoundingClientRect();
      const tapX = touch.clientX - rect.left;
      const width = rect.width;

      if (now - lastTapTime < 320 && Math.abs(tapX - lastTapX) < 90) {
        const video = document.querySelector('video');
        if (video) {
          if (tapX < width * 0.4) {
            video.currentTime = Math.max(0, video.currentTime - infinitySettings.seekSeconds);
            showGestureFeedback('◀◀ ' + infinitySettings.seekSeconds + 's', touch.clientX, touch.clientY);
          } else if (tapX > width * 0.6) {
            video.currentTime = Math.min(video.duration || 99999, video.currentTime + infinitySettings.seekSeconds);
            showGestureFeedback(infinitySettings.seekSeconds + 's ▶▶', touch.clientX, touch.clientY);
          }
        }
      }
      lastTapTime = now;
      lastTapX = tapX;
    }, { passive: true });
  }

  installDoubleTapGestures();

  // 10. Background Play Enabler: Prevent player from pausing when app is minimized or screen off
  try {
    if (!infinitySettings.backgroundPlayback) throw new Error('disabled');
    Object.defineProperty(document, 'hidden', { get: () => false, configurable: true });
    Object.defineProperty(document, 'visibilityState', { get: () => 'visible', configurable: true });
    Object.defineProperty(document, 'webkitVisibilityState', { get: () => 'visible', configurable: true });

    ['visibilitychange', 'webkitvisibilitychange', 'blur', 'pagehide'].forEach(evt => {
      window.addEventListener(evt, (e) => e.stopImmediatePropagation(), true);
      document.addEventListener(evt, (e) => e.stopImmediatePropagation(), true);
    });
  } catch(e) {}

  // 11. Picture-in-Picture (PiP)
  window.__togglePiP__ = async function() {
    try {
      const video = document.querySelector('video');
      if (video && document.pictureInPictureEnabled) {
        if (document.pictureInPictureElement) {
          await document.exitPictureInPicture();
          return true;
        } else if (video.requestPictureInPicture) {
          await video.requestPictureInPicture();
          return true;
        }
      }
    } catch(e) {}
    return false;
  };

  window.__setNativePiPMode__ = function(enabled) {
    try {
      let style = document.getElementById('__infinity_native_pip_style__');
      if (!style) {
        style = document.createElement('style');
        style.id = '__infinity_native_pip_style__';
        style.textContent = `
          html.__infinity_native_pip__,
          html.__infinity_native_pip__ body {
            background: #000 !important;
            overflow: hidden !important;
          }
          html.__infinity_native_pip__ video {
            position: fixed !important;
            inset: 0 !important;
            width: 100vw !important;
            height: 100vh !important;
            object-fit: contain !important;
            background: #000 !important;
            z-index: 2147483647 !important;
          }
        `;
        (document.head || document.documentElement).appendChild(style);
      }
      document.documentElement.classList.toggle('__infinity_native_pip__', !!enabled);
      return true;
    } catch(e) {
      return false;
    }
  };

  // 12. Jump Ahead: Skips +30s or to peak interest moments
  window.__jumpAhead__ = function() {
    try {
      const video = document.querySelector('video');
      if (!video) return;
      video.currentTime = Math.min((video.duration || 99999) - 2, video.currentTime + 30);
      showGestureFeedback('Jump Ahead ⏩', window.innerWidth / 2, window.innerHeight / 2);
    } catch(e) {}
  };

  // 13. Enhanced 1080p: Auto-requests highest available bitrate quality on player
  function setEnhanced1080pQuality() {
    if (!infinitySettings.enhanced1080) return;
    try {
      const player = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
      if (player && typeof player.setPlaybackQualityRange === 'function') {
        player.setPlaybackQualityRange('hd1080', 'hd1080');
      }
    } catch(e) {}
  }

  // 14. Player Monitoring: Reports playback progress (for Continue Watching) and video end (for Queuing)
  function setupPlayerMonitoring() {
    const video = document.querySelector('video');
    if (!video || video.__monitoring_installed__) return;
    video.__monitoring_installed__ = true;

    function reportPlaybackState() {
      try {
        if (window.PlayerStateChannel) {
          window.PlayerStateChannel.postMessage(JSON.stringify({
            type: 'playback',
            playing: !video.paused && !video.ended && video.readyState > 1,
            width: video.videoWidth || 16,
            height: video.videoHeight || 9,
          }));
        }
      } catch(e) {}
    }

    video.addEventListener('play', reportPlaybackState);
    video.addEventListener('playing', reportPlaybackState);
    video.addEventListener('pause', reportPlaybackState);
    video.addEventListener('loadedmetadata', reportPlaybackState);
    video.addEventListener('emptied', reportPlaybackState);
    reportPlaybackState();

    video.addEventListener('ended', () => {
      reportPlaybackState();
      try {
        if (window.PlayerStateChannel) {
          window.PlayerStateChannel.postMessage(JSON.stringify({ type: 'ended' }));
        }
      } catch(e) {}
    });

    let lastReportTime = 0;
    video.addEventListener('timeupdate', () => {
      const now = Date.now();
      if (now - lastReportTime > 4000) {
        lastReportTime = now;
        try {
          if (window.PlayerStateChannel && video.duration > 0) {
            const titleEl = document.querySelector('h1.title, .slim-video-metadata-title, ytm-slim-video-metadata-section-renderer .title');
            const title = titleEl ? titleEl.textContent.trim() : '';
            window.PlayerStateChannel.postMessage(JSON.stringify({
              type: 'progress',
              position: Math.round(video.currentTime),
              duration: Math.round(video.duration),
              title: title,
              url: window.location.href,
            }));
          }
        } catch(e) {}
      }
    });
  }

  // 15. Fullscreen Change Detection
  function onFullscreenChange() {
    const isFullscreen = !!(document.fullscreenElement || document.webkitFullscreenElement);
    try {
      if (window.FullscreenChannel) {
        window.FullscreenChannel.postMessage(isFullscreen ? 'fullscreen_enter' : 'fullscreen_exit');
      }
    } catch(e) {}
  }

  document.addEventListener('fullscreenchange', onFullscreenChange);
  document.addEventListener('webkitfullscreenchange', onFullscreenChange);

  // 11. Ensure page scroll is never locked by modal backdrops
  function unlockScroll() {
    try {
      if (document.body) {
        if (document.body.style.overflow === 'hidden') document.body.style.overflow = '';
        if (document.body.style.pointerEvents === 'none') document.body.style.pointerEvents = '';
      }
      if (document.documentElement) {
        if (document.documentElement.style.overflow === 'hidden') document.documentElement.style.overflow = '';
      }
      const backdrops = document.querySelectorAll('tp-yt-iron-overlay-backdrop, iron-overlay-backdrop, tp-yt-paper-dialog-behavior-backdrop');
      backdrops.forEach(b => {
        b.style.pointerEvents = 'none';
        b.remove();
      });
    } catch(e) {}
  }

  // YouTube enforces Trusted Types. Build injected controls with DOM nodes
  // instead of assigning HTML strings, which Chromium blocks and logs.
  function createControlIcon(pathData, size, fill) {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('width', String(size));
    svg.setAttribute('height', String(size));
    svg.setAttribute('fill', fill);
    svg.style.pointerEvents = 'none';
    svg.style.flexShrink = '0';
    const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    path.setAttribute('d', pathData);
    svg.appendChild(path);
    return svg;
  }

  function createControlLabel(text, cssText) {
    const label = document.createElement('span');
    label.textContent = text;
    label.style.cssText = cssText;
    return label;
  }

  const downloadIconPath = 'M12 16l4-4h-3V4h-2v8H8l4 4zm9 4H3v-2h18v2z';
  const pipIconPath = 'M19 11h-8v6h8v-6zm4 8V4.98C23 3.88 22.1 3 21 3H3c-1.1 0-2 .88-2 1.98V19c0 1.1.9 2 2 2h18c1.1 0 2-.9 2-2zm-2 .02H3V4.97h18v14.05z';
  const premiumIconPath = 'M12 17.27L18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21z';

  // 12. Configures YouTube bottom navigation bar to: [Home] [Shorts] [Settings] [Download]
  function setupYouTubeNavBar() {
    const pivotBar = document.querySelector('ytm-pivot-bar-renderer');
    if (pivotBar) {
      const items = Array.from(pivotBar.querySelectorAll('ytm-pivot-bar-item-renderer, .pivot-bar-item-tab, a.pivot-bar-item-tab'))
                         .filter(el => el.id !== '__yt_downloads_pivot_tab__' && el.id !== '__yt_settings_pivot_tab__');

      let homeItem = null;
      let shortsItem = null;
      let youItem = null;
      let subsItem = null;
      const createItems = [];

      items.forEach((item) => {
        const text = (item.textContent || '').trim().toLowerCase();
        const href = (item.getAttribute('href') || '').toLowerCase();
        const aria = (item.getAttribute('aria-label') || '').toLowerCase();
        const html = item.innerHTML.toLowerCase();

        if (aria.includes('create') || aria.includes('upload') || text.includes('create') || text.includes('upload') || html.includes('c3-icon-plus')) {
          createItems.push(item);
        } else if (text === 'home' || href === '/' || href === '/?app=m' || aria.includes('home')) {
          homeItem = item;
        } else if (text.includes('short') || href.includes('short') || aria.includes('short')) {
          shortsItem = item;
        } else if (text.includes('you') || href.includes('/feed/you') || href.includes('/feed/library') || aria.includes('you') || text.includes('library') || aria.includes('library') || href.includes('/account')) {
          youItem = item;
        } else if (text.includes('subscription') || href.includes('subscription') || aria.includes('subscription')) {
          subsItem = item;
        }
      });

      // Hide any Create (+) buttons to keep the clean 4-tab layout
      createItems.forEach(item => {
        item.style.setProperty('display', 'none', 'important');
      });

      // Native Settings replaces You/Subscriptions in the strict 4-tab layout.
      if (youItem) youItem.style.setProperty('display', 'none', 'important');
      if (subsItem) subsItem.style.setProperty('display', 'none', 'important');

      let settingsTab = document.getElementById('__yt_settings_pivot_tab__');
      if (!settingsTab) {
        settingsTab = document.createElement('div');
        settingsTab.id = '__yt_settings_pivot_tab__';
        settingsTab.className = 'ytm-pivot-bar-item-renderer pivot-bar-item-tab';
        settingsTab.style.cssText = `
          flex: 1 1 0;
          max-width: 25%;
          height: 100%;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          cursor: pointer;
          user-select: none;
          -webkit-tap-highlight-color: transparent;
          color: #ffffff;
        `;
        settingsTab.appendChild(createControlLabel(
          '⚙',
          'color:#ffffff;font-size:22px;line-height:24px;font-family:Arial,sans-serif;'
        ));
        settingsTab.appendChild(createControlLabel(
          'Settings',
          'font-size:10px;color:#ffffff;margin-top:3px;font-weight:500;font-family:Roboto,Arial,sans-serif;'
        ));
        settingsTab.addEventListener('click', (e) => {
          e.preventDefault();
          e.stopPropagation();
          try {
            if (window.DownloadsChannel) {
              window.DownloadsChannel.postMessage('open_settings');
            }
          } catch(err) {}
        }, true);
      }

      // Create or retrieve Download Tab
      let downloadTab = document.getElementById('__yt_downloads_pivot_tab__');
      if (!downloadTab) {
        downloadTab = document.createElement('div');
        downloadTab.id = '__yt_downloads_pivot_tab__';
        downloadTab.className = 'ytm-pivot-bar-item-renderer pivot-bar-item-tab';
        downloadTab.style.cssText = `
          flex: 1 1 0;
          max-width: 25%;
          height: 100%;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          cursor: pointer;
          user-select: none;
          -webkit-tap-highlight-color: transparent;
          color: #ffffff;
        `;
        const iconWrap = document.createElement('div');
        iconWrap.style.cssText = 'width:24px;height:24px;display:flex;align-items:center;justify-content:center;';
        iconWrap.appendChild(createControlIcon(downloadIconPath, 22, '#ffffff'));
        downloadTab.appendChild(iconWrap);
        downloadTab.appendChild(createControlLabel(
          'Download',
          'font-size:10px;color:#ffffff;margin-top:3px;font-weight:500;letter-spacing:-0.2px;font-family:Roboto,Arial,sans-serif;'
        ));

        downloadTab.addEventListener('click', (e) => {
          e.preventDefault();
          e.stopPropagation();
          try {
            if (window.DownloadsChannel) {
              window.DownloadsChannel.postMessage('open_downloads');
            }
          } catch(err) {}
        }, true);
      }

      // Re-order strictly: [Home] -> [Shorts] -> [Settings] -> [Download]
      if (homeItem && homeItem.parentElement === pivotBar) {
        pivotBar.appendChild(homeItem);
      }
      if (shortsItem && shortsItem.parentElement === pivotBar) {
        pivotBar.appendChild(shortsItem);
      }
      pivotBar.appendChild(settingsTab);
      pivotBar.appendChild(downloadTab);
    }

    // Tablet / Desktop mini-guide support
    const miniGuide = document.querySelector('ytd-mini-guide-renderer #items');
    if (miniGuide && !document.getElementById('__yt_desktop_downloads_guide_entry__')) {
      const entry = document.createElement('ytd-mini-guide-entry-renderer');
      entry.id = '__yt_desktop_downloads_guide_entry__';
      entry.className = 'style-scope ytd-mini-guide-renderer';
      entry.setAttribute('role', 'tab');
      entry.setAttribute('tabindex', '0');
      entry.style.cssText = 'cursor: pointer; display: flex; flex-direction: column; align-items: center; justify-content: center; padding: 16px 0; color: #fff;';
      const guideIconWrap = document.createElement('div');
      guideIconWrap.style.cssText = 'width:24px;height:24px;display:flex;align-items:center;justify-content:center;margin-bottom:6px;';
      guideIconWrap.appendChild(createControlIcon(downloadIconPath, 24, '#ffffff'));
      entry.appendChild(guideIconWrap);
      entry.appendChild(createControlLabel(
        'Download',
        'font-size:10px;color:#ffffff;font-family:Roboto,Arial,sans-serif;'
      ));
      entry.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();
        try {
          if (window.DownloadsChannel) {
            window.DownloadsChannel.postMessage('open_downloads');
          }
        } catch(err) {}
      }, true);
      miniGuide.appendChild(entry);
    }
  }

  // 13. Injects Custom InfinityTube Controls directly into YouTube UI (Action Bar, Shorts, and Top Masthead)
  // 13. Injects Custom InfinityTube Controls directly into YouTube UI (replacing Like/Dislike with Download)
  function injectYouTubeCustomUI() {
    try {
      // A. Hide Like and Dislike buttons across all YouTube variants
      const likeDislikeSelectors = [
        'ytm-segmented-like-dislike-button-renderer',
        'ytd-segmented-like-dislike-button-renderer',
        'segmented-like-dislike-button-view-model',
        '#segmented-like-dislike-button',
        '.yt-spec-segmented-like-dislike-button',
        'ytm-like-button-renderer',
        'ytm-dislike-button-renderer',
        'ytd-like-button-renderer',
        'ytd-dislike-button-renderer',
        'like-button-view-model',
        'dislike-button-view-model',
        'button[aria-label*="like this video" i]',
        'button[aria-label*="dislike this video" i]',
        'button[aria-label*="I like this" i]',
        'button[aria-label*="I dislike this" i]'
      ];

      const hideEls = document.querySelectorAll(likeDislikeSelectors.join(','));
      hideEls.forEach(el => {
        if (!el.id || !el.id.startsWith('__yt_')) {
          el.style.setProperty('display', 'none', 'important');
          el.style.setProperty('visibility', 'hidden', 'important');
        }
      });

      // B. Create or retrieve the Download Button
      let dlBtn = document.getElementById('__yt_video_action_download_btn__');
      if (!dlBtn) {
        dlBtn = document.createElement('button');
        dlBtn.id = '__yt_video_action_download_btn__';
        dlBtn.setAttribute('type', 'button');
        dlBtn.setAttribute('role', 'button');
        dlBtn.setAttribute('aria-label', 'Download Video');
        dlBtn.style.cssText = `
          display: inline-flex !important;
          align-items: center !important;
          justify-content: center !important;
          height: 36px !important;
          min-height: 36px !important;
          max-height: 36px !important;
          min-width: 110px !important;
          padding: 0 16px !important;
          margin: 0 6px 0 0 !important;
          background: #272727 !important;
          color: #ffffff !important;
          border-radius: 18px !important;
          border: 1px solid rgba(255, 255, 255, 0.25) !important;
          font-family: Roboto, Arial, sans-serif !important;
          font-size: 13px !important;
          font-weight: 600 !important;
          cursor: pointer !important;
          user-select: none !important;
          -webkit-tap-highlight-color: transparent !important;
          flex-shrink: 0 !important;
          box-sizing: border-box !important;
          line-height: 1 !important;
          z-index: 9999 !important;
          visibility: visible !important;
          opacity: 1 !important;
        `;
        const downloadIcon = createControlIcon(downloadIconPath, 18, '#ffffff');
        downloadIcon.style.marginRight = '6px';
        dlBtn.appendChild(downloadIcon);
        dlBtn.appendChild(createControlLabel(
          'Download',
          'color:#ffffff;font-size:13px;font-weight:600;pointer-events:none;white-space:nowrap;'
        ));
        dlBtn.addEventListener('click', (e) => {
          e.preventDefault();
          e.stopPropagation();
          try {
            if (window.DownloadsChannel) {
              window.DownloadsChannel.postMessage('download_active_video');
            }
          } catch(err) {}
        }, true);
      }

      // Ensure dlBtn is attached to the DOM at the Like/Dislike position
      let targetLikeContainer = document.querySelector(`
        segmented-like-dislike-button-view-model,
        ytm-segmented-like-dislike-button-renderer,
        ytd-segmented-like-dislike-button-renderer,
        #segmented-like-dislike-button,
        .yt-spec-segmented-like-dislike-button,
        like-button-view-model,
        ytm-like-button-renderer,
        ytd-like-button-renderer,
        button[aria-label*="like this video" i]
      `);

      let inserted = false;
      if (targetLikeContainer) {
        // Find outer segmented button container
        const segmented = targetLikeContainer.closest(`
          segmented-like-dislike-button-view-model,
          ytm-segmented-like-dislike-button-renderer,
          ytd-segmented-like-dislike-button-renderer,
          #segmented-like-dislike-button,
          .yt-spec-segmented-like-dislike-button
        `) || targetLikeContainer;

        const parent = segmented.parentElement;
        if (parent) {
          if (dlBtn.parentElement !== parent || dlBtn.nextSibling !== segmented) {
            parent.insertBefore(dlBtn, segmented);
          }
          inserted = true;
        }
      }

      if (!inserted) {
        // Fallback 1: Insert before Share button
        const shareBtn = document.querySelector(`
          share-button-view-model,
          ytm-share-button-renderer,
          ytd-share-button-renderer,
          button[aria-label*="share" i],
          button[aria-label*="Share" i]
        `);
        if (shareBtn) {
          const shareTarget = shareBtn.closest('yt-button-view-model, ytm-button-renderer, share-button-view-model') || shareBtn;
          if (shareTarget.parentElement) {
            if (dlBtn.parentElement !== shareTarget.parentElement || dlBtn.nextSibling !== shareTarget) {
              shareTarget.parentElement.insertBefore(dlBtn, shareTarget);
            }
            inserted = true;
          }
        }
      }

      if (!inserted) {
        // Fallback 2: Insert into action bar container
        const actionBar = document.querySelector(`
          ytm-slim-video-action-bar-renderer .slim-video-action-bar-actions,
          .slim-video-action-bar-actions,
          ytm-slim-video-action-bar-renderer,
          actions-view-model,
          yt-flexible-actions-view-model,
          #top-level-buttons-computed,
          ytd-watch-metadata #actions,
          ytd-menu-renderer #top-level-buttons-computed,
          #actions-inner,
          #actions
        `);
        if (actionBar) {
          if (actionBar.firstChild !== dlBtn) {
            actionBar.insertBefore(dlBtn, actionBar.firstChild);
          }
          inserted = true;
        }
      }

      if (!inserted && (window.location.href.includes('/watch') || document.querySelector('video'))) {
        // Fallback 3: Insert directly after video title / info section
        const infoSection = document.querySelector(`
          ytm-slim-video-information-renderer,
          ytm-video-description-header-renderer,
          .slim-video-metadata-title,
          #above-the-fold,
          #meta-contents,
          #title,
          h1.title
        `);
        if (infoSection && infoSection.parentElement) {
          if (dlBtn.parentElement !== infoSection.parentElement) {
            infoSection.insertAdjacentElement('afterend', dlBtn);
          }
          inserted = true;
        }
      }

      // Also inject PiP button right after Download button if on video page
      if (inserted && dlBtn.parentElement) {
        let pipBtn = document.getElementById('__yt_video_action_pip_btn__');
        if (!infinitySettings.pictureInPicture && pipBtn) {
          pipBtn.remove();
          pipBtn = null;
        }
        if (!pipBtn && infinitySettings.pictureInPicture) {
          pipBtn = document.createElement('button');
          pipBtn.id = '__yt_video_action_pip_btn__';
          pipBtn.setAttribute('type', 'button');
          pipBtn.setAttribute('role', 'button');
          pipBtn.setAttribute('aria-label', 'Picture in Picture');
          pipBtn.style.cssText = dlBtn.style.cssText;
          pipBtn.style.minWidth = '75px';
          const pipIcon = createControlIcon(pipIconPath, 18, '#3EA6FF');
          pipIcon.style.marginRight = '5px';
          pipBtn.appendChild(pipIcon);
          pipBtn.appendChild(createControlLabel(
            'PiP',
            'color:#ffffff;font-size:13px;font-weight:600;pointer-events:none;'
          ));
          pipBtn.addEventListener('click', (e) => {
            e.preventDefault();
            e.stopPropagation();
            try {
              if (window.DownloadsChannel) {
                window.DownloadsChannel.postMessage('pip');
              }
            } catch(err) {}
          }, true);
        }
        if (pipBtn && dlBtn.nextSibling !== pipBtn && dlBtn.parentElement) {
          dlBtn.parentElement.insertBefore(pipBtn, dlBtn.nextSibling);
        }

        let jumpBtn = document.getElementById('__yt_video_action_jump_btn__');
        if (!jumpBtn) {
          jumpBtn = document.createElement('button');
          jumpBtn.id = '__yt_video_action_jump_btn__';
          jumpBtn.type = 'button';
          jumpBtn.setAttribute('aria-label', 'Jump ahead 30 seconds');
          jumpBtn.style.cssText = dlBtn.style.cssText;
          jumpBtn.style.minWidth = '68px';
          jumpBtn.style.padding = '0 10px';
          jumpBtn.textContent = '+30s';
          jumpBtn.addEventListener('click', (e) => {
            e.preventDefault();
            e.stopPropagation();
            try {
              if (window.DownloadsChannel) {
                window.DownloadsChannel.postMessage('jump_ahead');
              }
            } catch(err) {}
          }, true);
        }
        if ((pipBtn ? pipBtn.nextSibling : dlBtn.nextSibling) !== jumpBtn && dlBtn.parentElement) {
          dlBtn.parentElement.insertBefore(jumpBtn, pipBtn ? pipBtn.nextSibling : dlBtn.nextSibling);
        }

        let queueBtn = document.getElementById('__yt_video_action_queue_btn__');
        if (!queueBtn) {
          queueBtn = document.createElement('button');
          queueBtn.id = '__yt_video_action_queue_btn__';
          queueBtn.type = 'button';
          queueBtn.setAttribute('aria-label', 'Open watch queue');
          queueBtn.style.cssText = dlBtn.style.cssText;
          queueBtn.style.minWidth = '72px';
          queueBtn.style.padding = '0 10px';
          queueBtn.textContent = 'Queue';
          queueBtn.addEventListener('click', (e) => {
            e.preventDefault();
            e.stopPropagation();
            try {
              if (window.DownloadsChannel) {
                window.DownloadsChannel.postMessage('open_queue');
              }
            } catch(err) {}
          }, true);
        }
        if (jumpBtn.nextSibling !== queueBtn && dlBtn.parentElement) {
          dlBtn.parentElement.insertBefore(queueBtn, jumpBtn.nextSibling);
        }
      }

      // C. Shorts Overlay Action Column (on the right)
      const shortsActions = document.querySelector(`
        .shorts-overlay-actions,
        ytm-shorts-action-bar-renderer,
        ytd-reel-player-overlay-renderer #actions,
        .reel-player-overlay-actions
      `);

      if (shortsActions) {
        let sDl = document.getElementById('__yt_shorts_action_download_btn__');
        if (!sDl) {
          sDl = document.createElement('div');
          sDl.id = '__yt_shorts_action_download_btn__';
          sDl.setAttribute('role', 'button');
          sDl.setAttribute('aria-label', 'Download Short');
          sDl.style.cssText = `
            display: flex !important;
            flex-direction: column !important;
            align-items: center !important;
            justify-content: center !important;
            margin-bottom: 12px !important;
            cursor: pointer !important;
            user-select: none !important;
            color: #ffffff !important;
            z-index: 9999 !important;
            visibility: visible !important;
            opacity: 1 !important;
          `;
          const shortsIconWrap = document.createElement('div');
          shortsIconWrap.style.cssText = 'width:44px;height:44px;background:rgba(30,30,30,0.85);border:1px solid rgba(255,255,255,0.3);border-radius:50%;display:flex;align-items:center;justify-content:center;backdrop-filter:blur(8px);';
          shortsIconWrap.appendChild(createControlIcon(downloadIconPath, 22, '#ffffff'));
          sDl.appendChild(shortsIconWrap);
          sDl.appendChild(createControlLabel(
            'Download',
            'color:#ffffff;font-size:10px;font-weight:600;margin-top:3px;font-family:Roboto,Arial,sans-serif;'
          ));
          sDl.addEventListener('click', (e) => {
            e.preventDefault();
            e.stopPropagation();
            try {
              if (window.DownloadsChannel) {
                window.DownloadsChannel.postMessage('download_active_video');
              }
            } catch(err) {}
          }, true);
        }

        const sLike = shortsActions.querySelector(`
          ytm-like-button-renderer,
          like-button-view-model,
          [aria-label*="like" i]
        `);
        if (sLike && sLike.parentElement === shortsActions) {
          if (shortsActions.firstChild !== sDl && sDl.nextSibling !== sLike) {
            shortsActions.insertBefore(sDl, sLike);
          }
        } else if (shortsActions.firstChild !== sDl) {
          shortsActions.insertBefore(sDl, shortsActions.firstChild);
        }
      }

      // D. YouTube Top Masthead / Header Bar: InfinityTube Premium Button
      const topbarEnd = document.querySelector('.mobile-topbar-header .topbar-icons') ||
                        document.querySelector('ytm-mobile-topbar-renderer .mobile-topbar-header') ||
                        document.querySelector('ytm-mobile-topbar-renderer') ||
                        document.querySelector('#masthead #end') ||
                        document.querySelector('ytd-masthead #end');

      if (topbarEnd) {
        let premBtn = document.getElementById('__yt_masthead_premium_btn__');
        if (!premBtn) {
          premBtn = document.createElement('div');
          premBtn.id = '__yt_masthead_premium_btn__';
          premBtn.style.cssText = `
            display: inline-flex !important;
            align-items: center !important;
            justify-content: center !important;
            height: 28px !important;
            padding: 0 10px !important;
            margin: 0 6px !important;
            background: linear-gradient(135deg, rgba(0, 112, 255, 0.25), rgba(255, 0, 119, 0.25)) !important;
            border: 1px solid rgba(255, 0, 119, 0.45) !important;
            border-radius: 14px !important;
            color: #ffffff !important;
            font-size: 11px !important;
            font-weight: 700 !important;
            cursor: pointer !important;
            user-select: none !important;
            -webkit-tap-highlight-color: transparent !important;
            z-index: 9999 !important;
            font-family: Roboto, Arial, sans-serif !important;
            letter-spacing: 0.2px !important;
            flex-shrink: 0 !important;
          `;
          const premiumIcon = createControlIcon(premiumIconPath, 15, '#ff0077');
          premiumIcon.style.marginRight = '4px';
          premBtn.appendChild(premiumIcon);
          premBtn.appendChild(createControlLabel(
            'Premium',
            'color:#ffffff;font-size:11px;font-weight:700;pointer-events:none;'
          ));
          premBtn.addEventListener('click', (e) => {
            e.preventDefault();
            e.stopPropagation();
            try {
              if (window.DownloadsChannel) {
                window.DownloadsChannel.postMessage('open_premium');
              }
            } catch(err) {}
          }, true);
        }

        if (topbarEnd.firstChild !== premBtn) {
          topbarEnd.insertBefore(premBtn, topbarEnd.firstChild);
        }
      }
    } catch(e) {}
  }

  setInterval(() => {
    unlockScroll();
    setupYouTubeNavBar();
    injectYouTubeCustomUI();
    setupPlayerMonitoring();
    setEnhanced1080pQuality();
  }, 750);

  // 14. Observe DOM additions
  try {
    let mutationRefreshTimer = null;
    const observer = new MutationObserver(() => {
      clearTimeout(mutationRefreshTimer);
      mutationRefreshTimer = setTimeout(() => {
        injectOledAndClutterRemovalStyles();
        installDoubleTapGestures();
        unlockScroll();
        setupYouTubeNavBar();
        injectYouTubeCustomUI();
        setupPlayerMonitoring();
        setEnhanced1080pQuality();
      }, 100);
    });

    observer.observe(document.documentElement || document.body, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['class']
    });
  } catch(e) {}

  window.addEventListener('yt-navigate-finish', () => {
    killVideoAds();
    injectOledAndClutterRemovalStyles();
    installDoubleTapGestures();
    unlockScroll();
    setupYouTubeNavBar();
    injectYouTubeCustomUI();
    setupPlayerMonitoring();
    setEnhanced1080pQuality();
  });
})();
''';
}
