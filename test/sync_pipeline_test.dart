import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:maps_saved_app/domain/models/classification_rule.dart';
import 'package:maps_saved_app/domain/models/group.dart';
import 'package:maps_saved_app/domain/models/place.dart';
import 'package:maps_saved_app/domain/models/place_group.dart';
import 'package:maps_saved_app/domain/models/sync_job.dart';
import 'package:maps_saved_app/domain/repositories/classification_rule_repository.dart';
import 'package:maps_saved_app/domain/repositories/group_repository.dart';
import 'package:maps_saved_app/domain/repositories/place_group_repository.dart';
import 'package:maps_saved_app/domain/repositories/place_repository.dart';
import 'package:maps_saved_app/domain/repositories/sync_job_repository.dart';
import 'package:maps_saved_app/infrastructure/classification/classification_engine.dart';
import 'package:maps_saved_app/infrastructure/csv/csv_parser.dart';
import 'package:maps_saved_app/infrastructure/csv/place_normalizer.dart';
import 'package:maps_saved_app/infrastructure/logging/sync_logger.dart';
import 'package:maps_saved_app/infrastructure/sync/diff_applier.dart';
import 'package:maps_saved_app/infrastructure/sync/diff_engine.dart';
import 'package:maps_saved_app/infrastructure/sync/source_key_generator.dart';

// ============================================================
// In-memory repository implementations for testing
// ============================================================

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

/// In-memory PlaceRepository.
class InMemoryPlaceRepository implements PlaceRepository {
  final Map<String, Place> _places = {};

  void seed(List<Place> places) {
    for (final place in places) {
      _places[place.id] = place;
    }
  }

  Place? getById(String id) => _places[id];

  @override
  Future<Place?> findById(String id) async => _places[id];

  @override
  Future<Place?> findBySourceKey(String sourceKey) async {
    for (final place in _places.values) {
      if (place.sourceKey == sourceKey) return place;
    }
    return null;
  }

  @override
  Future<void> insert(Place place) async {
    _places[place.id] = place;
  }

  @override
  Future<void> update(Place place) async {
    _places[place.id] = place;
  }

  @override
  Future<void> markMissing(String placeId) async {
    final place = _places[placeId];
    if (place == null) return;
    final newMissCount = place.deletedMissCount + 1;
    _places[placeId] = place.copyWith(
      isDeletedCandidate: true,
      deletedMissCount: newMissCount,
      isHidden: newMissCount >= 2,
    );
  }

  @override
  Future<List<Place>> listMissingCandidates() async {
    return _places.values.where((p) => p.isDeletedCandidate).toList();
  }

  @override
  Future<List<Place>> listAllActive() async {
    return _places.values.where((p) => !p.isHidden).toList();
  }

  @override
  Future<List<Place>> listAll() async {
    return _places.values.toList();
  }
}

/// In-memory GroupRepository.
class InMemoryGroupRepository implements GroupRepository {
  final Map<String, Group> _groups = {};

  void seed(List<Group> groups) {
    for (final group in groups) {
      _groups[group.id] = group;
    }
  }

  @override
  Future<List<Group>> listAll() async => _groups.values.toList();

  @override
  Future<Group?> findById(String id) async => _groups[id];

  @override
  Future<Group?> findByName(String name) async {
    for (final group in _groups.values) {
      if (group.name == name) return group;
    }
    return null;
  }

  @override
  Future<void> upsert(Group group) async {
    _groups[group.id] = group;
  }

  @override
  Future<void> delete(String groupId) async {
    _groups.remove(groupId);
  }
}

/// In-memory PlaceGroupRepository.
class InMemoryPlaceGroupRepository implements PlaceGroupRepository {
  // Map<placeId, List<PlaceGroup>>
  final Map<String, List<PlaceGroup>> _placeGroups = {};

