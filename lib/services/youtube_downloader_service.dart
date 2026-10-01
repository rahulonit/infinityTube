import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Represents a downloadable quality option for a video or audio stream.
class DownloadQualityOption {
  final String id;
  final String label;
  final String format;
  final String sizeText;
  final int totalBytes;
  final bool hasAudio;
  final bool isAudioOnly;
  final StreamInfo streamInfo;

  const DownloadQualityOption({
    required this.id,
    required this.label,
    required this.format,
    required this.sizeText,
    required this.totalBytes,
    required this.hasAudio,
    required this.isAudioOnly,
    required this.streamInfo,
  });
}

/// Metadata and all available qualities for an active YouTube video or Short.
class VideoDownloadMetadata {
  final String id;
  final String title;
  final String author;
  final String durationText;
  final String thumbnailUrl;
  final bool isShort;
  final List<DownloadQualityOption> videoOptions;
  final List<DownloadQualityOption> audioOptions;

  const VideoDownloadMetadata({
    required this.id,
    required this.title,
    required this.author,
    required this.durationText,
    required this.thumbnailUrl,
    required this.isShort,
    required this.videoOptions,
    required this.audioOptions,
  });
}

/// Service for extracting video/short IDs, retrieving stream manifests,
/// and downloading media files with live progress.
class YouTubeDownloaderService {
  /// Extracts the YouTube Video ID or Short ID from any URL.
  static String? extractVideoId(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return null;

    // 1. YouTube watch query: ?v=VIDEO_ID
    if (uri.queryParameters.containsKey('v')) {
      final v = uri.queryParameters['v'];
      if (v != null && v.isNotEmpty) return v;
    }

    // 2. YouTube Shorts: /shorts/SHORT_ID
    final shortsMatch = RegExp(r'/shorts/([a-zA-Z0-9_-]+)').firstMatch(uri.path);
    if (shortsMatch != null) {
      return shortsMatch.group(1);
    }

    // 3. Shortened URL: youtu.be/VIDEO_ID
    if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.first;
    }

    // 4. Embeds & Live streams: /embed/VIDEO_ID or /live/VIDEO_ID
    final embedMatch = RegExp(r'/(?:embed|live|v)/([a-zA-Z0-9_-]+)').firstMatch(uri.path);
    if (embedMatch != null) {
      return embedMatch.group(1);
    }

