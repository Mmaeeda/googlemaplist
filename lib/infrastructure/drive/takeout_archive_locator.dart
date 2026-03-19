import '../../domain/models/archive_descriptor.dart';
import '../logging/sync_logger.dart';
import 'google_drive_service.dart';

/// Discovers and groups Takeout archives on Google Drive.
class TakeoutArchiveLocator {
  final GoogleDriveService _driveService;
  final SyncLogger _logger;

  /// Regex to detect split archive naming: takeout-xxx-001.zip, etc.
  static final _splitPattern = RegExp(
    r'^(.*?)[-_]?(\d{3})\.zip$',
    caseSensitive: false,
  );

  TakeoutArchiveLocator({
    required GoogleDriveService driveService,
    required SyncLogger logger,
  }) : _driveService = driveService,
       _logger = logger;

  /// Find the latest Takeout archive group on Drive.
  /// Returns null if no archives found.
  Future<ArchiveGroup?> findLatestArchiveGroup() async {
    final groups = await findArchiveGroupsSorted();
    if (groups.isEmpty) return null;
    return groups.first;
  }

  /// Find all Takeout archive groups sorted by latest created time, descending.
  Future<List<ArchiveGroup>> findArchiveGroupsSorted() async {
    final files = await _driveService.listTakeoutArchives();

    if (files.isEmpty) {
      _logger.info('archive_locator_no_archives_found');
      return const [];
    }

    // Group split archives together
    final groups = _groupArchiveFiles(files);

    if (groups.isEmpty) return const [];

    // Sort by latest created time, descending
    groups.sort((a, b) => b.latestCreatedTime.compareTo(a.latestCreatedTime));

    _logger.info('archive_locator_candidates_built', {
      'groupCount': groups.length,
      'latestIdentifier': groups.first.identifier,
    });

    return groups;
  }

  /// Group archive files by their base name (handling split archives).
  List<ArchiveGroup> _groupArchiveFiles(List<ArchiveFile> files) {
    final groupMap = <String, List<ArchiveFile>>{};

    for (final file in files) {
      final baseName = _extractBaseName(file.name);
      groupMap.putIfAbsent(baseName, () => []).add(file);
    }

    return groupMap.entries.map((entry) {
      final groupFiles = entry.value..sort((a, b) => a.name.compareTo(b.name));

      return ArchiveGroup(
        identifier: _generateIdentifier(groupFiles),
        files: groupFiles,
        latestCreatedTime: groupFiles
            .map((f) => f.createdTime)
            .reduce((a, b) => a.isAfter(b) ? a : b),
      );
    }).toList();
  }

  /// Extract the base name from a potentially split archive filename.
  /// e.g., "takeout-20240101-001.zip" → "takeout-20240101"
  String _extractBaseName(String fileName) {
    final match = _splitPattern.firstMatch(fileName);
    if (match != null) {
      return match.group(1)!;
    }
    // Remove .zip extension for non-split archives
    if (fileName.toLowerCase().endsWith('.zip')) {
      return fileName.substring(0, fileName.length - 4);
    }
    return fileName;
  }

  /// Generate a stable identifier for an archive group.
  String _generateIdentifier(List<ArchiveFile> files) {
    final fileIds = files.map((f) => f.fileId).toList()..sort();
    return fileIds.join('_');
  }
}
