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

  static File get _configFile {
    return File('library_config.json');
  }

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

  /// Save manual or custom metadata for a specific video path
  static Future<void> saveCustomMetadata(String videoPath, MediaItem item) async {
    final config = await _readConfig();
    final Map<String, dynamic> metaMap = Map<String, dynamic>.from(
      config['customMetadata'] as Map<String, dynamic>? ?? {},
    );

    metaMap[videoPath] = item.toJson();
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

  /// Scan all connected folders and return enriched media items
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

    final List<MediaItem> allItems = [];
    final Set<String> seenPaths = {};

    for (final folderPath in folders) {
      final dir = Directory(folderPath);
      if (!await dir.exists()) continue;

      onProgress?.call('Memindai folder: $folderPath');

      try {
        final entities = dir.listSync(recursive: true, followLinks: false);

        for (final entity in entities) {
          if (entity is File) {
            final pathLower = entity.path.toLowerCase();
            final hasVideoExt = supportedVideoExtensions.any((ext) => pathLower.endsWith(ext));

            final fileName = entity.uri.pathSegments.isNotEmpty
                ? entity.uri.pathSegments.last
                : entity.path.split(Platform.pathSeparator).last;

            if (hasVideoExt && !seenPaths.contains(entity.path) && !fileName.startsWith('.')) {
              seenPaths.add(entity.path);

              // 1. Check if we already have saved/manual metadata for this file
              if (customMetadataMap.containsKey(entity.path)) {
                try {
                  final savedJson = customMetadataMap[entity.path] as Map<String, dynamic>;
                  final item = MediaItem.fromJson(savedJson);
                  allItems.add(item);
                  continue;
                } catch (e) {
                  debugPrint('Error reading custom metadata for ${entity.path}: $e');
                }
              }

              // 2. Otherwise create item from file name
              final cleanedTitle = cleanVideoTitle(fileName);
              final ext = fileName.contains('.') ? fileName.split('.').last.toUpperCase() : 'VIDEO';

              var item = MediaItem(
                id: 'local-${entity.path.hashCode.abs()}',
                title: cleanedTitle,
                description: 'File: $fileName\nFormat: $ext\nLokasi: ${entity.path}',
                genre: 'Koleksi Lokal',
                maturity: '13',
                slug: 'local-video',
                category: 'films',
                videoPath: entity.path,
                folderPath: folderPath,
              );

              // 3. Online metadata fetch (if online & enabled)
              if (fetchOnlineMetadata) {
                try {
                  onProgress?.call('Mencari info online: $cleanedTitle');
                  final online = await OnlineMetadataService.searchMetadata(cleanedTitle);
                  if (online != null) {
                    item = item.copyWith(
                      title: online.title,
                      description: online.blurb,
                      customThumbnail: online.posterUrl,
                      year: online.year,
                      rating: online.rating,
                      genre: online.genre ?? item.genre,
                    );
                    // Cache the fetched metadata so we don't query every time
                    customMetadataMap[entity.path] = item.toJson();
                  }
                } catch (e) {
                  debugPrint('Online metadata fetch failed for $cleanedTitle: $e');
                }
              }

              allItems.add(item);
            }
          }
        }
      } catch (e) {
        debugPrint('Error scanning folder $folderPath: $e');
      }
    }

    // Update config with any newly fetched metadata cache
    config['customMetadata'] = customMetadataMap;
    await _writeConfig(config);

    // Sort alphabetically by title
    allItems.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    return allItems;
  }

  /// Clean raw movie/series filenames into readable titles
  static String cleanVideoTitle(String rawFileName) {
    String name = rawFileName;
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex != -1) {
      name = name.substring(0, dotIndex);
    }

    name = name.replaceAll(RegExp(r'[\._\-]'), ' ');

    final tagsPattern = RegExp(
      r'\b(1080p|720p|2160p|4k|uhd|bluray|blu-ray|web-dl|webrip|hdrip|dvdrip|h264|x264|h265|x265|hevc|aac|ac3|dts|remux|yts|yify|rarbg|psa|eztv|proper|repack|complete|extended|multi|sub|dub|hdr)\b',
      caseSensitive: false,
    );
    name = name.replaceAll(tagsPattern, ' ');
    name = name.replaceAll(RegExp(r'[\[\]\{\}]'), ' ');
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (name.isNotEmpty) {
      name = name.split(' ').map((word) {
        if (word.isEmpty) return word;
        return word[0].toUpperCase() + (word.length > 1 ? word.substring(1) : '');
      }).join(' ');
    }

    return name.isEmpty ? rawFileName : name;
  }
}
