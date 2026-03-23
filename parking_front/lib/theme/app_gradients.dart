import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppGradients {
  /// Gradient principal SmartPark
  static const LinearGradient primary = LinearGradient(
    colors: [
      AppColors.blue,
      AppColors.green,
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
