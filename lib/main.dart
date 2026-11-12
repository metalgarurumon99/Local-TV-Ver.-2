import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'models/media_item.dart';
import 'services/library_service.dart';
import 'services/thumbnail_service.dart';
import 'services/watch_history_service.dart';
import 'views/browse_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Increase Flutter image cache so poster thumbnails stay warm in memory while scrolling at 120Hz/144Hz
  PaintingBinding.instance.imageCache.maximumSize = 1500;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 512 << 20; // 512 MB

  // Initialize MediaKit (LibMPV engine for desktop)
  MediaKit.ensureInitialized();

  // Initialize WindowManager & preload cached library in parallel for 0ms seamless startup
  final results = await Future.wait<dynamic>([
    windowManager.ensureInitialized(),
    LocalThumbnailService.init(),
    LocalLibraryService.getConnectedFolders(),
    LocalLibraryService.getCachedItems(),
    WatchHistoryService.getRecentHistory(),
  ]);

  final List<String> initialFolders = results[2] as List<String>;
  final List<MediaItem> initialItems = results[3] as List<MediaItem>;
  final List<WatchHistoryEntry> initialHistory = results[4] as List<WatchHistoryEntry>;

  // Pre-warm file existence cache for local poster, backdrop, logo, and video thumbnails
  for (final item in initialItems) {
    if (item.customThumbnail != null &&
        item.customThumbnail!.isNotEmpty &&
        !item.isNetworkImage) {
      LocalThumbnailService.fileExistsCached(item.customThumbnail);
    }
    if (item.backdropUrl != null &&
        item.backdropUrl!.isNotEmpty &&
        !item.backdropUrl!.startsWith('http')) {
      LocalThumbnailService.fileExistsCached(item.backdropUrl);
    }
    if (item.logoUrl != null &&
        item.logoUrl!.isNotEmpty &&
        !item.logoUrl!.startsWith('http')) {
      LocalThumbnailService.fileExistsCached(item.logoUrl);
    }
    final vPath = item.videoPath.isNotEmpty
        ? item.videoPath
        : (item.episodes.isNotEmpty ? item.episodes.first.videoPath : '');
    if (vPath.isNotEmpty) {
      LocalThumbnailService.hasThumbnail(vPath);
    }
  }

  const windowOptions = WindowOptions(
    size: Size(1280, 720),
    minimumSize: Size(960, 580),
    center: true,
    title: 'Local TV Ver. 2',
    backgroundColor: Color(0xFF111111),
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );

  runApp(
    LocalTvApp(
      initialFolders: initialFolders,
      initialItems: initialItems,
      initialHistory: initialHistory,
    ),
  );

  // Self-healing maintenance in background (no delay to UI startup)
  unawaited(Future.microtask(() async {
    await LocalLibraryService.cleanOrphanedCache();
  }));

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.maximize();
    await windowManager.show();
    await windowManager.focus();
  });
}

class LocalTvApp extends StatelessWidget {
  final List<String> initialFolders;
  final List<MediaItem> initialItems;
  final List<WatchHistoryEntry> initialHistory;

  const LocalTvApp({
    super.key,
    this.initialFolders = const [],
    this.initialItems = const [],
    this.initialHistory = const [],
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local TV Ver. 2',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const SmoothDesktopScrollBehavior(),
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF111111),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE50914),
          surface: Color(0xFF181818),
        ),
      ),
      home: BrowseScreen(
        key: const ValueKey('browse_screen'),
        initialFolders: initialFolders,
        initialItems: initialItems,
        initialHistory: initialHistory,
      ),
    );
  }
}

/// Clean desktop scroll behavior without artificial mouse dragging or unnatural springs
class SmoothDesktopScrollBehavior extends MaterialScrollBehavior {
  const SmoothDesktopScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }
}
