import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/classification_rule.dart';
import '../../domain/repositories/classification_rule_repository.dart';
import 'supabase_helpers.dart';

class SupabaseClassificationRuleRepository
    implements ClassificationRuleRepository {
  static const _table = 'classification_rules';

  String get _userId => SupabaseHelpers.requireUserId();
  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<List<ClassificationRule>> listAll() async {
    final results = await _client
        .from(_table)
        .select()
        .eq('user_id', _userId)
        .order('priority', ascending: true);
    return results.map(SupabaseHelpers.ruleFromRow).toList();
  }

  @override
  Future<List<ClassificationRule>> listEnabled() async {
    final results = await _client
        .from(_table)
        .select()
        .eq('user_id', _userId)
        .eq('enabled', true)
        .order('priority', ascending: true);
    return results.map(SupabaseHelpers.ruleFromRow).toList();
  }

  @override
  Future<void> insert(ClassificationRule rule) async {
    await _client
        .from(_table)
        .insert(SupabaseHelpers.ruleToRow(rule, _userId));
  }

  @override
  Future<void> update(ClassificationRule rule) async {
    await _client
        .from(_table)
        .update(SupabaseHelpers.ruleToRow(rule, _userId))
        .eq('id', rule.id)
        .eq('user_id', _userId);
  }

  @override
  Future<void> delete(String ruleId) async {
    await _client
        .from(_table)
        .delete()
        .eq('id', ruleId)
        .eq('user_id', _userId);
  }
}
