import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'youtube_downloader_service.dart';

/// Status of an individual media download task.
enum DownloadStatus { queued, downloading, paused, completed, failed, canceled }

/// Represents an active or completed download task with pause/resume support.
class DownloadTask {
  DownloadTask({
    required this.id,
    required this.videoId,
    required this.title,
    required this.author,
    required this.durationText,
    required this.thumbnailUrl,
    required this.qualityLabel,
    required this.format,
    required this.isAudioOnly,
    required this.isShort,
    required this.streamInfo,
    required this.targetFile,
    required this.tempFile,
    required this.totalBytes,
    this.status = DownloadStatus.queued,
    this.receivedBytes = 0,
    this.progress = 0.0,
    this.progressText = 'Starting...',
    this.errorMessage,
  });

  final String id;
  final String videoId;
  final String title;
  final String author;
  final String durationText;
  final String thumbnailUrl;
  final String qualityLabel;
  final String format;
  final bool isAudioOnly;
  final bool isShort;
  StreamInfo streamInfo;
  final File targetFile;
  final File tempFile;

  DownloadStatus status;
  int receivedBytes;
  int totalBytes;
  double progress;
  String progressText;
  String? errorMessage;

  /// Smoothed instantaneous transfer rate shown by the downloads UI.
  double bytesPerSecond = 0;
  DateTime? _lastSpeedSampleAt;
  int _lastSpeedSampleBytes = 0;

  HttpClient? _activeClient;
  StreamSubscription<List<int>>? _streamSubscription;
  IOSink? _fileSink;
  bool _isDisposed = false;

  bool get isDownloading => status == DownloadStatus.downloading;
  bool get isPaused => status == DownloadStatus.paused;
  bool get isCompleted => status == DownloadStatus.completed;
  bool get isFailed => status == DownloadStatus.failed;
}

/// Centralized manager for handling persistent, resumable downloads.
/// Supports pausing, resuming with HTTP Range headers, and auto-refreshing expired links.
class DownloadManager extends ChangeNotifier {
  static final DownloadManager instance = DownloadManager._internal();
  DownloadManager._internal();

  final Map<String, DownloadTask> _tasks = {};

  List<DownloadTask> get allTasks => _tasks.values.toList();

  /// Returns all currently in-progress tasks (downloading, paused, queued, or failed).
  List<DownloadTask> get inProgressTasks => _tasks.values
      .where(
        (t) =>
            t.status == DownloadStatus.downloading ||
            t.status == DownloadStatus.paused ||
            t.status == DownloadStatus.queued ||
            t.status == DownloadStatus.failed,
      )
      .toList();

  DownloadTask? getTask(String id) => _tasks[id];

  /// Adds or updates a task in the manager.
  void addTask(DownloadTask task) {
    _tasks[task.id] = task;
    notifyListeners();
  }

  /// Removes a task from the manager.
  void removeTask(String id) {
    _tasks.remove(id);
  }

