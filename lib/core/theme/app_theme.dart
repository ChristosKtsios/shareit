import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      primary:   AppColors.primary,
      surface:   AppColors.surface,
      error:     AppColors.danger,
      onPrimary: Color(0xFF0D0F14),
      onSurface: AppColors.textPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor:  AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: TextStyle(
          color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w600),
      iconTheme: IconThemeData(color: AppColors.textPrimary),
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: AppColors.border, width: 0.5),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceVariant,
      hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border, width: 0.5)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border, width: 0.5)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.danger, width: 1)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.background,
        elevation: 0,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primary)),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 0.5),
    textTheme: const TextTheme(
      headlineMedium: TextStyle(color: AppColors.textPrimary,   fontSize: 24, fontWeight: FontWeight.w700),
      titleLarge:     TextStyle(color: AppColors.textPrimary,   fontSize: 18, fontWeight: FontWeight.w600),
      titleMedium:    TextStyle(color: AppColors.textPrimary,   fontSize: 15, fontWeight: FontWeight.w500),
      bodyLarge:      TextStyle(color: AppColors.textPrimary,   fontSize: 15),
      bodyMedium:     TextStyle(color: AppColors.textSecondary, fontSize: 13),
      labelSmall:     TextStyle(color: AppColors.textHint,      fontSize: 11),
    ),
  );
}
