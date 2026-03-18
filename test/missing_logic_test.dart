import 'package:flutter_test/flutter_test.dart';

import 'package:maps_saved_app/domain/models/diff_result.dart';
import 'package:maps_saved_app/domain/models/normalized_place_record.dart';
import 'package:maps_saved_app/domain/models/place.dart';
import 'package:maps_saved_app/domain/repositories/place_repository.dart';
import 'package:maps_saved_app/infrastructure/sync/diff_applier.dart';
import 'package:maps_saved_app/infrastructure/sync/diff_engine.dart';
import 'package:maps_saved_app/infrastructure/sync/source_key_generator.dart';
import 'package:maps_saved_app/infrastructure/logging/sync_logger.dart';

/// In-memory implementation of PlaceRepository for testing.
class InMemoryPlaceRepository implements PlaceRepository {
  final Map<String, Place> _places = {};

  void seed(List<Place> places) {
    for (final place in places) {
      _places[place.id] = place;
    }
  }

  Place? getById(String id) => _places[id];

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
    return _places.values.where((p) => !p.isHidden).toList();
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
  late DiffApplier diffApplier;
  late NoOpSyncLogger logger;

  setUp(() {
    repository = InMemoryPlaceRepository();
    keyGenerator = SourceKeyGenerator();
    logger = NoOpSyncLogger();
    diffEngine = DiffEngine(repository, keyGenerator, logger);
    diffApplier = DiffApplier(repository, keyGenerator, logger);
  });

  /// Helper to create a Place.
  Place createPlace({
    required String id,
    required NormalizedPlaceRecord record,
    bool isDeletedCandidate = false,
    int deletedMissCount = 0,
    bool isHidden = false,
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
      isDeletedCandidate: isDeletedCandidate,
      deletedMissCount: deletedMissCount,
      isHidden: isHidden,
    );
  }

