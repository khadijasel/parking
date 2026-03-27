import 'package:flutter/material.dart';
import 'package:parking_front/features/parking/presentation/map_home_screen.dart';
import '../../data/mock_payment_service.dart';

const _kBlue     = Color(0xFF4A90E2);
const _kGreen    = Color(0xFF2ECC71);
const _kBg       = Color(0xFFEAF1FB);
const _kBorder   = Color(0xFFE2ECF9);
const _kLocked   = Color(0xFFDDE8F7);
const _kTextDark = Color(0xFF1A1A2E);
const _kTextMid  = Color(0xFF8A9BB5);

// ════════════════════════════════════════════════════════════
//  PAYMENT CONFIRMATION SCREEN
// ════════════════════════════════════════════════════════════

class PaymentConfirmationScreen extends StatelessWidget {
  final PaymentTransaction transaction;

  const PaymentConfirmationScreen({
    super.key,
    required this.transaction,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: _appBar(context),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(children: [
          const Spacer(),

          // ── Check animé ──────────────────────────────────
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 700),
            curve: Curves.elasticOut,
            builder: (_, v, child) =>
                Transform.scale(scale: v, child: child),
            child: Container(
              width: 92, height: 92,
              decoration: BoxDecoration(
                  color: _kGreen.withOpacity(0.10),
                  shape: BoxShape.circle),
              child: Center(
                child: Container(
                  width: 68, height: 68,
                  decoration: BoxDecoration(
                      color: _kGreen.withOpacity(0.18),
                      shape: BoxShape.circle),
                  child: Icon(Icons.check_circle_outline_rounded,
                      color: _kGreen, size: 44),
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),
          const Text('Paiement réussi !',
              style: TextStyle(fontSize: 26,
                  fontWeight: FontWeight.w800, color: _kTextDark)),
          const SizedBox(height: 6),
          const Text('Votre transaction a été traitée avec succès.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: _kTextMid)),
          const SizedBox(height: 24),

          // ── Reçu ─────────────────────────────────────────
          _receipt(),

          const Spacer(),

          // ── Bouton "Guider vers la sortie" ────────────────
          // Remplacer le body quand GuidanceScreen sera créé :
          // Navigator.pushReplacement(context,
          //   MaterialPageRoute(builder: (_) => GuidanceScreen()));
          SizedBox(
            width: double.infinity, height: 56,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MapHomeScreen(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _kBlue, elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
              ),
              icon: const Icon(Icons.meeting_room_outlined,
                  color: Colors.white, size: 20),
              label: const Text('Guider vers la sortie',
                  style: TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
          const SizedBox(height: 12),

          // ── Bouton "Retour à l'accueil" ───────────────────
          SizedBox(
            width: double.infinity, height: 52,
            child: OutlinedButton(
              onPressed: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const MapHomeScreen()),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _kBorder),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
              ),
              child: const Text("Retour à l'accueil",
                  style: TextStyle(fontWeight: FontWeight.w600,
                      color: _kTextDark)),
            ),
          ),
        ]),
      ),
    );
  }

  AppBar _appBar(BuildContext context) => AppBar(
    backgroundColor: _kBg,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    automaticallyImplyLeading: false,
    leading: Padding(
      padding: const EdgeInsets.all(8),
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          decoration: BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.arrow_back_rounded,
              size: 20, color: _kTextDark),
        ),
      ),
    ),
    title: const Text('Confirmation',
        style: TextStyle(fontWeight: FontWeight.w700,
            fontSize: 18, color: _kTextDark)),
    centerTitle: true,
  );

  Widget _receipt() {
    return Container(
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(22)),
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        Row(children: [
          Container(width: 46, height: 46,
              decoration: BoxDecoration(color: _kLocked,
                  borderRadius: BorderRadius.circular(13)),
              child: const Center(child: Text('P', style: TextStyle(
                  fontWeight: FontWeight.w800, color: _kBlue, fontSize: 18)))),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Parking',
                style: TextStyle(fontSize: 12, color: _kTextMid)),
            Text(transaction.parkingName,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15)),
          ]),
        ]),
        const SizedBox(height: 16),
        Divider(color: _kBorder),
        _row('Statut',         null,    badge: 'PAYÉ'),
        _row('ID Transaction', '#${transaction.transactionRef}'),
        _row('Durée', MockPaymentService.formaterDuree(transaction.dureeMinutes)),
        _row('Méthode',
            transaction.methode.name[0].toUpperCase() +
            transaction.methode.name.substring(1)),
        _row('Total', '${transaction.montant.toInt()} DA', isTotal: true),
      ]),
    );
  }

  Widget _row(String label, String? value,
      {String? badge, bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Text(label, style: const TextStyle(fontSize: 14, color: _kTextMid)),
        const Spacer(),
        if (badge != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _kGreen.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(badge, style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: _kGreen)),
          )
        else
          Text(value ?? '', style: TextStyle(
            fontSize: isTotal ? 17 : 14,
            fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600,
            color: isTotal ? _kBlue : _kTextDark,
          )),
      ]),
    );
  }
}