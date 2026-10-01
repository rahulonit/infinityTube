import 'dart:io';
import 'package:flutter/material.dart';

import '../services/download_manager.dart';
import '../services/youtube_downloader_service.dart';
import 'downloads_screen.dart';
import 'video_player_screen.dart';

/// Modal bottom sheet displaying video details and all available quality options
/// (Video resolutions and Audio streams) with interactive download progress.
class DownloadBottomSheet extends StatefulWidget {
  const DownloadBottomSheet({
    super.key,
    required this.videoId,
    this.isShort = false,
    this.initialMetadata,
  });

  final String videoId;
  final bool isShort;
  final VideoDownloadMetadata? initialMetadata;

  static Future<void> show(
    BuildContext context, {
    required String videoId,
    bool isShort = false,
    VideoDownloadMetadata? initialMetadata,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DownloadBottomSheet(
        videoId: videoId,
        isShort: isShort,
        initialMetadata: initialMetadata,
      ),
    );
  }

  @override
  State<DownloadBottomSheet> createState() => _DownloadBottomSheetState();
}

class _DownloadBottomSheetState extends State<DownloadBottomSheet> {
  bool _isLoading = true;
  String? _errorMessage;
  VideoDownloadMetadata? _metadata;

  int _selectedTabIndex = 0; // 0: Video, 1: Audio

  // Download state tracking keyed by unique option.id
  String? _downloadingOptionId;
  double _downloadProgress = 0.0;
  String _downloadStatusText = '';
  final Map<String, File> _downloadedFiles = {};

  @override
  void initState() {
    super.initState();
    DownloadManager.instance.addListener(_onDownloadManagerChanged);
    if (widget.initialMetadata != null) {
      _metadata = widget.initialMetadata;
      _isLoading = false;
    } else {
      _loadVideoDetails();
    }
  }

  @override
  void dispose() {
    DownloadManager.instance.removeListener(_onDownloadManagerChanged);
    super.dispose();
  }

