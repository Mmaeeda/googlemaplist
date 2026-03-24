import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<void> downloadCsvFile(String csvContent, String fileName) async {
  // Add BOM for Excel compatibility with Japanese characters
  final bom = utf8.encode('\uFEFF');
  final contentBytes = utf8.encode(csvContent);
  final allBytes = Uint8List.fromList([...bom, ...contentBytes]);

  final blob = web.Blob(
    [allBytes.toJS].toJS,
    web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
  );

  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = url;
  anchor.download = fileName;
  anchor.style.display = 'none';
  web.document.body!.appendChild(anchor);
  anchor.click();
  web.document.body!.removeChild(anchor);
  web.URL.revokeObjectURL(url);
}
