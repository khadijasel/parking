import 'package:flutter/material.dart';
import 'features/main/main_screen.dart';
import 'theme/app_theme.dart';
import 'features/splash/presentation/screens/splash_screen.dart';

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
      home: const SplashScreen(nextRoute: MainScreen()),
      //home: const SplashScreen(nextRoute: MapHomeScreen()),
      //home: const HomeScreen(),
    );
  }
}
