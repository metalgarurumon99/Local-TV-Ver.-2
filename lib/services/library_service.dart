import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import '../models/media_item.dart';

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

  /// Get the saved folder path from disk config
  static Future<String?> getSavedFolderPath() async {
    try {
      if (await _configFile.exists()) {
        final content = await _configFile.readAsString();
        final Map<String, dynamic> data = jsonDecode(content);
        return data['folderPath'] as String?;
      }
    } catch (e) {
      debugPrint('Error reading library config: $e');
    }
    return null;
  }

  /// Save folder path and cached items to disk
  static Future<void> saveFolderPath(String folderPath, List<MediaItem> items) async {
    try {
      final data = {
        'folderPath': folderPath,
        'itemCount': items.length,
        'lastScanned': DateTime.now().toIso8601String(),
      };
      await _configFile.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('Error saving library config: $e');
    }
  }

  /// Open native Windows folder picker dialog and scan
  static Future<List<MediaItem>> pickFolderAndScan() async {
    try {
      final selectedDirectory = await FilePicker.getDirectoryPath(
        dialogTitle: 'Pilih Folder Koleksi Film / Serial Anda',
      );

      if (selectedDirectory == null || selectedDirectory.isEmpty) {
        return [];
      }

      final items = await scanFolder(selectedDirectory);
      await saveFolderPath(selectedDirectory, items);
      return items;
    } catch (e) {
      debugPrint('Error picking folder: $e');
      return [];
    }
  }

  /// Scan a folder path on disk for video files
  static Future<List<MediaItem>> scanFolder(String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) {
      return [];
    }

    final List<MediaItem> items = [];
    final seenPaths = <String>{};

    try {
      final entities = dir.listSync(recursive: true, followLinks: false);

      for (final entity in entities) {
        if (entity is File) {
          final pathLower = entity.path.toLowerCase();
          final hasVideoExt = supportedVideoExtensions.any((ext) => pathLower.endsWith(ext));

          // Exclude sample files or hidden files
          final fileName = entity.uri.pathSegments.isNotEmpty
              ? entity.uri.pathSegments.last
              : entity.path.split(Platform.pathSeparator).last;

          if (hasVideoExt && !seenPaths.contains(entity.path) && !fileName.startsWith('.')) {
            seenPaths.add(entity.path);

            final cleanedTitle = cleanVideoTitle(fileName);
            final ext = fileName.contains('.') ? fileName.split('.').last.toUpperCase() : 'VIDEO';

            items.add(
              MediaItem(
                id: 'local-${entity.path.hashCode.abs()}',
                title: cleanedTitle,
                description: 'File: $fileName\nFormat: $ext\nLokasi: ${entity.path}',
                genre: 'Koleksi Lokal',
                maturity: '13',
                slug: 'local-video',
                category: 'films',
                videoPath: entity.path,
                customThumbnail: null,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error scanning folder: $e');
    }

    // Sort alphabetically by title
    items.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    return items;
  }

  /// Clean raw movie/series filenames into readable titles
  static String cleanVideoTitle(String rawFileName) {
    // 1. Remove extension
    String name = rawFileName;
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex != -1) {
      name = name.substring(0, dotIndex);
    }

    // 2. Replace dots, underscores, hyphens with spaces
    name = name.replaceAll(RegExp(r'[\._\-]'), ' ');

    // 3. Remove common release tags and resolutions
    final tagsPattern = RegExp(
      r'\b(1080p|720p|2160p|4k|uhd|bluray|blu-ray|web-dl|webrip|hdrip|dvdrip|h264|x264|h265|x265|hevc|aac|ac3|dts|remux|yts|yify|rarbg|psa|eztv|proper|repack|complete|extended|multi|sub|dub)\b',
      caseSensitive: false,
    );
    name = name.replaceAll(tagsPattern, ' ');

    // 4. Remove extra brackets and square brackets
    name = name.replaceAll(RegExp(r'[\[\]\{\}]'), ' ');

    // 5. Condense multiple spaces into one and trim
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();

    // 6. Capitalize words
    if (name.isNotEmpty) {
      name = name.split(' ').map((word) {
        if (word.isEmpty) return word;
        return word[0].toUpperCase() + (word.length > 1 ? word.substring(1) : '');
      }).join(' ');
    }

    return name.isEmpty ? rawFileName : name;
  }
}
