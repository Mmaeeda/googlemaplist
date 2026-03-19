import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/app_error.dart';
import '../../domain/models/sync_job.dart';
import '../../domain/models/sync_summary.dart';
import 'core_providers.dart';

// Place count (active, non-hidden)
final placeCountProvider = FutureProvider<int>((ref) async {
  final repo = ref.watch(placeRepositoryProvider);
  final places = await repo.listAllActive();
  return places.length;
});

// Rule count (enabled)
final ruleCountProvider = FutureProvider<int>((ref) async {
  final repo = ref.watch(classificationRuleRepositoryProvider);
  final rules = await repo.listEnabled();
  return rules.length;
});

// Last sync job
final lastSyncJobProvider = FutureProvider<SyncJob?>((ref) async {
  final repo = ref.watch(syncJobRepositoryProvider);
  return repo.latest();
});

// Sync action
final syncActionProvider =
    NotifierProvider<SyncActionNotifier, AsyncValue<SyncSummary?>>(
  SyncActionNotifier.new,
);

class SyncActionNotifier extends Notifier<AsyncValue<SyncSummary?>> {
  @override
  AsyncValue<SyncSummary?> build() => const AsyncData(null);

  Future<void> runSync() async {
    if (state is AsyncLoading) return;

    state = const AsyncLoading();
    try {
      final runSync = ref.read(syncPipelineRunProvider);
      final summary = await runSync();
      state = AsyncData(summary);

      // Invalidate dependent providers to refresh UI
      ref.invalidate(placeCountProvider);
      ref.invalidate(ruleCountProvider);
      ref.invalidate(lastSyncJobProvider);
    } on AppError catch (e, st) {
      if (e.code == AppErrorCode.tokenExpired ||
          e.code == AppErrorCode.authRequired) {
        // Token expired → sign out so user is redirected to login screen
        await ref.read(authStateProvider.notifier).signOut();
        state = const AsyncData(null);
      } else {
        state = AsyncError(e, st);
      }
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}
