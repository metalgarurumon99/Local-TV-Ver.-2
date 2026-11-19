import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

class DebugLogger {
  static File? _logFile;
  static Future<void> _writeQueue = Future<void>.value();
  static const int _maxLogBytes = 2 * 1024 * 1024; // 2 MB cap

  static File _resolveLogFile() {
    if (_logFile != null) return _logFile!;
    try {
      final dir = Directory('.cache/logs');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _logFile = File('${dir.path}${Platform.pathSeparator}debug_dismiss.log');
    } catch (_) {
      _logFile = File('debug_dismiss.log');
    }
    return _logFile!;
  }

  static void log(String message) {
    if (!kDebugMode) return;
    final now = DateTime.now().toIso8601String();
    final line = '[$now] $message\r\n';
    _writeQueue = _writeQueue.then((_) async {
      try {
        final file = _resolveLogFile();
        if (await file.exists() && await file.length() > _maxLogBytes) {
          await file.writeAsString(line, mode: FileMode.write, flush: false);
        } else {
          await file.writeAsString(line, mode: FileMode.append, flush: false);
        }
      } catch (_) {}
    });
  }

  static void clear() {
    if (!kDebugMode) return;
    _writeQueue = _writeQueue.then((_) async {
      try {
        final file = _resolveLogFile();
        if (await file.exists()) await file.delete();
      } catch (_) {}
    });
  }
}
