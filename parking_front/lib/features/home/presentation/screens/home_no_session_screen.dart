import 'package:flutter/material.dart';

const _kBg = Color(0xFFEAF1FB);
const _kBlue = Color(0xFF4A90E2);
const _kDark = Color(0xFF1A1A2E);
const _kMid = Color(0xFF8A9BB5);
const _kLight = Color(0xFFD0DDF0);

/// Accueil — pas de session active
class HomeNoSessionScreen extends StatelessWidget {
  final VoidCallback onSearchTap;
  const HomeNoSessionScreen({super.key, required this.onSearchTap});

  String get _dateLabel {
    final now = DateTime.now();
    const days = [
      'Lundi',
      'Mardi',
      'Mercredi',
      'Jeudi',
      'Vendredi',
      'Samedi',
      'Dimanche'
    ];
    const months = [
      'Janvier',
      'Février',
      'Mars',
      'Avril',
      'Mai',
      'Juin',
      'Juillet',
      'Août',
      'Septembre',
      'Octobre',
      'Novembre',
      'Décembre'
    ];
    return '${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 32),
            // Header
            RichText(
                text: const TextSpan(
              style: TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w800, color: _kDark),
              children: [TextSpan(text: 'Bonjour '), TextSpan(text: '👋')],
            )),
            const SizedBox(height: 4),
            Text(_dateLabel,
                style: const TextStyle(
                    fontSize: 15, color: _kMid, fontWeight: FontWeight.w500)),
            // Illustration
            Expanded(
              child: Center(
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: const BoxDecoration(
                      color: Color(0xFFD6E6F7), // Fond bleu clair
                      shape: BoxShape.circle),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 1. La voiture en arrière-plan (légèrement transparente)
                      Positioned(
                        bottom: 50,
                        child: Icon(Icons.directions_car,
                            size: 80, color: Colors.white.withOpacity(0.5)),
                      ),

                      // 2. Le "P" en avant-plan (INCLINÉ)
                      Positioned(
                        top: 40,
                        // 🔥 ASTUCE : On ajoute Transform.rotate ici
                        child: Transform.rotate(
                          angle:
                              -0.2, // Angle en radians (négatif = penché vers la gauche, positif = droite)
                          // -0.2 est un angle subtil et élégant (~ -11 degrés)
                          child: Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius:
                                  BorderRadius.circular(22), // Coins arrondis
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.12),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6)),
                              ],
                            ),
                            child: const Center(
                              child: Text('P',
                                  style: TextStyle(
                                      fontSize: 48,
                                      fontWeight: FontWeight.w900,
                                      color:
                                          Color(0xFF0F172A) // Ton texte foncé
                                      )),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Texte
            const Text("Où allez-vous aujourd'hui ?",
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _kDark,
                    height: 1.25)),
            const SizedBox(height: 10),
            const Text(
                'Trouvez rapidement une place de\nstationnement à Tlemcen.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: _kMid, height: 1.5)),
            const SizedBox(height: 32),
            // Bouton
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onSearchTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                  elevation: 0,
                ),
                child: const Row(children: [
                  SizedBox(width: 4),
                  Icon(Icons.search_rounded, size: 22),
                  SizedBox(width: 12),
                  Expanded(
                      child: Text('Chercher un parking',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700))),
                  Icon(Icons.chevron_right_rounded, size: 24),
                ]),
              ),
            ),
            const SizedBox(height: 32),
            const Text('ACTIONS DE SESSION',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _kMid,
                    letterSpacing: 1.2)),
            const SizedBox(height: 16),
            const Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _LockedAction(
                      icon: Icons.location_on_outlined,
                      label: 'Trouver\nvoiture'),
                  _LockedAction(icon: Icons.logout_rounded, label: 'Sortie'),
                  _LockedAction(
                      icon: Icons.credit_card_rounded, label: 'Payer'),
                ]),
            const SizedBox(height: 32),
          ]),
        ),
      ),
    );
  }
}

class _LockedAction extends StatelessWidget {
  final IconData icon;
  final String label;
  const _LockedAction({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Column(children: [
        Stack(children: [
          Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                  color: const Color(0xFFDDE8F7),
                  borderRadius: BorderRadius.circular(18)),
              child: Icon(icon, size: 28, color: _kLight)),
          Positioned(
              right: 4,
              top: 4,
              child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                      color: Color(0xFFB0C4DE), shape: BoxShape.circle),
                  child: const Icon(Icons.lock_outline_rounded,
                      size: 11, color: Colors.white))),
        ]),
        const SizedBox(height: 8),
        Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 11, color: _kMid, fontWeight: FontWeight.w500)),
      ]);
}
