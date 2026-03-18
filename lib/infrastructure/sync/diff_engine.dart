import '../../domain/models/diff_result.dart';
import '../../domain/models/normalized_place_record.dart';
import '../../domain/models/place.dart';
import '../../domain/repositories/place_repository.dart';
import '../logging/sync_logger.dart';
import 'source_key_generator.dart';

class DiffEngine {
  final PlaceRepository _placeRepository;
  final SourceKeyGenerator _sourceKeyGenerator;
  final SyncLogger _logger;

  DiffEngine(this._placeRepository, this._sourceKeyGenerator, this._logger);

  /// Compute the diff between incoming records and existing DB state.
  Future<DiffResult> compute(List<NormalizedPlaceRecord> records) async {
    final newRecords = <NormalizedPlaceRecord>[];
    final updatedRecords = <UpdatedRecord>[];
    final unchangedRecords = <UnchangedRecord>[];

    // Track which existing place IDs we've seen
    final seenPlaceIds = <String>{};

    var skippedCount = 0;

    for (final record in records) {
      final String sourceKey;
      try {
        sourceKey = _sourceKeyGenerator.generate(record);
      } catch (e) {
        _logger.warn('Skipping record: cannot generate source_key', {
          'error': e.toString(),
        });
        skippedCount++;
        continue;
      }

      final existing = await _placeRepository.findBySourceKey(sourceKey);

      if (existing == null) {
        // New record
        newRecords.add(record);
      } else {
        seenPlaceIds.add(existing.id);

        // Check for changes
        final changedFields = _detectChanges(existing, record);

        if (changedFields.isNotEmpty) {
          updatedRecords.add(UpdatedRecord(
            existingPlaceId: existing.id,
            record: record,
            changedFields: changedFields,
          ));
        } else {
          unchangedRecords.add(UnchangedRecord(
            existingPlaceId: existing.id,
            record: record,
          ));
        }
      }
    }

    // Find missing places (exist in DB but not in current input)
    final allPlaces = await _placeRepository.listAllActive();
    final missingPlaceIds = <String>[];

    for (final place in allPlaces) {
      if (!seenPlaceIds.contains(place.id) && !place.isHidden) {
        missingPlaceIds.add(place.id);
      }
    }

    final result = DiffResult(
      newRecords: newRecords,
      updatedRecords: updatedRecords,
      unchangedRecords: unchangedRecords,
      missingPlaceIds: missingPlaceIds,
      skippedCount: skippedCount,
    );

    _logger.info('diff_computed', {
      'newCount': result.newRecords.length,
      'updatedCount': result.updatedRecords.length,
      'unchangedCount': result.unchangedRecords.length,
      'missingCount': result.missingPlaceIds.length,
      'skippedCount': skippedCount,
    });

    return result;
  }

  /// Detect which fields have changed between existing and incoming record.
  List<String> _detectChanges(Place existing, NormalizedPlaceRecord incoming) {
    final changes = <String>[];

    if (_changed(existing.sourceTitle, incoming.sourceTitle)) {
      changes.add('source_title');
    }
    if (_changed(existing.mapsUrl, incoming.mapsUrl)) {
      changes.add('maps_url');
    }
    if (_changed(existing.note, incoming.note)) {
      changes.add('note');
    }
    if (_changed(existing.comments, incoming.comments)) {
      changes.add('comments');
    }
    if (_changed(existing.collectionName, incoming.collectionName)) {
      changes.add('collection_name');
    }
    if (_changed(existing.collectionDescription, incoming.collectionDescription)) {
      changes.add('collection_description');
    }

    return changes;
  }

  /// Compare two nullable strings, treating null and empty as equivalent.
  bool _changed(String? a, String? b) {
    final normalizedA = (a ?? '').trim();
    final normalizedB = (b ?? '').trim();
    return normalizedA != normalizedB;
  }
}
