import 'dart:async';
import 'package:flutter/material.dart';
import 'package:parking_front/core/widgets/app_feedback.dart';
import 'package:parking_front/features/payment/data/mock_payment_service.dart';
import 'package:parking_front/features/payment/data/payment_repository.dart';
import 'package:parking_front/features/payment/presentation/screens/payment_confirmation_screen.dart';
import 'package:parking_front/features/payment/presentation/screens/payment_screen.dart';
import '../../../guidance/presentation/screens/guidance_to_exit_screen.dart';
import '../../../guidance/presentation/screens/guidance_to_spot_screen.dart';
import '../../../guidance/presentation/screens/guidance_to_vehicle_screen.dart';
import '../../../guidance/presentation/screens/vehicle_found_screen.dart';
import '../../../guidance/presentation/screens/vehicle_parked_confirmation_screen.dart';
import '../../../parking/data/parking_data.dart';
import '../../../parking/models/parking.dart';
import '../../../reservation/data/models/parking_session_api_model.dart';
import '../../../reservation/data/reservation_repository.dart';

// ─── Constantes couleurs ───────────────────────────────────────────────────────
const _kBlue = Color(0xFF4A90E2);
const _kGreen = Color(0xFF2ECC71);
const _kBg = Color(0xFFF0F2F5);
const _kCard = Colors.white;
const _kTextDark = Color(0xFF1A1A2E);
const _kTextMid = Color(0xFF7A8499);
const _kTextLight = Color(0xFFB0B8CC);

// ─── Modèle session (simplifié) ────────────────────────────────────────────────
class _Session {
  final String reservationId;
  final String parkingName;
  final String parkingAddress;
  final String spotLabel;
  final String ticketCode;
  final DateTime entryTime;
  final double tarifActuel;
  final String reservationDurationType;
  final double reservationAmount;
  final bool canGuideToSpot;
  final bool canFindCar;
  final bool canExit;
  final bool canPay;
  final bool isPaid;
  final bool isVehicleParked;
  final bool isVehicleFound;

  const _Session({
    required this.reservationId,
    required this.parkingName,
    required this.parkingAddress,
    required this.spotLabel,
    required this.ticketCode,
    required this.entryTime,
    required this.tarifActuel,
    required this.reservationDurationType,
    required this.reservationAmount,
    required this.canGuideToSpot,
    required this.canFindCar,
    required this.canExit,
    required this.canPay,
    required this.isPaid,
    required this.isVehicleParked,
    required this.isVehicleFound,
  });
}

