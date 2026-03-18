import '../models/classification_rule.dart';

abstract class ClassificationRuleRepository {
  Future<List<ClassificationRule>> listAll();
  Future<List<ClassificationRule>> listEnabled();
  Future<void> insert(ClassificationRule rule);
  Future<void> update(ClassificationRule rule);
  Future<void> delete(String ruleId);
}
