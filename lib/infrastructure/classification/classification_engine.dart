import 'package:uuid/uuid.dart';

import '../../domain/models/classification_hit.dart';
import '../../domain/models/classification_rule.dart';
import '../../domain/models/group.dart';
import '../../domain/models/place.dart';
import '../../domain/models/place_group.dart';
import '../../domain/repositories/classification_rule_repository.dart';
import '../../domain/repositories/group_repository.dart';
import '../../domain/repositories/place_classifier.dart';
import '../../domain/repositories/place_group_repository.dart';
import '../../domain/repositories/place_repository.dart';
import '../logging/sync_logger.dart';

class RuleBasedClassificationEngine implements PlaceClassifier {
  final ClassificationRuleRepository _ruleRepository;
  final SyncLogger _logger;

  RuleBasedClassificationEngine(this._ruleRepository, this._logger);

  @override
  Future<List<ClassificationHit>> classify(Place place) async {
    final rules = await _ruleRepository.listEnabled();
    final hits = <ClassificationHit>[];

    // Sort by priority (lower number = higher priority)
    final sortedRules = List<ClassificationRule>.from(rules)
      ..sort((a, b) => a.priority.compareTo(b.priority));

    for (final rule in sortedRules) {
      final text = _collectFields(place, rule.targetFields).join('\n');

      if (_matches(rule, text)) {
        final hit = ClassificationHit(
          groupId: rule.groupId,
          source: 'rule',
          confidence: 1.0,
        );

        // Dedupe: only add if groupId not already present
        if (!hits.any((h) => h.groupId == hit.groupId)) {
          hits.add(hit);
        }
      }
    }

    return hits;
  }

  /// Collect text from the specified fields of a place.
  List<String> _collectFields(Place place, List<String> fieldNames) {
    final texts = <String>[];

    for (final field in fieldNames) {
      final value = _getFieldValue(place, field);
      if (value != null && value.isNotEmpty) {
        texts.add(value);
      }
    }

    return texts;
  }

  String? _getFieldValue(Place place, String fieldName) {
    switch (fieldName.toLowerCase()) {
      case 'title':
      case 'sourcetitle':
      case 'source_title':
        return place.sourceTitle;
      case 'note':
        return place.note;
      case 'comments':
      case 'comment':
        return place.comments;
      case 'collectionname':
      case 'collection_name':
        return place.collectionName;
      default:
        return null;
    }
  }

  /// Check if a rule matches the given text.
  bool _matches(ClassificationRule rule, String text) {
    if (text.isEmpty) return false;

    if (rule.isRegex) {
      try {
        final regex = RegExp(rule.pattern, caseSensitive: false);
        return regex.hasMatch(text);
      } catch (e) {
        _logger.warn('Invalid regex pattern', {
          'ruleId': rule.id,
          'pattern': rule.pattern,
          'error': e.toString(),
        });
        return false;
      }
    }

    // For non-regex patterns, treat "|" as OR separator
    final patterns = rule.pattern.split('|');
    for (final pattern in patterns) {
      if (pattern.isEmpty) continue;
      if (text.contains(pattern)) {
        return true;
      }
    }

    return false;
  }
}

/// Orchestrates classification for a set of places.
class ClassificationOrchestrator {
  static const _uuid = Uuid();

  final PlaceClassifier _classifier;
  final PlaceRepository _placeRepository;
  final PlaceGroupRepository _placeGroupRepository;
  final GroupRepository _groupRepository;
  final SyncLogger _logger;

  /// Cache: collectionName → Group (avoids repeated DB lookups)
  final _collectionGroupCache = <String, Group>{};

  ClassificationOrchestrator(
    this._classifier,
    this._placeRepository,
    this._placeGroupRepository,
    this._groupRepository,
    this._logger,
  );

  /// Rebuild classification for specific place IDs.
  Future<void> rebuildForPlaces(List<String> placeIds) async {
    if (placeIds.isEmpty) return;

    _logger.info('classification_started', {'placeCount': placeIds.length});

    final unclassifiedGroup = await _groupRepository.findByName('未分類');

    for (final placeId in placeIds) {
      await _classifyPlace(placeId, unclassifiedGroup?.id);
    }

    _logger.info('classification_completed', {'placeCount': placeIds.length});
  }

  /// Rebuild classification for all active places.
  Future<void> rebuildAll() async {
    _collectionGroupCache.clear();
    final places = await _placeRepository.listAllActive();
    final placeIds = places
        .where((p) => !p.manualGroupOverride)
        .map((p) => p.id)
        .toList();

    await rebuildForPlaces(placeIds);
  }

