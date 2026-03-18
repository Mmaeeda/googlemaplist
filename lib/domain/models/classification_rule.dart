class ClassificationRule {
  final String id;
  final String groupId;
  final String pattern;
  final List<String> targetFields; // "title", "note", "comments", "collectionName"
  final bool isRegex;
  final int priority;
  final bool enabled;

  const ClassificationRule({
    required this.id,
    required this.groupId,
    required this.pattern,
    required this.targetFields,
    this.isRegex = false,
    this.priority = 100,
    this.enabled = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'group_id': groupId,
      'pattern': pattern,
      'target_fields': targetFields.join(','),
      'is_regex': isRegex ? 1 : 0,
      'priority': priority,
      'enabled': enabled ? 1 : 0,
    };
  }

  factory ClassificationRule.fromMap(Map<String, dynamic> map) {
    return ClassificationRule(
      id: map['id'] as String,
      groupId: map['group_id'] as String,
      pattern: map['pattern'] as String,
      targetFields: (map['target_fields'] as String).split(','),
      isRegex: (map['is_regex'] as int) == 1,
      priority: map['priority'] as int,
      enabled: (map['enabled'] as int) == 1,
    );
  }

  ClassificationRule copyWith({
    String? id,
    String? groupId,
    String? pattern,
    List<String>? targetFields,
    bool? isRegex,
    int? priority,
    bool? enabled,
  }) {
    return ClassificationRule(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      pattern: pattern ?? this.pattern,
      targetFields: targetFields ?? this.targetFields,
      isRegex: isRegex ?? this.isRegex,
      priority: priority ?? this.priority,
      enabled: enabled ?? this.enabled,
    );
  }

  @override
  String toString() =>
      'ClassificationRule(id: $id, group: $groupId, pattern: $pattern)';
}
