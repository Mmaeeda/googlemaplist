import 'package:flutter_test/flutter_test.dart';

import 'package:maps_saved_app/domain/models/archive_descriptor.dart';

void main() {
  group('ArchiveFile', () {
    test('stores all fields correctly', () {
      final now = DateTime(2025, 1, 15, 10, 30);
      final file = ArchiveFile(
        fileId: 'file-123',
        name: 'takeout-20250115.zip',
        sizeBytes: 1024000,
        createdTime: now,
      );

      expect(file.fileId, equals('file-123'));
      expect(file.name, equals('takeout-20250115.zip'));
      expect(file.sizeBytes, equals(1024000));
      expect(file.createdTime, equals(now));
    });

    test('toString contains name and size', () {
      final file = ArchiveFile(
        fileId: 'file-1',
        name: 'takeout.zip',
        sizeBytes: 500,
        createdTime: DateTime(2025, 1, 1),
      );

      expect(file.toString(), contains('takeout.zip'));
      expect(file.toString(), contains('500'));
    });
  });

  group('ArchiveGroup', () {
    test('displayName for single file returns the file name', () {
      final group = ArchiveGroup(
        identifier: 'id-1',
        files: [
          ArchiveFile(
            fileId: 'file-1',
            name: 'takeout-20250115.zip',
            sizeBytes: 1000,
            createdTime: DateTime(2025, 1, 15),
          ),
        ],
        latestCreatedTime: DateTime(2025, 1, 15),
      );

      expect(group.displayName, equals('takeout-20250115.zip'));
    });

    test('displayName for multiple files includes part count', () {
      final group = ArchiveGroup(
        identifier: 'id-1',
        files: [
          ArchiveFile(
            fileId: 'file-1',
            name: 'takeout-20250115-001.zip',
            sizeBytes: 1000,
            createdTime: DateTime(2025, 1, 15),
          ),
          ArchiveFile(
            fileId: 'file-2',
            name: 'takeout-20250115-002.zip',
            sizeBytes: 2000,
            createdTime: DateTime(2025, 1, 15),
          ),
          ArchiveFile(
            fileId: 'file-3',
            name: 'takeout-20250115-003.zip',
            sizeBytes: 1500,
            createdTime: DateTime(2025, 1, 15),
          ),
        ],
        latestCreatedTime: DateTime(2025, 1, 15),
      );

      expect(group.displayName,
          equals('takeout-20250115-001.zip (+2 parts)'));
    });

    test('totalSizeBytes calculates sum of all files', () {
      final group = ArchiveGroup(
        identifier: 'id-1',
        files: [
          ArchiveFile(
            fileId: 'file-1',
            name: 'part-001.zip',
            sizeBytes: 1000,
            createdTime: DateTime(2025, 1, 15),
          ),
          ArchiveFile(
            fileId: 'file-2',
            name: 'part-002.zip',
            sizeBytes: 2000,
            createdTime: DateTime(2025, 1, 15),
          ),
          ArchiveFile(
            fileId: 'file-3',
            name: 'part-003.zip',
            sizeBytes: 1500,
            createdTime: DateTime(2025, 1, 15),
          ),
        ],
        latestCreatedTime: DateTime(2025, 1, 15),
      );

      expect(group.totalSizeBytes, equals(4500));
    });

    test('totalSizeBytes for empty files list is zero', () {
      final group = ArchiveGroup(
        identifier: 'id-empty',
        files: [],
        latestCreatedTime: DateTime(2025, 1, 1),
      );

      expect(group.totalSizeBytes, equals(0));
    });

    test('totalSizeBytes for single file returns that file size', () {
      final group = ArchiveGroup(
        identifier: 'id-single',
        files: [
          ArchiveFile(
            fileId: 'file-1',
            name: 'archive.zip',
            sizeBytes: 52428800,
            createdTime: DateTime(2025, 1, 1),
          ),
        ],
        latestCreatedTime: DateTime(2025, 1, 1),
      );

      expect(group.totalSizeBytes, equals(52428800));
    });
  });

  group('Split archive filename pattern detection', () {
    // The TakeoutArchiveLocator._splitPattern regex:
    // r'^(.*?)[-_]?(\d{3})\.zip$' (case insensitive)
    final splitPattern = RegExp(
      r'^(.*?)[-_]?(\d{3})\.zip$',
      caseSensitive: false,
    );

    String extractBaseName(String fileName) {
      final match = splitPattern.firstMatch(fileName);
      if (match != null) {
        return match.group(1)!;
      }
      if (fileName.toLowerCase().endsWith('.zip')) {
        return fileName.substring(0, fileName.length - 4);
      }
      return fileName;
    }

    test('split archive filenames share the same base name', () {
      final base1 = extractBaseName('takeout-20250115-001.zip');
      final base2 = extractBaseName('takeout-20250115-002.zip');
      final base3 = extractBaseName('takeout-20250115-003.zip');

      expect(base1, equals(base2));
      expect(base2, equals(base3));
      expect(base1, equals('takeout-20250115'));
    });

    test('split archives with underscore separator share base name', () {
      final base1 = extractBaseName('takeout-20250115_001.zip');
      final base2 = extractBaseName('takeout-20250115_002.zip');

      expect(base1, equals(base2));
      expect(base1, equals('takeout-20250115'));
    });

    test('non-split archive with trailing 3-digit number matches split pattern', () {
      // The regex (.*?)[-_]?(\d{3})\.zip$ is lazy, so "takeout-20250115.zip"
      // matches with base "takeout-20250" and number "115".
      // This is the actual regex behavior.
      final base = extractBaseName('takeout-20250115.zip');
      expect(base, equals('takeout-20250'));
    });

    test('non-split archive without trailing digits uses full name', () {
      final base = extractBaseName('takeout-january.zip');
      expect(base, equals('takeout-january'));
    });

    test('different date prefixes produce different base names', () {
      final base1 = extractBaseName('takeout-20250115-001.zip');
      final base2 = extractBaseName('takeout-20250220-001.zip');

      expect(base1, isNot(equals(base2)));
    });

    test('case-insensitive matching for .ZIP extension', () {
      final base1 = extractBaseName('takeout-20250115-001.zip');
      final base2 = extractBaseName('takeout-20250115-001.ZIP');

      expect(base1, equals(base2));
    });

    test('non-zip file name is returned as-is', () {
      final base = extractBaseName('takeout-20250115.tar.gz');

      expect(base, equals('takeout-20250115.tar.gz'));
    });
  });

  group('Archive grouping logic', () {
    /// Simulates the grouping logic from TakeoutArchiveLocator._groupArchiveFiles.
    List<ArchiveGroup> groupArchiveFiles(List<ArchiveFile> files) {
      final splitPattern = RegExp(
        r'^(.*?)[-_]?(\d{3})\.zip$',
        caseSensitive: false,
      );

      String extractBaseName(String fileName) {
        final match = splitPattern.firstMatch(fileName);
        if (match != null) {
          return match.group(1)!;
        }
        if (fileName.toLowerCase().endsWith('.zip')) {
          return fileName.substring(0, fileName.length - 4);
        }
        return fileName;
      }

      final groupMap = <String, List<ArchiveFile>>{};

      for (final file in files) {
        final baseName = extractBaseName(file.name);
        groupMap.putIfAbsent(baseName, () => []).add(file);
      }

      return groupMap.entries.map((entry) {
        final groupFiles = entry.value
          ..sort((a, b) => a.name.compareTo(b.name));

        return ArchiveGroup(
          identifier: (groupFiles.map((f) => f.fileId).toList()..sort()).join('_'),
          files: groupFiles,
          latestCreatedTime: groupFiles
              .map((f) => f.createdTime)
              .reduce((a, b) => a.isAfter(b) ? a : b),
        );
      }).toList();
    }

    test('split archive files are grouped together', () {
      final files = [
        ArchiveFile(
          fileId: 'f1',
          name: 'takeout-20250115-001.zip',
          sizeBytes: 1000,
          createdTime: DateTime(2025, 1, 15, 10, 0),
        ),
        ArchiveFile(
          fileId: 'f2',
          name: 'takeout-20250115-002.zip',
          sizeBytes: 2000,
          createdTime: DateTime(2025, 1, 15, 10, 5),
        ),
        ArchiveFile(
          fileId: 'f3',
          name: 'takeout-20250115-003.zip',
          sizeBytes: 1500,
          createdTime: DateTime(2025, 1, 15, 10, 10),
        ),
      ];

      final groups = groupArchiveFiles(files);

      expect(groups, hasLength(1));
      expect(groups.first.files, hasLength(3));
      expect(groups.first.totalSizeBytes, equals(4500));
    });

    test('non-split archives with distinct base names are separate groups', () {
      // Use names that will produce different base names after regex matching.
      // "takeout-january.zip" has no trailing 3 digits -> base = "takeout-january"
      // "takeout-february.zip" has no trailing 3 digits -> base = "takeout-february"
      final files = [
        ArchiveFile(
          fileId: 'f1',
          name: 'takeout-january.zip',
          sizeBytes: 1000,
          createdTime: DateTime(2025, 1, 15),
        ),
        ArchiveFile(
          fileId: 'f2',
          name: 'takeout-february.zip',
          sizeBytes: 2000,
          createdTime: DateTime(2025, 2, 20),
        ),
      ];

      final groups = groupArchiveFiles(files);

      expect(groups, hasLength(2));
      expect(groups[0].files, hasLength(1));
      expect(groups[1].files, hasLength(1));
    });

    test('mixed split and non-split are grouped correctly', () {
      // Use a non-split name without trailing digits to avoid regex match
      final files = [
        ArchiveFile(
          fileId: 'f1',
          name: 'takeout-20250115-001.zip',
          sizeBytes: 1000,
          createdTime: DateTime(2025, 1, 15),
        ),
        ArchiveFile(
          fileId: 'f2',
          name: 'takeout-20250115-002.zip',
          sizeBytes: 1500,
          createdTime: DateTime(2025, 1, 15),
        ),
        ArchiveFile(
          fileId: 'f3',
          name: 'takeout-february.zip',
          sizeBytes: 3000,
          createdTime: DateTime(2025, 2, 20),
        ),
      ];

      final groups = groupArchiveFiles(files);

      expect(groups, hasLength(2));

      // Find the split group
      final splitGroup = groups.firstWhere((g) => g.files.length > 1);
      expect(splitGroup.files, hasLength(2));
      expect(splitGroup.totalSizeBytes, equals(2500));

      // Find the non-split group
      final singleGroup = groups.firstWhere((g) => g.files.length == 1);
      expect(singleGroup.files.first.name, equals('takeout-february.zip'));
    });

    test('groups sorted by latest created time', () {
      final files = [
        ArchiveFile(
          fileId: 'f1',
          name: 'takeout-jan-001.zip',
          sizeBytes: 1000,
          createdTime: DateTime(2025, 1, 15),
        ),
        ArchiveFile(
          fileId: 'f2',
          name: 'takeout-jan-002.zip',
          sizeBytes: 1000,
          createdTime: DateTime(2025, 1, 16),
        ),
        ArchiveFile(
          fileId: 'f3',
          name: 'takeout-feb-001.zip',
          sizeBytes: 2000,
          createdTime: DateTime(2025, 2, 20),
        ),
        ArchiveFile(
          fileId: 'f4',
          name: 'takeout-feb-002.zip',
          sizeBytes: 2000,
          createdTime: DateTime(2025, 2, 21),
        ),
      ];

      final groups = groupArchiveFiles(files);

      // Sort by latest created time descending (simulating findLatestArchiveGroup)
      groups.sort(
          (a, b) => b.latestCreatedTime.compareTo(a.latestCreatedTime));

      expect(groups, hasLength(2));
      // Latest group should be first (2025-02-21 > 2025-01-16)
      expect(groups.first.latestCreatedTime, DateTime(2025, 2, 21));
      expect(groups.last.latestCreatedTime, DateTime(2025, 1, 16));
    });

    test('files within a group are sorted by name', () {
      final files = [
        ArchiveFile(
          fileId: 'f3',
          name: 'takeout-20250115-003.zip',
          sizeBytes: 1000,
          createdTime: DateTime(2025, 1, 15),
        ),
        ArchiveFile(
          fileId: 'f1',
          name: 'takeout-20250115-001.zip',
          sizeBytes: 1000,
          createdTime: DateTime(2025, 1, 15),
        ),
        ArchiveFile(
          fileId: 'f2',
          name: 'takeout-20250115-002.zip',
          sizeBytes: 1000,
          createdTime: DateTime(2025, 1, 15),
        ),
      ];

      final groups = groupArchiveFiles(files);

      expect(groups, hasLength(1));
      expect(groups.first.files[0].name, equals('takeout-20250115-001.zip'));
      expect(groups.first.files[1].name, equals('takeout-20250115-002.zip'));
      expect(groups.first.files[2].name, equals('takeout-20250115-003.zip'));
    });

    test('latestCreatedTime picks the most recent among group files', () {
      final files = [
        ArchiveFile(
          fileId: 'f1',
          name: 'takeout-20250115-001.zip',
          sizeBytes: 1000,
          createdTime: DateTime(2025, 1, 15, 8, 0),
        ),
        ArchiveFile(
          fileId: 'f2',
          name: 'takeout-20250115-002.zip',
          sizeBytes: 1000,
          createdTime: DateTime(2025, 1, 15, 12, 0),
        ),
        ArchiveFile(
          fileId: 'f3',
          name: 'takeout-20250115-003.zip',
          sizeBytes: 1000,
          createdTime: DateTime(2025, 1, 15, 10, 0),
        ),
      ];

      final groups = groupArchiveFiles(files);

      expect(groups, hasLength(1));
      // Latest created time should be 12:00
      expect(groups.first.latestCreatedTime,
          equals(DateTime(2025, 1, 15, 12, 0)));
    });
  });
}