  Future<void> _classifyPlace(String placeId, String? unclassifiedGroupId) async {
    final place = await _placeRepository.findById(placeId);
    if (place == null) return;

    // Skip places with manual override
    if (place.manualGroupOverride) return;

    try {
      final hits = await _classifier.classify(place);

      final groups = <PlaceGroup>[];
      final now = DateTime.now();

      // Rule-based hits
      for (final hit in hits) {
        groups.add(PlaceGroup(
          placeId: placeId,
          groupId: hit.groupId,
          source: hit.source,
          confidence: hit.confidence,
          createdAt: now,
        ));
      }

      // Collection-name-based auto-grouping:
      // CSV places have collectionName derived from filename (e.g. "お気に入りの場所").
      // Auto-create a group for each unique collectionName and assign the place to it.
      if (place.collectionName != null && place.collectionName!.isNotEmpty) {
        final collectionGroup =
            await _ensureCollectionGroup(place.collectionName!);
        if (!groups.any((g) => g.groupId == collectionGroup.id)) {
          groups.add(PlaceGroup(
            placeId: placeId,
            groupId: collectionGroup.id,
            source: 'collection',
            confidence: 1.0,
            createdAt: now,
          ));
        }
      }

      // If still no groups, assign to "未分類"
      if (groups.isEmpty && unclassifiedGroupId != null) {
        groups.add(PlaceGroup(
          placeId: placeId,
          groupId: unclassifiedGroupId,
          source: 'rule',
          confidence: 1.0,
          createdAt: now,
        ));
      }

      // Replace auto groups (preserves manual groups)
      await _placeGroupRepository.replaceAutoGroups(placeId, groups);
    } catch (e) {
      _logger.error('classification_failed', {
        'placeId': placeId,
        'error': e.toString(),
      });

      // On failure, assign to "未分類" if available
      if (unclassifiedGroupId != null) {
        try {
          await _placeGroupRepository.replaceAutoGroups(placeId, [
            PlaceGroup(
              placeId: placeId,
              groupId: unclassifiedGroupId,
              source: 'rule',
              confidence: 0.0,
              createdAt: DateTime.now(),
            ),
          ]);
        } catch (_) {
          // Best-effort fallback
        }
      }
    }
  }

  /// Find or create a group for the given collection name.
  Future<Group> _ensureCollectionGroup(String collectionName) async {
    if (_collectionGroupCache.containsKey(collectionName)) {
      return _collectionGroupCache[collectionName]!;
    }

    var group = await _groupRepository.findByName(collectionName);
    if (group == null) {
      group = Group(
        id: _uuid.v4(),
        name: collectionName,
        iconName: _iconForCollection(collectionName),
        colorKey: _colorForCollection(collectionName),
        sortOrder: 50,
      );
      await _groupRepository.upsert(group);
      _logger.info('auto_created_collection_group', {
        'groupName': collectionName,
        'groupId': group.id,
      });
    }

    _collectionGroupCache[collectionName] = group;
    return group;
  }

  /// Choose an icon based on common collection name patterns.
  static String _iconForCollection(String name) {
    if (name.contains('お気に入り') || name.contains('favorite')) {
      return 'favorite';
    }
    if (name.contains('行ってみたい') ||
        name.contains('行きたい') ||
        name.contains('want')) {
      return 'explore';
    }
    if (name.contains('スター') || name.contains('star')) return 'star';
    if (name.contains('旗') || name.contains('flag')) return 'flag';
    if (name.contains('飲食') ||
        name.contains('カフェ') ||
        name.contains('パン') ||
        name.contains('restaurant')) {
      return 'restaurant';
    }
    return 'folder';
  }

  /// Choose a color based on common collection name patterns.
  static String _colorForCollection(String name) {
    if (name.contains('お気に入り') || name.contains('favorite')) return 'red';
    if (name.contains('行ってみたい') ||
        name.contains('行きたい') ||
        name.contains('want')) {
      return 'blue';
    }
    if (name.contains('スター') || name.contains('star')) return 'amber';
    if (name.contains('旗') || name.contains('flag')) return 'green';
    if (name.contains('飲食') ||
        name.contains('カフェ') ||
        name.contains('パン') ||
        name.contains('restaurant')) {
      return 'orange';
    }
    return 'teal';
  }
}
