import 'dart:convert';
import 'dart:typed_data';

import '../../domain/models/normalized_place_record.dart';
import '../logging/sync_logger.dart';

class GeoJsonParseResult {
  final List<NormalizedPlaceRecord> records;
  final int skippedCount;

  const GeoJsonParseResult({
    required this.records,
    required this.skippedCount,
  });
}

/// Parses Google Takeout GeoJSON files into NormalizedPlaceRecords.
///
/// Handles multiple Google Takeout format variations:
/// - Standard: properties.Title
/// - Alternative: properties.name
/// - Nested: properties.Location."Business Name"
/// - Case-insensitive fallback
/// - Dynamic property scanning as last resort
class GeoJsonParser {
  final SyncLogger _logger;

  GeoJsonParser(this._logger);

  /// Parse GeoJSON bytes into NormalizedPlaceRecords.
  GeoJsonParseResult parse(Uint8List bytes, {String? fileName}) {
    final content = _decodeContent(bytes);
    return parseString(content, fileName: fileName);
  }

  /// Parse GeoJSON string into NormalizedPlaceRecords.
  GeoJsonParseResult parseString(String content, {String? fileName}) {
    final records = <NormalizedPlaceRecord>[];
    var skippedCount = 0;

    final dynamic json;
    try {
      json = jsonDecode(content);
    } catch (e) {
      _logger.warn('geojson_parse_failed', {
        'fileName': fileName,
        'error': e.toString(),
      });
      return GeoJsonParseResult(records: [], skippedCount: 0);
    }

    if (json is! Map<String, dynamic>) {
      _logger.warn('geojson_not_object', {'fileName': fileName});
      return GeoJsonParseResult(records: [], skippedCount: 0);
    }

    // Handle FeatureCollection
    final features = json['features'] as List<dynamic>? ?? [];

    // Log FULL first feature for diagnostics
    if (features.isNotEmpty) {
      try {
        final firstFeature = features[0] as Map<String, dynamic>;
        final firstProps =
            firstFeature['properties'] as Map<String, dynamic>? ?? {};
        _logger.info('geojson_first_feature_debug', {
          'fileName': fileName,
          'featureKeys': firstFeature.keys.toList(),
          'propertyKeys': firstProps.keys.toList(),
          'propertyValues': firstProps.map(
            (k, v) => MapEntry(
              k,
              v is String
                  ? (v.length > 80 ? '${v.substring(0, 80)}...' : v)
                  : v is Map
                      ? '{${(v as Map).keys.join(", ")}}'
                      : v.toString(),
            ),
          ),
          'hasGeometry': firstFeature.containsKey('geometry'),
        });
      } catch (_) {
        // Diagnostic only — ignore errors
      }
    }

    for (var i = 0; i < features.length; i++) {
      try {
        final feature = features[i] as Map<String, dynamic>;
        final record = _parseFeature(feature, logIndex: i);
        if (record != null) {
          records.add(record);
        } else {
          skippedCount++;
        }
      } catch (e) {
        _logger.warn('geojson_feature_skipped', {
          'fileName': fileName,
          'index': i,
          'error': e.toString(),
        });
        skippedCount++;
      }
    }

    _logger.info('geojson_parse_completed', {
      'fileName': fileName,
      'featureCount': features.length,
      'parsedRecords': records.length,
      'skippedCount': skippedCount,
    });

    return GeoJsonParseResult(records: records, skippedCount: skippedCount);
  }

