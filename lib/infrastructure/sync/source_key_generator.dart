import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../domain/models/app_error.dart';
import '../../domain/models/normalized_place_record.dart';
import 'url_normalizer.dart';

class SourceKeyGenerator {
  /// Generate a stable, idempotent source key for a normalized place record.
  ///
  /// Priority:
  /// 1. Normalized maps_url (if present)
  /// 2. Concatenation of title + note + comments + collection_name
  /// 3. Full raw payload hash as last resort
  String generate(NormalizedPlaceRecord record) {
    // Priority 1: URL-based key
    if (record.mapsUrl != null && record.mapsUrl!.isNotEmpty) {
      final normalizedUrl = UrlNormalizer.normalize(record.mapsUrl!);
      return _sha256(normalizedUrl);
    }

    // Priority 2: Field-based key
    final fallback = [
      _normalizeText(record.sourceTitle),
      _normalizeText(record.note),
      _normalizeText(record.comments),
      _normalizeText(record.collectionName),
    ].join('||');

    if (fallback.replaceAll('||', '').isNotEmpty) {
      return _sha256(fallback);
    }

    // Priority 3: Raw payload hash (last resort)
    if (record.rawPayloadJson != null && record.rawPayloadJson!.isNotEmpty) {
      return _sha256(record.rawPayloadJson!);
    }

    // Should not reach here in normal operation
    throw const AppError(
      AppErrorCode.csvParseFailed,
      'Cannot generate source_key: all fields are empty',
    );
  }

  /// Normalize text for stable hashing.
  static String _normalizeText(String? text) {
    if (text == null) return '';

    return text
        .trim()
        .toLowerCase()
        // Normalize full-width to half-width for common chars
        .replaceAll('\u3000', ' ') // Full-width space
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _sha256(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
