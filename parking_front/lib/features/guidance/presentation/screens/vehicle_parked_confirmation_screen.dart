import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ════════════════════════════════════════════════════════════
//  VEHICLE PARKED CONFIRMATION  — Image 2
//  "Véhicule garé !" — après que l'utilisateur clique Arrivé
// ════════════════════════════════════════════════════════════

const _kBg = Color(0xFFF0F4FA);
const _kGreen = Color(0xFF2ECC71);
const _kBlue = Color(0xFF4A90E2);
const _kDark = Color(0xFF1A1A2E);
const _kMid = Color(0xFF8A9BB5);
const _kBorder = Color(0xFFE2ECF9);

class VehicleParkedConfirmationScreen extends StatelessWidget {
  final String spotLabel;
  final String floor;

  const VehicleParkedConfirmationScreen({
    super.key,
    this.spotLabel = 'B2',
    this.floor = 'Niveau -1',
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
          onTap: () => Navigator.pop(context, true),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.06), blurRadius: 8)
              ],
            ),
            child:
                const Icon(Icons.arrow_back_rounded, color: _kDark, size: 20),
          ),
        ),
        title: const Text('Confirmation',
            style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 18, color: _kDark)),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(children: [
          const Spacer(),

          // ── Check animé ─────────────────────────────────
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 700),
            curve: Curves.elasticOut,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: _kGreen.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: const BoxDecoration(
                    color: _kGreen,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: Colors.white, size: 38),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),
          const Text('Véhicule garé !',
              style: TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w800, color: _kDark)),
          const SizedBox(height: 8),
          const Text(
            'Votre stationnement a bien été\nenregistré avec succès.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: _kMid, height: 1.5),
          ),

          const SizedBox(height: 32),

          // ── Carte détails ────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 4))
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('DÉTAILS DU STATIONNEMENT',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _kMid,
                        letterSpacing: 1.0)),
                const SizedBox(height: 16),
                _detailRow(
                  icon: Icons.location_on_outlined,
                  label: 'Emplacement',
                  value: 'Place $spotLabel',
                ),
                const Divider(color: _kBorder, height: 24),
                _detailRow(
                  icon: Icons.layers_outlined,
                  label: 'Niveau',
                  value: floor,
                ),
              ],
            ),
          ),

          const Spacer(),

          // ── Bouton retour accueil ────────────────────────
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: () {
                HapticFeedback.mediumImpact();
                Navigator.pop(context, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _kBlue,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              icon:
                  const Icon(Icons.home_rounded, color: Colors.white, size: 22),
              label: const Text("Retour à l'accueil",
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _detailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: const Color(0xFFEAF1FB),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: _kBlue, size: 20),
      ),
      const SizedBox(width: 14),
      Text(label, style: const TextStyle(fontSize: 15, color: _kMid)),
      const Spacer(),
      Text(value,
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w800, color: _kDark)),
    ]);
  }
}
