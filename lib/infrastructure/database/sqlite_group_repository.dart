import 'package:sqflite/sqflite.dart';

import '../../domain/models/app_error.dart';
import '../../domain/models/group.dart';
import '../../domain/repositories/group_repository.dart';
import 'app_database.dart';

class SqliteGroupRepository implements GroupRepository {
  final AppDatabase _appDatabase;

  SqliteGroupRepository(this._appDatabase);

  Future<Database> get _db => _appDatabase.database;

  @override
  Future<List<Group>> listAll() async {
    final db = await _db;
    final results = await db.query('groups', orderBy: 'sort_order ASC');
    return results.map(Group.fromMap).toList();
  }

  @override
  Future<Group?> findById(String id) async {
    final db = await _db;
    final results = await db.query(
      'groups',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return Group.fromMap(results.first);
  }

  @override
  Future<Group?> findByName(String name) async {
    final db = await _db;
    final results = await db.query(
      'groups',
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return Group.fromMap(results.first);
  }

  @override
  Future<void> upsert(Group group) async {
    final db = await _db;
    await db.insert(
      'groups',
      group.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> delete(String groupId) async {
    final db = await _db;
    // Prevent deleting system groups
    final group = await findById(groupId);
    if (group != null && group.systemGroup) {
      throw AppError(
        AppErrorCode.dbWriteFailed,
        'Cannot delete system group: ${group.name}',
      );
    }
    await db.delete('groups', where: 'id = ?', whereArgs: [groupId]);
  }
}
