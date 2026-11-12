import 'dart:io';
import 'package:flutter/foundation.dart';

class DebugLogger {
  static File? _logFile;

  static File _resolveLogFile() {
    if (_logFile != null) return _logFile!;
    try {
      final dir = Directory('.cache/logs');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _logFile = File('${dir.path}/debug_dismiss.log');
    } catch (_) {
      _logFile = File('debug_dismiss.log');
    }
    return _logFile!;
  }

  static void log(String message) {
    if (!kDebugMode) return;
    try {
      final now = DateTime.now().toIso8601String();
      final line = '[$now] $message\r\n';
      // Non-blocking asynchronous append without flush: true
      _resolveLogFile().writeAsString(line, mode: FileMode.append, flush: false).catchError((_) => _resolveLogFile());
    } catch (_) {}
  }

  static void clear() {
    if (!kDebugMode) return;
    try {
      final file = _resolveLogFile();
      if (file.existsSync()) file.delete().catchError((_) => file);
    } catch (_) {}
  }
}
