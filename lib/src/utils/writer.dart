// Shared output helpers.

import 'dart:io';

import 'package:path/path.dart' as p;

/// Writes [content] to [path], creating parent directories as needed.
void writeTextFile(String path, String content) {
  final parent = p.dirname(path);
  Directory(parent).createSync(recursive: true);
  File(path).writeAsStringSync(content);
}

/// Collects all markdown files under [directory] (non-recursive), returning
/// their contents concatenated, or an empty string when none exist.
String readMarkdownBodies(String directory) {
  final dir = Directory(directory);
  if (!dir.existsSync()) return '';
  final buffer = StringBuffer();
  for (final entity in dir.listSync().whereType<File>()) {
    if (p.extension(entity.path) == '.md') {
      buffer.writeln(entity.readAsStringSync());
    }
  }
  return buffer.toString();
}
