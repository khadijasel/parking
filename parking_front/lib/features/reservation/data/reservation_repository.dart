import '../../auth/data/auth_local_storage.dart';
import 'models/parking_session_api_model.dart';
import 'models/reservation_api_model.dart';
import 'reservation_api_service.dart';

class ReservationException implements Exception {
  final String message;

  const ReservationException(this.message);

  @override
  String toString() => 'ReservationException(message: $message)';
}

class ReservationRepository {
  static const Duration _cacheTtl = Duration(seconds: 15);

  static List<ReservationApiModel>? _reservationsCache;
  static DateTime? _reservationsCacheAt;

  static ParkingSessionApiModel? _currentSessionCache;
  static DateTime? _currentSessionCacheAt;
  static bool _hasCurrentSessionCache = false;

  static List<ParkingSessionApiModel>? _parkingHistoryCache;
  static DateTime? _parkingHistoryCacheAt;

  final ReservationApiService _apiService;
  final AuthLocalStorage _localStorage;

  ReservationRepository({
    ReservationApiService? apiService,
    AuthLocalStorage? localStorage,
  })  : _apiService = apiService ?? ReservationApiService(),
        _localStorage = localStorage ?? AuthLocalStorage();

  bool _isCacheFresh(DateTime? at) {
    if (at == null) {
      return false;
    }

    return DateTime.now().difference(at) < _cacheTtl;
  }

  void _invalidateReservationsCache() {
    _reservationsCache = null;
    _reservationsCacheAt = null;
  }

  void _invalidateCurrentSessionCache() {
    _currentSessionCache = null;
    _currentSessionCacheAt = null;
    _hasCurrentSessionCache = false;
  }

  void _invalidateParkingHistoryCache() {
    _parkingHistoryCache = null;
    _parkingHistoryCacheAt = null;
  }

  void _invalidateAllReservationCaches() {
    _invalidateReservationsCache();
    _invalidateCurrentSessionCache();
    _invalidateParkingHistoryCache();
  }

  Future<ReservationApiModel> createReservation({
    required String parkingId,
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
      throw const ReservationException(
          'Session expiree. Reconnectez-vous puis reessayez.');
    }

    try {
      final Map<String, dynamic> data = await _apiService.createReservation(
        token: token,
        parkingId: parkingId,
        parkingName: parkingName,
        parkingAddress: parkingAddress,
        equipments: equipments,
        durationType: durationType,
        durationMinutes: durationMinutes,
        amount: amount,
        depositAmount: depositAmount,
      );
      _invalidateAllReservationCaches();
      return ReservationApiModel.fromJson(data);
    } on ReservationApiException catch (error) {
      throw ReservationException(error.message);
    }
  }

  Future<List<ReservationApiModel>> fetchMyReservations({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _reservationsCache != null &&
        _isCacheFresh(_reservationsCacheAt)) {
      return _reservationsCache!;
    }

    final String? token = await _localStorage.readToken();
    if (token == null || token.isEmpty) {
      throw const ReservationException(
          'Session expiree. Reconnectez-vous puis reessayez.');
    }

    try {
      final List<Map<String, dynamic>> data =
          await _apiService.fetchReservations(
        token: token,
      );

      final List<ReservationApiModel> mapped = data
          .map(
              (Map<String, dynamic> item) => ReservationApiModel.fromJson(item))
          .toList(growable: false);

      _reservationsCache = mapped;
      _reservationsCacheAt = DateTime.now();
      return mapped;
    } on ReservationApiException catch (error) {
      throw ReservationException(error.message);
    }
  }

  Future<void> cancelReservation(String reservationId) async {
    final String? token = await _localStorage.readToken();
    if (token == null || token.isEmpty) {
      throw const ReservationException(
          'Session expiree. Reconnectez-vous puis reessayez.');
    }

    try {
      await _apiService.cancelReservation(
        token: token,
        reservationId: reservationId,
      );
      _invalidateAllReservationCaches();
    } on ReservationApiException catch (error) {
      throw ReservationException(error.message);
    }
  }

  Future<ReservationApiModel> markReservationEnRoute(
      String reservationId) async {
    final String? token = await _localStorage.readToken();
    if (token == null || token.isEmpty) {
      throw const ReservationException(
          'Session expiree. Reconnectez-vous puis reessayez.');
    }

    try {
      final Map<String, dynamic> data =
          await _apiService.markReservationEnRoute(
        token: token,
        reservationId: reservationId,
      );
      _invalidateAllReservationCaches();
      return ReservationApiModel.fromJson(data);
    } on ReservationApiException catch (error) {
      throw ReservationException(error.message);
    }
  }

