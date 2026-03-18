import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/classification_rule.dart';
import 'core_providers.dart';

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
