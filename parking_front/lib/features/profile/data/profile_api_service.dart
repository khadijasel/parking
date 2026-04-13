import 'package:dio/dio.dart';

import '../../../core/constants/api_constants.dart';

class ProfileApiException implements Exception {
  final String message;
  final int? statusCode;

  const ProfileApiException(this.message, {this.statusCode});

  @override
  String toString() =>
      'ProfileApiException(statusCode: $statusCode, message: $message)';
}

class ProfileApiService {
  final Dio _dio;

  ProfileApiService({Dio? dio})
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

  Future<Map<String, dynamic>> fetchProfile({required String token}) async {
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        ApiConstants.userMePath,
        options: _authorizedOptions(token),
      );

      final int statusCode = response.statusCode ?? 0;
      final Map<String, dynamic> payload = _normalizePayload(response.data);

      if (statusCode != 200) {
        throw ProfileApiException(
          _extractMessage(payload),
          statusCode: statusCode,
        );
      }

      final Object? data = payload['data'];
      if (data is! Map<String, dynamic>) {
        throw const ProfileApiException('Format de reponse inattendu du serveur.');
      }

      return data;
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Future<Map<String, dynamic>> updateProfile({
    required String token,
    required Map<String, dynamic> payload,
  }) async {
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        ApiConstants.userProfileUpdatePath,
        data: payload,
        options: _authorizedOptions(token),
      );

      final int statusCode = response.statusCode ?? 0;
      final Map<String, dynamic> body = _normalizePayload(response.data);

      if (statusCode != 200) {
        throw ProfileApiException(
          _extractMessage(body),
          statusCode: statusCode,
        );
      }

      final Object? data = body['data'];
      if (data is! Map<String, dynamic>) {
        throw const ProfileApiException('Format de reponse inattendu du serveur.');
      }

      return data;
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

  ProfileApiException _mapDioException(DioException error) {
    final int? statusCode = error.response?.statusCode;
    final Map<String, dynamic> payload = _normalizePayload(error.response?.data);

    if (statusCode != null) {
      return ProfileApiException(
        _extractMessage(payload),
        statusCode: statusCode,
      );
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const ProfileApiException(
          'Delai depasse. Verifiez votre connexion puis reessayez.',
        );
      case DioExceptionType.connectionError:
        return const ProfileApiException('Impossible de contacter le serveur.');
      case DioExceptionType.cancel:
        return const ProfileApiException('Requete annulee.');
      case DioExceptionType.badCertificate:
        return const ProfileApiException('Certificat serveur invalide.');
      case DioExceptionType.unknown:
      case DioExceptionType.badResponse:
        return const ProfileApiException(
          'Une erreur est survenue, veuillez reessayer.',
        );
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
