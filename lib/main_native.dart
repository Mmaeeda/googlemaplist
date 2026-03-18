import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'infrastructure/database/app_database.dart';
import 'presentation/providers/core_providers.dart';
import 'app.dart';

/// Native: initialize SQLite database and create the app widget.
Future<Widget> createApp() async {
  final db = AppDatabase();
  await db.database; // ensure DB created + seed
  return ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: const MapsSavedApp(),
  );
}
