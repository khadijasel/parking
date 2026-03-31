import '../../auth/data/auth_local_storage.dart';
import 'models/reservation_api_model.dart';
import 'reservation_api_service.dart';

class ReservationException implements Exception {
  final String message;

  const ReservationException(this.message);

  @override
  String toString() => 'ReservationException(message: $message)';
}

class ReservationRepository {
  final ReservationApiService _apiService;
  final AuthLocalStorage _localStorage;

  ReservationRepository({
    ReservationApiService? apiService,
    AuthLocalStorage? localStorage,
  })  : _apiService = apiService ?? ReservationApiService(),
        _localStorage = localStorage ?? AuthLocalStorage();

  Future<ReservationApiModel> createReservation({
    required String parkingName,
    required String parkingAddress,
    required List<String> equipments,
    required String durationType,
    required int durationMinutes,
    required double amount,
    required double depositAmount,
  }) async {
    final String? token = await _localStorage.readToken();
    if (token == null || token.isEmpty) {
      throw const ReservationException('Session expiree. Reconnectez-vous puis reessayez.');
    }

    try {
      final Map<String, dynamic> data = await _apiService.createReservation(
        token: token,
        parkingName: parkingName,
        parkingAddress: parkingAddress,
        equipments: equipments,
        durationType: durationType,
        durationMinutes: durationMinutes,
        amount: amount,
        depositAmount: depositAmount,
      );

      return ReservationApiModel.fromJson(data);
    } on ReservationApiException catch (error) {
      throw ReservationException(error.message);
    }
  }

  Future<List<ReservationApiModel>> fetchMyReservations() async {
    final String? token = await _localStorage.readToken();
    if (token == null || token.isEmpty) {
      throw const ReservationException('Session expiree. Reconnectez-vous puis reessayez.');
    }

    try {
      final List<Map<String, dynamic>> data = await _apiService.fetchReservations(
        token: token,
      );

      return data
          .map((Map<String, dynamic> item) => ReservationApiModel.fromJson(item))
          .toList(growable: false);
    } on ReservationApiException catch (error) {
      throw ReservationException(error.message);
    }
  }

  Future<void> cancelReservation(String reservationId) async {
    final String? token = await _localStorage.readToken();
    if (token == null || token.isEmpty) {
      throw const ReservationException('Session expiree. Reconnectez-vous puis reessayez.');
    }

    try {
      await _apiService.cancelReservation(
        token: token,
        reservationId: reservationId,
      );
    } on ReservationApiException catch (error) {
      throw ReservationException(error.message);
    }
  }

  Future<ReservationApiModel> markReservationEnRoute(String reservationId) async {
    final String? token = await _localStorage.readToken();
    if (token == null || token.isEmpty) {
      throw const ReservationException('Session expiree. Reconnectez-vous puis reessayez.');
    }

    try {
      final Map<String, dynamic> data = await _apiService.markReservationEnRoute(
        token: token,
        reservationId: reservationId,
      );

      return ReservationApiModel.fromJson(data);
    } on ReservationApiException catch (error) {
      throw ReservationException(error.message);
    }
  }

  Future<ReservationApiModel> completeReservationByTicket(String reservationId) async {
    final String? token = await _localStorage.readToken();
    if (token == null || token.isEmpty) {
      throw const ReservationException('Session expiree. Reconnectez-vous puis reessayez.');
    }

    try {
      final Map<String, dynamic> data = await _apiService.completeReservationByTicket(
        token: token,
        reservationId: reservationId,
      );

      return ReservationApiModel.fromJson(data);
    } on ReservationApiException catch (error) {
      throw ReservationException(error.message);
    }
  }
}