  NormalizedPlaceRecord? _parseFeature(
    Map<String, dynamic> feature, {
    int logIndex = -1,
  }) {
    final props = feature['properties'] as Map<String, dynamic>? ?? {};
    final geometry = feature['geometry'] as Map<String, dynamic>?;

    // ── Step 1: Extract title ──

    // 1a. Try exact key matches at top level
    var title = _findString(props, [
      'Title', 'title', 'Name', 'name', 'label', 'Label',
      'タイトル', '名前', 'ラベル',
    ]);

    // 1b. Try nested Location/場所 object
    if (title == null) {
      final location = _findMap(props, [
        'Location', 'location', '場所', 'Place', 'place',
      ]);
      if (location != null) {
        title = _findString(location, [
          'Business Name', 'business_name', 'Name', 'name',
          'ビジネス名', '名前', '店名', 'Label', 'label',
        ]);
      }
    }

    // 1c. Case-insensitive key scan
    if (title == null) {
      title = _findStringCaseInsensitive(props, [
        'title', 'name', 'label', 'place_name', 'placename',
      ]);
    }

    // 1d. Last resort: find any suitable string property
    if (title == null) {
      title = _findFirstSuitableTitle(props);
    }

    // ── Step 2: Extract Maps URL ──

    var mapsUrl = _findString(props, [
      'Google Maps URL', 'google_maps_url', 'URL', 'url',
      'Google マップの URL', 'maps_url', 'link', 'Link',
    ]);

    // Case-insensitive URL search
    if (mapsUrl == null) {
      mapsUrl = _findStringCaseInsensitive(props, [
        'google maps url', 'url', 'link', 'maps_url',
      ]);
    }

    // Construct URL from geometry coordinates
    if (mapsUrl == null && geometry != null) {
      final coords = geometry['coordinates'] as List<dynamic>?;
      if (coords != null && coords.length >= 2) {
        final lng = coords[0];
        final lat = coords[1];
        if (lng is num && lat is num) {
          mapsUrl = 'https://www.google.com/maps?q=$lat,$lng';
        }
      }
    }

    // Skip entries with no title and no URL
    if (title == null && mapsUrl == null) return null;

    // Log what we found for the first few features
    if (logIndex < 3) {
      _logger.info('geojson_feature_parsed', {
        'index': logIndex,
        'title': title,
        'mapsUrl': mapsUrl != null
            ? (mapsUrl.length > 60
                ? '${mapsUrl.substring(0, 60)}...'
                : mapsUrl)
            : null,
        'propKeys': props.keys.toList(),
      });
    }

    // ── Step 3: Extract other fields ──

    // Location object for address
    final location = _findMap(props, [
      'Location', 'location', '場所', 'Place', 'place',
    ]);

    String? address;
    if (location != null) {
      address = _findString(location, [
        'Address', 'address', '住所',
      ]);
    }

    // Note/comment
    final note = _findString(props, [
      'Note', 'note', 'Notes', 'notes',
      'メモ', 'ノート',
    ]);

    final comment = _findString(props, [
      'Comment', 'comment', 'Comments', 'comments',
      'Description', 'description',
      'コメント', '説明',
    ]);

    return NormalizedPlaceRecord(
      sourceTitle: title,
      mapsUrl: mapsUrl,
      note: note ?? address,
      comments: comment,
      rawPayloadJson: jsonEncode(props),
    );
  }

  /// Find a string value by trying exact key matches.
  String? _findString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value != null && value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  /// Find a nested Map by trying multiple keys.
  Map<String, dynamic>? _findMap(
      Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is Map<String, dynamic>) {
        return value;
      }
    }
    // Case-insensitive fallback
    for (final entry in map.entries) {
      final lowerKey = entry.key.toLowerCase();
      for (final key in keys) {
        if (lowerKey == key.toLowerCase() && entry.value is Map) {
          return Map<String, dynamic>.from(entry.value as Map);
        }
      }
    }
    return null;
  }

  /// Case-insensitive key search for string values.
  String? _findStringCaseInsensitive(
      Map<String, dynamic> map, List<String> targetKeys) {
    for (final entry in map.entries) {
      final lowerKey = entry.key.toLowerCase().replaceAll(' ', '_');
      for (final target in targetKeys) {
        if (lowerKey == target.toLowerCase().replaceAll(' ', '_')) {
          final value = entry.value;
          if (value is String && value.trim().isNotEmpty) {
            return value.trim();
          }
        }
      }
    }
    return null;
  }

  /// Find the first string property that looks like a place name.
  /// Excludes URLs, dates, and very long strings.
  String? _findFirstSuitableTitle(Map<String, dynamic> props) {
    // Skip these keys — they are known non-title fields
    const skipKeys = {
      'published', 'updated', 'created', 'date', 'type',
      'google maps url', 'url', 'link',
      'status', 'category',
    };

    for (final entry in props.entries) {
      if (skipKeys.contains(entry.key.toLowerCase())) continue;

      final value = entry.value;
      if (value is String &&
          value.trim().isNotEmpty &&
          value.trim().length > 1 &&
          value.trim().length < 200 &&
          !value.trim().startsWith('http') &&
          !_looksLikeDate(value.trim())) {
        return value.trim();
      }
    }
    return null;
  }

  /// Check if a string looks like an ISO date.
  bool _looksLikeDate(String value) {
    return RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(value);
  }

  /// Decode bytes handling BOM and UTF-8.
  String _decodeContent(List<int> bytes) {
    // Remove UTF-8 BOM if present
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      bytes = bytes.sublist(3);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}
