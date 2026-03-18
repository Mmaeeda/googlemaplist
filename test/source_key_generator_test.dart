import 'package:flutter_test/flutter_test.dart';

import 'package:maps_saved_app/domain/models/app_error.dart';
import 'package:maps_saved_app/infrastructure/sync/source_key_generator.dart';
import 'package:maps_saved_app/domain/models/normalized_place_record.dart';

void main() {
  late SourceKeyGenerator generator;

  setUp(() {
    generator = SourceKeyGenerator();
  });

  group('SourceKeyGenerator', () {
    group('URL-based key generation', () {
      test('generates SHA-256 hash for URL-based record', () {
        final record = NormalizedPlaceRecord(
          mapsUrl: 'https://www.google.com/maps/place/CafeABC',
          sourceTitle: 'Cafe ABC',
        );
        final key = generator.generate(record);
        // SHA-256 produces 64 hex characters
        expect(key, hasLength(64));
        expect(key, matches(RegExp(r'^[a-f0-9]{64}$')));
      });

      test('URL takes priority over title+note+comments', () {
        final recordWithUrl = NormalizedPlaceRecord(
          mapsUrl: 'https://www.google.com/maps/place/CafeABC',
          sourceTitle: 'Cafe ABC',
          note: 'Some note',
        );

        final recordWithDiffTitle = NormalizedPlaceRecord(
          mapsUrl: 'https://www.google.com/maps/place/CafeABC',
          sourceTitle: 'Different Title',
          note: 'Different note',
        );

        // Same URL -> same key, regardless of other fields
        expect(
          generator.generate(recordWithUrl),
          equals(generator.generate(recordWithDiffTitle)),
        );
      });
    });

    group('fallback to title+note+comments+collection', () {
      test('uses field concatenation when no URL', () {
        final record = NormalizedPlaceRecord(
          sourceTitle: 'Cafe ABC',
          note: 'Good coffee',
          comments: 'Near station',
          collectionName: 'Favorites',
        );
        final key = generator.generate(record);
        expect(key, hasLength(64));
        expect(key, matches(RegExp(r'^[a-f0-9]{64}$')));
      });

      test('uses only title when other fields are null', () {
        final record = NormalizedPlaceRecord(
          sourceTitle: 'Cafe ABC',
        );
        final key = generator.generate(record);
        expect(key, hasLength(64));
      });

      test('different field values produce different keys', () {
        final record1 = NormalizedPlaceRecord(
          sourceTitle: 'Cafe ABC',
        );
        final record2 = NormalizedPlaceRecord(
          sourceTitle: 'Cafe DEF',
        );
        expect(
          generator.generate(record1),
          isNot(equals(generator.generate(record2))),
        );
      });
    });

    group('same URL produces same key (idempotent)', () {
      test('identical URL strings produce identical keys', () {
        final record1 = NormalizedPlaceRecord(
          mapsUrl: 'https://www.google.com/maps/place/Tokyo',
        );
        final record2 = NormalizedPlaceRecord(
          mapsUrl: 'https://www.google.com/maps/place/Tokyo',
        );
        expect(
          generator.generate(record1),
          equals(generator.generate(record2)),
        );
      });

      test('calling generate multiple times returns same key', () {
        final record = NormalizedPlaceRecord(
          mapsUrl: 'https://www.google.com/maps/place/Osaka',
        );
        final key1 = generator.generate(record);
        final key2 = generator.generate(record);
        final key3 = generator.generate(record);
        expect(key1, equals(key2));
        expect(key2, equals(key3));
      });
    });

    group('different URLs produce different keys', () {
      test('different paths produce different keys', () {
        final record1 = NormalizedPlaceRecord(
          mapsUrl: 'https://www.google.com/maps/place/Tokyo',
        );
        final record2 = NormalizedPlaceRecord(
          mapsUrl: 'https://www.google.com/maps/place/Osaka',
        );
        expect(
          generator.generate(record1),
          isNot(equals(generator.generate(record2))),
        );
      });

      test('different hosts produce different keys', () {
        final record1 = NormalizedPlaceRecord(
          mapsUrl: 'https://www.google.com/maps/place/Test',
        );
        final record2 = NormalizedPlaceRecord(
          mapsUrl: 'https://maps.google.co.jp/maps/place/Test',
        );
        expect(
          generator.generate(record1),
          isNot(equals(generator.generate(record2))),
        );
      });
    });

    group('full-width/half-width space normalization', () {
      test('full-width space is normalized to half-width for field-based key',
          () {
        final recordFullWidth = NormalizedPlaceRecord(
          sourceTitle: 'Cafe\u3000ABC', // full-width space
        );
        final recordHalfWidth = NormalizedPlaceRecord(
          sourceTitle: 'Cafe ABC', // normal half-width space
        );
        expect(
          generator.generate(recordFullWidth),
          equals(generator.generate(recordHalfWidth)),
        );
      });

      test('multiple spaces are collapsed to single space', () {
        final record1 = NormalizedPlaceRecord(
          sourceTitle: 'Cafe   ABC', // multiple spaces
        );
        final record2 = NormalizedPlaceRecord(
          sourceTitle: 'Cafe ABC', // single space
        );
        expect(
          generator.generate(record1),
          equals(generator.generate(record2)),
        );
      });

      test('leading/trailing whitespace is trimmed', () {
        final record1 = NormalizedPlaceRecord(
          sourceTitle: '  Cafe ABC  ',
        );
        final record2 = NormalizedPlaceRecord(
          sourceTitle: 'Cafe ABC',
        );
        expect(
          generator.generate(record1),
          equals(generator.generate(record2)),
        );
      });
    });

    group('empty record throws AppError', () {
      test('throws when all fields are null', () {
        final record = NormalizedPlaceRecord();
        expect(
          () => generator.generate(record),
          throwsA(isA<AppError>().having(
            (e) => e.code,
            'code',
            AppErrorCode.csvParseFailed,
          )),
        );
      });

      test('throws when all fields are empty strings', () {
        final record = NormalizedPlaceRecord(
          sourceTitle: null,
          mapsUrl: null,
          note: null,
          comments: null,
          collectionName: null,
          rawPayloadJson: null,
        );
        expect(
          () => generator.generate(record),
          throwsA(isA<AppError>().having(
            (e) => e.code,
            'code',
            AppErrorCode.csvParseFailed,
          )),
        );
      });

      test('does not throw when URL is empty but title is present', () {
        final record = NormalizedPlaceRecord(
          mapsUrl: '',
          sourceTitle: 'Some Title',
        );
        expect(
          () => generator.generate(record),
          returnsNormally,
        );
      });
    });

    group('raw payload fallback when other fields empty', () {
      test('uses rawPayloadJson as last resort', () {
        final record = NormalizedPlaceRecord(
          rawPayloadJson: '{"some":"data","row":1}',
        );
        final key = generator.generate(record);
        expect(key, hasLength(64));
        expect(key, matches(RegExp(r'^[a-f0-9]{64}$')));
      });

      test('same payload produces same key', () {
        final record1 = NormalizedPlaceRecord(
          rawPayloadJson: '{"key":"value"}',
        );
        final record2 = NormalizedPlaceRecord(
          rawPayloadJson: '{"key":"value"}',
        );
        expect(
          generator.generate(record1),
          equals(generator.generate(record2)),
        );
      });

      test('different payload produces different key', () {
        final record1 = NormalizedPlaceRecord(
          rawPayloadJson: '{"key":"value1"}',
        );
        final record2 = NormalizedPlaceRecord(
          rawPayloadJson: '{"key":"value2"}',
        );
        expect(
          generator.generate(record1),
          isNot(equals(generator.generate(record2))),
        );
      });
    });
  });
}
