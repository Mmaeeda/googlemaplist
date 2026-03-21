import 'package:flutter_test/flutter_test.dart';

import 'package:maps_saved_app/domain/models/normalized_place_record.dart';
import 'package:maps_saved_app/domain/models/place.dart';
import 'package:maps_saved_app/domain/repositories/place_repository.dart';
import 'package:maps_saved_app/infrastructure/sync/diff_engine.dart';
import 'package:maps_saved_app/infrastructure/sync/source_key_generator.dart';
import 'package:maps_saved_app/infrastructure/logging/sync_logger.dart';

/// In-memory implementation of PlaceRepository for testing.
class InMemoryPlaceRepository implements PlaceRepository {
  final Map<String, Place> _places = {};

  /// Helper to pre-populate the repository with test data.
  void seed(List<Place> places) {
    for (final place in places) {
      _places[place.id] = place;
    }
  }

  @override
  Future<Place?> findById(String id) async {
    return _places[id];
  }

  @override
  Future<Place?> findBySourceKey(String sourceKey) async {
    for (final place in _places.values) {
      if (place.sourceKey == sourceKey) {
        return place;
      }
    }
    return null;
  }

  @override
  Future<void> insert(Place place) async {
    _places[place.id] = place;
  }

  @override
  Future<void> update(Place place) async {
    _places[place.id] = place;
  }

  @override
  Future<void> updateTitle(String placeId, String? newTitle) async {
    final place = _places[placeId];
    if (place == null) return;
    _places[placeId] = place.copyWith(sourceTitle: newTitle ?? place.sourceTitle);
  }

  @override
  Future<void> markMissing(String placeId) async {
    final place = _places[placeId];
    if (place == null) return;

    final newMissCount = place.deletedMissCount + 1;
    final shouldHide = newMissCount >= 2;

    _places[placeId] = place.copyWith(
      isDeletedCandidate: true,
      deletedMissCount: newMissCount,
      isHidden: shouldHide,
    );
  }

  @override
  Future<List<Place>> listMissingCandidates() async {
    return _places.values
        .where((p) => p.isDeletedCandidate)
        .toList();
  }

  @override
  Future<List<Place>> listAllActive() async {
    return _places.values
        .where((p) => !p.isHidden)
        .toList();
  }

