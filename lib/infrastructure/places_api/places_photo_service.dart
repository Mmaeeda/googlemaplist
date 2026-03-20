import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/place.dart';
import '../../domain/repositories/place_repository.dart';
import '../logging/sync_logger.dart';

/// Resolves place photos via Google Places API (New).
///
/// Flow per place:
/// 1. Nearby Search by coordinates → get first photo reference
/// 2. Photo media endpoint with skipHttpRedirect → get CDN photoUri
/// 3. Store photoUri in place record
class PlacesPhotoService {
  final PlaceRepository _placeRepository;
  final SyncLogger _logger;
  final http.Client _httpClient;

  PlacesPhotoService({
    required PlaceRepository placeRepository,
    required SyncLogger logger,
    http.Client? httpClient,
  })  : _placeRepository = placeRepository,
        _logger = logger,
        _httpClient = httpClient ?? http.Client();

  /// Resolve photos for all places that don't have one yet.
  /// Returns the number of successfully resolved photos.
  Future<int> resolvePhotos({
    required String apiKey,
    void Function(int current, int total)? onProgress,
  }) async {
    final allPlaces = await _placeRepository.listAllActive();
    final withoutPhoto = allPlaces
        .where((p) => p.photoUrl == null || p.photoUrl!.isEmpty)
        .toList();

    if (withoutPhoto.isEmpty) {
      _logger.info('photo_resolve_skipped', {'reason': 'all places have photos'});
      return 0;
    }

    _logger.info('photo_resolve_started', {'count': withoutPhoto.length});
    var resolvedCount = 0;
    var failedCount = 0;
    var noCoordCount = 0;

    for (var i = 0; i < withoutPhoto.length; i++) {
      final place = withoutPhoto[i];
      onProgress?.call(i + 1, withoutPhoto.length);

      try {
        final coords = _extractCoordinates(place);
        if (coords == null) {
          noCoordCount++;
          continue;
        }

        final photoUrl = await _resolvePhotoForPlace(
          lat: coords.$1,
          lng: coords.$2,
          apiKey: apiKey,
        );

        if (photoUrl != null) {
          final updated = place.copyWith(
            photoUrl: photoUrl,
            updatedAt: DateTime.now(),
          );
          await _placeRepository.update(updated);
          resolvedCount++;

          if (resolvedCount <= 5) {
            _logger.info('photo_resolved', {
              'placeId': place.id,
              'title': place.sourceTitle,
            });
          }
        }

        // Rate limit: ~5 requests/second (2 API calls per place)
        await Future.delayed(const Duration(milliseconds: 400));
      } catch (e) {
        failedCount++;
        if (failedCount <= 5) {
          _logger.warn('photo_resolve_failed', {
            'placeId': place.id,
            'error': e.toString(),
          });
        }
        // If we get auth errors, stop early
        if (e.toString().contains('403') || e.toString().contains('401')) {
          _logger.error('photo_resolve_auth_error', {
            'error': 'API key may be invalid or Places API not enabled',
          });
          break;
        }
      }
    }

    _logger.info('photo_resolve_completed', {
      'total': withoutPhoto.length,
      'resolved': resolvedCount,
      'failed': failedCount,
      'noCoordinates': noCoordCount,
    });

    return resolvedCount;
  }

  /// Resolve a photo URL for a single place using coordinates.
  Future<String?> _resolvePhotoForPlace({
    required double lat,
    required double lng,
    required String apiKey,
  }) async {
    // Step 1: Nearby Search to find the place and get photo reference
    final searchUri = Uri.parse(
      'https://places.googleapis.com/v1/places:searchNearby',
    );

    final searchResponse = await _httpClient.post(
      searchUri,
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask': 'places.photos',
      },
      body: jsonEncode({
        'maxResultCount': 1,
        'locationRestriction': {
          'circle': {
            'center': {'latitude': lat, 'longitude': lng},
            'radiusMeters': 50,
          },
        },
      }),
    );

    if (searchResponse.statusCode != 200) {
      throw Exception(
        'Nearby Search failed: ${searchResponse.statusCode} ${searchResponse.body}',
      );
    }

    final searchData =
        jsonDecode(searchResponse.body) as Map<String, dynamic>;
    final places = searchData['places'] as List<dynamic>?;
    if (places == null || places.isEmpty) return null;

    final firstPlace = places[0] as Map<String, dynamic>;
    final photos = firstPlace['photos'] as List<dynamic>?;
    if (photos == null || photos.isEmpty) return null;

    final photoName = photos[0]['name'] as String?;
    if (photoName == null) return null;

    // Step 2: Get the photo CDN URL
    final photoUri = Uri.parse(
      'https://places.googleapis.com/v1/$photoName/media'
      '?maxHeightPx=200&maxWidthPx=200&skipHttpRedirect=true',
    );

    final photoResponse = await _httpClient.get(
      photoUri,
      headers: {'X-Goog-Api-Key': apiKey},
    );

    if (photoResponse.statusCode != 200) return null;

    final photoData =
        jsonDecode(photoResponse.body) as Map<String, dynamic>;
    return photoData['photoUri'] as String?;
  }

  /// Extract (lat, lng) from rawPayloadJson or mapsUrl.
  (double, double)? _extractCoordinates(Place place) {
    if (place.rawPayloadJson != null) {
      try {
        final raw =
            jsonDecode(place.rawPayloadJson!) as Map<String, dynamic>;
        final geometry = raw['geometry'] as Map<String, dynamic>?;
        if (geometry != null) {
          final coords = geometry['coordinates'] as List<dynamic>?;
          if (coords != null && coords.length >= 2) {
            final lng = (coords[0] as num).toDouble();
            final lat = (coords[1] as num).toDouble();
            return (lat, lng);
          }
        }
      } catch (_) {}
    }

    if (place.mapsUrl != null) {
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

  void dispose() {
    _httpClient.close();
  }
}
