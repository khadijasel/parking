import 'package:dio/dio.dart';

import '../../../core/constants/api_constants.dart';

class PaymentApiException implements Exception {
  final String message;
  final int? statusCode;

  const PaymentApiException(this.message, {this.statusCode});

  @override
  String toString() => 'PaymentApiException(statusCode: $statusCode, message: $message)';
}

class PaymentApiService {
  final Dio _dio;

  PaymentApiService({Dio? dio})
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

  Future<Map<String, dynamic>> initiate({
    required String token,
    required String reservationId,
    required String method,
  }) async {
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        ApiConstants.userPaymentsInitiatePath,
        data: <String, dynamic>{
          'reservation_id': reservationId,
          'method': method,
        },
        options: _authorizedOptions(token),
      );

      final int statusCode = response.statusCode ?? 0;
      final Map<String, dynamic> payload = _normalizePayload(response.data);

      if (statusCode != 201) {
        throw PaymentApiException(_extractMessage(payload), statusCode: statusCode);
      }

      final Object? data = payload['data'];
      if (data is! Map<String, dynamic>) {
        throw const PaymentApiException('Format de reponse inattendu du serveur.');
      }

      final Object? transaction = data['transaction'];
      if (transaction is! Map<String, dynamic>) {
        throw const PaymentApiException('Transaction invalide recue depuis le serveur.');
      }

      return transaction;
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Future<Map<String, dynamic>> confirm({
    required String token,
    required String transactionId,
    required String method,
    required String? pin,
  }) async {
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        ApiConstants.userPaymentsConfirmPath,
        data: <String, dynamic>{
          'transaction_id': transactionId,
          'method': method,
          'pin': pin,
        },
        options: _authorizedOptions(token),
      );

      final int statusCode = response.statusCode ?? 0;
      final Map<String, dynamic> payload = _normalizePayload(response.data);

      if (statusCode != 200 && statusCode != 422) {
        throw PaymentApiException(_extractMessage(payload), statusCode: statusCode);
      }

      final Object? data = payload['data'];
      if (data is! Map<String, dynamic>) {
        throw const PaymentApiException('Format de reponse inattendu du serveur.');
      }

      return data;
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Future<List<Map<String, dynamic>>> history({
    required String token,
  }) async {
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        ApiConstants.userPaymentsHistoryPath,
        options: _authorizedOptions(token),
      );

      final int statusCode = response.statusCode ?? 0;
      final Map<String, dynamic> payload = _normalizePayload(response.data);

      if (statusCode != 200) {
        throw PaymentApiException(_extractMessage(payload), statusCode: statusCode);
      }

      final Object? data = payload['data'];
      if (data is! List) {
        return const <Map<String, dynamic>>[];
      }

      return data.whereType<Map>().map((Map<dynamic, dynamic> item) {
        return item.map<String, dynamic>(
          (dynamic key, dynamic value) => MapEntry<String, dynamic>(key.toString(), value),
        );
      }).toList(growable: false);
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Options _authorizedOptions(String token) {
    return Options(
      headers: <String, String>{
        'Authorization': 'Bearer $token',
      },
      validateStatus: (int? status) => status != null && status < 500,
    );
  }

  PaymentApiException _mapDioException(DioException error) {
    final int? statusCode = error.response?.statusCode;
    final Map<String, dynamic> payload = _normalizePayload(error.response?.data);

    if (statusCode != null) {
      return PaymentApiException(
        _extractMessage(payload),
        statusCode: statusCode,
      );
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const PaymentApiException('Delai depasse. Verifiez votre connexion puis reessayez.');
      case DioExceptionType.connectionError:
        return const PaymentApiException('Impossible de contacter le serveur.');
      case DioExceptionType.cancel:
        return const PaymentApiException('Requete annulee.');
      case DioExceptionType.badCertificate:
        return const PaymentApiException('Certificat serveur invalide.');
      case DioExceptionType.unknown:
      case DioExceptionType.badResponse:
        return const PaymentApiException('Une erreur est survenue, veuillez reessayer.');
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
