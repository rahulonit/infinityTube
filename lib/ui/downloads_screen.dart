import 'package:flutter/material.dart';
import '../services/download_manager.dart';
import '../services/smart_downloads_service.dart';
import '../services/youtube_downloader_service.dart';
import 'video_player_screen.dart';

/// Screen to view, manage, and delete all downloaded videos and YouTube Shorts.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({
    super.key,
    this.initialItems,
  });

  /// Optional initial items for testing or preloaded cache.
  final List<DownloadedMediaItem>? initialItems;

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  List<DownloadedMediaItem> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    DownloadManager.instance.addListener(_onDownloadManagerUpdated);
    if (widget.initialItems != null) {
      _items = widget.initialItems!;
      _isLoading = false;
    } else {
      _loadDownloadedFiles();
    }
  }

  @override
  void dispose() {
    DownloadManager.instance.removeListener(_onDownloadManagerUpdated);
    super.dispose();
  }

  void _onDownloadManagerUpdated() {
    if (!mounted) return;
    setState(() {});
    // Auto-reload completed files when a download completes (only if not using mock initialItems)
    if (widget.initialItems == null) {
      final currentCount = _items.length;
      YouTubeDownloaderService.getDownloadedFiles().then((freshFiles) {
        if (mounted && freshFiles.length != currentCount) {
          setState(() {
            _items = freshFiles;
          });
        }
      });
    }
  }

  void _playVideo(DownloadedMediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => OfflineVideoPlayerScreen(item: item),
      ),
    );
  }

  Future<void> _loadDownloadedFiles() async {
    setState(() {
      _isLoading = true;
    });
    final files = await YouTubeDownloaderService.getDownloadedFiles();
    if (!mounted) return;
    setState(() {
      _items = files;
      _isLoading = false;
    });
  }

  int get _totalSizeBytes {
    return _items.fold<int>(0, (sum, item) => sum + item.sizeBytes);
  }

  Future<void> _deleteItem(DownloadedMediaItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F1F1F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Download?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete "${item.title}"?\nThis cannot be undone.',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF0000),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await YouTubeDownloaderService.deleteDownloadedFile(item.file);
      await _loadDownloadedFiles();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted "${item.title}"'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF282828),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _deleteAllItems() async {
    if (_items.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F1F1F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Clear All Downloads?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete all ${_items.length} downloaded files?\nThis will free ${YouTubeDownloaderService.formatBytes(_totalSizeBytes)}.',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF0000),
            ),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await YouTubeDownloaderService.deleteAllDownloadedFiles();
      await _loadDownloadedFiles();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All downloaded files cleared.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF282828),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showFileInfo(DownloadedMediaItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF0000).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.video_file_rounded,
                        color: Color(0xFFFF0000),
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        item.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildInfoRow('Quality & Format', '${item.quality} • ${item.format}'),
                const SizedBox(height: 10),
                _buildInfoRow('File Size', item.sizeText),
                const SizedBox(height: 10),
                _buildInfoRow('Storage Path', item.file.path),
                const SizedBox(height: 10),
                _buildInfoRow('Date Added', _formatDate(item.modified)),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _playVideo(item);
                        },
                        icon: const Icon(Icons.play_arrow_rounded, size: 22),
                        label: const Text('Play Video'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFF0000),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton.filledTonal(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _deleteItem(item);
                      },
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.white70),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white12,
                        padding: const EdgeInsets.all(14),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');
      return 'Today at $hour:$minute';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    }
    return '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _showSmartDownloadsDialog() async {
    final smart = SmartDownloadsService.instance;
    bool enabled = smart.isEnabled;
    int maxDownloads = smart.maxAutoDownloads;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E676).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF00E676), size: 24),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Smart Downloads',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Auto-save recommended videos for offline viewing',
                                style: TextStyle(color: Colors.white60, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Enable Smart Downloads',
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Automatically download videos in the background',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      activeThumbColor: const Color(0xFF00E676),
                      value: enabled,
                      onChanged: (val) {
                        setModalState(() {
                          enabled = val;
                        });
                        smart.setEnabled(val);
                        setState(() {});
                      },
                    ),
                    const Divider(color: Colors.white12, height: 24),
                    const Text(
                      'Maximum Auto-Downloads',
                      style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [3, 5, 10, 20].map((count) {
                        final isSelected = maxDownloads == count;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text('$count videos'),
                            selected: isSelected,
                            selectedColor: const Color(0xFF00E676),
                            backgroundColor: const Color(0xFF2C2C2C),
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.black : Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                            onSelected: enabled
                                ? (val) {
                                    if (val) {
                                      setModalState(() {
                                        maxDownloads = count;
                                      });
                                      smart.setMaxAutoDownloads(count);
                                      setState(() {});
                                    }
                                  }
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Downloads',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 19,
              ),
            ),
            if (!_isLoading && _items.isNotEmpty)
              Text(
                '${_items.length} ${_items.length == 1 ? "video" : "videos"} • ${YouTubeDownloaderService.formatBytes(_totalSizeBytes)}',
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 12,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.auto_awesome_rounded,
              color: SmartDownloadsService.instance.isEnabled
                  ? const Color(0xFF00E676)
                  : Colors.white60,
            ),
            tooltip: 'Smart Downloads Settings',
            onPressed: _showSmartDownloadsDialog,
          ),
          if (!_isLoading && _items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white70),
              tooltip: 'Clear All Downloads',
              onPressed: _deleteAllItems,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF0000)),
              ),
            )
          : (DownloadManager.instance.inProgressTasks.isEmpty && _items.isEmpty)
              ? _buildEmptyState()
              : RefreshIndicator(
                  color: const Color(0xFFFF0000),
                  backgroundColor: const Color(0xFF1E1E1E),
                  onRefresh: _loadDownloadedFiles,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    children: [
                      // In-progress downloads section
                      if (DownloadManager.instance.inProgressTasks.isNotEmpty) ...[
                        Row(
                          children: [
                            const Icon(Icons.downloading_rounded, color: Color(0xFF3EA6FF), size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'In Progress (${DownloadManager.instance.inProgressTasks.length})',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...DownloadManager.instance.inProgressTasks.map(_buildInProgressTaskCard),
                        if (_items.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Divider(color: Colors.white12, height: 1),
                          const SizedBox(height: 16),
                        ],
                      ],

                      // Completed downloads section
                      if (_items.isNotEmpty) ...[
                        if (DownloadManager.instance.inProgressTasks.isNotEmpty)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Completed Downloads',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ..._items.asMap().entries.map((entry) {
                          final index = entry.key;
                          final item = entry.value;
                          return Column(
                            children: [
                              _buildDownloadItemTile(item),
                              if (index < _items.length - 1)
                                const Divider(color: Colors.white10, height: 20),
                            ],
                          );
                        }),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildInProgressTaskCard(DownloadTask task) {
    final isPaused = task.isPaused;
    final isFailed = task.isFailed;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPaused
              ? Colors.amber.withValues(alpha: 0.4)
              : (isFailed
                  ? const Color(0xFFFF0000).withValues(alpha: 0.4)
                  : const Color(0xFF3EA6FF).withValues(alpha: 0.4)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 80,
                  height: 48,
                  child: task.thumbnailUrl.isNotEmpty
                      ? Image.network(
                          task.thumbnailUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            color: const Color(0xFF282828),
                            child: const Icon(Icons.movie_outlined, color: Colors.white54),
                          ),
                        )
                      : Container(
                          color: const Color(0xFF282828),
                          child: const Icon(Icons.movie_outlined, color: Colors.white54),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              // Title & Quality badge
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E676).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            task.format,
                            style: const TextStyle(
                              color: Color(0xFF00E676),
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            task.qualityLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Action buttons (Pause / Resume / Cancel)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (task.isDownloading)
                    IconButton(
                      icon: const Icon(Icons.pause_circle_filled_rounded, color: Colors.amber, size: 28),
                      tooltip: 'Pause Download',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => DownloadManager.instance.pauseDownload(task.id),
                    )
                  else if (task.isPaused || task.isFailed)
                    IconButton(
                      icon: Icon(
                        task.isFailed ? Icons.refresh_rounded : Icons.play_circle_fill_rounded,
                        color: task.isFailed ? const Color(0xFF3EA6FF) : const Color(0xFF00E676),
                        size: 28,
                      ),
                      tooltip: task.isFailed ? 'Retry' : 'Resume Download',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => DownloadManager.instance.resumeDownload(task.id),
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                    tooltip: 'Cancel Download',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => DownloadManager.instance.cancelDownload(task.id),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: task.progress > 0 ? task.progress : null,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(
                isPaused
                    ? Colors.amber
                    : (isFailed ? const Color(0xFFFF0000) : const Color(0xFF3EA6FF)),
              ),
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 6),
          // Progress text / status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isFailed
                    ? (task.errorMessage ?? 'Download failed. Tap retry.')
                    : (isPaused ? 'Paused' : 'Downloading...'),
                style: TextStyle(
                  color: isFailed
                      ? const Color(0xFFFF4D4D)
                      : (isPaused ? Colors.amber : const Color(0xFF3EA6FF)),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                task.progressText,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF0000).withValues(alpha: 0.15),
                    blurRadius: 24,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.download_done_rounded,
                  color: Color(0xFFFF0000),
                  size: 44,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Downloads Yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Videos and YouTube Shorts you download will appear here for offline playback and management.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.play_circle_outline_rounded, size: 20),
              label: const Text('Browse YouTube'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF0000),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadItemTile(DownloadedMediaItem item) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _playVideo(item),
      onLongPress: () => _showFileInfo(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Thumbnail / Icon Badge with Play Overlay
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    item.format == 'MP3' || item.format == 'M4A'
                        ? Icons.music_note_rounded
                        : Icons.movie_outlined,
                    color: const Color(0xFFFF0000).withValues(alpha: 0.6),
                    size: 26,
                  ),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        item.format,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),

            // Video Title & Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF0000).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.quality,
                          style: const TextStyle(
                            color: Color(0xFFFF4D4D),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        item.sizeText,
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '•',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      ),
                      Text(
                        _formatDate(item.modified),
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Play & Options
            IconButton(
              icon: const Icon(Icons.play_circle_fill_rounded,
                  color: Color(0xFFFF0000), size: 34),
              tooltip: 'Replay Video',
              onPressed: () => _playVideo(item),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded,
                  color: Colors.white60, size: 20),
              color: const Color(0xFF242424),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              onSelected: (val) {
                if (val == 'play') {
                  _playVideo(item);
                } else if (val == 'info') {
                  _showFileInfo(item);
                } else if (val == 'delete') {
                  _deleteItem(item);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'play',
                  child: Row(
                    children: [
                      Icon(Icons.play_arrow_rounded, color: Colors.white70, size: 20),
                      SizedBox(width: 10),
                      Text('Play Video', style: TextStyle(color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'info',
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: Colors.white70, size: 20),
                      SizedBox(width: 10),
                      Text('File Details', style: TextStyle(color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                      SizedBox(width: 10),
                      Text('Delete', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
