class SyncSummary {
  final String status; // "success" | "failed" | "partial"
  final int newCount;
  final int updatedCount;
  final int unchangedCount;
  final int deletedCandidateCount;
  final int skippedRowCount;
  final String? archiveName;
  /// Number of archive groups processed
  final int archiveGroupCount;
  /// Number of data files (CSV/JSON) found
  final int dataFileCount;
  /// Total normalized records parsed
  final int parsedRecordCount;

  const SyncSummary({
    required this.status,
    this.newCount = 0,
    this.updatedCount = 0,
    this.unchangedCount = 0,
    this.deletedCandidateCount = 0,
    this.skippedRowCount = 0,
    this.archiveName,
    this.archiveGroupCount = 0,
    this.dataFileCount = 0,
    this.parsedRecordCount = 0,
  });

  @override
  String toString() =>
      'SyncSummary(status: $status, new: $newCount, updated: $updatedCount, '
      'unchanged: $unchangedCount, deleted: $deletedCandidateCount)';
}
