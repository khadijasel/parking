import 'package:dio/dio.dart';

import '../../../core/constants/api_constants.dart';

class ParkingAvailabilityApiException implements Exception {
  final String message;

  const ParkingAvailabilityApiException(this.message);

  @override
  String toString() => 'ParkingAvailabilityApiException(message: $message)';
}

class ParkingAvailabilityApiService {
  final Dio _dio;

  ParkingAvailabilityApiService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: ApiConstants.baseUrl,
                headers: const <String, String>{
                  'Accept': 'application/json',
                  'Content-Type': 'application/json',
                },
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 15),
              ),
            );

  Future<List<Map<String, dynamic>>> fetchAvailability() async {
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        ApiConstants.publicParkingAvailabilityPath,
        options: Options(
          validateStatus: (int? status) => status != null && status < 500,
        ),
      );

      final int statusCode = response.statusCode ?? 0;
      final Map<String, dynamic> payload = _normalizePayload(response.data);

      if (statusCode != 200) {
        throw ParkingAvailabilityApiException(_extractMessage(payload));
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
      throw ParkingAvailabilityApiException(_mapDioError(error));
    }
  }

  String _mapDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Delai depasse pour charger les places disponibles.';
      case DioExceptionType.connectionError:
        return 'Impossible de contacter le serveur des places disponibles.';
      case DioExceptionType.cancel:
        return 'Requete annulee.';
      case DioExceptionType.badCertificate:
        return 'Certificat serveur invalide.';
      case DioExceptionType.unknown:
      case DioExceptionType.badResponse:
        final Map<String, dynamic> payload = _normalizePayload(error.response?.data);
        return _extractMessage(payload);
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

    return 'Impossible de charger les places disponibles.';
  }
}
