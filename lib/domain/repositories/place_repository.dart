import '../models/place.dart';

abstract class PlaceRepository {
  Future<Place?> findById(String id);
  Future<Place?> findBySourceKey(String sourceKey);
  Future<void> insert(Place place);
  Future<void> update(Place place);
  Future<void> markMissing(String placeId);
  Future<List<Place>> listMissingCandidates();
  Future<List<Place>> listAllActive();
  Future<List<Place>> listAll();
}
