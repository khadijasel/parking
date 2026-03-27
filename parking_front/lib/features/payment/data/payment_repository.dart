import 'mock_payment_service.dart';

// ════════════════════════════════════════════════════════════
//  PAYMENT REPOSITORY
//
//  PHASE ACTUELLE  → 100 % mock, aucun import Dio
//  PHASE BACKEND   → décommenter les blocs "VERSION API RÉELLE"
//                    et ajouter : import '../../../core/network/dio_client.dart';
// ════════════════════════════════════════════════════════════

class PaymentRepository {
  final MockPaymentService _mock = MockPaymentService();

  // ── Créer / initier une transaction ───────────────────────
  Future<PaymentTransaction> initiate({
    required String sessionId,
    required String userId,
    required String parkingName,
    required int dureeMinutes,
    required PaymentMethod methode,
  }) async {
    final montant = MockPaymentService.calculerMontant(dureeMinutes);

    // VERSION MOCK (actuelle — fonctionne sans backend) ──────
    return _mock.createTransaction(
      sessionId: sessionId,
      userId: userId,
      parkingName: parkingName,
      montant: montant,
      dureeMinutes: dureeMinutes,
      methode: methode,
    );

    // VERSION API RÉELLE (décommenter quand Laravel est prêt) ─
    // final response = await _dio.post('/api/payments/initiate', data: {
    //   'session_id'    : sessionId,
    //   'methode'       : methode.name,
    //   'montant'       : montant,
    //   'duree_minutes' : dureeMinutes,
    // });
    // return PaymentTransaction.fromJson(response.data['transaction']);
  }

  // ── Confirmer avec PIN ────────────────────────────────────
  Future<PaymentResult> confirm({
    required PaymentTransaction transaction,
    required String? pin,
  }) async {
    // VERSION MOCK ───────────────────────────────────────────
    return _mock.processPayment(transaction: transaction, pin: pin);

    // VERSION API RÉELLE ─────────────────────────────────────
    // try {
    //   final response = await _dio.post('/api/payments/confirm', data: {
    //     'transaction_id' : transaction.id,
    //     'pin'            : pin,
    //     'methode'        : transaction.methode.name,
    //   });
    //   transaction.statut = PaymentStatus.success;
    //   transaction.paidAt = DateTime.now();
    //   return PaymentResult(
    //     success: true,
    //     status: PaymentStatus.success,
    //     transaction: transaction,
    //   );
    // } on DioException catch (e) {
    //   final data      = e.response?.data as Map<String, dynamic>?;
    //   final errorCode = data?['error_code'] as String?;
    //   return PaymentResult(
    //     success      : false,
    //     status       : PaymentStatus.failed,
    //     errorType    : _mapError(errorCode),
    //     errorMessage : data?['message'] as String?,
    //   );
    // }
  }

  // ── Historique ────────────────────────────────────────────
  Future<List<PaymentTransaction>> getHistory() async {
    // VERSION MOCK : liste vide
    return [];
    // VERSION API RÉELLE :
    // final r = await _dio.get('/api/payments/history');
    // return (r.data['data'] as List)
    //     .map((e) => PaymentTransaction.fromJson(e as Map<String, dynamic>))
    //     .toList();
  }

  // ── Mapper code erreur API → enum (API réelle uniquement) ─
  // PaymentError _mapError(String? code) {
  //   switch (code) {
  //     case 'WRONG_PIN'          : return PaymentError.wrongPin;
  //     case 'INSUFFICIENT_FUNDS' : return PaymentError.insufficientFunds;
  //     case 'ACCOUNT_BLOCKED'    : return PaymentError.accountBlocked;
  //     case 'NETWORK_TIMEOUT'    : return PaymentError.networkTimeout;
  //     default                   : return PaymentError.unknownError;
  //   }
  // }
}