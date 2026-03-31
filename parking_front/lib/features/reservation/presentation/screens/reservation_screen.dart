import 'package:flutter/material.dart';
import 'package:parking_front/features/payment/presentation/screens/payment_screen.dart';
import 'package:parking_front/features/profile/presentation/screens/my_reservations_screen.dart';
import 'package:parking_front/features/reservation/data/reservation_repository.dart';

const _kBlue     = Color(0xFF4A90E2);
const _kDark     = Color(0xFF1A1A2E);
const _kMid      = Color(0xFF8A9BB5);
const _kOrange   = Color(0xFFF5A623);
const _kOrangeBg = Color(0xFFFFF8EC);
const _kGreen    = Color(0xFF27AE60);
const _kBorder   = Color(0xFFE2ECF9);

enum _DurationType { courte, journee, semaine, mois }

class ReservationScreen extends StatefulWidget {
  final String parkingName;
  final String parkingAddress;
  final List<String> equipments;

  const ReservationScreen({
    super.key,
    this.parkingName    = 'Parking Didouche Mourad',
    this.parkingAddress = 'Alger Centre, Alger',
    this.equipments     = const ['GPL', 'SÉCURITÉ', 'HANDI'],
  });

  @override
  State<ReservationScreen> createState() => _ReservationScreenState();
}

class _ReservationScreenState extends State<ReservationScreen> {
  _DurationType _selected = _DurationType.courte;
  final ReservationRepository _reservationRepository = ReservationRepository();
  bool _isSubmitting = false;

  bool get _isCourte => _selected == _DurationType.courte;

  final List<_DurationOption> _options = const [
    _DurationOption(
      type     : _DurationType.courte,
      icon     : Icons.access_time_rounded,
      label    : 'Courte durée',
      sublabel : 'Facturation horaire',
      price    : '100 DA',
      unit     : '/ HEURE',
    ),
    _DurationOption(
      type     : _DurationType.journee,
      icon     : Icons.calendar_today_rounded,
      label    : 'Journée',
      sublabel : 'Forfait complet',
      price    : '800 DA',
      unit     : '/ JOUR',
    ),
    _DurationOption(
      type     : _DurationType.semaine,
      icon     : Icons.date_range_rounded,
      label    : 'Semaine',
      sublabel : 'Pass hebdomadaire',
      price    : '4,500 DA',
      unit     : '/ SEMAINE',
    ),
    _DurationOption(
      type     : _DurationType.mois,
      icon     : Icons.calendar_month_rounded,
      label    : 'Mois',
      sublabel : 'Abonnement',
      price    : '15,000 DA',
      unit     : '/ MOIS',
    ),
  ];