  void _onDownloadManagerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadVideoDetails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await YouTubeDownloaderService.fetchDownloadDetails(
        widget.videoId,
        isShort: widget.isShort,
      );
      if (!mounted) return;
      setState(() {
        _metadata = data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load video streams: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _startDownload(DownloadQualityOption option) async {
    if (_metadata == null) return;
    setState(() {
      _downloadingOptionId = option.id;
      _downloadProgress = 0.0;
      _downloadStatusText = 'Starting download...';
    });

    try {
      final task = await DownloadManager.instance.startDownload(
        videoId: _metadata!.id,
        title: _metadata!.title,
        author: _metadata!.author,
        durationText: _metadata!.durationText,
        thumbnailUrl: _metadata!.thumbnailUrl,
        qualityOption: option,
        isShort: _metadata!.isShort,
      );

      if (!mounted) return;
      setState(() {
        _downloadedFiles[option.id] = task.targetFile;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Downloading: ${_metadata!.title}',
            style: const TextStyle(fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF282828),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'View',
            textColor: const Color(0xFF3EA6FF),
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const DownloadsScreen(),
                ),
              );
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadingOptionId = null;
        _downloadStatusText = 'Download failed: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF161616),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Bar: Drag handle & Downloads Screen Shortcut
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  const SizedBox(width: 40),
                  const Spacer(),
                  // Drag handle
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Spacer(),
                  // Shortcut to Downloads Manager
                  IconButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const DownloadsScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.folder_open_rounded, color: Colors.white70, size: 20),
                    tooltip: 'All Downloads',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                  ),
                ],
              ),
            ),

            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF0000)),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Fetching available qualities...',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              )
            else if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _loadVideoDetails,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF3EA6FF),
                        foregroundColor: Colors.black,
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            else if (_metadata != null)
              Expanded(
                child: Column(
                  children: [
                    // Video Header Preview
                    _buildVideoHeader(_metadata!),

                    const Divider(color: Colors.white12, height: 1),

                    // Tabs: Video / Audio
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildTabButton(
                              index: 0,
                              label: 'Video (${_metadata!.videoOptions.length})',
                              icon: Icons.videocam_rounded,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildTabButton(
                              index: 1,
                              label: 'Audio Only (${_metadata!.audioOptions.length})',
                              icon: Icons.audiotrack_rounded,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Quality Options List
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        children: [
                          if (_selectedTabIndex == 0)
                            ..._metadata!.videoOptions.map((opt) => _buildOptionTile(opt))
                          else
                            ..._metadata!.audioOptions.map((opt) => _buildOptionTile(opt)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoHeader(VideoDownloadMetadata meta) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail with duration / short badge
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  meta.thumbnailUrl,
                  width: 120,
                  height: 68,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 120,
                    height: 68,
                    color: const Color(0xFF282828),
                    child: const Icon(Icons.play_circle_outline, color: Colors.white54),
                  ),
                ),
              ),
              Positioned(
                bottom: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    meta.durationText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          // Title & Channel
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (meta.isShort)
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF0000),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'SHORTS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                Text(
                  meta.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  meta.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required int index,
    required String label,
    required IconData icon,
  }) {
    final bool isSelected = _selectedTabIndex == index;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedTabIndex = index;
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF282828) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? Colors.white30 : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? const Color(0xFFFF0000) : Colors.white60,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white60,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile(DownloadQualityOption option) {
    final taskId = '${_metadata?.id}_${option.id}';
    final task = DownloadManager.instance.getTask(taskId);
    final bool isDownloading = task?.isDownloading ?? (_downloadingOptionId == option.id);
    final bool isPaused = task?.isPaused ?? false;
    final bool isDownloaded = (task?.isCompleted ?? false) ||
        _downloadedFiles.containsKey(option.id) ||
        (isDownloading && _downloadProgress >= 1.0);
    final double displayProgress = task != null ? task.progress : _downloadProgress;
    final String displayStatusText = task != null ? task.progressText : _downloadStatusText;
    final File? completedFile = task?.targetFile ?? _downloadedFiles[option.id];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDownloaded
              ? const Color(0xFF00E676).withValues(alpha: 0.5)
              : (isDownloading
                  ? const Color(0xFF3EA6FF)
                  : (isPaused
                      ? Colors.amber.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.06))),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Format chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: option.isAudioOnly
                      ? const Color(0xFF9C27B0).withValues(alpha: 0.2)
                      : (option.hasAudio
                          ? const Color(0xFF00E676).withValues(alpha: 0.2)
                          : const Color(0xFF29B6F6).withValues(alpha: 0.2)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  option.format,
                  style: TextStyle(
                    color: option.isAudioOnly
                        ? const Color(0xFFCE93D8)
                        : (option.hasAudio
                            ? const Color(0xFF00E676)
                            : const Color(0xFF81D4FA)),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Quality label
              Expanded(
                child: Text(
                  option.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Size text
              Text(
                option.sizeText,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(width: 12),

              // Action buttons (Downloaded / Downloading / Paused / Idle)
              if (isDownloaded) ...[
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF00E676),
                  size: 20,
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () {
                    final file = completedFile ?? _downloadedFiles[option.id];
                    if (file != null) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => OfflineVideoPlayerScreen(
                            item: DownloadedMediaItem(
                              file: file,
                              title: _metadata?.title ?? 'Downloaded Media',
                              quality: option.label,
                              format: option.format,
                              sizeBytes: file.existsSync()
                                  ? file.lengthSync()
                                  : option.totalBytes,
                              modified: DateTime.now(),
                            ),
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.play_arrow_rounded, size: 16),
                  label: const Text(
                    'Replay',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF00E676),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ] else if (isDownloading) ...[
                IconButton(
                  icon: const Icon(Icons.pause_circle_filled_rounded, color: Colors.amber, size: 24),
                  tooltip: 'Pause Download',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => DownloadManager.instance.pauseDownload(taskId),
                ),
              ] else if (isPaused) ...[
                IconButton(
                  icon: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF00E676), size: 24),
                  tooltip: 'Resume Download',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => DownloadManager.instance.resumeDownload(taskId),
                ),
              ] else
                IconButton(
                  onPressed: () => _startDownload(option),
                  icon: const Icon(Icons.download_rounded, color: Color(0xFF3EA6FF), size: 22),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Download',
                ),
            ],
          ),

          // Download Progress Bar
          if (isDownloading || isPaused) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: displayProgress > 0 ? displayProgress : null,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(
                isDownloaded
                    ? const Color(0xFF00E676)
                    : (isPaused ? Colors.amber : const Color(0xFF3EA6FF)),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              displayStatusText,
              style: TextStyle(
                color: isDownloaded
                    ? const Color(0xFF00E676)
                    : (isPaused ? Colors.amber : Colors.white70),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
