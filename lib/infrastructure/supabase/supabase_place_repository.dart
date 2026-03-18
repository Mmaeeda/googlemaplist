import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/place.dart';
import '../../domain/repositories/place_repository.dart';
import 'supabase_helpers.dart';

class SupabasePlaceRepository implements PlaceRepository {
  static const _table = 'places';
  static const missingThreshold = 2;

  String get _userId => SupabaseHelpers.requireUserId();
  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<Place?> findById(String id) async {
    final userId = _userId;
    final result = await _client
        .from(_table)
        .select()
        .eq('id', id)
        .eq('user_id', userId)
        .maybeSingle();
    if (result == null) return null;
    return SupabaseHelpers.placeFromRow(result);
  }

  @override
  Future<Place?> findBySourceKey(String sourceKey) async {
    final userId = _userId;
    final result = await _client
        .from(_table)
        .select()
        .eq('source_key', sourceKey)
        .eq('user_id', userId)
        .maybeSingle();
    if (result == null) return null;
    return SupabaseHelpers.placeFromRow(result);
  }

  @override
  Future<void> insert(Place place) async {
    await _client
        .from(_table)
        .insert(SupabaseHelpers.placeToRow(place, _userId));
  }

  @override
  Future<void> update(Place place) async {
    final userId = _userId;
    await _client
        .from(_table)
        .update(SupabaseHelpers.placeToRow(place, userId))
        .eq('id', place.id)
        .eq('user_id', userId);
  }

  @override
  Future<void> markMissing(String placeId) async {
    final place = await findById(placeId);
    if (place == null) return;

    final newMissCount = place.deletedMissCount + 1;
    final shouldHide = newMissCount >= missingThreshold;

    await _client
        .from(_table)
        .update({
          'is_deleted_candidate': true,
          'deleted_miss_count': newMissCount,
          'is_hidden': shouldHide,
        })
        .eq('id', placeId)
        .eq('user_id', _userId);
  }

  @override
  Future<List<Place>> listMissingCandidates() async {
    final results = await _client
        .from(_table)
        .select()
        .eq('user_id', _userId)
        .eq('is_deleted_candidate', true);
    return results.map(SupabaseHelpers.placeFromRow).toList();
  }

  @override
  Future<List<Place>> listAllActive() async {
    final results = await _client
        .from(_table)
        .select()
        .eq('user_id', _userId)
        .eq('is_hidden', false)
        .order('updated_at', ascending: false);
    return results.map(SupabaseHelpers.placeFromRow).toList();
  }

  @override
  Future<List<Place>> listAll() async {
    final results = await _client
        .from(_table)
        .select()
        .eq('user_id', _userId)
        .order('updated_at', ascending: false);
    return results.map(SupabaseHelpers.placeFromRow).toList();
  }
}
