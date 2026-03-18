import '../../domain/models/group.dart';
import '../../domain/models/place.dart';

class PlaceWithGroups {
  final Place place;
  final List<Group> groups;

  const PlaceWithGroups({required this.place, required this.groups});
}
