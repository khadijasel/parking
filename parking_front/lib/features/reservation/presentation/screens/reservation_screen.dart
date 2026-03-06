import 'package:flutter/material.dart';

const _kBlue     = Color(0xFF4A90E2);
const _kDark     = Color(0xFF1A1A2E);
const _kMid      = Color(0xFF8A9BB5);
const _kOrange   = Color(0xFFF5A623);
const _kOrangeBg = Color(0xFFFFF8EC);
const _kGreen    = Color(0xFF27AE60);
const _kBorder   = Color(0xFFE2ECF9);

/// Types de durée
enum _DurationType { courte, journee, semaine, mois }

/// Écran Réservation — fidèle à la maquette image 3
/// Logique métier :
///  • Courte durée  → confirmation directe, place garantie 30 min gratuitement
///  • Longue durée  → paiement acompte 200 DA requis avant confirmation
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
  bool _isLoading = false;

  bool get _isCourte => _selected == _DurationType.courte;

  // ─── Données des cartes ──────────────────────────────────────────────────
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

  // ─── Action bouton ───────────────────────────────────────────────────────
  Future<void> _handleConfirm() async {
    if (_isCourte) {
      // Courte durée : confirmation directe
      _showConfirmDialog(
        title   : '✅ Réservation confirmée',
        message : 'Votre place est réservée gratuitement pendant 30 minutes.',
        color   : _kGreen,
      );
    } else {
      // Longue durée : paiement acompte 200 DA
      _showPaymentDialog();
    }
  }

  void _showConfirmDialog({
    required String title,
    required String message,
    required Color color,
  }) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title : Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
        content: Text(message, style: const TextStyle(color: _kMid, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () { Navigator.pop(context); Navigator.maybePop(context); },
            child: const Text('OK', style: TextStyle(color: _kBlue, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showPaymentDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _AcompteSheet(
        duration: _options.firstWhere((o) => o.type == _selected),
        onPaid: () {
          Navigator.pop(context); // ferme la sheet
          _showConfirmDialog(
            title  : '✅ Paiement accepté',
            message: 'Acompte de 200 DA encaissé. Votre place est garantie.',
            color  : _kGreen,
          );
        },
      ),
    );
  }

  // ── ICÔNES équipements ────────────────────────────────────────────────────
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

  // ── BUILD ─────────────────────────────────────────────────────────────────
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
            child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: _kDark),
          ),
        ),
        centerTitle: true,
        title: const Text('Réservation',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _kDark)),
      ),
      body: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // ── Nom parking ────────────────────────────────────────────
              Text(widget.parkingName,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _kDark)),
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.location_on_outlined, size: 15, color: _kMid),
                const SizedBox(width: 4),
                Text(widget.parkingAddress,
                    style: const TextStyle(fontSize: 13, color: _kMid)),
              ]),
              const SizedBox(height: 16),

              // ── Chips équipements ───────────────────────────────────────
              Wrap(spacing: 8, runSpacing: 8,
                children: widget.equipments.map((eq) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: _kBorder, width: 1.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_equipIcon(eq), size: 14, color: _equipColor(eq)),
                    const SizedBox(width: 5),
                    Text(eq, style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600, color: _kDark)),
                  ]),
                )).toList()),
              const SizedBox(height: 20),

              // ── Bannière "Place garantie 30 min" ───────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4A90E2), Color(0xFF6BA8F0)],
                    begin: Alignment.centerLeft, end: Alignment.centerRight),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(children: [
                  // Badge 30 MIN
                  Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('30', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
                      Text('MIN', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Colors.white70)),
                    ]),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Place garantie',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                    SizedBox(height: 4),
                    Text('Votre emplacement est réservé\ngratuitement pendant 30 minutes.',
                        style: TextStyle(fontSize: 12, color: Colors.white70, height: 1.4)),
                  ])),
                  // Grande icône décorative
                  const Icon(Icons.local_parking_rounded,
                      size: 52, color: Colors.white24),
                ]),
              ),
              const SizedBox(height: 14),

              // ── Avertissement 30 min ────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _kOrangeBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _kOrange.withOpacity(0.25)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.access_alarm_rounded, color: _kOrange, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: RichText(text: TextSpan(
                    style: const TextStyle(fontSize: 13, color: _kDark, height: 1.4),
                    children: [
                      const TextSpan(text: 'Attention : '),
                      const TextSpan(text: 'Passé le délai de 30 min, la\nréservation sera '),
                      TextSpan(text: 'annulée automatiquement.',
                        style: TextStyle(color: _kOrange, fontWeight: FontWeight.w700)),
                    ],
                  ))),
                ]),
              ),
              const SizedBox(height: 24),

              // ── Sélectionner la durée ───────────────────────────────────
              const Text('Sélectionner la durée',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _kDark)),
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
            ]),
          ),
        ),

        // ── Bouton bas ────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          decoration: const BoxDecoration(color: Colors.white),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleConfirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(
                        _isCourte ? 'Confirmer la réservation' : 'Payer 200 DA & Confirmer',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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

