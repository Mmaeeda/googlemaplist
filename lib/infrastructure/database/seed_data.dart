import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class SeedData {
  static const _uuid = Uuid();

  static Future<void> seed(Database db) async {
    await _seedGroups(db);
    await _seedRules(db);
  }

  static Future<void> _seedGroups(Database db) async {
    final groups = [
      _group('春', 'flower', 'pink', 1),
      _group('夏', 'sunny', 'orange', 2),
      _group('秋', 'leaf', 'red', 3),
      _group('冬', 'snow', 'blue', 4),
      _group('桜スポット', 'cherry_blossom', 'pink_light', 5),
      _group('飲食店', 'restaurant', 'amber', 6),
      _group('星景', 'star', 'indigo', 7),
      _group('家族向け', 'family', 'green', 8),
      _group('未分類', 'help_outline', 'grey', 99, systemGroup: true),
    ];

    for (final group in groups) {
      await db.insert('groups', group);
    }
  }

  static Future<void> _seedRules(Database db) async {
    // First, get group IDs by name
    final groupRows = await db.query('groups');
    final groupIdByName = <String, String>{};
    for (final row in groupRows) {
      groupIdByName[row['name'] as String] = row['id'] as String;
    }

    final rules = [
      _rule(groupIdByName['春']!, r'桜|花見|さくら|菜の花|春',
          'title,note,comments,collectionName', 10),
      _rule(groupIdByName['桜スポット']!, r'桜|花見|さくら',
          'title,note,comments', 10),
      _rule(groupIdByName['飲食店']!, r'飲食店|ランチ|ディナー|カフェ|喫茶|レストラン',
          'title,note,comments,collectionName', 20),
      _rule(groupIdByName['星景']!, r'星|星空|天の川|夜景',
          'title,note,comments', 20),
      _rule(groupIdByName['秋']!, r'紅葉|もみじ|いちょう|秋',
          'title,note,comments', 20),
      _rule(groupIdByName['夏']!, r'海|花火|ひまわり|川|夏',
          'title,note,comments', 20),
      _rule(groupIdByName['冬']!, r'雪|イルミ|クリスマス|温泉|冬',
          'title,note,comments', 20),
      _rule(groupIdByName['家族向け']!, r'公園|遊園地|動物園|水族館|キッズ|子供|家族',
          'title,note,comments,collectionName', 30),
    ];

    for (final rule in rules) {
      await db.insert('classification_rules', rule);
    }
  }

  static Map<String, dynamic> _group(
    String name,
    String iconName,
    String colorKey,
    int sortOrder, {
    bool systemGroup = false,
  }) {
    return {
      'id': _uuid.v4(),
      'name': name,
      'icon_name': iconName,
      'color_key': colorKey,
      'sort_order': sortOrder,
      'system_group': systemGroup ? 1 : 0,
    };
  }

  static Map<String, dynamic> _rule(
    String groupId,
    String pattern,
    String targetFields,
    int priority,
  ) {
    return {
      'id': _uuid.v4(),
      'group_id': groupId,
      'pattern': pattern,
      'target_fields': targetFields,
      'is_regex': 0,
      'priority': priority,
      'enabled': 1,
    };
  }
}
