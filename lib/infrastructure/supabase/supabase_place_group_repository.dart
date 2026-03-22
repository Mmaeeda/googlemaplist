import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/place_group.dart';
import '../../domain/repositories/place_group_repository.dart';
import 'supabase_helpers.dart';

class SupabasePlaceGroupRepository implements PlaceGroupRepository {
  static const _table = 'place_groups';

  String get _userId => SupabaseHelpers.requireUserId();
  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<void> replaceAutoGroups(
      String placeId, List<PlaceGroup> groups) async {
    final userId = _userId;

    // Use RPC for atomic replace (delete non-manual + insert new)
    final rows = groups
        .map((g) => SupabaseHelpers.placeGroupToRow(g, userId))
        .toList();

    await _client.rpc('replace_auto_groups', params: {
      'p_user_id': userId,
      'p_place_id': placeId,
      'p_new_groups': rows,
    });
  }

  @override
  Future<void> replaceAllGroups(
      String placeId, List<PlaceGroup> groups) async {
    final userId = _userId;

    // Delete ALL existing groups for this place
    await _client
        .from(_table)
        .delete()
        .eq('place_id', placeId)
        .eq('user_id', userId);

    // Insert new groups
    if (groups.isNotEmpty) {
      final rows = groups
          .map((g) => SupabaseHelpers.placeGroupToRow(g, userId))
          .toList();
      await _client.from(_table).insert(rows);
    }
  }

  @override
  Future<List<PlaceGroup>> listByPlaceId(String placeId) async {
    final results = await _client
        .from(_table)
        .select()
        .eq('place_id', placeId)
        .eq('user_id', _userId);
    return results.map(SupabaseHelpers.placeGroupFromRow).toList();
  }

  @override
  Future<List<PlaceGroup>> listAll() async {
    final results = await _client
        .from(_table)
        .select()
        .eq('user_id', _userId);
    return results.map(SupabaseHelpers.placeGroupFromRow).toList();
  }

  @override
  Future<void> insertManualGroup(PlaceGroup placeGroup) async {
    await _client
        .from(_table)
        .upsert(SupabaseHelpers.placeGroupToRow(placeGroup, _userId));
  }
}