  Future<void> _handleConfirm() async {
    if (_isSubmitting) {
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final reservation = await _reservationRepository.createReservation(
        parkingName: widget.parkingName,
        parkingAddress: widget.parkingAddress,
        equipments: widget.equipments,
        durationType: _selected.name,
        durationMinutes: _durationMinutes(_selected),
        amount: _amountFor(_selected),
        depositAmount: _isCourte ? 0 : 200,
      );

      if (!mounted) {
        return;
      }

      if (_isCourte) {
      // ── Courte durée : redirection directe vers Mes Réservations ──
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const MyReservationsScreen(),
        ),
      );
      } else {
      // ── Longue durée : paiement puis redirection Mes Réservations ──
      final bool? paymentConfirmed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentScreen(
            reservationId: reservation.id,
            parkingName:  widget.parkingName,
            dureeMinutes: reservation.durationMinutes,
            montantFixe: 200.0,  // acompte fixe réservation longue durée
            allowCash: false,
            returnToCallerOnSuccess: true,
          ),
        ),
      );

      if (!mounted || paymentConfirmed != true) {
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const MyReservationsScreen(),
        ),
      );
    }
    } on ReservationException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur lors de la reservation. Veuillez reessayer.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  int _durationMinutes(_DurationType type) {
    switch (type) {
      case _DurationType.courte:
        return 30;
      case _DurationType.journee:
        return 24 * 60;
      case _DurationType.semaine:
        return 7 * 24 * 60;
      case _DurationType.mois:
        return 30 * 24 * 60;
    }
  }

  double _amountFor(_DurationType type) {
    switch (type) {
      case _DurationType.courte:
        return 0;
      case _DurationType.journee:
        return 800;
      case _DurationType.semaine:
        return 4500;
      case _DurationType.mois:
        return 15000;
    }
  }

  IconData _equipIcon(String eq) {
    switch (eq.toUpperCase()) {
      case 'GPL'      : return Icons.local_gas_station_outlined;
      case 'SÉCURITÉ' :
      case 'SECURITE' : return Icons.shield_outlined;
      case 'HANDI'    : return Icons.accessible_rounded;
      default          : return Icons.check_circle_outline;
    }
  }

  Color _equipColor(String eq) {
    switch (eq.toUpperCase()) {
      case 'GPL'      : return _kGreen;
      case 'SÉCURITÉ' :
      case 'SECURITE' : return _kBlue;
      case 'HANDI'    : return _kOrange;
      default          : return _kMid;
    }
  }

  @override
  Widget build(BuildContext context) {
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
              color: const Color(0xFFF0F4FA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 18, color: _kDark),
          ),
        ),
        centerTitle: true,
        title: const Text('Réservation',
            style: TextStyle(fontSize: 18,
                fontWeight: FontWeight.w700, color: _kDark)),
      ),
      body: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [

              // ── Nom parking ────────────────────────────────
              Text(widget.parkingName,
                  style: const TextStyle(fontSize: 22,
                      fontWeight: FontWeight.w800, color: _kDark)),
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.location_on_outlined,
                    size: 15, color: _kMid),
                const SizedBox(width: 4),
                Text(widget.parkingAddress,
                    style: const TextStyle(fontSize: 13, color: _kMid)),
              ]),
              const SizedBox(height: 16),

              // ── Chips équipements ──────────────────────────
              Wrap(
                spacing: 8, runSpacing: 8,
                children: widget.equipments.map((eq) => Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: _kBorder, width: 1.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_equipIcon(eq), size: 14, color: _equipColor(eq)),
                    const SizedBox(width: 5),
                    Text(eq, style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600,
                        color: _kDark)),
                  ]),
                )).toList(),
              ),
              const SizedBox(height: 20),

              // ── Bannière garantie 30 min ───────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF4A90E2), Color(0xFF6BA8F0)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(children: [
                  Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      Text('30', style: TextStyle(fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Colors.white)),
                      Text('MIN', style: TextStyle(fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: Colors.white70)),
                    ]),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Place garantie',
                          style: TextStyle(fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                      SizedBox(height: 4),
                      Text(
                          'Votre emplacement est réservé\n'
                          'gratuitement pendant 30 minutes.',
                          style: TextStyle(fontSize: 12,
                              color: Colors.white70, height: 1.4)),
                    ]),
                  ),
                  const Icon(Icons.local_parking_rounded,
                      size: 52, color: Colors.white24),
                ]),
              ),
              const SizedBox(height: 14),

              // ── Avertissement annulation 30 min ───────────
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _kOrangeBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: _kOrange.withOpacity(0.25)),
                ),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Icon(Icons.access_alarm_rounded,
                      color: _kOrange, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: RichText(text: TextSpan(
                    style: const TextStyle(fontSize: 13,
                        color: _kDark, height: 1.4),
                    children: [
                      const TextSpan(text: 'Attention : '),
                      const TextSpan(
                          text: 'Passé le délai de 30 min, la réservation sera '),
                      TextSpan(
                          text: 'annulée automatiquement.',
                          style: TextStyle(color: _kOrange,
                              fontWeight: FontWeight.w700)),
                    ],
                  ))),
                ]),
              ),
              const SizedBox(height: 24),

              // ── Sélection durée ────────────────────────────
              const Text('Sélectionner la durée',
                  style: TextStyle(fontSize: 18,
                      fontWeight: FontWeight.w800, color: _kDark)),
              const SizedBox(height: 14),
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 12, mainAxisSpacing: 12,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.05,
                children: _options.map((opt) => _DurationCard(
                  option  : opt,
                  selected: _selected == opt.type,
                  onTap   : () => setState(() => _selected = opt.type),
                )).toList(),
              ),

              // ── Info acompte si longue durée ──────────────
              if (!_isCourte) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _kBlue.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: _kBlue.withOpacity(0.2)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.info_outline_rounded,
                        color: _kBlue, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: RichText(text: const TextSpan(
                        style: TextStyle(fontSize: 13,
                            color: _kDark, height: 1.4),
                        children: [
                          TextSpan(text: 'Acompte de '),
                          TextSpan(text: '200 DA ',
                              style: TextStyle(
                                  color: _kBlue,
                                  fontWeight: FontWeight.w700)),
                          TextSpan(
                              text: 'requis pour garantir votre place.'
                                  ' Vous choisirez la méthode de paiement à l\'étape suivante.'),
                        ],
                      )),
                    ),
                  ]),
                ),
              ],
            ]),
          ),
        ),

        // ── Bouton confirmation ────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.06),
                  blurRadius: 12, offset: const Offset(0, -4)),
            ],
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _handleConfirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
                elevation: 0,
              ),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                if (_isSubmitting) ...[
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Text(
                  _isSubmitting
                      ? 'Traitement...'
                      : _isCourte
                      ? 'Confirmer la réservation'
                      : 'Payer 200 DA & Confirmer',
                  style: const TextStyle(fontSize: 16,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, size: 20),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Modèle option durée ───────────────────────────────────────────────────────
class _DurationOption {
  final _DurationType type;
  final IconData icon;
  final String label;
  final String sublabel;
  final String price;
  final String unit;
  const _DurationOption({
    required this.type,
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.price,
    required this.unit,
  });
}

// ── Carte durée ───────────────────────────────────────────────────────────────
class _DurationCard extends StatelessWidget {
  final _DurationOption option;
  final bool selected;
  final VoidCallback onTap;
  const _DurationCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? _kBlue : _kBorder,
            width: selected ? 2 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? _kBlue.withOpacity(0.10)
                  : Colors.black.withOpacity(0.03),
              blurRadius: selected ? 12 : 6,
            ),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
            Icon(option.icon, size: 22,
                color: selected ? _kBlue : _kMid),
            if (selected)
              Container(
                width: 22, height: 22,
                decoration: const BoxDecoration(
                    color: _kBlue, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded,
                    size: 14, color: Colors.white),
              ),
          ]),
          const Spacer(),
          Text(option.label,
              style: const TextStyle(fontSize: 15,
                  fontWeight: FontWeight.w700, color: _kDark)),
          const SizedBox(height: 2),
          Text(option.sublabel,
              style: const TextStyle(fontSize: 11, color: _kMid)),
          const SizedBox(height: 6),
          Text(option.price,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                  color: selected ? _kBlue : _kDark)),
          Text(option.unit,
              style: const TextStyle(fontSize: 10, color: _kMid,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}