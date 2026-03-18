enum SyncJobStatus {
  running,
  success,
  failed,
  partial;

  String get value {
    switch (this) {
      case SyncJobStatus.running:
        return 'running';
      case SyncJobStatus.success:
        return 'success';
      case SyncJobStatus.failed:
        return 'failed';
      case SyncJobStatus.partial:
        return 'partial';
    }
  }

  static SyncJobStatus fromString(String value) {
    switch (value) {
      case 'running':
        return SyncJobStatus.running;
      case 'success':
        return SyncJobStatus.success;
      case 'failed':
        return SyncJobStatus.failed;
      case 'partial':
        return SyncJobStatus.partial;
      default:
        throw ArgumentError('Unknown SyncJobStatus: $value');
    }
  }
}

class SyncJob {
  final String id;
  final String archiveIdentifier;
  final String archiveName;
  final DateTime startedAt;
  final DateTime? endedAt;
  final SyncJobStatus status;
  final int newCount;
  final int updatedCount;
  final int unchangedCount;
  final int deletedCandidateCount;
  final int skippedRowCount;
  final String? errorMessage;

  const SyncJob({
    required this.id,
    required this.archiveIdentifier,
    required this.archiveName,
    required this.startedAt,
    this.endedAt,
    required this.status,
    this.newCount = 0,
    this.updatedCount = 0,
    this.unchangedCount = 0,
    this.deletedCandidateCount = 0,
    this.skippedRowCount = 0,
    this.errorMessage,
  });

  SyncJob copyWith({
    String? id,
    String? archiveIdentifier,
    String? archiveName,
    DateTime? startedAt,
    DateTime? endedAt,
    SyncJobStatus? status,
    int? newCount,
    int? updatedCount,
    int? unchangedCount,
    int? deletedCandidateCount,
    int? skippedRowCount,
    String? errorMessage,
  }) {
    return SyncJob(
      id: id ?? this.id,
      archiveIdentifier: archiveIdentifier ?? this.archiveIdentifier,
      archiveName: archiveName ?? this.archiveName,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      status: status ?? this.status,
      newCount: newCount ?? this.newCount,
      updatedCount: updatedCount ?? this.updatedCount,
      unchangedCount: unchangedCount ?? this.unchangedCount,
      deletedCandidateCount: deletedCandidateCount ?? this.deletedCandidateCount,
      skippedRowCount: skippedRowCount ?? this.skippedRowCount,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'archive_identifier': archiveIdentifier,
      'archive_name': archiveName,
      'started_at': startedAt.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'status': status.value,
      'new_count': newCount,
      'updated_count': updatedCount,
      'unchanged_count': unchangedCount,
      'deleted_candidate_count': deletedCandidateCount,
      'skipped_row_count': skippedRowCount,
      'error_message': errorMessage,
    };
  }

  factory SyncJob.fromMap(Map<String, dynamic> map) {
    return SyncJob(
      id: map['id'] as String,
      archiveIdentifier: map['archive_identifier'] as String,
      archiveName: map['archive_name'] as String,
      startedAt: DateTime.parse(map['started_at'] as String),
      endedAt: map['ended_at'] != null
          ? DateTime.parse(map['ended_at'] as String)
          : null,
      status: SyncJobStatus.fromString(map['status'] as String),
      newCount: map['new_count'] as int,
      updatedCount: map['updated_count'] as int,
      unchangedCount: map['unchanged_count'] as int,
      deletedCandidateCount: map['deleted_candidate_count'] as int,
      skippedRowCount: map['skipped_row_count'] as int,
      errorMessage: map['error_message'] as String?,
    );
  }

  @override
  String toString() =>
      'SyncJob(id: $id, status: ${status.value}, new: $newCount, updated: $updatedCount)';
}
