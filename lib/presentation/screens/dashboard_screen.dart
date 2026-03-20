import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/sync_job.dart';
import '../../domain/models/sync_summary.dart';
import '../providers/core_providers.dart';
import '../providers/dashboard_providers.dart';
import '../providers/places_providers.dart';
import '../theme/app_colors.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placeCount = ref.watch(placeCountProvider);
    final ruleCount = ref.watch(ruleCountProvider);
    final lastSync = ref.watch(lastSyncJobProvider);
    final syncAction = ref.watch(syncActionProvider);

    final placeValue = placeCount.when(
      data: (count) => '$count',
      loading: () => '...',
      error: (e, st) => '-',
    );

    final ruleValue = ruleCount.when(
      data: (count) => '$count',
      loading: () => '...',
      error: (e, st) => '-',
    );

    final lastSyncValue = lastSync.when(
      data: (job) => job != null ? _formatSyncTime(job) : '未実施',
      loading: () => '...',
      error: (e, st) => '-',
    );

    final isSyncing = syncAction is AsyncLoading;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < 600;

        return Padding(
          padding: EdgeInsets.all(isMobile ? 16.0 : 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'ダッシュボード',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                          fontSize: isMobile ? 24 : null,
                        ),
                  ),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: isSyncing
                            ? null
                            : () => ref.read(syncActionProvider.notifier).runSync(),
                        icon: isSyncing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sync),
                        label: isMobile
                            ? const Text('')
                            : Text(isSyncing ? '同期中...' : '今すぐ同期'),
                      ),
                      const SizedBox(width: 8),
                      _PhotoFetchButton(isMobile: isMobile),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => ref.read(authStateProvider.notifier).signOut(),
                        icon: const Icon(Icons.logout),
                        tooltip: 'ログアウト',
                        style: IconButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: isMobile ? 16 : 32),
              // Stats
              isMobile
                  ? Column(
                      children: [
                        _StatCard(title: '登録済み件数', value: placeValue, icon: Icons.map, iconColor: AppColors.googleBlue),
                        const SizedBox(height: 16),
                        _StatCard(title: '有効なルール', value: ruleValue, icon: Icons.rule, iconColor: AppColors.googleYellow),
                        const SizedBox(height: 16),
                        _StatCard(title: '最終同期', value: lastSyncValue, icon: Icons.access_time, iconColor: AppColors.googleRed),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: _StatCard(title: '登録済み件数', value: placeValue, icon: Icons.map, iconColor: AppColors.googleBlue)),
                        const SizedBox(width: 24),
                        Expanded(child: _StatCard(title: '有効なルール', value: ruleValue, icon: Icons.rule, iconColor: AppColors.googleYellow)),
                        const SizedBox(width: 24),
                        Expanded(child: _StatCard(title: '最終同期', value: lastSyncValue, icon: Icons.access_time, iconColor: AppColors.googleRed)),
                      ],
                    ),
              // Sync error display
              if (syncAction is AsyncError)
                Padding(
                  padding: EdgeInsets.only(bottom: isMobile ? 16 : 24),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.googleRed.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.googleRed.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.googleRed, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '同期エラー: ${(syncAction as AsyncError).error}',
                            style: const TextStyle(color: AppColors.googleRed, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // Sync success display
              if (syncAction case AsyncData<SyncSummary?>(:final value?))
                Padding(
                  padding: EdgeInsets.only(bottom: isMobile ? 16 : 24),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline, color: AppColors.primary, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '同期完了: 新規${value.newCount}件 / 更新${value.updatedCount}件 / 未変更${value.unchangedCount}件',
                            style: TextStyle(color: AppColors.primary, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              SizedBox(height: isMobile ? 24 : 32),
              Text(
                '最近のアクティビティ',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _ActivitySection(lastSync: lastSync, syncAction: syncAction),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatSyncTime(SyncJob job) {
    final diff = DateTime.now().difference(job.startedAt);
    if (diff.inMinutes < 1) return 'たった今';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分前';
    if (diff.inHours < 24) return '${diff.inHours}時間前';
    return '${diff.inDays}日前';
  }
}

class _ActivitySection extends StatelessWidget {
  final AsyncValue<SyncJob?> lastSync;
  final AsyncValue syncAction;

  const _ActivitySection({required this.lastSync, required this.syncAction});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: lastSync.when(
        data: (job) {
          if (job == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  '同期を実行するとアクティビティが表示されます',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            );
          }
          return _buildSyncSummary(context, job);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => const Center(
          child: Text('読み込みエラー', style: TextStyle(color: AppColors.googleRed)),
        ),
      ),
    );
  }

  Widget _buildSyncSummary(BuildContext context, SyncJob job) {
    final items = <_ActivityItem>[
      _ActivityItem(
        icon: Icons.sync,
        iconColor: _statusColor(job.status),
        title: '同期 ${_statusLabel(job.status)}',
        subtitle: job.archiveName,
        time: _formatTime(job.startedAt),
      ),
      if (job.newCount > 0)
        _ActivityItem(
          icon: Icons.add_location_alt,
          iconColor: AppColors.primary,
          title: '${job.newCount}件の新規スポットを追加',
          subtitle: '',
          time: '',
        ),
      if (job.updatedCount > 0)
        _ActivityItem(
          icon: Icons.update,
          iconColor: AppColors.googleBlue,
          title: '${job.updatedCount}件のスポットを更新',
          subtitle: '',
          time: '',
        ),
      if (job.deletedCandidateCount > 0)
        _ActivityItem(
          icon: Icons.remove_circle_outline,
          iconColor: AppColors.googleRed,
          title: '${job.deletedCandidateCount}件の削除候補を検出',
          subtitle: '',
          time: '',
        ),
      if (job.errorMessage != null)
        _ActivityItem(
          icon: Icons.error_outline,
          iconColor: AppColors.googleRed,
          title: 'エラー',
          subtitle: job.errorMessage!,
          time: '',
        ),
    ];

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.surface,
            child: Icon(item.icon, color: item.iconColor),
          ),
          title: Text(item.title),
          subtitle: item.subtitle.isNotEmpty ? Text(item.subtitle) : null,
          trailing: item.time.isNotEmpty
              ? Text(item.time, style: const TextStyle(color: AppColors.textSecondary))
              : null,
        );
      },
    );
  }

  Color _statusColor(SyncJobStatus status) {
    switch (status) {
      case SyncJobStatus.success:
        return AppColors.primary;
      case SyncJobStatus.failed:
        return AppColors.googleRed;
      case SyncJobStatus.partial:
        return AppColors.googleYellow;
      case SyncJobStatus.running:
        return AppColors.googleBlue;
    }
  }

  String _statusLabel(SyncJobStatus status) {
    switch (status) {
      case SyncJobStatus.success:
        return '完了';
      case SyncJobStatus.failed:
        return '失敗';
      case SyncJobStatus.partial:
        return '一部完了';
      case SyncJobStatus.running:
        return '実行中';
    }
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'たった今';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分前';
    if (diff.inHours < 24) return '${diff.inHours}時間前';
    return '${diff.inDays}日前';
  }
}

