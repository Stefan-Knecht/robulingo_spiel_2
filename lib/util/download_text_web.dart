import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_util' as js_util;

Future<void> downloadTextFile({required String filename, required String contents}) async {
  final bytes = utf8.encode(contents);
  // Prefer the File System Access API on Chromium browsers. This allows overwriting
  // the previously chosen file without creating multiple downloaded copies.
  // Falls back to a standard download if unavailable.
  if (js_util.hasProperty(html.window, 'showSaveFilePicker')) {
    try {
      final handle = await _getOrPickHandle(filename);
      final writable = await js_util.promiseToFuture(
        js_util.callMethod(handle, 'createWritable', const []),
      );
      await js_util.promiseToFuture(js_util.callMethod(writable, 'write', [bytes]));
      await js_util.promiseToFuture(js_util.callMethod(writable, 'close', const []));
      return;
    } catch (_) {
      // fall through to classic download
    }
  }

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

final Map<String, dynamic> _savedHandlesByName = {};

Future<dynamic> _getOrPickHandle(String filename) async {
  final existing = _savedHandlesByName[filename];
  if (existing != null) {
    return existing;
  }
  final options = <String, dynamic>{
    'suggestedName': filename,
    'types': [
      {
        'description': 'Text',
        'accept': {
          'text/plain': ['.txt', '.log', '.ndjson']
        }
      }
    ],
  };
  final handle = await js_util.promiseToFuture(
    js_util.callMethod(html.window, 'showSaveFilePicker', [options]),
  );
  _savedHandlesByName[filename] = handle;
  return handle;
}
