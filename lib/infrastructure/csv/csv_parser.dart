import 'dart:convert';

import 'package:csv/csv.dart';

import '../../domain/models/raw_place_record.dart';
import '../logging/sync_logger.dart';

class CsvParseResult {
  final List<RawPlaceRecord> records;
  final int skippedRowCount;
  final List<String> headers;

  const CsvParseResult({
    required this.records,
    required this.skippedRowCount,
    required this.headers,
  });
}

class CsvParser {
  final SyncLogger _logger;

  CsvParser(this._logger);

  /// Parse CSV content bytes into RawPlaceRecords.
  CsvParseResult parse(List<int> bytes, {String? fileName}) {
    final content = _decodeContent(bytes);
    return parseString(content, fileName: fileName);
  }

  /// Parse CSV content string into RawPlaceRecords.
  CsvParseResult parseString(String content, {String? fileName}) {
    final records = <RawPlaceRecord>[];
    var skippedCount = 0;

    final rows = const CsvToListConverter(
      shouldParseNumbers: false,
      allowInvalid: true,
    ).convert(content);

    if (rows.isEmpty) {
      _logger.warn('CSV is empty', {'fileName': fileName});
      return CsvParseResult(
        records: [],
        skippedRowCount: 0,
        headers: [],
      );
    }

    // First row is headers
    final headers =
        rows.first.map((e) => _normalizeHeader(e.toString())).toList();

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];

      // Skip empty rows
      if (row.isEmpty || (row.length == 1 && row.first.toString().isEmpty)) {
        skippedCount++;
        continue;
      }

      try {
        final fields = <String, String>{};
        for (var j = 0; j < headers.length && j < row.length; j++) {
          final value = row[j].toString().trim();
          if (value.isNotEmpty) {
            fields[headers[j]] = value;
          }
        }

        if (fields.isEmpty) {
          skippedCount++;
          continue;
        }

        records.add(RawPlaceRecord(
          rowNumber: i + 1, // 1-based, +1 for header row
          fields: fields,
        ));
      } catch (e) {
        _logger.warn('Skipping invalid row', {
          'fileName': fileName,
          'rowNumber': i + 1,
          'error': e.toString(),
        });
        skippedCount++;
      }
    }

    _logger.info('csv_parse_completed', {
      'fileName': fileName,
      'totalRows': rows.length - 1,
      'parsedRecords': records.length,
      'skippedRows': skippedCount,
    });

    return CsvParseResult(
      records: records,
      skippedRowCount: skippedCount,
      headers: headers,
    );
  }

  /// Decode bytes handling BOM and various encodings.
  String _decodeContent(List<int> bytes) {
    // Remove UTF-8 BOM if present
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      bytes = bytes.sublist(3);
    }

    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Normalize header names to a canonical form.
  /// Preserves Unicode characters (Japanese etc.) while cleaning whitespace.
  /// Note: Dart's \w with unicode:true is still ASCII-only [a-zA-Z0-9_],
  /// so we use \p{L}\p{N} to match all Unicode letters and numbers.
  String _normalizeHeader(String header) {
    return header
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^\p{L}\p{N}_]', unicode: true), '');
  }
}
