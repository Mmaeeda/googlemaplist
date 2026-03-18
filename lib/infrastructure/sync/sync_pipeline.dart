import '../../domain/models/sync_summary.dart';

/// Abstract sync pipeline interface.
/// Both SyncOrchestrator (native) and WebSyncOrchestrator (web) implement this.
abstract class SyncPipeline {
  Future<SyncSummary> runSync([SyncPipelineOptions options]);
}

class SyncPipelineOptions {
  final bool forceSync;
  final bool rebuildOnly;

  const SyncPipelineOptions({
    this.forceSync = false,
    this.rebuildOnly = false,
  });
}
