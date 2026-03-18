import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import 'seed_data.dart';

class AppDatabase {
  static const _databaseName = 'maps_saved.db';
  static const _databaseVersion = 1;

  Database? _database;

  /// For testing: allow injecting a database instance.
  AppDatabase([Database? database]) : _database = database;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _databaseName);

    return openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE places (
        id TEXT PRIMARY KEY,
        source_key TEXT NOT NULL UNIQUE,
        source_title TEXT,
        maps_url TEXT,
        note TEXT,
        comments TEXT,
        collection_name TEXT,
        collection_description TEXT,
        raw_payload_json TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_seen_at TEXT NOT NULL,
        is_hidden INTEGER NOT NULL DEFAULT 0,
        is_deleted_candidate INTEGER NOT NULL DEFAULT 0,
        deleted_miss_count INTEGER NOT NULL DEFAULT 0,
        manual_group_override INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE groups (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        icon_name TEXT NOT NULL,
        color_key TEXT NOT NULL,
        sort_order INTEGER NOT NULL,
        system_group INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE place_groups (
        place_id TEXT NOT NULL,
        group_id TEXT NOT NULL,
        source TEXT NOT NULL,
        confidence REAL NOT NULL DEFAULT 1.0,
        created_at TEXT NOT NULL,
        PRIMARY KEY (place_id, group_id, source),
        FOREIGN KEY (place_id) REFERENCES places(id) ON DELETE CASCADE,
        FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE sync_jobs (
        id TEXT PRIMARY KEY,
        archive_identifier TEXT NOT NULL,
        archive_name TEXT NOT NULL,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        status TEXT NOT NULL,
        new_count INTEGER NOT NULL DEFAULT 0,
        updated_count INTEGER NOT NULL DEFAULT 0,
        unchanged_count INTEGER NOT NULL DEFAULT 0,
        deleted_candidate_count INTEGER NOT NULL DEFAULT 0,
        skipped_row_count INTEGER NOT NULL DEFAULT 0,
        error_message TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE classification_rules (
        id TEXT PRIMARY KEY,
        group_id TEXT NOT NULL,
        pattern TEXT NOT NULL,
        target_fields TEXT NOT NULL,
        is_regex INTEGER NOT NULL DEFAULT 0,
        priority INTEGER NOT NULL DEFAULT 100,
        enabled INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // Indexes
    await db.execute(
        'CREATE INDEX idx_places_source_key ON places(source_key)');
    await db.execute(
        'CREATE INDEX idx_places_last_seen_at ON places(last_seen_at)');
    await db.execute(
        'CREATE INDEX idx_places_hidden ON places(is_hidden)');
    await db.execute(
        'CREATE INDEX idx_sync_jobs_started_at ON sync_jobs(started_at)');
    await db.execute(
        'CREATE INDEX idx_place_groups_group_id ON place_groups(group_id)');

    // Seed initial groups and rules
    await SeedData.seed(db);
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
