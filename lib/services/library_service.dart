import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import '../models/media_item.dart';
import 'metadata_service.dart';

class LocalLibraryService {
  static const Set<String> supportedVideoExtensions = {
    '.mp4',
    '.mkv',
    '.avi',
    '.mov',
    '.webm',
    '.ts',
    '.m4v',
    '.flv',
    '.wmv',
  };

  static File get _configFile => File('library_config.json');

  /// Read the full persistent library configuration
  static Future<Map<String, dynamic>> _readConfig() async {
    try {
      if (await _configFile.exists()) {
        final content = await _configFile.readAsString();
        return jsonDecode(content) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Error reading library config: $e');
    }
    return {
      'folders': <String>[],
      'customMetadata': <String, dynamic>{},
    };
  }

  /// Save full configuration to disk
  static Future<void> _writeConfig(Map<String, dynamic> config) async {
    try {
      await _configFile.writeAsString(jsonEncode(config));
    } catch (e) {
      debugPrint('Error writing library config: $e');
    }
  }

  /// Get all connected folders
  static Future<List<String>> getConnectedFolders() async {
    final config = await _readConfig();
    final rawList = config['folders'] as List<dynamic>? ?? [];
    return rawList.map((e) => e.toString()).where((p) => p.isNotEmpty).toList();
  }

  /// Add a new folder to connected list
  static Future<bool> addFolder(String folderPath) async {
    final cleanPath = folderPath.trim();
    if (cleanPath.isEmpty) return false;

    final config = await _readConfig();
    final List<String> folders = (config['folders'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();

    if (!folders.contains(cleanPath)) {
      folders.add(cleanPath);
      config['folders'] = folders;
      await _writeConfig(config);
      return true;
    }
    return false;
  }

  /// Remove a folder from connected list
  static Future<void> removeFolder(String folderPath) async {
    final config = await _readConfig();
    final List<String> folders = (config['folders'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();

    folders.remove(folderPath);
    config['folders'] = folders;
    await _writeConfig(config);
  }

  /// Save manual or custom metadata for a specific media item (by item id or title)
  static Future<void> saveCustomMetadata(String key, MediaItem item) async {
    final config = await _readConfig();
    final Map<String, dynamic> metaMap = Map<String, dynamic>.from(
      config['customMetadata'] as Map<String, dynamic>? ?? {},
    );

    metaMap[key] = item.toJson();
    // Also save by item.videoPath for backward compatibility
    if (item.videoPath.isNotEmpty) {
      metaMap[item.videoPath] = item.toJson();
    }
    config['customMetadata'] = metaMap;
    await _writeConfig(config);
  }

  /// Open native Windows folder picker dialog and add folder
  static Future<String?> pickAndAddFolder() async {
    try {
      final selectedDirectory = await FilePicker.getDirectoryPath(
        dialogTitle: 'Pilih Folder Koleksi Film / Serial',
      );

      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        await addFolder(selectedDirectory);
        return selectedDirectory;
      }
    } catch (e) {
      debugPrint('Error picking folder: $e');
    }
    return null;
  }

  /// Scan all connected folders and group videos PER TITLE / SHOW
  static Future<List<MediaItem>> scanAllFolders({
    bool fetchOnlineMetadata = true,
    void Function(String message)? onProgress,
  }) async {
    final folders = await getConnectedFolders();
    if (folders.isEmpty) return [];

    final config = await _readConfig();
    final Map<String, dynamic> customMetadataMap = Map<String, dynamic>.from(
      config['customMetadata'] as Map<String, dynamic>? ?? {},
    );

    // 1. Collect all video files
    final List<File> videoFiles = [];
    final Set<String> seenPaths = {};

    for (final folderPath in folders) {
      final dir = Directory(folderPath);
      if (!await dir.exists()) continue;

      try {
        final entities = dir.listSync(recursive: true, followLinks: false);
        for (final entity in entities) {
          if (entity is File) {
            final pLower = entity.path.toLowerCase();
            final hasExt = supportedVideoExtensions.any((ext) => pLower.endsWith(ext));
            final fileName = entity.path.split(Platform.pathSeparator).last;
            if (hasExt && !seenPaths.contains(entity.path) && !fileName.startsWith('.')) {
              seenPaths.add(entity.path);
              videoFiles.add(entity);
            }
          }
        }
      } catch (e) {
        debugPrint('Error scanning dir $folderPath: $e');
      }
    }

    if (videoFiles.isEmpty) return [];

    // 2. Parse and Group files per Title / Show
    onProgress?.call('Mengelompokkan file berdasarkan judul...');
    final Map<String, _ParsedGroup> groups = {};

    for (final file in videoFiles) {
      final info = _parseVideoFile(file);
      final groupKey = info.groupKey;

      if (!groups.containsKey(groupKey)) {
        groups[groupKey] = _ParsedGroup(
          cleanTitle: info.cleanTitle,
          year: info.year,
          folderPath: file.parent.path,
          isSeries: info.isSeries,
        );
      } else {
        // If any file indicates a series pattern, treat group as series
        if (info.isSeries) {
          groups[groupKey]!.isSeries = true;
        }
      }

      groups[groupKey]!.episodes.add(Episode(
        id: 'ep-${file.path.hashCode.abs()}',
        title: info.episodeLabel,
        videoPath: file.path,
        season: info.season,
        episodeNumber: info.episodeNumber,
        fileSize: file.lengthSync(),
      ));
    }

    // 3. Convert groups into MediaItems and fetch online metadata per title
    final List<MediaItem> resultItems = [];

    for (final entry in groups.entries) {
      final groupKey = entry.key;
      final group = entry.value;

      // Sort episodes naturally by season and episode number
      group.episodes.sort((a, b) {
        if (a.season != b.season) return a.season.compareTo(b.season);
        return a.episodeNumber.compareTo(b.episodeNumber);
      });

      final isShow = group.isSeries || group.episodes.length > 1;
      final primaryVideoPath = group.episodes.isNotEmpty ? group.episodes.first.videoPath : '';

      // Check if we already have saved custom metadata for this title or file
      MediaItem? existingItem;
      if (customMetadataMap.containsKey(groupKey)) {
        try {
          existingItem = MediaItem.fromJson(customMetadataMap[groupKey] as Map<String, dynamic>);
        } catch (_) {}
      } else if (customMetadataMap.containsKey(group.cleanTitle)) {
        try {
          existingItem = MediaItem.fromJson(customMetadataMap[group.cleanTitle] as Map<String, dynamic>);
        } catch (_) {}
      } else if (customMetadataMap.containsKey(primaryVideoPath)) {
        try {
          existingItem = MediaItem.fromJson(customMetadataMap[primaryVideoPath] as Map<String, dynamic>);
        } catch (_) {}
      }

      String defaultDesc;
      if (isShow) {
        defaultDesc = 'Serial TV / Anime (${group.episodes.length} Episode)\nFolder: ${group.folderPath}';
      } else {
        final ep = group.episodes.first;
        final sizeMb = ((ep.fileSize ?? 0) / (1024 * 1024)).toStringAsFixed(1);
        defaultDesc = 'Film Layar Lebar\nUkuran: $sizeMb MB\nLokasi: ${ep.videoPath}';
      }

      var item = MediaItem(
        id: existingItem?.id ?? 'title-${group.cleanTitle.toLowerCase().hashCode.abs()}',
        title: existingItem?.title ?? group.cleanTitle,
        description: (existingItem?.description.isNotEmpty ?? false) ? existingItem!.description : defaultDesc,
        genre: existingItem?.genre ?? (isShow ? 'Serial TV' : 'Film'),
        maturity: existingItem?.maturity ?? '13',
        slug: 'local-title',
        category: isShow ? 'series' : 'films',
        videoPath: primaryVideoPath,
        customThumbnail: existingItem?.customThumbnail,
        year: existingItem?.year ?? group.year,
        rating: existingItem?.rating,
        isManualEdit: existingItem?.isManualEdit ?? false,
        folderPath: group.folderPath,
        isSeries: isShow,
        episodes: group.episodes,
      );

      // 4. Fetch online metadata per Title (TVMaze / AniList) if not already fetched
      if (fetchOnlineMetadata && !item.isManualEdit && item.customThumbnail == null) {
        try {
          onProgress?.call('Mencari info online: ${item.title}');
          final online = await OnlineMetadataService.searchMetadata(item.title);
          if (online != null) {
            item = item.copyWith(
              title: online.title,
              description: online.blurb,
              customThumbnail: online.posterUrl,
              year: online.year ?? item.year,
              rating: online.rating ?? item.rating,
              genre: online.genre ?? item.genre,
            );
            // Cache by groupKey & title
            customMetadataMap[groupKey] = item.toJson();
            customMetadataMap[item.title] = item.toJson();
          }
        } catch (e) {
          debugPrint('Online metadata fetch failed for ${item.title}: $e');
        }
      }

      resultItems.add(item);
    }

    // Save updated metadata cache to config
    config['customMetadata'] = customMetadataMap;
    await _writeConfig(config);

    // Sort alphabetically by title
    resultItems.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    return resultItems;
  }

  /// Parse a video file and extract its show title, season, and episode number
  static _ParsedFileInfo _parseVideoFile(File file) {
    final fileName = file.path.split(Platform.pathSeparator).last;
    final parentDir = file.parent;
    final parentDirName = parentDir.path.split(Platform.pathSeparator).last;
    final grandParentDirName = parentDir.parent.path.split(Platform.pathSeparator).last;

    String cleanName = fileName;
    final dotIndex = cleanName.lastIndexOf('.');
    if (dotIndex != -1) {
      cleanName = cleanName.substring(0, dotIndex);
    }

    int season = 1;
    int episodeNumber = 1;
    bool isSeries = false;
    String? year;
    String cleanTitle = '';

    // Check year pattern (e.g. (2021) or .2021.)
    final yearMatch = RegExp(r'[\(\[\.]?(19\d{2}|20\d{2})[\)\]\.]?').firstMatch(cleanName);
    if (yearMatch != null) {
      year = yearMatch.group(1);
    }

    // Check parent folder for Season pattern (e.g. "Season 2", "S01", "Specials")
    final seasonDirMatch = RegExp(r'^(?:Season|S)\s?(\d{1,2})$', caseSensitive: false).firstMatch(parentDirName);
    if (seasonDirMatch != null) {
      season = int.tryParse(seasonDirMatch.group(1)!) ?? 1;
      isSeries = true;
      // Show title comes from grandParent directory
      cleanTitle = _cleanTitleString(grandParentDirName);
    }

    // 1) Match S01E02 or s1e2
    final seMatch = RegExp(r'[sS](\d{1,2})[eE](\d{1,3})').firstMatch(cleanName);
    if (seMatch != null) {
      season = int.tryParse(seMatch.group(1)!) ?? season;
      episodeNumber = int.tryParse(seMatch.group(2)!) ?? 1;
      isSeries = true;
      if (cleanTitle.isEmpty) {
        cleanTitle = _cleanTitleString(cleanName.substring(0, seMatch.start));
      }
    }

    // 2) Match 1x02
    if (!isSeries) {
      final nxmMatch = RegExp(r'\b(\d{1,2})x(\d{1,3})\b', caseSensitive: false).firstMatch(cleanName);
      if (nxmMatch != null) {
        season = int.tryParse(nxmMatch.group(1)!) ?? season;
        episodeNumber = int.tryParse(nxmMatch.group(2)!) ?? 1;
        isSeries = true;
        if (cleanTitle.isEmpty) {
          cleanTitle = _cleanTitleString(cleanName.substring(0, nxmMatch.start));
        }
      }
    }

    // 3) Match EP01 or Episode 01 or Eps 01
    if (!isSeries) {
      final epMatch = RegExp(r'\b(?:EP|E|Episode|Eps)\s?(\d{1,3})\b', caseSensitive: false).firstMatch(cleanName);
      if (epMatch != null) {
        episodeNumber = int.tryParse(epMatch.group(1)!) ?? 1;
        isSeries = true;
        if (cleanTitle.isEmpty) {
          cleanTitle = _cleanTitleString(cleanName.substring(0, epMatch.start));
        }
      }
    }

    // 4) Match anime bracket e.g. [01] or [01v2]
    if (!isSeries) {
      final bracketMatch = RegExp(r'\[(\d{1,3})(?:v\d)?\]').firstMatch(cleanName);
      if (bracketMatch != null) {
        episodeNumber = int.tryParse(bracketMatch.group(1)!) ?? 1;
        isSeries = true;
      }
    }

    // Fallback title extraction
    if (cleanTitle.isEmpty) {
      // If inside a dedicated show/movie folder (not a drive root)
      if (parentDirName.length > 2 && !parentDirName.contains(':')) {
        cleanTitle = _cleanTitleString(parentDirName);
      } else {
        cleanTitle = _cleanTitleString(cleanName);
      }
    }

    if (cleanTitle.isEmpty) {
      cleanTitle = cleanName;
    }

    final String episodeLabel = isSeries
        ? (season > 1 ? 'Season $season Episode $episodeNumber' : 'Episode $episodeNumber')
        : 'Putar Film';

    final String groupKey = isSeries
        ? 'series_${cleanTitle.toLowerCase().replaceAll(RegExp(r'\s+'), '_')}'
        : 'film_${cleanTitle.toLowerCase().replaceAll(RegExp(r'\s+'), '_')}';

    return _ParsedFileInfo(
      cleanTitle: cleanTitle,
      year: year,
      season: season,
      episodeNumber: episodeNumber,
      episodeLabel: episodeLabel,
      isSeries: isSeries,
      groupKey: groupKey,
    );
  }

  /// Clean title string removing release tags, brackets, and separators
  static String _cleanTitleString(String raw) {
    String text = raw;

    // Remove file extension if present
    final dot = text.lastIndexOf('.');
    if (dot != -1 && text.length - dot <= 5) {
      text = text.substring(0, dot);
    }

    // Remove brackets content like [Erai-raws], [1080p]
    text = text.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    text = text.replaceAll(RegExp(r'\{[^\}]*\}'), ' ');
    text = text.replaceAll(RegExp(r'\([^\)]*\)'), ' ');

    // Normalize dots and underscores
    text = text.replaceAll(RegExp(r'[\._\-]'), ' ');

    // Remove technical quality/codec tokens
    final stopWords = RegExp(
      r'\b(2160p|1080p|720p|480p|4k|uhd|fhd|bluray|blu-ray|web-dl|webdl|webrip|hdrip|dvdrip|h264|x264|h265|x265|hevc|av1|10bit|aac|ac3|dts|remux|yts|yify|rarbg|eztv|repack|proper|complete|sub|dub)\b',
      caseSensitive: false,
    );
    text = text.replaceAll(stopWords, ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Capitalize words
    if (text.isNotEmpty) {
      text = text.split(' ').map((word) {
        if (word.isEmpty) return word;
        return word[0].toUpperCase() + (word.length > 1 ? word.substring(1) : '');
      }).join(' ');
    }

    return text;
  }

  /// Public helper to clean title for single file picker
  static String cleanVideoTitle(String rawFileName) {
    return _cleanTitleString(rawFileName);
  }
}

class _ParsedFileInfo {
  final String cleanTitle;
  final String? year;
  final int season;
  final int episodeNumber;
  final String episodeLabel;
  final bool isSeries;
  final String groupKey;

  _ParsedFileInfo({
    required this.cleanTitle,
    this.year,
    required this.season,
    required this.episodeNumber,
    required this.episodeLabel,
    required this.isSeries,
    required this.groupKey,
  });
}

class _ParsedGroup {
  final String cleanTitle;
  final String? year;
  final String folderPath;
  bool isSeries;
  final List<Episode> episodes = [];

  _ParsedGroup({
    required this.cleanTitle,
    this.year,
    required this.folderPath,
    this.isSeries = false,
  });
}
