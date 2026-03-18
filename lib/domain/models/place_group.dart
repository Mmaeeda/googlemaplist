class PlaceGroup {
  final String placeId;
  final String groupId;
  final String source; // "rule" | "manual" | "ai"
  final double confidence;
  final DateTime createdAt;

  const PlaceGroup({
    required this.placeId,
    required this.groupId,
    required this.source,
    this.confidence = 1.0,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'place_id': placeId,
      'group_id': groupId,
      'source': source,
      'confidence': confidence,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory PlaceGroup.fromMap(Map<String, dynamic> map) {
    return PlaceGroup(
      placeId: map['place_id'] as String,
      groupId: map['group_id'] as String,
      source: map['source'] as String,
      confidence: (map['confidence'] as num).toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  @override
  String toString() =>
      'PlaceGroup(place: $placeId, group: $groupId, source: $source)';
}
