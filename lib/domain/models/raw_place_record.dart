class RawPlaceRecord {
  final int rowNumber;
  final Map<String, String> fields;

  const RawPlaceRecord({
    required this.rowNumber,
    required this.fields,
  });

  String? operator [](String key) => fields[key];

  bool hasField(String key) => fields.containsKey(key) && fields[key]!.isNotEmpty;

  @override
  String toString() => 'RawPlaceRecord(row: $rowNumber, fields: $fields)';
}
