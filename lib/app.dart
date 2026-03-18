import 'package:flutter/material.dart';
import 'presentation/theme/app_theme.dart';
import 'presentation/screens/shell_screen.dart';

class MapsSavedApp extends StatelessWidget {
  const MapsSavedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Maps Saved',
      theme: AppTheme.lightTheme,
      home: const ShellScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
