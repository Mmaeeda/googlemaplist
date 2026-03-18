import 'package:sqflite/sqflite.dart';

import '../../domain/models/place_group.dart';
import '../../domain/repositories/place_group_repository.dart';
import 'app_database.dart';

class SqlitePlaceGroupRepository implements PlaceGroupRepository {
  final AppDatabase _appDatabase;

  SqlitePlaceGroupRepository(this._appDatabase);

  Future<Database> get _db => _appDatabase.database;

  @override
  Future<void> replaceAutoGroups(
      String placeId, List<PlaceGroup> groups) async {
    final db = await _db;
    await db.transaction((txn) async {
      // Delete existing auto groups (rule, ai) but keep manual
      await txn.delete(
        'place_groups',
        where: 'place_id = ? AND source != ?',
        whereArgs: [placeId, 'manual'],
      );

      // Insert new auto groups
      for (final group in groups) {
        await txn.insert('place_groups', group.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  @override
  Future<List<PlaceGroup>> listByPlaceId(String placeId) async {
    final db = await _db;
    final results = await db.query(
      'place_groups',
      where: 'place_id = ?',
      whereArgs: [placeId],
    );
    return results.map(PlaceGroup.fromMap).toList();
  }

  @override
  Future<void> insertManualGroup(PlaceGroup placeGroup) async {
    final db = await _db;
    await db.insert(
      'place_groups',
      placeGroup.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
