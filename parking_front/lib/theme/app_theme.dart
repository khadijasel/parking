import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: Colors.white,
    canvasColor: Colors.white,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.blue,
      surface: Colors.white,
    ),
    cardTheme: CardTheme(
      color: AppColors.card,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
    ),
    textTheme: const TextTheme(
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: AppColors.textDark,
      ),
      bodyMedium: TextStyle(
        fontSize: 16,
        color: AppColors.textDark,
      ),
    ),
  );
}