  Future<ReservationApiModel> completeReservationByTicket(
      String reservationId) async {
    final String? token = await _localStorage.readToken();
    if (token == null || token.isEmpty) {
      throw const ReservationException(
          'Session expiree. Reconnectez-vous puis reessayez.');
    }

    try {
      final Map<String, dynamic> data =
          await _apiService.completeReservationByTicket(
        token: token,
        reservationId: reservationId,
      );

      _invalidateReservationsCache();
      _invalidateParkingHistoryCache();

      final Object? parkingSessionRaw = data['parking_session'];
      if (parkingSessionRaw is Map<String, dynamic>) {
        _currentSessionCache =
            ParkingSessionApiModel.fromJson(parkingSessionRaw);
        _currentSessionCacheAt = DateTime.now();
        _hasCurrentSessionCache = true;
      } else if (parkingSessionRaw is Map) {
        final Map<String, dynamic> normalized =
            parkingSessionRaw.map<String, dynamic>(
          (dynamic key, dynamic value) => MapEntry<String, dynamic>(
            key.toString(),
            value,
          ),
        );
        _currentSessionCache = ParkingSessionApiModel.fromJson(normalized);
        _currentSessionCacheAt = DateTime.now();
        _hasCurrentSessionCache = true;
      } else {
        _invalidateCurrentSessionCache();
      }

      return ReservationApiModel.fromJson(data);
    } on ReservationApiException catch (error) {
      throw ReservationException(error.message);
    }
  }

  Future<ParkingSessionApiModel?> fetchCurrentParkingSession({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _hasCurrentSessionCache &&
        _isCacheFresh(_currentSessionCacheAt)) {
      return _currentSessionCache;
    }

    final String? token = await _localStorage.readToken();
    if (token == null || token.isEmpty) {
      throw const ReservationException(
          'Session expiree. Reconnectez-vous puis reessayez.');
    }

    try {
      final Map<String, dynamic>? data =
          await _apiService.fetchCurrentParkingSession(
        token: token,
      );

      if (data == null) {
        _currentSessionCache = null;
        _currentSessionCacheAt = DateTime.now();
        _hasCurrentSessionCache = true;
        return null;
      }

      final ParkingSessionApiModel mapped =
          ParkingSessionApiModel.fromJson(data);
      _currentSessionCache = mapped;
      _currentSessionCacheAt = DateTime.now();
      _hasCurrentSessionCache = true;
      return mapped;
    } on ReservationApiException catch (error) {
      throw ReservationException(error.message);
    }
  }

  Future<ParkingSessionApiModel> exitCurrentParkingSession() async {
    final String? token = await _localStorage.readToken();
    if (token == null || token.isEmpty) {
      throw const ReservationException(
          'Session expiree. Reconnectez-vous puis reessayez.');
    }

    try {
      final Map<String, dynamic> data =
          await _apiService.exitCurrentParkingSession(
        token: token,
      );
      final ParkingSessionApiModel mapped =
          ParkingSessionApiModel.fromJson(data);

      _currentSessionCache = null;
      _currentSessionCacheAt = DateTime.now();
      _hasCurrentSessionCache = true;
      _invalidateReservationsCache();
      _invalidateParkingHistoryCache();

      return mapped;
    } on ReservationApiException catch (error) {
      throw ReservationException(error.message);
    }
  }

  Future<List<ParkingSessionApiModel>> fetchParkingSessionHistory({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _parkingHistoryCache != null &&
        _isCacheFresh(_parkingHistoryCacheAt)) {
      return _parkingHistoryCache!;
    }

    final String? token = await _localStorage.readToken();
    if (token == null || token.isEmpty) {
      throw const ReservationException(
          'Session expiree. Reconnectez-vous puis reessayez.');
    }

    try {
      final List<Map<String, dynamic>> data =
          await _apiService.fetchParkingSessionHistory(
        token: token,
      );

      final List<ParkingSessionApiModel> mapped = data
          .map((Map<String, dynamic> item) =>
              ParkingSessionApiModel.fromJson(item))
          .toList(growable: false);

      _parkingHistoryCache = mapped;
      _parkingHistoryCacheAt = DateTime.now();
      return mapped;
    } on ReservationApiException catch (error) {
      throw ReservationException(error.message);
    }
  }
}
