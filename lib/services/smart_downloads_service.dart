import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'download_manager.dart';
import 'app_settings_service.dart';
import 'youtube_downloader_service.dart';

/// Service that automatically saves recently watched videos for offline access
/// without requiring a manual download action.
class SmartDownloadsService extends ChangeNotifier {
  static final SmartDownloadsService instance =
      SmartDownloadsService._internal();
  SmartDownloadsService._internal() {
    _loadSettings();
  }

  bool _isEnabled = true;
  int _maxAutoDownloads = 5;
  bool _wifiOnly = true;
  final Set<String> _processingVideoIds = {};

  bool get isEnabled => _isEnabled;
  int get maxAutoDownloads => _maxAutoDownloads;
  bool get wifiOnly => _wifiOnly;

  Future<File> _getConfigFile() async {
    final dir = await YouTubeDownloaderService.getSaveDirectory();
    return File('${dir.path}/smart_downloads_config.json');
  }

  Future<void> _loadSettings() async {
    try {
      final file = await _getConfigFile();
      if (await file.exists()) {
        final data =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _isEnabled = data['isEnabled'] as bool? ?? true;
        _maxAutoDownloads = data['maxAutoDownloads'] as int? ?? 5;
        _wifiOnly = data['wifiOnly'] as bool? ?? true;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    notifyListeners();
    try {
      final file = await _getConfigFile();
      await file.writeAsString(
        jsonEncode({
          'isEnabled': _isEnabled,
          'maxAutoDownloads': _maxAutoDownloads,
          'wifiOnly': _wifiOnly,
        }),
      );
    } catch (_) {}
  }

  Future<void> setMaxAutoDownloads(int max) async {
    _maxAutoDownloads = max;
    notifyListeners();
    try {
      final file = await _getConfigFile();
      await file.writeAsString(
        jsonEncode({
          'isEnabled': _isEnabled,
          'maxAutoDownloads': _maxAutoDownloads,
          'wifiOnly': _wifiOnly,
        }),
      );
    } catch (_) {}
  }

  Future<void> setWifiOnly(bool wifiOnly) async {
    _wifiOnly = wifiOnly;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> _saveSettings() async {
    try {
      final file = await _getConfigFile();
      await file.writeAsString(
        jsonEncode({
          'isEnabled': _isEnabled,
          'maxAutoDownloads': _maxAutoDownloads,
          'wifiOnly': _wifiOnly,
        }),
      );
    } catch (_) {}
  }

  /// Evaluates whether the currently watched video should be automatically cached
  /// for offline use based on user settings and available downloads.
  Future<void> processSmartDownloadForVideo(String videoId) async {
    if (!_isEnabled ||
        videoId.isEmpty ||
        _processingVideoIds.contains(videoId)) {
      return;
    }

    _processingVideoIds.add(videoId);

    try {
      if (_wifiOnly) {
        final connectivity = await Connectivity().checkConnectivity();
        if (!connectivity.contains(ConnectivityResult.wifi) &&
            !connectivity.contains(ConnectivityResult.ethernet)) {
          return;
        }
      }

      final completedFiles =
          await YouTubeDownloaderService.getDownloadedFiles();
      if (completedFiles.length >= _maxAutoDownloads) return;

      // Check if already downloaded or in progress
      final alreadyDownloaded = completedFiles.any(
        (file) =>
            file.videoId == videoId ||
            file.file.path.contains('__${videoId}__'),
      );
      if (alreadyDownloaded) return;

      final alreadyQueued = DownloadManager.instance.allTasks.any(
        (t) => t.videoId == videoId,
      );
      if (alreadyQueued) return;

      // Fetch download streams and pick best 720p or 360p muxed stream
      final meta = await YouTubeDownloaderService.fetchDownloadDetails(videoId);
      final quality = AppSettingsService.instance.preferredDownloadQuality;
      final playableOptions = quality == PreferredDownloadQuality.audio
          ? meta.audioOptions
          : meta.videoOptions.where((opt) => opt.hasAudio).toList();
      if (playableOptions.isEmpty) return;
      final preferredOption = switch (quality) {
        PreferredDownloadQuality.p360 => playableOptions.firstWhere(
          (opt) => opt.label.contains('360p'),
          orElse: () => playableOptions.first,
        ),
        PreferredDownloadQuality.p720 => playableOptions.firstWhere(
          (opt) => opt.label.contains('720p'),
          orElse: () => playableOptions.first,
        ),
        PreferredDownloadQuality.best => playableOptions.first,
        PreferredDownloadQuality.audio => playableOptions.first,
      };

      await DownloadManager.instance.startDownload(
        videoId: meta.id,
        title: meta.title,
        author: meta.author,
        durationText: meta.durationText,
        thumbnailUrl: meta.thumbnailUrl,
        qualityOption: preferredOption,
        isShort: meta.isShort,
      );
    } catch (_) {
      // Smart downloads are opportunistic and must not interrupt playback.
    } finally {
      _processingVideoIds.remove(videoId);
    }
  }
}
