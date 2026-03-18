import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/sync_job.dart';
import '../../domain/repositories/sync_job_repository.dart';
import 'supabase_helpers.dart';

class SupabaseSyncJobRepository implements SyncJobRepository {
  static const _table = 'sync_jobs';

  String get _userId => SupabaseHelpers.requireUserId();
  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<void> start(SyncJob job) async {
    await _client
        .from(_table)
        .insert(SupabaseHelpers.syncJobToRow(job, _userId));
  }

  @override
  Future<void> complete(
    String jobId, {
    SyncJobStatus status = SyncJobStatus.success,
    int newCount = 0,
    int updatedCount = 0,
    int unchangedCount = 0,
    int deletedCandidateCount = 0,
    int skippedRowCount = 0,
  }) async {
    await _client
        .from(_table)
        .update({
          'status': status.value,
          'ended_at': DateTime.now().toUtc().toIso8601String(),
          'new_count': newCount,
          'updated_count': updatedCount,
          'unchanged_count': unchangedCount,
          'deleted_candidate_count': deletedCandidateCount,
          'skipped_row_count': skippedRowCount,
        })
        .eq('id', jobId)
        .eq('user_id', _userId);
  }

  @override
  Future<void> fail(String jobId, String errorMessage) async {
    await _client
        .from(_table)
        .update({
          'status': SyncJobStatus.failed.value,
          'ended_at': DateTime.now().toUtc().toIso8601String(),
          'error_message': errorMessage,
        })
        .eq('id', jobId)
        .eq('user_id', _userId);
  }

  @override
  Future<SyncJob?> latest() async {
    final results = await _client
        .from(_table)
        .select()
        .eq('user_id', _userId)
        .order('started_at', ascending: false)
        .limit(1);
    if (results.isEmpty) return null;
    return SupabaseHelpers.syncJobFromRow(results.first);
  }

  @override
  Future<SyncJob?> findById(String jobId) async {
    final result = await _client
        .from(_table)
        .select()
        .eq('id', jobId)
        .eq('user_id', _userId)
        .maybeSingle();
    if (result == null) return null;
    return SupabaseHelpers.syncJobFromRow(result);
  }
}
