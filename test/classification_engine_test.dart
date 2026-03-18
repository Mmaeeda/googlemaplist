import 'package:flutter_test/flutter_test.dart';

import 'package:maps_saved_app/domain/models/classification_rule.dart';
import 'package:maps_saved_app/domain/models/place.dart';
import 'package:maps_saved_app/domain/repositories/classification_rule_repository.dart';
import 'package:maps_saved_app/infrastructure/classification/classification_engine.dart';
import 'package:maps_saved_app/infrastructure/logging/sync_logger.dart';

/// In-memory implementation of ClassificationRuleRepository for testing.
class InMemoryClassificationRuleRepository
    implements ClassificationRuleRepository {
  final List<ClassificationRule> _rules = [];

  void seed(List<ClassificationRule> rules) {
    _rules
      ..clear()
      ..addAll(rules);
  }

  @override
  Future<List<ClassificationRule>> listAll() async {
    return List.unmodifiable(_rules);
  }

  @override
  Future<List<ClassificationRule>> listEnabled() async {
    return _rules.where((r) => r.enabled).toList();
  }

  @override
  Future<void> insert(ClassificationRule rule) async {
    _rules.add(rule);
  }

  @override
  Future<void> update(ClassificationRule rule) async {
    final index = _rules.indexWhere((r) => r.id == rule.id);
    if (index >= 0) {
      _rules[index] = rule;
    }
  }

  @override
  Future<void> delete(String ruleId) async {
    _rules.removeWhere((r) => r.id == ruleId);
  }
}

/// No-op SyncLogger for testing.
class NoOpSyncLogger extends SyncLogger {
  NoOpSyncLogger() : super(minLevel: LogLevel.error);

  @override
  void debug(String event, [Map<String, dynamic>? data]) {}

  @override
  void info(String event, [Map<String, dynamic>? data]) {}

  @override
  void warn(String event, [Map<String, dynamic>? data]) {}

  @override
  void error(String event, [Map<String, dynamic>? data]) {}
}

/// Helper to create a Place for testing.
Place createTestPlace({
  String id = 'test-place-1',
  String? sourceTitle,
  String? mapsUrl,
  String? note,
  String? comments,
  String? collectionName,
}) {
  final now = DateTime.now();
  return Place(
    id: id,
    sourceKey: 'test-key-$id',
    sourceTitle: sourceTitle,
    mapsUrl: mapsUrl,
    note: note,
    comments: comments,
    collectionName: collectionName,
    createdAt: now,
    updatedAt: now,
    lastSeenAt: now,
  );
}

