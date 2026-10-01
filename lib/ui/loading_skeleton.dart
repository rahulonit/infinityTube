import 'package:flutter/material.dart';

/// A sleek shimmer skeleton loading placeholder matching YouTube's dark theme.
///
/// Prevents harsh blank flashes while YouTube's web bundles and player initialize.
class YouTubeLoadingSkeleton extends StatefulWidget {
  const YouTubeLoadingSkeleton({super.key});

  @override
  State<YouTubeLoadingSkeleton> createState() => _YouTubeLoadingSkeletonState();
}

class _YouTubeLoadingSkeletonState extends State<YouTubeLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          color: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top filter chips mockup
              Row(
                children: [
                  _buildShimmerItem(width: 60, height: 32, radius: 16),
                  const SizedBox(width: 8),
                  _buildShimmerItem(width: 75, height: 32, radius: 16),
                  const SizedBox(width: 8),
                  _buildShimmerItem(width: 90, height: 32, radius: 16),
                ],
              ),
              const SizedBox(height: 16),

              // First video thumbnail skeleton
              Expanded(
                child: ListView(
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildVideoSkeleton(),
                    const SizedBox(height: 24),
                    _buildVideoSkeleton(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVideoSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 16:9 Thumbnail
        AspectRatio(aspectRatio: 16 / 9, child: _buildShimmerItem(radius: 12)),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Channel Avatar
            _buildShimmerItem(width: 36, height: 36, radius: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title Line 1
                  _buildShimmerItem(height: 14, radius: 4),
                  const SizedBox(height: 6),
                  // Title Line 2
                  _buildShimmerItem(width: 160, height: 14, radius: 4),
                  const SizedBox(height: 6),
                  // Subtitle (channel & views)
                  _buildShimmerItem(width: 100, height: 11, radius: 4),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildShimmerItem({
    double? width,
    double? height,
    required double radius,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment(-1.0 + (_controller.value * 2.5), -0.3),
          end: Alignment(0.5 + (_controller.value * 2.5), 0.3),
          colors: const [
            Color(0xFF141414),
            Color(0xFF262626),
            Color(0xFF141414),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}
