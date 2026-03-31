import 'package:flutter/foundation.dart';

class ApiConstants {
  ApiConstants._();

  static const String _defaultBaseUrlAndroid = 'http://10.0.2.2:8000/api';
  static const String _defaultBaseUrlOthers = 'http://127.0.0.1:8000/api';

  static String get baseUrl {
    const String override = String.fromEnvironment('API_BASE_URL');
    if (override.isNotEmpty) {
      return override;
    }

    if (kIsWeb) {
      return _defaultBaseUrlOthers;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _defaultBaseUrlAndroid;
      default:
        return _defaultBaseUrlOthers;
    }
  }

  static const String userLoginPath = '/user/auth/login';
  static const String userRegisterPath = '/user/auth/register';
  static const String userLogoutPath = '/user/auth/logout';
  static const String userMePath = '/user/auth/me';

  static const String userReservationsPath = '/user/reservations';
  static String userReservationByIdPath(String reservationId) => '/user/reservations/$reservationId';
  static String userReservationGoPath(String reservationId) => '/user/reservations/$reservationId/go';
  static String userReservationScanTicketPath(String reservationId) => '/user/reservations/$reservationId/scan-ticket';
  static const String userPaymentsInitiatePath = '/user/payments/initiate';
  static const String userPaymentsConfirmPath = '/user/payments/confirm';
  static const String userPaymentsHistoryPath = '/user/payments/history';
}
