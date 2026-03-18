import 'dart:convert';

import '../../domain/models/raw_place_record.dart';
import '../../domain/models/normalized_place_record.dart';

class PlaceNormalizer {
  // Mapping from possible CSV header names to our internal field names
  static const _headerMappings = {
    'sourceTitle': ['title', 'name', 'place_name', 'source_title'],
    'mapsUrl': [
      'url',
      'item_content_url',
      'maps_url',
      'link',
      'google_maps_url'
    ],
    'note': ['note', 'notes', 'memo'],
    'comments': ['comments', 'comment', 'description'],
    'collectionName': ['collection_name', 'list_name', 'list', 'collection'],
    'collectionDescription': [
      'collection_description',
      'list_description',
    ],
  };

  /// Normalize a RawPlaceRecord into a NormalizedPlaceRecord.
  NormalizedPlaceRecord normalize(RawPlaceRecord raw) {
    final mapped = _mapFields(raw.fields);

    return NormalizedPlaceRecord(
      sourceTitle: _cleanString(mapped['sourceTitle']),
      mapsUrl: _cleanUrl(mapped['mapsUrl']),
      note: _cleanString(mapped['note']),
      comments: _cleanString(mapped['comments']),
      collectionName: _cleanString(mapped['collectionName']),
      collectionDescription: _cleanString(mapped['collectionDescription']),
      rawPayloadJson: jsonEncode(raw.fields),
    );
  }

  /// Map raw CSV field names to internal field names.
  Map<String, String?> _mapFields(Map<String, String> rawFields) {
    final result = <String, String?>{};

    for (final entry in _headerMappings.entries) {
      final internalName = entry.key;
      final possibleHeaders = entry.value;

      String? value;
      for (final header in possibleHeaders) {
        final normalizedHeader = header.toLowerCase().replaceAll(' ', '_');
        for (final rawEntry in rawFields.entries) {
          if (rawEntry.key.toLowerCase().replaceAll(' ', '_') ==
              normalizedHeader) {
            value = rawEntry.value;
            break;
          }
        }
        if (value != null) break;
      }

      result[internalName] = value;
    }

    return result;
  }

  /// Clean a string value: trim, collapse whitespace, return null if empty.
  static String? _cleanString(String? value) {
    if (value == null) return null;

    var cleaned = value.trim();

    // Collapse multiple newlines
    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    // Collapse multiple spaces
    cleaned = cleaned.replaceAll(RegExp(r' {2,}'), ' ');

    return cleaned.isEmpty ? null : cleaned;
  }

  /// Clean and normalize a URL.
  static String? _cleanUrl(String? url) {
    if (url == null) return null;

    var cleaned = url.trim();
    if (cleaned.isEmpty) return null;

    // Basic URL validation
    if (!cleaned.startsWith('http://') && !cleaned.startsWith('https://')) {
      // Try to prepend https if it looks like a URL
      if (cleaned.contains('google.com/maps') ||
          cleaned.contains('goo.gl') ||
          cleaned.contains('maps.app')) {
        cleaned = 'https://$cleaned';
      } else {
        return cleaned; // Store as-is if not a recognizable URL
      }
    }

    return cleaned;
  }
}
