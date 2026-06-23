import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parking_front/core/constants/api_constants.dart';
import 'package:parking_front/core/widgets/app_feedback.dart';
import 'package:parking_front/features/payment/data/mock_payment_service.dart';
import 'package:parking_front/features/payment/data/payment_repository.dart';
import 'package:parking_front/features/payment/presentation/screens/payment_confirmation_screen.dart';
import 'package:parking_front/features/payment/presentation/screens/payment_screen.dart';
import 'package:parking_front/core/state/selected_spot_provider.dart';
import 'package:parking_front/features/guidance/presentation/utils/guidance_spot_layout.dart';
import '../../../guidance/presentation/screens/guidance_to_exit_screen.dart';
import '../../../guidance/presentation/screens/guidance_to_spot_screen.dart';
import '../../../guidance/presentation/screens/guidance_to_vehicle_screen.dart';
import '../../../guidance/presentation/screens/vehicle_found_screen.dart';
import '../../../guidance/presentation/screens/vehicle_parked_confirmation_screen.dart';
import '../../../parking/data/parking_data.dart';
import '../../../parking/data/parking_repository.dart';
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
  final String parkingId;
  final Parking? parking;
  final String parkingName;
  final String parkingAddress;
  final String spotLabel;
  final String ticketCode;
  final DateTime entryTime;
  final double tarifActuel;
  final String reservationDurationType;
  final double reservationAmount;
  final double depositAmount;
  final bool isAdvanceReservation;
  final bool canGuideToSpot;
  final bool canFindCar;
  final bool canExit;
  final bool canPay;
  final bool isPaid;
  final bool isVehicleParked;
  final bool isVehicleFound;

  const _Session({
    required this.reservationId,
    required this.parkingId,
    required this.parking,
    required this.parkingName,
    required this.parkingAddress,
    required this.spotLabel,
    required this.ticketCode,
    required this.entryTime,
    required this.tarifActuel,
    required this.reservationDurationType,
    required this.reservationAmount,
    required this.depositAmount,
    required this.isAdvanceReservation,
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
  final ParkingRepository _parkingRepository = ParkingRepository();
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

  // Spot locked on first detection — stays constant for the whole session.
  String? _confirmedSpotLabel;
  String? _confirmedReservationId;

  // Empeche l'ouverture multiple de l'ecran de paiement : tant que la
  // verification "deja paye ?" est en cours, on ignore les nouveaux taps sur
  // "Payer" (sinon chaque tap empilait un PaymentScreen et declenchait un
  // appel /payments/initiate de plus).
  bool _isOpeningPayment = false;

  // Derniere transaction reellement payee durant cette session (avec la vraie
  // methode : Edahabia/CIB/Cash). Sert a afficher une preuve de paiement
  // correcte quand l'utilisateur rouvre "Paiement OK".
  PaymentTransaction? _lastPaidTransaction;

  @override
  void initState() {
    super.initState();
    // La session passee par HomeTabGate vient juste d'etre recuperee du serveur
    // (cache frais) : une seule initialisation suffit. L'ancien double appel
    // (normal puis "silent") relancait inutilement les fetchs au demarrage.
    _initializeSession();
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
      
      // On s'appuie sur le cache parkings (TTL 20s, deja rempli par HomeTabGate)
      // au lieu de forcer un rechargement reseau a chaque init de session :
      // c'est l'endpoint le plus lourd et il etait recharge a chaque action.
      try {
        await _parkingRepository.fetchParkings();
      } catch (_) {}
      Parking? matchedParking = _resolveParking(apiSession);
      final bool isVehicleParked =
          _parkedReservationIds.contains(apiSession.reservationId);
      final bool isVehicleFound = isVehicleParked &&
          _vehicleFoundReservationIds.contains(apiSession.reservationId);
      final String backendSpotLabel = apiSession.spotLabel.trim().isNotEmpty
          ? apiSession.spotLabel.trim()
          : _resolveSpotLabel(apiSession.ticketCode, matchedParking);

      // Si la place renvoyée par le backend est physiquement OCCUPÉE
      // (capteur IR), basculer vers une vraie place libre et la sauvegarder
      // pour toute la durée de la session.
      final String normalizedSpotLabel = _pickFreeSpotIfBackendSpotOccupied(
        backendSpotLabel,
        matchedParking,
      );

      // Lock the spot the first time this reservation is seen; keep it for
      // the entire session so all 3 guidance buttons stay consistent.
      // (Une fois choisie, on ne change plus — sinon dès que l'utilisateur
      // se gare et que le capteur passe la place en OCCUPIED, on basculerait
      // vers une autre place, désynchronisant les écrans.)
      if (_confirmedReservationId != apiSession.reservationId) {
        _confirmedReservationId = apiSession.reservationId;
        _confirmedSpotLabel = normalizedSpotLabel;
      }

      setState(() {
        _session = _Session(
          reservationId: apiSession.reservationId,
          parkingId: apiSession.parkingId,
          parking: matchedParking,
          parkingName: apiSession.parkingName.trim().isEmpty ||
                  apiSession.parkingName.trim().toLowerCase() == 'session parking'
              ? (matchedParking?.name.isNotEmpty == true ? matchedParking!.name : 'Session parking')
              : apiSession.parkingName,
          parkingAddress: apiSession.parkingAddress,
          spotLabel: normalizedSpotLabel,
          ticketCode: apiSession.ticketCode,
          entryTime: entry,
          tarifActuel: _resolveParkingRate(matchedParking, apiSession),
          reservationDurationType: apiSession.reservationDurationType,
          reservationAmount: apiSession.reservationAmount,
          depositAmount: apiSession.depositAmount,
          isAdvanceReservation: apiSession.isAdvanceReservation,
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
        parkingId: currentSession.parkingId,
        parking: currentSession.parking,
        parkingName: currentSession.parkingName,
        parkingAddress: currentSession.parkingAddress,
        spotLabel: currentSession.spotLabel,
        ticketCode: currentSession.ticketCode,
        entryTime: currentSession.entryTime,
        tarifActuel: currentSession.tarifActuel,
        reservationDurationType: currentSession.reservationDurationType,
        reservationAmount: currentSession.reservationAmount,
        depositAmount: currentSession.depositAmount,
        isAdvanceReservation: currentSession.isAdvanceReservation,
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

  /// Returns true if the spot identified by [label] is physically occupied
  /// (state OCCUPIED or OFFLINE in the latest backend layout).
  bool _isSpotPhysicallyOccupied(String label, Parking? parking) {
    final String needle = label.trim().toUpperCase();
    if (needle.isEmpty) return false;

    final List<ParkingIndoorSpot> spots =
        parking?.indoorMap?.spots ?? const <ParkingIndoorSpot>[];

    for (final ParkingIndoorSpot spot in spots) {
      if (spot.label.trim().toUpperCase() == needle) {
        final String state = spot.state.trim().toUpperCase();
        return state == 'OCCUPIED' || state == 'OFFLINE';
      }
    }
    return false;
  }

  /// If the backend-assigned spot is physically OCCUPIED, picks the first
  /// truly AVAILABLE spot in the layout instead. Otherwise returns the
  /// backend value unchanged.
  String _pickFreeSpotIfBackendSpotOccupied(
      String backendSpotLabel, Parking? parking) {
    if (!_isSpotPhysicallyOccupied(backendSpotLabel, parking)) {
      return backendSpotLabel;
    }

    final List<ParkingIndoorSpot> spots =
        parking?.indoorMap?.spots ?? const <ParkingIndoorSpot>[];

    for (final ParkingIndoorSpot spot in spots) {
      if (spot.state.trim().toUpperCase() == 'AVAILABLE' &&
          spot.label.trim().isNotEmpty) {
        return spot.label.trim();
      }
    }
    // Aucune place libre détectée → garder l'assignation backend.
    return backendSpotLabel;
  }

  String _resolveSpotLabel(String rawTicketCode, Parking? parking) {
    final List<ParkingIndoorSpot> spots =
        parking?.indoorMap?.spots ?? const <ParkingIndoorSpot>[];

    // Préférer la place RESERVED (= assignée à cette session par le backend).
    for (final ParkingIndoorSpot spot in spots) {
      if (spot.state.trim().toUpperCase() == 'RESERVED' &&
          spot.label.trim().isNotEmpty) {
        return spot.label.trim();
      }
    }

    // Sinon, tenter d'extraire du ticket code, fallback sur première place libre.
    final String firstAvailable = spots.firstWhere(
      (ParkingIndoorSpot s) => s.state.trim().toUpperCase() == 'AVAILABLE',
      orElse: () => spots.isNotEmpty
          ? spots.first
          : const ParkingIndoorSpot(
              spotId: '', label: '', row: 0, col: 0, type: '', state: ''),
    ).label.trim();

    return resolveSpotLabelFromTicketCode(
      rawTicketCode,
      spots,
      fallback: firstAvailable.isNotEmpty ? firstAvailable : 'A1',
    );
  }

  double _resolveParkingRate(Parking? parking, ParkingSessionApiModel apiSession) {
    if (parking != null) {
      return parking.pricePerHour.toDouble();
    }

    final String needle = apiSession.parkingName.trim().toLowerCase();
    final String parkingId = apiSession.parkingId.trim().toLowerCase();

    final List<Parking> cached = ParkingRepository.cachedParkings;
    final Iterable<Parking> sources =
        cached.isNotEmpty ? cached : ParkingData.parkings;

    for (final Parking parking in sources) {
      final String candidate = parking.name.trim().toLowerCase();
      final String candidateId = parking.id.trim().toLowerCase();
      if (candidate == needle ||
          candidate.contains(needle) ||
          needle.contains(candidate) ||
          (candidateId.isNotEmpty && candidateId == parkingId)) {
        return parking.pricePerHour.toDouble();
      }
    }

    return 100;
  }

  Parking? _resolveParking(ParkingSessionApiModel apiSession) {
    final Parking? byId = _resolveParkingById(apiSession.parkingId);
    if (byId != null) {
      return byId;
    }

    final Parking? byName = _resolveParkingByName(apiSession.parkingName);
    if (byName != null) {
      return byName;
    }

    return _resolveParkingByAddress(apiSession.parkingAddress);
  }

  Parking? _resolveParkingById(String parkingId) {
    final String needle = parkingId.trim().toLowerCase();
    if (needle.isEmpty) {
      return null;
    }

    final List<Parking> cached = ParkingRepository.cachedParkings;
    final Iterable<Parking> sources =
        cached.isNotEmpty ? cached : ParkingData.parkings;

    for (final Parking parking in sources) {
      final String candidateId = parking.id.trim().toLowerCase();
      if (candidateId == needle) {
        return parking;
      }
    }

    return null;
  }

  Parking? _resolveParkingByAddress(String parkingAddress) {
    final String needle = parkingAddress.trim().toLowerCase();
    if (needle.isEmpty) {
      return null;
    }

    final List<Parking> cached = ParkingRepository.cachedParkings;
    final Iterable<Parking> sources =
        cached.isNotEmpty ? cached : ParkingData.parkings;

    for (final Parking parking in sources) {
      final String candidate = parking.address.trim().toLowerCase();
      if (candidate.isNotEmpty &&
          (candidate == needle ||
              candidate.contains(needle) ||
              needle.contains(candidate))) {
        return parking;
      }
    }

    return null;
  }

  Parking? _resolveParkingByName(String parkingName) {
    final String needle = parkingName.trim().toLowerCase();
    if (needle.isEmpty) {
      return null;
    }

    final List<Parking> cached = ParkingRepository.cachedParkings;
    final Iterable<Parking> sources =
        cached.isNotEmpty ? cached : ParkingData.parkings;

    for (final Parking parking in sources) {
      final String candidate = parking.name.trim().toLowerCase();
      if (candidate == needle ||
          candidate.contains(needle) ||
          needle.contains(candidate)) {
        return parking;
      }
    }

    return null;
  }

  bool _isShortDurationType(String durationType) {
    return durationType.trim().toLowerCase() == 'courte';
  }


  bool _isSmartGuidanceEnabled(String parkingName, Parking? parking) {
    final Parking? resolved = parking ?? _resolveParkingByName(parkingName);
    if (resolved?.indoorMap?.spots.isNotEmpty == true) {
      return true;
    }

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

  /// Décompose un nombre de secondes en coût hiérarchique :
  /// semaines × prixSem + jours × prixJour + heures × prixHeure
  double _hierarchicalCost(int seconds, double prixHeure, double prixJour, double prixSem) {
    if (seconds <= 0) return 0.0;
    final int weeks = seconds ~/ (7 * 24 * 3600);
    int rem = seconds % (7 * 24 * 3600);
    final int days = rem ~/ (24 * 3600);
    rem = rem % (24 * 3600);
    final double hours = rem / 3600.0;
    return weeks * prixSem + days * prixJour + hours * prixHeure;
  }

  double _computeCurrentTotal() {
    final _Session? session = _session;
    if (session == null) return 0.0;

    final int safeElapsed = _elapsedSec < 0 ? 0 : _elapsedSec;

    // Courte durée : tarif horaire × heures
    if (_isShortDurationType(session.reservationDurationType)) {
      if (safeElapsed == 0) return 0.0;
      return (session.tarifActuel * (safeElapsed / 3600.0)).clamp(0.0, double.infinity);
    }

    // Prix unitaires depuis le parking ou fallback
    final Parking? p = session.parking;
    final double prixHeure = session.tarifActuel > 0 ? session.tarifActuel : 100.0;
    final double prixJour  = (p?.priceJournee ?? 0) > 0 ? p!.priceJournee! : 800.0;
    final double prixSem   = (p?.priceSemaine ?? 0) > 0 ? p!.priceSemaine! : 4500.0;

    // Durée réservée en secondes
    final int dureeType = switch (session.reservationDurationType.trim().toLowerCase()) {
      'journee' => 1 * 24 * 3600,
      'semaine' => 7 * 24 * 3600,
      'mois'    => 30 * 24 * 3600,
      _         => 0,
    };

    final double remaining = (session.reservationAmount - session.depositAmount).clamp(0.0, double.infinity);

    if (safeElapsed <= dureeType) {
      // Durée réelle ≤ durée réservée → facturation sur temps réel
      return _hierarchicalCost(safeElapsed, prixHeure, prixJour, prixSem);
    } else {
      // Dépassement → remaining + coût du temps extra
      final int extraSeconds = safeElapsed - dureeType;
      return remaining + _hierarchicalCost(extraSeconds, prixHeure, prixJour, prixSem);
    }
  }

  /// Tarif unitaire AFFICHE sur la carte de session selon le type de
  /// reservation : tarif horaire pour "courte", sinon le forfait de la duree
  /// choisie (jour/semaine/mois). Le calcul du TOTAL ne change pas — il reste
  /// gere par [_computeCurrentTotal] avec les regles hierarchiques.
  double _resolveDisplayRate() {
    final _Session? session = _session;
    if (session == null) {
      return 0.0;
    }

    final Parking? p = session.parking;
    switch (session.reservationDurationType.trim().toLowerCase()) {
      case 'journee':
        return _firstPositiveRate(
            <double?>[session.reservationAmount, p?.priceJournee, 800.0]);
      case 'semaine':
        return _firstPositiveRate(
            <double?>[session.reservationAmount, p?.priceSemaine, 4500.0]);
      case 'mois':
        return _firstPositiveRate(
            <double?>[session.reservationAmount, p?.priceMois, 15000.0]);
      default:
        return session.tarifActuel;
    }
  }

  double _firstPositiveRate(List<double?> candidates) {
    for (final double? value in candidates) {
      if (value != null && value > 0) {
        return value;
      }
    }
    return 0.0;
  }

  /// Suffixe d'unite du tarif affiche ("/jour", "/semaine", "/mois", "/h").
  String _rateUnitSuffix() {
    switch (_session?.reservationDurationType.trim().toLowerCase()) {
      case 'journee':
        return '/jour';
      case 'semaine':
        return '/semaine';
      case 'mois':
        return '/mois';
      default:
        return '/h';
    }
  }

  String _formatTime(DateTime dt) =>
      '${dt.toLocal().hour.toString().padLeft(2, '0')}:${dt.toLocal().minute.toString().padLeft(2, '0')}';

  String _sanitizeTicketFileKey(String value) {
    final String safe = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'^_+'), '')
        .replaceAll(RegExp(r'_+$'), '');

    return safe;
  }

  String _resolveTicketPngUrl(String ticketCode) {
    final String trimmed = ticketCode.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final String base = ApiConstants.baseUrl;
    final String origin = base.replaceFirst(RegExp(r'/api/?$'), '');
    final String key = _sanitizeTicketFileKey(trimmed);
    if (origin.trim().isEmpty || key.isEmpty) {
      return '';
    }

    return '$origin/tickets/ticket_$key.png';
  }

  void _showTicketDialog() {
    final _Session? session = _session;
    if (session == null) {
      return;
    }

    final String ticketKey =
        session.ticketCode.isEmpty ? session.spotLabel : session.ticketCode;
    final String ticketPngUrl = _resolveTicketPngUrl(ticketKey);

    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Ticket numerique'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (ticketPngUrl.isNotEmpty) ...[
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.network(
                        ticketPngUrl,
                        width: 240,
                        height: 340,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 240,
                          height: 340,
                          alignment: Alignment.center,
                          color: const Color(0xFFF0F2F5),
                          child: const Icon(
                            Icons.qr_code_2_rounded,
                            color: _kBlue,
                            size: 72,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text('Parking: ${session.parkingName}'),
                const SizedBox(height: 6),
                Text('Ticket: $ticketKey'),
                const SizedBox(height: 6),
                Text('Réservation : ${session.isAdvanceReservation ? 'Oui' : 'Non'}'),
                const SizedBox(height: 6),
                Text('Entree: ${_formatTime(session.entryTime)}'),
              ],
            ),
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
      _isSmartGuidanceEnabled(session.parkingName, session.parking);
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

    final String effectiveSpot = _confirmedSpotLabel ?? session.spotLabel;

    if (_parkedReservationIds.contains(session.reservationId)) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => VehicleParkedConfirmationScreen(
            spotLabel: effectiveSpot,
          ),
        ),
      );
      return;
    }

    if (!session.canGuideToSpot) {
      return;
    }

    ProviderScope.containerOf(context, listen: false)
        .read(selectedSpotProvider.notifier)
        .state = effectiveSpot;

    final bool parkedConfirmed = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => GuidanceToSpotScreen(
              spotLabel: effectiveSpot,
              isGuideToFree: false,
              spots: session.parking?.indoorMap?.spots ??
                  const <ParkingIndoorSpot>[],
              parkingId: session.parkingId,
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
      _isSmartGuidanceEnabled(session.parkingName, session.parking);
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

    final String effectiveSpot = _confirmedSpotLabel ?? session.spotLabel;

    if (session.isVehicleFound) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => VehicleFoundScreen(
            spotLabel: effectiveSpot,
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

    ProviderScope.containerOf(context, listen: false)
        .read(selectedSpotProvider.notifier)
        .state = effectiveSpot;

    final bool vehicleFoundConfirmed = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => GuidanceToVehicleScreen(
              spotLabel: effectiveSpot,
              parkingName: session.parkingName,
              reservationId: session.reservationId,
              durationMinutes: (_elapsedSec / 60).ceil(),
              spots: session.parking?.indoorMap?.spots ??
                  const <ParkingIndoorSpot>[],
              parkingId: session.parkingId,
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
      _isSmartGuidanceEnabled(session.parkingName, session.parking);

    final String effectiveSpot = _confirmedSpotLabel ?? session.spotLabel;

    ProviderScope.containerOf(context, listen: false)
      .read(selectedSpotProvider.notifier)
      .state = effectiveSpot;

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => GuidanceToExitScreen(
          spotLabel: effectiveSpot,
          showMapComingSoon: !guidanceEnabled,
          spots: session.parking?.indoorMap?.spots ??
              const <ParkingIndoorSpot>[],
          parkingId: session.parkingId,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    await _initializeSession(silent: true, forcePaymentHistoryRefresh: true);
  }

  Future<void> _handlePayCurrentSession() async {
    if (_isOpeningPayment) {
      return;
    }

    final _Session? session = _session;
    if (session == null) {
      return;
    }

    if (session.isPaid) {
      await _openPaymentProof(session);
      return;
    }

    setState(() => _isOpeningPayment = true);
    try {
      await _openPaymentFlow(session);
    } finally {
      if (mounted) {
        setState(() => _isOpeningPayment = false);
      }
    }
  }

  Future<void> _openPaymentFlow(_Session session) async {
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

    final PaymentTransaction? paidTransaction =
        await Navigator.push<PaymentTransaction>(
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
    );

    final bool paymentConfirmed = paidTransaction != null;
    if (paidTransaction != null) {
      _lastPaidTransaction = paidTransaction;
    }

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

  Future<void> _openPaymentProof(_Session session) async {
    final String reservationId = session.reservationId.trim();

    // 1) Transaction reelle renvoyee par l'ecran de paiement (methode exacte).
    PaymentTransaction? transaction =
        (_lastPaidTransaction != null &&
                _lastPaidTransaction!.sessionId.trim() == reservationId)
            ? _lastPaidTransaction
            : null;

    // 2) Sinon, on recherche le paiement reussi dans l'historique serveur
    //    (source de verite : bonne methode, bon montant, bonne reference).
    if (transaction == null && reservationId.isNotEmpty) {
      try {
        final List<PaymentTransaction> history = await _loadPaymentHistory();
        transaction = _findSuccessfulPaymentForSession(
          history: history,
          reservationId: reservationId,
          sessionEntry: session.entryTime,
        );
      } catch (_) {
        transaction = null;
      }
    }

    if (!mounted) {
      return;
    }

    // 3) Dernier recours : preuve synthetisee. On ne force JAMAIS "cash" :
    //    on reprend la methode reellement utilisee si connue, sinon Edahabia.
    final PaymentTransaction proof = transaction ??
        PaymentTransaction(
          id: 'proof-${session.reservationId}',
          sessionId: session.reservationId,
          userId: '',
          parkingName: session.parkingName,
          montant: _computeCurrentTotal(),
          dureeMinutes: (_elapsedSec / 60).ceil().clamp(1, 100000),
          methode: _lastPaidTransaction?.methode ?? PaymentMethod.edahabia,
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
          transaction: proof,
        ),
      ),
    );
  }

  /// Retourne le dernier paiement REUSSI enregistre pour cette reservation,
  /// avec la vraie methode/montant. Filtre les paiements anterieurs a l'entree
  /// (sessions precedentes) comme [_hasSuccessfulPaymentForSession].
  PaymentTransaction? _findSuccessfulPaymentForSession({
    required List<PaymentTransaction> history,
    required String reservationId,
    required DateTime sessionEntry,
  }) {
    final DateTime thresholdUtc =
        sessionEntry.toUtc().subtract(const Duration(seconds: 5));

    PaymentTransaction? best;
    for (final PaymentTransaction transaction in history) {
      if (transaction.sessionId.trim() != reservationId) {
        continue;
      }
      if (transaction.statut != PaymentStatus.success) {
        continue;
      }

      final DateTime paidAtUtc =
          (transaction.paidAt ?? transaction.createdAt).toUtc();
      if (paidAtUtc.isBefore(thresholdUtc)) {
        continue;
      }

      final DateTime current = transaction.paidAt ?? transaction.createdAt;
      final DateTime bestDate =
          best == null ? current : (best.paidAt ?? best.createdAt);
      if (best == null || current.isAfter(bestDate)) {
        best = transaction;
      }
    }

    return best;
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
                          _confirmedSpotLabel ?? _session!.spotLabel,
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
                          '${_resolveDisplayRate().toInt()} DA${_rateUnitSuffix()}',
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

    final String paySubtitle = _isOpeningPayment
        ? 'OUVERTURE...'
        : (session.isPaid
            ? 'PAIEMENT REUSSI'
            : (session.canPay ? 'ETAPE 3' : 'ETAPE 2 D ABORD'));

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
          // Une fois la voiture retrouvee, la carte redevient blanche (etat
          // "CONFIRMEE") comme "Guider vers une place" — seul le bouton suivant
          // ("Payer") reste en bleu. Elle reste cliquable (locked=false) pour
          // revoir l'ecran de localisation du vehicule.
          subtitle: findSubtitle,
          isActive: session.canFindCar,
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
          isActive: session.canPay || _isOpeningPayment,
          locked: !_isOpeningPayment && !session.canPay && !session.isPaid,
          isLoading: _isOpeningPayment,
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
  final bool isLoading;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isActive,
    required this.locked,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: (locked || isLoading) ? null : onTap,
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
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isActive
                    ? Colors.white.withOpacity(0.20)
                    : const Color(0xFFF0F2F5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: isLoading
                  ? Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isActive ? Colors.white : _kBlue,
                          ),
                        ),
                      ),
                    )
                  : Icon(icon,
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
                    color:
                        isActive ? Colors.white.withOpacity(0.7) : _kTextLight),
              if (locked) const SizedBox(width: 4),
              Flexible(
                child: Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color:
                        isActive ? Colors.white.withOpacity(0.75) : _kTextLight,
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
