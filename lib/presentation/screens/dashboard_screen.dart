import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/sync_job.dart';
import '../providers/dashboard_providers.dart';
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
