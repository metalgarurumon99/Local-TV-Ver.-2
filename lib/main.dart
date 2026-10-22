import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'views/browse_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize MediaKit (LibMPV engine for desktop)
  MediaKit.ensureInitialized();

  // Initialize WindowManager for desktop fullscreen & window controls
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    minimumSize: Size(960, 580),
    center: true,
    title: 'Local TV Ver. 2',
    backgroundColor: Color(0xFF111111),
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const LocalTvApp());
}

class LocalTvApp extends StatelessWidget {
  const LocalTvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local TV Ver. 2',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF111111),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE50914),
          surface: Color(0xFF181818),
        ),
      ),
      home: const BrowseScreen(),
    );
  }
}
