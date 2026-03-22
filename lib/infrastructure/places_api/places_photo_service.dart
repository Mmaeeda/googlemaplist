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

/// Resolves place photos via Google Places API (New).
///
/// Uses the Nearby Search (New) API to find a place by coordinates,
/// then fetches a direct photo URL via the Place Photos (New) API.
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
          firstError = 'APIキーが無効、またはPlaces API (New)が未有効化です';
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
    // Nearby Search (New): POST with JSON body
    final searchResponse = await _httpClient.post(
      Uri.parse('https://places.googleapis.com/v1/places:searchNearby'),
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask': 'places.photos',
      },
      body: jsonEncode({
        'locationRestriction': {
          'circle': {
            'center': {'latitude': lat, 'longitude': lng},
            'radius': 50.0,
          },
        },
        'maxResultCount': 1,
      }),
    );

    if (searchResponse.statusCode == 403 ||
        searchResponse.statusCode == 401) {
      throw Exception('REQUEST_DENIED');
    }

    if (searchResponse.statusCode != 200) {
      throw Exception(
        'Nearby Search HTTP ${searchResponse.statusCode}: '
        '${searchResponse.body.length > 200 ? searchResponse.body.substring(0, 200) : searchResponse.body}',
      );
    }

    final searchData =
        jsonDecode(searchResponse.body) as Map<String, dynamic>;

    final places = searchData['places'] as List<dynamic>?;
    if (places == null || places.isEmpty) return null;

    final firstPlace = places[0] as Map<String, dynamic>;
    final photos = firstPlace['photos'] as List<dynamic>?;
    if (photos == null || photos.isEmpty) return 'no_photo';

    final photoName = photos[0]['name'] as String?;
    if (photoName == null) return 'no_photo';

    // Place Photos (New): get direct CDN URL via skipHttpRedirect
    final photoResponse = await _httpClient.get(
      Uri.parse(
        'https://places.googleapis.com/v1/$photoName/media'
        '?maxWidthPx=200&skipHttpRedirect=true',
      ),
      headers: {'X-Goog-Api-Key': apiKey},
    );

    if (photoResponse.statusCode != 200) return 'no_photo';

    final photoData =
        jsonDecode(photoResponse.body) as Map<String, dynamic>;
    return photoData['photoUri'] as String?;
  }

  /// Extract (lat, lng) from rawPayloadJson or mapsUrl.
  ///
  /// Supports multiple Google Maps URL formats:
  ///   - GeoJSON geometry.coordinates (from 保存した場所.json)
  ///   - ?q=lat,lng
  ///   - @lat,lng,zoom (common in Google Maps URLs)
  ///   - !3dlat!4dlng (in data= parameter)
  ///   - ll=lat,lng (query parameter)
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
      final url = place.mapsUrl!;

      // Pattern 1: ?q=lat,lng or &q=lat,lng
      final qMatch =
          RegExp(r'[?&]q=([-\d.]+),([-\d.]+)').firstMatch(url);
      if (qMatch != null) {
        final parsed = _tryParseCoords(qMatch.group(1)!, qMatch.group(2)!);
        if (parsed != null) return parsed;
      }

      // Pattern 2: @lat,lng (e.g. /place/Name/@35.658,139.745,17z/)
      final atMatch =
          RegExp(r'@([-\d.]+),([-\d.]+)').firstMatch(url);
      if (atMatch != null) {
        final parsed = _tryParseCoords(atMatch.group(1)!, atMatch.group(2)!);
        if (parsed != null) return parsed;
      }

      // Pattern 3: !3dlat!4dlng (in data= parameter)
      final dataMatch =
          RegExp(r'!3d([-\d.]+)!4d([-\d.]+)').firstMatch(url);
      if (dataMatch != null) {
        final parsed =
            _tryParseCoords(dataMatch.group(1)!, dataMatch.group(2)!);
        if (parsed != null) return parsed;
      }

      // Pattern 4: ll=lat,lng
      final llMatch =
          RegExp(r'[?&]ll=([-\d.]+),([-\d.]+)').firstMatch(url);
      if (llMatch != null) {
        final parsed =
            _tryParseCoords(llMatch.group(1)!, llMatch.group(2)!);
        if (parsed != null) return parsed;
      }
    }

    return null;
  }

  /// Try to parse lat/lng strings, returning null on failure.
  static (double, double)? _tryParseCoords(String latStr, String lngStr) {
    try {
      final lat = double.parse(latStr);
      final lng = double.parse(lngStr);
      // Basic validation: lat -90..90, lng -180..180
      if (lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
        return (lat, lng);
      }
    } catch (_) {}
    return null;
  }

  void dispose() {
    _httpClient.close();
  }
}
