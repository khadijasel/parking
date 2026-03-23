import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../constants/app_constants.dart';

/// Logo et titre de l'application SmartPark
class AppLogo extends StatelessWidget {
  final bool showTagline;

  const AppLogo({
    super.key,
    this.showTagline = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Logo circulaire avec P
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Text(
              'P',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: AppColors.blue,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppConstants.paddingMedium),
        // Nom de l'app
        const Text(
          AppConstants.appName,
          style: AppTextStyles.title,
        ),
        if (showTagline) ...[
          const SizedBox(height: AppConstants.paddingSmall),
          const Text(
            AppConstants.appTagline,
            textAlign: TextAlign.center,
            style: AppTextStyles.caption,
          ),
        ],
      ],
    );
  }
}
