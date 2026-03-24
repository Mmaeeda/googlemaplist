import 'package:flutter_test/flutter_test.dart';

import 'package:maps_saved_app/domain/models/group.dart';
import 'package:maps_saved_app/domain/models/place.dart';
import 'package:maps_saved_app/domain/models/place_group.dart';
import 'package:maps_saved_app/domain/repositories/group_repository.dart';
import 'package:maps_saved_app/domain/repositories/place_group_repository.dart';
import 'package:maps_saved_app/domain/repositories/place_repository.dart';
import 'package:maps_saved_app/infrastructure/csv/tag_csv_service.dart';

// --- Mock Repositories ---

class MockPlaceRepository implements PlaceRepository {
  final List<Place> _places;
  final Map<String, bool> _manualOverrides = {};

  MockPlaceRepository(this._places);

  @override
  Future<List<Place>> listAllActive() async =>
      _places.where((p) => !p.isHidden && !p.isDeletedCandidate).toList();

  @override
  Future<List<Place>> listAll() async => _places;

  @override
  Future<Place?> findById(String id) async =>
      _places.where((p) => p.id == id).firstOrNull;

  @override
  Future<Place?> findBySourceKey(String sourceKey) async =>
      _places.where((p) => p.sourceKey == sourceKey).firstOrNull;

  @override
  Future<void> setManualGroupOverride(String placeId, bool value) async {
    _manualOverrides[placeId] = value;
  }

  bool getManualOverride(String placeId) =>
      _manualOverrides[placeId] ?? false;

  @override
  Future<void> insert(Place place) async => _places.add(place);

  @override
  Future<void> update(Place place) async {
    _places.removeWhere((p) => p.id == place.id);
    _places.add(place);
  }

  @override
  Future<void> updateTitle(String placeId, String? newTitle) async {}

  @override
  Future<void> markMissing(String placeId) async {}

  @override
  Future<List<Place>> listMissingCandidates() async => [];
}

class MockGroupRepository implements GroupRepository {
  final List<Group> _groups;

  MockGroupRepository(this._groups);

  @override
  Future<List<Group>> listAll() async => List.from(_groups);

  @override
  Future<Group?> findById(String id) async =>
      _groups.where((g) => g.id == id).firstOrNull;

  @override
  Future<Group?> findByName(String name) async =>
      _groups.where((g) => g.name == name).firstOrNull;

  @override
  Future<void> upsert(Group group) async {
    _groups.removeWhere((g) => g.id == group.id);
    _groups.add(group);
  }

  @override
  Future<void> delete(String groupId) async {
    _groups.removeWhere((g) => g.id == groupId);
  }
}

class MockPlaceGroupRepository implements PlaceGroupRepository {
  final List<PlaceGroup> _placeGroups;

  MockPlaceGroupRepository(this._placeGroups);

  @override
  Future<List<PlaceGroup>> listAll() async => List.from(_placeGroups);

  @override
  Future<List<PlaceGroup>> listByPlaceId(String placeId) async =>
      _placeGroups.where((pg) => pg.placeId == placeId).toList();

  @override
  Future<void> replaceAllGroups(
      String placeId, List<PlaceGroup> groups) async {
    _placeGroups.removeWhere((pg) => pg.placeId == placeId);
    _placeGroups.addAll(groups);
  }

  @override
  Future<void> replaceAutoGroups(
      String placeId, List<PlaceGroup> groups) async {
    _placeGroups.removeWhere(
        (pg) => pg.placeId == placeId && pg.source != 'manual');
    _placeGroups.addAll(groups);
  }

  @override
  Future<void> insertManualGroup(PlaceGroup placeGroup) async {
    _placeGroups.add(placeGroup);
  }
}

// --- Test Helpers ---

Place _makePlace(String id, String title) => Place(
      id: id,
      sourceKey: 'key_$id',
      sourceTitle: title,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
      lastSeenAt: DateTime(2024, 1, 1),
    );

Group _makeGroup(String id, String name) => Group(
      id: id,
      name: name,
      iconName: 'label',
      colorKey: 'blue',
      sortOrder: 100,
    );

// --- Tests ---

