import 'package:flutter/material.dart';
import 'features/parking/presentation/map_home_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const SmartParkApp());
}

class SmartParkApp extends StatelessWidget {
  const SmartParkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'smartpark',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const MapHomeScreen(),
    );
  }
}
