import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:parking_front/features/payment/presentation/screens/payment_screen.dart';

// ════════════════════════════════════════════════════════════
//  VEHICLE FOUND SCREEN  — Image 3
//  "Véhicule retrouvé !" — après scan QR / confirmation
//  Boutons : Payer | Retour à l'accueil
// ════════════════════════════════════════════════════════════

const _kBg = Color(0xFFF0F4FA);
const _kBlue = Color(0xFF4A90E2);
const _kDark = Color(0xFF1A1A2E);
const _kMid = Color(0xFF8A9BB5);
const _kCard = Colors.white;

class VehicleFoundScreen extends StatelessWidget {
  final String spotLabel;
  final String floor;
  final String reservationId;
  final String parkingName;
  final int dureeMinutes;

  const VehicleFoundScreen({
    super.key,
    this.spotLabel = 'B2',
    this.floor = 'Niveau -1',
    this.reservationId = '',
    this.parkingName = 'Notre parking',
    this.dureeMinutes = 90,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                const Icon(Icons.arrow_back_rounded, color: _kDark, size: 20),
          ),
        ),
        title: const Text('Parking',
            style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 18, color: _kDark)),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(children: [
          const Spacer(),

          // ── Check + titre ────────────────────────────────
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _kBlue.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_outline_rounded,
                  color: _kBlue, size: 44),
            ),
          ),
          const SizedBox(height: 14),
          const Text('SUCCES',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF4A90E2),
                  letterSpacing: 2)),
          const SizedBox(height: 8),
          const Text('Véhicule retrouvé !',
              style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w800, color: _kDark)),
          const SizedBox(height: 6),
          const Text('Session de stationnement terminée',
              style: TextStyle(fontSize: 13, color: _kMid)),

          const SizedBox(height: 24),

          // ── Carte avec photo + infos ─────────────────────
          Container(
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4))
              ],
            ),
            child: Column(children: [
              // Photo parking (vue de dessus)
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                child: Container(
                  height: 170,
                  color: const Color(0xFF2D3748),
                  child: Stack(children: [
                    // Simule une vue aérienne de parking
                    CustomPaint(
                      size: const Size(double.infinity, 170),
                      painter: _ParkingTopViewPainter(),
                    ),
                  ]),
                ),
              ),
              // Infos
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Expanded(child: _infoBox('EMPLACEMENT', 'Place $spotLabel')),
                  const SizedBox(width: 12),
                  Expanded(child: _infoBox('NIVEAU', floor)),
                ]),
              ),
            ]),
          ),

          const Spacer(),

          // ── Bouton Payer ─────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: () {
                HapticFeedback.mediumImpact();
                if (reservationId.trim().isEmpty) {
                  Navigator.popUntil(context, (r) => r.isFirst);
                  return;
                }

                Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PaymentScreen(
                        reservationId: reservationId,
                        parkingName: parkingName,
                        dureeMinutes: dureeMinutes,
                      ),
                    ));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _kBlue,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              icon: const Icon(Icons.payment_rounded,
                  color: Colors.white, size: 22),
              label: const Text('Payer',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
            ),
          ),
          const SizedBox(height: 12),

          // ── Bouton Retour accueil ─────────────────────────
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFE2ECF9)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text("Retour à l'accueil",
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _kDark,
                      fontSize: 15)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _infoBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6FA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _kMid,
                letterSpacing: 0.8)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: _kDark)),
      ]),
    );
  }
}

// ── Vue aérienne parking (dessinée) ──────────────────────────
class _ParkingTopViewPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF3A4557);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bg);

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..strokeWidth = 1;

    // Lignes de délimitation des places
    for (int i = 0; i < 5; i++) {
      final x = size.width * 0.1 + i * (size.width * 0.08);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
    for (int i = 0; i < 5; i++) {
      final x = size.width * 0.58 + i * (size.width * 0.08);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }

    // Allée centrale
    final aisle = Paint()..color = const Color(0xFF4A5568);
    canvas.drawRect(
        Rect.fromLTWH(size.width * 0.42, 0, size.width * 0.16, size.height),
        aisle);

    // Voitures gauche (gris foncé)
    final carPaint = Paint()..color = const Color(0xFF5A6A80);
    for (int i = 0; i < 3; i++) {
      final y = size.height * 0.15 + i * (size.height * 0.28);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(
                  size.width * 0.04, y, size.width * 0.35, size.height * 0.20),
              const Radius.circular(4)),
          carPaint);
    }
    // Voiture rouge (la voiture de l'utilisateur)
    final redPaint = Paint()..color = const Color(0xFFE53935);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(size.width * 0.62, size.height * 0.15,
                size.width * 0.32, size.height * 0.22),
            const Radius.circular(4)),
        redPaint);
    // Autres voitures droite
    for (int i = 1; i < 3; i++) {
      final y = size.height * 0.15 + i * (size.height * 0.28);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(
                  size.width * 0.62, y, size.width * 0.32, size.height * 0.20),
              const Radius.circular(4)),
          carPaint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