void main() {
  late TagCsvService service;

  setUp(() {
    service = TagCsvService();
  });

  group('TagCsvService.exportCsv', () {
    test('exports header and place rows', () async {
      final places = [
        _makePlace('p1', '東京タワー'),
        _makePlace('p2', 'スターバックス 渋谷'),
      ];
      final groups = [
        _makeGroup('g1', '観光'),
        _makeGroup('g2', 'カフェ'),
      ];
      final placeGroups = [
        PlaceGroup(
            placeId: 'p1',
            groupId: 'g1',
            source: 'manual',
            createdAt: DateTime(2024)),
      ];

      final csv = await service.exportCsv(
        placeRepository: MockPlaceRepository(places),
        placeGroupRepository: MockPlaceGroupRepository(placeGroups),
        groupRepository: MockGroupRepository(groups),
      );

      final lines = csv.trim().split('\n');
      expect(lines[0], 'place_id,place_title,group_names');
      // Sorted by title: スターバックス comes before 東京タワー
      expect(lines.length, 3);

      // Find 東京タワー row
      final tokyoLine = lines.firstWhere((l) => l.contains('p1'));
      expect(tokyoLine, 'p1,東京タワー,観光');

      // Find スターバックス row (no groups)
      final sbLine = lines.firstWhere((l) => l.contains('p2'));
      expect(sbLine, 'p2,スターバックス 渋谷,');
    });

    test('exports multiple groups with pipe separator', () async {
      final places = [_makePlace('p1', 'テスト')];
      final groups = [
        _makeGroup('g1', '観光'),
        _makeGroup('g2', 'ランドマーク'),
      ];
      final placeGroups = [
        PlaceGroup(
            placeId: 'p1',
            groupId: 'g1',
            source: 'manual',
            createdAt: DateTime(2024)),
        PlaceGroup(
            placeId: 'p1',
            groupId: 'g2',
            source: 'rule',
            createdAt: DateTime(2024)),
      ];

      final csv = await service.exportCsv(
        placeRepository: MockPlaceRepository(places),
        placeGroupRepository: MockPlaceGroupRepository(placeGroups),
        groupRepository: MockGroupRepository(groups),
      );

      final lines = csv.trim().split('\n');
      expect(lines[1], 'p1,テスト,観光|ランドマーク');
    });

    test('exports empty CSV when no places exist', () async {
      final csv = await service.exportCsv(
        placeRepository: MockPlaceRepository([]),
        placeGroupRepository: MockPlaceGroupRepository([]),
        groupRepository: MockGroupRepository([]),
      );

      final lines = csv.trim().split('\n');
      expect(lines.length, 1);
      expect(lines[0], 'place_id,place_title,group_names');
    });

    test('escapes fields containing commas', () async {
      final places = [_makePlace('p1', '東京,タワー')];
      final groups = <Group>[];
      final placeGroups = <PlaceGroup>[];

      final csv = await service.exportCsv(
        placeRepository: MockPlaceRepository(places),
        placeGroupRepository: MockPlaceGroupRepository(placeGroups),
        groupRepository: MockGroupRepository(groups),
      );

      final lines = csv.trim().split('\n');
      expect(lines[1], 'p1,"東京,タワー",');
    });

    test('escapes fields containing double quotes', () async {
      final places = [_makePlace('p1', '東京"タワー"')];

      final csv = await service.exportCsv(
        placeRepository: MockPlaceRepository(places),
        placeGroupRepository: MockPlaceGroupRepository([]),
        groupRepository: MockGroupRepository([]),
      );

      final lines = csv.trim().split('\n');
      expect(lines[1], 'p1,"東京""タワー""",');
    });
  });

  group('TagCsvService.importCsv', () {
    test('imports and updates tag assignments', () async {
      final places = [
        _makePlace('p1', '東京タワー'),
        _makePlace('p2', 'スターバックス'),
      ];
      final groups = [_makeGroup('g1', '観光')];
      final placeGroups = <PlaceGroup>[];

      final placeRepo = MockPlaceRepository(places);
      final pgRepo = MockPlaceGroupRepository(placeGroups);
      final groupRepo = MockGroupRepository(groups);

      final csv = 'place_id,place_title,group_names\n'
          'p1,東京タワー,観光\n'
          'p2,スターバックス,カフェ\n';

      final result = await service.importCsv(
        csvContent: csv,
        placeRepository: placeRepo,
        placeGroupRepository: pgRepo,
        groupRepository: groupRepo,
      );

      expect(result.totalRows, 2);
      expect(result.updatedCount, 2);
      expect(result.skippedCount, 0);
      expect(result.newGroupsCreated, 1); // カフェ is new
      expect(result.errors, isEmpty);

      // Verify place groups
      final p1Groups = await pgRepo.listByPlaceId('p1');
      expect(p1Groups, hasLength(1));
      expect(p1Groups[0].groupId, 'g1');

      final p2Groups = await pgRepo.listByPlaceId('p2');
      expect(p2Groups, hasLength(1));
      // p2 should have the new カフェ group
      final cafeGroup = (await groupRepo.listAll())
          .firstWhere((g) => g.name == 'カフェ');
      expect(p2Groups[0].groupId, cafeGroup.id);

      // Verify manual override set
      expect(placeRepo.getManualOverride('p1'), isTrue);
      expect(placeRepo.getManualOverride('p2'), isTrue);
    });

    test('handles multiple groups per place', () async {
      final places = [_makePlace('p1', '東京タワー')];
      final groups = [
        _makeGroup('g1', '観光'),
        _makeGroup('g2', 'ランドマーク'),
      ];

      final pgRepo = MockPlaceGroupRepository([]);

      final csv = 'place_id,place_title,group_names\n'
          'p1,東京タワー,観光|ランドマーク\n';

      final result = await service.importCsv(
        csvContent: csv,
        placeRepository: MockPlaceRepository(places),
        placeGroupRepository: pgRepo,
        groupRepository: MockGroupRepository(groups),
      );

      expect(result.updatedCount, 1);
      final p1Groups = await pgRepo.listByPlaceId('p1');
      expect(p1Groups, hasLength(2));
    });

    test('clears groups when group_names is empty', () async {
      final places = [_makePlace('p1', '東京タワー')];
      final groups = [_makeGroup('g1', '観光')];
      final placeGroups = [
        PlaceGroup(
            placeId: 'p1',
            groupId: 'g1',
            source: 'manual',
            createdAt: DateTime(2024)),
      ];

      final pgRepo = MockPlaceGroupRepository(placeGroups);

      final csv = 'place_id,place_title,group_names\n'
          'p1,東京タワー,\n';

      final result = await service.importCsv(
        csvContent: csv,
        placeRepository: MockPlaceRepository(places),
        placeGroupRepository: pgRepo,
        groupRepository: MockGroupRepository(groups),
      );

      expect(result.updatedCount, 1);
      final p1Groups = await pgRepo.listByPlaceId('p1');
      expect(p1Groups, isEmpty);
    });

    test('skips rows with unknown place_id', () async {
      final places = [_makePlace('p1', '東京タワー')];

      final csv = 'place_id,place_title,group_names\n'
          'p1,東京タワー,観光\n'
          'unknown_id,不明,カフェ\n';

      final result = await service.importCsv(
        csvContent: csv,
        placeRepository: MockPlaceRepository(places),
        placeGroupRepository: MockPlaceGroupRepository([]),
        groupRepository: MockGroupRepository([_makeGroup('g1', '観光')]),
      );

      expect(result.updatedCount, 1);
      expect(result.skippedCount, 1);
      expect(result.errors, hasLength(1));
      expect(result.errors[0], contains('unknown_id'));
    });

    test('returns error for empty CSV', () async {
      final result = await service.importCsv(
        csvContent: '',
        placeRepository: MockPlaceRepository([]),
        placeGroupRepository: MockPlaceGroupRepository([]),
        groupRepository: MockGroupRepository([]),
      );

      expect(result.totalRows, 0);
      expect(result.errors, isNotEmpty);
    });

    test('returns error for invalid header', () async {
      final csv = 'id,name,tags\np1,test,group\n';

      final result = await service.importCsv(
        csvContent: csv,
        placeRepository: MockPlaceRepository([]),
        placeGroupRepository: MockPlaceGroupRepository([]),
        groupRepository: MockGroupRepository([]),
      );

      expect(result.totalRows, 0);
      expect(result.errors, isNotEmpty);
      expect(result.errors[0], contains('ヘッダー'));
    });

    test('auto-creates new groups', () async {
      final places = [_makePlace('p1', 'テスト')];
      final groupRepo = MockGroupRepository([]);

      final csv = 'place_id,place_title,group_names\n'
          'p1,テスト,新グループA|新グループB\n';

      final result = await service.importCsv(
        csvContent: csv,
        placeRepository: MockPlaceRepository(places),
        placeGroupRepository: MockPlaceGroupRepository([]),
        groupRepository: groupRepo,
      );

      expect(result.newGroupsCreated, 2);
      final allGroups = await groupRepo.listAll();
      expect(allGroups.map((g) => g.name),
          containsAll(['新グループA', '新グループB']));
    });

    test('handles Windows line endings (CRLF)', () async {
      final places = [_makePlace('p1', 'テスト')];
      final groups = [_makeGroup('g1', '観光')];

      final csv = 'place_id,place_title,group_names\r\n'
          'p1,テスト,観光\r\n';

      final result = await service.importCsv(
        csvContent: csv,
        placeRepository: MockPlaceRepository(places),
        placeGroupRepository: MockPlaceGroupRepository([]),
        groupRepository: MockGroupRepository(groups),
      );

      expect(result.updatedCount, 1);
      expect(result.errors, isEmpty);
    });

    test('handles bare CR line endings', () async {
      final places = [_makePlace('p1', 'テスト')];
      final groups = [_makeGroup('g1', '観光')];

      final csv = 'place_id,place_title,group_names\r'
          'p1,テスト,観光\r';

      final result = await service.importCsv(
        csvContent: csv,
        placeRepository: MockPlaceRepository(places),
        placeGroupRepository: MockPlaceGroupRepository([]),
        groupRepository: MockGroupRepository(groups),
      );

      expect(result.updatedCount, 1);
      expect(result.errors, isEmpty);
    });

    test('handles quoted fields in import', () async {
      final places = [_makePlace('p1', '東京,タワー')];
      final groups = [_makeGroup('g1', '観光')];

      final csv = 'place_id,place_title,group_names\n'
          'p1,"東京,タワー",観光\n';

      final result = await service.importCsv(
        csvContent: csv,
        placeRepository: MockPlaceRepository(places),
        placeGroupRepository: MockPlaceGroupRepository([]),
        groupRepository: MockGroupRepository(groups),
      );

      expect(result.updatedCount, 1);
      expect(result.errors, isEmpty);
    });

    test('skips empty lines in CSV', () async {
      final places = [_makePlace('p1', 'テスト')];
      final groups = [_makeGroup('g1', '観光')];

      final csv = 'place_id,place_title,group_names\n'
          'p1,テスト,観光\n'
          '\n'
          '\n';

      final result = await service.importCsv(
        csvContent: csv,
        placeRepository: MockPlaceRepository(places),
        placeGroupRepository: MockPlaceGroupRepository([]),
        groupRepository: MockGroupRepository(groups),
      );

      expect(result.updatedCount, 1);
      expect(result.errors, isEmpty);
    });

    test('round-trip: export then import preserves data', () async {
      final places = [
        _makePlace('p1', '東京タワー'),
        _makePlace('p2', 'スターバックス'),
      ];
      final groups = [
        _makeGroup('g1', '観光'),
        _makeGroup('g2', 'カフェ'),
      ];
      final placeGroups = [
        PlaceGroup(
            placeId: 'p1',
            groupId: 'g1',
            source: 'manual',
            createdAt: DateTime(2024)),
        PlaceGroup(
            placeId: 'p2',
            groupId: 'g2',
            source: 'manual',
            createdAt: DateTime(2024)),
      ];

      // Export
      final csv = await service.exportCsv(
        placeRepository: MockPlaceRepository(places),
        placeGroupRepository: MockPlaceGroupRepository(placeGroups),
        groupRepository: MockGroupRepository(groups),
      );

      // Import into fresh repos
      final newPgRepo = MockPlaceGroupRepository([]);
      final result = await service.importCsv(
        csvContent: csv,
        placeRepository: MockPlaceRepository(places),
        placeGroupRepository: newPgRepo,
        groupRepository: MockGroupRepository(List.from(groups)),
      );

      expect(result.updatedCount, 2);
      expect(result.errors, isEmpty);
      expect(result.newGroupsCreated, 0);

      // Verify data preserved
      final p1Groups = await newPgRepo.listByPlaceId('p1');
      expect(p1Groups, hasLength(1));
      expect(p1Groups[0].groupId, 'g1');

      final p2Groups = await newPgRepo.listByPlaceId('p2');
      expect(p2Groups, hasLength(1));
      expect(p2Groups[0].groupId, 'g2');
    });
  });
}
