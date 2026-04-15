import 'dart:convert';
import 'dart:html' as html;

Future<void> downloadTextFile(
    {required String filename, required String contents}) {
  // Always use classic browser downloads so the file lands in the browser's
  // configured download location instead of going through the save-file picker.
  _classicDownload(filename, contents);
  return Future.value();
}

void _classicDownload(String filename, String contents) {
  final bytes = utf8.encode(contents);
  final blob = html.Blob(<dynamic>[bytes], 'text/plain;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  try {
    final anchor = html.AnchorElement(href: url)
      ..download = filename
      ..style.display = 'none';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
  } finally {
    html.Url.revokeObjectUrl(url);
  }
}
