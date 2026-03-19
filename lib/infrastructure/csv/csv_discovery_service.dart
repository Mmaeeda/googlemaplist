import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../logging/sync_logger.dart';

class CsvCandidate {
  final String filePath;
  final int score;
  final List<String> matchReasons;

  const CsvCandidate({
    required this.filePath,
    required this.score,
    required this.matchReasons,
  });

  @override
  String toString() =>
      'CsvCandidate(path: $filePath, score: $score, reasons: $matchReasons)';
}

class CsvDiscoveryService {
  final SyncLogger _logger;

  // Header columns that indicate a Saved-places CSV
  static const _scoredHeaders = {
    // English
    'title': 3,
    'note': 2,
    'comments': 2,
    'comment': 2,
    'item_content_url': 3,
    'collection_name': 2,
    'collection_description': 1,
    'url': 2,
    'updated': 1,
    // Japanese
    'タイトル': 3,
    'メモ': 2,
    'コメント': 2,
    '説明': 1,
  };

  // Filename patterns that boost score
  static const _fileNamePatterns = [
    // English
    'saved', 'maps', 'places', 'locations',
    // Japanese
    '保存', 'マップ', '場所', 'マイプレイス', 'お気に入り', '行きたい', 'スター',
  ];

  CsvDiscoveryService(this._logger);

  /// Find candidate CSV files within an extracted directory.
  Future<List<CsvCandidate>> findCandidates(String extractedDir) async {
    final dir = Directory(extractedDir);
    if (!await dir.exists()) {
      _logger.warn('Extracted directory does not exist', {
        'path': extractedDir,
      });
      return [];
    }

    final candidates = <CsvCandidate>[];

    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File) continue;
      if (p.extension(entity.path).toLowerCase() != '.csv') continue;

      final candidate = await _evaluateFile(entity);
      if (candidate != null) {
        candidates.add(candidate);
      }
    }

    // Sort by score descending
    candidates.sort((a, b) => b.score.compareTo(a.score));

    _logger.info('csv_discovery_completed', {
      'directory': extractedDir,
      'candidateCount': candidates.length,
      'topScore': candidates.isNotEmpty ? candidates.first.score : 0,
    });

    return candidates;
  }

  Future<CsvCandidate?> _evaluateFile(File file) async {
    var score = 0;
    final reasons = <String>[];

    // Score by filename
    final fileName = p.basenameWithoutExtension(file.path).toLowerCase();
    for (final pattern in _fileNamePatterns) {
      if (fileName.contains(pattern)) {
        score += 2;
        reasons.add('filename_match:$pattern');
      }
    }

    // Score by header content
    try {
      final firstLine = await _readFirstLine(file);
      if (firstLine != null) {
        final headers = firstLine
            .toLowerCase()
            .split(',')
            .map((h) => h.trim().replaceAll('"', ''))
            .toList();

        for (final entry in _scoredHeaders.entries) {
          if (headers.any((h) => h.contains(entry.key))) {
            score += entry.value;
            reasons.add('header_match:${entry.key}');
          }
        }
      }
    } catch (e) {
      // Can't read file, skip it
      return null;
    }

    // Minimum score threshold
    if (score < 3) return null;

    return CsvCandidate(
      filePath: file.path,
      score: score,
      matchReasons: reasons,
    );
  }

  Future<String?> _readFirstLine(File file) async {
    try {
      final lines = await file
          .openRead()
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .take(1)
          .toList();
      return lines.isNotEmpty ? lines.first : null;
    } catch (_) {
      return null;
    }
  }
}
