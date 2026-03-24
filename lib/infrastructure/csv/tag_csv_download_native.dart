import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<void> downloadCsvFile(String csvContent, String fileName) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$fileName');
  // Write with BOM for Excel compatibility
  await file.writeAsString('\uFEFF$csvContent', flush: true);
}
