import '../models/sync_job.dart';

abstract class SyncJobRepository {
  Future<void> start(SyncJob job);
  Future<void> complete(String jobId, {
    SyncJobStatus status = SyncJobStatus.success,
    int newCount = 0,
    int updatedCount = 0,
    int unchangedCount = 0,
    int deletedCandidateCount = 0,
    int skippedRowCount = 0,
  });
  Future<void> fail(String jobId, String errorMessage);
  Future<SyncJob?> latest();
  Future<SyncJob?> findById(String jobId);
}
