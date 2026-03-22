import 'package:flutter/material.dart';
import '../../../../theme/app_colors.dart';

// ─── Constantes locales ─────────────────────────────────────────────────────
const _kBg       = Color(0xFFF4F7FC);
const _kDark     = Color(0xFF1A1A2E);
const _kMid      = Color(0xFF8A9BB5);
const _kBlue     = Color(0xFF4A90E2);
const _kGreen    = Color(0xFF2ECC71);
const _kGreenBg  = Color(0xFFE8F5E9);
const _kBlueBg   = Color(0xFFEAF1FB);

// ─── Modèle simplifié ───────────────────────────────────────────────────────
enum _SessionStatus { enCours, termine }

class _ParkingSession {
  final String parkingName;
  final String sessionId;
  final String dateHeure;
  final String duree;
  final int totalCost;
  final _SessionStatus status;

  const _ParkingSession({
    required this.parkingName,
    required this.sessionId,
    required this.dateHeure,
    required this.duree,
    required this.totalCost,
    required this.status,
  });
}

// ─── Données statiques ──────────────────────────────────────────────────────
const List<_ParkingSession> _kSessions = [
  _ParkingSession(
    parkingName: 'Place Audin',
    sessionId: 'PK-994201',
    dateHeure: "Aujourd'hui, 09:15",
    duree: '1h 45min',
    totalCost: 150,
    status: _SessionStatus.enCours,
  ),
  _ParkingSession(
    parkingName: 'Sidi Yahia Central',
    sessionId: 'PK-882910',
    dateHeure: '12 Oct 2023, 14:30',
    duree: '2h 30min',
    totalCost: 450,
    status: _SessionStatus.termine,
  ),
  _ParkingSession(
    parkingName: 'El Biar Heights',
    sessionId: 'PK-661554',
    dateHeure: '08 Oct 2023, 18:00',
    duree: '1h 00min',
    totalCost: 200,
    status: _SessionStatus.termine,
  ),
  _ParkingSession(
    parkingName: 'Bab Ezzouar Mall',
    sessionId: 'PK-110293',
    dateHeure: '05 Oct 2023, 11:45',
    duree: '4h 15min',
    totalCost: 850,
    status: _SessionStatus.termine,
  ),
];

// ─── ÉCRAN HISTORIQUE ───────────────────────────────────────────────────────
class ParkingHistoryScreen extends StatelessWidget {
  const ParkingHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<_ParkingSession> enCours = _kSessions
        .where((s) => s.status == _SessionStatus.enCours)
        .toList();
    final List<_ParkingSession> terminees = _kSessions
        .where((s) => s.status == _SessionStatus.termine)
        .toList();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _kBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: _kDark),
          ),
        ),
        centerTitle: true,
        title: const Text(
          'Historique',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _kDark),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _kBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.filter_list_rounded, size: 20, color: _kDark),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Section EN COURS ──────────────────────────────────────
            if (enCours.isNotEmpty) ...[
              const _SectionTitle(title: 'EN COURS'),
              const SizedBox(height: 12),
              ...enCours.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ActiveSessionCard(session: s),
              )),
              const SizedBox(height: 12),
            ],

            // ── Section TERMINÉES ─────────────────────────────────────
            if (terminees.isNotEmpty) ...[
              const _SectionTitle(title: 'TERMINÉES'),
              const SizedBox(height: 12),
              ...terminees.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _CompletedSessionCard(session: s),
              )),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Titre de section ───────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: _kMid,
        letterSpacing: 1.2,
      ),
    );
  }
}

// ─── Carte session EN COURS ─────────────────────────────────────────────────
class _ActiveSessionCard extends StatelessWidget {
  final _ParkingSession session;
  const _ActiveSessionCard({required this.session});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBlue.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _kBlue.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header : icône P + nom + badge
          Row(
            children: [
              _buildParkingIcon(isActive: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.parkingName,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _kDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ID: ${session.sessionId}',
                      style: const TextStyle(fontSize: 13, color: _kMid),
                    ),
                  ],
                ),
              ),
              _buildBadge('EN COURS', _kBlue, _kBlueBg),
            ],
          ),
          const SizedBox(height: 18),
          // Début + Durée
          Row(
            children: [
              _buildInfoColumn('DÉBUT', session.dateHeure),
              const SizedBox(width: 40),
              _buildInfoColumn('DURÉE ACTUELLE', session.duree, valueColor: _kBlue),
            ],
          ),
          const SizedBox(height: 14),
          // Coût + bouton Gérer
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'COÛT ACTUEL',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _kMid,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${session.totalCost} DA',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: _kDark,
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('Gérer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Carte session TERMINÉE ─────────────────────────────────────────────────
class _CompletedSessionCard extends StatelessWidget {
  final _ParkingSession session;
  const _CompletedSessionCard({required this.session});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header : icône P + nom + badge
          Row(
            children: [
              _buildParkingIcon(isActive: false),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.parkingName,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _kDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ID: ${session.sessionId}',
                      style: const TextStyle(fontSize: 13, color: _kMid),
                    ),
                  ],
                ),
              ),
              _buildBadge('TERMINÉ', _kGreen, _kGreenBg),
            ],
          ),
          const SizedBox(height: 16),
          // Date + Durée
          Row(
            children: [
              _buildInfoColumn('DATE & HEURE', session.dateHeure),
              const SizedBox(width: 40),
              _buildInfoColumn('DURÉE', session.duree),
            ],
          ),
          const SizedBox(height: 14),
          // Total cost
          const Text(
            'TOTAL COST',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _kMid,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${session.totalCost} DA',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: _kBlue,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Helpers partagés ───────────────────────────────────────────────────────
Widget _buildParkingIcon({required bool isActive}) {
  return Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      color: isActive ? _kBlueBg : _kBg,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Center(
      child: Text(
        'P',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w900,
          color: isActive ? _kBlue : _kMid,
        ),
      ),
    ),
  );
}

Widget _buildBadge(String text, Color color, Color bgColor) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 0.3,
      ),
    ),
  );
}

Widget _buildInfoColumn(String label, String value, {Color? valueColor}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: _kMid,
          letterSpacing: 0.5,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: valueColor ?? _kDark,
        ),
      ),
    ],
  );
}
