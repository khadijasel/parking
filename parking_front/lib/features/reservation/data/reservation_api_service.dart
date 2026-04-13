import 'package:dio/dio.dart';

import '../../../core/constants/api_constants.dart';

class ReservationApiException implements Exception {
  final String message;
  final int? statusCode;

  const ReservationApiException(this.message, {this.statusCode});

  @override
  String toString() =>
      'ReservationApiException(statusCode: $statusCode, message: $message)';
}

class ReservationApiService {
  final Dio _dio;

  ReservationApiService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: ApiConstants.baseUrl,
                headers: const <String, String>{
                  'Accept': 'application/json',
                  'Content-Type': 'application/json',
                },
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(seconds: 30),
              ),
            );

  Future<Map<String, dynamic>> createReservation({
    required String token,
    required String parkingId,
    required String parkingName,
    required String parkingAddress,
    required List<String> equipments,
    required String durationType,
    required int durationMinutes,
    required double amount,
    required double depositAmount,
  }) async {
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        ApiConstants.userReservationsPath,
        data: <String, dynamic>{
          'parking_id': parkingId,
          'parking_name': parkingName,
          'parking_address': parkingAddress,
          'equipments': equipments,
          'duration_type': durationType,
          'duration_minutes': durationMinutes,
          'amount': amount,
          'deposit_amount': depositAmount,
        },
        options: Options(
          headers: <String, String>{
            'Authorization': 'Bearer $token',
          },
          validateStatus: (int? status) => status != null && status < 500,
        ),
      );

      final int statusCode = response.statusCode ?? 0;
      final Map<String, dynamic> payload = _normalizePayload(response.data);

      if (statusCode != 201) {
        throw ReservationApiException(
          _extractMessage(payload),
          statusCode: statusCode,
        );
      }

      final Object? data = payload['data'];
      if (data is! Map<String, dynamic>) {
        throw const ReservationApiException(
            'Format de reponse inattendu du serveur.');
      }

      final Object? reservation = data['reservation'];
      if (reservation is! Map<String, dynamic>) {
        throw const ReservationApiException(
            'Reservation invalide recue depuis le serveur.');
      }

      return reservation;
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Future<List<Map<String, dynamic>>> fetchReservations({
    required String token,
  }) async {
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        ApiConstants.userReservationsPath,
        options: Options(
          headers: <String, String>{
            'Authorization': 'Bearer $token',
          },
          validateStatus: (int? status) => status != null && status < 500,
        ),
      );

      final int statusCode = response.statusCode ?? 0;
      final Map<String, dynamic> payload = _normalizePayload(response.data);

      if (statusCode != 200) {
        throw ReservationApiException(
          _extractMessage(payload),
          statusCode: statusCode,
        );
      }

      final Object? data = payload['data'];
      if (data is! List) {
        return const <Map<String, dynamic>>[];
      }

      return data.whereType<Map>().map((Map<dynamic, dynamic> item) {
        return item.map<String, dynamic>(
          (dynamic key, dynamic value) => MapEntry<String, dynamic>(
            key.toString(),
            value,
          ),
        );
      }).toList(growable: false);
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Future<void> cancelReservation({
    required String token,
    required String reservationId,
  }) async {
    try {
      final Response<dynamic> response = await _dio.delete<dynamic>(
        ApiConstants.userReservationByIdPath(reservationId),
        options: Options(
          headers: <String, String>{
            'Authorization': 'Bearer $token',
          },
          validateStatus: (int? status) => status != null && status < 500,
        ),
      );

      final int statusCode = response.statusCode ?? 0;
      final Map<String, dynamic> payload = _normalizePayload(response.data);

      if (statusCode != 200) {
        throw ReservationApiException(
          _extractMessage(payload),
          statusCode: statusCode,
        );
      }
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Future<Map<String, dynamic>> markReservationEnRoute({
    required String token,
    required String reservationId,
  }) async {
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        ApiConstants.userReservationGoPath(reservationId),
        options: Options(
          headers: <String, String>{
            'Authorization': 'Bearer $token',
          },
          validateStatus: (int? status) => status != null && status < 500,
        ),
      );

      final int statusCode = response.statusCode ?? 0;
      final Map<String, dynamic> payload = _normalizePayload(response.data);

      if (statusCode != 200) {
        throw ReservationApiException(
          _extractMessage(payload),
          statusCode: statusCode,
        );
      }

      final Object? data = payload['data'];
      if (data is! Map<String, dynamic>) {
        throw const ReservationApiException(
            'Reservation invalide recue depuis le serveur.');
      }

      return data;
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Future<Map<String, dynamic>> completeReservationByTicket({
    required String token,
    required String reservationId,
  }) async {
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        ApiConstants.userReservationScanTicketPath(reservationId),
        options: Options(
          headers: <String, String>{
            'Authorization': 'Bearer $token',
          },
          validateStatus: (int? status) => status != null && status < 500,
        ),
      );

      final int statusCode = response.statusCode ?? 0;
      final Map<String, dynamic> payload = _normalizePayload(response.data);

      if (statusCode != 200) {
        throw ReservationApiException(
          _extractMessage(payload),
          statusCode: statusCode,
        );
      }

      final Object? data = payload['data'];
      if (data is! Map<String, dynamic>) {
        throw const ReservationApiException(
            'Reservation invalide recue depuis le serveur.');
      }

      return data;
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Future<Map<String, dynamic>?> fetchCurrentParkingSession({
    required String token,
  }) async {
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        ApiConstants.userParkingSessionCurrentPath,
        options: Options(
          headers: <String, String>{
            'Authorization': 'Bearer $token',
          },
          validateStatus: (int? status) => status != null && status < 500,
        ),
      );

      final int statusCode = response.statusCode ?? 0;
      final Map<String, dynamic> payload = _normalizePayload(response.data);

      if (statusCode != 200) {
        throw ReservationApiException(
          _extractMessage(payload),
          statusCode: statusCode,
        );
      }

      final Object? data = payload['data'];
      if (data == null) {
        return null;
      }

      if (data is! Map<String, dynamic>) {
        throw const ReservationApiException(
            'Session parking invalide recue depuis le serveur.');
      }

      return data;
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Future<Map<String, dynamic>> exitCurrentParkingSession({
    required String token,
  }) async {
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        ApiConstants.userParkingSessionExitPath,
        options: Options(
          headers: <String, String>{
            'Authorization': 'Bearer $token',
          },
          validateStatus: (int? status) => status != null && status < 500,
        ),
      );

      final int statusCode = response.statusCode ?? 0;
      final Map<String, dynamic> payload = _normalizePayload(response.data);

      if (statusCode != 200) {
        throw ReservationApiException(
          _extractMessage(payload),
          statusCode: statusCode,
        );
      }

      final Object? data = payload['data'];
      if (data is! Map<String, dynamic>) {
        throw const ReservationApiException(
            'Session parking invalide recue depuis le serveur.');
      }

      return data;
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Future<List<Map<String, dynamic>>> fetchParkingSessionHistory({
    required String token,
  }) async {
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        ApiConstants.userParkingSessionHistoryPath,
        options: Options(
          headers: <String, String>{
            'Authorization': 'Bearer $token',
          },
          validateStatus: (int? status) => status != null && status < 500,
        ),
      );

      final int statusCode = response.statusCode ?? 0;
      final Map<String, dynamic> payload = _normalizePayload(response.data);

      if (statusCode != 200) {
        throw ReservationApiException(
          _extractMessage(payload),
          statusCode: statusCode,
        );
      }

      final Object? data = payload['data'];
      if (data is! List) {
        return const <Map<String, dynamic>>[];
      }

      return data.whereType<Map>().map((Map<dynamic, dynamic> item) {
        return item.map<String, dynamic>(
          (dynamic key, dynamic value) => MapEntry<String, dynamic>(
            key.toString(),
            value,
          ),
        );
      }).toList(growable: false);
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  ReservationApiException _mapDioException(DioException error) {
    final int? statusCode = error.response?.statusCode;
    final Map<String, dynamic> payload =
        _normalizePayload(error.response?.data);

    if (statusCode != null) {
      return ReservationApiException(
        _extractMessage(payload),
        statusCode: statusCode,
      );
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const ReservationApiException(
            'Delai depasse. Verifiez votre connexion puis reessayez.');
      case DioExceptionType.connectionError:
        return const ReservationApiException(
            'Impossible de contacter le serveur.');
      case DioExceptionType.cancel:
        return const ReservationApiException('Requete annulee.');
      case DioExceptionType.badCertificate:
        return const ReservationApiException('Certificat serveur invalide.');
      case DioExceptionType.unknown:
      case DioExceptionType.badResponse:
        return const ReservationApiException(
            'Une erreur est survenue, veuillez reessayer.');
    }
  }

  Map<String, dynamic> _normalizePayload(Object? data) {
    if (data == null) {
      return <String, dynamic>{};
    }

    if (data is Map<String, dynamic>) {
      return data;
    }

    if (data is Map) {
      return data.map<String, dynamic>(
        (Object? key, Object? value) => MapEntry<String, dynamic>(
          key.toString(),
          value,
        ),
      );
    }

    return <String, dynamic>{};
  }

  String _extractMessage(Map<String, dynamic> payload) {
    final Object? message = payload['message'];
    if (message is String && message.trim().isNotEmpty) {
      return message;
    }

    final Object? errors = payload['errors'];
    if (errors is Map<String, dynamic>) {
      for (final Object value in errors.values) {
        if (value is List && value.isNotEmpty && value.first is String) {
          return value.first as String;
        }
      }
    }

    return 'Une erreur est survenue, veuillez reessayer.';
  }
}
