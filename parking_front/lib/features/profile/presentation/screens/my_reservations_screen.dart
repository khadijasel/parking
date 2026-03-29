import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../parking/presentation/parking_detail_screen.dart';
import '../../../parking/data/parking_data.dart';

// ════════════════════════════════════════════════════════════
//  MY RESERVATIONS SCREEN
// ════════════════════════════════════════════════════════════

const _kBlue = Color(0xFF4A90E2);
const _kBg = Color(0xFFF4F6F9);
const _kCard = Colors.white;
const _kBorder = Color(0xFFE8ECF2);
const _kTextDark = Color(0xFF1A1A2E);
const _kTextMid = Color(0xFF8A9BB5);
const _kRed = Color(0xFFE53935);
const _kRedBg = Color(0xFFFFF0EE);

// ── Modèle réservation ────────────────────────────────────────────────────────
enum ReservationStatus { active, terminated }
enum ReservationType { mensuel, hebdomadaire, journalier, courteDuree }

class ReservationModel {
  final String id;
  final String parkingName;
  final String spotLabel;
  final String location;
  final ReservationType type;
  final ReservationStatus status;
  final double montant;
  final DateTime? expiresAt;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? imagePath;

  const ReservationModel({
    required this.id,
    required this.parkingName,
    required this.spotLabel,
    required this.location,
    required this.type,
    required this.status,
    required this.montant,
    this.expiresAt,
    this.startDate,
    this.endDate,
    this.imagePath,
  });
}

// ── Données de test ───────────────────────────────────────────────────────────
final _mockReservations = [
  ReservationModel(
    id: 'R001',
    parkingName: 'Parking Centre-Ville',
    spotLabel: 'Place A-12 • Niveau 1',
    location: 'Tlemcen-Algérie',
    type: ReservationType.courteDuree,
    status: ReservationStatus.active,
    montant: 300,
    expiresAt: DateTime.now().add(const Duration(minutes: 28, seconds: 45)),
  ),
  ReservationModel(
    id: 'R002',
    parkingName: 'Parking Grande Poste',
    spotLabel: 'Abonnement Mensuel • Octobre 2023',
    location: 'Alger-Algérie',
    type: ReservationType.mensuel,
    status: ReservationStatus.terminated,
    montant: 4500,
    startDate: DateTime(2023, 10, 1),
    endDate: DateTime(2023, 10, 31),
  ),
  ReservationModel(
    id: 'R003',
    parkingName: 'Parking Aéroport Houari Boumédiène',
    spotLabel: 'Abonnement Hebdomadaire • Sem. 41',
    location: 'Alger-Algérie',
    type: ReservationType.hebdomadaire,
    status: ReservationStatus.terminated,
    montant: 1200,
    startDate: DateTime(2023, 10, 9),
    endDate: DateTime(2023, 10, 15),
  ),
];

// ════════════════════════════════════════════════════════════
//  SCREEN
// ════════════════════════════════════════════════════════════

class MyReservationsScreen extends StatefulWidget {
  const MyReservationsScreen({super.key});

  @override
  State<MyReservationsScreen> createState() => _MyReservationsScreenState();
}

class _MyReservationsScreenState extends State<MyReservationsScreen> {
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  List<ReservationModel> get _active => _mockReservations
      .where((r) => r.status == ReservationStatus.active)
      .toList();

  List<ReservationModel> get _terminated => _mockReservations
      .where((r) => r.status == ReservationStatus.terminated)
      .toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _kBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.arrow_back_rounded,
                size: 20, color: _kTextDark),
          ),
        ),
        title: const Text('Mes Réservations',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: _kTextDark)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (_active.isNotEmpty) ...[
            _sectionTitle('RÉSERVATIONS EN COURS'),
            const SizedBox(height: 10),
            ..._active.map((r) => _ActiveCard(reservation: r)),
            const SizedBox(height: 20),
          ],
          if (_terminated.isNotEmpty) ...[
            _sectionTitle('RÉSERVATIONS TERMINÉES'),
            const SizedBox(height: 10),
            ..._terminated.map((r) => _TerminatedCard(reservation: r)),
          ],
          if (_active.isEmpty && _terminated.isEmpty) _emptyState(),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _kTextMid,
          letterSpacing: 1.2,
        ),
      );

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 80),
          child: Column(children: [
            Icon(Icons.bookmark_border_rounded,
                size: 64, color: _kTextMid.withOpacity(0.4)),
            const SizedBox(height: 16),
            const Text('Aucune réservation',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: _kTextMid)),
            const SizedBox(height: 6),
            const Text('Vos réservations apparaîtront ici.',
                style: TextStyle(fontSize: 13, color: _kTextMid)),
          ]),
        ),
      );
}

// ════════════════════════════════════════════════════════════
//  CARTE RÉSERVATION ACTIVE
// ════════════════════════════════════════════════════════════

class _ActiveCard extends StatelessWidget {
  final ReservationModel reservation;
  const _ActiveCard({required this.reservation});

