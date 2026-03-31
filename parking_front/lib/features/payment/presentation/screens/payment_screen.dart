import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/mock_payment_service.dart';
import '../../providers/payment_provider.dart';
import 'payment_confirmation_screen.dart';

const _kBlue     = Color(0xFF4A90E2);
const _kGreen    = Color(0xFF2ECC71);
const _kOrange   = Color(0xFFF5A623);
const _kOrangeBg = Color(0xFFFFF8EC);
const _kRed      = Color(0xFFE53935);
const _kRedBg    = Color(0xFFFFF0EE);
const _kBg       = Color(0xFFEAF1FB);
const _kBorder   = Color(0xFFE2ECF9);
const _kLocked   = Color(0xFFDDE8F7);
const _kTextDark = Color(0xFF1A1A2E);
const _kTextMid  = Color(0xFF8A9BB5);

class PaymentScreen extends ConsumerStatefulWidget {
  final String  reservationId;
  final String  parkingName;
  final int     dureeMinutes;
  final double? montantFixe;
  final bool    allowCash;
  final bool    returnToCallerOnSuccess;

  const PaymentScreen({
    super.key,
    required this.reservationId,
    required this.parkingName,
    required this.dureeMinutes,
    this.montantFixe,
    this.allowCash = true,
    this.returnToCallerOnSuccess = false,
  });

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen>
    with SingleTickerProviderStateMixin {

  final _pinController = TextEditingController();
  final _pinFocus      = FocusNode();

  late AnimationController _shakeCtrl;
  late Animation<double>   _shakeAnim;

  @override
  void initState() {
    super.initState();

    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = ref.read(paymentProvider.notifier);
      notifier.reset();

      if (!widget.allowCash) {
        notifier.selectMethod(PaymentMethod.edahabia);
      }

      notifier.initiate(
        reservationId: widget.reservationId,
        parkingName:  widget.parkingName,
        dureeMinutes: widget.dureeMinutes,
      );
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    _pinFocus.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  double get _montant => widget.montantFixe
      ?? MockPaymentService.calculerMontant(widget.dureeMinutes);

    List<PaymentMethod> get _availableMethods => widget.allowCash
      ? PaymentMethod.values
      : const <PaymentMethod>[PaymentMethod.edahabia, PaymentMethod.cib];

  void _onStateChange(PaymentState? _, PaymentState next) {
    if (next.isSuccess && next.transaction != null) {
      HapticFeedback.heavyImpact();

      if (widget.returnToCallerOnSuccess) {
        Navigator.pop(context, true);
        ref.read(paymentProvider.notifier).reset();
        return;
      }

      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, a, __) =>
              PaymentConfirmationScreen(transaction: next.transaction!),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
      ref.read(paymentProvider.notifier).reset();
      return;
    }
    if (next.hasError) {
      HapticFeedback.heavyImpact();
      _pinController.clear();
      _shakeCtrl.forward(from: 0);
      if (next.isBlocked) {
        _showBlockedDialog(next.errorMessage ?? '');
      } else {
        _showErrorSnackbar(next.errorMessage ?? '', next.errorType);
      }
    }
  }

  void _showErrorSnackbar(String msg, PaymentError type) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
          type == PaymentError.networkTimeout
              ? Icons.wifi_off_rounded
              : Icons.error_outline_rounded,
          color: Colors.white, size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(
            color: Colors.white, fontSize: 13, height: 1.4))),
      ]),
      backgroundColor: _kRed,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      duration: const Duration(seconds: 4),
    ));
  }

  void _showBlockedDialog(String msg) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(
                color: _kRedBg, borderRadius: BorderRadius.circular(18)),
            child: const Icon(Icons.lock_outline_rounded,
                color: _kRed, size: 30),
          ),
          const SizedBox(height: 16),
          const Text('Compte bloqué', style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(msg, textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 14, color: _kTextMid, height: 1.5)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  final PaymentMethod replacementMethod = widget.allowCash
                      ? PaymentMethod.cash
                      : (ref.read(paymentProvider).selectedMethod == PaymentMethod.edahabia
                          ? PaymentMethod.cib
                          : PaymentMethod.edahabia);

                  Navigator.pop(context);
                  _pinController.clear();
                  ref.read(paymentProvider.notifier)
                      .selectMethod(replacementMethod);
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _kBorder),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Autre méthode'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kBlue, elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Retour',
                    style: TextStyle(color: Colors.white)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PaymentState>(paymentProvider, _onStateChange);
    final state = ref.watch(paymentProvider);
    final bool isCashSelected = widget.allowCash && state.selectedMethod == PaymentMethod.cash;

    return Scaffold(
      backgroundColor: _kBg,
      // ── resizeToAvoidBottomInset: true = le scroll remonte quand clavier ouvre
      resizeToAvoidBottomInset: true,
      appBar: _appBar(),
      body: GestureDetector(
        // Tap en dehors → ferme le clavier
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          // ── keyboardDismissBehavior = scroll vers le bas ferme le clavier
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          child: Column(children: [
            const SizedBox(height: 16),
            _summaryCard(state),
            const SizedBox(height: 16),
            _methodSelector(state),
            const SizedBox(height: 20),
            if (!isCashSelected) ...[
              _pinSection(state),
              const SizedBox(height: 20),
            ],
            if (isCashSelected) ...[
              _cashInfo(),
              const SizedBox(height: 20),
            ],
            _confirmButton(state),
            const SizedBox(height: 14),
            _securityNote(),
            if (state.showDemoHint) ...[
              const SizedBox(height: 16),
              _demoHint(),
            ],
            // ── Espace en bas pour éviter overflow avec clavier ──
            SizedBox(height: MediaQuery.of(context).viewInsets.bottom > 0
                ? 20 : 0),
          ]),
        ),
      ),
    );
  }

  AppBar _appBar() => AppBar(
    backgroundColor: Colors.white,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    leading: Padding(
      padding: const EdgeInsets.all(8),
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          decoration: BoxDecoration(
              color: _kBg, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.arrow_back_rounded,
              size: 20, color: _kTextDark),
        ),
      ),
    ),
    title: const Text('Paiement',
        style: TextStyle(fontWeight: FontWeight.w700,
            fontSize: 18, color: _kTextDark)),
    centerTitle: true,
  );

  Widget _summaryCard(PaymentState state) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: _kBlue.withOpacity(0.07),
            blurRadius: 24, offset: const Offset(0, 8))],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        Container(width: 52, height: 52,
            decoration: BoxDecoration(
                color: _kLocked, borderRadius: BorderRadius.circular(14)),
            child: const Center(child: Text('P', style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: _kBlue)))),
        const SizedBox(height: 10),
        const Text('Total à payer',
            style: TextStyle(fontSize: 13, color: _kTextMid)),
        const SizedBox(height: 4),
        Text('${_montant.toInt()} DA', style: const TextStyle(
            fontSize: 34, fontWeight: FontWeight.w800, color: _kTextDark)),
        const SizedBox(height: 2),
        Text(widget.parkingName,
            style: const TextStyle(fontSize: 13, color: _kTextMid)),
        Text(widget.montantFixe != null ? 'Acompte réservation' : MockPaymentService.formaterDuree(widget.dureeMinutes),
            style: const TextStyle(fontSize: 13,
                fontWeight: FontWeight.w600, color: _kBlue)),
        const SizedBox(height: 14),
        Divider(color: _kBorder),
        const SizedBox(height: 10),
        Row(children: [
          Container(width: 36, height: 36,
              decoration: BoxDecoration(color: _kLocked,
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(_methodeIcon(state.selectedMethod),
                  color: _kBlue, size: 17)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Méthode choisie',
                style: TextStyle(fontSize: 11, color: _kTextMid)),
            Text(_methodeLabel(state.selectedMethod),
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
          const Spacer(),
          state.isProcessing
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: _kBlue))
              : const Icon(Icons.check_circle_rounded,
                  color: _kGreen, size: 20),
        ]),
        if (state.isProcessing) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
            decoration: BoxDecoration(
                color: _kLocked, borderRadius: BorderRadius.circular(12)),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center,
                children: [
              SizedBox(width: 13, height: 13,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: _kBlue)),
              SizedBox(width: 8),
              Text('En attente de validation...',
                  style: TextStyle(fontSize: 12, color: _kBlue)),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _methodSelector(PaymentState state) {
    final methods = _availableMethods;

    return Row(
      children: methods.asMap().entries.map((entry) {
        final idx = entry.key;
        final m = entry.value;
        final selected = state.selectedMethod == m;
        return Expanded(
          child: GestureDetector(
            onTap: () {
              if (state.isProcessing) return;
              HapticFeedback.selectionClick();
              _pinController.clear();
              ref.read(paymentProvider.notifier).selectMethod(m);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.only(
                left:  idx == 0 ? 0 : 6,
                right: idx == methods.length - 1 ? 0 : 6,
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: selected ? _kBlue : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? _kBlue : _kBorder,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Column(children: [
                Icon(_methodeIcon(m),
                    color: selected ? Colors.white : _kBlue, size: 20),
                const SizedBox(height: 4),
                Text(_methodeLabel(m),
                    style: TextStyle(fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : _kTextDark)),
              ]),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── PIN section — TextField réel stylisé ──────────────────
  Widget _pinSection(PaymentState state) {
    return Column(children: [
      const Text('Saisissez votre code secret',
          style: TextStyle(fontSize: 15,
              fontWeight: FontWeight.w700, color: _kTextDark)),
      const SizedBox(height: 14),

      // ── 4 cases visuelles (décoratif) ─────────────────────
      AnimatedBuilder(
        animation: _shakeAnim,
        builder: (_, child) {
          final offset = _sin(_shakeAnim.value * 3.14159 * 8) * 8;
          return Transform.translate(
              offset: Offset(offset, 0), child: child);
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (i) {
            final filled = i < _pinController.text.length;
            return GestureDetector(
              onTap: () => _pinFocus.requestFocus(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 60, height: 68,
                margin: const EdgeInsets.symmetric(horizontal: 7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: filled ? _kBlue : _kBorder,
                    width: filled ? 2 : 1.5,
                  ),
                  boxShadow: filled
                      ? [BoxShadow(color: _kBlue.withOpacity(0.10),
                          blurRadius: 8, offset: const Offset(0, 2))]
                      : null,
                ),
                child: Center(
                  child: filled
                      ? Container(width: 12, height: 12,
                          decoration: const BoxDecoration(
                              shape: BoxShape.circle, color: _kTextDark))
                      : null,
                ),
              ),
            );
          }),
        ),
      ),

      const SizedBox(height: 14),

      // ── TextField réel mais caché visuellement ─────────────
      // Opacity 0 = invisible MAIS focusable et reçoit les touches
      Opacity(
        opacity: 0,
        child: SizedBox(
          height: 1,
          child: TextField(
            controller: _pinController,
            focusNode: _pinFocus,
            keyboardType: TextInputType.numberWithOptions(decimal: false),
            maxLength: 4,
            autofocus: true,
            decoration: const InputDecoration(
              counterText: '',
              border: InputBorder.none,
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (val) {
              setState(() {});
              ref.read(paymentProvider.notifier).syncPin(val);
              if (val.length == 4) _pinFocus.unfocus();
            },
          ),
        ),
      ),

      // ── Bouton "Appuyer pour saisir" si clavier fermé ─────
      if (!_pinFocus.hasFocus && _pinController.text.length < 4)
        GestureDetector(
          onTap: () => _pinFocus.requestFocus(),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 9),
            decoration: BoxDecoration(
              color: _kLocked,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.keyboard_rounded, size: 15, color: _kTextMid),
              SizedBox(width: 6),
              Text('Appuyer pour saisir le code',
                  style: TextStyle(fontSize: 12, color: _kTextMid)),
            ]),
          ),
        ),
    ]);
  }

  Widget _cashInfo() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _kBorder),
    ),
    child: const Row(children: [
      Icon(Icons.info_outline_rounded, color: _kBlue, size: 20),
      SizedBox(width: 10),
      Expanded(child: Text(
        'Présentez votre QR code à l\'agent de caisse.\n'
        'Il validera votre sortie manuellement.',
        style: TextStyle(fontSize: 13, color: _kTextMid, height: 1.5),
      )),
    ]),
  );

  Widget _confirmButton(PaymentState state) {
    final canConfirm = (widget.allowCash && state.selectedMethod == PaymentMethod.cash)
        || _pinController.text.length == 4;

    return SizedBox(
      width: double.infinity, height: 54,
      child: ElevatedButton(
        onPressed: state.isProcessing
            ? null
            : (canConfirm
                ? () {
                    _pinFocus.unfocus();
                    ref.read(paymentProvider.notifier).confirmPayment();
                  }
                : null),
        style: ElevatedButton.styleFrom(
          backgroundColor: canConfirm ? _kBlue : _kLocked,
          foregroundColor: canConfirm ? Colors.white : _kTextMid,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (state.isProcessing)
            const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
          else
            Icon(canConfirm
                ? Icons.lock_open_rounded : Icons.lock_rounded, size: 18),
          const SizedBox(width: 8),
          Text(state.isProcessing
              ? 'Traitement...' : 'Confirmer le paiement',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 15)),
        ]),
      ),
    );
  }

  Widget _securityNote() => const Text(
    'Transaction sécurisée par Algérie Poste.\nNe partagez jamais votre code.',
    textAlign: TextAlign.center,
    style: TextStyle(fontSize: 12, color: _kTextMid, height: 1.5),
  );

  Widget _demoHint() => Container(
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: _kOrangeBg,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _kOrange.withOpacity(0.3)),
    ),
    child: Column(children: [
      Row(children: [
        const Icon(Icons.science_outlined, color: _kOrange, size: 15),
        const SizedBox(width: 6),
        const Text('Mode démo', style: TextStyle(
            fontWeight: FontWeight.w700, fontSize: 11, color: _kOrange)),
        const Spacer(),
        GestureDetector(
          onTap: () =>
              ref.read(paymentProvider.notifier).hideDemoHint(),
          child: const Icon(Icons.close, size: 15, color: _kOrange),
        ),
      ]),
      const SizedBox(height: 5),
      const Text(MockPaymentService.demoHint,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11,
              color: Color(0xFF854F0B), height: 1.5)),
    ]),
  );

  String _methodeLabel(PaymentMethod m) => switch (m) {
    PaymentMethod.edahabia => 'Edahabia',
    PaymentMethod.cib      => 'CIB',
    PaymentMethod.cash     => 'Cash',
  };

  IconData _methodeIcon(PaymentMethod m) => switch (m) {
    PaymentMethod.edahabia => Icons.credit_card_rounded,
    PaymentMethod.cib      => Icons.account_balance_rounded,
    PaymentMethod.cash     => Icons.payments_rounded,
  };
}

double _sin(double x) {
  double r = 0, t = x;
  for (int i = 1; i <= 10; i++) {
    r += t;
    t *= -x * x / ((2 * i) * (2 * i + 1));
  }
  return r;
}