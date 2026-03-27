import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parking_front/features/profile/presentation/screens/my_reservations_screen.dart';
import 'package:parking_front/features/reservation/presentation/screens/reservation_screen.dart';
import 'package:parking_front/features/scanner/presentation/screens/scanner_screen.dart';
import 'features/main/main_screen.dart';
import 'theme/app_theme.dart';
import 'features/splash/presentation/screens/splash_screen.dart';
import 'features/parking/presentation/map_home_screen.dart';
import 'features/payment/presentation/screens/payment_screen.dart';

void main() {
  runApp(const ProviderScope(child: SmartParkApp()));
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
     /* home: const PaymentScreen(
        sessionId: 'test_session',
        userId: 'test_user',
        parkingName: 'Parking Sidi Yahia',
        dureeMinutes: 90,
      ),*/
      //home: const ReservationScreen(),
      
    );
  }
}
