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
/// Google Takeout exports saved places as GeoJSON FeatureCollection:
/// ```json
/// {
///   "type": "FeatureCollection",
///   "features": [{
///     "type": "Feature",
///     "geometry": { "coordinates": [lng, lat], "type": "Point" },
///     "properties": {
///       "Title": "Place Name",
///       "Google Maps URL": "https://maps.google.com/...",
///       "Location": { "Address": "..." },
///       "Published": "2024-01-01T00:00:00Z",
///       "Updated": "2024-01-01T00:00:00Z"
///     }
///   }]
/// }
/// ```
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

    for (var i = 0; i < features.length; i++) {
      try {
        final feature = features[i] as Map<String, dynamic>;
        final record = _parseFeature(feature);
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

  NormalizedPlaceRecord? _parseFeature(Map<String, dynamic> feature) {
    final props = feature['properties'] as Map<String, dynamic>? ?? {};

    // Extract title (try multiple field names)
    final title = _findString(props, [
      'Title', 'title', 'Name', 'name',
      'タイトル', '名前',
    ]);

    // Extract Google Maps URL
    final mapsUrl = _findString(props, [
      'Google Maps URL', 'google_maps_url', 'URL', 'url',
      'Google マップの URL',
    ]);

    // Skip entries with no title and no URL
    if (title == null && mapsUrl == null) return null;

    // Extract note/comment
    final note = _findString(props, [
      'Note', 'note', 'Notes', 'notes',
      'メモ', 'ノート',
    ]);

    final comment = _findString(props, [
      'Comment', 'comment', 'Comments', 'comments',
      'Description', 'description',
      'コメント', '説明',
    ]);

    // Extract address from Location object
    final location = props['Location'] as Map<String, dynamic>?;
    String? address;
    if (location != null) {
      address = _findString(location, [
        'Address', 'address', '住所',
      ]);
    }

    // Use the filename (without extension) as collection name
    // e.g., "保存済みの場所.json" → "保存済みの場所"
    // This is set by the caller, not here

    return NormalizedPlaceRecord(
      sourceTitle: title,
      mapsUrl: mapsUrl,
      note: note ?? address,
      comments: comment,
      rawPayloadJson: jsonEncode(props),
    );
  }

  /// Find a string value in a map by trying multiple keys.
  String? _findString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value != null && value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
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
