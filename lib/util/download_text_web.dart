import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_util' as js_util;

Future<void> downloadTextFile({required String filename, required String contents}) {
  // Important: keep this function free of async/await so browsers treat it as a
  // "user gesture" call chain when invoked from a button press.
  //
  // Prefer the File System Access API (Chromium) to overwrite the same file.
  // Fall back to classic blob download otherwise.
  if (js_util.hasProperty(html.window, 'showSaveFilePicker')) {
    final existing = _savedHandlesByName[filename];
    if (existing != null) {
      return _writeToHandle(existing, contents).catchError((_) {
        _classicDownload(filename, contents);
      });
    }

    final promise =
        js_util.callMethod(html.window, 'showSaveFilePicker', [_pickerOptions(filename)]);
    return js_util.promiseToFuture(promise).then((handle) {
      _savedHandlesByName[filename] = handle;
      return _writeToHandle(handle, contents);
    }).catchError((_) {
      // If the picker is blocked/canceled, still try a classic download.
      _classicDownload(filename, contents);
    });
  }

  _classicDownload(filename, contents);
  return Future.value();
}

final Map<String, dynamic> _savedHandlesByName = {};

Map<String, dynamic> _pickerOptions(String filename) {
  return <String, dynamic>{
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
}

Future<void> _writeToHandle(dynamic handle, String contents) {
  final createWritablePromise =
      js_util.callMethod(handle, 'createWritable', const []);
  return js_util.promiseToFuture(createWritablePromise).then((writable) {
    final writePromise = js_util.callMethod(writable, 'write', [contents]);
    return js_util.promiseToFuture(writePromise).then((_) {
      final closePromise = js_util.callMethod(writable, 'close', const []);
      return js_util.promiseToFuture(closePromise);
    });
  });
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
