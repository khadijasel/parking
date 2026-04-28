import 'package:flutter/foundation.dart';

class ApiConstants {
  ApiConstants._();

  static const String _defaultBaseUrlAndroid = 'http://10.0.2.2:8000/api';
  static const String _defaultBaseUrlOthers = 'http://127.0.0.1:8000/api';

  static String get baseUrl {
    const String override = String.fromEnvironment('API_BASE_URL');
    if (override.trim().isNotEmpty) {
      return _sanitizeBaseUrl(override);
    }

    if (kIsWeb) {
      return _sanitizeBaseUrl(_defaultBaseUrlOthers);
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _sanitizeBaseUrl(_defaultBaseUrlAndroid);
      default:
        return _sanitizeBaseUrl(_defaultBaseUrlOthers);
    }
  }

  static String _sanitizeBaseUrl(String rawBaseUrl) {
    final String trimmed = rawBaseUrl.trim();
    final Uri? parsed = Uri.tryParse(trimmed);

    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      return _defaultBaseUrlOthers;
    }

    final List<String> segments = parsed.pathSegments
        .where((String segment) => segment.isNotEmpty)
        .toList();
    final bool hasApiSegment =
        segments.any((String segment) => segment.toLowerCase() == 'api');

    if (!hasApiSegment) {
      segments.add('api');
    }

    return parsed
        .replace(
          pathSegments: segments,
          query: null,
          fragment: null,
        )
        .toString();
  }

  static const String userLoginPath = '/user/auth/login';
  static const String userGoogleAuthPath = '/user/auth/google';
  static const String userRegisterPath = '/user/auth/register';
  static const String userLogoutPath = '/user/auth/logout';
  static const String userMePath = '/user/auth/me';
  static const String userProfileUpdatePath = '/user/auth/profile';

  static const String publicParkingAvailabilityPath = '/parkings/availability';

  static const String userReservationsPath = '/user/reservations';
  static String userReservationByIdPath(String reservationId) =>
      '/user/reservations/$reservationId';
  static String userReservationGoPath(String reservationId) =>
      '/user/reservations/$reservationId/go';
  static String userReservationScanTicketPath(String reservationId) =>
      '/user/reservations/$reservationId/scan-ticket';
  static const String userParkingSessionCurrentPath =
      '/user/parking-sessions/current';
  static const String userParkingSessionExitPath =
      '/user/parking-sessions/exit';
  static const String userParkingSessionHistoryPath =
      '/user/parking-sessions/history';
  static const String userPaymentsInitiatePath = '/user/payments/initiate';
  static const String userPaymentsConfirmPath = '/user/payments/confirm';
  static const String userPaymentsHistoryPath = '/user/payments/history';
}
