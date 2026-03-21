import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../domain/models/group.dart';
import '../../domain/models/place.dart';
import '../models/place_with_groups.dart';
import '../providers/places_providers.dart';
import '../theme/app_colors.dart';

class PlacesScreen extends ConsumerWidget {
  const PlacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupListProvider);
    final selectedGroupId = ref.watch(selectedGroupProvider);
    final filteredPlaces = ref.watch(filteredPlacesProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < 600;

        final searchField = TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: '場所を検索...',
          ),
          onChanged: (value) =>
              ref.read(searchQueryProvider.notifier).update(value),
        );

        Widget buildFilterChips({bool horizontal = false}) {
          return groups.when(
            data: (groupList) {
              final chips = <Widget>[
                _FilterChip(
                  label: 'すべて',
                  isSelected: selectedGroupId == null,
                  onSelected: () =>
                      ref.read(selectedGroupProvider.notifier).select(null),
                ),
                ...groupList.map((group) => _FilterChip(
                      label: group.name,
                      isSelected: selectedGroupId == group.id,
                      onSelected: () =>
                          ref.read(selectedGroupProvider.notifier).select(
                              group.id),
                    )),
              ];
              if (horizontal) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: chips.map((c) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: c,
                    )).toList(),
                  ),
                );
              }
              return Wrap(spacing: 8, children: chips);
            },
            loading: () => const SizedBox.shrink(),
            error: (e, st) => const SizedBox.shrink(),
          );
        }

        // Mobile: compact header, list fills remaining space
        if (isMobile) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '場所リスト',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                ),
                const SizedBox(height: 8),
                searchField,
                const SizedBox(height: 8),
                buildFilterChips(horizontal: true),
                const SizedBox(height: 8),
                Expanded(
                  child: filteredPlaces.when(
                    data: (places) => _PlaceList(places: places),
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(
                      child: Text('エラー: $e',
                          style: const TextStyle(color: AppColors.googleRed)),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // Desktop: fixed layout
        return Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '場所リスト',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                  ),
                  SizedBox(width: 280, child: searchField),
                ],
              ),
              const SizedBox(height: 32),
              buildFilterChips(),
              const SizedBox(height: 24),
              Expanded(
                child: filteredPlaces.when(
                  data: (places) => _PlaceList(places: places),
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Text('エラー: $e',
                        style: const TextStyle(color: AppColors.googleRed)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlaceList extends ConsumerWidget {
  final List<PlaceWithGroups> places;
  final bool shrinkWrap;

  const _PlaceList({required this.places, this.shrinkWrap = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (places.isEmpty) {
      return const Card(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              '場所が見つかりません\n同期を実行してデータを取り込みましょう',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
      );
    }

    return Card(
      child: ListView.separated(
        shrinkWrap: shrinkWrap,
        physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
        itemCount: places.length,
        separatorBuilder: (context, index) => const Divider(),
        itemBuilder: (context, index) {
          final item = places[index];
          final place = item.place;
          final subtitle = [
            if (place.collectionName != null && place.collectionName!.isNotEmpty)
              place.collectionName!,
            if (place.note != null && place.note!.isNotEmpty) place.note!,
          ].join('\n');

          return ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            leading: _PlacePhoto(photoUrl: place.photoUrl),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    place.sourceTitle ?? '(タイトルなし)',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                _EditButton(
                  place: place,
                  onSaved: () => ref.invalidate(filteredPlacesProvider),
                ),
              ],
            ),
            subtitle: subtitle.isNotEmpty
                ? Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis)
                : null,
            isThreeLine: subtitle.contains('\n'),
            trailing: Wrap(
              spacing: 8,
              children: [
                ...item.groups.map((group) => _GroupChip(group: group)),
                if (place.mapsUrl != null)
                  const Icon(Icons.open_in_new,
                      size: 16, color: AppColors.textSecondary),
              ],
            ),
            onTap: place.mapsUrl != null
                ? () => launchUrl(
                      Uri.parse(place.mapsUrl!),
                      mode: LaunchMode.externalApplication,
                    )
                : null,
          );
        },
      ),
    );
  }
}

class _EditButton extends ConsumerWidget {
  final Place place;
  final VoidCallback onSaved;

  const _EditButton({required this.place, required this.onSaved});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.edit_outlined, size: 18),
      color: AppColors.textSecondary,
      tooltip: '名前を編集',
      onPressed: () => _showEditDialog(context, ref),
    );
  }

  Future<void> _showEditDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: place.sourceTitle ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('場所の名前を編集'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '場所の名前を入力',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (result == null) return; // cancelled

    try {
      await ref.read(placeUpdateProvider.notifier).updateTitle(place, result);
      onSaved();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('名前を更新しました')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新に失敗しました: $e')),
        );
      }
    }
  }
}

class _GroupChip extends StatelessWidget {
  final Group group;

  const _GroupChip({required this.group});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(group.name, style: const TextStyle(fontSize: 12)),
      backgroundColor: AppColors.background,
      side: const BorderSide(color: AppColors.border),
    );
  }
}

class _PlacePhoto extends StatelessWidget {
  final String? photoUrl;

  const _PlacePhoto({required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 22,
        backgroundImage: NetworkImage(photoUrl!),
        backgroundColor: AppColors.surface,
        onBackgroundImageError: (_, _) {},
      );
    }
    return const CircleAvatar(
      radius: 22,
      backgroundColor: AppColors.surface,
      child: Icon(Icons.place, color: AppColors.textSecondary, size: 20),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onSelected;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      selectedColor: AppColors.primaryLight,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? AppColors.primary : AppColors.border,
        ),
      ),
    );
  }
}
