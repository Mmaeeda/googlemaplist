import '../models/place_group.dart';

abstract class PlaceGroupRepository {
  Future<void> replaceAutoGroups(String placeId, List<PlaceGroup> groups);
  Future<void> replaceAllGroups(String placeId, List<PlaceGroup> groups);
  Future<List<PlaceGroup>> listByPlaceId(String placeId);
  Future<List<PlaceGroup>> listAll();
  Future<void> insertManualGroup(PlaceGroup placeGroup);
}
