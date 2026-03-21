import 'package:sqflite/sqflite.dart';

import '../../domain/models/place.dart';
import '../../domain/repositories/place_repository.dart';
import 'app_database.dart';

class SqlitePlaceRepository implements PlaceRepository {
  static const missingThreshold = 2;

  final AppDatabase _appDatabase;

  SqlitePlaceRepository(this._appDatabase);

  Future<Database> get _db => _appDatabase.database;

  @override
  Future<Place?> findById(String id) async {
    final db = await _db;
    return _findById(db, id);
  }

  @override
  Future<Place?> findBySourceKey(String sourceKey) async {
    final db = await _db;
    final results = await db.query(
      'places',
      where: 'source_key = ?',
      whereArgs: [sourceKey],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return Place.fromMap(results.first);
  }

  @override
  Future<void> insert(Place place) async {
    final db = await _db;
    await db.insert('places', place.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort);
  }

  @override
  Future<void> update(Place place) async {
    final db = await _db;
    await db.update(
      'places',
      place.toMap(),
      where: 'id = ?',
      whereArgs: [place.id],
    );
  }

  @override
  Future<void> updateTitle(String placeId, String? newTitle) async {
    final db = await _db;
    await db.update(
      'places',
      {
        'source_title': newTitle,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [placeId],
    );
  }

  @override
  Future<void> markMissing(String placeId) async {
    final db = await _db;
    final place = await _findById(db, placeId);
    if (place == null) return;

    final newMissCount = place.deletedMissCount + 1;
    final shouldHide = newMissCount >= missingThreshold;

    await db.update(
      'places',
      {
        'is_deleted_candidate': 1,
        'deleted_miss_count': newMissCount,
        'is_hidden': shouldHide ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [placeId],
    );
  }

  @override
  Future<List<Place>> listMissingCandidates() async {
    final db = await _db;
    final results = await db.query(
      'places',
      where: 'is_deleted_candidate = 1',
    );
    return results.map(Place.fromMap).toList();
  }

  @override
  Future<List<Place>> listAllActive() async {
    final db = await _db;
    final results = await db.query(
      'places',
      where: 'is_hidden = 0',
      orderBy: 'updated_at DESC',
    );
    return results.map(Place.fromMap).toList();
  }

  @override
  Future<List<Place>> listAll() async {
    final db = await _db;
    final results = await db.query('places', orderBy: 'updated_at DESC');
    return results.map(Place.fromMap).toList();
  }

  Future<Place?> _findById(Database db, String id) async {
    final results = await db.query(
      'places',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return Place.fromMap(results.first);
  }
}
