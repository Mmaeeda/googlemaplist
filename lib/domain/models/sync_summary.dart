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
  /// Per-file breakdown: fileName → diagnostic string
  /// e.g. "5件" or "0件 (0行/45B, headers: タイトル,メモ,URL)"
  final Map<String, String> fileBreakdown;

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
    this.fileBreakdown = const {},
  });

  @override
  String toString() =>
      'SyncSummary(status: $status, new: $newCount, updated: $updatedCount, '
      'unchanged: $unchangedCount, deleted: $deletedCandidateCount)';
}
