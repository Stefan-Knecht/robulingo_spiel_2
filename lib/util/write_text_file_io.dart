import 'dart:io';

Future<void> writeTextFile(String path, String contents) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  await f.writeAsString(contents, flush: true);
}

