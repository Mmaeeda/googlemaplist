import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../infrastructure/csv/tag_csv_download.dart' as csv_download;
import '../../infrastructure/csv/tag_csv_upload.dart' as csv_upload;
import '../../infrastructure/csv/tag_csv_service.dart';
import '../providers/places_providers.dart';
import '../providers/settings_providers.dart';
import '../theme/app_colors.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exportState = ref.watch(tagCsvExportProvider);
    final importState = ref.watch(tagCsvImportProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < 600;
        final padding = isMobile ? 16.0 : 32.0;

        return SingleChildScrollView(
          padding: EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '設定',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      fontSize: isMobile ? 24 : null,
                    ),
              ),
              const SizedBox(height: 24),

              // Data Management Section
              Text(
                'データ管理',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Export
                      Row(
                        children: [
                          const Icon(LucideIcons.download, size: 20, color: AppColors.textSecondary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'タグ割り当てをCSVエクスポート',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '全場所のグループ割り当てをCSVファイルとしてダウンロードします',
                                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: exportState is AsyncLoading
                                ? null
                                : () => _handleExport(context, ref),
                            child: exportState is AsyncLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('エクスポート'),
                          ),
                        ],
                      ),

                      const Divider(height: 32),

                      // Import
                      Row(
                        children: [
                          const Icon(LucideIcons.upload, size: 20, color: AppColors.textSecondary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'タグ割り当てをCSVインポート',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'CSVファイルからグループ割り当てを一括更新します。存在しないグループ名は自動作成されます',
                                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: importState is AsyncLoading
                                ? null
                                : () => _handleImport(context, ref),
                            child: importState is AsyncLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('インポート'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Import result
              if (importState is AsyncData<TagCsvImportResult?> &&
                  importState.value != null) ...[
                const SizedBox(height: 16),
                _ImportResultCard(result: importState.value!),
              ],

              if (importState is AsyncError) ...[
                const SizedBox(height: 16),
                Card(
                  color: AppColors.googleRed.withValues(alpha: 0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'インポートエラー: ${importState.error}',
                      style: const TextStyle(color: AppColors.googleRed),
                    ),
                  ),
                ),
              ],

              if (exportState is AsyncError) ...[
                const SizedBox(height: 16),
                Card(
                  color: AppColors.googleRed.withValues(alpha: 0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'エクスポートエラー: ${exportState.error}',
                      style: const TextStyle(color: AppColors.googleRed),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleExport(BuildContext context, WidgetRef ref) async {
    final csv = await ref.read(tagCsvExportProvider.notifier).export();
    if (csv != null && context.mounted) {
      try {
        final now = DateTime.now();
        final fileName =
            'tag_assignments_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.csv';
        await csv_download.downloadCsvFile(csv, fileName);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('CSVファイルをダウンロードしました')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('ダウンロードエラー: $e')),
          );
        }
      }
    }
  }

  Future<void> _handleImport(BuildContext context, WidgetRef ref) async {
    try {
      final csvContent = await csv_upload.pickCsvFile();
      if (csvContent == null) return; // user cancelled

      if (!context.mounted) return;

      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('CSVインポート'),
          content: const Text(
            'CSVファイルの内容でタグ割り当てを更新します。\n'
            '既存のタグ割り当ては上書きされます。\n\n'
            '続行しますか？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('インポート'),
            ),
          ],
        ),
      );

      if (confirmed != true || !context.mounted) return;

      final result =
          await ref.read(tagCsvImportProvider.notifier).import(csvContent);
      if (result != null && context.mounted) {
        // Refresh places list
        ref.invalidate(filteredPlacesProvider);
        ref.invalidate(groupListProvider);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'インポート完了: ${result.updatedCount}件更新'
              '${result.newGroupsCreated > 0 ? '、${result.newGroupsCreated}グループ新規作成' : ''}',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ファイル選択エラー: $e')),
        );
      }
    }
  }
}

class _ImportResultCard extends StatelessWidget {
  final TagCsvImportResult result;

  const _ImportResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: result.errors.isEmpty
          ? AppColors.primaryLight
          : AppColors.googleYellow.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'インポート結果',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text('対象行数: ${result.totalRows}'),
            Text('更新成功: ${result.updatedCount}件'),
            if (result.skippedCount > 0)
              Text('スキップ: ${result.skippedCount}件'),
            if (result.newGroupsCreated > 0)
              Text('新規グループ作成: ${result.newGroupsCreated}件'),
            if (result.errors.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'エラー:',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.googleRed,
                ),
              ),
              const SizedBox(height: 4),
              ...result.errors.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: Text(
                    '• $e',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.googleRed,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
