import 'package:sqflite/sqflite.dart';

import '../../domain/models/classification_rule.dart';
import '../../domain/repositories/classification_rule_repository.dart';
import 'app_database.dart';

class SqliteClassificationRuleRepository
    implements ClassificationRuleRepository {
  final AppDatabase _appDatabase;

  SqliteClassificationRuleRepository(this._appDatabase);

  Future<Database> get _db => _appDatabase.database;

  @override
  Future<List<ClassificationRule>> listAll() async {
    final db = await _db;
    final results =
        await db.query('classification_rules', orderBy: 'priority ASC');
    return results.map(ClassificationRule.fromMap).toList();
  }

  @override
  Future<List<ClassificationRule>> listEnabled() async {
    final db = await _db;
    final results = await db.query(
      'classification_rules',
      where: 'enabled = 1',
      orderBy: 'priority ASC',
    );
    return results.map(ClassificationRule.fromMap).toList();
  }

  @override
  Future<void> insert(ClassificationRule rule) async {
    final db = await _db;
    await db.insert('classification_rules', rule.toMap());
  }

  @override
  Future<void> update(ClassificationRule rule) async {
    final db = await _db;
    await db.update(
      'classification_rules',
      rule.toMap(),
      where: 'id = ?',
      whereArgs: [rule.id],
    );
  }

  @override
  Future<void> delete(String ruleId) async {
    final db = await _db;
    await db.delete(
      'classification_rules',
      where: 'id = ?',
      whereArgs: [ruleId],
    );
  }
}