void main() {
  late InMemoryClassificationRuleRepository ruleRepository;
  late RuleBasedClassificationEngine engine;
  late NoOpSyncLogger logger;

  setUp(() {
    ruleRepository = InMemoryClassificationRuleRepository();
    logger = NoOpSyncLogger();
    engine = RuleBasedClassificationEngine(ruleRepository, logger);
  });

  group('RuleBasedClassificationEngine', () {
    group('matches single rule by pipe-separated pattern', () {
      test('matches first alternative in pipe-separated pattern', () async {
        ruleRepository.seed([
          ClassificationRule(
            id: 'rule-1',
            groupId: 'group-cafe',
            pattern: 'cafe|coffee|espresso',
            targetFields: ['title'],
          ),
        ]);

        final place = createTestPlace(sourceTitle: 'Best cafe in town');
        final hits = await engine.classify(place);

        expect(hits, hasLength(1));
        expect(hits.first.groupId, equals('group-cafe'));
        expect(hits.first.source, equals('rule'));
        expect(hits.first.confidence, equals(1.0));
      });

      test('matches second alternative in pipe-separated pattern', () async {
        ruleRepository.seed([
          ClassificationRule(
            id: 'rule-1',
            groupId: 'group-cafe',
            pattern: 'cafe|coffee|espresso',
            targetFields: ['title'],
          ),
        ]);

        final place = createTestPlace(sourceTitle: 'Great coffee shop');
        final hits = await engine.classify(place);

        expect(hits, hasLength(1));
        expect(hits.first.groupId, equals('group-cafe'));
      });

      test('does not match when no alternative matches', () async {
        ruleRepository.seed([
          ClassificationRule(
            id: 'rule-1',
            groupId: 'group-cafe',
            pattern: 'cafe|coffee|espresso',
            targetFields: ['title'],
          ),
        ]);

        final place = createTestPlace(sourceTitle: 'Restaurant Downtown');
        final hits = await engine.classify(place);

        expect(hits, isEmpty);
      });
    });

    group('multiple rules can match same place', () {
      test('two rules matching different groups both produce hits', () async {
        ruleRepository.seed([
          ClassificationRule(
            id: 'rule-1',
            groupId: 'group-cafe',
            pattern: 'cafe',
            targetFields: ['title'],
          ),
          ClassificationRule(
            id: 'rule-2',
            groupId: 'group-wifi',
            pattern: 'wifi',
            targetFields: ['note'],
          ),
        ]);

        final place = createTestPlace(
          sourceTitle: 'Best cafe',
          note: 'Has free wifi',
        );
        final hits = await engine.classify(place);

        expect(hits, hasLength(2));
        final groupIds = hits.map((h) => h.groupId).toSet();
        expect(groupIds, contains('group-cafe'));
        expect(groupIds, contains('group-wifi'));
      });

      test('rule checking multiple target fields', () async {
        ruleRepository.seed([
          ClassificationRule(
            id: 'rule-1',
            groupId: 'group-cafe',
            pattern: 'cafe',
            targetFields: ['title', 'note', 'comments'],
          ),
        ]);

        // cafe is in note, not title
        final place = createTestPlace(
          sourceTitle: 'Some place',
          note: 'Nice cafe nearby',
        );
        final hits = await engine.classify(place);

        expect(hits, hasLength(1));
        expect(hits.first.groupId, equals('group-cafe'));
      });
    });

    group('disabled rules are skipped', () {
      test('disabled rule does not produce hits', () async {
        ruleRepository.seed([
          ClassificationRule(
            id: 'rule-1',
            groupId: 'group-cafe',
            pattern: 'cafe',
            targetFields: ['title'],
            enabled: false,
          ),
        ]);

        final place = createTestPlace(sourceTitle: 'Best cafe in town');
        final hits = await engine.classify(place);

        expect(hits, isEmpty);
      });

      test('only enabled rules produce hits', () async {
        ruleRepository.seed([
          ClassificationRule(
            id: 'rule-1',
            groupId: 'group-cafe',
            pattern: 'cafe',
            targetFields: ['title'],
            enabled: false,
          ),
          ClassificationRule(
            id: 'rule-2',
            groupId: 'group-restaurant',
            pattern: 'restaurant',
            targetFields: ['title'],
            enabled: true,
          ),
        ]);

        final place = createTestPlace(
            sourceTitle: 'cafe restaurant combo');
        final hits = await engine.classify(place);

        expect(hits, hasLength(1));
        expect(hits.first.groupId, equals('group-restaurant'));
      });
    });

    group('empty text returns no hits', () {
      test('place with no text fields returns empty hits', () async {
        ruleRepository.seed([
          ClassificationRule(
            id: 'rule-1',
            groupId: 'group-cafe',
            pattern: 'cafe',
            targetFields: ['title'],
          ),
        ]);

        final place = createTestPlace(); // No title, note, etc.
        final hits = await engine.classify(place);

        expect(hits, isEmpty);
      });

      test('place with null target field returns no match', () async {
        ruleRepository.seed([
          ClassificationRule(
            id: 'rule-1',
            groupId: 'group-cafe',
            pattern: 'cafe',
            targetFields: ['note'], // Looking at note only
          ),
        ]);

        final place = createTestPlace(
          sourceTitle: 'Best cafe',
          note: null, // Target field is null
        );
        final hits = await engine.classify(place);

        expect(hits, isEmpty);
      });
    });

    group('deduplicates hits by groupId', () {
      test('two rules with same groupId produce only one hit', () async {
        ruleRepository.seed([
          ClassificationRule(
            id: 'rule-1',
            groupId: 'group-cafe',
            pattern: 'cafe',
            targetFields: ['title'],
            priority: 10,
          ),
          ClassificationRule(
            id: 'rule-2',
            groupId: 'group-cafe', // Same groupId
            pattern: 'coffee',
            targetFields: ['note'],
            priority: 20,
          ),
        ]);

        final place = createTestPlace(
          sourceTitle: 'Best cafe',
          note: 'Great coffee',
        );
        final hits = await engine.classify(place);

        expect(hits, hasLength(1));
        expect(hits.first.groupId, equals('group-cafe'));
      });

      test('first matching rule by priority wins for deduplicated group',
          () async {
        ruleRepository.seed([
          ClassificationRule(
            id: 'rule-high',
            groupId: 'group-cafe',
            pattern: 'coffee',
            targetFields: ['title'],
            priority: 1, // Higher priority (lower number)
          ),
          ClassificationRule(
            id: 'rule-low',
            groupId: 'group-cafe',
            pattern: 'cafe',
            targetFields: ['title'],
            priority: 100,
          ),
        ]);

        final place = createTestPlace(sourceTitle: 'cafe with coffee');
        final hits = await engine.classify(place);

        // Only one hit since they share the same groupId
        expect(hits, hasLength(1));
        expect(hits.first.groupId, equals('group-cafe'));
      });
    });

    group('regex pattern matching when isRegex=true', () {
      test('matches regex pattern', () async {
        ruleRepository.seed([
          ClassificationRule(
            id: 'rule-1',
            groupId: 'group-cafe',
            pattern: r'caf[eé]',
            targetFields: ['title'],
            isRegex: true,
          ),
        ]);

        final place = createTestPlace(sourceTitle: 'Best cafe');
        final hits = await engine.classify(place);

        expect(hits, hasLength(1));
      });

      test('regex is case insensitive', () async {
        ruleRepository.seed([
          ClassificationRule(
            id: 'rule-1',
            groupId: 'group-cafe',
            pattern: r'CAFE',
            targetFields: ['title'],
            isRegex: true,
          ),
        ]);

        final place = createTestPlace(sourceTitle: 'Best cafe');
        final hits = await engine.classify(place);

        expect(hits, hasLength(1));
      });

      test('regex non-match returns empty', () async {
        ruleRepository.seed([
          ClassificationRule(
            id: 'rule-1',
            groupId: 'group-cafe',
            pattern: r'^cafe$', // Exact match only
            targetFields: ['title'],
            isRegex: true,
          ),
        ]);

        final place = createTestPlace(sourceTitle: 'Best cafe in town');
        final hits = await engine.classify(place);

        expect(hits, isEmpty);
      });

      test('invalid regex does not throw, returns no match', () async {
        ruleRepository.seed([
          ClassificationRule(
            id: 'rule-1',
            groupId: 'group-cafe',
            pattern: r'[invalid regex(',
            targetFields: ['title'],
            isRegex: true,
          ),
        ]);

        final place = createTestPlace(sourceTitle: 'cafe');
        final hits = await engine.classify(place);

        // Should not throw, just returns no match
        expect(hits, isEmpty);
      });

      test('complex regex with groups and quantifiers', () async {
        ruleRepository.seed([
          ClassificationRule(
            id: 'rule-1',
            groupId: 'group-restaurant',
            pattern: r'(\brestaurant\b|\bramen\b)\s*\w+',
            targetFields: ['title'],
            isRegex: true,
          ),
        ]);

        final place =
            createTestPlace(sourceTitle: 'Best ramen shop');
        final hits = await engine.classify(place);

        expect(hits, hasLength(1));
      });
    });

    group('priority ordering', () {
      test('rules are processed in priority order (lower number first)',
          () async {
        ruleRepository.seed([
          ClassificationRule(
            id: 'rule-low-priority',
            groupId: 'group-restaurant',
            pattern: 'restaurant',
            targetFields: ['title'],
            priority: 100,
          ),
          ClassificationRule(
            id: 'rule-high-priority',
            groupId: 'group-cafe',
            pattern: 'cafe',
            targetFields: ['title'],
            priority: 1,
          ),
        ]);

        final place = createTestPlace(
            sourceTitle: 'cafe restaurant');
        final hits = await engine.classify(place);

        expect(hits, hasLength(2));
        // The cafe rule (priority 1) should come first
        expect(hits.first.groupId, equals('group-cafe'));
        expect(hits.last.groupId, equals('group-restaurant'));
      });

      test('same priority rules both match', () async {
        ruleRepository.seed([
          ClassificationRule(
            id: 'rule-1',
            groupId: 'group-a',
            pattern: 'pizza',
            targetFields: ['title'],
            priority: 50,
          ),
          ClassificationRule(
            id: 'rule-2',
            groupId: 'group-b',
            pattern: 'pasta',
            targetFields: ['title'],
            priority: 50,
          ),
        ]);

        final place = createTestPlace(
            sourceTitle: 'pizza and pasta');
        final hits = await engine.classify(place);

        expect(hits, hasLength(2));
      });
    });

    group('field targeting', () {
      test('matches in collection_name field', () async {
        ruleRepository.seed([
          ClassificationRule(
            id: 'rule-1',
            groupId: 'group-favorites',
            pattern: 'Favorites',
            targetFields: ['collection_name'],
          ),
        ]);

        final place = createTestPlace(
          sourceTitle: 'Some place',
          collectionName: 'Favorites',
        );
        final hits = await engine.classify(place);

        expect(hits, hasLength(1));
        expect(hits.first.groupId, equals('group-favorites'));
      });

      test('does not match when pattern is in wrong field', () async {
        ruleRepository.seed([
          ClassificationRule(
            id: 'rule-1',
            groupId: 'group-cafe',
            pattern: 'cafe',
            targetFields: ['note'], // Only looking at note
          ),
        ]);

        final place = createTestPlace(
          sourceTitle: 'cafe', // cafe is in title, not note
          note: 'no match here',
        );
        final hits = await engine.classify(place);

        expect(hits, isEmpty);
      });
    });
  });
}
