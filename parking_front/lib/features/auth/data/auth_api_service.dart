import 'package:dio/dio.dart';

import '../../../core/constants/api_constants.dart';

class AuthApiException implements Exception {
  final String message;
  final int? statusCode;
  final Map<String, String> fieldErrors;
  final bool isRetryable;

  const AuthApiException(
    this.message, {
    this.statusCode,
    this.fieldErrors = const <String, String>{},
    this.isRetryable = false,
  });

  @override
  String toString() =>
      'AuthApiException(statusCode: $statusCode, message: $message, fieldErrors: $fieldErrors, isRetryable: $isRetryable)';
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
    required String matricule,
    required String email,
    required String password,
  }) async {
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        ApiConstants.userLoginPath,
        data: <String, dynamic>{
          'matricule': matricule,
          'email': email,
          'password': password,
        },
      );

      final int statusCode = response.statusCode ?? 0;
      final Map<String, dynamic> payload = _normalizePayload(response.data);

      if (statusCode != 200) {
        final Map<String, String> fieldErrors = _extractFieldErrors(payload);
        throw AuthApiException(
          _extractMessage(payload, fieldErrors: fieldErrors),
          statusCode: statusCode,
          fieldErrors: fieldErrors,
          isRetryable: statusCode >= 500,
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
        final Map<String, String> fieldErrors = _extractFieldErrors(payload);
        throw AuthApiException(
          _extractMessage(payload, fieldErrors: fieldErrors),
          statusCode: statusCode,
          fieldErrors: fieldErrors,
          isRetryable: statusCode >= 500,
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
          validateStatus: (int? status) => status != null && status < 500,
        ),
      );

      final int statusCode = response.statusCode ?? 0;
      if (statusCode == 200) {
        return true;
      }

      // Explicit auth failures should invalidate local session.
      if (statusCode == 401 || statusCode == 403) {
        return false;
      }

      // Preserve local session on transient backend issues.
      return true;
    } on DioException catch (error) {
      final int? statusCode = error.response?.statusCode;
      if (statusCode == 401 || statusCode == 403) {
        return false;
      }

      // Network errors should not force logout.
      return true;
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
        final Map<String, String> fieldErrors = _extractFieldErrors(payload);
        throw AuthApiException(
          _extractMessage(payload, fieldErrors: fieldErrors),
          statusCode: statusCode,
          fieldErrors: fieldErrors,
          isRetryable: statusCode >= 500,
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

    if (tokenObj is! String ||
        tokenObj.isEmpty ||
        userObj is! Map<String, dynamic>) {
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
    final Map<String, dynamic> payload =
        _normalizePayload(error.response?.data);
    final String serverHint = 'Serveur: ${ApiConstants.baseUrl}';

    if (statusCode != null) {
      final Map<String, String> fieldErrors = _extractFieldErrors(payload);
      return AuthApiException(
        _extractMessage(payload, fieldErrors: fieldErrors),
        statusCode: statusCode,
        fieldErrors: fieldErrors,
        isRetryable: statusCode >= 500,
      );
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return AuthApiException(
          'Délai dépassé. Vérifiez votre connexion puis appuyez sur Réessayer. $serverHint',
          isRetryable: true,
        );
      case DioExceptionType.connectionError:
        return AuthApiException(
          'Impossible de contacter le serveur. Vérifiez votre connexion puis appuyez sur Réessayer. $serverHint',
          isRetryable: true,
        );
      case DioExceptionType.cancel:
        return const AuthApiException('Requête annulée.');
      case DioExceptionType.badCertificate:
        return const AuthApiException('Certificat serveur invalide.');
      case DioExceptionType.unknown:
      case DioExceptionType.badResponse:
        return const AuthApiException(
          'Une erreur réseau est survenue. Appuyez sur Réessayer.',
          isRetryable: true,
        );
    }
  }

  String _extractMessage(
    Map<String, dynamic> payload, {
    Map<String, String>? fieldErrors,
  }) {
    if (fieldErrors != null && fieldErrors.isNotEmpty) {
      return fieldErrors.values.first;
    }

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

  Map<String, String> _extractFieldErrors(Map<String, dynamic> payload) {
    final Object? errorsObj = payload['errors'];
    if (errorsObj is! Map<String, dynamic>) {
      return const <String, String>{};
    }

    final Map<String, String> fieldErrors = <String, String>{};
    for (final MapEntry<String, dynamic> entry in errorsObj.entries) {
      final dynamic value = entry.value;
      if (value is List && value.isNotEmpty && value.first is String) {
        fieldErrors[entry.key] = (value.first as String).trim();
        continue;
      }
      if (value is String && value.trim().isNotEmpty) {
        fieldErrors[entry.key] = value.trim();
      }
    }

    return fieldErrors;
  }
}
