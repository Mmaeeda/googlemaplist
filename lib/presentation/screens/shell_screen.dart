import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/app_colors.dart';
import 'dashboard_screen.dart';
import 'places_screen.dart';
import 'rules_screen.dart';
import 'settings_screen.dart';

class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({super.key});

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    DashboardScreen(),
    PlacesScreen(),
    RulesScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < 800;

        return Scaffold(
          appBar: isMobile
              ? AppBar(
                  title: const Text(
                    'マップ保存管理',
                    style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
                  ),
                )
              : null,
          body: Row(
            children: [
              // Sidebar for Desktop/Tablet
              if (!isMobile)
                Container(
                  width: 240,
                  color: AppColors.surface,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(24, 48, 24, 32),
                        child: Text(
                          'マップ保存管理',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      _SidebarItem(
                        icon: LucideIcons.layoutDashboard,
                        label: 'ダッシュボード',
                        isSelected: _selectedIndex == 0,
                        onTap: () => setState(() => _selectedIndex = 0),
                      ),
                      _SidebarItem(
                        icon: LucideIcons.mapPin,
                        label: '場所リスト',
                        isSelected: _selectedIndex == 1,
                        onTap: () => setState(() => _selectedIndex = 1),
                      ),
                      _SidebarItem(
                        icon: LucideIcons.tags,
                        label: 'ルールとグループ',
                        isSelected: _selectedIndex == 2,
                        onTap: () => setState(() => _selectedIndex = 2),
                      ),
                      _SidebarItem(
                        icon: LucideIcons.settings,
                        label: '設定',
                        isSelected: _selectedIndex == 3,
                        onTap: () => setState(() => _selectedIndex = 3),
                      ),
                    ],
                  ),
                ),
              if (!isMobile) const VerticalDivider(width: 1),
              // Main Content
              Expanded(
                child: Container(
                  color: AppColors.background,
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: _screens,
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: isMobile
              ? BottomNavigationBar(
                  type: BottomNavigationBarType.fixed,
                  currentIndex: _selectedIndex,
                  onTap: (index) => setState(() => _selectedIndex = index),
                  selectedItemColor: AppColors.primary,
                  unselectedItemColor: AppColors.textSecondary,
                  backgroundColor: AppColors.surface,
                  items: const [
                    BottomNavigationBarItem(
                      icon: Icon(LucideIcons.layoutDashboard),
                      label: 'ダッシュボード',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(LucideIcons.mapPin),
                      label: '場所',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(LucideIcons.tags),
                      label: 'ルール',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(LucideIcons.settings),
                      label: '設定',
                    ),
                  ],
                )
              : null,
        );
      },
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: AppColors.primaryLight.withValues(alpha: 0.5),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primaryLight : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected ? AppColors.primary : AppColors.textSecondary,
                ),
                const SizedBox(width: 16),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
