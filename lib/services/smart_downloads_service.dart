import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'download_manager.dart';
import 'youtube_downloader_service.dart';

/// Service that automatically saves recommended or frequently watched videos
/// for offline access without requiring manual downloads.
class SmartDownloadsService extends ChangeNotifier {
  static final SmartDownloadsService instance = SmartDownloadsService._internal();
  SmartDownloadsService._internal() {
    _loadSettings();
  }

  bool _isEnabled = true;
  int _maxAutoDownloads = 5;

  bool get isEnabled => _isEnabled;
  int get maxAutoDownloads => _maxAutoDownloads;

  Future<File> _getConfigFile() async {
    final dir = await YouTubeDownloaderService.getSaveDirectory();
    return File('${dir.path}/smart_downloads_config.json');
  }

  Future<void> _loadSettings() async {
    try {
      final file = await _getConfigFile();
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _isEnabled = data['isEnabled'] as bool? ?? true;
        _maxAutoDownloads = data['maxAutoDownloads'] as int? ?? 5;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    notifyListeners();
    try {
      final file = await _getConfigFile();
      await file.writeAsString(jsonEncode({
        'isEnabled': _isEnabled,
        'maxAutoDownloads': _maxAutoDownloads,
      }));
    } catch (_) {}
  }

  Future<void> setMaxAutoDownloads(int max) async {
    _maxAutoDownloads = max;
    notifyListeners();
    try {
      final file = await _getConfigFile();
      await file.writeAsString(jsonEncode({
        'isEnabled': _isEnabled,
        'maxAutoDownloads': _maxAutoDownloads,
      }));
    } catch (_) {}
  }

  /// Evaluates whether the currently watched video should be automatically cached
  /// for offline use based on user settings and available downloads.
  Future<void> processSmartDownloadForVideo(String videoId) async {
    if (!_isEnabled || videoId.isEmpty) return;

    try {
      final completedFiles = await YouTubeDownloaderService.getDownloadedFiles();
      if (completedFiles.length >= _maxAutoDownloads) return;

      // Check if already downloaded or in progress
      final alreadyDownloaded = completedFiles.any((f) => f.title.contains(videoId) || f.file.path.contains(videoId));
      if (alreadyDownloaded) return;

      final alreadyQueued = DownloadManager.instance.allTasks.any((t) => t.videoId == videoId);
      if (alreadyQueued) return;

      // Fetch download streams and pick best 720p or 360p muxed stream
      final meta = await YouTubeDownloaderService.fetchDownloadDetails(videoId);
      if (meta.videoOptions.isEmpty) return;

      final preferredOption = meta.videoOptions.firstWhere(
        (opt) => opt.hasAudio && (opt.label.contains('720p') || opt.label.contains('360p')),
        orElse: () => meta.videoOptions.first,
      );

      await DownloadManager.instance.startDownload(
        videoId: meta.id,
        title: meta.title,
        author: meta.author,
        durationText: meta.durationText,
        thumbnailUrl: meta.thumbnailUrl,
        qualityOption: preferredOption,
        isShort: meta.isShort,
      );
    } catch (_) {}
  }
}
