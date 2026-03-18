import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/app_error.dart';
import '../../domain/models/place.dart';
import '../../domain/models/group.dart';
import '../../domain/models/classification_rule.dart';
import '../../domain/models/place_group.dart';
import '../../domain/models/sync_job.dart';

/// Helpers to convert between Supabase (PostgreSQL) and domain model types.
/// PostgreSQL uses native booleans and timestamptz; SQLite uses int 0/1 and TEXT.

class SupabaseHelpers {
  SupabaseHelpers._();

  /// Get the current user ID, throwing AppError if not authenticated.
  static String requireUserId() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      throw const AppError(
        AppErrorCode.authRequired,
        'User is not authenticated. Please sign in first.',
      );
    }
    return user.id;
  }

  // ── Place ──

  static Map<String, dynamic> placeToRow(Place place, String userId) {
    return {
      'id': place.id,
      'user_id': userId,
      'source_key': place.sourceKey,
      'source_title': place.sourceTitle,
      'maps_url': place.mapsUrl,
      'note': place.note,
      'comments': place.comments,
      'collection_name': place.collectionName,
      'collection_description': place.collectionDescription,
      'raw_payload_json': place.rawPayloadJson,
      'created_at': place.createdAt.toUtc().toIso8601String(),
      'updated_at': place.updatedAt.toUtc().toIso8601String(),
      'last_seen_at': place.lastSeenAt.toUtc().toIso8601String(),
      'is_hidden': place.isHidden,
      'is_deleted_candidate': place.isDeletedCandidate,
      'deleted_miss_count': place.deletedMissCount,
      'manual_group_override': place.manualGroupOverride,
    };
  }

  static Place placeFromRow(Map<String, dynamic> row) {
    return Place(
      id: row['id'] as String,
      sourceKey: row['source_key'] as String,
      sourceTitle: row['source_title'] as String?,
      mapsUrl: row['maps_url'] as String?,
      note: row['note'] as String?,
      comments: row['comments'] as String?,
      collectionName: row['collection_name'] as String?,
      collectionDescription: row['collection_description'] as String?,
      rawPayloadJson: row['raw_payload_json'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      lastSeenAt: DateTime.parse(row['last_seen_at'] as String),
      isHidden: row['is_hidden'] as bool? ?? false,
      isDeletedCandidate: row['is_deleted_candidate'] as bool? ?? false,
      deletedMissCount: row['deleted_miss_count'] as int? ?? 0,
      manualGroupOverride: row['manual_group_override'] as bool? ?? false,
    );
  }

  // ── Group ──

  static Map<String, dynamic> groupToRow(Group group, String userId) {
    return {
      'id': group.id,
      'user_id': userId,
      'name': group.name,
      'icon_name': group.iconName,
      'color_key': group.colorKey,
      'sort_order': group.sortOrder,
      'system_group': group.systemGroup,
    };
  }

  static Group groupFromRow(Map<String, dynamic> row) {
    return Group(
      id: row['id'] as String,
      name: row['name'] as String,
      iconName: row['icon_name'] as String,
      colorKey: row['color_key'] as String,
      sortOrder: row['sort_order'] as int,
      systemGroup: row['system_group'] as bool? ?? false,
    );
  }

  // ── ClassificationRule ──

  static Map<String, dynamic> ruleToRow(
      ClassificationRule rule, String userId) {
    return {
      'id': rule.id,
      'user_id': userId,
      'group_id': rule.groupId,
      'pattern': rule.pattern,
      'target_fields': rule.targetFields.join(','),
      'is_regex': rule.isRegex,
      'priority': rule.priority,
      'enabled': rule.enabled,
    };
  }

  static ClassificationRule ruleFromRow(Map<String, dynamic> row) {
    return ClassificationRule(
      id: row['id'] as String,
      groupId: row['group_id'] as String,
      pattern: row['pattern'] as String,
      targetFields: (row['target_fields'] as String).split(','),
      isRegex: row['is_regex'] as bool? ?? false,
      priority: row['priority'] as int,
      enabled: row['enabled'] as bool? ?? true,
    );
  }

  // ── PlaceGroup ──

  static Map<String, dynamic> placeGroupToRow(
      PlaceGroup pg, String userId) {
    return {
      'user_id': userId,
      'place_id': pg.placeId,
      'group_id': pg.groupId,
      'source': pg.source,
      'confidence': pg.confidence,
      'created_at': pg.createdAt.toUtc().toIso8601String(),
    };
  }

  static PlaceGroup placeGroupFromRow(Map<String, dynamic> row) {
    return PlaceGroup(
      placeId: row['place_id'] as String,
      groupId: row['group_id'] as String,
      source: row['source'] as String,
      confidence: (row['confidence'] as num).toDouble(),
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  // ── SyncJob ──

  static Map<String, dynamic> syncJobToRow(SyncJob job, String userId) {
    return {
      'id': job.id,
      'user_id': userId,
      'archive_identifier': job.archiveIdentifier,
      'archive_name': job.archiveName,
      'started_at': job.startedAt.toUtc().toIso8601String(),
      'ended_at': job.endedAt?.toUtc().toIso8601String(),
      'status': job.status.value,
      'new_count': job.newCount,
      'updated_count': job.updatedCount,
      'unchanged_count': job.unchangedCount,
      'deleted_candidate_count': job.deletedCandidateCount,
      'skipped_row_count': job.skippedRowCount,
      'error_message': job.errorMessage,
    };
  }

  static SyncJob syncJobFromRow(Map<String, dynamic> row) {
    return SyncJob(
      id: row['id'] as String,
      archiveIdentifier: row['archive_identifier'] as String,
      archiveName: row['archive_name'] as String,
      startedAt: DateTime.parse(row['started_at'] as String),
      endedAt: row['ended_at'] != null
          ? DateTime.parse(row['ended_at'] as String)
          : null,
      status: SyncJobStatus.fromString(row['status'] as String),
      newCount: row['new_count'] as int? ?? 0,
      updatedCount: row['updated_count'] as int? ?? 0,
      unchangedCount: row['unchanged_count'] as int? ?? 0,
      deletedCandidateCount: row['deleted_candidate_count'] as int? ?? 0,
      skippedRowCount: row['skipped_row_count'] as int? ?? 0,
      errorMessage: row['error_message'] as String?,
    );
  }
}