    return null;
  }

  /// Determines if a URL represents a YouTube Short.
  static bool isShortsUrl(String? url) {
    if (url == null) return false;
    return url.contains('/shorts/');
  }

  /// Fetches video details and all available video/audio streams for the given [videoId].
  static Future<VideoDownloadMetadata> fetchDownloadDetails(
    String videoId, {
    bool isShort = false,
  }) async {
    final yt = YoutubeExplode();
    try {
      final video = await yt.videos.get(videoId);
      final manifest = await yt.videos.streamsClient.getManifest(videoId);

      final List<DownloadQualityOption> videoOptions = [];
      final List<DownloadQualityOption> audioOptions = [];

      // 1. Collect all MUXED streams (Video + Audio combined in MP4 - fully playable on all devices)
      final Map<String, VideoStreamInfo> muxedStreams = {};
      for (final stream in manifest.muxed) {
        final key = stream.qualityLabel;
        final isMp4 = stream.container.name.toLowerCase() == 'mp4';
        if (!muxedStreams.containsKey(key)) {
          muxedStreams[key] = stream;
        } else if (isMp4 && muxedStreams[key]!.container.name.toLowerCase() != 'mp4') {
          muxedStreams[key] = stream;
        } else if (stream.bitrate.bitsPerSecond > muxedStreams[key]!.bitrate.bitsPerSecond) {
          muxedStreams[key] = stream;
        }
      }

      // Add all Muxed streams first (guaranteed to have both video + audio in MP4)
      for (final stream in muxedStreams.values) {
        final totalBytes = stream.size.totalBytes;
        final sizeText = _formatBytes(totalBytes);
        final containerName = stream.container.name.toUpperCase();
        final label = '${stream.qualityLabel} $containerName (Video + Audio)';

        videoOptions.add(
          DownloadQualityOption(
            id: 'muxed_${stream.tag}_${stream.container.name}_$totalBytes',
            label: label,
            format: containerName,
            sizeText: sizeText,
            totalBytes: totalBytes,
            hasAudio: true,
            isAudioOnly: false,
            streamInfo: stream,
          ),
        );
      }

      // 2. For resolutions higher than available in muxed (e.g. 1080p, 1440p, 4K),
      // add video-only streams prioritizing MP4 (H.264) for maximum offline device compatibility
      final Map<String, VideoStreamInfo> videoOnlyStreams = {};
      for (final stream in manifest.videoOnly) {
        if (muxedStreams.containsKey(stream.qualityLabel)) continue;

        final key = stream.qualityLabel;
        final isMp4 = stream.container.name.toLowerCase() == 'mp4';
        if (!videoOnlyStreams.containsKey(key)) {
          videoOnlyStreams[key] = stream;
        } else if (isMp4 && videoOnlyStreams[key]!.container.name.toLowerCase() != 'mp4') {
          videoOnlyStreams[key] = stream;
        } else if (stream.container.name == videoOnlyStreams[key]!.container.name &&
            stream.bitrate.bitsPerSecond > videoOnlyStreams[key]!.bitrate.bitsPerSecond) {
          videoOnlyStreams[key] = stream;
        }
      }

      for (final stream in videoOnlyStreams.values) {
        final totalBytes = stream.size.totalBytes;
        final sizeText = _formatBytes(totalBytes);
        final containerName = stream.container.name.toUpperCase();
        final isEnhanced1080p = stream.qualityLabel.contains('1080p');
        final label = isEnhanced1080p
            ? '${stream.qualityLabel} $containerName (Enhanced 1080p)'
            : '${stream.qualityLabel} $containerName (Video Only)';

        videoOptions.add(
          DownloadQualityOption(
            id: 'video_${stream.tag}_${stream.container.name}_$totalBytes',
            label: label,
            format: containerName,
            sizeText: sizeText,
            totalBytes: totalBytes,
            hasAudio: false,
            isAudioOnly: false,
            streamInfo: stream,
          ),
        );
      }

      // Prioritize all MP4 video formats first, sorted by totalBytes descending
      videoOptions.sort((a, b) {
        final aIsMp4 = a.format == 'MP4';
        final bIsMp4 = b.format == 'MP4';
        if (aIsMp4 && !bIsMp4) return -1;
        if (!aIsMp4 && bIsMp4) return 1;
        return b.totalBytes.compareTo(a.totalBytes);
      });

      // 3. Group and deduplicate audio streams by container & bitrate
      final Map<String, AudioStreamInfo> uniqueAudioStreams = {};
      for (final stream in manifest.audioOnly) {
        final kbps = (stream.bitrate.kiloBitsPerSecond).round();
        final key = '${stream.container.name.toUpperCase()}_$kbps';
        if (!uniqueAudioStreams.containsKey(key)) {
          uniqueAudioStreams[key] = stream;
        }
      }

      for (final stream in uniqueAudioStreams.values) {
        final totalBytes = stream.size.totalBytes;
        final sizeText = _formatBytes(totalBytes);
        final kbps = (stream.bitrate.kiloBitsPerSecond).round();
        final isM4a = stream.container.name.toLowerCase() == 'mp4';
        final formatName = isM4a ? 'M4A (MP4)' : stream.container.name.toUpperCase();
        final isHighQuality = kbps >= 256 || kbps >= 160;
        final label = isHighQuality
            ? '$kbps kbps High-Quality Audio'
            : (isM4a ? '$kbps kbps MP4 Audio' : '$kbps kbps Audio');

        audioOptions.add(
          DownloadQualityOption(
            id: 'audio_${stream.tag}_${stream.container.name}_$totalBytes',
            label: label,
            format: formatName,
            sizeText: sizeText,
            totalBytes: totalBytes,
            hasAudio: true,
            isAudioOnly: true,
            streamInfo: stream,
          ),
        );
      }

      // Prioritize MP4 / M4A audio streams, sorted by bitrate descending
      audioOptions.sort((a, b) {
        final aIsMp4 = a.format.contains('MP4') || a.format.contains('M4A');
        final bIsMp4 = b.format.contains('MP4') || b.format.contains('M4A');
        if (aIsMp4 && !bIsMp4) return -1;
        if (!aIsMp4 && bIsMp4) return 1;
        return b.totalBytes.compareTo(a.totalBytes);
      });

      // Format duration text
      final duration = video.duration;
      final durationText = duration != null
          ? _formatDuration(duration)
          : (isShort ? 'Short' : 'Video');

      // Best thumbnail URL
      final thumbnailUrl = video.thumbnails.highResUrl.isNotEmpty
          ? video.thumbnails.highResUrl
          : video.thumbnails.mediumResUrl;

      return VideoDownloadMetadata(
        id: videoId,
        title: video.title,
        author: video.author,
        durationText: durationText,
        thumbnailUrl: thumbnailUrl,
        isShort: isShort,
        videoOptions: videoOptions,
        audioOptions: audioOptions,
      );
    } finally {
      yt.close();
    }
  }

  /// Downloads the specified [streamInfo] to device storage with progress and atomic write.
  static Future<File> downloadStream({
    required StreamInfo streamInfo,
    required String videoTitle,
    required String qualityLabel,
    required void Function(double progress, String transferredText) onProgress,
  }) async {
    final yt = YoutubeExplode();
    try {
      final stream = yt.videos.streamsClient.get(streamInfo);
      final dir = await getSaveDirectory();

      // Clean title for valid file names and constrain length for file systems
      String safeTitle = videoTitle
          .replaceAll(RegExp(r'[\\/:*?"<>|#%&{}\$\+`!@=]'), '_')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (safeTitle.length > 50) {
        safeTitle = safeTitle.substring(0, 50).trim();
      }
      if (safeTitle.isEmpty) {
        safeTitle = 'Video_${DateTime.now().millisecondsSinceEpoch}';
      }

      final safeQuality = qualityLabel
          .replaceAll(RegExp(r'[\\/:*?"<>|\(\)\s+#%&{}`!@=]'), '_')
          .replaceAll(RegExp(r'_+'), '_');

      // Determine proper file extension
      String ext = streamInfo.container.name.toLowerCase();
      if (streamInfo is AudioStreamInfo && ext == 'mp4') {
        ext = 'm4a';
      } else if (ext == '3gpp') {
        ext = '3gp';
      }

      final fileName = '${safeTitle}_$safeQuality.$ext';
      final file = File('${dir.path}/$fileName');

      // Use temporary download file so unfinished/corrupted downloads are never read
      final tempFile = File('${file.path}.download');
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }

      final output = tempFile.openWrite();
      int receivedBytes = 0;
      final totalBytes = streamInfo.size.totalBytes;

      await for (final chunk in stream) {
        output.add(chunk);
        receivedBytes += chunk.length;
        final progress = totalBytes > 0
            ? (receivedBytes / totalBytes).clamp(0.0, 1.0)
            : 0.0;
        final receivedMb = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
        final totalMb = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
        onProgress(progress, '$receivedMb / $totalMb MB');
      }

      await output.flush();
      await output.close();

      // Atomically replace target file
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      await tempFile.rename(file.path);
      return file;
    } finally {
      yt.close();
    }
  }

  static Directory? _cachedSaveDirectory;

  /// Resolves the storage destination directory (persistent /downloads).
  static Future<Directory> getSaveDirectory() async {
    if (_cachedSaveDirectory != null) {
      if (!await _cachedSaveDirectory!.exists()) {
        await _cachedSaveDirectory!.create(recursive: true);
      }
      return _cachedSaveDirectory!;
    }

    Directory baseDir;
    try {
      baseDir = await getApplicationDocumentsDirectory();
    } catch (_) {
      baseDir = Directory.systemTemp;
    }

    final downloadFolder = Directory('${baseDir.path}/downloads');
    if (!await downloadFolder.exists()) {
      await downloadFolder.create(recursive: true);
    }
    _cachedSaveDirectory = downloadFolder;
    return downloadFolder;
  }

  /// Formats byte count to human-readable string.
  static String formatBytes(int bytes) => _formatBytes(bytes);

  /// Lists all downloaded media files in the save directory.
  static Future<List<DownloadedMediaItem>> getDownloadedFiles() async {
    try {
      final dir = await getSaveDirectory();
      if (!await dir.exists()) return [];

      final entities = dir.listSync();
      final List<DownloadedMediaItem> items = [];

      for (final entity in entities) {
        if (entity is File && !entity.path.endsWith('.download')) {
          final stat = entity.statSync();
          if (stat.size <= 0) continue; // Skip empty files

          final ext = entity.path.split('.').last.toLowerCase();
          if (['mp4', 'webm', 'm4a', 'mp3', 'mkv', '3gp', '3gpp'].contains(ext)) {
            final fileName = entity.uri.pathSegments.last;
            final baseName = fileName.substring(0, fileName.lastIndexOf('.'));

            String title = baseName;
            String quality = ext.toUpperCase();
            final lastUnderscore = baseName.lastIndexOf('_');
            if (lastUnderscore > 0) {
              title = baseName.substring(0, lastUnderscore).replaceAll('_', ' ');
              quality = baseName.substring(lastUnderscore + 1).replaceAll('_', ' ');
            }

            items.add(
              DownloadedMediaItem(
                file: entity,
                title: title,
                quality: quality,
                format: ext == '3gpp' ? '3GP' : ext.toUpperCase(),
                sizeBytes: stat.size,
                modified: stat.modified,
              ),
            );
          }
        }
      }

      items.sort((a, b) => b.modified.compareTo(a.modified));
      return items;
    } catch (_) {
      return [];
    }
  }

  /// Deletes an individual downloaded file.
  static Future<bool> deleteDownloadedFile(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Clears all downloaded files.
  static Future<void> deleteAllDownloadedFiles() async {
    try {
      final items = await getDownloadedFiles();
      for (final item in items) {
        await deleteDownloadedFile(item.file);
      }
    } catch (_) {}
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }

  static String _formatDuration(Duration duration) {
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
}

/// Represents a downloaded video or audio file on local storage.
class DownloadedMediaItem {
  final File file;
  final String title;
  final String quality;
  final String format;
  final int sizeBytes;
  final DateTime modified;

  const DownloadedMediaItem({
    required this.file,
    required this.title,
    required this.quality,
    required this.format,
    required this.sizeBytes,
    required this.modified,
  });

  String get sizeText => YouTubeDownloaderService.formatBytes(sizeBytes);
}
