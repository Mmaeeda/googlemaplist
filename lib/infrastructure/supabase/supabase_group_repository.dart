import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/app_error.dart';
import '../../domain/models/group.dart';
import '../../domain/repositories/group_repository.dart';
import 'supabase_helpers.dart';

class SupabaseGroupRepository implements GroupRepository {
  static const _table = 'groups';

  String get _userId => SupabaseHelpers.requireUserId();
  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<List<Group>> listAll() async {
    final results = await _client
        .from(_table)
        .select()
        .eq('user_id', _userId)
        .order('sort_order', ascending: true);
    return results.map(SupabaseHelpers.groupFromRow).toList();
  }

  @override
  Future<Group?> findById(String id) async {
    final result = await _client
        .from(_table)
        .select()
        .eq('id', id)
        .eq('user_id', _userId)
        .maybeSingle();
    if (result == null) return null;
    return SupabaseHelpers.groupFromRow(result);
  }

  @override
  Future<Group?> findByName(String name) async {
    final result = await _client
        .from(_table)
        .select()
        .eq('name', name)
        .eq('user_id', _userId)
        .maybeSingle();
    if (result == null) return null;
    return SupabaseHelpers.groupFromRow(result);
  }

  @override
  Future<void> upsert(Group group) async {
    await _client
        .from(_table)
        .upsert(SupabaseHelpers.groupToRow(group, _userId));
  }

  @override
  Future<void> delete(String groupId) async {
    final group = await findById(groupId);
    if (group != null && group.systemGroup) {
      throw AppError(
        AppErrorCode.dbWriteFailed,
        'Cannot delete system group: ${group.name}',
      );
    }
    await _client
        .from(_table)
        .delete()
        .eq('id', groupId)
        .eq('user_id', _userId);
  }
}
