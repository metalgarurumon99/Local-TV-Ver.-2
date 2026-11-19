import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_tv/models/media_item.dart';
import 'package:local_tv/services/chapter_service.dart';
import 'package:local_tv/services/library_service.dart';
import 'package:local_tv/services/trickplay_service.dart';
import 'package:local_tv/services/watch_history_service.dart';
import 'package:local_tv/utils/media_ui_helpers.dart';

void main() {
  group('ChapterService.parseChaptersFromFfmpegOutput', () {
    test('parses chapters and does NOT overwrite last chapter title with Stream metadata', () {
      const sampleStderr = '''
Input #0, matroska,webm, from 'sample.mkv':
  Chapters:
    Chapter #0:0: start 0.000000, end 90.500000
      Metadata:
        title           : Opening
    Chapter #0:1: start 90.500000, end 1320.000000
      Metadata:
        title           : Episode Content
    Chapter #0:2: start 1320.000000, end 1410.000000
      Metadata:
        title           : Ending
  Stream #0:0(jpn): Video: hevc
    Metadata:
      title           : Japanese 1080p
  Stream #0:1(eng): Subtitle: ass
    Metadata:
      title           : English Signs & Songs
''';

      final chapters = ChapterService.parseChaptersFromFfmpegOutput(sampleStderr);
      expect(chapters.length, 3);
      expect(chapters[0].title, 'Opening');
      expect(chapters[0].isIntro, isTrue);
      expect(chapters[0].start, Duration.zero);
      expect(chapters[0].end, const Duration(milliseconds: 90500));

      expect(chapters[1].title, 'Episode Content');
      expect(chapters[1].isIntro, isFalse);

      // Must NOT be overwritten by "English Signs & Songs" or "Japanese 1080p"
      expect(chapters[2].title, 'Ending');
    });
  });

  group('TrickplayData.getTileRect', () {
    test('maps positions accurately across short, normal, and >100min videos', () {
      // 3-hour movie (10800s -> intervalSec = 108s per tile for 10x10)
      final longMovie = TrickplayData(
        imagePath: 'sprite.jpg',
        totalDuration: const Duration(hours: 3),
      );
      expect(longMovie.intervalSec, closeTo(108.0, 0.01));
      expect(longMovie.getTileRect(Duration.zero), const Rect.fromLTWH(0, 0, 160, 90));
      // Near end of 3-hour movie should reach tile index 99 (col 9, row 9)
      expect(
        longMovie.getTileRect(const Duration(hours: 2, minutes: 59)),
        const Rect.fromLTWH(9 * 160, 9 * 90, 160, 90),
      );

      // Short 30s clip (intervalSec = 0.3s)
      final shortClip = TrickplayData(
        imagePath: 'sprite_short.jpg',
        totalDuration: const Duration(seconds: 30),
      );
      expect(shortClip.intervalSec, closeTo(0.3, 0.01));
      // Midpoint 15s -> tile index 50 (col 0, row 5)
      expect(
        shortClip.getTileRect(const Duration(seconds: 15)),
        const Rect.fromLTWH(0, 5 * 90, 160, 90),
      );
    });
  });

  group('LocalLibraryService.cleanVideoTitle', () {
    test('preserves titles with dots like Dr. No and Mr. Robot while stripping video extensions', () {
      expect(LocalLibraryService.cleanVideoTitle('Dr. No (1962).mkv'), 'Dr No');
      expect(LocalLibraryService.cleanVideoTitle('Mr. Robot.mp4'), 'Mr Robot');
      expect(LocalLibraryService.cleanVideoTitle('[SubsPlease] Frieren - 1080p.mkv'), 'Frieren');
    });

    test('parses underscore-dash anime episode numbers like [DB]Azumanga Daiou_-_02_(...)', () {
      for (int i = 1; i <= 5; i++) {
        final epStr = i.toString().padLeft(2, '0');
        final parsed = LocalLibraryService.parseVideoFileMetadata(
          r'I:\New folder\Anime\Azumanga Daiou\[DB]Azumanga Daiou_-_'
          '$epStr'
          r'_(Dual Audio_10bit_BD1080p_x265).mkv',
        );
        expect(parsed.isSeries, isTrue);
        expect(parsed.season, 1);
        expect(parsed.episodeNumber, i);
        expect(parsed.cleanTitle, 'Azumanga Daiou');
      }

      // Standard space-dash & SxxExx & underscore-no-dash
      final std = LocalLibraryService.parseVideoFileMetadata(
        r'D:\Anime\Frieren\[SubsPlease] Frieren - 14 (1080p).mkv',
      );
      expect(std.episodeNumber, 14);
      expect(std.isSeries, isTrue);

      final sxe = LocalLibraryService.parseVideoFileMetadata(
        r'D:\Shows\Breaking Bad\Breaking.Bad.S02E09.1080p.mkv',
      );
      expect(sxe.season, 2);
      expect(sxe.episodeNumber, 9);
      expect(sxe.isSeries, isTrue);
    });
  });

  group('MediaItem', () {
    test('matchesSearchQuery is case-insensitive and isLocalImage rejects empty strings', () {
      const item = MediaItem(
        id: 'm1',
        title: 'Attack on Titan',
        description: 'Humanity fights Titans',
        genre: 'Action, Anime',
        maturity: '16',
        category: 'series',
        customThumbnail: '',
      );

      expect(item.matchesSearchQuery('ATTACK'), isTrue);
      expect(item.matchesSearchQuery('titan'), isTrue);
      expect(item.matchesSearchQuery('comedy'), isFalse);
      expect(item.isLocalImage, isFalse);
    });

    test('fromJson cleans mojibake without corrupting em-dash or ellipsis', () {
      final item = MediaItem.fromJson({
        'id': 'm2',
        'title': 'Test â€” Part 1â€¦',
        'description': 'A â€™greatâ€™ film',
        'genre': 'Drama',
        'maturity': '13',
        'category': 'films',
      });

      expect(item.title, 'Test — Part 1...');
      expect(item.description, "A 'great' film");
    });
  });

  group('WatchHistoryEntry', () {
    test('computes progress, remaining time, and roundtrips JSON', () {
      final entry = WatchHistoryEntry(
        mediaId: 'series-1',
        mediaTitle: 'Demo Series',
        videoPath: r'D:\Videos\Demo\E01.mkv',
        thumbnailPath: '',
        category: 'series',
        isSeries: true,
        seasonNumber: 1,
        episodeNumber: 1,
        positionMs: 30 * 60 * 1000,
        durationMs: 120 * 60 * 1000,
        lastWatchedAt: DateTime(2026, 11, 19),
      );

      expect(entry.progress, closeTo(0.25, 0.001));
      expect(entry.formattedRemainingTime, 'Sisa 1 j 30 m');

      final roundtrip = WatchHistoryEntry.fromJson(entry.toJson());
      expect(roundtrip.mediaId, entry.mediaId);
      expect(roundtrip.positionMs, entry.positionMs);
      expect(roundtrip.durationMs, entry.durationMs);
    });
  });

  group('MediaUiHelpers', () {
    test('resolveVideoResolutionLabel avoids false positives like birthday/SDCard', () {
      expect(
        MediaUiHelpers.resolveVideoResolutionLabel(
          const MediaItem(
            id: '1',
            title: 'Birthday Party',
            description: '',
            genre: '',
            maturity: '13',
            category: 'films',
            videoPath: r'D:\SDCard\birthday_party.mkv',
          ),
        ),
        '1080p',
      );
      expect(
        MediaUiHelpers.resolveVideoResolutionLabel(
          const MediaItem(
            id: '2',
            title: 'Dune',
            description: '',
            genre: '',
            maturity: '13',
            category: 'films',
            videoPath: r'D:\Movies\Dune.2160p.WEB-DL.mkv',
          ),
        ),
        '4K',
      );
    });

    test('buildEpisodeMediaItem preserves backdrop2Url, logoUrl, and series metadata', () {
      const ep = Episode(
        id: 'ep-1',
        title: 'Pilot',
        videoPath: r'D:\Series\Show\E01.mkv',
        season: 2,
        episodeNumber: 1,
      );
      const parent = MediaItem(
        id: 'series-1',
        title: 'My Show',
        description: 'Desc',
        genre: 'Sci-Fi',
        maturity: '16',
        category: 'series',
        backdropUrl: 'bg1.jpg',
        backdrop2Url: 'bg2.jpg',
        logoUrl: 'logo.png',
        isSeries: true,
        episodes: [ep],
      );
      final built = MediaUiHelpers.buildEpisodeMediaItem(parent: parent, episode: ep);
      expect(built.seriesId, 'series-1');
      expect(built.seriesTitle, 'My Show');
      expect(built.backdrop2Url, 'bg2.jpg');
      expect(built.logoUrl, 'logo.png');
      expect(built.seasonNumber, 2);
      expect(built.episodeNumber, 1);
    });
  });
}
