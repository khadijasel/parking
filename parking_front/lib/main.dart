import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/main/main_screen.dart';
import 'theme/app_theme.dart';
import 'features/splash/presentation/screens/splash_screen.dart';
import 'features/parking/presentation/map_home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
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
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData mediaQuery = MediaQuery.of(context);

        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: mediaQuery.textScaler
                .clamp(minScaleFactor: 0.90, maxScaleFactor: 1.15),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
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
        reservationId: 'reservation_12345',
        parkingName: 'Parking Sidi Yahia',
        dureeMinutes: 90,
      ),*/
      //home: const ReservationScreen(),
    );
  }
}
