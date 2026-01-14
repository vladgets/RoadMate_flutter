import 'dart:io';
import 'package:path_provider/path_provider.dart';

class MemoryStore {
  static const String _fileName = 'roadmate_memory.txt';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<String> readAll() async {
    final f = await _file();
    if (!await f.exists()) return '';
    return f.readAsString();
  }

  /// Overwrite the entire memory file with the provided text.
  /// Normalizes line endings and ensures a trailing newline when non-empty.
  static Future<void> writeAll(String text) async {
    final f = await _file();

    // Normalize Windows CRLF to LF for consistency
    var normalized = text.replaceAll('\r\n', '\n');

    // Ensure trailing newline if file is not empty
    if (normalized.trim().isNotEmpty && !normalized.endsWith('\n')) {
      normalized = '$normalized\n';
    }

    await f.writeAsString(normalized, mode: FileMode.write, flush: true);
  }

  static Future<void> appendLine(String text) async {
    final line = _sanitizeOneLine(text);
    final f = await _file();
    await f.writeAsString('$line\n', mode: FileMode.append, flush: true);
  }

  static Future<void> overwrite(String text) async {
    final f = await _file();
    await f.writeAsString(text, mode: FileMode.write, flush: true);
  }

  static Future<void> clear() async {
    final f = await _file();
    if (await f.exists()) {
      await f.writeAsString('', mode: FileMode.write, flush: true);
    }
  }

  static String _sanitizeOneLine(String s) {
    var x = s.replaceAll('\r', ' ').replaceAll('\n', ' ');
    x = x.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (x.isEmpty) return '(empty)';
    if (x.length > 500) x = x.substring(0, 500).trimRight();
    return x;
  }

  /// Tool-compatible wrapper: append a fact into memory
  /// Expected args: { "text": "..." }
  static Future<Map<String, dynamic>> toolAppend(dynamic args) async {
    final text = (args is Map && args['text'] is String)
        ? args['text'] as String
        : '';

    await appendLine(text);

    return {
      'ok': true,
      'stored': _sanitizeOneLine(text),
    };
  }

  /// Tool-compatible wrapper: read full memory contents
  static Future<Map<String, dynamic>> toolRead() async {
    final text = await readAll();

    final lines = text.isEmpty
        ? 0
        : text.split('\n').where((l) => l.trim().isNotEmpty).length;

    return {
      'text': text,
      'lines': lines,
      'bytes': text.codeUnits.length,
    };
  }

}
