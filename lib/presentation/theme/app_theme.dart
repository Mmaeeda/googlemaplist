import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData get lightTheme {
    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
        surface: AppColors.background,
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.primaryAccent,
        surfaceContainerHigh: AppColors.surface, // Used for sidebar/cards sometimes
      ),
      scaffoldBackgroundColor: AppColors.scaffoldBackground,
    );

    // Apply Montserrat as primary, Space Grotesk for body if desired. 
    // For simplicity, we use Montserrat for most of the UI.
    final primaryTextTheme = GoogleFonts.montserratTextTheme(baseTheme.textTheme).copyWith(
      bodyLarge: GoogleFonts.spaceGrotesk(
        color: AppColors.textPrimary,
        fontSize: 16,
      ),
      bodyMedium: GoogleFonts.spaceGrotesk(
        color: AppColors.textPrimary,
        fontSize: 14,
      ),
      bodySmall: GoogleFonts.spaceGrotesk(
        color: AppColors.textSecondary,
        fontSize: 12,
      ),
      titleLarge: GoogleFonts.montserrat(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
      titleMedium: GoogleFonts.montserrat(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w500,
      ),
      labelLarge: GoogleFonts.montserrat( // Buttons etc
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
    );

    return baseTheme.copyWith(
      textTheme: primaryTextTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: primaryTextTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardBackground,
        elevation: 0, // Flat design
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: primaryTextTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.border, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: primaryTextTheme.labelLarge,
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.hovered) 
                ? AppColors.primaryLight : null,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          textStyle: primaryTextTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.hovered) 
                ? AppColors.primaryLight : null,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.hovered) 
                ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.7)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