// ─── Carte durée ─────────────────────────────────────────────────────────────
class _DurationOption {
  final _DurationType type;
  final IconData icon;
  final String label;
  final String sublabel;
  final String price;
  final String unit;
  const _DurationOption({
    required this.type, required this.icon,
    required this.label, required this.sublabel,
    required this.price, required this.unit,
  });
}

class _DurationCard extends StatelessWidget {
  final _DurationOption option;
  final bool selected;
  final VoidCallback onTap;
  const _DurationCard({required this.option, required this.selected, required this.onTap});

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
              color: selected ? _kBlue.withOpacity(0.10) : Colors.black.withOpacity(0.03),
              blurRadius: selected ? 12 : 6,
            ),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Icon(option.icon, size: 22, color: selected ? _kBlue : _kMid),
            if (selected)
              Container(
                width: 22, height: 22,
                decoration: const BoxDecoration(color: _kBlue, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
              ),
          ]),
          const Spacer(),
          Text(option.label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _kDark)),
          const SizedBox(height: 2),
          Text(option.sublabel,
              style: const TextStyle(fontSize: 11, color: _kMid)),
          const SizedBox(height: 6),
          Text(option.price,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                  color: selected ? _kBlue : _kDark)),
          Text(option.unit,
              style: const TextStyle(fontSize: 10, color: _kMid, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

// ─── Bottom sheet paiement acompte ────────────────────────────────────────────
class _AcompteSheet extends StatefulWidget {
  final _DurationOption duration;
  final VoidCallback onPaid;
  const _AcompteSheet({required this.duration, required this.onPaid});

  @override
  State<_AcompteSheet> createState() => _AcompteSheetState();
}

class _AcompteSheetState extends State<_AcompteSheet> {
  int _payMode = 0; // 0=Edahabia 1=CIB 2=Cash
  bool _loading = false;

  Future<void> _pay() async {
    setState(() => _loading = true);
    await Future.delayed(const Duration(seconds: 2)); // simulation
    if (mounted) { widget.onPaid(); }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Poignée
          Container(width: 40, height: 4,
            decoration: BoxDecoration(color: const Color(0xFFDDE3EE), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          const Text('Paiement de l\'acompte',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _kDark)),
          const SizedBox(height: 6),
          Text('Garantie de votre place — ${widget.duration.label}',
            style: const TextStyle(fontSize: 13, color: _kMid)),
          const SizedBox(height: 24),
          // Montant
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F7FC),
              borderRadius: BorderRadius.circular(16)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Acompte à régler',
                style: TextStyle(fontSize: 15, color: _kMid, fontWeight: FontWeight.w500)),
              const Text('200 DA',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _kDark)),
            ]),
          ),
          const SizedBox(height: 20),
          // Modes paiement
          Row(children: [
            _PayChip(label: '💳 Edahabia', active: _payMode==0, onTap: () => setState(()=>_payMode=0)),
            const SizedBox(width: 8),
            _PayChip(label: '🏦 Carte CIB', active: _payMode==1, onTap: () => setState(()=>_payMode=1)),
            const SizedBox(width: 8),
            _PayChip(label: '💵 Cash',       active: _payMode==2, onTap: () => setState(()=>_payMode=2)),
          ]),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _pay,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kBlue, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0),
              child: _loading
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                : const Text('Confirmer le paiement',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }
}

class _PayChip extends StatelessWidget {
  final String label; final bool active; final VoidCallback onTap;
  const _PayChip({required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: active ? _kBlue.withOpacity(0.1) : const Color(0xFFF4F7FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: active ? _kBlue : const Color(0xFFE2ECF9), width: active ? 1.5 : 1)),
      child: Text(label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
            color: active ? _kBlue : _kMid)),
    ),
  );
}