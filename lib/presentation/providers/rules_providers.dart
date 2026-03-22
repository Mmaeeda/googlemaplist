import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/classification_rule.dart';
import '../../domain/models/group.dart';
import 'core_providers.dart';
import 'places_providers.dart';

// Rule list
final ruleListProvider = FutureProvider<List<ClassificationRule>>((ref) async {
  final repo = ref.watch(classificationRuleRepositoryProvider);
  return repo.listAll();
});

// Rule CRUD
final ruleCrudProvider =
    NotifierProvider<RuleCrudNotifier, AsyncValue<void>>(
  RuleCrudNotifier.new,
);

class RuleCrudNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> addRule(ClassificationRule rule) async {
    state = const AsyncLoading();
    try {
      final repo = ref.read(classificationRuleRepositoryProvider);
      await repo.insert(rule);
      ref.invalidate(ruleListProvider);
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> updateRule(ClassificationRule rule) async {
    state = const AsyncLoading();
    try {
      final repo = ref.read(classificationRuleRepositoryProvider);
      await repo.update(rule);
      ref.invalidate(ruleListProvider);
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> deleteRule(String ruleId) async {
    state = const AsyncLoading();
    try {
      final repo = ref.read(classificationRuleRepositoryProvider);
      await repo.delete(ruleId);
      ref.invalidate(ruleListProvider);
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

// Group CRUD
final groupCrudProvider =
    NotifierProvider<GroupCrudNotifier, AsyncValue<void>>(
  GroupCrudNotifier.new,
);

class GroupCrudNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> addGroup(Group group) async {
    state = const AsyncLoading();
    try {
      final repo = ref.read(groupRepositoryProvider);
      await repo.upsert(group);
      ref.invalidate(groupListProvider);
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> updateGroup(Group group) async {
    state = const AsyncLoading();
    try {
      final repo = ref.read(groupRepositoryProvider);
      await repo.upsert(group);
      ref.invalidate(groupListProvider);
      ref.invalidate(filteredPlacesProvider);
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> deleteGroup(String groupId) async {
    state = const AsyncLoading();
    try {
      final repo = ref.read(groupRepositoryProvider);
      await repo.delete(groupId);
      ref.invalidate(groupListProvider);
      ref.invalidate(filteredPlacesProvider);
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}
