import 'dart:ui';
import 'package:flutter/material.dart';

/// A sleek frosted-glass floating control capsule for the YouTube WebView shell.
///
/// Features:
/// - Quick navigation: Home, Refresh, Back, Forward.
/// - Ad-Block Shield: Live counter badge showing blocked ads.
/// - Desktop / Mobile Mode Toggle: Manual override between mobile & desktop experiences.
/// - Expandable & Collapsible: Tap to collapse into an unobtrusive mini-pill.
class FloatingControlPill extends StatefulWidget {
  const FloatingControlPill({
    super.key,
    required this.isDesktopMode,
    required this.adsBlockedCount,
    required this.canGoBack,
    required this.canGoForward,
    required this.hasActiveVideo,
    required this.onHomePressed,
    required this.onRefreshPressed,
    required this.onBackPressed,
    required this.onForwardPressed,
    required this.onToggleModePressed,
    required this.onShieldPressed,
    required this.onDownloadPressed,
    this.onPiPPressed,
    this.onJumpAheadPressed,
    this.onQueuePressed,
    this.onMusicPressed,
    this.queueCount = 0,
  });

  final bool isDesktopMode;
  final int adsBlockedCount;
  final bool canGoBack;
  final bool canGoForward;
  final bool hasActiveVideo;
  final int queueCount;

  final VoidCallback onHomePressed;
  final VoidCallback onRefreshPressed;
  final VoidCallback onBackPressed;
  final VoidCallback onForwardPressed;
  final VoidCallback onToggleModePressed;
  final VoidCallback onShieldPressed;
  final VoidCallback onDownloadPressed;
  final VoidCallback? onPiPPressed;
  final VoidCallback? onJumpAheadPressed;
  final VoidCallback? onQueuePressed;
  final VoidCallback? onMusicPressed;

  @override
  State<FloatingControlPill> createState() => _FloatingControlPillState();
}

class _FloatingControlPillState extends State<FloatingControlPill> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(28),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF141414).withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1,
              ),
            ),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. Ad-Block Shield with live counter badge
                  InkWell(
                    onTap: widget.onShieldPressed,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.shield_rounded,
                            size: 18,
                            color: Color(0xFF00E676),
                          ),
                          if (widget.adsBlockedCount > 0) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00E676).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${widget.adsBlockedCount}',
                                style: const TextStyle(
                                  color: Color(0xFF00E676),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  if (_isExpanded) ...[
                    _buildDivider(),

                    // 2. Back button
                    _buildIconButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      tooltip: 'Back',
                      onPressed: widget.canGoBack ? widget.onBackPressed : null,
                    ),

                    // 3. Forward button
                    _buildIconButton(
                      icon: Icons.arrow_forward_ios_rounded,
                      tooltip: 'Forward',
                      onPressed: widget.canGoForward ? widget.onForwardPressed : null,
                    ),

                    // 4. Home button
                    _buildIconButton(
                      icon: Icons.home_rounded,
                      tooltip: 'Home',
                      onPressed: widget.onHomePressed,
                    ),

                    // 5. Reload button
                    _buildIconButton(
                      icon: Icons.refresh_rounded,
                      tooltip: 'Refresh',
                      onPressed: widget.onRefreshPressed,
                    ),

                    // 6. Download Video / Short button
                    _buildIconButton(
                      icon: Icons.download_rounded,
                      tooltip: widget.hasActiveVideo
                          ? 'Download Active Video / Short'
                          : 'Open Video / Short to Download',
                      color: widget.hasActiveVideo
                          ? const Color(0xFF00E676)
                          : Colors.white54,
                      onPressed: widget.onDownloadPressed,
                    ),

                    if (widget.hasActiveVideo) ...[
                      // PiP button
                      if (widget.onPiPPressed != null)
                        _buildIconButton(
                          icon: Icons.picture_in_picture_alt_rounded,
                          tooltip: 'Picture in Picture',
                          onPressed: widget.onPiPPressed,
                          color: const Color(0xFF3EA6FF),
                        ),

                      // Jump Ahead button
                      if (widget.onJumpAheadPressed != null)
                        _buildIconButton(
                          icon: Icons.fast_forward_rounded,
                          tooltip: 'Jump Ahead (+30s)',
                          onPressed: widget.onJumpAheadPressed,
                          color: Colors.amber,
                        ),
                    ],

                    // YouTube Music toggle
                    if (widget.onMusicPressed != null)
                      _buildIconButton(
                        icon: Icons.music_note_rounded,
                        tooltip: 'YouTube Music Mode',
                        onPressed: widget.onMusicPressed,
                        color: const Color(0xFFFF0000),
                      ),

                    // Queue button with count badge
                    if (widget.onQueuePressed != null)
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          _buildIconButton(
                            icon: Icons.queue_music_rounded,
                            tooltip: 'Watch Queue',
                            onPressed: widget.onQueuePressed,
                            color: Colors.white,
                          ),
                          if (widget.queueCount > 0)
                            Positioned(
                              top: 2,
                              right: 2,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFF0000),
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '${widget.queueCount}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),

                    _buildDivider(),

                    // 7. Mobile / Desktop Experience Toggle
                    _buildIconButton(
                      icon: widget.isDesktopMode
                          ? Icons.desktop_windows_rounded
                          : Icons.smartphone_rounded,
                      tooltip: widget.isDesktopMode
                          ? 'Desktop Mode (Tap for Mobile)'
                          : 'Mobile Mode (Tap for Desktop)',
                      color: widget.isDesktopMode
                          ? const Color(0xFF3EA6FF)
                          : const Color(0xFFFF5252),
                      onPressed: widget.onToggleModePressed,
                    ),
                  ],

                  // 7. Collapse / Expand toggle chevron
                  InkWell(
                    onTap: () {
                      setState(() {
                        _isExpanded = !_isExpanded;
                      });
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                      child: Icon(
                        _isExpanded
                            ? Icons.chevron_left_rounded
                            : Icons.chevron_right_rounded,
                        size: 18,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    Color? color,
  }) {
    final bool isEnabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Icon(
            icon,
            size: 19,
            color: isEnabled
                ? (color ?? Colors.white)
                : Colors.white.withValues(alpha: 0.25),
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.white.withValues(alpha: 0.15),
    );
  }
}
