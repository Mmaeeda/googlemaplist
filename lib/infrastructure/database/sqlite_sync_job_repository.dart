import 'package:sqflite/sqflite.dart';

import '../../domain/models/sync_job.dart';
import '../../domain/repositories/sync_job_repository.dart';
import 'app_database.dart';

class SqliteSyncJobRepository implements SyncJobRepository {
  final AppDatabase _appDatabase;

  SqliteSyncJobRepository(this._appDatabase);

  Future<Database> get _db => _appDatabase.database;

  @override
  Future<void> start(SyncJob job) async {
    final db = await _db;
    await db.insert('sync_jobs', job.toMap());
  }

  @override
  Future<void> complete(String jobId, {
    SyncJobStatus status = SyncJobStatus.success,
    int newCount = 0,
    int updatedCount = 0,
    int unchangedCount = 0,
    int deletedCandidateCount = 0,
    int skippedRowCount = 0,
  }) async {
    final db = await _db;
    await db.update(
      'sync_jobs',
      {
        'status': status.value,
        'ended_at': DateTime.now().toIso8601String(),
        'new_count': newCount,
        'updated_count': updatedCount,
        'unchanged_count': unchangedCount,
        'deleted_candidate_count': deletedCandidateCount,
        'skipped_row_count': skippedRowCount,
      },
      where: 'id = ?',
      whereArgs: [jobId],
    );
  }

  @override
  Future<void> fail(String jobId, String errorMessage) async {
    final db = await _db;
    await db.update(
      'sync_jobs',
      {
        'status': SyncJobStatus.failed.value,
        'ended_at': DateTime.now().toIso8601String(),
        'error_message': errorMessage,
      },
      where: 'id = ?',
      whereArgs: [jobId],
    );
  }

  @override
  Future<SyncJob?> latest() async {
    final db = await _db;
    final results = await db.query(
      'sync_jobs',
      orderBy: 'started_at DESC',
      limit: 1,
    );
    if (results.isEmpty) return null;
    return SyncJob.fromMap(results.first);
  }

  @override
  Future<SyncJob?> findById(String jobId) async {
    final db = await _db;
    final results = await db.query(
      'sync_jobs',
      where: 'id = ?',
      whereArgs: [jobId],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return SyncJob.fromMap(results.first);
  }
}