// ─── HOME SCREEN ───────────────────────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  final ParkingSessionApiModel? initialSession;
  final VoidCallback? onSessionClosed;

  const HomeScreen({
    super.key,
    this.initialSession,
    this.onSessionClosed,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _kGuidanceComingSoonMessage =
      'La carte de ce parking sera affichee prochainement.';

  final ReservationRepository _reservationRepository = ReservationRepository();
  final PaymentRepository _paymentRepository = PaymentRepository();
  final Set<String> _parkedReservationIds = <String>{};
  final Set<String> _vehicleFoundReservationIds = <String>{};

  static const Duration _paymentHistoryCacheDuration = Duration(seconds: 20);

  _Session? _session;
  Timer? _timer;
  int _elapsedSec = 0;
  bool _isLoadingSession = true;
  String? _sessionError;
  bool _didUseInitialSession = false;
  List<PaymentTransaction>? _cachedPaymentHistory;
  DateTime? _paymentHistoryFetchedAt;

  @override
  void initState() {
    super.initState();
    _initializeSession().then((_) {
      if (!mounted) {
        return;
      }

      if (widget.initialSession?.isActive == true) {
        _initializeSession(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _hh => (_elapsedSec ~/ 3600).toString().padLeft(2, '0');
  String get _mm => ((_elapsedSec % 3600) ~/ 60).toString().padLeft(2, '0');
  String get _ss => (_elapsedSec % 60).toString().padLeft(2, '0');

  Future<void> _initializeSession({
    bool silent = false,
    bool forcePaymentHistoryRefresh = false,
  }) async {
    if (!silent || _session == null) {
      setState(() {
        _isLoadingSession = true;
        _sessionError = null;
      });
    } else {
      setState(() {
        _sessionError = null;
      });
    }

    try {
      final ParkingSessionApiModel? apiSession = await _resolveCurrentSession();

      if (!mounted) {
        return;
      }

      if (apiSession == null || !apiSession.isActive) {
        setState(() {
          _session = null;
          _isLoadingSession = false;
          _sessionError = null;
          _elapsedSec = 0;
        });
        _timer?.cancel();
        widget.onSessionClosed?.call();
        return;
      }

      final DateTime entry = _resolveEntryTime(apiSession);
      final int elapsed = _resolveElapsedSeconds(apiSession, entry);
      final bool isPaid = await _isSessionPaid(
        apiSession,
        entry,
        forceRefresh: forcePaymentHistoryRefresh,
      );
      final bool isVehicleParked =
          _parkedReservationIds.contains(apiSession.reservationId);
      final bool isVehicleFound = isVehicleParked &&
          _vehicleFoundReservationIds.contains(apiSession.reservationId);
      final String normalizedSpotLabel =
          _resolveSpotLabel(apiSession.ticketCode);

      setState(() {
        _session = _Session(
          reservationId: apiSession.reservationId,
          parkingName: apiSession.parkingName.isEmpty
              ? 'Session parking'
              : apiSession.parkingName,
          parkingAddress: apiSession.parkingAddress,
          spotLabel: normalizedSpotLabel,
          ticketCode: apiSession.ticketCode,
          entryTime: entry,
          tarifActuel: _resolveParkingRate(apiSession.parkingName),
          reservationDurationType: apiSession.reservationDurationType,
          reservationAmount: apiSession.reservationAmount,
          canGuideToSpot: !isPaid && !isVehicleParked,
          canFindCar: !isPaid && isVehicleParked && !isVehicleFound,
          canExit: isPaid,
          canPay: !isPaid && isVehicleParked && isVehicleFound,
          isPaid: isPaid,
          isVehicleParked: isVehicleParked,
          isVehicleFound: isVehicleFound,
        );
        _elapsedSec = elapsed;
        _isLoadingSession = false;
      });

      _timer?.cancel();
      if (!isPaid) {
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted || _session == null) {
            return;
          }
          setState(() => _elapsedSec++);
        });
      }
    } on ReservationException catch (error) {
      if (!mounted) {
        return;
      }

      if (silent && _session != null) {
        setState(() {
          _isLoadingSession = false;
          _sessionError = error.message;
        });
        return;
      }

      setState(() {
        _session = null;
        _isLoadingSession = false;
        _sessionError = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      if (silent && _session != null) {
        setState(() {
          _isLoadingSession = false;
          _sessionError = 'Impossible de charger la session active.';
        });
        return;
      }

      setState(() {
        _session = null;
        _isLoadingSession = false;
        _sessionError = 'Impossible de charger la session active.';
      });
    }
  }

  Future<ParkingSessionApiModel?> _resolveCurrentSession() async {
    if (!_didUseInitialSession) {
      _didUseInitialSession = true;
      final ParkingSessionApiModel? initialSession = widget.initialSession;
      if (initialSession != null && initialSession.isActive) {
        return initialSession;
      }
    }

    return _reservationRepository.fetchCurrentParkingSession();
  }

  DateTime _resolveEntryTime(ParkingSessionApiModel apiSession) {
    if (apiSession.startedAt != null) {
      return apiSession.startedAt!;
    }

    if (apiSession.createdAt != null) {
      return apiSession.createdAt!;
    }

    final int duration = apiSession.durationSeconds ?? 0;
    if (duration > 0) {
      return DateTime.now().subtract(Duration(seconds: duration));
    }

    return DateTime.now();
  }

  int _resolveElapsedSeconds(
      ParkingSessionApiModel apiSession, DateTime entryTime) {
    final int fromApi = apiSession.durationSeconds ??
        DateTime.now().difference(entryTime).inSeconds;
    return fromApi < 0 ? 0 : fromApi;
  }

  Future<bool> _isSessionPaid(
    ParkingSessionApiModel apiSession,
    DateTime sessionEntry, {
    bool forceRefresh = false,
  }) async {
    final String sessionPaymentStatus =
        apiSession.sessionPaymentStatus.trim().toLowerCase();
    final String reservationId = apiSession.reservationId.trim();

    if (sessionPaymentStatus == 'paid') {
      return true;
    }

    if (sessionPaymentStatus.isNotEmpty && sessionPaymentStatus != 'paid') {
      return false;
    }

    if (reservationId.isEmpty) {
      return false;
    }

    try {
      final List<PaymentTransaction> history = await _loadPaymentHistory(
        forceRefresh: forceRefresh,
      );

      final bool paidForThisSession = _hasSuccessfulPaymentForSession(
        history: history,
        reservationId: reservationId,
        sessionEntry: sessionEntry,
      );

      if (paidForThisSession) {
        return true;
      }
    } catch (_) {
      // Keep unpaid defaults when payment history is temporarily unavailable.
    }

    return false;
  }

  bool _hasSuccessfulPaymentForSession({
    required List<PaymentTransaction> history,
    required String reservationId,
    required DateTime sessionEntry,
  }) {
    final DateTime thresholdUtc =
        sessionEntry.toUtc().subtract(const Duration(seconds: 5));

    for (final PaymentTransaction transaction in history) {
      if (transaction.sessionId.trim() != reservationId) {
        continue;
      }

      if (transaction.statut != PaymentStatus.success) {
        continue;
      }

      final DateTime paidAtUtc =
          (transaction.paidAt ?? transaction.createdAt).toUtc();
      if (!paidAtUtc.isBefore(thresholdUtc)) {
        return true;
      }
    }

    return false;
  }

  Future<List<PaymentTransaction>> _loadPaymentHistory({
    bool forceRefresh = false,
  }) async {
    final DateTime now = DateTime.now();
    final bool hasFreshCache = _cachedPaymentHistory != null &&
        _paymentHistoryFetchedAt != null &&
        now.difference(_paymentHistoryFetchedAt!) <
            _paymentHistoryCacheDuration;

    if (!forceRefresh && hasFreshCache) {
      return _cachedPaymentHistory!;
    }

    final List<PaymentTransaction> history =
        await _paymentRepository.getHistory();
    _cachedPaymentHistory = history;
    _paymentHistoryFetchedAt = now;
    return history;
  }

  void _invalidatePaymentHistoryCache() {
    _cachedPaymentHistory = null;
    _paymentHistoryFetchedAt = null;
  }

  void _markSessionAsPaidLocally(_Session currentSession) {
    _timer?.cancel();
    setState(() {
      _session = _Session(
        reservationId: currentSession.reservationId,
        parkingName: currentSession.parkingName,
        parkingAddress: currentSession.parkingAddress,
        spotLabel: currentSession.spotLabel,
        ticketCode: currentSession.ticketCode,
        entryTime: currentSession.entryTime,
        tarifActuel: currentSession.tarifActuel,
        reservationDurationType: currentSession.reservationDurationType,
        reservationAmount: currentSession.reservationAmount,
        canGuideToSpot: false,
        canFindCar: false,
        canExit: true,
        canPay: false,
        isPaid: true,
        isVehicleParked: true,
        isVehicleFound: true,
      );
    });
  }

  Future<bool> _isReservationAlreadyPaidOnServer(String reservationId) async {
    final String trimmedReservationId = reservationId.trim();
    if (trimmedReservationId.isEmpty) {
      return false;
    }

    try {
      final ParkingSessionApiModel? apiSession =
          await _reservationRepository.fetchCurrentParkingSession(
        forceRefresh: true,
      );
      if (apiSession == null || !apiSession.isActive) {
        return false;
      }

      if (apiSession.reservationId.trim() != trimmedReservationId) {
        return false;
      }

      final String paymentStatus =
          apiSession.sessionPaymentStatus.trim().toLowerCase();
      return paymentStatus == 'paid';
    } catch (_) {
      return false;
    }
  }

  String _resolveSpotLabel(String rawTicketCode) {
    final String source = rawTicketCode.trim().toUpperCase();
    if (source.isEmpty) {
      return 'A1';
    }

    final Iterable<Match> matches =
        RegExp(r'([AB])\s*-?\s*(\d+)').allMatches(source);
    if (matches.isNotEmpty) {
      final Match last = matches.last;
      final String letter = last.group(1) ?? 'A';
      final int rawNumber = int.tryParse(last.group(2) ?? '1') ?? 1;
      final int normalizedNumber = ((rawNumber - 1) % 3) + 1;

      return '$letter$normalizedNumber';
    }

    return 'A1';
  }

  double _resolveParkingRate(String parkingName) {
    final String needle = parkingName.trim().toLowerCase();

    for (final Parking parking in ParkingData.parkings) {
      final String candidate = parking.name.trim().toLowerCase();
      if (candidate == needle ||
          candidate.contains(needle) ||
          needle.contains(candidate)) {
        return parking.pricePerHour.toDouble();
      }
    }

    return 100;
  }

  bool _isShortDurationType(String durationType) {
    return durationType.trim().toLowerCase() == 'courte';
  }

  double _resolveLongDurationFallbackAmount(String durationType) {
    switch (durationType.trim().toLowerCase()) {
      case 'journee':
        return 800.0;
      case 'semaine':
        return 4500.0;
      case 'mois':
        return 15000.0;
      default:
        return 0.0;
    }
  }

  bool _isSmartGuidanceEnabledForParking(String parkingName) {
    final String normalized =
        parkingName.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

    return normalized.contains('notre parking') ||
        normalized.contains('arduino');
  }

  Future<void> _showGuidanceComingSoonDialog() async {
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Guidage indisponible'),
          content: const Text(_kGuidanceComingSoonMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
          ],
        );
      },
    );
  }

  double _computeCurrentTotal() {
    final _Session? session = _session;
    if (session == null) {
      return 0.0;
    }

    if (!_isShortDurationType(session.reservationDurationType)) {
      if (session.reservationAmount > 0) {
        return session.reservationAmount;
      }

      final double fallbackAmount =
          _resolveLongDurationFallbackAmount(session.reservationDurationType);
      return fallbackAmount < 0 ? 0.0 : fallbackAmount;
    }

    final int safeElapsed = _elapsedSec < 0 ? 0 : _elapsedSec;
    if (safeElapsed == 0) {
      return 0.0;
    }

    final double total = session.tarifActuel * (safeElapsed / 3600.0);
    return total < 0 ? 0.0 : total;
  }

  String _formatTime(DateTime dt) =>
      '${dt.toLocal().hour.toString().padLeft(2, '0')}:${dt.toLocal().minute.toString().padLeft(2, '0')}';

  void _showTicketDialog() {
    final _Session? session = _session;
    if (session == null) {
      return;
    }

    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Ticket numerique'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Parking: ${session.parkingName}'),
              const SizedBox(height: 6),
              Text(
                  'Ticket: ${session.ticketCode.isEmpty ? session.spotLabel : session.ticketCode}'),
              const SizedBox(height: 6),
              Text('Reservation: ${session.reservationId}'),
              const SizedBox(height: 6),
              Text('Entree: ${_formatTime(session.entryTime)}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleGuideToSpot() async {
    final _Session? session = _session;
    if (session == null) {
      return;
    }

    final bool guidanceEnabled =
        _isSmartGuidanceEnabledForParking(session.parkingName);
    if (!guidanceEnabled) {
      await _showGuidanceComingSoonDialog();

      if (!_parkedReservationIds.contains(session.reservationId)) {
        _parkedReservationIds.add(session.reservationId);
        _vehicleFoundReservationIds.remove(session.reservationId);
      }

      if (mounted) {
        await _initializeSession(silent: true);
      }

      return;
    }

    if (_parkedReservationIds.contains(session.reservationId)) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => VehicleParkedConfirmationScreen(
            spotLabel: session.spotLabel,
          ),
        ),
      );
      return;
    }

    if (!session.canGuideToSpot) {
      return;
    }

    final bool parkedConfirmed = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => GuidanceToSpotScreen(
              spotLabel: session.spotLabel,
              isGuideToFree: false,
            ),
          ),
        ) ??
        false;

    if (parkedConfirmed) {
      _parkedReservationIds.add(session.reservationId);
      _vehicleFoundReservationIds.remove(session.reservationId);
    }

    if (!mounted) {
      return;
    }

    await _initializeSession(silent: true);
  }

  Future<void> _handleFindCar() async {
    final _Session? session = _session;
    if (session == null) {
      return;
    }

    final bool guidanceEnabled =
        _isSmartGuidanceEnabledForParking(session.parkingName);
    if (!guidanceEnabled) {
      await _showGuidanceComingSoonDialog();

      if (!session.isVehicleFound) {
        _vehicleFoundReservationIds.add(session.reservationId);
      }

      if (mounted) {
        await _initializeSession(silent: true);
      }

      return;
    }

    if (session.isVehicleFound) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => VehicleFoundScreen(
            spotLabel: session.spotLabel,
            reservationId: session.reservationId,
            parkingName: session.parkingName,
            dureeMinutes: (_elapsedSec / 60).ceil().clamp(1, 100000),
          ),
        ),
      );
      return;
    }

    if (!session.canFindCar) {
      return;
    }

    final bool vehicleFoundConfirmed = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => GuidanceToVehicleScreen(
              spotLabel: session.spotLabel,
              parkingName: session.parkingName,
              reservationId: session.reservationId,
              durationMinutes: (_elapsedSec / 60).ceil(),
            ),
          ),
        ) ??
        false;

    if (vehicleFoundConfirmed) {
      _vehicleFoundReservationIds.add(session.reservationId);
    }

    if (!mounted) {
      return;
    }

    await _initializeSession(silent: true);
  }

  Future<void> _handleGuideToExit() async {
    final _Session? session = _session;
    if (session == null || !session.canExit) {
      return;
    }

    final bool guidanceEnabled =
        _isSmartGuidanceEnabledForParking(session.parkingName);

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => GuidanceToExitScreen(
          spotLabel: session.spotLabel,
          showMapComingSoon: !guidanceEnabled,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    await _initializeSession(silent: true, forcePaymentHistoryRefresh: true);
  }

  Future<void> _handlePayCurrentSession() async {
    final _Session? session = _session;
    if (session == null) {
      return;
    }

    if (session.isPaid) {
      _openPaymentProof(session);
      return;
    }

    final bool alreadyPaidOnServer =
        await _isReservationAlreadyPaidOnServer(session.reservationId);

    if (!mounted) {
      return;
    }

    if (alreadyPaidOnServer) {
      _markSessionAsPaidLocally(session);
      AppFeedback.showInfo(
        context,
        'Paiement deja enregistre. La sortie est maintenant disponible.',
      );
      await _initializeSession(silent: true, forcePaymentHistoryRefresh: true);
      return;
    }

    if (!session.canPay) {
      AppFeedback.showInfo(
        context,
        'Terminez d abord Trouver ma voiture avant de payer.',
      );
      return;
    }

    if (session.reservationId.trim().isEmpty) {
      AppFeedback.showWarning(
        context,
        'Reservation introuvable pour cette session.',
      );
      return;
    }

    final int durationMinutes = (_elapsedSec / 60).ceil().clamp(1, 100000);
    final double amount = _computeCurrentTotal();

    final bool paymentConfirmed = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => PaymentScreen(
              reservationId: session.reservationId,
              parkingName: session.parkingName,
              dureeMinutes: durationMinutes,
              montantFixe: amount,
              allowCash: true,
              autoConfirmCashSelection: true,
              returnToCallerOnSuccess: true,
            ),
          ),
        ) ??
        false;

    if (!mounted) {
      return;
    }

    if (!paymentConfirmed) {
      final bool becamePaidOnServer =
          await _isReservationAlreadyPaidOnServer(session.reservationId);
      if (becamePaidOnServer && mounted) {
        _markSessionAsPaidLocally(_session ?? session);
        AppFeedback.showInfo(
          context,
          'Paiement deja enregistre. La sortie est maintenant disponible.',
        );
      }
    }

    if (paymentConfirmed && mounted) {
      _invalidatePaymentHistoryCache();
      _markSessionAsPaidLocally(_session ?? session);
    }

    await _initializeSession(silent: true, forcePaymentHistoryRefresh: true);
  }

  void _openPaymentProof(_Session session) {
    final PaymentTransaction transaction = PaymentTransaction(
      id: 'proof-${session.reservationId}',
      sessionId: session.reservationId,
      userId: '',
      parkingName: session.parkingName,
      montant: _computeCurrentTotal(),
      dureeMinutes: (_elapsedSec / 60).ceil().clamp(1, 100000),
      methode: PaymentMethod.cash,
      statut: PaymentStatus.success,
      transactionRef: session.ticketCode.isEmpty
          ? session.reservationId
          : session.ticketCode,
      createdAt: session.entryTime,
      paidAt: DateTime.now(),
      errorType: PaymentError.none,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentConfirmationScreen(
          transaction: transaction,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingSession) {
      return const Scaffold(
        backgroundColor: _kBg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_session == null) {
      return Scaffold(
        backgroundColor: _kBg,
        body: Center(
          child: Text(
            _sessionError ?? 'Aucune session active.',
            style: const TextStyle(fontSize: 14, color: _kTextMid),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

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
                _session!.parkingName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
        // ✅ CORRECTION : icône ticket/QR au lieu de profil
        GestureDetector(
          onTap: _showTicketDialog,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFDDE3EE),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.qr_code_2_rounded, color: _kBlue, size: 26),
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
    final double screenWidth = MediaQuery.of(context).size.width;
    final double contentWidth = screenWidth - 40 - 48;
    final double digitWidth = ((contentWidth - 60) / 3).clamp(64.0, 86.0);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildDigitBlock(_hh, 'HEURES', width: digitWidth),
                _buildSeparator(),
                _buildDigitBlock(_mm, 'MINUTES', width: digitWidth),
                _buildSeparator(),
                _buildDigitBlock(_ss, 'SECONDES', width: digitWidth),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(color: Color(0xFFF0F2F5), thickness: 1.5),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ENTRÉE',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _kTextMid,
                                letterSpacing: 0.8)),
                        const SizedBox(height: 4),
                        Text(
                          _formatTime(_session!.entryTime),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: _kTextDark,
                          ),
                        ),
                      ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('TOTAL',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _kTextMid,
                                letterSpacing: 0.8)),
                        const SizedBox(height: 4),
                        Text(
                          '${_computeCurrentTotal().toStringAsFixed(2)} DZD',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: _kTextDark,
                          ),
                        ),
                      ]),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Divider(color: Color(0xFFF0F2F5), thickness: 1.5),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Place estimée',
                            style: TextStyle(fontSize: 13, color: _kTextMid)),
                        const SizedBox(height: 3),
                        Text(
                          _session!.spotLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: _kTextDark,
                          ),
                        ),
                      ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Tarif actuel',
                            style: TextStyle(fontSize: 13, color: _kTextMid)),
                        const SizedBox(height: 3),
                        Text(
                          '${_session!.tarifActuel.toInt()} DZD',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: _kBlue,
                          ),
                        ),
                      ]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDigitBlock(String value, String label, {double width = 86}) {
    final double height = width >= 80 ? 86 : 76;

    return Column(
      children: [
        Container(
          width: width,
          height: height,
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
              fontSize: 28, fontWeight: FontWeight.w300, color: _kTextLight)),
    );
  }

  // ── ACTION GRID ────────────────────────────────────────────────────────────
  Widget _buildActionGrid() {
    final _Session session = _session!;

    final bool guideCardLocked =
        !session.canGuideToSpot && !session.isVehicleParked;
    final String guideSubtitle = session.canGuideToSpot
        ? 'ETAPE 1'
        : (session.isVehicleParked ? 'CONFIRMEE' : 'INDISPONIBLE');

    final String findSubtitle = session.canFindCar
        ? 'ETAPE 2'
        : (session.isVehicleFound ? 'CONFIRMEE' : 'ETAPE 1 D ABORD');

    final String paySubtitle = session.isPaid
        ? 'PAIEMENT REUSSI'
        : (session.canPay ? 'ETAPE 3' : 'ETAPE 2 D ABORD');

    final String exitSubtitle = session.canExit ? 'ETAPE 4' : 'PAYER D ABORD';

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
          subtitle: guideSubtitle,
          isActive: session.canGuideToSpot,
          locked: guideCardLocked,
          onTap: _handleGuideToSpot,
        ),
        _ActionCard(
          icon: Icons.directions_car_outlined,
          title: 'Trouver ma voiture',
          subtitle: findSubtitle,
          isActive: session.canFindCar || session.isVehicleFound,
          locked: !session.canFindCar && !session.isVehicleFound,
          onTap: _handleFindCar,
        ),
        _ActionCard(
          icon: Icons.exit_to_app_rounded,
          title: 'Guider vers la sortie',
          subtitle: exitSubtitle,
          isActive: session.canExit,
          locked: !session.canExit,
          onTap: _handleGuideToExit,
        ),
        _ActionCard(
          icon: Icons.credit_card_rounded,
          title: session.isPaid ? 'Paiement OK' : 'Payer',
          subtitle: paySubtitle,
          isActive: session.canPay,
          locked: !session.canPay && !session.isPaid,
          onTap: _handlePayCurrentSession,
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
      onTap: locked ? null : onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isActive ? _kBlue : _kCard,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: isActive
                  ? _kBlue.withValues(alpha: 0.30)
                  : Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isActive
                    ? Colors.white.withValues(alpha: 0.20)
                    : const Color(0xFFF0F2F5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon,
                  size: 22, color: isActive ? Colors.white : _kTextMid),
            ),
            const Spacer(),
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
            Row(children: [
              if (locked)
                Icon(Icons.lock_outline_rounded,
                    size: 11,
                    color: isActive
                        ? Colors.white.withValues(alpha: 0.7)
                        : _kTextLight),
              if (locked) const SizedBox(width: 4),
              Flexible(
                child: Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isActive
                        ? Colors.white.withValues(alpha: 0.75)
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
