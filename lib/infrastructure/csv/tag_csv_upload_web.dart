import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Opens a file picker and returns the CSV content as a String, or null if cancelled.
Future<String?> pickCsvFile() async {
  final completer = Completer<String?>();

  final input = web.document.createElement('input') as web.HTMLInputElement;
  input.type = 'file';
  input.accept = '.csv,text/csv';
  input.style.display = 'none';

  input.onChange.listen((event) {
    final files = input.files;
    if (files == null || files.length == 0) {
      completer.complete(null);
      return;
    }
    final file = files.item(0)!;
    final reader = web.FileReader();
    reader.onLoadEnd.listen((event) {
      final result = reader.result;
      if (result != null) {
        completer.complete((result as JSString).toDart);
      } else {
        completer.complete(null);
      }
    });
    reader.readAsText(file);
  });

  web.document.body!.appendChild(input);
  input.click();
  web.document.body!.removeChild(input);

  return completer.future;
}
