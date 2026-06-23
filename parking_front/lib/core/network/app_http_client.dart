import 'dart:async';

import 'package:dio/dio.dart';

import '../constants/api_constants.dart';

/// Client HTTP Dio partage par toute l'application.
///
/// Pourquoi : auparavant chaque service API (`auth`, `reservation`, `payment`,
/// `profile`, `parking`, `availability`) instanciait son propre `Dio`, soit
/// autant de pools de connexions HTTP distincts recrees a chaque navigation.
/// Un client unique reutilise les connexions keep-alive entre tous les ecrans,
/// ce qui reduit nettement la latence percue au clic sur un bouton.
///
/// Les timeouts etaient aussi incoherents (30s sur certains services) : une
/// requete bloquee gelait l'interface jusqu'a 30s. On uniformise a 12s.
///
/// On ajoute aussi un [_RetryInterceptor] : au demarrage a froid (cold start),
/// l'app envoie ses premieres requetes pendant que le serveur Laravel finit de
/// demarrer. La toute premiere requete echoue alors avec "connection refused"
/// et l'ecran affichait "parkings indisponibles" jusqu'a un hot-restart manuel.
/// L'intercepteur retente automatiquement les GET en cas d'erreur de connexion,
/// ce qui fait que l'app se rattrape toute seule quand le serveur est pret.
class AppHttpClient {
  AppHttpClient._();

  static final Dio instance = _build();

  static Dio _build() {
    final Dio dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        headers: const <String, String>{
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 12),
        sendTimeout: const Duration(seconds: 12),
      ),
    );

    dio.interceptors.add(_RetryInterceptor(dio));
    return dio;
  }
}

/// Retente automatiquement les requetes GET qui echouent parce que le serveur
/// est injoignable (refus de connexion / timeout de connexion). On se limite
/// aux GET : ce sont des operations idempotentes ou le serveur n'a de toute
/// facon jamais traite la requete, donc les rejouer est sans danger. Les POST
/// (paiement, login...) ne sont jamais rejoues pour eviter tout double envoi.
class _RetryInterceptor extends Interceptor {
  _RetryInterceptor(this._dio);

  final Dio _dio;

  static const int _maxRetries = 3;
  static const List<Duration> _backoff = <Duration>[
    Duration(milliseconds: 400),
    Duration(milliseconds: 900),
    Duration(milliseconds: 1600),
  ];

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final RequestOptions request = err.requestOptions;
    final int attempt = (request.extra['retry_attempt'] as int?) ?? 0;

    if (!_shouldRetry(err) || attempt >= _maxRetries) {
      return handler.next(err);
    }

    await Future<void>.delayed(_backoff[attempt]);

    try {
      final Response<dynamic> response = await _dio.request<dynamic>(
        request.path,
        data: request.data,
        queryParameters: request.queryParameters,
        cancelToken: request.cancelToken,
        onReceiveProgress: request.onReceiveProgress,
        onSendProgress: request.onSendProgress,
        options: Options(
          method: request.method,
          headers: request.headers,
          responseType: request.responseType,
          contentType: request.contentType,
          sendTimeout: request.sendTimeout,
          receiveTimeout: request.receiveTimeout,
          validateStatus: request.validateStatus,
          extra: <String, dynamic>{
            ...request.extra,
            'retry_attempt': attempt + 1,
          },
        ),
      );
      return handler.resolve(response);
    } on DioException catch (retryError) {
      return handler.next(retryError);
    }
  }

  bool _shouldRetry(DioException error) {
    if (error.requestOptions.method.toUpperCase() != 'GET') {
      return false;
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.badCertificate:
      case DioExceptionType.badResponse:
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
        return false;
    }
  }
}
