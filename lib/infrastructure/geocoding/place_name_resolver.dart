import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/place.dart';
import '../../domain/repositories/place_repository.dart';
import '../logging/sync_logger.dart';

/// Resolves place names for records that lack titles by reverse geocoding
/// coordinates via the Nominatim (OpenStreetMap) API.
///
/// Nominatim usage policy: max 1 request/second, requires email parameter.
class PlaceNameResolver {
  final PlaceRepository _placeRepository;
  final SyncLogger _logger;
  final http.Client _httpClient;

  PlaceNameResolver({
    required PlaceRepository placeRepository,
    required SyncLogger logger,
    http.Client? httpClient,
  })  : _placeRepository = placeRepository,
        _logger = logger,
        _httpClient = httpClient ?? http.Client();

  /// Resolve titles for places with null sourceTitle.
  /// Returns the number of successfully resolved places.
  Future<int> resolveAll() async {
    final allPlaces = await _placeRepository.listAllActive();
    final untitled = allPlaces
        .where((p) => p.sourceTitle == null || p.sourceTitle!.trim().isEmpty)
        .toList();

    if (untitled.isEmpty) {
      _logger.info('place_name_resolve_skipped', {
        'reason': 'no untitled places',
      });
      return 0;
    }

    _logger.info('place_name_resolve_started', {'count': untitled.length});
    var resolvedCount = 0;
    var failedCount = 0;
    var noCoordCount = 0;

    for (final place in untitled) {
      try {
        final coords = _extractCoordinates(place);
        if (coords == null) {
          noCoordCount++;
          continue;
        }

        final name = await _reverseGeocode(coords.$1, coords.$2);
        if (name != null && name.isNotEmpty) {
          final updated = place.copyWith(
            sourceTitle: name,
            updatedAt: DateTime.now(),
          );
          await _placeRepository.update(updated);
          resolvedCount++;

          if (resolvedCount <= 5) {
            _logger.info('place_name_resolved', {
              'placeId': place.id,
              'name': name,
              'lat': coords.$1,
              'lng': coords.$2,
            });
          }
        }

        // Nominatim rate limit: max 1 request/second
        await Future.delayed(const Duration(milliseconds: 1100));
      } catch (e) {
        failedCount++;
        _logger.warn('place_name_resolve_failed', {
          'placeId': place.id,
          'error': e.toString(),
        });
      }
    }

    _logger.info('place_name_resolve_completed', {
      'total': untitled.length,
      'resolved': resolvedCount,
      'failed': failedCount,
      'noCoordinates': noCoordCount,
    });

    return resolvedCount;
  }

  /// Extract (lat, lng) from rawPayloadJson or mapsUrl.
  (double, double)? _extractCoordinates(Place place) {
    // Try rawPayloadJson first (contains geometry if from GeoJSON parser)
    if (place.rawPayloadJson != null) {
      try {
        final raw = jsonDecode(place.rawPayloadJson!) as Map<String, dynamic>;

        // New format: {properties: {...}, geometry: {...}}
        final geometry = raw['geometry'] as Map<String, dynamic>?;
        if (geometry != null) {
          final coords = geometry['coordinates'] as List<dynamic>?;
          if (coords != null && coords.length >= 2) {
            final lng = (coords[0] as num).toDouble();
            final lat = (coords[1] as num).toDouble();
            return (lat, lng);
          }
        }
      } catch (_) {
        // Fall through to mapsUrl extraction
      }
    }

    // Try to extract from mapsUrl
    if (place.mapsUrl != null) {
      // Coordinate URL: https://www.google.com/maps?q=LAT,LNG
      final qMatch =
          RegExp(r'[?&]q=([-\d.]+),([-\d.]+)').firstMatch(place.mapsUrl!);
      if (qMatch != null) {
        try {
          return (
            double.parse(qMatch.group(1)!),
            double.parse(qMatch.group(2)!),
          );
        } catch (_) {}
      }
    }

    return null;
  }

  /// Reverse geocode coordinates via Nominatim (OpenStreetMap).
  Future<String?> _reverseGeocode(double lat, double lng) async {
    final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/reverse'
      '?lat=$lat&lon=$lng&format=json&zoom=18'
      '&accept-language=ja'
      '&email=maps-saved-app@example.com',
    );

    final response = await _httpClient.get(uri, headers: {
      'Accept': 'application/json',
    });

    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    // Priority 1: Specific place name
    final name = data['name'] as String?;
    if (name != null && name.isNotEmpty) return name;

    // Priority 2: Address component with a meaningful name
    final address = data['address'] as Map<String, dynamic>?;
    if (address != null) {
      for (final key in [
        'tourism',
        'amenity',
        'shop',
        'leisure',
        'building',
        'historic',
        'natural',
        'man_made',
        'road',
        'neighbourhood',
        'suburb',
      ]) {
        final value = address[key];
        if (value is String && value.isNotEmpty) return value;
      }
    }

    // Priority 3: First component of display_name
    final displayName = data['display_name'] as String?;
    if (displayName != null && displayName.isNotEmpty) {
      return displayName.split(',').first.trim();
    }

    return null;
  }

  void dispose() {
    _httpClient.close();
  }
}
