import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Persisted application settings for playback & subtitles (`.cache/app_settings.json`).
class AppSettingsService extends ChangeNotifier {
  AppSettingsService._();
  static final AppSettingsService instance = AppSettingsService._();

  static const String _fileName = 'app_settings.json';
  static Directory? _cachedCacheDir;

  bool _volumeBoostEnabled = true;
  bool _continuousAutoplay = true;
  double _defaultPlaybackSpeed = 1.0;
  int _subtitleSize = 55;
  String _preferredSubtitleLanguage = 'id';
  String _tmdbApiKey = '';

  bool get volumeBoostEnabled => _volumeBoostEnabled;
  bool get continuousAutoplay => _continuousAutoplay;
  double get defaultPlaybackSpeed => _defaultPlaybackSpeed;
  int get subtitleSize => _subtitleSize;
  String get preferredSubtitleLanguage => _preferredSubtitleLanguage;
  String get tmdbApiKey => _tmdbApiKey;

  double get maxVolume => _volumeBoostEnabled ? 130.0 : 100.0;

  static Directory _resolveCacheDir() {
    if (_cachedCacheDir != null) return _cachedCacheDir!;
    final direct = Directory('.cache');
    if (direct.existsSync()) {
      _cachedCacheDir = direct;
      return direct;
    }
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final resolved = Directory('$exeDir${Platform.pathSeparator}.cache');
      if (resolved.existsSync() || !kDebugMode) {
        _cachedCacheDir = resolved;
        return resolved;
      }
    } catch (_) {}
    _cachedCacheDir = direct;
    return direct;
  }

  static File _getSettingsFile() {
    final dir = _resolveCacheDir();
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  Future<void> init() async {
    try {
      final file = _getSettingsFile();
      if (!await file.exists()) return;
      final raw = (await file.readAsString()).trim();
      if (raw.isEmpty) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _volumeBoostEnabled = data['volumeBoostEnabled'] as bool? ?? true;
      _continuousAutoplay = data['continuousAutoplay'] as bool? ?? true;
      _defaultPlaybackSpeed = ((data['defaultPlaybackSpeed'] as num?)?.toDouble() ?? 1.0).clamp(0.5, 2.0);
      _subtitleSize = ((data['subtitleSize'] as num?)?.toInt() ?? 55).clamp(24, 90);
      _preferredSubtitleLanguage = data['preferredSubtitleLanguage'] as String? ?? 'id';
      _tmdbApiKey = (data['tmdbApiKey'] as String? ?? '').trim();
    } catch (e) {
      debugPrint('Error loading app settings: $e');
    }
  }

  Future<void> _save() async {
    try {
      final file = _getSettingsFile();
      final tmp = File('${file.path}.tmp');
      final encoded = jsonEncode({
        'volumeBoostEnabled': _volumeBoostEnabled,
        'continuousAutoplay': _continuousAutoplay,
        'defaultPlaybackSpeed': _defaultPlaybackSpeed,
        'subtitleSize': _subtitleSize,
        'preferredSubtitleLanguage': _preferredSubtitleLanguage,
        'tmdbApiKey': _tmdbApiKey,
      });
      await tmp.writeAsString(encoded, flush: true);
      try {
        await tmp.rename(file.path);
      } catch (_) {
        if (await file.exists()) await file.delete();
        await tmp.rename(file.path);
      }
    } catch (e) {
      debugPrint('Error saving app settings: $e');
    }
  }

  Future<void> setVolumeBoostEnabled(bool value) async {
    if (_volumeBoostEnabled == value) return;
    _volumeBoostEnabled = value;
    notifyListeners();
    await _save();
  }

  Future<void> setContinuousAutoplay(bool value) async {
    if (_continuousAutoplay == value) return;
    _continuousAutoplay = value;
    notifyListeners();
    await _save();
  }

  Future<void> setDefaultPlaybackSpeed(double value) async {
    final clamped = value.clamp(0.5, 2.0);
    if (_defaultPlaybackSpeed == clamped) return;
    _defaultPlaybackSpeed = clamped;
    notifyListeners();
    await _save();
  }

  Future<void> setSubtitleSize(int value) async {
    final clamped = value.clamp(24, 90);
    if (_subtitleSize == clamped) return;
    _subtitleSize = clamped;
    notifyListeners();
    await _save();
  }

  Future<void> setPreferredSubtitleLanguage(String value) async {
    if (_preferredSubtitleLanguage == value) return;
    _preferredSubtitleLanguage = value;
    notifyListeners();
    await _save();
  }

  Future<void> setTmdbApiKey(String value) async {
    final trimmed = value.trim();
    if (_tmdbApiKey == trimmed) return;
    _tmdbApiKey = trimmed;
    notifyListeners();
    await _save();
  }
}
