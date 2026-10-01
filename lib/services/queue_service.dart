import 'package:flutter/foundation.dart';

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
}

/// Service that maintains a seamless up-next video queue for uninterrupted watch sessions.
class QueueService extends ChangeNotifier {
  static final QueueService instance = QueueService._internal();
  QueueService._internal();

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
  }

  /// Inserts a video to be played immediately after the current video.
  void playNext(QueuedVideo video) {
    _queue.removeWhere((v) => v.videoId == video.videoId);
    _queue.insert(0, video);
    notifyListeners();
  }

  /// Removes a video at [index] from the queue.
  void removeAt(int index) {
    if (index >= 0 && index < _queue.length) {
      _queue.removeAt(index);
      notifyListeners();
    }
  }

  /// Removes a video with [videoId] from the queue.
  void removeVideo(String videoId) {
    _queue.removeWhere((v) => v.videoId == videoId);
    notifyListeners();
  }

  /// Retrieves and dequeues the next video to play.
  QueuedVideo? popNext() {
    if (_queue.isEmpty) return null;
    final next = _queue.removeAt(0);
    notifyListeners();
    return next;
  }

  /// Clears all videos from the queue.
  void clear() {
    _queue.clear();
    notifyListeners();
  }
}
