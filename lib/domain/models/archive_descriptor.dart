/// Describes a single file within a Takeout archive on Drive.
class ArchiveFile {
  final String fileId;
  final String name;
  final int sizeBytes;
  final DateTime createdTime;

  const ArchiveFile({
    required this.fileId,
    required this.name,
    required this.sizeBytes,
    required this.createdTime,
  });

  @override
  String toString() => 'ArchiveFile(name: $name, size: $sizeBytes)';
}

/// A group of related Takeout archive files (may include split ZIPs).
class ArchiveGroup {
  final String identifier;
  final List<ArchiveFile> files;
  final DateTime latestCreatedTime;

  const ArchiveGroup({
    required this.identifier,
    required this.files,
    required this.latestCreatedTime,
  });

  String get displayName {
    if (files.length == 1) return files.first.name;
    return '${files.first.name} (+${files.length - 1} parts)';
  }

  int get totalSizeBytes =>
      files.fold(0, (sum, f) => sum + f.sizeBytes);

  @override
  String toString() =>
      'ArchiveGroup(id: $identifier, files: ${files.length}, '
      'totalSize: $totalSizeBytes)';
}
