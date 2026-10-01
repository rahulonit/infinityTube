import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../services/youtube_downloader_service.dart';

/// Full-featured offline media player for downloaded videos and audio files.
class OfflineVideoPlayerScreen extends StatefulWidget {
  const OfflineVideoPlayerScreen({super.key, required this.item});

  final DownloadedMediaItem item;

  @override
  State<OfflineVideoPlayerScreen> createState() =>
      _OfflineVideoPlayerScreenState();
}

class _OfflineVideoPlayerScreenState extends State<OfflineVideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  String? _errorMessage;

  bool _showControls = true;
  Timer? _hideControlsTimer;
  Timer? _seekFeedbackTimer;
  double _playbackSpeed = 1.0;
  String? _seekFeedback;
  Alignment _seekFeedbackAlignment = Alignment.center;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      final previousController = _controller;
      if (previousController != null) {
        previousController.removeListener(_onPlayerStateChanged);
        await previousController.dispose();
        _controller = null;
      }
      final file = widget.item.file;
      if (!await file.exists() || await file.length() == 0) {
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage = 'File is missing or incomplete on device storage.';
          });
        }
        return;
      }

      _controller = VideoPlayerController.file(file);
      await _controller!.initialize();
      _controller!.addListener(_onPlayerStateChanged);

      if (_controller!.value.hasError) {
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage =
                _controller!.value.errorDescription ??
                'Codec error: Unable to decode file.';
          });
        }
        return;
      }

      await _controller!.play();

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        _startHideControlsTimer();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Unable to play this media file ($e).';
        });
      }
    }
  }

  void _onPlayerStateChanged() {
    if (!mounted) return;
    if (_controller?.value.hasError == true && !_hasError) {
      setState(() {
        _hasError = true;
        _errorMessage =
            _controller?.value.errorDescription ??
            'Playback error encountered.';
      });
    } else {
      setState(() {});
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideControlsTimer();
    }
  }

  void _togglePlayPause() {
    if (_controller == null || !_isInitialized) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
      setState(() {
        _showControls = true;
      });
      _hideControlsTimer?.cancel();
    } else {
      if (_controller!.value.position >= _controller!.value.duration) {
        _controller!.seekTo(Duration.zero);
      }
      _controller!.play();
      _startHideControlsTimer();
    }
  }

  void _seekRelative(int seconds) {
    if (_controller == null || !_isInitialized) return;
    final current = _controller!.value.position;
    final target = current + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > _controller!.value.duration
              ? _controller!.value.duration
              : target);
    _controller!.seekTo(clamped);
    _seekFeedbackTimer?.cancel();
    setState(() {
      _seekFeedback = seconds < 0 ? '−10s' : '+10s';
      _seekFeedbackAlignment = seconds < 0
          ? const Alignment(-0.62, 0)
          : const Alignment(0.62, 0);
    });
    _seekFeedbackTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _seekFeedback = null);
    });
    _startHideControlsTimer();
  }

  void _cyclePlaybackSpeed() {
    const speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
    final currentIndex = speeds.indexOf(_playbackSpeed);
    final nextSpeed = speeds[(currentIndex + 1) % speeds.length];
    setState(() {
      _playbackSpeed = nextSpeed;
    });
    _controller?.setPlaybackSpeed(nextSpeed);
    _startHideControlsTimer();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    final secondsStr = seconds.toString().padLeft(2, '0');
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final remainingMins = minutes % 60;
      final remainingMinsStr = remainingMins.toString().padLeft(2, '0');
      return '$hours:$remainingMinsStr:$secondsStr';
    }
    return '$minutes:$secondsStr';
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _seekFeedbackTimer?.cancel();
    _controller?.removeListener(_onPlayerStateChanged);
    _controller?.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAudioOnly =
        widget.item.isAudioOnly ||
        widget.item.format == 'MP3' ||
        widget.item.format == 'M4A' ||
        widget.item.quality.toLowerCase().contains('audio') ||
        (_isInitialized &&
            _controller != null &&
            _controller!.value.size == Size.zero);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 1. Video or Audio Surface
              if (_hasError)
                _buildErrorView()
              else if (!_isInitialized)
                const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFFFF0000),
                    ),
                  ),
                )
              else if (isAudioOnly)
                _buildAudioVisualizer()
              else
                Center(
                  child: AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio > 0
                        ? _controller!.value.aspectRatio
                        : 16 / 9,
                    child: VideoPlayer(_controller!),
                  ),
                ),

              // 2. Gesture Detector for Overlay Taps and Double-Tap Skips
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleControls,
                onDoubleTapDown: (details) {
                  final screenWidth = MediaQuery.of(context).size.width;
                  if (details.globalPosition.dx < screenWidth * 0.4) {
                    _seekRelative(-10);
                  } else if (details.globalPosition.dx > screenWidth * 0.6) {
                    _seekRelative(10);
                  }
                },
                child: const SizedBox.expand(),
              ),

              if (_seekFeedback != null)
                Align(
                  alignment: _seekFeedbackAlignment,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Text(
                        _seekFeedback!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),

              // 3. Top Controls Bar
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black87,
                            Colors.black45,
                            Colors.transparent,
                          ],
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.arrow_back_rounded,
                              color: Colors.white,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.item.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFF0000)
                                            .withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        widget.item.quality,
                                        style: const TextStyle(
                                          color: Color(0xFFFF4D4D),
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      widget.item.sizeText,
                                      style: TextStyle(
                                        color: Colors.grey.shade400,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: _cyclePlaybackSpeed,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                            child: Text(
                              '${_playbackSpeed}x',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 4. Center Play/Pause & Skip Buttons
              AnimatedOpacity(
                opacity: _showControls && _isInitialized ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: IgnorePointer(
                  ignoring: !_showControls || !_isInitialized,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // -10s
                      IconButton(
                        iconSize: 42,
                        icon: const Icon(
                          Icons.replay_10_rounded,
                          color: Colors.white,
                        ),
                        onPressed: () => _seekRelative(-10),
                      ),
                      const SizedBox(width: 36),

                      // Play/Pause / Replay
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF0000).withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF0000)
                                  .withValues(alpha: 0.35),
                              blurRadius: 18,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: IconButton(
                          iconSize: 34,
                          icon: Icon(
                            _controller?.value.isPlaying == true
                                ? Icons.pause_rounded
                                : (_controller != null &&
                                          _controller!.value.position >=
                                              _controller!.value.duration
                                      ? Icons.replay_rounded
                                      : Icons.play_arrow_rounded),
                            color: Colors.white,
                          ),
                          onPressed: _togglePlayPause,
                        ),
                      ),
                      const SizedBox(width: 36),

                      // +10s
                      IconButton(
                        iconSize: 42,
                        icon: const Icon(
                          Icons.forward_10_rounded,
                          color: Colors.white,
                        ),
                        onPressed: () => _seekRelative(10),
                      ),
                    ],
                  ),
                ),
              ),

              // 5. Bottom Progress Slider & Duration Bar
              AnimatedOpacity(
                opacity: _showControls && _isInitialized ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: IgnorePointer(
                  ignoring: !_showControls || !_isInitialized,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black87,
                            Colors.black45,
                            Colors.transparent,
                          ],
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: const Color(0xFFFF0000),
                              inactiveTrackColor: Colors.white24,
                              thumbColor: const Color(0xFFFF0000),
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6,
                              ),
                              overlayColor: const Color(0xFFFF0000)
                                  .withValues(alpha: 0.2),
                              trackHeight: 3.5,
                            ),
                            child: Slider(
                              value:
                                  _controller != null &&
                                      _controller!
                                              .value
                                              .duration
                                              .inMilliseconds >
                                          0
                                  ? (_controller!
                                                .value
                                                .position
                                                .inMilliseconds /
                                            _controller!
                                                .value
                                                .duration
                                                .inMilliseconds)
                                        .clamp(0.0, 1.0)
                                  : 0.0,
                              onChanged: (value) {
                                if (_controller != null) {
                                  final duration = _controller!
                                      .value
                                      .duration
                                      .inMilliseconds;
                                  final seekMs = (value * duration).round();
                                  _controller!.seekTo(
                                    Duration(milliseconds: seekMs),
                                  );
                                }
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _controller != null
                                      ? _formatDuration(
                                          _controller!.value.position,
                                        )
                                      : '00:00',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  _controller != null
                                      ? _formatDuration(
                                          _controller!.value.duration,
                                        )
                                      : '00:00',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAudioVisualizer() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFF1F1F1F),
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFFF0000).withValues(alpha: 0.6),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF0000).withValues(alpha: 0.3),
                  blurRadius: 28,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: const Center(
              child: Icon(
                Icons.music_note_rounded,
                color: Color(0xFFFF0000),
                size: 56,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            widget.item.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Offline Audio Track • ${widget.item.quality}',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.redAccent,
              size: 48,
            ),
            const SizedBox(height: 16),
            const Text(
              'Playback Error',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Unable to play this video.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                setState(() {
                  _hasError = false;
                  _isInitialized = false;
                });
                _initializePlayer();
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF0000),
              ),
              child: const Text('Retry Playback'),
            ),
          ],
        ),
      ),
    );
  }
}
