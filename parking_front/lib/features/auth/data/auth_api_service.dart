import 'package:dio/dio.dart';

import '../../../core/constants/api_constants.dart';

class AuthApiException implements Exception {
  final String message;
  final int? statusCode;

  const AuthApiException(this.message, {this.statusCode});

  @override
  String toString() => 'AuthApiException(statusCode: $statusCode, message: $message)';
}

class AuthApiResult {
  final String token;
  final Map<String, dynamic> user;

  const AuthApiResult({
    required this.token,
    required this.user,
  });
}

class AuthApiService {
  final Dio _dio;

  AuthApiService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: ApiConstants.baseUrl,
                headers: <String, String>{
                  'Accept': 'application/json',
                  'Content-Type': 'application/json',
                },
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(seconds: 30),
              ),
            );

  Future<AuthApiResult> login({
    required String email,
    required String password,
  }) async {
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        ApiConstants.userLoginPath,
        data: <String, dynamic>{
          'email': email,
          'password': password,
        },
      );

      final int statusCode = response.statusCode ?? 0;
      final Map<String, dynamic> payload = _normalizePayload(response.data);

      if (statusCode != 200) {
        throw AuthApiException(
          _extractMessage(payload),
          statusCode: statusCode,
        );
      }

      return _parseAuthPayload(payload);
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Future<AuthApiResult> register({
    required String name,
    required String email,
    required String phone,
    required String matricule,
    required String password,
    required String passwordConfirmation,
  }) async {
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        ApiConstants.userRegisterPath,
        data: <String, dynamic>{
          'name': name,
          'email': email,
          'phone': phone,
          'matricule': matricule,
          'password': password,
          'password_confirmation': passwordConfirmation,
        },
      );

      final int statusCode = response.statusCode ?? 0;
      final Map<String, dynamic> payload = _normalizePayload(response.data);

      if (statusCode != 201) {
        throw AuthApiException(
          _extractMessage(payload),
          statusCode: statusCode,
        );
      }

      return _parseAuthPayload(payload);
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Future<bool> validateSession(String token) async {
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        ApiConstants.userMePath,
        options: Options(
          headers: <String, String>{
            'Authorization': 'Bearer $token',
          },
        ),
      );

      return response.statusCode == 200;
    } on DioException {
      return false;
    }
  }

  Future<void> logout(String token) async {
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        ApiConstants.userLogoutPath,
        options: Options(
          headers: <String, String>{
            'Authorization': 'Bearer $token',
          },
        ),
      );

      final int statusCode = response.statusCode ?? 0;
      if (statusCode != 200 && statusCode != 204) {
        final Map<String, dynamic> payload = _normalizePayload(response.data);
        throw AuthApiException(
          _extractMessage(payload),
          statusCode: statusCode,
        );
      }
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  AuthApiResult _parseAuthPayload(Map<String, dynamic> payload) {
    final Object? data = payload['data'];
    if (data is! Map<String, dynamic>) {
      throw const AuthApiException('Format de réponse inattendu du serveur.');
    }

    final Object? tokenObj = data['token'];
    final Object? userObj = data['user'];

    if (tokenObj is! String || tokenObj.isEmpty || userObj is! Map<String, dynamic>) {
      throw const AuthApiException('Session invalide reçue depuis le serveur.');
    }

    return AuthApiResult(token: tokenObj, user: userObj);
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

  AuthApiException _mapDioException(DioException error) {
    final int? statusCode = error.response?.statusCode;
    final Map<String, dynamic> payload = _normalizePayload(error.response?.data);
    final String serverHint = 'Serveur: ${ApiConstants.baseUrl}';

    if (statusCode != null) {
      return AuthApiException(
        _extractMessage(payload),
        statusCode: statusCode,
      );
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return AuthApiException(
          'Délai dépassé. Vérifiez votre connexion puis réessayez. $serverHint',
        );
      case DioExceptionType.connectionError:
        return AuthApiException(
          'Impossible de contacter le serveur. Vérifiez votre connexion. $serverHint',
        );
      case DioExceptionType.cancel:
        return const AuthApiException('Requête annulée.');
      case DioExceptionType.badCertificate:
        return const AuthApiException('Certificat serveur invalide.');
      case DioExceptionType.unknown:
      case DioExceptionType.badResponse:
        return const AuthApiException('Une erreur est survenue, veuillez réessayer.');
    }
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

    return 'Une erreur est survenue, veuillez réessayer.';
  }
}
