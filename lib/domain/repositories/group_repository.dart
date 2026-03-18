import '../models/group.dart';

abstract class GroupRepository {
  Future<List<Group>> listAll();
  Future<Group?> findById(String id);
  Future<Group?> findByName(String name);
  Future<void> upsert(Group group);
  Future<void> delete(String groupId);
}
