import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum PreferredExperience { automatic, mobile, desktop }

enum PreferredDownloadQuality { best, p720, p360, audio }

class AppSettingsService extends ChangeNotifier {
  AppSettingsService._internal() {
    _load();
  }

  static final AppSettingsService instance = AppSettingsService._internal();

  bool adBlockingEnabled = true;
  bool trackerBlockingEnabled = true;
  bool cosmeticFilteringEnabled = true;
  bool backgroundPlaybackEnabled = true;
  bool pictureInPictureEnabled = true;
  bool autoEnterPictureInPicture = true;
  bool enhanced1080Enabled = true;
  bool continueWatchingEnabled = true;
  bool autoResumeDownloads = true;
  bool downloadsWifiOnly = false;
  bool diagnosticLoggingEnabled = false;
  int seekSeconds = 10;
  int storageReserveMb = 512;
  PreferredExperience preferredExperience = PreferredExperience.automatic;
  PreferredDownloadQuality preferredDownloadQuality =
      PreferredDownloadQuality.p720;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  Future<File> _settingsFile() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return File('${directory.path}/infinitytube_settings.json');
  }

  Future<void> _load() async {
    try {
      final file = await _settingsFile();
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        if (json is Map<String, dynamic>) _applyJson(json);
      }
    } catch (_) {
      // Defaults remain usable when the platform storage plugin is unavailable.
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  void _applyJson(Map<String, dynamic> json) {
    adBlockingEnabled = json['adBlockingEnabled'] as bool? ?? true;
    trackerBlockingEnabled = json['trackerBlockingEnabled'] as bool? ?? true;
    cosmeticFilteringEnabled =
        json['cosmeticFilteringEnabled'] as bool? ?? true;
    backgroundPlaybackEnabled =
        json['backgroundPlaybackEnabled'] as bool? ?? true;
    pictureInPictureEnabled = json['pictureInPictureEnabled'] as bool? ?? true;
    autoEnterPictureInPicture =
        json['autoEnterPictureInPicture'] as bool? ?? true;
    enhanced1080Enabled = json['enhanced1080Enabled'] as bool? ?? true;
    continueWatchingEnabled = json['continueWatchingEnabled'] as bool? ?? true;
    autoResumeDownloads = json['autoResumeDownloads'] as bool? ?? true;
    downloadsWifiOnly = json['downloadsWifiOnly'] as bool? ?? false;
    diagnosticLoggingEnabled =
        json['diagnosticLoggingEnabled'] as bool? ?? false;
    seekSeconds = (json['seekSeconds'] as int? ?? 10).clamp(5, 30);
    storageReserveMb = (json['storageReserveMb'] as int? ?? 512).clamp(
      128,
      4096,
    );
    preferredExperience = PreferredExperience.values.firstWhere(
      (value) => value.name == json['preferredExperience'],
      orElse: () => PreferredExperience.automatic,
    );
    preferredDownloadQuality = PreferredDownloadQuality.values.firstWhere(
      (value) => value.name == json['preferredDownloadQuality'],
      orElse: () => PreferredDownloadQuality.p720,
    );
  }

  Map<String, dynamic> _toJson() => {
    'adBlockingEnabled': adBlockingEnabled,
    'trackerBlockingEnabled': trackerBlockingEnabled,
    'cosmeticFilteringEnabled': cosmeticFilteringEnabled,
    'backgroundPlaybackEnabled': backgroundPlaybackEnabled,
    'pictureInPictureEnabled': pictureInPictureEnabled,
    'autoEnterPictureInPicture': autoEnterPictureInPicture,
    'enhanced1080Enabled': enhanced1080Enabled,
    'continueWatchingEnabled': continueWatchingEnabled,
    'autoResumeDownloads': autoResumeDownloads,
    'downloadsWifiOnly': downloadsWifiOnly,
    'diagnosticLoggingEnabled': diagnosticLoggingEnabled,
    'seekSeconds': seekSeconds,
    'storageReserveMb': storageReserveMb,
    'preferredExperience': preferredExperience.name,
    'preferredDownloadQuality': preferredDownloadQuality.name,
  };

  Map<String, dynamic> toWebConfiguration() => {
    'adBlocking': adBlockingEnabled,
    'trackerBlocking': trackerBlockingEnabled,
    'cosmeticFiltering': cosmeticFilteringEnabled,
    'backgroundPlayback': backgroundPlaybackEnabled,
    'pictureInPicture': pictureInPictureEnabled,
    'enhanced1080': enhanced1080Enabled,
    'seekSeconds': seekSeconds,
  };

  Future<void> update(void Function(AppSettingsService settings) change) async {
    change(this);
    notifyListeners();
    await _save();
  }

  Future<void> resetDefaults() async {
    _applyJson(const {});
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final file = await _settingsFile();
      await file.writeAsString(jsonEncode(_toJson()), flush: true);
    } catch (_) {}
  }
}
