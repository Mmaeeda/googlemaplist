class Place {
  final String id;
  final String sourceKey;
  final String? sourceTitle;
  final String? mapsUrl;
  final String? note;
  final String? comments;
  final String? collectionName;
  final String? collectionDescription;
  final String? rawPayloadJson;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime lastSeenAt;
  final bool isHidden;
  final bool isDeletedCandidate;
  final int deletedMissCount;
  final bool manualGroupOverride;

  const Place({
    required this.id,
    required this.sourceKey,
    this.sourceTitle,
    this.mapsUrl,
    this.note,
    this.comments,
    this.collectionName,
    this.collectionDescription,
    this.rawPayloadJson,
    required this.createdAt,
    required this.updatedAt,
    required this.lastSeenAt,
    this.isHidden = false,
    this.isDeletedCandidate = false,
    this.deletedMissCount = 0,
    this.manualGroupOverride = false,
  });

  Place copyWith({
    String? id,
    String? sourceKey,
    String? sourceTitle,
    String? mapsUrl,
    String? note,
    String? comments,
    String? collectionName,
    String? collectionDescription,
    String? rawPayloadJson,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastSeenAt,
    bool? isHidden,
    bool? isDeletedCandidate,
    int? deletedMissCount,
    bool? manualGroupOverride,
  }) {
    return Place(
      id: id ?? this.id,
      sourceKey: sourceKey ?? this.sourceKey,
      sourceTitle: sourceTitle ?? this.sourceTitle,
      mapsUrl: mapsUrl ?? this.mapsUrl,
      note: note ?? this.note,
      comments: comments ?? this.comments,
      collectionName: collectionName ?? this.collectionName,
      collectionDescription: collectionDescription ?? this.collectionDescription,
      rawPayloadJson: rawPayloadJson ?? this.rawPayloadJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      isHidden: isHidden ?? this.isHidden,
      isDeletedCandidate: isDeletedCandidate ?? this.isDeletedCandidate,
      deletedMissCount: deletedMissCount ?? this.deletedMissCount,
      manualGroupOverride: manualGroupOverride ?? this.manualGroupOverride,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'source_key': sourceKey,
      'source_title': sourceTitle,
      'maps_url': mapsUrl,
      'note': note,
      'comments': comments,
      'collection_name': collectionName,
      'collection_description': collectionDescription,
      'raw_payload_json': rawPayloadJson,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'last_seen_at': lastSeenAt.toIso8601String(),
      'is_hidden': isHidden ? 1 : 0,
      'is_deleted_candidate': isDeletedCandidate ? 1 : 0,
      'deleted_miss_count': deletedMissCount,
      'manual_group_override': manualGroupOverride ? 1 : 0,
    };
  }

  factory Place.fromMap(Map<String, dynamic> map) {
    return Place(
      id: map['id'] as String,
      sourceKey: map['source_key'] as String,
      sourceTitle: map['source_title'] as String?,
      mapsUrl: map['maps_url'] as String?,
      note: map['note'] as String?,
      comments: map['comments'] as String?,
      collectionName: map['collection_name'] as String?,
      collectionDescription: map['collection_description'] as String?,
      rawPayloadJson: map['raw_payload_json'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      lastSeenAt: DateTime.parse(map['last_seen_at'] as String),
      isHidden: (map['is_hidden'] as int) == 1,
      isDeletedCandidate: (map['is_deleted_candidate'] as int) == 1,
      deletedMissCount: map['deleted_miss_count'] as int,
      manualGroupOverride: (map['manual_group_override'] as int) == 1,
    );
  }

  @override
  String toString() => 'Place(id: $id, title: $sourceTitle, key: $sourceKey)';
}
