import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:maps_saved_app/infrastructure/csv/place_normalizer.dart';
import 'package:maps_saved_app/domain/models/raw_place_record.dart';

void main() {
  late PlaceNormalizer normalizer;

  setUp(() {
    normalizer = PlaceNormalizer();
  });

  group('PlaceNormalizer', () {
    group('maps CSV headers to internal fields', () {
      test('maps "title" to sourceTitle', () {
        final raw = RawPlaceRecord(
          rowNumber: 1,
          fields: {'title': 'Cafe ABC'},
        );
        final result = normalizer.normalize(raw);
        expect(result.sourceTitle, equals('Cafe ABC'));
      });

      test('maps "name" to sourceTitle', () {
        final raw = RawPlaceRecord(
          rowNumber: 1,
          fields: {'name': 'Shop XYZ'},
        );
        final result = normalizer.normalize(raw);
        expect(result.sourceTitle, equals('Shop XYZ'));
      });

      test('maps "place_name" to sourceTitle', () {
        final raw = RawPlaceRecord(
          rowNumber: 1,
          fields: {'place_name': 'Restaurant'},
        );
        final result = normalizer.normalize(raw);
        expect(result.sourceTitle, equals('Restaurant'));
      });

      test('maps "url" to mapsUrl', () {
        final raw = RawPlaceRecord(
          rowNumber: 1,
          fields: {'url': 'https://google.com/maps/place/Test'},
        );
        final result = normalizer.normalize(raw);
        expect(result.mapsUrl, equals('https://google.com/maps/place/Test'));
      });

      test('maps "item_content_url" to mapsUrl', () {
        final raw = RawPlaceRecord(
          rowNumber: 1,
          fields: {'item_content_url': 'https://maps.google.com/place/Foo'},
        );
        final result = normalizer.normalize(raw);
        expect(result.mapsUrl,
            equals('https://maps.google.com/place/Foo'));
      });

      test('maps "note" to note', () {
        final raw = RawPlaceRecord(
          rowNumber: 1,
          fields: {'note': 'Great place'},
        );
        final result = normalizer.normalize(raw);
        expect(result.note, equals('Great place'));
      });

      test('maps "comments" to comments', () {
        final raw = RawPlaceRecord(
          rowNumber: 1,
          fields: {'comments': 'Near the station'},
        );
        final result = normalizer.normalize(raw);
        expect(result.comments, equals('Near the station'));
      });

      test('maps "comment" to comments', () {
        final raw = RawPlaceRecord(
          rowNumber: 1,
          fields: {'comment': 'Near the station'},
        );
        final result = normalizer.normalize(raw);
        expect(result.comments, equals('Near the station'));
      });

      test('maps "collection_name" to collectionName', () {
        final raw = RawPlaceRecord(
          rowNumber: 1,
          fields: {'collection_name': 'Favorites'},
        );
        final result = normalizer.normalize(raw);
        expect(result.collectionName, equals('Favorites'));
      });

      test('maps "list_name" to collectionName', () {
        final raw = RawPlaceRecord(
          rowNumber: 1,
          fields: {'list_name': 'Wishlist'},
        );
        final result = normalizer.normalize(raw);
        expect(result.collectionName, equals('Wishlist'));
      });

      test('maps "collection_description" to collectionDescription', () {
        final raw = RawPlaceRecord(
          rowNumber: 1,
          fields: {'collection_description': 'My favorite spots'},
        );
        final result = normalizer.normalize(raw);
        expect(result.collectionDescription, equals('My favorite spots'));
      });
    });

    group('cleans whitespace and collapses newlines', () {
      test('trims leading and trailing whitespace', () {
        final raw = RawPlaceRecord(
          rowNumber: 1,
          fields: {'title': '  Cafe ABC  '},
        );
        final result = normalizer.normalize(raw);
        expect(result.sourceTitle, equals('Cafe ABC'));
      });

      test('collapses multiple consecutive newlines to two', () {
        final raw = RawPlaceRecord(
          rowNumber: 1,
          fields: {'note': 'Line 1\n\n\n\nLine 2'},
        );
        final result = normalizer.normalize(raw);
        expect(result.note, equals('Line 1\n\nLine 2'));
      });

      test('collapses multiple consecutive spaces to single', () {
        final raw = RawPlaceRecord(
          rowNumber: 1,
          fields: {'title': 'Cafe    ABC'},
        );
        final result = normalizer.normalize(raw);
        expect(result.sourceTitle, equals('Cafe ABC'));
      });

      test('preserves single newlines', () {
        final raw = RawPlaceRecord(
          rowNumber: 1,
          fields: {'note': 'Line 1\nLine 2'},
        );
        final result = normalizer.normalize(raw);
        expect(result.note, equals('Line 1\nLine 2'));
      });

      test('preserves double newlines', () {
        final raw = RawPlaceRecord(
          rowNumber: 1,
          fields: {'note': 'Line 1\n\nLine 2'},
        );
        final result = normalizer.normalize(raw);
        expect(result.note, equals('Line 1\n\nLine 2'));
      });
    });

    group('empty strings become null', () {
      test('empty string field becomes null', () {
        final raw = RawPlaceRecord(
          rowNumber: 1,
          fields: {'title': '', 'url': 'https://example.com'},
        );
        final result = normalizer.normalize(raw);
        // CsvParser already strips empty fields, but PlaceNormalizer's
        // _cleanString returns null for empty/whitespace-only strings
        expect(result.sourceTitle, isNull);
      });

      test('whitespace-only string becomes null', () {
        final raw = RawPlaceRecord(
          rowNumber: 1,
          fields: {'title': '   ', 'url': 'https://example.com'},
        );
        final result = normalizer.normalize(raw);
        expect(result.sourceTitle, isNull);
      });

      test('missing field becomes null', () {
        final raw = RawPlaceRecord(
          rowNumber: 1,
          fields: {'url': 'https://example.com'},
        );
        final result = normalizer.normalize(raw);
        expect(result.sourceTitle, isNull);
        expect(result.note, isNull);
      });
    });

    group('URL normalization', () {
      test('prefixes https:// for google.com/maps URL', () {
        final raw = RawPlaceRecord(
          rowNumber: 1,
          fields: {'url': 'google.com/maps/place/Cafe'},
        );
        final result = normalizer.normalize(raw);
        expect(result.mapsUrl,
            equals('https://google.com/maps/place/Cafe'));
      });

      test('prefixes https:// for goo.gl URL', () {
        final raw = RawPlaceRecord(
          rowNumber: 1,
          fields: {'url': 'goo.gl/maps/abc123'},
        );
        final result = normalizer.normalize(raw);
        expect(result.mapsUrl, equals('https://goo.gl/maps/abc123'));
      });

      test('prefixes https:// for maps.app URL', () {
        final raw = RawPlaceRecord(
          rowNumber: 1,
          fields: {'url': 'maps.app/something'},
        );
        final result = normalizer.normalize(raw);
        expect(result.mapsUrl, equals('https://maps.app/something'));
      });

      test('keeps existing https:// prefix', () {
        final raw = RawPlaceRecord(
          rowNumber: 1,
          fields: {'url': 'https://google.com/maps/place/Cafe'},
        );
        final result = normalizer.normalize(raw);
        expect(result.mapsUrl,
            equals('https://google.com/maps/place/Cafe'));
      });

      test('keeps existing http:// prefix', () {
        final raw = RawPlaceRecord(
          rowNumber: 1,
          fields: {'url': 'http://google.com/maps/place/Cafe'},
        );
        final result = normalizer.normalize(raw);
        expect(result.mapsUrl,
            equals('http://google.com/maps/place/Cafe'));
      });

      test('stores non-Google URL as-is without prefix', () {
        final raw = RawPlaceRecord(
          rowNumber: 1,
          fields: {'url': 'example.com/place'},
        );
        final result = normalizer.normalize(raw);
        expect(result.mapsUrl, equals('example.com/place'));
      });

      test('empty URL becomes null', () {
        final raw = RawPlaceRecord(
          rowNumber: 1,
          fields: {'url': '   '},
        );
        final result = normalizer.normalize(raw);
        expect(result.mapsUrl, isNull);
      });
    });

    group('raw payload JSON is preserved', () {
      test('stores original fields as JSON', () {
        final raw = RawPlaceRecord(
          rowNumber: 1,
          fields: {
            'title': 'Cafe ABC',
            'url': 'https://google.com/maps',
            'note': 'Good',
          },
        );
        final result = normalizer.normalize(raw);

        expect(result.rawPayloadJson, isNotNull);

        final decoded =
            jsonDecode(result.rawPayloadJson!) as Map<String, dynamic>;
        expect(decoded['title'], equals('Cafe ABC'));
        expect(decoded['url'], equals('https://google.com/maps'));
        expect(decoded['note'], equals('Good'));
      });

      test('rawPayloadJson is valid JSON', () {
        final raw = RawPlaceRecord(
          rowNumber: 1,
          fields: {'title': 'Test "quoted" value'},
        );
        final result = normalizer.normalize(raw);

        expect(
          () => jsonDecode(result.rawPayloadJson!),
          returnsNormally,
        );
      });
    });

    group('handles unknown headers gracefully', () {
      test('unknown headers are ignored but do not cause errors', () {
        final raw = RawPlaceRecord(
          rowNumber: 1,
          fields: {
            'title': 'Cafe ABC',
            'custom_field': 'some value',
            'unknown_column': 'another value',
          },
        );
        final result = normalizer.normalize(raw);

        expect(result.sourceTitle, equals('Cafe ABC'));
        // Unknown fields should not appear in normalized record
        // but should be in raw payload
        final decoded =
            jsonDecode(result.rawPayloadJson!) as Map<String, dynamic>;
        expect(decoded['custom_field'], equals('some value'));
        expect(decoded['unknown_column'], equals('another value'));
      });

      test('record with only unknown headers has null internal fields', () {
        final raw = RawPlaceRecord(
          rowNumber: 1,
          fields: {
            'unknown1': 'value1',
            'unknown2': 'value2',
          },
        );
        final result = normalizer.normalize(raw);

        expect(result.sourceTitle, isNull);
        expect(result.mapsUrl, isNull);
        expect(result.note, isNull);
        expect(result.comments, isNull);
        expect(result.collectionName, isNull);
      });
    });
  });
}