  /// Starts or queues a download for the given video and quality option.
  Future<DownloadTask> startDownload({
    required String videoId,
    required String title,
    required String author,
    required String durationText,
    required String thumbnailUrl,
    required DownloadQualityOption qualityOption,
    bool isShort = false,
  }) async {
    final taskId = '${videoId}_${qualityOption.id}';

    // If already exists and is downloading or paused, return existing task
    if (_tasks.containsKey(taskId)) {
      final existing = _tasks[taskId]!;
      if (existing.isPaused || existing.isFailed) {
        await resumeDownload(taskId);
      }
      return existing;
    }

    final dir = await YouTubeDownloaderService.getSaveDirectory();

    // Clean title for valid file names
    String safeTitle = title
        .replaceAll(RegExp(r'[\\/:*?"<>|#%&{}\$\+`!@=]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (safeTitle.length > 50) {
      safeTitle = safeTitle.substring(0, 50).trim();
    }
    if (safeTitle.isEmpty) {
      safeTitle = 'Video_${DateTime.now().millisecondsSinceEpoch}';
    }

    final safeQuality = qualityOption.label
        .replaceAll(RegExp(r'[\\/:*?"<>|\(\)\s+#%&{}`!@=]'), '_')
        .replaceAll(RegExp(r'_+'), '_');

    // Extension: mp4 for video, m4a for audio mp4
    String ext = qualityOption.streamInfo.container.name.toLowerCase();
    if (qualityOption.isAudioOnly && ext == 'mp4') {
      ext = 'm4a';
    } else if (ext == '3gpp') {
      ext = '3gp';
    }

    final targetFile = File('${dir.path}/${safeTitle}_$safeQuality.$ext');
    final tempFile = File('${targetFile.path}.download');

    final task = DownloadTask(
      id: taskId,
      videoId: videoId,
      title: title,
      author: author,
      durationText: durationText,
      thumbnailUrl: thumbnailUrl,
      qualityLabel: qualityOption.label,
      format: qualityOption.format,
      isAudioOnly: qualityOption.isAudioOnly,
      isShort: isShort,
      streamInfo: qualityOption.streamInfo,
      targetFile: targetFile,
      tempFile: tempFile,
      totalBytes: qualityOption.totalBytes,
      status: DownloadStatus.downloading,
    );

    _tasks[taskId] = task;
    notifyListeners();

    _executeDownload(task);
    return task;
  }

  /// Pauses an active download, preserving downloaded bytes in temp file.
  Future<void> pauseDownload(String taskId) async {
    final task = _tasks[taskId];
    if (task == null || task.status != DownloadStatus.downloading) return;

    task.status = DownloadStatus.paused;
    task.progressText = 'Paused (${(task.progress * 100).round()}%)';

    try {
      await task._streamSubscription?.cancel();
      task._streamSubscription = null;
    } catch (_) {}

    try {
      await task._fileSink?.flush();
      await task._fileSink?.close();
      task._fileSink = null;
    } catch (_) {}

    try {
      task._activeClient?.close(force: true);
      task._activeClient = null;
    } catch (_) {}

    notifyListeners();
  }

  /// Resumes a paused or failed download using HTTP Range without breaking link.
  Future<void> resumeDownload(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return;
    if (task.status == DownloadStatus.downloading) return;

    task.status = DownloadStatus.downloading;
    task.errorMessage = null;
    task.progressText = 'Resuming...';
    task.bytesPerSecond = 0;
    task._lastSpeedSampleAt = null;
    task._lastSpeedSampleBytes = task.receivedBytes;
    notifyListeners();

    _executeDownload(task);
  }

  /// Cancels a download task and deletes the temporary file.
  Future<void> cancelDownload(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return;

    task.status = DownloadStatus.canceled;
    task._isDisposed = true;

    try {
      await task._streamSubscription?.cancel();
    } catch (_) {}

    try {
      await task._fileSink?.close();
    } catch (_) {}

    try {
      task._activeClient?.close(force: true);
    } catch (_) {}

    if (await task.tempFile.exists()) {
      try {
        await task.tempFile.delete();
      } catch (_) {}
    }

    _tasks.remove(taskId);
    notifyListeners();
  }

  /// Core download worker handling chunk streaming, range headers, and expired link renewal.
  Future<void> _executeDownload(DownloadTask task) async {
    if (task._isDisposed || task.status != DownloadStatus.downloading) return;

    final client = HttpClient();
    task._activeClient = client;

    try {
      int existingBytes = 0;
      if (await task.tempFile.exists()) {
        existingBytes = await task.tempFile.length();
      }

      // If already fully downloaded
      if (task.totalBytes > 0 && existingBytes >= task.totalBytes) {
        await _completeDownload(task);
        return;
      }

      task.receivedBytes = existingBytes;
      task._lastSpeedSampleBytes = existingBytes;
      task._lastSpeedSampleAt = DateTime.now();
      if (task.totalBytes > 0) {
        task.progress = (existingBytes / task.totalBytes).clamp(0.0, 1.0);
      }

      final request = await client.getUrl(task.streamInfo.url);
      if (existingBytes > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existingBytes-');
      }

      final response = await request.close();

      // Handle link expiry (HTTP 403 Forbidden or 410 Gone) by refreshing manifest
      if (response.statusCode == HttpStatus.forbidden ||
          response.statusCode == HttpStatus.gone ||
          response.statusCode == HttpStatus.notFound) {
        debugPrint(
          '[DownloadManager] Stream URL expired for ${task.videoId}. Refreshing stream manifest...',
        );
        final yt = YoutubeExplode();
        try {
          final manifest = await yt.videos.streamsClient.getManifest(
            task.videoId,
          );
          final freshStream = manifest.streams.firstWhere(
            (s) => s.tag == task.streamInfo.tag,
            orElse: () => manifest.streams.firstWhere(
              (s) =>
                  s.container == task.streamInfo.container &&
                  s.size.totalBytes == task.totalBytes,
              orElse: () => task.streamInfo,
            ),
          );
          task.streamInfo = freshStream;
          yt.close();
          // Seamlessly re-execute with fresh link from current offset
          if (task.status == DownloadStatus.downloading && !task._isDisposed) {
            await _executeDownload(task);
            return;
          }
          return;
        } catch (e) {
          yt.close();
          throw Exception('Failed to renew stream link: $e');
        }
      }

      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        throw HttpException(
          'Invalid response status: ${response.statusCode} ${response.reasonPhrase}',
          uri: task.streamInfo.url,
        );
      }

      // Open temp file in append mode if resuming, or write if starting fresh
      final openMode =
          (existingBytes > 0 &&
              response.statusCode == HttpStatus.partialContent)
          ? FileMode.append
          : FileMode.write;

      final sink = task.tempFile.openWrite(mode: openMode);
      task._fileSink = sink;

      final completer = Completer<void>();

      task._streamSubscription = response.listen(
        (chunk) {
          if (task.status != DownloadStatus.downloading || task._isDisposed) {
            return;
          }
          sink.add(chunk);
          task.receivedBytes += chunk.length;
          if (task.totalBytes > 0) {
            task.progress = (task.receivedBytes / task.totalBytes).clamp(
              0.0,
              1.0,
            );
          }
          final receivedMb = (task.receivedBytes / (1024 * 1024))
              .toStringAsFixed(1);
          final totalMb = (task.totalBytes / (1024 * 1024)).toStringAsFixed(1);
          final percent = (task.progress * 100).round();
          final now = DateTime.now();
          final previousSample = task._lastSpeedSampleAt;
          if (previousSample != null) {
            final elapsedMs = now.difference(previousSample).inMilliseconds;
            if (elapsedMs >= 500) {
              final sampleRate =
                  (task.receivedBytes - task._lastSpeedSampleBytes) *
                  1000 /
                  elapsedMs;
              task.bytesPerSecond = task.bytesPerSecond == 0
                  ? sampleRate
                  : (task.bytesPerSecond * 0.65) + (sampleRate * 0.35);
              task._lastSpeedSampleAt = now;
              task._lastSpeedSampleBytes = task.receivedBytes;
            }
          }
          final speed = _formatTransferRate(task.bytesPerSecond);
          task.progressText = '$receivedMb / $totalMb MB ($percent%) • $speed';
          notifyListeners();
        },
        onDone: () async {
          try {
            await sink.flush();
            await sink.close();
            task._fileSink = null;
          } catch (_) {}
          if (!completer.isCompleted) completer.complete();
        },
        onError: (e) {
          if (!completer.isCompleted) completer.completeError(e);
        },
        cancelOnError: true,
      );

      await completer.future;

      if (task.status == DownloadStatus.downloading && !task._isDisposed) {
        await _completeDownload(task);
      }
    } catch (e) {
      if (task.status != DownloadStatus.paused && !task._isDisposed) {
        task.status = DownloadStatus.failed;
        task.errorMessage = 'Download error: $e';
        task.progressText = 'Failed. Tap to retry';
        notifyListeners();
      }
    } finally {
      try {
        await task._fileSink?.close();
        task._fileSink = null;
      } catch (_) {}
      try {
        client.close(force: true);
        if (task._activeClient == client) {
          task._activeClient = null;
        }
      } catch (_) {}
    }
  }

  Future<void> _completeDownload(DownloadTask task) async {
    try {
      if (await task.targetFile.exists()) {
        try {
          await task.targetFile.delete();
        } catch (_) {}
      }
      await task.tempFile.rename(task.targetFile.path);
      task.status = DownloadStatus.completed;
      task.progress = 1.0;
      task.bytesPerSecond = 0;
      task.progressText = 'Completed';
      notifyListeners();
    } catch (e) {
      task.status = DownloadStatus.failed;
      task.errorMessage = 'Failed to save completed file: $e';
      notifyListeners();
    }
  }

  static String _formatTransferRate(double bytesPerSecond) {
    if (bytesPerSecond <= 0) return 'Calculating speed…';
    if (bytesPerSecond >= 1024 * 1024) {
      return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    return '${(bytesPerSecond / 1024).toStringAsFixed(0)} KB/s';
  }
}
