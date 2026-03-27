import 'dart:math';

// ════════════════════════════════════════════════════════════
//  ENUMS  — aucune dépendance externe
// ════════════════════════════════════════════════════════════

enum PaymentMethod { edahabia, cib, cash }

enum PaymentStatus { idle, processing, success, failed, timeout, blocked }

enum PaymentError {
  none,
  wrongPin,
  insufficientFunds,
  networkTimeout,
  accountBlocked,
  unknownError,   // ← correction : était absent dans l'enum
}

// ════════════════════════════════════════════════════════════
//  MODÈLE TRANSACTION
// ════════════════════════════════════════════════════════════

class PaymentTransaction {
  final String id;
  final String sessionId;
  final String userId;
  final String parkingName;
  final double montant;
  final int dureeMinutes;
  final PaymentMethod methode;
  PaymentStatus statut;
  final String transactionRef;
  final DateTime createdAt;
  DateTime? paidAt;
  String? errorMessage;
  PaymentError errorType;

  PaymentTransaction({
    required this.id,
    required this.sessionId,
    required this.userId,
    required this.parkingName,
    required this.montant,
    required this.dureeMinutes,
    required this.methode,
    this.statut = PaymentStatus.idle,
    required this.transactionRef,
    required this.createdAt,
    this.paidAt,
    this.errorMessage,
    this.errorType = PaymentError.none,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'sessionId': sessionId,
        'userId': userId,
        'parkingName': parkingName,
        'montant': montant,
        'dureeMinutes': dureeMinutes,
        'methode': methode.name,
        'statut': statut.name,
        'transactionRef': transactionRef,
        'createdAt': createdAt.toIso8601String(),
        'paidAt': paidAt?.toIso8601String(),
        'errorMessage': errorMessage,
      };
}

// ════════════════════════════════════════════════════════════
//  RÉSULTAT DE PAIEMENT
// ════════════════════════════════════════════════════════════

class PaymentResult {
  final bool success;
  final PaymentStatus status;
  final PaymentError errorType;
  final String? errorMessage;
  final PaymentTransaction? transaction;
  final int remainingAttempts;

  const PaymentResult({
    required this.success,
    required this.status,
    this.errorType = PaymentError.none,
    this.errorMessage,
    this.transaction,
    this.remainingAttempts = 3,
  });
}

// ════════════════════════════════════════════════════════════
//  MOCK PAYMENT SERVICE
// ════════════════════════════════════════════════════════════

class MockPaymentService {
  static const int    maxAttempts   = 3;
  static const double tarifParHeure = 150.0;
  static const double tarifMinimum  = 50.0;
  static const String demoHint =
      '1234 → succès   •   0000 → fonds insuffisants\n'
      '9999 → timeout  •   autre → PIN incorrect';

  final Map<String, int> _attempts = {};

  // ── Créer une transaction ─────────────────────────────────
  PaymentTransaction createTransaction({
    required String sessionId,
    required String userId,
    required String parkingName,
    required double montant,
    required int dureeMinutes,
    required PaymentMethod methode,
  }) {
    final ref = 'SP-${(10000 + Random().nextInt(89999))}';
    return PaymentTransaction(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      sessionId: sessionId,
      userId: userId,
      parkingName: parkingName,
      montant: montant,
      dureeMinutes: dureeMinutes,
      methode: methode,
      transactionRef: ref,
      createdAt: DateTime.now(),
    );
  }

  // ── Traiter le paiement ───────────────────────────────────
  Future<PaymentResult> processPayment({
    required PaymentTransaction transaction,
    required String? pin,
  }) async {
    // CASH → pas de PIN
    if (transaction.methode == PaymentMethod.cash) {
      await Future.delayed(const Duration(seconds: 1));
      transaction.statut = PaymentStatus.success;
      transaction.paidAt = DateTime.now();
      return PaymentResult(
        success: true,
        status: PaymentStatus.success,
        transaction: transaction,
      );
    }

    // Compte déjà bloqué
    final key      = transaction.id;
    final attempts = _attempts[key] ?? 0;
    if (attempts >= maxAttempts) {
      return _blocked(transaction);
    }

    // Délai simulé
    transaction.statut = PaymentStatus.processing;
    await Future.delayed(const Duration(seconds: 2));

    switch (pin) {
      case '1234': // ✅ Succès
        transaction.statut = PaymentStatus.success;
        transaction.paidAt = DateTime.now();
        _attempts.remove(key);
        return PaymentResult(
          success: true,
          status: PaymentStatus.success,
          transaction: transaction,
        );

      case '0000': // ❌ Fonds insuffisants
        _attempts[key] = attempts + 1;
        transaction.statut    = PaymentStatus.failed;
        transaction.errorType = PaymentError.insufficientFunds;
        transaction.errorMessage = 'Solde insuffisant.\nChoisissez une autre méthode.';
        return PaymentResult(
          success: false,
          status: PaymentStatus.failed,
          errorType: PaymentError.insufficientFunds,
          errorMessage: transaction.errorMessage,
          remainingAttempts: maxAttempts - (_attempts[key]!),
        );

      case '9999': // ⏱ Timeout
        transaction.statut    = PaymentStatus.timeout;
        transaction.errorType = PaymentError.networkTimeout;
        transaction.errorMessage = 'Connexion perdue.\nVotre compte n\'a pas été débité.';
        return PaymentResult(
          success: false,
          status: PaymentStatus.timeout,
          errorType: PaymentError.networkTimeout,
          errorMessage: transaction.errorMessage,
          remainingAttempts: maxAttempts - attempts,
        );

      default: // ❌ PIN incorrect
        _attempts[key] = attempts + 1;
        final remaining = maxAttempts - (_attempts[key]!);
        if (remaining <= 0) return _blocked(transaction);
        transaction.statut    = PaymentStatus.failed;
        transaction.errorType = PaymentError.wrongPin;
        transaction.errorMessage =
            'Code incorrect. Il vous reste $remaining tentative${remaining > 1 ? 's' : ''}.';
        return PaymentResult(
          success: false,
          status: PaymentStatus.failed,
          errorType: PaymentError.wrongPin,
          errorMessage: transaction.errorMessage,
          remainingAttempts: remaining,
        );
    }
  }

  PaymentResult _blocked(PaymentTransaction t) {
    t.statut    = PaymentStatus.failed;
    t.errorType = PaymentError.accountBlocked;
    t.errorMessage = 'Compte bloqué après 3 tentatives.\nContactez Algérie Poste.';
    return PaymentResult(
      success: false,
      status: PaymentStatus.failed,
      errorType: PaymentError.accountBlocked,
      errorMessage: t.errorMessage,
      remainingAttempts: 0,
    );
  }

  // ── Utilitaires statiques ─────────────────────────────────
  static double calculerMontant(int dureeMinutes) {
    if (dureeMinutes <= 30) return tarifMinimum;
    return ((dureeMinutes / 60.0) * tarifParHeure).roundToDouble();
  }

  static String formaterDuree(int dureeMinutes) {
    if (dureeMinutes < 60) return '$dureeMinutes min';
    final h = dureeMinutes ~/ 60;
    final m = dureeMinutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}min';
  }

  void resetAttempts(String transactionId) => _attempts.remove(transactionId);
}