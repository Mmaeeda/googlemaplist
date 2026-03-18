import 'package:uuid/uuid.dart';

import '../../domain/models/diff_result.dart';
import '../../domain/models/place.dart';
import '../../domain/repositories/place_repository.dart';
import '../logging/sync_logger.dart';
import 'source_key_generator.dart';

/// Applies a DiffResult to the database.
class DiffApplier {
  final PlaceRepository _placeRepository;
  final SourceKeyGenerator _sourceKeyGenerator;
  final SyncLogger _logger;
  static const _uuid = Uuid();

  DiffApplier(this._placeRepository, this._sourceKeyGenerator, this._logger);

  /// Apply the diff: insert new, update changed, mark missing.
  /// Returns the list of place IDs that were newly inserted.
  Future<List<String>> apply(DiffResult diff) async {
    final now = DateTime.now();
    final newPlaceIds = <String>[];

    _logger.info('db_transaction_started', {
      'newCount': diff.newRecords.length,
      'updatedCount': diff.updatedRecords.length,
      'missingCount': diff.missingPlaceIds.length,
    });

    // Insert new records
    for (final record in diff.newRecords) {
      final id = _uuid.v4();
      final sourceKey = _sourceKeyGenerator.generate(record);

      final place = Place(
        id: id,
        sourceKey: sourceKey,
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

      await _placeRepository.insert(place);
      newPlaceIds.add(id);
    }

    // Update existing records
    for (final updated in diff.updatedRecords) {
      final existing = await _placeRepository.findById(updated.existingPlaceId);
      if (existing == null) continue;

      final updatedPlace = existing.copyWith(
        sourceTitle: updated.record.sourceTitle,
        mapsUrl: updated.record.mapsUrl,
        note: updated.record.note,
        comments: updated.record.comments,
        collectionName: updated.record.collectionName,
        collectionDescription: updated.record.collectionDescription,
        rawPayloadJson: updated.record.rawPayloadJson,
        updatedAt: now,
        lastSeenAt: now,
        // Reset deletion flags when seen again
        isDeletedCandidate: false,
        deletedMissCount: 0,
      );

      await _placeRepository.update(updatedPlace);
    }

    // Update lastSeenAt for unchanged records
    for (final unchanged in diff.unchangedRecords) {
      final existing =
          await _placeRepository.findById(unchanged.existingPlaceId);
      if (existing == null) continue;

      final refreshed = existing.copyWith(
        lastSeenAt: now,
        // Reset deletion flags when seen again
        isDeletedCandidate: false,
        deletedMissCount: 0,
      );

      await _placeRepository.update(refreshed);
    }

    // Mark missing places
    for (final placeId in diff.missingPlaceIds) {
      await _placeRepository.markMissing(placeId);
    }

    _logger.info('db_transaction_completed', {
      'insertedCount': newPlaceIds.length,
      'updatedCount': diff.updatedRecords.length,
      'missingCount': diff.missingPlaceIds.length,
    });

    return newPlaceIds;
  }
}
