import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'youtube_downloader_service.dart';

/// Represents a video in the user's active watch queue.
class QueuedVideo {
  final String videoId;
  final String title;
  final String author;
  final String durationText;
  final String thumbnailUrl;
  final String url;

  const QueuedVideo({
    required this.videoId,
    required this.title,
    this.author = '',
    this.durationText = '',
    this.thumbnailUrl = '',
    required this.url,
  });

  Map<String, dynamic> toJson() => {
    'videoId': videoId,
    'title': title,
    'author': author,
    'durationText': durationText,
    'thumbnailUrl': thumbnailUrl,
    'url': url,
  };

  factory QueuedVideo.fromJson(Map<String, dynamic> json) => QueuedVideo(
    videoId: json['videoId'] as String? ?? '',
    title: json['title'] as String? ?? 'Video',
    author: json['author'] as String? ?? '',
    durationText: json['durationText'] as String? ?? '',
    thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
    url: json['url'] as String? ?? '',
  );
}

/// Service that maintains a seamless up-next video queue for uninterrupted watch sessions.
class QueueService extends ChangeNotifier {
  static final QueueService instance = QueueService._internal();
  QueueService._internal() {
    _load();
  }

  final List<QueuedVideo> _queue = [];

  List<QueuedVideo> get queue => List.unmodifiable(_queue);

  bool get isEmpty => _queue.isEmpty;
  bool get isNotEmpty => _queue.isNotEmpty;
  int get length => _queue.length;

  /// Adds a video to the end of the queue.
  void addToQueue(QueuedVideo video) {
    if (_queue.any((v) => v.videoId == video.videoId)) return;
    _queue.add(video);
    notifyListeners();
    _save();
  }

  /// Inserts a video to be played immediately after the current video.
  void playNext(QueuedVideo video) {
    _queue.removeWhere((v) => v.videoId == video.videoId);
    _queue.insert(0, video);
    notifyListeners();
    _save();
  }

  /// Removes a video at [index] from the queue.
  void removeAt(int index) {
    if (index >= 0 && index < _queue.length) {
      _queue.removeAt(index);
      notifyListeners();
      _save();
    }
  }

  QueuedVideo? takeAt(int index) {
    if (index < 0 || index >= _queue.length) return null;
    final video = _queue.removeAt(index);
    notifyListeners();
    _save();
    return video;
  }

  /// Removes a video with [videoId] from the queue.
  void removeVideo(String videoId) {
    _queue.removeWhere((v) => v.videoId == videoId);
    notifyListeners();
    _save();
  }

  /// Retrieves and dequeues the next video to play.
  QueuedVideo? popNext() {
    if (_queue.isEmpty) return null;
    final next = _queue.removeAt(0);
    notifyListeners();
    _save();
    return next;
  }

  /// Clears all videos from the queue.
  void clear() {
    _queue.clear();
    notifyListeners();
    _save();
  }

  Future<File> _queueFile() async {
    final directory = await YouTubeDownloaderService.getSaveDirectory();
    return File('${directory.path}/watch_queue.json');
  }

  Future<void> _load() async {
    try {
      final file = await _queueFile();
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString());
      if (data is! List) return;
      _queue
        ..clear()
        ..addAll(
          data
              .whereType<Map<String, dynamic>>()
              .map(QueuedVideo.fromJson)
              .where(
                (video) => video.videoId.isNotEmpty && video.url.isNotEmpty,
              ),
        );
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final file = await _queueFile();
      await file.writeAsString(
        jsonEncode(_queue.map((video) => video.toJson()).toList()),
        flush: true,
      );
    } catch (_) {}
  }
}