class _ActivityItem {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String time;

  const _ActivityItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.time,
  });
}

class _PhotoFetchButton extends ConsumerWidget {
  final bool isMobile;

  const _PhotoFetchButton({required this.isMobile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoFetch = ref.watch(photoFetchProvider);
    final apiKey = ref.watch(apiKeyProvider);
    final isFetching = photoFetch.isRunning;

    return ElevatedButton.icon(
      onPressed: isFetching
          ? null
          : () => _handlePhotoFetch(context, ref, apiKey),
      icon: isFetching
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.photo_camera),
      label: isMobile
          ? const Text('')
          : Text(isFetching
              ? '${photoFetch.current}/${photoFetch.total}'
              : '写真取得'),
    );
  }

  Future<void> _handlePhotoFetch(
    BuildContext context,
    WidgetRef ref,
    String? currentKey,
  ) async {
    // Show API key dialog if not set
    if (currentKey == null || currentKey.isEmpty) {
      final key = await _showApiKeyDialog(context, currentKey);
      if (key == null || key.isEmpty) return;
      ref.read(apiKeyProvider.notifier).set(key);
    }

    try {
      await ref.read(photoFetchProvider.notifier).fetchPhotos();
      final resolved = ref.read(photoFetchProvider).resolved;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$resolved件の写真を取得しました')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('写真取得エラー: $e')),
        );
      }
    }
  }

  Future<String?> _showApiKeyDialog(
    BuildContext context,
    String? currentKey,
  ) async {
    final controller = TextEditingController(text: currentKey ?? '');
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Google Places API キー'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '場所の写真を取得するには、Google Cloud Console で '
              'Places API (New) を有効化し、APIキーを入力してください。',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'AIza...',
                border: OutlineInputBorder(),
                labelText: 'API キー',
              ),
              onSubmitted: (value) => Navigator.of(context).pop(value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('保存して取得開始'),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color iconColor;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    this.iconColor = AppColors.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
