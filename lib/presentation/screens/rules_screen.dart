import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../domain/models/classification_rule.dart';
import '../../domain/models/group.dart';
import '../providers/places_providers.dart';
import '../providers/rules_providers.dart';
import '../theme/app_colors.dart';

class RulesScreen extends ConsumerWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(ruleListProvider);
    final groups = ref.watch(groupListProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < 600;

        final headerRow = Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'ルールとグループ',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    fontSize: isMobile ? 24 : null,
                  ),
            ),
            ElevatedButton.icon(
              onPressed: () => _showRuleDialog(context, ref, groups),
              icon: const Icon(Icons.add),
              label: isMobile ? const Text('') : const Text('ルールを追加'),
            ),
          ],
        );

        final groupSection = _GroupSection(groups: groups, isMobile: isMobile);

        // Mobile: scrollable layout
        if (isMobile) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                headerRow,
                const SizedBox(height: 16),
                groupSection,
                const SizedBox(height: 24),
                rules.when(
                  data: (ruleList) => _RuleList(
                    rules: ruleList,
                    groups: groups,
                    shrinkWrap: true,
                  ),
                  loading: () => const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => SizedBox(
                    height: 200,
                    child: Center(
                      child: Text('エラー: $e',
                          style: const TextStyle(color: AppColors.googleRed)),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // Desktop: fixed layout
        return Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              headerRow,
              const SizedBox(height: 32),
              groupSection,
              const SizedBox(height: 32),
              Expanded(
                child: rules.when(
                  data: (ruleList) => _RuleList(
                    rules: ruleList,
                    groups: groups,
                  ),
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Text('エラー: $e',
                        style: const TextStyle(color: AppColors.googleRed)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showRuleDialog(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Group>> groups,
  ) {
    groups.whenData((groupList) {
      if (groupList.isEmpty) return;
      showDialog(
        context: context,
        builder: (ctx) => _RuleFormDialog(groups: groupList),
      ).then((rule) {
        if (rule != null) {
          ref.read(ruleCrudProvider.notifier).addRule(rule);
        }
      });
    });
  }
}

class _RuleList extends ConsumerWidget {
  final List<ClassificationRule> rules;
  final AsyncValue<List<Group>> groups;
  final bool shrinkWrap;

  const _RuleList({required this.rules, required this.groups, this.shrinkWrap = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (rules.isEmpty) {
      return const Card(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'ルールがありません\n「ルールを追加」から分類ルールを作成しましょう',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
      );
    }

    final groupMap = groups.whenOrNull(
          data: (list) => {for (final g in list) g.id: g},
        ) ??
        {};

    return Card(
      child: ListView.separated(
        shrinkWrap: shrinkWrap,
        physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
        itemCount: rules.length,
        separatorBuilder: (context, index) => const Divider(),
        itemBuilder: (context, index) {
          final rule = rules[index];
          final group = groupMap[rule.groupId];
          final groupName = group?.name ?? '(不明)';
          final fieldLabel = rule.targetFields.map(_fieldDisplayName).join(', ');

          return ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            title: Text(
              '${rule.isRegex ? "正規表現" : "キーワード"}「${rule.pattern}」を$fieldLabel内で検索',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              'グループ「$groupName」に割り当て${rule.enabled ? '' : ' (無効)'}',
              style: TextStyle(
                color: rule.enabled
                    ? AppColors.textSecondary
                    : AppColors.googleRed,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: AppColors.textSecondary),
                  onPressed: () => _editRule(context, ref, rule, groupMap),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: AppColors.googleRed),
                  onPressed: () => _confirmDelete(context, ref, rule),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _editRule(
    BuildContext context,
    WidgetRef ref,
    ClassificationRule rule,
    Map<String, Group> groupMap,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => _RuleFormDialog(
        groups: groupMap.values.toList(),
        existingRule: rule,
      ),
    ).then((updated) {
      if (updated != null) {
        ref.read(ruleCrudProvider.notifier).updateRule(updated);
      }
    });
  }

  void _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ClassificationRule rule,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ルールを削除'),
        content: Text('ルール「${rule.pattern}」を削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(ruleCrudProvider.notifier).deleteRule(rule.id);
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.googleRed),
            child: const Text('削除'),
          ),
        ],
      ),
    );
  }

  String _fieldDisplayName(String field) {
    switch (field) {
      case 'title':
      case 'sourcetitle':
      case 'source_title':
        return 'タイトル';
      case 'note':
        return 'メモ';
      case 'comments':
      case 'comment':
        return 'コメント';
      case 'collectionName':
      case 'collection_name':
        return 'コレクション名';
      default:
        return field;
    }
  }
}

class _GroupSection extends ConsumerWidget {
  final AsyncValue<List<Group>> groups;
  final bool isMobile;

  const _GroupSection({required this.groups, required this.isMobile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'グループ',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
            ),
            TextButton.icon(
              onPressed: () => _showGroupDialog(context, ref),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('追加'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        groups.when(
          data: (groupList) {
            if (groupList.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('グループがありません',
                      style: TextStyle(color: AppColors.textSecondary)),
                ),
              );
            }
            return Card(
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: groupList.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final group = groupList[index];
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      _iconFromName(group.iconName),
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                    title: Text(
                      group.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '表示順: ${group.sortOrder}${group.systemGroup ? ' (システム)' : ''}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          color: AppColors.textSecondary,
                          onPressed: () =>
                              _showGroupDialog(context, ref, existing: group),
                        ),
                        if (!group.systemGroup)
                          IconButton(
                            icon: const Icon(Icons.delete, size: 18),
                            color: AppColors.googleRed,
                            onPressed: () =>
                                _confirmDeleteGroup(context, ref, group),
                          ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
          loading: () => const SizedBox(
            height: 60,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('エラー: $e',
              style: const TextStyle(color: AppColors.googleRed)),
        ),
      ],
    );
  }

  void _showGroupDialog(BuildContext context, WidgetRef ref,
      {Group? existing}) {
    showDialog<Group>(
      context: context,
      builder: (ctx) => _GroupFormDialog(existingGroup: existing),
    ).then((group) {
      if (group != null) {
        if (existing != null) {
          ref.read(groupCrudProvider.notifier).updateGroup(group);
        } else {
          ref.read(groupCrudProvider.notifier).addGroup(group);
        }
      }
    });
  }

  void _confirmDeleteGroup(BuildContext context, WidgetRef ref, Group group) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('グループを削除'),
        content: Text('グループ「${group.name}」を削除しますか？\nこのグループに割り当てられた場所のタグも削除されます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(groupCrudProvider.notifier).deleteGroup(group.id);
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.googleRed),
            child: const Text('削除'),
          ),
        ],
      ),
    );
  }

  static IconData _iconFromName(String iconName) {
    return _iconMap[iconName] ?? Icons.label;
  }

  static const _iconMap = <String, IconData>{
    'restaurant': Icons.restaurant,
    'cafe': Icons.coffee,
    'shopping_bag': Icons.shopping_bag,
    'hotel': Icons.hotel,
    'landscape': Icons.landscape,
    'museum': Icons.museum,
    'local_hospital': Icons.local_hospital,
    'school': Icons.school,
    'sports': Icons.sports,
    'church': Icons.church,
    'park': Icons.park,
    'beach': Icons.beach_access,
    'airport': Icons.flight,
    'train': Icons.train,
    'bus': Icons.directions_bus,
    'car': Icons.directions_car,
    'home': Icons.home,
    'work': Icons.work,
    'star': Icons.star,
    'favorite': Icons.favorite,
    'bookmark': Icons.bookmark,
    'label': Icons.label,
    'place': Icons.place,
    'category': Icons.category,
  };
}

class _GroupFormDialog extends StatefulWidget {
  final Group? existingGroup;

  const _GroupFormDialog({this.existingGroup});

  @override
  State<_GroupFormDialog> createState() => _GroupFormDialogState();
}

class _GroupFormDialogState extends State<_GroupFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _sortOrderController;
  late String _selectedIcon;
  late String _selectedColor;

  static const _uuid = Uuid();

  static const _availableIcons = [
    ('restaurant', 'レストラン'),
    ('cafe', 'カフェ'),
    ('shopping_bag', 'ショッピング'),
    ('hotel', 'ホテル'),
    ('landscape', '観光'),
    ('museum', '美術館'),
    ('park', '公園'),
    ('beach', 'ビーチ'),
    ('star', 'お気に入り'),
    ('favorite', 'ハート'),
    ('bookmark', 'ブックマーク'),
    ('label', 'ラベル'),
    ('place', '場所'),
    ('category', 'カテゴリ'),
    ('home', '自宅'),
    ('work', '仕事'),
  ];

  static const _availableColors = [
    ('blue', 'ブルー'),
    ('red', 'レッド'),
    ('green', 'グリーン'),
    ('orange', 'オレンジ'),
    ('purple', 'パープル'),
    ('teal', 'ティール'),
    ('pink', 'ピンク'),
    ('amber', 'アンバー'),
    ('grey', 'グレー'),
  ];

  @override
  void initState() {
    super.initState();
    final group = widget.existingGroup;
    _nameController = TextEditingController(text: group?.name ?? '');
    _sortOrderController =
        TextEditingController(text: (group?.sortOrder ?? 100).toString());
    _selectedIcon = group?.iconName ?? 'label';
    _selectedColor = group?.colorKey ?? 'blue';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sortOrderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingGroup != null;

    return AlertDialog(
      title: Text(isEditing ? 'グループを編集' : 'グループを追加'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'グループ名'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedIcon,
              decoration: const InputDecoration(labelText: 'アイコン'),
              items: _availableIcons
                  .map((e) => DropdownMenuItem(
                        value: e.$1,
                        child: Row(
                          children: [
                            Icon(_GroupSection._iconFromName(e.$1), size: 18),
                            const SizedBox(width: 8),
                            Text(e.$2),
                          ],
                        ),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _selectedIcon = value);
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedColor,
              decoration: const InputDecoration(labelText: '色'),
              items: _availableColors
                  .map((e) => DropdownMenuItem(
                        value: e.$1,
                        child: Text(e.$2),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _selectedColor = value);
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _sortOrderController,
              decoration: const InputDecoration(labelText: '表示順'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        ElevatedButton(
          onPressed: _nameController.text.trim().isEmpty
              ? null
              : () {
                  final sortOrder =
                      int.tryParse(_sortOrderController.text) ?? 100;
                  final group = Group(
                    id: widget.existingGroup?.id ?? _uuid.v4(),
                    name: _nameController.text.trim(),
                    iconName: _selectedIcon,
                    colorKey: _selectedColor,
                    sortOrder: sortOrder,
                    systemGroup: widget.existingGroup?.systemGroup ?? false,
                  );
                  Navigator.of(context).pop(group);
                },
          child: Text(isEditing ? '更新' : '追加'),
        ),
      ],
    );
  }
}

class _RuleFormDialog extends StatefulWidget {
  final List<Group> groups;
  final ClassificationRule? existingRule;

  const _RuleFormDialog({required this.groups, this.existingRule});

  @override
  State<_RuleFormDialog> createState() => _RuleFormDialogState();
}

class _RuleFormDialogState extends State<_RuleFormDialog> {
  late final TextEditingController _patternController;
  late String _selectedGroupId;
  late bool _isRegex;
  late List<String> _selectedFields;

  static const _uuid = Uuid();

  static const _availableFields = [
    ('title', 'タイトル'),
    ('note', 'メモ'),
    ('comments', 'コメント'),
    ('collectionName', 'コレクション名'),
  ];

  @override
  void initState() {
    super.initState();
    final rule = widget.existingRule;
    _patternController = TextEditingController(text: rule?.pattern ?? '');
    _selectedGroupId = rule?.groupId ?? widget.groups.first.id;
    _isRegex = rule?.isRegex ?? false;
    _selectedFields = rule?.targetFields.toList() ?? ['title'];
  }

  @override
  void dispose() {
    _patternController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingRule != null;

    return AlertDialog(
      title: Text(isEditing ? 'ルールを編集' : 'ルールを追加'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _patternController,
              decoration: InputDecoration(
                labelText: 'パターン',
                hintText: _isRegex ? '正規表現パターン' : 'キーワード（|区切りでOR）',
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedGroupId,
              decoration: const InputDecoration(labelText: 'グループ'),
              items: widget.groups
                  .map((g) => DropdownMenuItem(value: g.id, child: Text(g.name)))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _selectedGroupId = value);
              },
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('正規表現'),
              value: _isRegex,
              onChanged: (value) => setState(() => _isRegex = value),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            const Text('検索対象フィールド:',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ..._availableFields.map((field) => CheckboxListTile(
                  title: Text(field.$2),
                  value: _selectedFields.contains(field.$1),
                  onChanged: (checked) {
                    setState(() {
                      if (checked == true) {
                        _selectedFields.add(field.$1);
                      } else {
                        _selectedFields.remove(field.$1);
                      }
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                )),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        ElevatedButton(
          onPressed: _selectedFields.isEmpty || _patternController.text.isEmpty
              ? null
              : () {
                  final rule = ClassificationRule(
                    id: widget.existingRule?.id ?? _uuid.v4(),
                    groupId: _selectedGroupId,
                    pattern: _patternController.text,
                    targetFields: _selectedFields,
                    isRegex: _isRegex,
                    priority: widget.existingRule?.priority ?? 100,
                    enabled: widget.existingRule?.enabled ?? true,
                  );
                  Navigator.of(context).pop(rule);
                },
          child: Text(isEditing ? '更新' : '追加'),
        ),
      ],
    );
  }
}
