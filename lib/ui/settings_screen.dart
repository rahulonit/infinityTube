import 'package:flutter/material.dart';

import '../services/app_settings_service.dart';
import '../services/queue_service.dart';
import '../services/smart_downloads_service.dart';
import '../services/watch_history_service.dart';
import 'downloads_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AppSettingsService get settings => AppSettingsService.instance;
  SmartDownloadsService get smart => SmartDownloadsService.instance;

  @override
  void initState() {
    super.initState();
    settings.addListener(_refresh);
    smart.addListener(_refresh);
  }

  @override
  void dispose() {
    settings.removeListener(_refresh);
    smart.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _change(void Function(AppSettingsService value) change) =>
      settings.update(change);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F0F),
        foregroundColor: Colors.white,
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _header('Playback', Icons.play_circle_outline_rounded),
          _switch(
            title: 'Background playback',
            subtitle: 'Keep media playing when the app is not visible',
            value: settings.backgroundPlaybackEnabled,
            onChanged: (v) => _change((s) => s.backgroundPlaybackEnabled = v),
          ),
          _switch(
            title: 'Picture-in-Picture',
            subtitle: 'Show the PiP action when supported by the device',
            value: settings.pictureInPictureEnabled,
            onChanged: (v) => _change((s) => s.pictureInPictureEnabled = v),
          ),
          _switch(
            title: 'Auto-enter PiP',
            subtitle: 'Keep a playing video visible when you leave the app',
            value: settings.autoEnterPictureInPicture,
            onChanged: settings.pictureInPictureEnabled
                ? (v) => _change((s) => s.autoEnterPictureInPicture = v)
                : null,
          ),
          _switch(
            title: 'Request enhanced 1080p',
            subtitle: 'Best effort; availability is controlled by YouTube',
            value: settings.enhanced1080Enabled,
            onChanged: (v) => _change((s) => s.enhanced1080Enabled = v),
          ),
          _switch(
            title: 'Continue Watching',
            subtitle: 'Save playback checkpoints locally on this device',
            value: settings.continueWatchingEnabled,
            onChanged: (v) => _change((s) => s.continueWatchingEnabled = v),
          ),
          _choiceRow<int>(
            title: 'Double-tap seek',
            values: const [5, 10, 15, 30],
            selected: settings.seekSeconds,
            label: (value) => '${value}s',
            onSelected: (value) => _change((s) => s.seekSeconds = value),
          ),
          _dropdown<PreferredExperience>(
            title: 'YouTube layout',
            value: settings.preferredExperience,
            values: PreferredExperience.values,
            label: (value) => switch (value) {
              PreferredExperience.automatic => 'Automatic',
              PreferredExperience.mobile => 'Mobile',
              PreferredExperience.desktop => 'Desktop',
            },
            onChanged: (value) => _change((s) => s.preferredExperience = value),
          ),
          _header('Downloads', Icons.download_rounded),
          ListTile(
            leading: const Icon(Icons.video_library_outlined),
            title: const Text('Manage offline library'),
            subtitle: const Text('Search, sort, share, retry, or delete files'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const DownloadsScreen())),
          ),
          _dropdown<PreferredDownloadQuality>(
            title: 'Default quality',
            value: settings.preferredDownloadQuality,
            values: PreferredDownloadQuality.values,
            label: (value) => switch (value) {
              PreferredDownloadQuality.best => 'Best available',
              PreferredDownloadQuality.p720 => '720p',
              PreferredDownloadQuality.p360 => '360p',
              PreferredDownloadQuality.audio => 'Audio only',
            },
            onChanged: (value) =>
                _change((s) => s.preferredDownloadQuality = value),
          ),
          _switch(
            title: 'Wi-Fi-only downloads',
            subtitle: 'Pause managed downloads on mobile data',
            value: settings.downloadsWifiOnly,
            onChanged: (v) => _change((s) => s.downloadsWifiOnly = v),
          ),
          _switch(
            title: 'Auto-resume interrupted downloads',
            subtitle: 'Resume eligible paused tasks when connectivity returns',
            value: settings.autoResumeDownloads,
            onChanged: (v) => _change((s) => s.autoResumeDownloads = v),
          ),
          _dropdown<int>(
            title: 'Keep storage free',
            value: settings.storageReserveMb,
            values: const [128, 256, 512, 1024, 2048, 4096],
            label: (value) => value >= 1024
                ? '${(value / 1024).toStringAsFixed(value % 1024 == 0 ? 0 : 1)} GB'
                : '$value MB',
            onChanged: (value) => _change((s) => s.storageReserveMb = value),
          ),
          _switch(
            title: 'Smart Downloads',
            subtitle: 'Cache recently watched videos automatically',
            value: smart.isEnabled,
            onChanged: smart.setEnabled,
          ),
          _switch(
            title: 'Smart Downloads on Wi-Fi only',
            subtitle: 'Never auto-cache over mobile data',
            value: smart.wifiOnly,
            onChanged: smart.isEnabled ? smart.setWifiOnly : null,
          ),
          _choiceRow<int>(
            title: 'Smart Download limit',
            values: const [3, 5, 10, 20],
            selected: smart.maxAutoDownloads,
            label: (value) => '$value',
            onSelected: smart.isEnabled ? smart.setMaxAutoDownloads : null,
          ),
          _header('Privacy and filtering', Icons.shield_outlined),
          _switch(
            title: 'Video ad handling',
            subtitle: 'Detect, mute, accelerate, and skip player ads',
            value: settings.adBlockingEnabled,
            onChanged: (v) => _change((s) => s.adBlockingEnabled = v),
          ),
          _switch(
            title: 'Tracker request blocking',
            subtitle: 'Block known advertising and tracking endpoints',
            value: settings.trackerBlockingEnabled,
            onChanged: (v) => _change((s) => s.trackerBlockingEnabled = v),
          ),
          _switch(
            title: 'Cosmetic filtering and OLED theme',
            subtitle: 'Hide promotions and force pitch-black page styling',
            value: settings.cosmeticFilteringEnabled,
            onChanged: (v) => _change((s) => s.cosmeticFilteringEnabled = v),
          ),
          ListTile(
            leading: const Icon(Icons.history_rounded),
            title: const Text('Clear watch checkpoints'),
            subtitle: Text(
              '${WatchHistoryService.instance.history.length} saved',
            ),
            onTap: () async {
              await WatchHistoryService.instance.clearHistory();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Watch checkpoints cleared.')),
              );
              setState(() {});
            },
          ),
          ListTile(
            leading: const Icon(Icons.queue_music_rounded),
            title: const Text('Clear watch queue'),
            subtitle: Text('${QueueService.instance.length} queued'),
            onTap: () {
              QueueService.instance.clear();
              setState(() {});
            },
          ),
          _header('Advanced', Icons.tune_rounded),
          _switch(
            title: 'Diagnostic logging',
            subtitle: 'Show InfinityTube diagnostic messages in debug builds',
            value: settings.diagnosticLoggingEnabled,
            onChanged: (v) => _change((s) => s.diagnosticLoggingEnabled = v),
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt_rounded),
            title: const Text('Reset all app settings'),
            subtitle: const Text('Restore recommended defaults'),
            onTap: _confirmReset,
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(
              'Changes affecting the YouTube page are applied when you return. '
              'Background downloads after the operating system terminates the app '
              'and high-resolution audio/video muxing remain platform limitations.',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(String title, IconData icon) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
    child: Row(
      children: [
        Icon(icon, color: const Color(0xFF3EA6FF), size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _switch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) => SwitchListTile(
    title: Text(title),
    subtitle: Text(subtitle),
    value: value,
    activeThumbColor: const Color(0xFF3EA6FF),
    onChanged: onChanged,
  );

  Widget _choiceRow<T>({
    required String title,
    required List<T> values,
    required T selected,
    required String Function(T value) label,
    required ValueChanged<T>? onSelected,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(title, style: const TextStyle(fontSize: 15)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: values
              .map(
                (value) => ChoiceChip(
                  label: Text(label(value)),
                  selected: value == selected,
                  onSelected: onSelected == null
                      ? null
                      : (chosen) {
                          if (chosen) onSelected(value);
                        },
                ),
              )
              .toList(),
        ),
      ],
    ),
  );

  Widget _dropdown<T>({
    required String title,
    required T value,
    required List<T> values,
    required String Function(T value) label,
    required ValueChanged<T> onChanged,
  }) => ListTile(
    title: Text(title),
    trailing: DropdownButton<T>(
      value: value,
      dropdownColor: const Color(0xFF282828),
      underline: const SizedBox.shrink(),
      items: values
          .map(
            (item) => DropdownMenuItem(value: item, child: Text(label(item))),
          )
          .toList(),
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    ),
  );

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset settings?'),
        content: const Text(
          'All InfinityTube preferences will return to defaults.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed == true) await settings.resetDefaults();
  }
}