  Duration get _remaining {
    if (reservation.expiresAt == null) return Duration.zero;
    final diff = reservation.expiresAt!.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final rem = _remaining;
    final hh = _pad(rem.inHours);
    final mm = _pad(rem.inMinutes.remainder(60));
    final ss = _pad(rem.inSeconds.remainder(60));
    final expired = rem == Duration.zero;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── En-tête parking ──────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 64,
                    height: 64,
                    color: const Color(0xFF2D3748),
                    child: const Icon(Icons.local_parking_rounded,
                        color: Colors.white, size: 32),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(reservation.parkingName,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: _kTextDark)),
                        const SizedBox(height: 2),
                        Text(reservation.spotLabel,
                            style: const TextStyle(
                                fontSize: 12, color: _kTextMid)),
                        const SizedBox(height: 4),
                        Row(children: [
                          const Icon(Icons.location_on_outlined,
                              size: 13, color: _kBlue),
                          const SizedBox(width: 3),
                          Text(reservation.location,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: _kBlue,
                                  fontWeight: FontWeight.w500)),
                        ]),
                      ]),
                ),
              ]),
        ),

        // ── Compte à rebours ──────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1FB),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    expired ? 'GARANTIE EXPIRÉE' : 'GARANTIE 30 MIN',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: expired ? _kRed : _kBlue,
                      letterSpacing: 0.8,
                    ),
                  ),
                  Icon(Icons.timer_outlined,
                      size: 18, color: expired ? _kRed : _kBlue),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _timeBlock(hh, 'HEURES'),
                  _colon(),
                  _timeBlock(mm, 'MIN'),
                  _colon(),
                  _timeBlock(ss, 'SEC'),
                ],
              ),
            ]),
          ),
        ),

        // ── Boutons Annuler / Détails ─────────────────────────
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _confirmCancel(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kBlue,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 16),
                label: const Text('Annuler',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                // ✅ CORRECTION : ouvre ParkingDetailScreen SANS bouton Réserver
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ParkingDetailScreen(
                        parking: ParkingData.parkings.first,
                        isAuthenticated: true,
                        hideReserveButton: true, // ← cache le bouton Réserver
                      ),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _kBorder),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.info_outline_rounded,
                    color: _kTextMid, size: 16),
                label: const Text('Détails',
                    style: TextStyle(
                        color: _kTextDark,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _timeBlock(String val, String label) {
    return Column(children: [
      Container(
        width: 62,
        height: 50,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(val,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _kTextDark,
                  fontFeatures: [FontFeature.tabularFigures()])),
        ),
      ),
      const SizedBox(height: 4),
      Text(label,
          style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: _kTextMid,
              letterSpacing: 0.5)),
    ]);
  }

  Widget _colon() => const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: Text(' : ',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w300,
                color: _kTextMid)),
      );

  void _confirmCancel(BuildContext context) {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
                color: _kRedBg,
                borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.cancel_outlined,
                color: _kRed, size: 28),
          ),
          const SizedBox(height: 14),
          const Text('Annuler la réservation ?',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _kTextDark)),
          const SizedBox(height: 8),
          const Text(
            'Cette action est irréversible.\nVotre place sera libérée.',
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 13, color: _kTextMid, height: 1.5),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _kBorder),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Non, garder',
                    style: TextStyle(
                        color: _kTextDark,
                        fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  // → API DELETE /reservations/{id}
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kRed,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Oui, annuler',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  CARTE RÉSERVATION TERMINÉE
// ════════════════════════════════════════════════════════════

class _TerminatedCard extends StatelessWidget {
  final ReservationModel reservation;
  const _TerminatedCard({required this.reservation});

  String _fmt(DateTime? dt) {
    if (dt == null) return '';
    return 'Du ${dt.day.toString().padLeft(2, '0')} '
        '${_monthFr(dt.month)}. ${dt.year}';
  }

  String _fmtEnd(DateTime? dt) {
    if (dt == null) return '';
    return 'au ${dt.day.toString().padLeft(2, '0')} '
        '${_monthFr(dt.month)}. ${dt.year}';
  }

  String _monthFr(int m) => const [
        '',
        'Jan',
        'Fév',
        'Mar',
        'Avr',
        'Mai',
        'Jun',
        'Jul',
        'Aoû',
        'Sep',
        'Oct',
        'Nov',
        'Déc'
      ][m];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF1FB),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Center(
            child: Text('P',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: _kBlue,
                    fontSize: 18)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(reservation.parkingName,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _kTextDark)),
                const SizedBox(height: 3),
                Text(reservation.spotLabel,
                    style: const TextStyle(
                        fontSize: 12, color: _kTextMid)),
                const SizedBox(height: 3),
                Text(
                  '${_fmt(reservation.startDate)} ${_fmtEnd(reservation.endDate)}',
                  style: const TextStyle(fontSize: 11, color: _kTextMid),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(reservation.montant).toStringAsFixed(2).replaceAll('.', ',')} DA',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _kTextDark),
                ),
              ]),
        ),
      ]),
    );
  }
}