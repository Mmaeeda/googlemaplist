import '../../domain/models/classification_hit.dart';
import '../../domain/models/classification_rule.dart';
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
  final PlaceClassifier _classifier;
  final PlaceRepository _placeRepository;
  final PlaceGroupRepository _placeGroupRepository;
  final GroupRepository _groupRepository;
  final SyncLogger _logger;

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

      if (hits.isEmpty && unclassifiedGroupId != null) {
        // Assign to "未分類" group
        groups.add(PlaceGroup(
          placeId: placeId,
          groupId: unclassifiedGroupId,
          source: 'rule',
          confidence: 1.0,
          createdAt: now,
        ));
      } else {
        for (final hit in hits) {
          groups.add(PlaceGroup(
            placeId: placeId,
            groupId: hit.groupId,
            source: hit.source,
            confidence: hit.confidence,
            createdAt: now,
          ));
        }
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
        await _placeGroupRepository.replaceAutoGroups(placeId, [
          PlaceGroup(
            placeId: placeId,
            groupId: unclassifiedGroupId,
            source: 'rule',
            confidence: 0.0,
            createdAt: DateTime.now(),
          ),
        ]);
      }
    }
  }
}