  @override
  Future<void> replaceAutoGroups(
      String placeId, List<PlaceGroup> groups) async {
    // Remove existing auto groups, keep manual ones
    final existing = _placeGroups[placeId] ?? [];
    final manualGroups =
        existing.where((pg) => pg.source == 'manual').toList();
    _placeGroups[placeId] = [
      ...manualGroups,
      ...groups.where((pg) => pg.source != 'manual'),
    ];
  }

  @override
  Future<List<PlaceGroup>> listByPlaceId(String placeId) async {
    return _placeGroups[placeId] ?? [];
  }

  @override
  Future<List<PlaceGroup>> listAll() async {
    return _placeGroups.values.expand((list) => list).toList();
  }

  @override
  Future<void> insertManualGroup(PlaceGroup placeGroup) async {
    _placeGroups
        .putIfAbsent(placeGroup.placeId, () => [])
        .add(placeGroup);
  }

  /// Helper for test assertions: get all place groups across all places.
  List<PlaceGroup> get allPlaceGroups =>
      _placeGroups.values.expand((list) => list).toList();
}

/// In-memory SyncJobRepository.
class InMemorySyncJobRepository implements SyncJobRepository {
  final Map<String, SyncJob> _jobs = {};

  @override
  Future<void> start(SyncJob job) async {
    _jobs[job.id] = job;
  }

  @override
  Future<void> complete(
    String jobId, {
    SyncJobStatus status = SyncJobStatus.success,
    int newCount = 0,
    int updatedCount = 0,
    int unchangedCount = 0,
    int deletedCandidateCount = 0,
    int skippedRowCount = 0,
  }) async {
    final job = _jobs[jobId];
    if (job == null) return;
    _jobs[jobId] = job.copyWith(
      status: status,
      endedAt: DateTime.now(),
      newCount: newCount,
      updatedCount: updatedCount,
      unchangedCount: unchangedCount,
      deletedCandidateCount: deletedCandidateCount,
      skippedRowCount: skippedRowCount,
    );
  }

  @override
  Future<void> fail(String jobId, String errorMessage) async {
    final job = _jobs[jobId];
    if (job == null) return;
    _jobs[jobId] = job.copyWith(
      status: SyncJobStatus.failed,
      endedAt: DateTime.now(),
      errorMessage: errorMessage,
    );
  }

  @override
  Future<SyncJob?> latest() async {
    if (_jobs.isEmpty) return null;
    final sorted = _jobs.values.toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return sorted.first;
  }

  @override
  Future<SyncJob?> findById(String jobId) async => _jobs[jobId];
}

/// In-memory ClassificationRuleRepository.
class InMemoryClassificationRuleRepository
    implements ClassificationRuleRepository {
  final Map<String, ClassificationRule> _rules = {};

  void seed(List<ClassificationRule> rules) {
    for (final rule in rules) {
      _rules[rule.id] = rule;
    }
  }

  @override
  Future<List<ClassificationRule>> listAll() async =>
      _rules.values.toList();

  @override
  Future<List<ClassificationRule>> listEnabled() async =>
      _rules.values.where((r) => r.enabled).toList();

  @override
  Future<void> insert(ClassificationRule rule) async {
    _rules[rule.id] = rule;
  }

  @override
  Future<void> update(ClassificationRule rule) async {
    _rules[rule.id] = rule;
  }

  @override
  Future<void> delete(String ruleId) async {
    _rules.remove(ruleId);
  }
}

// ============================================================
// Tests
// ============================================================

