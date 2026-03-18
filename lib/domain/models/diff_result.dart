import 'normalized_place_record.dart';

class UpdatedRecord {
  final String existingPlaceId;
  final NormalizedPlaceRecord record;
  final List<String> changedFields;

  const UpdatedRecord({
    required this.existingPlaceId,
    required this.record,
    required this.changedFields,
  });
}

class UnchangedRecord {
  final String existingPlaceId;
  final NormalizedPlaceRecord record;

  const UnchangedRecord({
    required this.existingPlaceId,
    required this.record,
  });
}

class DiffResult {
  final List<NormalizedPlaceRecord> newRecords;
  final List<UpdatedRecord> updatedRecords;
  final List<UnchangedRecord> unchangedRecords;
  final List<String> missingPlaceIds;
  final int skippedCount;

  const DiffResult({
    required this.newRecords,
    required this.updatedRecords,
    required this.unchangedRecords,
    required this.missingPlaceIds,
    this.skippedCount = 0,
  });

  /// IDs of places that were updated (for re-classification).
  /// New place IDs are not available here — they are assigned during insertion
  /// by DiffApplier, which returns them separately.
  List<String> get updatedPlaceIds {
    return updatedRecords.map((r) => r.existingPlaceId).toList();
  }

  @override
  String toString() =>
      'DiffResult(new: ${newRecords.length}, updated: ${updatedRecords.length}, '
      'unchanged: ${unchangedRecords.length}, missing: ${missingPlaceIds.length}, '
      'skipped: $skippedCount)';
}
