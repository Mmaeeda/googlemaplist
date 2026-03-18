class NormalizedPlaceRecord {
  final String? sourceTitle;
  final String? mapsUrl;
  final String? note;
  final String? comments;
  final String? collectionName;
  final String? collectionDescription;
  final String? rawPayloadJson;

  const NormalizedPlaceRecord({
    this.sourceTitle,
    this.mapsUrl,
    this.note,
    this.comments,
    this.collectionName,
    this.collectionDescription,
    this.rawPayloadJson,
  });

  NormalizedPlaceRecord copyWith({
    String? sourceTitle,
    String? mapsUrl,
    String? note,
    String? comments,
    String? collectionName,
    String? collectionDescription,
    String? rawPayloadJson,
  }) {
    return NormalizedPlaceRecord(
      sourceTitle: sourceTitle ?? this.sourceTitle,
      mapsUrl: mapsUrl ?? this.mapsUrl,
      note: note ?? this.note,
      comments: comments ?? this.comments,
      collectionName: collectionName ?? this.collectionName,
      collectionDescription: collectionDescription ?? this.collectionDescription,
      rawPayloadJson: rawPayloadJson ?? this.rawPayloadJson,
    );
  }

  @override
  String toString() =>
      'NormalizedPlaceRecord(title: $sourceTitle, url: $mapsUrl, collection: $collectionName)';
}
