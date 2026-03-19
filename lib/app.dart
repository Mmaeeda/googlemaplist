import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'presentation/providers/core_providers.dart';
import 'presentation/theme/app_theme.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/shell_screen.dart';

class MapsSavedApp extends ConsumerWidget {
  const MapsSavedApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return MaterialApp(
      title: 'Maps Saved',
      theme: AppTheme.lightTheme,
      home: authState.when(
        data: (isSignedIn) =>
            isSignedIn ? const ShellScreen() : const LoginScreen(),
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (e, st) => const LoginScreen(),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
