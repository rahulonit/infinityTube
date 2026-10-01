import 'package:flutter/services.dart';

class StorageInfo {
  const StorageInfo({required this.totalBytes, required this.freeBytes});

  final int totalBytes;
  final int freeBytes;
}

class StorageInfoService {
  static const MethodChannel _channel = MethodChannel('infinitytube/storage');

  static Future<StorageInfo?> getStorageInfo() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getStorageInfo',
      );
      final total = result?['totalBytes'];
      final free = result?['freeBytes'];
      if (total is num && free is num) {
        return StorageInfo(totalBytes: total.toInt(), freeBytes: free.toInt());
      }
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
    return null;
  }
}
