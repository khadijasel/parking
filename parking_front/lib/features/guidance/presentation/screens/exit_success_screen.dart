import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ════════════════════════════════════════════════════════════
//  EXIT SUCCESS SCREEN  — Image 6
//  "Sortie réussie" — Merci + notation étoiles
// ════════════════════════════════════════════════════════════

const _kBg = Color(0xFFF4F6FA);
const _kBlue = Color(0xFF4A90E2);
const _kGreen = Color(0xFF2ECC71);
const _kDark = Color(0xFF1A1A2E);
const _kMid = Color(0xFF8A9BB5);

class ExitSuccessScreen extends StatefulWidget {
  final String? parkingId;
  const ExitSuccessScreen({super.key, this.parkingId});

  @override
  State<ExitSuccessScreen> createState() => _ExitSuccessScreenState();
}

class _ExitSuccessScreenState extends State<ExitSuccessScreen>
    with SingleTickerProviderStateMixin {
  int _rating = 4; // note actuelle (1 à 5)

  late AnimationController _scaleCtrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
    _scaleAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _scaleCtrl, curve: Curves.elasticOut));
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  void _submitRating() {
    HapticFeedback.mediumImpact();
    // → API PUT /parkings/{id}/rating
    Navigator.popUntil(context, (r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(children: [
            // ── Bouton fermer ──────────────────────────────
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () => Navigator.popUntil(context, (r) => r.isFirst),
                child: const Icon(Icons.close_rounded, color: _kMid, size: 24),
              ),
            ),
            const SizedBox(height: 4),
            const Text('Sortie réussie',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: _kDark)),

            const Spacer(),

            // ── Icône voiture + check ──────────────────────
            AnimatedBuilder(
              animation: _scaleAnim,
              builder: (_, child) =>
                  Transform.scale(scale: _scaleAnim.value, child: child),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: _kBlue.withOpacity(0.10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.directions_bus_rounded,
                      color: _kBlue,
                      size: 54,
                    ),
                  ),
                  // Badge check vert
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: _kGreen,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            const Text('Merci de votre visite',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: _kDark)),
            const SizedBox(height: 8),
            const Text('Au revoir et à bientôt !',
                style: TextStyle(fontSize: 15, color: _kMid)),

            const Spacer(),

            // ── Notation étoiles ───────────────────────────
            const Text('Notez votre expérience',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: _kDark)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final filled = i < _rating;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _rating = i + 1);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      filled ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: filled
                          ? const Color(0xFFF5A623)
                          : const Color(0xFFD0DCF0),
                      size: filled ? 46 : 42,
                    ),
                  ),
                );
              }),
            ),

            const SizedBox(height: 32),

            // ── Bouton retour accueil ─────────────────────
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _submitRating,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kBlue,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                ),
                icon: const Icon(Icons.home_rounded,
                    color: Colors.white, size: 22),
                label: const Text("Retour à l'accueil",
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