  @override
  Future<List<Place>> listAll() async {
    return _places.values.toList();
  }
}

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
  late InMemoryPlaceRepository repository;
  late SourceKeyGenerator keyGenerator;
  late DiffEngine diffEngine;
  late NoOpSyncLogger logger;

  setUp(() {
    repository = InMemoryPlaceRepository();
    keyGenerator = SourceKeyGenerator();
    logger = NoOpSyncLogger();
    diffEngine = DiffEngine(repository, keyGenerator, logger);
  });

  /// Helper to create a Place from a NormalizedPlaceRecord.
  Place createPlace({
    required String id,
    required NormalizedPlaceRecord record,
  }) {
    final now = DateTime.now();
    return Place(
      id: id,
      sourceKey: keyGenerator.generate(record),
      sourceTitle: record.sourceTitle,
      mapsUrl: record.mapsUrl,
      note: record.note,
      comments: record.comments,
      collectionName: record.collectionName,
      collectionDescription: record.collectionDescription,
      rawPayloadJson: record.rawPayloadJson,
      createdAt: now,
      updatedAt: now,
      lastSeenAt: now,
    );
  }

  group('DiffEngine', () {
    group('all new records when DB is empty', () {
      test('all records are classified as new', () async {
        final records = [
          NormalizedPlaceRecord(
            mapsUrl: 'https://google.com/maps/place/CafeA',
            sourceTitle: 'Cafe A',
          ),
          NormalizedPlaceRecord(
            mapsUrl: 'https://google.com/maps/place/CafeB',
            sourceTitle: 'Cafe B',
          ),
          NormalizedPlaceRecord(
            mapsUrl: 'https://google.com/maps/place/CafeC',
            sourceTitle: 'Cafe C',
          ),
        ];

        final result = await diffEngine.compute(records);

        expect(result.newRecords, hasLength(3));
        expect(result.updatedRecords, isEmpty);
        expect(result.unchangedRecords, isEmpty);
        expect(result.missingPlaceIds, isEmpty);
      });

      test('new record fields are preserved', () async {
        final records = [
          NormalizedPlaceRecord(
            mapsUrl: 'https://google.com/maps/place/CafeA',
            sourceTitle: 'Cafe A',
            note: 'Good coffee',
          ),
        ];

        final result = await diffEngine.compute(records);

        expect(result.newRecords.first.sourceTitle, equals('Cafe A'));
        expect(result.newRecords.first.note, equals('Good coffee'));
      });
    });

    group('detects updated records', () {
      test('detects changed title', () async {
        final originalRecord = NormalizedPlaceRecord(
          mapsUrl: 'https://google.com/maps/place/CafeA',
          sourceTitle: 'Cafe A',
        );
        repository.seed([createPlace(id: 'place-1', record: originalRecord)]);

        final incomingRecords = [
          NormalizedPlaceRecord(
            mapsUrl: 'https://google.com/maps/place/CafeA',
            sourceTitle: 'Cafe A - Updated Name',
          ),
        ];

        final result = await diffEngine.compute(incomingRecords);

        expect(result.newRecords, isEmpty);
        expect(result.updatedRecords, hasLength(1));
        expect(result.updatedRecords.first.existingPlaceId, equals('place-1'));
        expect(result.updatedRecords.first.changedFields,
            contains('source_title'));
      });

      test('detects changed note', () async {
        final originalRecord = NormalizedPlaceRecord(
          mapsUrl: 'https://google.com/maps/place/CafeA',
          sourceTitle: 'Cafe A',
          note: 'Original note',
        );
        repository.seed([createPlace(id: 'place-1', record: originalRecord)]);

        final incomingRecords = [
          NormalizedPlaceRecord(
            mapsUrl: 'https://google.com/maps/place/CafeA',
            sourceTitle: 'Cafe A',
            note: 'Updated note',
          ),
        ];

        final result = await diffEngine.compute(incomingRecords);

        expect(result.updatedRecords, hasLength(1));
        expect(result.updatedRecords.first.changedFields, contains('note'));
        expect(result.updatedRecords.first.changedFields,
            isNot(contains('source_title')));
      });

      test('detects multiple changed fields', () async {
        final originalRecord = NormalizedPlaceRecord(
          mapsUrl: 'https://google.com/maps/place/CafeA',
          sourceTitle: 'Cafe A',
          note: 'Note',
          comments: 'Comment',
        );
        repository.seed([createPlace(id: 'place-1', record: originalRecord)]);

        final incomingRecords = [
          NormalizedPlaceRecord(
            mapsUrl: 'https://google.com/maps/place/CafeA',
            sourceTitle: 'Cafe A Updated',
            note: 'Updated note',
            comments: 'Comment', // Unchanged
          ),
        ];

        final result = await diffEngine.compute(incomingRecords);

        expect(result.updatedRecords, hasLength(1));
        expect(result.updatedRecords.first.changedFields,
            contains('source_title'));
        expect(result.updatedRecords.first.changedFields, contains('note'));
        expect(result.updatedRecords.first.changedFields,
            isNot(contains('comments')));
      });
    });

    group('detects unchanged records', () {
      test('identical record is unchanged', () async {
        final originalRecord = NormalizedPlaceRecord(
          mapsUrl: 'https://google.com/maps/place/CafeA',
          sourceTitle: 'Cafe A',
          note: 'Good coffee',
        );
        repository.seed([createPlace(id: 'place-1', record: originalRecord)]);

        final incomingRecords = [
          NormalizedPlaceRecord(
            mapsUrl: 'https://google.com/maps/place/CafeA',
            sourceTitle: 'Cafe A',
            note: 'Good coffee',
          ),
        ];

        final result = await diffEngine.compute(incomingRecords);

        expect(result.newRecords, isEmpty);
        expect(result.updatedRecords, isEmpty);
        expect(result.unchangedRecords, hasLength(1));
        expect(result.unchangedRecords.first.existingPlaceId,
            equals('place-1'));
      });

      test('null vs empty string is treated as unchanged', () async {
        final originalRecord = NormalizedPlaceRecord(
          mapsUrl: 'https://google.com/maps/place/CafeA',
          sourceTitle: 'Cafe A',
          note: null,
        );
        repository.seed([createPlace(id: 'place-1', record: originalRecord)]);

        final incomingRecords = [
          NormalizedPlaceRecord(
            mapsUrl: 'https://google.com/maps/place/CafeA',
            sourceTitle: 'Cafe A',
            note: '', // Empty string should be same as null
          ),
        ];

        final result = await diffEngine.compute(incomingRecords);

        expect(result.updatedRecords, isEmpty);
        expect(result.unchangedRecords, hasLength(1));
      });
    });

    group('detects missing place IDs', () {
      test('place in DB but not in incoming is missing', () async {
        final record1 = NormalizedPlaceRecord(
          mapsUrl: 'https://google.com/maps/place/CafeA',
          sourceTitle: 'Cafe A',
        );
        final record2 = NormalizedPlaceRecord(
          mapsUrl: 'https://google.com/maps/place/CafeB',
          sourceTitle: 'Cafe B',
        );

        repository.seed([
          createPlace(id: 'place-1', record: record1),
          createPlace(id: 'place-2', record: record2),
        ]);

        // Only send record1, record2's place should be missing
        final incomingRecords = [
          NormalizedPlaceRecord(
            mapsUrl: 'https://google.com/maps/place/CafeA',
            sourceTitle: 'Cafe A',
          ),
        ];

        final result = await diffEngine.compute(incomingRecords);

        expect(result.missingPlaceIds, hasLength(1));
        expect(result.missingPlaceIds, contains('place-2'));
      });

      test('hidden places are not listed as missing', () async {
        final record1 = NormalizedPlaceRecord(
          mapsUrl: 'https://google.com/maps/place/CafeA',
          sourceTitle: 'Cafe A',
        );
        final hiddenRecord = NormalizedPlaceRecord(
          mapsUrl: 'https://google.com/maps/place/CafeHidden',
          sourceTitle: 'Hidden Cafe',
        );

        final hiddenPlace =
            createPlace(id: 'place-hidden', record: hiddenRecord)
                .copyWith(isHidden: true);

        repository.seed([
          createPlace(id: 'place-1', record: record1),
          hiddenPlace,
        ]);

        // Send only record1
        final incomingRecords = [
          NormalizedPlaceRecord(
            mapsUrl: 'https://google.com/maps/place/CafeA',
            sourceTitle: 'Cafe A',
          ),
        ];

        final result = await diffEngine.compute(incomingRecords);

        // Hidden place should NOT appear in missing list
        // (listAllActive filters them out, plus isHidden check)
        expect(result.missingPlaceIds, isEmpty);
      });

      test('empty incoming list makes all active places missing', () async {
        final record1 = NormalizedPlaceRecord(
          mapsUrl: 'https://google.com/maps/place/CafeA',
          sourceTitle: 'Cafe A',
        );
        repository.seed([createPlace(id: 'place-1', record: record1)]);

        final result = await diffEngine.compute([]);

        expect(result.missingPlaceIds, hasLength(1));
        expect(result.missingPlaceIds, contains('place-1'));
      });
    });

    group('mixed scenario', () {
      test('some new, some updated, some unchanged, some missing', () async {
        final existingRecordA = NormalizedPlaceRecord(
          mapsUrl: 'https://google.com/maps/place/CafeA',
          sourceTitle: 'Cafe A',
          note: 'Original',
        );
        final existingRecordB = NormalizedPlaceRecord(
          mapsUrl: 'https://google.com/maps/place/CafeB',
          sourceTitle: 'Cafe B',
        );
        final existingRecordC = NormalizedPlaceRecord(
          mapsUrl: 'https://google.com/maps/place/CafeC',
          sourceTitle: 'Cafe C',
        );

        repository.seed([
          createPlace(id: 'place-a', record: existingRecordA),
          createPlace(id: 'place-b', record: existingRecordB),
          createPlace(id: 'place-c', record: existingRecordC),
        ]);

        final incomingRecords = [
          // Cafe A - updated note
          NormalizedPlaceRecord(
            mapsUrl: 'https://google.com/maps/place/CafeA',
            sourceTitle: 'Cafe A',
            note: 'Updated note',
          ),
          // Cafe B - unchanged
          NormalizedPlaceRecord(
            mapsUrl: 'https://google.com/maps/place/CafeB',
            sourceTitle: 'Cafe B',
          ),
          // Cafe D - new
          NormalizedPlaceRecord(
            mapsUrl: 'https://google.com/maps/place/CafeD',
            sourceTitle: 'Cafe D',
          ),
          // Cafe C is NOT in incoming -> missing
        ];

        final result = await diffEngine.compute(incomingRecords);

        expect(result.newRecords, hasLength(1));
        expect(result.newRecords.first.sourceTitle, equals('Cafe D'));

        expect(result.updatedRecords, hasLength(1));
        expect(
            result.updatedRecords.first.existingPlaceId, equals('place-a'));
        expect(result.updatedRecords.first.changedFields, contains('note'));

        expect(result.unchangedRecords, hasLength(1));
        expect(
            result.unchangedRecords.first.existingPlaceId, equals('place-b'));

        expect(result.missingPlaceIds, hasLength(1));
        expect(result.missingPlaceIds, contains('place-c'));
      });
    });
  });
}
