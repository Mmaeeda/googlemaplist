import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/place.dart';
import '../../domain/repositories/place_repository.dart';
import '../logging/sync_logger.dart';

/// Diagnostic result from photo resolution.
class PhotoResolveResult {
  final int total;
  final int resolved;
  final int noCoordinates;
  final int noPlaceFound;
  final int noPhotoFound;
  final int saveFailed;
  final int apiFailed;
  final String? firstError;

  const PhotoResolveResult({
    this.total = 0,
    this.resolved = 0,
    this.noCoordinates = 0,
    this.noPlaceFound = 0,
    this.noPhotoFound = 0,
    this.saveFailed = 0,
    this.apiFailed = 0,
    this.firstError,
  });
}

/// Resolves place photos via Google Places API.
///
/// Uses the Nearby Search API to find a place by coordinates,
/// then constructs a photo URL from the photo_reference.
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
  Future<PhotoResolveResult> resolvePhotos({
    required String apiKey,
    void Function(int current, int total)? onProgress,
  }) async {
    final allPlaces = await _placeRepository.listAllActive();
    final withoutPhoto = allPlaces
        .where((p) => p.photoUrl == null || p.photoUrl!.isEmpty)
        .toList();

    if (withoutPhoto.isEmpty) {
      _logger.info('photo_resolve_skipped', {
        'reason': 'all places have photos',
      });
      return PhotoResolveResult(total: allPlaces.length);
    }

    _logger.info('photo_resolve_started', {
      'totalPlaces': allPlaces.length,
      'withoutPhoto': withoutPhoto.length,
    });

    var resolved = 0;
    var noCoordinates = 0;
    var noPlaceFound = 0;
    var noPhotoFound = 0;
    var saveFailed = 0;
    var apiFailed = 0;
    String? firstError;

    for (var i = 0; i < withoutPhoto.length; i++) {
      final place = withoutPhoto[i];
      onProgress?.call(i + 1, withoutPhoto.length);

      try {
        final coords = _extractCoordinates(place);
        if (coords == null) {
          noCoordinates++;
          continue;
        }

        final photoUrl = await _resolvePhotoForPlace(
          lat: coords.$1,
          lng: coords.$2,
          apiKey: apiKey,
        );

        if (photoUrl == null) {
          noPlaceFound++;
          continue;
        }

        if (photoUrl == 'no_photo') {
          noPhotoFound++;
          continue;
        }

        // Save to DB
        try {
          final updated = place.copyWith(
            photoUrl: photoUrl,
            updatedAt: DateTime.now(),
          );
          await _placeRepository.update(updated);
          resolved++;
        } catch (e) {
          saveFailed++;
          firstError ??= 'DB保存エラー: $e';
          _logger.warn('photo_save_failed', {
            'placeId': place.id,
            'error': e.toString(),
          });
        }

        // Rate limit: ~3 requests/second
        await Future.delayed(const Duration(milliseconds: 350));
      } catch (e) {
        apiFailed++;
        firstError ??= e.toString();
        _logger.warn('photo_resolve_failed', {
          'placeId': place.id,
          'error': e.toString(),
        });
        // Stop early on auth errors
        if (e.toString().contains('403') ||
            e.toString().contains('401') ||
            e.toString().contains('REQUEST_DENIED')) {
          firstError = 'APIキーが無効、またはPlaces APIが未有効化です';
          break;
        }
      }
    }

    final result = PhotoResolveResult(
      total: withoutPhoto.length,
      resolved: resolved,
      noCoordinates: noCoordinates,
      noPlaceFound: noPlaceFound,
      noPhotoFound: noPhotoFound,
      saveFailed: saveFailed,
      apiFailed: apiFailed,
      firstError: firstError,
    );

    _logger.info('photo_resolve_completed', {
      'total': result.total,
      'resolved': result.resolved,
      'noCoordinates': result.noCoordinates,
      'noPlaceFound': result.noPlaceFound,
      'noPhotoFound': result.noPhotoFound,
      'saveFailed': result.saveFailed,
      'apiFailed': result.apiFailed,
      'firstError': result.firstError,
    });

    return result;
  }

  /// Resolve a photo URL for a single place using coordinates.
  /// Returns photo URL, 'no_photo' if place found but no photos, or null if no place.
  Future<String?> _resolvePhotoForPlace({
    required double lat,
    required double lng,
    required String apiKey,
  }) async {
    // Use Places API Nearby Search (GET, simpler CORS)
    final searchUri = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
      '?location=$lat,$lng'
      '&radius=50'
      '&key=$apiKey',
    );

    final searchResponse = await _httpClient.get(searchUri);

    if (searchResponse.statusCode != 200) {
      throw Exception(
        'Nearby Search HTTP ${searchResponse.statusCode}: '
        '${searchResponse.body.length > 200 ? searchResponse.body.substring(0, 200) : searchResponse.body}',
      );
    }

    final searchData =
        jsonDecode(searchResponse.body) as Map<String, dynamic>;

    // Check API-level error
    final status = searchData['status'] as String?;
    if (status == 'REQUEST_DENIED') {
      throw Exception(
        'REQUEST_DENIED: ${searchData['error_message'] ?? 'Unknown'}',
      );
    }
    if (status != 'OK' && status != 'ZERO_RESULTS') {
      throw Exception('API status: $status');
    }

    final results = searchData['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) return null;

    final firstResult = results[0] as Map<String, dynamic>;
    final photos = firstResult['photos'] as List<dynamic>?;
    if (photos == null || photos.isEmpty) return 'no_photo';

    final photoRef = photos[0]['photo_reference'] as String?;
    if (photoRef == null) return 'no_photo';

    // Construct photo URL directly (this URL works as an image src)
    return 'https://maps.googleapis.com/maps/api/place/photo'
        '?maxwidth=200&photo_reference=$photoRef&key=$apiKey';
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
