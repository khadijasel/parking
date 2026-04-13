import 'mock_payment_service.dart';
import '../../auth/data/auth_local_storage.dart';
import 'payment_api_service.dart';

// ════════════════════════════════════════════════════════════
//  PAYMENT REPOSITORY
//
//  PHASE ACTUELLE  → 100 % mock, aucun import Dio
//  PHASE BACKEND   → décommenter les blocs "VERSION API RÉELLE"
//                    et ajouter : import '../../../core/network/dio_client.dart';
// ════════════════════════════════════════════════════════════

class PaymentRepository {
  final PaymentApiService _apiService;
  final AuthLocalStorage _localStorage;

  PaymentRepository({
    PaymentApiService? apiService,
    AuthLocalStorage? localStorage,
  })  : _apiService = apiService ?? PaymentApiService(),
        _localStorage = localStorage ?? AuthLocalStorage();

  // ── Créer / initier une transaction ───────────────────────
  Future<PaymentTransaction> initiate({
    required String reservationId,
    required String parkingName,
    required int dureeMinutes,
    required double amount,
    required PaymentMethod methode,
  }) async {
    final String? token = await _localStorage.readToken();
    if (token == null || token.isEmpty) {
      throw Exception('Session expiree. Reconnectez-vous puis reessayez.');
    }

    try {
      final Map<String, dynamic> transaction = await _apiService.initiate(
        token: token,
        reservationId: reservationId,
        method: methode.name,
        durationMinutes: dureeMinutes,
        amount: amount,
      );

      return _transactionFromApi(
        json: transaction,
        fallbackParkingName: parkingName,
        fallbackDurationMinutes: dureeMinutes,
        fallbackMethod: methode,
        fallbackReservationId: reservationId,
      );
    } on PaymentApiException catch (error) {
      throw Exception(error.message);
    }
  }

  // ── Confirmer avec PIN ────────────────────────────────────
  Future<PaymentResult> confirm({
    required PaymentTransaction transaction,
    required PaymentMethod method,
    required String? pin,
  }) async {
    final String? token = await _localStorage.readToken();
    if (token == null || token.isEmpty) {
      return const PaymentResult(
        success: false,
        status: PaymentStatus.failed,
        errorType: PaymentError.unknownError,
        errorMessage: 'Session expiree. Reconnectez-vous puis reessayez.',
      );
    }

    try {
      final Map<String, dynamic> data = await _apiService.confirm(
        token: token,
        transactionId: transaction.id,
        method: method.name,
        pin: pin,
      );

      final PaymentTransaction updatedTransaction = _transactionFromApi(
        json: (data['transaction'] is Map<String, dynamic>)
            ? data['transaction'] as Map<String, dynamic>
            : <String, dynamic>{},
        fallbackParkingName: transaction.parkingName,
        fallbackDurationMinutes: transaction.dureeMinutes,
        fallbackMethod: method,
        fallbackReservationId: transaction.sessionId,
      );

      final bool success = data['success'] == true;
      final PaymentStatus status = _mapStatus(data['status']?.toString());
      final PaymentError errorType = _mapError(data['error_code']?.toString());
      final String? errorMessage = data['error_message']?.toString();
      final int remainingAttempts = (data['remaining_attempts'] is num)
          ? (data['remaining_attempts'] as num).toInt()
          : 3;

      return PaymentResult(
        success: success,
        status: success ? PaymentStatus.success : status,
        errorType: success ? PaymentError.none : errorType,
        errorMessage: success ? null : errorMessage,
        transaction: updatedTransaction,
        remainingAttempts: remainingAttempts,
      );
    } on PaymentApiException catch (error) {
      return PaymentResult(
        success: false,
        status: PaymentStatus.failed,
        errorType: PaymentError.unknownError,
        errorMessage: error.message,
        transaction: transaction,
      );
    } catch (_) {
      return const PaymentResult(
        success: false,
        status: PaymentStatus.failed,
        errorType: PaymentError.unknownError,
        errorMessage: 'Impossible de confirmer le paiement pour le moment.',
      );
    }
  }

  // ── Historique ────────────────────────────────────────────
  Future<List<PaymentTransaction>> getHistory() async {
    final String? token = await _localStorage.readToken();
    if (token == null || token.isEmpty) {
      return const <PaymentTransaction>[];
    }

    try {
      final List<Map<String, dynamic>> data =
          await _apiService.history(token: token);
      return data
          .map(
            (Map<String, dynamic> item) => _transactionFromApi(
              json: item,
              fallbackParkingName: (item['parking_name'] ?? '').toString(),
              fallbackDurationMinutes: (item['duree_minutes'] is num)
                  ? (item['duree_minutes'] as num).toInt()
                  : 0,
              fallbackMethod: _mapMethod(item['methode']?.toString()),
              fallbackReservationId: (item['session_id'] ?? '').toString(),
            ),
          )
          .toList(growable: false);
    } on PaymentApiException {
      return const <PaymentTransaction>[];
    }
  }

  PaymentTransaction _transactionFromApi({
    required Map<String, dynamic> json,
    required String fallbackParkingName,
    required int fallbackDurationMinutes,
    required PaymentMethod fallbackMethod,
    required String fallbackReservationId,
  }) {
    final String statusRaw = (json['statut'] ?? 'idle').toString();
    final String methodRaw =
        (json['methode'] ?? fallbackMethod.name).toString();

    return PaymentTransaction(
      id: (json['id'] ?? '').toString(),
      sessionId: (json['session_id'] ?? fallbackReservationId).toString(),
      userId: (json['user_id'] ?? '').toString(),
      parkingName: (json['parking_name'] ?? fallbackParkingName).toString(),
      montant: (json['montant'] is num)
          ? (json['montant'] as num).toDouble()
          : MockPaymentService.calculerMontant(fallbackDurationMinutes),
      dureeMinutes: (json['duree_minutes'] is num)
          ? (json['duree_minutes'] as num).toInt()
          : fallbackDurationMinutes,
      methode: _mapMethod(methodRaw),
      statut: _mapStatus(statusRaw),
      transactionRef: (json['transaction_ref'] ?? '').toString(),
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
      paidAt: _parseDate(json['paid_at']),
      errorMessage: json['error_message']?.toString(),
      errorType: _mapError(json['error_code']?.toString()),
    );
  }

  PaymentMethod _mapMethod(String? value) {
    switch (value) {
      case 'cash':
        return PaymentMethod.cash;
      case 'cib':
        return PaymentMethod.cib;
      case 'edahabia':
      default:
        return PaymentMethod.edahabia;
    }
  }

  PaymentStatus _mapStatus(String? value) {
    switch (value) {
      case 'success':
        return PaymentStatus.success;
      case 'failed':
        return PaymentStatus.failed;
      case 'timeout':
        return PaymentStatus.timeout;
      case 'processing':
        return PaymentStatus.processing;
      case 'blocked':
        return PaymentStatus.blocked;
      case 'idle':
      default:
        return PaymentStatus.idle;
    }
  }

  PaymentError _mapError(String? code) {
    switch (code) {
      case 'WRONG_PIN':
        return PaymentError.wrongPin;
      case 'INSUFFICIENT_FUNDS':
        return PaymentError.insufficientFunds;
      case 'ACCOUNT_BLOCKED':
        return PaymentError.accountBlocked;
      case 'NETWORK_TIMEOUT':
        return PaymentError.networkTimeout;
      default:
        return PaymentError.unknownError;
    }
  }

  DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }

    return DateTime.tryParse(value);
  }
}