  group('Missing/deletion candidate logic', () {
    group('first missing: is_deleted_candidate=true, deleted_miss_count=1, is_hidden=false',
        () {
      test('marking a place as missing the first time sets correct flags',
          () async {
        final record = NormalizedPlaceRecord(
          mapsUrl: 'https://google.com/maps/place/CafeA',
          sourceTitle: 'Cafe A',
        );
        final place = createPlace(id: 'place-1', record: record);
        repository.seed([place]);

        // Simulate: incoming CSV does NOT contain this place
        final diff = await diffEngine.compute([]);

        expect(diff.missingPlaceIds, contains('place-1'));

        // Apply the diff to update flags
        await diffApplier.apply(diff);

        // Verify the place flags
        final updated = repository.getById('place-1')!;
        expect(updated.isDeletedCandidate, isTrue);
        expect(updated.deletedMissCount, equals(1));
        expect(updated.isHidden, isFalse);
      });
    });

    group('second missing: is_hidden=true', () {
      test(
          'marking a place as missing the second time sets is_hidden=true',
          () async {
        final record = NormalizedPlaceRecord(
          mapsUrl: 'https://google.com/maps/place/CafeA',
          sourceTitle: 'Cafe A',
        );
        // Place already missed once
        final place = createPlace(
          id: 'place-1',
          record: record,
          isDeletedCandidate: true,
          deletedMissCount: 1,
          isHidden: false,
        );
        repository.seed([place]);

        // Second time: incoming CSV does NOT contain this place
        final diff = await diffEngine.compute([]);

        expect(diff.missingPlaceIds, contains('place-1'));

        // Apply the diff
        await diffApplier.apply(diff);

        // Verify flags
        final updated = repository.getById('place-1')!;
        expect(updated.isDeletedCandidate, isTrue);
        expect(updated.deletedMissCount, equals(2));
        expect(updated.isHidden, isTrue);
      });

      test('third miss keeps is_hidden=true and increments count', () async {
        final record = NormalizedPlaceRecord(
          mapsUrl: 'https://google.com/maps/place/CafeA',
          sourceTitle: 'Cafe A',
        );
        // Place already missed twice and is hidden
        final place = createPlace(
          id: 'place-1',
          record: record,
          isDeletedCandidate: true,
          deletedMissCount: 2,
          isHidden: true,
        );
        repository.seed([place]);

        // Hidden places are not listed in listAllActive(), so they won't
        // appear in missing list from diffEngine
        final diff = await diffEngine.compute([]);

        // Hidden places should NOT appear in missing IDs
        // (diffEngine skips hidden places)
        expect(diff.missingPlaceIds, isEmpty);

        // But if we directly call markMissing, it should still increment
        await repository.markMissing('place-1');

        final updated = repository.getById('place-1')!;
        expect(updated.deletedMissCount, equals(3));
        expect(updated.isHidden, isTrue);
      });
    });

    group('seen again after missing: flags reset (via diff_applier)', () {
      test('updated record resets deletion flags', () async {
        final record = NormalizedPlaceRecord(
          mapsUrl: 'https://google.com/maps/place/CafeA',
          sourceTitle: 'Cafe A',
          note: 'Original note',
        );
        // Place was previously marked as deletion candidate
        final place = createPlace(
          id: 'place-1',
          record: record,
          isDeletedCandidate: true,
          deletedMissCount: 1,
          isHidden: false,
        );
        repository.seed([place]);

        // Now the place re-appears in incoming CSV with updated content
        final incomingRecords = [
          NormalizedPlaceRecord(
            mapsUrl: 'https://google.com/maps/place/CafeA',
            sourceTitle: 'Cafe A',
            note: 'Updated note', // Changed field triggers update
          ),
        ];

        final diff = await diffEngine.compute(incomingRecords);

        expect(diff.updatedRecords, hasLength(1));
        expect(diff.missingPlaceIds, isEmpty);

        // Apply the diff
        await diffApplier.apply(diff);

        // Verify flags are reset
        final updated = repository.getById('place-1')!;
        expect(updated.isDeletedCandidate, isFalse);
        expect(updated.deletedMissCount, equals(0));
        expect(updated.isHidden, isFalse);
        expect(updated.note, equals('Updated note'));
      });

      test('unchanged record also resets deletion flags', () async {
        final record = NormalizedPlaceRecord(
          mapsUrl: 'https://google.com/maps/place/CafeA',
          sourceTitle: 'Cafe A',
        );
        // Place was previously marked as deletion candidate
        final place = createPlace(
          id: 'place-1',
          record: record,
          isDeletedCandidate: true,
          deletedMissCount: 1,
          isHidden: false,
        );
        repository.seed([place]);

        // Now the same record re-appears unchanged
        final incomingRecords = [
          NormalizedPlaceRecord(
            mapsUrl: 'https://google.com/maps/place/CafeA',
            sourceTitle: 'Cafe A',
          ),
        ];

        final diff = await diffEngine.compute(incomingRecords);

        expect(diff.unchangedRecords, hasLength(1));
        expect(diff.missingPlaceIds, isEmpty);

        // Apply the diff
        await diffApplier.apply(diff);

        // Verify flags are reset
        final updated = repository.getById('place-1')!;
        expect(updated.isDeletedCandidate, isFalse);
        expect(updated.deletedMissCount, equals(0));
      });
    });

    group('end-to-end missing lifecycle', () {
      test('full lifecycle: present -> missing1 -> missing2(hidden) -> re-appears',
          () async {
        final record = NormalizedPlaceRecord(
          mapsUrl: 'https://google.com/maps/place/CafeA',
          sourceTitle: 'Cafe A',
        );

        // Step 1: Place initially present
        final place = createPlace(id: 'place-1', record: record);
        repository.seed([place]);

        // Verify initial state
        var current = repository.getById('place-1')!;
        expect(current.isDeletedCandidate, isFalse);
        expect(current.deletedMissCount, equals(0));
        expect(current.isHidden, isFalse);

        // Step 2: First sync without the place -> first miss
        var diff = await diffEngine.compute([]);
        expect(diff.missingPlaceIds, contains('place-1'));
        await diffApplier.apply(diff);

        current = repository.getById('place-1')!;
        expect(current.isDeletedCandidate, isTrue);
        expect(current.deletedMissCount, equals(1));
        expect(current.isHidden, isFalse);

        // Step 3: Second sync without the place -> second miss, hidden
        diff = await diffEngine.compute([]);
        expect(diff.missingPlaceIds, contains('place-1'));
        await diffApplier.apply(diff);

        current = repository.getById('place-1')!;
        expect(current.isDeletedCandidate, isTrue);
        expect(current.deletedMissCount, equals(2));
        expect(current.isHidden, isTrue);

        // Step 4: Third sync - place is hidden, so not in missing list
        diff = await diffEngine.compute([]);
        expect(diff.missingPlaceIds, isEmpty);

        // Step 5: Place re-appears with updated data.
        // findBySourceKey still finds hidden places, so diffEngine
        // detects it as an update rather than a new record.
        final incomingRecords = [
          NormalizedPlaceRecord(
            mapsUrl: 'https://google.com/maps/place/CafeA',
            sourceTitle: 'Cafe A Updated',
          ),
        ];

        diff = await diffEngine.compute(incomingRecords);

        // findBySourceKey should still find the hidden place
        expect(diff.updatedRecords, hasLength(1));
        expect(diff.newRecords, isEmpty);

        await diffApplier.apply(diff);

        // DiffApplier resets isDeletedCandidate and deletedMissCount,
        // but does NOT reset isHidden (that requires separate user action
        // or a dedicated "un-hide" step).
        current = repository.getById('place-1')!;
        expect(current.isDeletedCandidate, isFalse);
        expect(current.deletedMissCount, equals(0));
        // isHidden stays true because DiffApplier.copyWith doesn't reset it
        expect(current.isHidden, isTrue);
        expect(current.sourceTitle, equals('Cafe A Updated'));
      });
    });

    group('multiple places missing scenario', () {
      test('only non-seen places are marked as missing', () async {
        final recordA = NormalizedPlaceRecord(
          mapsUrl: 'https://google.com/maps/place/CafeA',
          sourceTitle: 'Cafe A',
        );
        final recordB = NormalizedPlaceRecord(
          mapsUrl: 'https://google.com/maps/place/CafeB',
          sourceTitle: 'Cafe B',
        );
        final recordC = NormalizedPlaceRecord(
          mapsUrl: 'https://google.com/maps/place/CafeC',
          sourceTitle: 'Cafe C',
        );

        repository.seed([
          createPlace(id: 'place-a', record: recordA),
          createPlace(id: 'place-b', record: recordB),
          createPlace(id: 'place-c', record: recordC),
        ]);

        // Only Cafe A is in incoming -> B and C are missing
        final incomingRecords = [
          NormalizedPlaceRecord(
            mapsUrl: 'https://google.com/maps/place/CafeA',
            sourceTitle: 'Cafe A',
          ),
        ];

        final diff = await diffEngine.compute(incomingRecords);
        await diffApplier.apply(diff);

        // Cafe A should be unchanged
        final placeA = repository.getById('place-a')!;
        expect(placeA.isDeletedCandidate, isFalse);

        // Cafe B and C should be first-time missing
        final placeB = repository.getById('place-b')!;
        expect(placeB.isDeletedCandidate, isTrue);
        expect(placeB.deletedMissCount, equals(1));
        expect(placeB.isHidden, isFalse);

        final placeC = repository.getById('place-c')!;
        expect(placeC.isDeletedCandidate, isTrue);
        expect(placeC.deletedMissCount, equals(1));
        expect(placeC.isHidden, isFalse);
      });
    });

    group('new place insertion via diff_applier', () {
      test('inserts new places and returns their IDs', () async {
        final diff = DiffResult(
          newRecords: [
            NormalizedPlaceRecord(
              mapsUrl: 'https://google.com/maps/place/NewCafe',
              sourceTitle: 'New Cafe',
              note: 'Just opened',
            ),
          ],
          updatedRecords: [],
          unchangedRecords: [],
          missingPlaceIds: [],
        );

        final newIds = await diffApplier.apply(diff);

        expect(newIds, hasLength(1));

        // Verify the place was inserted
        final allPlaces = await repository.listAll();
        expect(allPlaces, hasLength(1));
        expect(allPlaces.first.sourceTitle, equals('New Cafe'));
        expect(allPlaces.first.note, equals('Just opened'));
        expect(allPlaces.first.isDeletedCandidate, isFalse);
        expect(allPlaces.first.deletedMissCount, equals(0));
        expect(allPlaces.first.isHidden, isFalse);
      });
    });
  });
}
