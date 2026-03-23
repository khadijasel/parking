import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTextStyles {
  /// Grand titre (Dashboard, Pages)
  static const title = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: AppColors.textDark,
  );

  /// Sous titre
  static const subtitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textDark,
  );

  /// Texte normal
  static const body = TextStyle(
    fontSize: 16,
    color: AppColors.textDark,
  );

  /// Petit texte
  static const caption = TextStyle(
    fontSize: 14,
    color: Colors.grey,
  );

  /// Texte bouton
  static const button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );
}
