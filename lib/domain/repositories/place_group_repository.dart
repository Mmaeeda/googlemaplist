import '../models/place_group.dart';

abstract class PlaceGroupRepository {
  Future<void> replaceAutoGroups(String placeId, List<PlaceGroup> groups);
  Future<List<PlaceGroup>> listByPlaceId(String placeId);
  Future<void> insertManualGroup(PlaceGroup placeGroup);
}
