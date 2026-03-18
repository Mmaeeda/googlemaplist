class Group {
  final String id;
  final String name;
  final String iconName;
  final String colorKey;
  final int sortOrder;
  final bool systemGroup;

  const Group({
    required this.id,
    required this.name,
    required this.iconName,
    required this.colorKey,
    required this.sortOrder,
    this.systemGroup = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'icon_name': iconName,
      'color_key': colorKey,
      'sort_order': sortOrder,
      'system_group': systemGroup ? 1 : 0,
    };
  }

  factory Group.fromMap(Map<String, dynamic> map) {
    return Group(
      id: map['id'] as String,
      name: map['name'] as String,
      iconName: map['icon_name'] as String,
      colorKey: map['color_key'] as String,
      sortOrder: map['sort_order'] as int,
      systemGroup: (map['system_group'] as int) == 1,
    );
  }

  Group copyWith({
    String? id,
    String? name,
    String? iconName,
    String? colorKey,
    int? sortOrder,
    bool? systemGroup,
  }) {
    return Group(
      id: id ?? this.id,
      name: name ?? this.name,
      iconName: iconName ?? this.iconName,
      colorKey: colorKey ?? this.colorKey,
      sortOrder: sortOrder ?? this.sortOrder,
      systemGroup: systemGroup ?? this.systemGroup,
    );
  }

  @override
  String toString() => 'Group(id: $id, name: $name)';
}
