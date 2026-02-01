import 'dart:io';

import 'package:path_provider/path_provider.dart';

class LogStorage {
  static const String _fileName = 'events.ndjson';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    final logsDir = Directory('${dir.path}/logs');
    await logsDir.create(recursive: true);
    return File('${logsDir.path}/$_fileName');
  }

  Future<void> init() async {
    await _file();
  }

  Future<void> appendLine(String line) async {
    final cleaned = line.trimRight();
    if (cleaned.isEmpty) return;
    final f = await _file();
    await f.writeAsString('$cleaned\n', mode: FileMode.append, flush: false);
  }

  Future<List<String>> readLines() async {
    final f = await _file();
    if (!await f.exists()) return <String>[];
    return f.readAsLines();
  }

  Future<bool> exists() async {
    final f = await _file();
    return f.exists();
  }

  Future<void> clear() async {
    final f = await _file();
    if (await f.exists()) {
      await f.delete();
    }
  }
}
