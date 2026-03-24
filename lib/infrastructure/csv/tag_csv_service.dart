import 'package:uuid/uuid.dart';

import '../../domain/models/group.dart';
import '../../domain/models/place.dart';
import '../../domain/models/place_group.dart';
import '../../domain/repositories/group_repository.dart';
import '../../domain/repositories/place_group_repository.dart';
import '../../domain/repositories/place_repository.dart';

class TagCsvImportResult {
  final int totalRows;
  final int updatedCount;
  final int skippedCount;
  final int newGroupsCreated;
  final List<String> errors;

  const TagCsvImportResult({
    required this.totalRows,
    required this.updatedCount,
    required this.skippedCount,
    required this.newGroupsCreated,
    required this.errors,
  });
}

class TagCsvService {
  static const _uuid = Uuid();

  Future<String> exportCsv({
    required PlaceRepository placeRepository,
    required PlaceGroupRepository placeGroupRepository,
    required GroupRepository groupRepository,
  }) async {
    final places = await placeRepository.listAllActive();
    final allPlaceGroups = await placeGroupRepository.listAll();
    final allGroups = await groupRepository.listAll();

    final groupMap = {for (final g in allGroups) g.id: g};

    // Build place_id -> list of group names
    final placeGroupNames = <String, List<String>>{};
    for (final pg in allPlaceGroups) {
      final group = groupMap[pg.groupId];
      if (group != null) {
        placeGroupNames.putIfAbsent(pg.placeId, () => []).add(group.name);
      }
    }

    final buffer = StringBuffer();
    buffer.writeln('place_id,place_title,group_names');

    // Sort places by title for readability
    final sorted = List<Place>.from(places)
      ..sort((a, b) => (a.sourceTitle ?? '').compareTo(b.sourceTitle ?? ''));

    for (final place in sorted) {
      final id = _escapeCsvField(place.id);
      final title = _escapeCsvField(place.sourceTitle ?? '');
      final groups = placeGroupNames[place.id] ?? [];
      final groupNames = _escapeCsvField(groups.join('|'));
      buffer.writeln('$id,$title,$groupNames');
    }

    return buffer.toString();
  }

  Future<TagCsvImportResult> importCsv({
    required String csvContent,
    required PlaceRepository placeRepository,
    required PlaceGroupRepository placeGroupRepository,
    required GroupRepository groupRepository,
  }) async {
    final lines = _parseLines(csvContent);
    if (lines.isEmpty) {
      return const TagCsvImportResult(
        totalRows: 0,
        updatedCount: 0,
        skippedCount: 0,
        newGroupsCreated: 0,
        errors: ['CSVが空です'],
      );
    }

    // Validate header
    final header = _parseCsvLine(lines.first);
    if (header.length < 3 ||
        header[0].trim().toLowerCase() != 'place_id' ||
        header[2].trim().toLowerCase() != 'group_names') {
      return const TagCsvImportResult(
        totalRows: 0,
        updatedCount: 0,
        skippedCount: 0,
        newGroupsCreated: 0,
        errors: ['ヘッダーが不正です。place_id,place_title,group_names が必要です'],
      );
    }

    final dataLines = lines.skip(1).toList();
    final allGroups = await groupRepository.listAll();
    final groupByName = {for (final g in allGroups) g.name: g};

    int updatedCount = 0;
    int skippedCount = 0;
    int newGroupsCreated = 0;
    final errors = <String>[];

    for (int i = 0; i < dataLines.length; i++) {
      final line = dataLines[i];
      if (line.trim().isEmpty) continue;

      final fields = _parseCsvLine(line);
      if (fields.length < 3) {
        errors.add('行${i + 2}: フィールド数が不足 (${fields.length}/3)');
        skippedCount++;
        continue;
      }

      final placeId = fields[0].trim();
      final groupNamesRaw = fields[2].trim();

      // Verify place exists
      final place = await placeRepository.findById(placeId);
      if (place == null) {
        errors.add('行${i + 2}: place_id "$placeId" が見つかりません');
        skippedCount++;
        continue;
      }

      // Parse group names
      final groupNames = groupNamesRaw.isEmpty
          ? <String>[]
          : groupNamesRaw.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

      // Resolve groups (create if necessary)
      final groupIds = <String>[];
      for (final name in groupNames) {
        var group = groupByName[name];
        if (group == null) {
          // Auto-create group
          group = Group(
            id: _uuid.v4(),
            name: name,
            iconName: 'label',
            colorKey: 'blue',
            sortOrder: 100,
          );
          await groupRepository.upsert(group);
          groupByName[name] = group;
          newGroupsCreated++;
        }
        groupIds.add(group.id);
      }

      // Replace all groups for this place
      final now = DateTime.now();
      final placeGroups = groupIds
          .map((gid) => PlaceGroup(
                placeId: placeId,
                groupId: gid,
                source: 'manual',
                createdAt: now,
              ))
          .toList();

      await placeGroupRepository.replaceAllGroups(placeId, placeGroups);
      await placeRepository.setManualGroupOverride(placeId, true);
      updatedCount++;
    }

    return TagCsvImportResult(
      totalRows: dataLines.length,
      updatedCount: updatedCount,
      skippedCount: skippedCount,
      newGroupsCreated: newGroupsCreated,
      errors: errors,
    );
  }

  /// Split content into lines, normalizing line endings.
  List<String> _parseLines(String content) {
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    // Remove trailing empty line
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    return lines;
  }

  /// Parse a single CSV line respecting quoted fields.
  List<String> _parseCsvLine(String line) {
    final fields = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      if (inQuotes) {
        if (char == '"') {
          // Check for escaped quote
          if (i + 1 < line.length && line[i + 1] == '"') {
            buffer.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          buffer.write(char);
        }
      } else {
        if (char == '"') {
          inQuotes = true;
        } else if (char == ',') {
          fields.add(buffer.toString());
          buffer.clear();
        } else {
          buffer.write(char);
        }
      }
    }
    fields.add(buffer.toString());
    return fields;
  }

  /// Escape a field for CSV output.
  String _escapeCsvField(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