void main() {
  late NoOpSyncLogger logger;
  late InMemoryPlaceRepository placeRepository;
  late InMemoryGroupRepository groupRepository;
  late InMemoryPlaceGroupRepository placeGroupRepository;
  late InMemoryClassificationRuleRepository classificationRuleRepository;
  late CsvParser csvParser;
  late PlaceNormalizer normalizer;
  late SourceKeyGenerator keyGenerator;
  late DiffEngine diffEngine;
  late DiffApplier diffApplier;
  late RuleBasedClassificationEngine classificationEngine;
  late ClassificationOrchestrator classificationOrchestrator;

  /// Test CSV with Japanese content for classification testing.
  /// Uses \r\n line endings as required by the csv package's CsvToListConverter.
  final testCsvContent = [
    'Title,URL,Note,Comments,Collection Name',
    '桜の名所 上野公園,https://maps.google.com/place1,春に訪れたい,満開の時期がおすすめ,お花見スポット',
    '東京スカイツリー展望台,https://maps.google.com/place2,夜景がきれい,,観光地',
    '鎌倉カフェ,https://maps.google.com/place3,抹茶ラテが美味しい,,飲食店リスト',
  ].join('\r\n');

  setUp(() {
    logger = NoOpSyncLogger();
    placeRepository = InMemoryPlaceRepository();
    groupRepository = InMemoryGroupRepository();
    placeGroupRepository = InMemoryPlaceGroupRepository();
    classificationRuleRepository = InMemoryClassificationRuleRepository();
    csvParser = CsvParser(logger);
    normalizer = PlaceNormalizer();
    keyGenerator = SourceKeyGenerator();
    diffEngine = DiffEngine(placeRepository, keyGenerator, logger);
    diffApplier = DiffApplier(placeRepository, keyGenerator, logger);
    classificationEngine =
        RuleBasedClassificationEngine(classificationRuleRepository, logger);
    classificationOrchestrator = ClassificationOrchestrator(
      classificationEngine,
      placeRepository,
      placeGroupRepository,
      groupRepository,
      logger,
    );

    // Seed groups
    groupRepository.seed([
      const Group(
        id: 'group-sakura',
        name: '桜スポット',
        iconName: 'cherry_blossom',
        colorKey: 'pink',
        sortOrder: 1,
      ),
      const Group(
        id: 'group-spring',
        name: '春',
        iconName: 'sun',
        colorKey: 'green',
        sortOrder: 2,
      ),
      const Group(
        id: 'group-nightview',
        name: '夜景スポット',
        iconName: 'night',
        colorKey: 'navy',
        sortOrder: 3,
      ),
      const Group(
        id: 'group-cafe',
        name: 'カフェ',
        iconName: 'coffee',
        colorKey: 'brown',
        sortOrder: 4,
      ),
      const Group(
        id: 'group-sightseeing',
        name: '観光地',
        iconName: 'landmark',
        colorKey: 'blue',
        sortOrder: 5,
      ),
      const Group(
        id: 'group-unclassified',
        name: '未分類',
        iconName: 'question',
        colorKey: 'grey',
        sortOrder: 999,
        systemGroup: true,
      ),
    ]);

    // Seed classification rules
    classificationRuleRepository.seed([
      const ClassificationRule(
        id: 'rule-sakura',
        groupId: 'group-sakura',
        pattern: '桜',
        targetFields: ['title', 'note', 'comments', 'collection_name'],
        priority: 10,
      ),
      const ClassificationRule(
        id: 'rule-spring',
        groupId: 'group-spring',
        pattern: '春|お花見',
        targetFields: ['title', 'note', 'comments', 'collection_name'],
        priority: 20,
      ),
      const ClassificationRule(
        id: 'rule-nightview',
        groupId: 'group-nightview',
        pattern: '夜景',
        targetFields: ['title', 'note', 'comments'],
        priority: 30,
      ),
      const ClassificationRule(
        id: 'rule-cafe',
        groupId: 'group-cafe',
        pattern: 'カフェ|cafe|コーヒー',
        targetFields: ['title', 'note', 'collection_name'],
        priority: 40,
      ),
      const ClassificationRule(
        id: 'rule-sightseeing',
        groupId: 'group-sightseeing',
        pattern: '観光',
        targetFields: ['title', 'collection_name'],
        priority: 50,
      ),
    ]);
  });

  group('Full sync pipeline: CSV -> Parse -> Normalize -> Diff -> Apply -> Classify', () {
    test('parses CSV and inserts all places into empty repository', () async {
      // Step 1: Parse CSV
      final csvBytes = utf8.encode(testCsvContent);
      final parseResult = csvParser.parse(csvBytes, fileName: 'test.csv');

      expect(parseResult.records, hasLength(3));
      expect(parseResult.skippedRowCount, equals(0));

      // Step 2: Normalize
      final normalized =
          parseResult.records.map((r) => normalizer.normalize(r)).toList();

      expect(normalized, hasLength(3));
      expect(normalized[0].sourceTitle, equals('桜の名所 上野公園'));
      expect(normalized[0].mapsUrl, equals('https://maps.google.com/place1'));
      expect(normalized[0].note, equals('春に訪れたい'));
      expect(normalized[0].comments, equals('満開の時期がおすすめ'));
      expect(normalized[0].collectionName, equals('お花見スポット'));

      // Step 3: Compute diff (all new, DB is empty)
      final diff = await diffEngine.compute(normalized);

      expect(diff.newRecords, hasLength(3));
      expect(diff.updatedRecords, isEmpty);
      expect(diff.unchangedRecords, isEmpty);
      expect(diff.missingPlaceIds, isEmpty);

      // Step 4: Apply diff
      final newPlaceIds = await diffApplier.apply(diff);

      expect(newPlaceIds, hasLength(3));

      // Verify places are in the repository
      final allPlaces = await placeRepository.listAll();
      expect(allPlaces, hasLength(3));

      // Verify data integrity
      final sakuraPlace = allPlaces.firstWhere(
        (p) => p.sourceTitle == '桜の名所 上野公園',
      );
      expect(sakuraPlace.mapsUrl, equals('https://maps.google.com/place1'));
      expect(sakuraPlace.note, equals('春に訪れたい'));
      expect(sakuraPlace.comments, equals('満開の時期がおすすめ'));
      expect(sakuraPlace.collectionName, equals('お花見スポット'));
      expect(sakuraPlace.isDeletedCandidate, isFalse);
      expect(sakuraPlace.isHidden, isFalse);
    });

    test('classification assigns correct groups to places', () async {
      // Parse, normalize, diff, apply
      final csvBytes = utf8.encode(testCsvContent);
      final parseResult = csvParser.parse(csvBytes, fileName: 'test.csv');
      final normalized =
          parseResult.records.map((r) => normalizer.normalize(r)).toList();
      final diff = await diffEngine.compute(normalized);
      final newPlaceIds = await diffApplier.apply(diff);

      // Step 5: Classify all new places
      await classificationOrchestrator.rebuildForPlaces(newPlaceIds);

      // Verify classification for "桜の名所 上野公園"
      // Should match: 桜 (in title), 春 (in note: 春に訪れたい), お花見 (in collection_name)
      final allPlaces = await placeRepository.listAll();
      final sakuraPlace = allPlaces.firstWhere(
        (p) => p.sourceTitle == '桜の名所 上野公園',
      );
      final sakuraGroups =
          await placeGroupRepository.listByPlaceId(sakuraPlace.id);

      final sakuraGroupIds =
          sakuraGroups.map((pg) => pg.groupId).toSet();
      expect(sakuraGroupIds, contains('group-sakura'),
          reason: 'Title contains 桜');
      expect(sakuraGroupIds, contains('group-spring'),
          reason: 'Note contains 春 and collection contains お花見');

      // Verify classification for "東京スカイツリー展望台"
      // Should match: 夜景 (in note), 観光 (in collection_name)
      final skytreePlace = allPlaces.firstWhere(
        (p) => p.sourceTitle == '東京スカイツリー展望台',
      );
      final skytreeGroups =
          await placeGroupRepository.listByPlaceId(skytreePlace.id);

      final skytreeGroupIds =
          skytreeGroups.map((pg) => pg.groupId).toSet();
      expect(skytreeGroupIds, contains('group-nightview'),
          reason: 'Note contains 夜景');
      expect(skytreeGroupIds, contains('group-sightseeing'),
          reason: 'Collection name contains 観光');

      // Verify classification for "鎌倉カフェ"
      // Should match: カフェ (in title)
      final cafePlace = allPlaces.firstWhere(
        (p) => p.sourceTitle == '鎌倉カフェ',
      );
      final cafeGroups =
          await placeGroupRepository.listByPlaceId(cafePlace.id);

      final cafeGroupIds = cafeGroups.map((pg) => pg.groupId).toSet();
      expect(cafeGroupIds, contains('group-cafe'),
          reason: 'Title contains カフェ');
    });

    test('classification source and confidence are set correctly', () async {
      final csvBytes = utf8.encode(testCsvContent);
      final parseResult = csvParser.parse(csvBytes, fileName: 'test.csv');
      final normalized =
          parseResult.records.map((r) => normalizer.normalize(r)).toList();
      final diff = await diffEngine.compute(normalized);
      final newPlaceIds = await diffApplier.apply(diff);

      await classificationOrchestrator.rebuildForPlaces(newPlaceIds);

      final allPlaces = await placeRepository.listAll();
      final sakuraPlace = allPlaces.firstWhere(
        (p) => p.sourceTitle == '桜の名所 上野公園',
      );
      final groups =
          await placeGroupRepository.listByPlaceId(sakuraPlace.id);

      for (final pg in groups) {
        expect(pg.source, equals('rule'));
        expect(pg.confidence, equals(1.0));
      }
    });

    test('second sync with same data results in no changes', () async {
      // First sync
      final csvBytes = utf8.encode(testCsvContent);
      final parseResult = csvParser.parse(csvBytes, fileName: 'test.csv');
      final normalized =
          parseResult.records.map((r) => normalizer.normalize(r)).toList();
      var diff = await diffEngine.compute(normalized);
      await diffApplier.apply(diff);

      // Second sync with same data
      final parseResult2 = csvParser.parse(csvBytes, fileName: 'test.csv');
      final normalized2 =
          parseResult2.records.map((r) => normalizer.normalize(r)).toList();
      diff = await diffEngine.compute(normalized2);

      expect(diff.newRecords, isEmpty);
      expect(diff.updatedRecords, isEmpty);
      expect(diff.unchangedRecords, hasLength(3));
      expect(diff.missingPlaceIds, isEmpty);
    });

    test('sync detects updated record when note changes', () async {
      // First sync
      final csvBytes = utf8.encode(testCsvContent);
      final parseResult = csvParser.parse(csvBytes, fileName: 'test.csv');
      final normalized =
          parseResult.records.map((r) => normalizer.normalize(r)).toList();
      var diff = await diffEngine.compute(normalized);
      await diffApplier.apply(diff);

      // Second sync with updated note for first place
      final updatedCsvContent = [
        'Title,URL,Note,Comments,Collection Name',
        '桜の名所 上野公園,https://maps.google.com/place1,秋にも訪れたい,満開の時期がおすすめ,お花見スポット',
        '東京スカイツリー展望台,https://maps.google.com/place2,夜景がきれい,,観光地',
        '鎌倉カフェ,https://maps.google.com/place3,抹茶ラテが美味しい,,飲食店リスト',
      ].join('\r\n');

      final csvBytes2 = utf8.encode(updatedCsvContent);
      final parseResult2 = csvParser.parse(csvBytes2, fileName: 'test.csv');
      final normalized2 =
          parseResult2.records.map((r) => normalizer.normalize(r)).toList();
      diff = await diffEngine.compute(normalized2);

      expect(diff.newRecords, isEmpty);
      expect(diff.updatedRecords, hasLength(1));
      expect(diff.unchangedRecords, hasLength(2));
      expect(diff.missingPlaceIds, isEmpty);

      // The updated record should show "note" as a changed field
      expect(diff.updatedRecords.first.changedFields, contains('note'));

      // Apply the update
      await diffApplier.apply(diff);

      // Verify the note was updated
      final allPlaces = await placeRepository.listAll();
      final updatedPlace = allPlaces.firstWhere(
        (p) => p.sourceTitle == '桜の名所 上野公園',
      );
      expect(updatedPlace.note, equals('秋にも訪れたい'));
    });

    test('sync detects missing place when removed from CSV', () async {
      // First sync: all 3 places
      final csvBytes = utf8.encode(testCsvContent);
      final parseResult = csvParser.parse(csvBytes, fileName: 'test.csv');
      final normalized =
          parseResult.records.map((r) => normalizer.normalize(r)).toList();
      var diff = await diffEngine.compute(normalized);
      await diffApplier.apply(diff);

      // Second sync: only 2 places (remove 鎌倉カフェ)
      final reducedCsvContent = [
        'Title,URL,Note,Comments,Collection Name',
        '桜の名所 上野公園,https://maps.google.com/place1,春に訪れたい,満開の時期がおすすめ,お花見スポット',
        '東京スカイツリー展望台,https://maps.google.com/place2,夜景がきれい,,観光地',
      ].join('\r\n');

      final csvBytes2 = utf8.encode(reducedCsvContent);
      final parseResult2 = csvParser.parse(csvBytes2, fileName: 'test.csv');
      final normalized2 =
          parseResult2.records.map((r) => normalizer.normalize(r)).toList();
      diff = await diffEngine.compute(normalized2);

      expect(diff.newRecords, isEmpty);
      expect(diff.updatedRecords, isEmpty);
      expect(diff.unchangedRecords, hasLength(2));
      expect(diff.missingPlaceIds, hasLength(1));

      // Apply the diff
      await diffApplier.apply(diff);

      // The missing place should be marked as deletion candidate
      final allPlaces = await placeRepository.listAll();
      final cafePlace = allPlaces.firstWhere(
        (p) => p.sourceTitle == '鎌倉カフェ',
      );
      expect(cafePlace.isDeletedCandidate, isTrue);
      expect(cafePlace.deletedMissCount, equals(1));
      expect(cafePlace.isHidden, isFalse);
    });

    test('place with no classification rules match gets assigned to 未分類', () async {
      // CSV with a place that matches no rules
      final noMatchCsv = [
        'Title,URL,Note,Comments,Collection Name',
        '普通の場所,https://maps.google.com/place99,特になし,,その他',
      ].join('\r\n');

      final csvBytes = utf8.encode(noMatchCsv);
      final parseResult = csvParser.parse(csvBytes, fileName: 'test.csv');
      final normalized =
          parseResult.records.map((r) => normalizer.normalize(r)).toList();
      final diff = await diffEngine.compute(normalized);
      final newPlaceIds = await diffApplier.apply(diff);

      await classificationOrchestrator.rebuildForPlaces(newPlaceIds);

      final allPlaces = await placeRepository.listAll();
      final place = allPlaces.first;
      final groups =
          await placeGroupRepository.listByPlaceId(place.id);

      expect(groups, hasLength(1));
      expect(groups.first.groupId, equals('group-unclassified'));
    });

    test('new place added in second sync is correctly processed', () async {
      // First sync
      final csvBytes = utf8.encode(testCsvContent);
      final parseResult = csvParser.parse(csvBytes, fileName: 'test.csv');
      final normalized =
          parseResult.records.map((r) => normalizer.normalize(r)).toList();
      var diff = await diffEngine.compute(normalized);
      await diffApplier.apply(diff);

      // Second sync: add a new place
      final extendedCsvContent = [
        'Title,URL,Note,Comments,Collection Name',
        '桜の名所 上野公園,https://maps.google.com/place1,春に訪れたい,満開の時期がおすすめ,お花見スポット',
        '東京スカイツリー展望台,https://maps.google.com/place2,夜景がきれい,,観光地',
        '鎌倉カフェ,https://maps.google.com/place3,抹茶ラテが美味しい,,飲食店リスト',
        '京都嵐山 渡月橋,https://maps.google.com/place4,桜の季節に最高,紅葉もおすすめ,観光地',
      ].join('\r\n');

      final csvBytes2 = utf8.encode(extendedCsvContent);
      final parseResult2 = csvParser.parse(csvBytes2, fileName: 'test.csv');
      final normalized2 =
          parseResult2.records.map((r) => normalizer.normalize(r)).toList();
      diff = await diffEngine.compute(normalized2);

      expect(diff.newRecords, hasLength(1));
      expect(diff.updatedRecords, isEmpty);
      expect(diff.unchangedRecords, hasLength(3));
      expect(diff.missingPlaceIds, isEmpty);

      expect(diff.newRecords.first.sourceTitle, equals('京都嵐山 渡月橋'));

      // Apply and classify
      final newPlaceIds = await diffApplier.apply(diff);
      await classificationOrchestrator.rebuildForPlaces(newPlaceIds);

      // Verify classification for the new place
      // "京都嵐山 渡月橋" with note "桜の季節に最高" and collection "観光地"
      // Should match: 桜 (in note), 観光 (in collection)
      final allPlaces = await placeRepository.listAll();
      expect(allPlaces, hasLength(4));

      final newPlace = allPlaces.firstWhere(
        (p) => p.sourceTitle == '京都嵐山 渡月橋',
      );
      final groups =
          await placeGroupRepository.listByPlaceId(newPlace.id);

      final groupIds = groups.map((pg) => pg.groupId).toSet();
      expect(groupIds, contains('group-sakura'),
          reason: 'Note contains 桜');
      expect(groupIds, contains('group-sightseeing'),
          reason: 'Collection name contains 観光');
    });

    test('CSV with BOM is parsed correctly', () async {
      // UTF-8 BOM + CSV content (using \r\n)
      final bomBytes = [0xEF, 0xBB, 0xBF, ...utf8.encode(testCsvContent)];
      final parseResult = csvParser.parse(bomBytes, fileName: 'bom.csv');

      expect(parseResult.records, hasLength(3));
      // First record should still parse correctly
      final normalized = normalizer.normalize(parseResult.records.first);
      expect(normalized.sourceTitle, equals('桜の名所 上野公園'));
    });

    test('empty rows in CSV are skipped', () async {
      final csvWithEmptyRows = [
        'Title,URL,Note,Comments,Collection Name',
        '桜の名所 上野公園,https://maps.google.com/place1,春に訪れたい,満開の時期がおすすめ,お花見スポット',
        '',
        '東京スカイツリー展望台,https://maps.google.com/place2,夜景がきれい,,観光地',
        '',
      ].join('\r\n');

      final csvBytes = utf8.encode(csvWithEmptyRows);
      final parseResult = csvParser.parse(csvBytes, fileName: 'test.csv');

      expect(parseResult.records, hasLength(2));
      expect(parseResult.skippedRowCount, greaterThanOrEqualTo(1));
    });

    test('full pipeline preserves rawPayloadJson', () async {
      final csvBytes = utf8.encode(testCsvContent);
      final parseResult = csvParser.parse(csvBytes, fileName: 'test.csv');
      final normalized =
          parseResult.records.map((r) => normalizer.normalize(r)).toList();
      final diff = await diffEngine.compute(normalized);
      await diffApplier.apply(diff);

      // Verify rawPayloadJson is preserved
      final allPlaces = await placeRepository.listAll();
      for (final place in allPlaces) {
        expect(place.rawPayloadJson, isNotNull);
        expect(place.rawPayloadJson, isNotEmpty);

        // Verify it can be decoded as JSON
        final decoded = jsonDecode(place.rawPayloadJson!);
        expect(decoded, isA<Map>());
      }
    });

    test('reclassification after update changes groups', () async {
      // First sync
      final csvBytes = utf8.encode(testCsvContent);
      final parseResult = csvParser.parse(csvBytes, fileName: 'test.csv');
      final normalized =
          parseResult.records.map((r) => normalizer.normalize(r)).toList();
      var diff = await diffEngine.compute(normalized);
      var newPlaceIds = await diffApplier.apply(diff);
      await classificationOrchestrator.rebuildForPlaces(newPlaceIds);

      // Verify initial classification for 鎌倉カフェ -> カフェ group
      var allPlaces = await placeRepository.listAll();
      var cafePlace = allPlaces.firstWhere(
        (p) => p.sourceTitle == '鎌倉カフェ',
      );
      var cafeGroups =
          await placeGroupRepository.listByPlaceId(cafePlace.id);
      expect(cafeGroups.map((pg) => pg.groupId), contains('group-cafe'));

      // Second sync: update 鎌倉カフェ to include 夜景 in note
      final updatedCsv = [
        'Title,URL,Note,Comments,Collection Name',
        '桜の名所 上野公園,https://maps.google.com/place1,春に訪れたい,満開の時期がおすすめ,お花見スポット',
        '東京スカイツリー展望台,https://maps.google.com/place2,夜景がきれい,,観光地',
        '鎌倉カフェ,https://maps.google.com/place3,夜景も見えるカフェ,,飲食店リスト',
      ].join('\r\n');

      final csvBytes2 = utf8.encode(updatedCsv);
      final parseResult2 = csvParser.parse(csvBytes2, fileName: 'test.csv');
      final normalized2 =
          parseResult2.records.map((r) => normalizer.normalize(r)).toList();
      diff = await diffEngine.compute(normalized2);

      expect(diff.updatedRecords, hasLength(1));

      newPlaceIds = await diffApplier.apply(diff);
      final placeIdsToClassify = [
        ...newPlaceIds,
        ...diff.updatedPlaceIds,
      ];
      await classificationOrchestrator.rebuildForPlaces(placeIdsToClassify);

      // After reclassification, 鎌倉カフェ should now also be in 夜景スポット
      allPlaces = await placeRepository.listAll();
      cafePlace = allPlaces.firstWhere(
        (p) => p.sourceTitle == '鎌倉カフェ',
      );
      cafeGroups =
          await placeGroupRepository.listByPlaceId(cafePlace.id);
      final cafeGroupIds = cafeGroups.map((pg) => pg.groupId).toSet();

      expect(cafeGroupIds, contains('group-cafe'),
          reason: 'Title still contains カフェ');
      expect(cafeGroupIds, contains('group-nightview'),
          reason: 'Updated note contains 夜景');
    });

    test('manualGroupOverride prevents reclassification', () async {
      // Insert a place with manual override
      final csvBytes = utf8.encode(testCsvContent);
      final parseResult = csvParser.parse(csvBytes, fileName: 'test.csv');
      final normalized =
          parseResult.records.map((r) => normalizer.normalize(r)).toList();
      final diff = await diffEngine.compute(normalized);
      final newPlaceIds = await diffApplier.apply(diff);

      // Set manual override on one place
      final allPlaces = await placeRepository.listAll();
      final cafePlace = allPlaces.firstWhere(
        (p) => p.sourceTitle == '鎌倉カフェ',
      );
      await placeRepository.update(
          cafePlace.copyWith(manualGroupOverride: true));

      // Manually assign to a specific group
      await placeGroupRepository.insertManualGroup(PlaceGroup(
        placeId: cafePlace.id,
        groupId: 'group-spring',
        source: 'manual',
        confidence: 1.0,
        createdAt: DateTime.now(),
      ));

      // Run classification on all new places
      await classificationOrchestrator.rebuildForPlaces(newPlaceIds);

      // The manually overridden place should still have only the manual group
      final cafeGroups =
          await placeGroupRepository.listByPlaceId(cafePlace.id);

      // Should have the manual group but no auto groups
      expect(cafeGroups.any((pg) => pg.source == 'manual'), isTrue);
      // Auto groups should not be added since manualGroupOverride is true
      expect(
        cafeGroups.where((pg) => pg.source == 'rule').length,
        equals(0),
        reason: 'No rule-based groups should be added when manualGroupOverride is true',
      );
    });
  });
}
