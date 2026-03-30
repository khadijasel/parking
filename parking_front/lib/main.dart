import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/main/main_screen.dart';
import 'theme/app_theme.dart';
import 'features/splash/presentation/screens/splash_screen.dart';
import 'features/parking/presentation/map_home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
      home: FutureBuilder<bool>(
        future: AuthRepository().hasActiveSession(),
        builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          final bool isAuthenticated = snapshot.data ?? false;
          return SplashScreen(
            nextRoute: isAuthenticated
                ? const MainScreen(isAuthenticated: true)
                : const MapHomeScreen(),
          );
        },
      ),
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
