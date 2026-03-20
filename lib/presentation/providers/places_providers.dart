import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/group.dart';
import '../../domain/models/place.dart';
import '../models/place_with_groups.dart';
import 'core_providers.dart';

// Group list for filter chips
final groupListProvider = FutureProvider<List<Group>>((ref) async {
  final repo = ref.watch(groupRepositoryProvider);
  return repo.listAll();
});

// Selected group filter (null = all)
final selectedGroupProvider =
    NotifierProvider<SelectedGroupNotifier, String?>(
  SelectedGroupNotifier.new,
);

class SelectedGroupNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? groupId) => state = groupId;
}

// Search query
final searchQueryProvider =
    NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void update(String query) => state = query;
}

// Filtered place list
final filteredPlacesProvider = FutureProvider<List<PlaceWithGroups>>((ref) async {
  final placeRepo = ref.watch(placeRepositoryProvider);
  final placeGroupRepo = ref.watch(placeGroupRepositoryProvider);
  final groupRepo = ref.watch(groupRepositoryProvider);
  final selectedGroupId = ref.watch(selectedGroupProvider);
  final searchQuery = ref.watch(searchQueryProvider).toLowerCase();

  final places = await placeRepo.listAllActive();
  final allGroups = await groupRepo.listAll();
  final groupMap = {for (final g in allGroups) g.id: g};

  final results = <PlaceWithGroups>[];

  for (final place in places) {
    final placeGroups = await placeGroupRepo.listByPlaceId(place.id);
    final groups = placeGroups
        .map((pg) => groupMap[pg.groupId])
        .whereType<Group>()
        .toList();

    // Filter by group
    if (selectedGroupId != null) {
      if (!placeGroups.any((pg) => pg.groupId == selectedGroupId)) {
        continue;
      }
    }

    // Filter by search query
    if (searchQuery.isNotEmpty) {
      final title = (place.sourceTitle ?? '').toLowerCase();
      final note = (place.note ?? '').toLowerCase();
      final collection = (place.collectionName ?? '').toLowerCase();
      if (!title.contains(searchQuery) &&
          !note.contains(searchQuery) &&
          !collection.contains(searchQuery)) {
        continue;
      }
    }

    results.add(PlaceWithGroups(place: place, groups: groups));
  }

  return results;
});

// Update a place's title
final placeUpdateProvider =
    NotifierProvider<PlaceUpdateNotifier, AsyncValue<void>>(
  PlaceUpdateNotifier.new,
);

class PlaceUpdateNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> updateTitle(Place place, String newTitle) async {
    final repo = ref.read(placeRepositoryProvider);
    final updated = place.copyWith(
      sourceTitle: newTitle.trim().isEmpty ? null : newTitle.trim(),
      updatedAt: DateTime.now(),
    );
    await repo.update(updated);
    ref.invalidate(filteredPlacesProvider);
  }
}
