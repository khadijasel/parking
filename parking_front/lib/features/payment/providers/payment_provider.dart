import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/mock_payment_service.dart';
import '../data/payment_repository.dart';

// ════════════════════════════════════════════════════════════
//  PAYMENT STATE
// ════════════════════════════════════════════════════════════

class PaymentState {
  final PaymentStatus       status;
  final PaymentTransaction? transaction;
  final PaymentError        errorType;
  final String?             errorMessage;
  final int                 remainingAttempts;
  final PaymentMethod       selectedMethod;
  final String              pin;
  final bool                showDemoHint;

  const PaymentState({
    this.status            = PaymentStatus.idle,
    this.transaction,
    this.errorType         = PaymentError.none,
    this.errorMessage,
    this.remainingAttempts = 3,
    this.selectedMethod    = PaymentMethod.edahabia,
    this.pin               = '',
    this.showDemoHint      = true,
  });

  bool get isIdle       => status == PaymentStatus.idle;
  bool get isProcessing => status == PaymentStatus.processing;
  bool get isSuccess    => status == PaymentStatus.success;
  bool get isFailed     => status == PaymentStatus.failed;
  bool get isTimeout    => status == PaymentStatus.timeout;
  bool get isBlocked    => status == PaymentStatus.blocked;
  bool get hasError     => isFailed || isTimeout || isBlocked;
  bool get canConfirm   => selectedMethod == PaymentMethod.cash || pin.length == 4;

  PaymentState copyWith({
    PaymentStatus?      status,
    PaymentTransaction? transaction,
    PaymentError?       errorType,
    String?             errorMessage,
    int?                remainingAttempts,
    PaymentMethod?      selectedMethod,
    String?             pin,
    bool?               showDemoHint,
  }) =>
      PaymentState(
        status:            status            ?? this.status,
        transaction:       transaction       ?? this.transaction,
        errorType:         errorType         ?? this.errorType,
        errorMessage:      errorMessage      ?? this.errorMessage,
        remainingAttempts: remainingAttempts ?? this.remainingAttempts,
        selectedMethod:    selectedMethod    ?? this.selectedMethod,
        pin:               pin               ?? this.pin,
        showDemoHint:      showDemoHint      ?? this.showDemoHint,
      );
}

// ════════════════════════════════════════════════════════════
//  PAYMENT NOTIFIER
// ════════════════════════════════════════════════════════════

class PaymentNotifier extends StateNotifier<PaymentState> {
  final PaymentRepository _repo;
  PaymentNotifier(this._repo) : super(const PaymentState());

  // ── Initialiser la transaction ────────────────────────────
  Future<void> initiate({
    required String sessionId,
    required String userId,
    required String parkingName,
    required int    dureeMinutes,
  }) async {
    final tx = await _repo.initiate(
      sessionId:    sessionId,
      userId:       userId,
      parkingName:  parkingName,
      dureeMinutes: dureeMinutes,
      methode:      state.selectedMethod,
    );
    state = state.copyWith(transaction: tx);
  }

  // ── Méthode de paiement ───────────────────────────────────
  void selectMethod(PaymentMethod m) {
    state = state.copyWith(
      selectedMethod: m,
      pin:            '',
      errorType:      PaymentError.none,
      errorMessage:   null,
    );
  }

  // ── Sync PIN depuis le TextField du téléphone ─────────────
  void syncPin(String val) => state = state.copyWith(pin: val);

  void clearPin() => state = state.copyWith(pin: '');

  // ── Confirmer le paiement ─────────────────────────────────
  Future<void> confirmPayment() async {
    if (!state.canConfirm || state.isProcessing) return;
    if (state.transaction == null) return;

    state = state.copyWith(
      status:       PaymentStatus.processing,
      errorType:    PaymentError.none,
      errorMessage: null,
    );

    final result = await _repo.confirm(
      transaction: state.transaction!,
      pin: state.selectedMethod == PaymentMethod.cash ? null : state.pin,
    );

    if (result.success) {
      state = state.copyWith(
        status:      PaymentStatus.success,
        transaction: result.transaction,
        pin:         '',
      );
    } else {
      final finalStatus = result.errorType == PaymentError.accountBlocked
          ? PaymentStatus.blocked
          : result.status;
      state = state.copyWith(
        status:            finalStatus,
        errorType:         result.errorType,
        errorMessage:      result.errorMessage,
        remainingAttempts: result.remainingAttempts,
        pin:               '',
      );
    }
  }

  void retry() {
    if (state.isBlocked) return;
    state = state.copyWith(
      status:       PaymentStatus.idle,
      errorType:    PaymentError.none,
      errorMessage: null,
      pin:          '',
    );
  }

  void hideDemoHint() => state = state.copyWith(showDemoHint: false);
  void reset()        => state = const PaymentState();
}

// ════════════════════════════════════════════════════════════
//  PROVIDERS
// ════════════════════════════════════════════════════════════

final paymentRepositoryProvider = Provider<PaymentRepository>(
  (_) => PaymentRepository(),
);

final paymentProvider =
    StateNotifierProvider<PaymentNotifier, PaymentState>((ref) {
  return PaymentNotifier(ref.watch(paymentRepositoryProvider));
});

final paymentStatusProvider =
    Provider<PaymentStatus>((ref) => ref.watch(paymentProvider).status);

final paymentTransactionProvider =
    Provider<PaymentTransaction?>((ref) => ref.watch(paymentProvider).transaction);

final canConfirmProvider =
    Provider<bool>((ref) => ref.watch(paymentProvider).canConfirm);