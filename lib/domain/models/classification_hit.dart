class ClassificationHit {
  final String groupId;
  final String source; // "rule" | "ai"
  final double confidence;

  const ClassificationHit({
    required this.groupId,
    required this.source,
    this.confidence = 1.0,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClassificationHit &&
          runtimeType == other.runtimeType &&
          groupId == other.groupId &&
          source == other.source;

  @override
  int get hashCode => groupId.hashCode ^ source.hashCode;

  @override
  String toString() =>
      'ClassificationHit(group: $groupId, source: $source, confidence: $confidence)';
}
