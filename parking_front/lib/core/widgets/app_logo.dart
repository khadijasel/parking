import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../constants/app_constants.dart';

const Color _kBrandCyan = Color(0xFF2FC7CD);

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
        SizedBox(
          width: 92,
          height: 96,
          child: Image.asset(
            'assets/images/parking.png',
            fit: BoxFit.contain,
            // Recolor only image pixels while preserving black parts as black.
            color: AppColors.blue,
            colorBlendMode: BlendMode.modulate,
            errorBuilder: (_, __, ___) => const _BrandIconMark(),
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

class _BrandIconMark extends StatelessWidget {
  const _BrandIconMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              width: 72,
              height: 78,
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: _kBrandCyan, width: 10),
                  left: BorderSide(color: _kBrandCyan, width: 10),
                  right: BorderSide(color: _kBrandCyan, width: 10),
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(34),
                  topRight: Radius.circular(34),
                ),
              ),
            ),
          ),
          const Positioned(
            top: 30,
            child: Text(
              'P',
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w800,
                color: _kBrandCyan,
                height: 1,
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: 70,
              height: 2,
              color: _kBrandCyan,
            ),
          ),
        ],
      ),
    );
  }
}
