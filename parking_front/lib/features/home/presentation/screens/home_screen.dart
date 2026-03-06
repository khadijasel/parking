import 'dart:async';
import 'package:flutter/material.dart';

// ─── Constantes couleurs ───────────────────────────────────────────────────────
const _kBlue       = Color(0xFF4A90E2);
const _kGreen      = Color(0xFF2ECC71);
const _kBg         = Color(0xFFF0F2F5);
const _kCard       = Colors.white;
const _kTextDark   = Color(0xFF1A1A2E);
const _kTextMid    = Color(0xFF7A8499);
const _kTextLight  = Color(0xFFB0B8CC);

// ─── Modèle session (simplifié) ────────────────────────────────────────────────
class _Session {
  final String parkingName;
  final String spotLabel;
  final DateTime entryTime;
  final double tarifActuel;
  final bool canFindCar;   // nécessite scan
  final bool canExit;      // nécessite scan
  final bool canPay;       // dispo après 1h

  const _Session({
    required this.parkingName,
    required this.spotLabel,
    required this.entryTime,
    required this.tarifActuel,
    this.canFindCar = false,
    this.canExit    = false,
    this.canPay     = false,
  });
}

// ─── HOME SCREEN ───────────────────────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Session simulée
  final _Session _session = _Session(
    parkingName: 'Parking Sidi Yahia',
    spotLabel:   'Niveau 2, A-42',
    entryTime:   DateTime.now().subtract(const Duration(minutes: 45, seconds: 12)),
    tarifActuel: 150,
  );

  late Timer _timer;
  late int _elapsedSec;

  @override
  void initState() {
    super.initState();
    _elapsedSec = DateTime.now().difference(_session.entryTime).inSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsedSec++);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  // ── helpers ────────────────────────────────────────────────────────────────
  String get _hh => (_elapsedSec ~/ 3600).toString().padLeft(2, '0');
  String get _mm => ((_elapsedSec % 3600) ~/ 60).toString().padLeft(2, '0');
  String get _ss => (_elapsedSec % 60).toString().padLeft(2, '0');

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  // ── build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 6),
              _buildSessionBadge(),
              const SizedBox(height: 20),
              _buildTimerCard(),
              const SizedBox(height: 20),
              _buildActionGrid(),
            ],
          ),
        ),
      ),
    );
  }

  // ── HEADER ─────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'STATIONNEMENT',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _kBlue,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _session.parkingName,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _kTextDark,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
        // Avatar bouton
        GestureDetector(
          onTap: () {},
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFDDE3EE),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_outline_rounded,
                color: _kBlue, size: 24),
          ),
        ),
      ],
    );
  }

  // ── SESSION BADGE ──────────────────────────────────────────────────────────
  Widget _buildSessionBadge() {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: _kGreen,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        const Text(
          'SESSION ACTIVE',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: _kGreen,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  // ── TIMER CARD ─────────────────────────────────────────────────────────────
  Widget _buildTimerCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          children: [
            // ── Digits HH:MM:SS ──────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildDigitBlock(_hh, 'HEURES'),
                _buildSeparator(),
                _buildDigitBlock(_mm, 'MINUTES'),
                _buildSeparator(),
                _buildDigitBlock(_ss, 'SECONDES'),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(color: Color(0xFFF0F2F5), thickness: 1.5),
            const SizedBox(height: 18),
            // ── Entrée + Total ────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('ENTRÉE',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _kTextMid,
                          letterSpacing: 0.8)),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(_session.entryTime),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _kTextDark,
                    ),
                  ),
                ]),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  const Text('TOTAL',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _kTextMid,
                          letterSpacing: 0.8)),
                  const SizedBox(height: 4),
                  Text(
                    '${_session.tarifActuel.toInt()} DZD',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _kTextDark,
                    ),
                  ),
                ]),
              ],
            ),
            const SizedBox(height: 18),
            const Divider(color: Color(0xFFF0F2F5), thickness: 1.5),
            const SizedBox(height: 18),
            // ── Place + Tarif ─────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Place estimée',
                      style: TextStyle(fontSize: 13, color: _kTextMid)),
                  const SizedBox(height: 3),
                  Text(
                    _session.spotLabel,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: _kTextDark,
                    ),
                  ),
                ]),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  const Text('Tarif actuel',
                      style: TextStyle(fontSize: 13, color: _kTextMid)),
                  const SizedBox(height: 3),
                  Text(
                    '${_session.tarifActuel.toInt()} DZD',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: _kBlue,
                    ),
                  ),
                ]),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDigitBlock(String value, String label) {
    return Column(
      children: [
        Container(
          width: 86,
          height: 86,
          decoration: BoxDecoration(
            color: const Color(0xFFF0F2F5),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Center(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                color: _kTextDark,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        // Underline bleue
        const SizedBox(height: 6),
        Container(
          width: 40,
          height: 3,
          decoration: BoxDecoration(
            color: _kBlue,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: _kTextMid,
                letterSpacing: 0.5)),
      ],
    );
  }

  Widget _buildSeparator() {
    return const Padding(
      padding: EdgeInsets.only(bottom: 28),
      child: Text(' : ',
          style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w300,
              color: _kTextLight)),
    );
  }

  // ── ACTION GRID ────────────────────────────────────────────────────────────
  Widget _buildActionGrid() {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.05,
      children: [
        _ActionCard(
          icon: Icons.navigation_rounded,
          title: 'Guider vers une place',
          subtitle: 'DISPONIBLE',
          isActive: true,
          locked: false,
          onTap: () {},
        ),
        _ActionCard(
          icon: Icons.directions_car_outlined,
          title: 'Trouver ma voiture',
          subtitle: 'SCANNER REQUIS',
          isActive: false,
          locked: true,
          onTap: () {},
        ),
        _ActionCard(
          icon: Icons.logout_rounded,
          title: 'Guider vers la sortie',
          subtitle: 'SCANNER REQUIS',
          isActive: false,
          locked: true,
          onTap: () {},
        ),
        _ActionCard(
          icon: Icons.credit_card_rounded,
          title: 'Payer',
          subtitle: 'DISPO APRÈS 1H',
          isActive: false,
          locked: true,
          onTap: () {},
        ),
      ],
    );
  }
}

// ─── ACTION CARD ──────────────────────────────────────────────────────────────
class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isActive;
  final bool locked;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isActive,
    required this.locked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isActive ? _kBlue : _kCard,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: isActive
                  ? _kBlue.withOpacity(0.30)
                  : Colors.black.withOpacity(0.05),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icône dans bulle
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isActive
                    ? Colors.white.withOpacity(0.20)
                    : const Color(0xFFF0F2F5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon,
                  size: 22,
                  color: isActive ? Colors.white : _kTextMid),
            ),
            const Spacer(),
            // Titre
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isActive ? Colors.white : _kTextDark,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 6),
            // Sous-titre avec icône cadenas
            Row(children: [
              if (locked)
                Icon(Icons.lock_outline_rounded,
                    size: 11,
                    color: isActive
                        ? Colors.white.withOpacity(0.7)
                        : _kTextLight),
              if (locked) const SizedBox(width: 4),
              Flexible(
                child: Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isActive
                        ? Colors.white.withOpacity(0.75)
                        : _kTextLight,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}