import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'youtube_downloader_service.dart';

/// Represents a video playback checkpoint for the "Continue Watching" feature.
class VideoCheckpoint {
  final String videoId;
  final String title;
  final int positionSeconds;
  final int durationSeconds;
  final DateTime lastWatched;

  const VideoCheckpoint({
    required this.videoId,
    required this.title,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.lastWatched,
  });

  double get progress => durationSeconds > 0
      ? (positionSeconds / durationSeconds).clamp(0.0, 1.0)
      : 0.0;

  String get positionFormatted {
    final m = positionSeconds ~/ 60;
    final s = (positionSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Map<String, dynamic> toJson() => {
    'videoId': videoId,
    'title': title,
    'positionSeconds': positionSeconds,
    'durationSeconds': durationSeconds,
    'lastWatched': lastWatched.toIso8601String(),
  };

  factory VideoCheckpoint.fromJson(Map<String, dynamic> json) =>
      VideoCheckpoint(
        videoId: json['videoId'] as String? ?? '',
        title: json['title'] as String? ?? '',
        positionSeconds: json['positionSeconds'] as int? ?? 0,
        durationSeconds: json['durationSeconds'] as int? ?? 0,
        lastWatched:
            DateTime.tryParse(json['lastWatched'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// Service that persists and restores video watch progress across sessions.
class WatchHistoryService extends ChangeNotifier {
  static final WatchHistoryService instance = WatchHistoryService._internal();
  WatchHistoryService._internal() {
    _loadHistory();
  }

  final Map<String, VideoCheckpoint> _history = {};
  VideoCheckpoint? _lastCheckpoint;

  List<VideoCheckpoint> get history =>
      _history.values.toList()
        ..sort((a, b) => b.lastWatched.compareTo(a.lastWatched));

  VideoCheckpoint? get lastWatched => _lastCheckpoint;

  VideoCheckpoint? getCheckpoint(String videoId) => _history[videoId];

  Future<File> _getHistoryFile() async {
    final dir = await YouTubeDownloaderService.getSaveDirectory();
    return File('${dir.path}/watch_history.json');
  }

  Future<void> _loadHistory() async {
    try {
      final file = await _getHistoryFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> list = jsonDecode(content) as List<dynamic>;
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final cp = VideoCheckpoint.fromJson(item);
            if (cp.videoId.isNotEmpty) {
              _history[cp.videoId] = cp;
            }
          }
        }
        if (_history.isNotEmpty) {
          _lastCheckpoint = history.first;
        }
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> saveProgress({
    required String videoId,
    required String title,
    required int positionSeconds,
    required int durationSeconds,
  }) async {
    if (videoId.isEmpty || durationSeconds <= 0) return;
    // Don't save if at the very beginning or basically finished (>95%)
    if (positionSeconds < 5 || positionSeconds >= durationSeconds * 0.95) {
      if (positionSeconds >= durationSeconds * 0.95) {
        _history.remove(videoId);
        _lastCheckpoint = history.isEmpty ? null : history.first;
        await _saveToDisk();
        notifyListeners();
      }
      return;
    }

    final cp = VideoCheckpoint(
      videoId: videoId,
      title: title.isNotEmpty ? title : (_history[videoId]?.title ?? 'Video'),
      positionSeconds: positionSeconds,
      durationSeconds: durationSeconds,
      lastWatched: DateTime.now(),
    );

    _history[videoId] = cp;
    _lastCheckpoint = cp;
    notifyListeners();
    await _saveToDisk();
  }

  Future<void> _saveToDisk() async {
    try {
      final file = await _getHistoryFile();
      final list = _history.values.map((c) => c.toJson()).toList();
      await file.writeAsString(jsonEncode(list));
    } catch (_) {}
  }

  Future<void> clearHistory() async {
    _history.clear();
    _lastCheckpoint = null;
    notifyListeners();
    try {
      final file = await _getHistoryFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<void> dismissCheckpoint(String videoId) async {
    _history.remove(videoId);
    _lastCheckpoint = history.isEmpty ? null : history.first;
    notifyListeners();
    await _saveToDisk();
  }
}
