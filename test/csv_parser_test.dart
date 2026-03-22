import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:maps_saved_app/infrastructure/csv/csv_parser.dart';
import 'package:maps_saved_app/infrastructure/logging/sync_logger.dart';

/// No-op SyncLogger for testing.
class NoOpSyncLogger extends SyncLogger {
  NoOpSyncLogger() : super(minLevel: LogLevel.error);

  @override
  void debug(String event, [Map<String, dynamic>? data]) {}

  @override
  void info(String event, [Map<String, dynamic>? data]) {}

  @override
  void warn(String event, [Map<String, dynamic>? data]) {}

  @override
  void error(String event, [Map<String, dynamic>? data]) {}
}

void main() {
  late CsvParser parser;

  setUp(() {
    parser = CsvParser(NoOpSyncLogger());
  });

  group('CsvParser', () {
    group('basic CSV parsing with headers', () {
      test('parses simple CSV with all columns', () {
        const csv = 'Title,URL,Note\r\n'
            'Cafe ABC,https://google.com/maps/place/Cafe,Good coffee\r\n'
            'Shop XYZ,https://google.com/maps/place/Shop,Nice shop\r\n';

        final result = parser.parseString(csv);

        expect(result.records, hasLength(2));
        expect(result.headers, equals(['title', 'url', 'note']));
        expect(result.skippedRowCount, equals(0));

        expect(result.records[0].fields['title'], equals('Cafe ABC'));
        expect(result.records[0].fields['url'],
            equals('https://google.com/maps/place/Cafe'));
        expect(result.records[0].fields['note'], equals('Good coffee'));
        expect(result.records[0].rowNumber, equals(2));

        expect(result.records[1].fields['title'], equals('Shop XYZ'));
        expect(result.records[1].rowNumber, equals(3));
      });

      test('normalizes header names to lowercase with underscores', () {
        const csv = 'Place Name,Item Content URL,My Note\r\n'
            'Test,https://example.com,Hello\r\n';

        final result = parser.parseString(csv);

        expect(result.headers, contains('place_name'));
        expect(result.headers, contains('item_content_url'));
        expect(result.headers, contains('my_note'));
      });
    });

    group('BOM-prefixed UTF-8 handling', () {
      test('strips UTF-8 BOM from byte input', () {
        const csv = 'Title,URL\r\nCafe,https://example.com\r\n';
        final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode(csv)];

        final result = parser.parse(bytes);

        expect(result.records, hasLength(1));
        expect(result.headers.first, equals('title'));
        expect(result.records[0].fields['title'], equals('Cafe'));
      });

      test('works correctly without BOM', () {
        const csv = 'Title,URL\r\nCafe,https://example.com\r\n';
        final bytes = utf8.encode(csv);

        final result = parser.parse(bytes);

        expect(result.records, hasLength(1));
        expect(result.records[0].fields['title'], equals('Cafe'));
      });
    });

    group('empty rows are skipped', () {
      test('skips completely empty rows', () {
        const csv = 'Title,URL\r\n'
            'Cafe,https://example.com\r\n'
            '\r\n'
            'Shop,https://example2.com\r\n';

        final result = parser.parseString(csv);

        expect(result.records, hasLength(2));
        expect(result.skippedRowCount, equals(1));
      });

      test('skips rows with only empty comma-separated values', () {
        const csv = 'Title,URL\r\n'
            'Cafe,https://example.com\r\n'
            ',\r\n'
            'Shop,https://example2.com\r\n';

        final result = parser.parseString(csv);

        // The row "," produces fields that are all empty after trim,
        // so it gets skipped
        expect(result.skippedRowCount, greaterThanOrEqualTo(1));
      });
    });

    group('missing columns are tolerated', () {
      test('rows with fewer columns than headers are still parsed', () {
        const csv = 'Title,URL,Note\r\n'
            'Cafe\r\n';

        final result = parser.parseString(csv);

        expect(result.records, hasLength(1));
        expect(result.records[0].fields['title'], equals('Cafe'));
        // URL and Note should not be present since they were missing
        expect(result.records[0].fields.containsKey('url'), isFalse);
        expect(result.records[0].fields.containsKey('note'), isFalse);
      });

      test('extra columns beyond headers are ignored', () {
        const csv = 'Title,URL\r\n'
            'Cafe,https://example.com,ExtraValue\r\n';

        final result = parser.parseString(csv);

        expect(result.records, hasLength(1));
        expect(result.records[0].fields['title'], equals('Cafe'));
        expect(result.records[0].fields['url'],
            equals('https://example.com'));
      });
    });

    group('invalid rows are skipped and counted', () {
      test('skipped rows are counted in skippedRowCount', () {
        const csv = 'Title,URL\r\n'
            'Cafe,https://example.com\r\n'
            '\r\n'
            '\r\n'
            'Shop,https://example2.com\r\n';

        final result = parser.parseString(csv);

        expect(result.records, hasLength(2));
        expect(result.skippedRowCount, equals(2));
      });
    });

    group('empty CSV returns empty result', () {
      test('completely empty string returns empty result', () {
        final result = parser.parseString('');

        expect(result.records, isEmpty);
        expect(result.headers, isEmpty);
        expect(result.skippedRowCount, equals(0));
      });

      test('header-only CSV returns empty records', () {
        const csv = 'Title,URL,Note\r\n';

        final result = parser.parseString(csv);

        expect(result.records, isEmpty);
        expect(result.headers, hasLength(3));
        expect(result.skippedRowCount, equals(0));
      });
    });

    group('Japanese content is preserved', () {
      test('parses Japanese text in fields correctly', () {
        const csv = 'Title,URL,Note\r\n'
            'cafe,https://google.com/maps,good\r\n';

        final result = parser.parseString(csv);

        expect(result.records, hasLength(1));
        expect(result.records[0].fields['title'], equals('cafe'));
      });

      test('parses full Japanese CSV content', () {
        const csv = 'title,url,note\r\n'
            'cafe,https://maps.google.com/place/cafe,in shibuya\r\n';

        final result = parser.parseString(csv);

        expect(result.records, hasLength(1));
        expect(result.records[0].fields['title'], equals('cafe'));
        expect(result.records[0].fields['note'],
            equals('in shibuya'));
      });

      test('Japanese content survives BOM + byte decoding', () {
        final csv =
            'Title,Note\r\n\u6771\u4eac\u30bf\u30ef\u30fc,\u7f8e\u3057\u3044\u666f\u8272\r\n';
        final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode(csv)];

        final result = parser.parse(bytes);

        expect(result.records, hasLength(1));
        expect(result.records[0].fields['title'],
            equals('\u6771\u4eac\u30bf\u30ef\u30fc'));
        expect(result.records[0].fields['note'],
            equals('\u7f8e\u3057\u3044\u666f\u8272'));
      });

      test('Japanese headers are preserved after normalization', () {
        const csv = 'タイトル,URL,メモ,コメント\r\n'
            '東京タワー,https://maps.google.com/?cid=123,いい場所,おすすめ\r\n';

        final result = parser.parseString(csv);

        expect(result.headers, equals(['タイトル', 'url', 'メモ', 'コメント']));
        expect(result.records, hasLength(1));
        expect(result.records[0].fields['タイトル'], equals('東京タワー'));
        expect(result.records[0].fields['url'],
            equals('https://maps.google.com/?cid=123'));
        expect(result.records[0].fields['メモ'], equals('いい場所'));
        expect(result.records[0].fields['コメント'], equals('おすすめ'));
      });

      test('mixed Japanese and English headers are normalized correctly', () {
        const csv = 'タイトル,Item Content URL,メモ\r\n'
            'カフェ,https://example.com,美味しい\r\n';

        final result = parser.parseString(csv);

        expect(result.headers, equals(['タイトル', 'item_content_url', 'メモ']));
        expect(result.records[0].fields['タイトル'], equals('カフェ'));
        expect(result.records[0].fields['item_content_url'],
            equals('https://example.com'));
        expect(result.records[0].fields['メモ'], equals('美味しい'));
      });
    });
  });
}
