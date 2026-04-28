import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:parking_front/core/widgets/app_feedback.dart';
import 'package:parking_front/features/main/main_screen.dart';

import '../../../parking/data/parking_data.dart';
import '../../../parking/data/parking_availability_repository.dart';
import '../../../parking/models/parking.dart';
import '../../../parking/presentation/parking_detail_screen.dart';
import '../../../reservation/data/models/reservation_api_model.dart';
import '../../../reservation/data/reservation_repository.dart';

const _kBlue = Color(0xFF4A90E2);
const _kGreen = Color(0xFF27AE60);
const _kBg = Color(0xFFF4F6F9);
const _kCard = Colors.white;
const _kBorder = Color(0xFFE8ECF2);
const _kTextDark = Color(0xFF1A1A2E);
const _kTextMid = Color(0xFF8A9BB5);
const _kRed = Color(0xFFE53935);
const _kRedBg = Color(0xFFFFF0EE);
const _kCancelledVisibilityDuration = Duration(hours: 24);

enum ReservationUiStatus { active, completed, cancelled }

enum ReservationType { mensuel, hebdomadaire, journalier, courteDuree }

String _resolveParkingImageUrlByName(String parkingName) {
  final String needle = parkingName.trim().toLowerCase();
  if (needle.isEmpty) {
    return kParkingPreviewImageUrl;
  }

  for (final Parking parking in ParkingData.parkings) {
    final String name = parking.name.trim().toLowerCase();
    if (name == needle || name.contains(needle) || needle.contains(name)) {
      final String? imageUrl = parking.imageUrl?.trim();
      if (imageUrl != null && imageUrl.isNotEmpty) {
        return imageUrl;
      }
      return kParkingPreviewImageUrl;
    }
  }

  return kParkingPreviewImageUrl;
}

class ReservationModel {
  final String id;
  final String parkingId;
  final String parkingName;
  final String parkingImageUrl;
  final String spotLabel;
  final String location;
  final ReservationType type;
  final ReservationUiStatus uiStatus;
  final String backendStatus;
  final double montant;
  final DateTime? expiresAt;
  final DateTime? startDate;
  final DateTime? endDate;
  final int guaranteeMinutes;

  const ReservationModel({
    required this.id,
    required this.parkingId,
    required this.parkingName,
    required this.parkingImageUrl,
    required this.spotLabel,
    required this.location,
    required this.type,
    required this.uiStatus,
    required this.backendStatus,
    required this.montant,
    required this.guaranteeMinutes,
    this.expiresAt,
    this.startDate,
    this.endDate,
  });

  bool get canGoToParking => backendStatus == 'confirmed';

  bool get canScanTicket => backendStatus == 'in_transit';

  bool get canCancel =>
      backendStatus == 'confirmed' ||
      backendStatus == 'in_transit' ||
      backendStatus == 'pending_payment';

  String get activeLabel {
    switch (backendStatus) {
      case 'in_transit':
        return 'En route vers le parking';
      case 'pending_payment':
        return 'Paiement requis';
      default:
        return 'Reservation active';
    }
  }

  String get cancelledLabel {
    switch (backendStatus) {
      case 'cancelled_by_user':
        return 'Annulee par utilisateur';
      case 'cancelled_timeout':
        return 'Annulee (delai depasse)';
      case 'expired':
        return 'Annulee (expiree)';
      default:
        return 'Annulee';
    }
  }

  factory ReservationModel.fromApi(ReservationApiModel api) {
    final ReservationType mappedType = switch (api.durationType) {
      'mois' => ReservationType.mensuel,
      'semaine' => ReservationType.hebdomadaire,
      'journee' => ReservationType.journalier,
      _ => ReservationType.courteDuree,
    };

    final int guarantee = api.durationType == 'courte' ? 30 : 60;
    final DateTime? start = api.createdAt;
    final DateTime? fallbackExpires =
        (start != null) ? start.add(Duration(minutes: guarantee)) : null;
    final DateTime? expires = api.expiresAt ?? fallbackExpires;

    String status = api.reservationStatus.trim().toLowerCase();
    if (status == 'canceled') {
      status = 'cancelled';
    }

    if (status == 'pending_payment' &&
        api.paymentStatus.trim().toLowerCase() == 'paid') {
      status = 'confirmed';
    }

    final bool expiredByTime =
        expires != null && DateTime.now().isAfter(expires);
    if (expiredByTime && status == 'pending_payment') {
      status = 'cancelled_timeout';
    }

    final ReservationUiStatus uiStatus;
    if (status == 'completed') {
      uiStatus = ReservationUiStatus.completed;
    } else if (status == 'cancelled_by_user' ||
        status == 'cancelled_timeout' ||
        status == 'cancelled' ||
        status == 'expired') {
      uiStatus = ReservationUiStatus.cancelled;
    } else {
      uiStatus = ReservationUiStatus.active;
    }

    final String label = switch (mappedType) {
      ReservationType.courteDuree => 'Courte duree',
      ReservationType.journalier => 'Journee',
      ReservationType.hebdomadaire => 'Semaine',
      ReservationType.mensuel => 'Mois',
    };

    final double price = api.depositRequired ? api.depositAmount : api.amount;

    return ReservationModel(
      id: api.id,
      parkingId: api.parkingId,
      parkingName: api.parkingName,
      parkingImageUrl: _resolveParkingImageUrlByName(api.parkingName),
      spotLabel: label,
      location: api.parkingAddress.isEmpty
          ? 'Adresse indisponible'
          : api.parkingAddress,
      type: mappedType,
      uiStatus: uiStatus,
      backendStatus: status,
      montant: price,
      guaranteeMinutes: guarantee,
      expiresAt: expires,
      startDate: start,
      endDate: uiStatus == ReservationUiStatus.active ? null : api.updatedAt,
    );
  }
}

class MyReservationsScreen extends StatefulWidget {
  const MyReservationsScreen({super.key});

  @override
  State<MyReservationsScreen> createState() => _MyReservationsScreenState();
}

class _MyReservationsScreenState extends State<MyReservationsScreen> {
  static const Duration _screenCacheTtl = Duration(seconds: 20);
  static List<ReservationModel>? _screenCache;
  static DateTime? _screenCacheAt;

  final ReservationRepository _reservationRepository = ReservationRepository();
  final ParkingAvailabilityRepository _availabilityRepository =
      ParkingAvailabilityRepository();

  late Timer _timer;
  List<ReservationModel> _reservations = <ReservationModel>[];
  bool _isLoading = true;
  String? _errorMessage;
  String? _cancellingId;
  Map<String, int> _dynamicSpotsById = const <String, int>{};
  Map<String, int> _dynamicSpotsByName = const <String, int>{};

  @override
  void initState() {
    super.initState();
    final bool hasFreshScreenCache = _screenCache != null &&
        _screenCacheAt != null &&
        DateTime.now().difference(_screenCacheAt!) < _screenCacheTtl;

    if (hasFreshScreenCache) {
      _reservations = List<ReservationModel>.from(_screenCache!);
      _isLoading = false;
    }

    _loadReservations();
    _refreshDynamicAvailability();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Future<void> _loadReservations({
    bool forceRefresh = false,
  }) async {
    final bool showBlockingLoader = _reservations.isEmpty;

    setState(() {
      _isLoading = showBlockingLoader;
      _errorMessage = null;
    });

    try {
      final List<ReservationApiModel> data =
          await _reservationRepository.fetchMyReservations(
        forceRefresh: forceRefresh,
      );
      final List<ReservationModel> mapped =
          data.map(ReservationModel.fromApi).toList(growable: false);

      mapped.sort((ReservationModel a, ReservationModel b) {
        final DateTime ad =
            a.startDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        final DateTime bd =
            b.startDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bd.compareTo(ad);
      });

      if (!mounted) {
        return;
      }

      setState(() {
        _reservations = mapped;
        _isLoading = false;
      });

      _screenCache = List<ReservationModel>.from(mapped);
      _screenCacheAt = DateTime.now();
    } on ReservationException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = 'Impossible de charger vos reservations.';
      });
    }
  }

  Duration _remainingFor(ReservationModel reservation) {
    if (reservation.expiresAt == null ||
        reservation.uiStatus != ReservationUiStatus.active) {
      return Duration.zero;
    }

    final DateTime now = DateTime.now();
    final Duration diff = reservation.expiresAt!.difference(now);
    if (diff.isNegative) {
      return Duration.zero;
    }

    final Duration guarantee = Duration(minutes: reservation.guaranteeMinutes);
    if (diff > guarantee + const Duration(minutes: 5)) {
      final DateTime start = reservation.startDate ?? now;
      final Duration fallback = start.add(guarantee).difference(now);
      if (fallback.isNegative) {
        return Duration.zero;
      }
      return fallback > guarantee ? guarantee : fallback;
    }

    return diff;
  }

  List<ReservationModel> get _active => _reservations
      .where((ReservationModel r) => r.uiStatus == ReservationUiStatus.active)
      .toList(growable: false);

  List<ReservationModel> get _completed => _reservations
      .where(
          (ReservationModel r) => r.uiStatus == ReservationUiStatus.completed)
      .toList(growable: false);

  List<ReservationModel> get _cancelled => _reservations
      .where((ReservationModel r) => _isVisibleCancelled(r))
      .toList(growable: false);

  bool _isVisibleCancelled(ReservationModel reservation) {
    if (reservation.uiStatus != ReservationUiStatus.cancelled) {
      return false;
    }

    final DateTime? cancelledAt = reservation.endDate ?? reservation.startDate;
    if (cancelledAt == null) {
      return true;
    }

    return DateTime.now().difference(cancelledAt) <=
        _kCancelledVisibilityDuration;
  }

  Future<void> _cancelReservation(String reservationId) async {
    setState(() {
      _cancellingId = reservationId;
    });

    try {
      await _reservationRepository.cancelReservation(reservationId);
      await _loadReservations(forceRefresh: true);

      if (!mounted) {
        return;
      }

      AppFeedback.showSuccess(context, 'Reservation annulee avec succes.');
    } on ReservationException catch (error) {
      if (!mounted) {
        return;
      }

      AppFeedback.showError(context, error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }

      AppFeedback.showError(context, 'Erreur lors de l annulation.');
    } finally {
      if (mounted) {
        setState(() {
          _cancellingId = null;
        });
      }
    }
  }

  Future<void> _goToParking(String reservationId) async {
    try {
      await _reservationRepository.markReservationEnRoute(reservationId);
      await _loadReservations(forceRefresh: true);

      if (!mounted) {
        return;
      }

      AppFeedback.showSuccess(
        context,
        'Mode en route active. Scannez le ticket a l arrivee.',
      );
    } on ReservationException catch (error) {
      if (!mounted) {
        return;
      }

      AppFeedback.showError(context, error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }

      AppFeedback.showError(context, 'Impossible de passer en mode en route.');
    }
  }

  Future<void> _scanTicket(String reservationId) async {
    try {
      await _reservationRepository.completeReservationByTicket(reservationId);
      await _loadReservations(forceRefresh: true);

      if (!mounted) {
        return;
      }

      AppFeedback.showSuccess(context, 'Ticket scanne. Reservation terminee.');
    } on ReservationException catch (error) {
      if (!mounted) {
        return;
      }

      AppFeedback.showError(context, error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }

      AppFeedback.showError(context, 'Erreur lors du scan ticket.');
    }
  }

  Future<void> _openReservationDetails(ReservationModel reservation) async {
    await _refreshDynamicAvailability();

    if (!mounted) {
      return;
    }

    final Parking resolvedParking = _withDynamicAvailability(
      _resolveParking(reservation.parkingName,
          parkingId: reservation.parkingId),
    );

    final String? action = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (BuildContext context) => ParkingDetailScreen(
          parking: resolvedParking,
          isAuthenticated: true,
          hideReserveButton: true,
          reservationStatus: reservation.backendStatus,
        ),
      ),
    );

    if (!mounted || action == null) {
      return;
    }

    if (action == 'go') {
      await _goToParking(reservation.id);
      return;
    }

    if (action == 'scan-ticket') {
      await _scanTicket(reservation.id);
    }
  }

  void _handleBackNavigation() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const MainScreen(
          initialIndex: 3,
          isAuthenticated: true,
        ),
      ),
      (Route<dynamic> route) => false,
    );
  }

  Future<void> _refreshDynamicAvailability() async {
    try {
      final availability = await _availabilityRepository.fetchAvailability();
      if (!mounted) {
        return;
      }

      final Map<String, int> byId = <String, int>{};
      final Map<String, int> byName = <String, int>{};
      for (final item in availability) {
        final String id = item.parkingId.trim();
        if (id.isNotEmpty) {
          byId[id] = item.availableSpots;
        }

        final String key = _normalizeParkingName(item.parkingName);
        if (key.isNotEmpty) {
          byName[key] = item.availableSpots;
        }
      }

      setState(() {
        _dynamicSpotsById = byId;
        _dynamicSpotsByName = byName;
      });
    } catch (_) {
      // Keep static values if availability API is temporarily unreachable.
    }
  }

  String _normalizeParkingName(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ä', 'a')
        .replaceAll('á', 'a')
        .replaceAll('ã', 'a')
        .replaceAll('å', 'a')
        .replaceAll('ç', 'c')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ì', 'i')
        .replaceAll('î', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('ñ', 'n')
        .replaceAll('ó', 'o')
        .replaceAll('ò', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ù', 'u')
        .replaceAll('û', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ý', 'y')
        .replaceAll('ÿ', 'y');
  }

  Parking _withDynamicAvailability(Parking parking) {
    final int? byId = _dynamicSpotsById[parking.id];
    final int resolved = byId ??
        _dynamicSpotsByName[_normalizeParkingName(parking.name)] ??
        parking.availableSpots;

    if (resolved == parking.availableSpots) {
      return parking;
    }

    return parking.copyWith(
      availableSpots: resolved,
      lastUpdate: 'Mis a jour via serveur',
    );
  }

  Parking _resolveParking(String parkingName, {String? parkingId}) {
    final String idNeedle = (parkingId ?? '').trim();
    if (idNeedle.isNotEmpty) {
      for (final Parking parking in ParkingData.parkings) {
        if (parking.id.trim() == idNeedle) {
          return parking;
        }
      }
    }

    final String needle = parkingName.trim().toLowerCase();

    for (final Parking parking in ParkingData.parkings) {
      final String name = parking.name.trim().toLowerCase();
      if (name == needle || name.contains(needle) || needle.contains(name)) {
        return parking;
      }
    }

    return ParkingData.parkings.first;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (bool didPop) {
        if (didPop) {
          return;
        }
        _handleBackNavigation();
      },
      child: Scaffold(
        backgroundColor: _kBg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          leading: GestureDetector(
            onTap: _handleBackNavigation,
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
          title: const Text(
            'Mes Reservations',
            style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 18, color: _kTextDark),
          ),
          centerTitle: true,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadReservations,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    if (_errorMessage != null && _reservations.isEmpty) ...[
                      _errorState(_errorMessage!),
                      const SizedBox(height: 20),
                    ],
                    if (_active.isNotEmpty) ...[
                      _sectionTitle('RESERVATIONS EN COURS'),
                      const SizedBox(height: 10),
                      ..._active.map((ReservationModel r) => _ActiveCard(
                            reservation: r,
                            remaining: _remainingFor(r),
                            isCancelling: _cancellingId == r.id,
                            onCancel: () => _cancelReservation(r.id),
                            onDetails: () => _openReservationDetails(r),
                          )),
                      const SizedBox(height: 20),
                    ],
                    if (_completed.isNotEmpty) ...[
                      _sectionTitle('RESERVATIONS TERMINEES'),
                      const SizedBox(height: 10),
                      ..._completed.map((ReservationModel r) => _HistoryCard(
                            reservation: r,
                            badgeLabel: 'TERMINEE',
                            badgeBg: const Color(0xFFE8F8EF),
                            badgeFg: _kGreen,
                          )),
                      const SizedBox(height: 20),
                    ],
                    if (_cancelled.isNotEmpty) ...[
                      _sectionTitle('RESERVATIONS ANNULEES'),
                      const SizedBox(height: 4),
                      const Text(
                        'Les reservations annulees restent visibles 24h puis sont masquees.',
                        style: TextStyle(fontSize: 12, color: _kTextMid),
                      ),
                      const SizedBox(height: 10),
                      ..._cancelled.map((ReservationModel r) => _HistoryCard(
                            reservation: r,
                            badgeLabel: r.cancelledLabel.toUpperCase(),
                            badgeBg: _kRedBg,
                            badgeFg: _kRed,
                          )),
                    ],
                    if (_active.isEmpty &&
                        _completed.isEmpty &&
                        _cancelled.isEmpty &&
                        _errorMessage == null)
                      _emptyState(),
                  ],
                ),
              ),
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

  Widget _errorState(String message) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kBorder),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Icon(Icons.error_outline_rounded, color: _kRed),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _kTextMid)),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _loadReservations,
              style: ElevatedButton.styleFrom(
                  backgroundColor: _kBlue, elevation: 0),
              child: const Text('Reessayer',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 80),
          child: Column(children: [
            Icon(Icons.bookmark_border_rounded,
                size: 64, color: _kTextMid.withOpacity(0.4)),
            const SizedBox(height: 16),
            const Text(
              'Aucune reservation',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600, color: _kTextMid),
            ),
            const SizedBox(height: 6),
            const Text('Vos reservations apparaitront ici.',
                style: TextStyle(fontSize: 13, color: _kTextMid)),
          ]),
        ),
      );
}

class _ActiveCard extends StatelessWidget {
  final ReservationModel reservation;
  final Duration remaining;
  final bool isCancelling;
  final Future<void> Function() onCancel;
  final VoidCallback onDetails;

  const _ActiveCard({
    required this.reservation,
    required this.remaining,
    required this.isCancelling,
    required this.onCancel,
    required this.onDetails,
  });

  String _pad(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final String hh = _pad(remaining.inHours);
    final String mm = _pad(remaining.inMinutes.remainder(60));
    final String ss = _pad(remaining.inSeconds.remainder(60));
    final bool hasTimer = reservation.expiresAt != null;
    final bool expired = hasTimer && remaining == Duration.zero;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 64,
                height: 64,
                color: const Color(0xFFEAF1FB),
                child: Image.network(
                  reservation.parkingImageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Image.asset(
                    'assets/images/parking.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reservation.parkingName,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _kTextDark),
                    ),
                    const SizedBox(height: 2),
                    Text(reservation.spotLabel,
                        style: const TextStyle(fontSize: 12, color: _kTextMid)),
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.location_on_outlined,
                          size: 13, color: _kBlue),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          reservation.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12,
                              color: _kBlue,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF1FB),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        reservation.activeLabel,
                        style: const TextStyle(
                            fontSize: 11,
                            color: _kBlue,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ]),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1FB),
              borderRadius: BorderRadius.circular(14),
            ),
            child: hasTimer
                ? Column(children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          expired
                              ? 'DELAI EXPIRE'
                              : 'GARANTIE ${reservation.guaranteeMinutes} MIN',
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
                    LayoutBuilder(
                      builder:
                          (BuildContext context, BoxConstraints constraints) {
                        final double blockWidth =
                            ((constraints.maxWidth - 24) / 3).clamp(50.0, 62.0);

                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _timeBlock(hh, 'HEURES', width: blockWidth),
                            _colon(),
                            _timeBlock(mm, 'MIN', width: blockWidth),
                            _colon(),
                            _timeBlock(ss, 'SEC', width: blockWidth),
                          ],
                        );
                      },
                    ),
                  ])
                : const Center(
                    child: Text(
                      'Aucun delai actif pour cette reservation.',
                      style: TextStyle(fontSize: 12, color: _kTextMid),
                      textAlign: TextAlign.center,
                    ),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onDetails,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _kBorder),
                  fixedSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.info_outline_rounded,
                    color: _kTextMid, size: 16),
                label: const Text(
                  'Details',
                  style: TextStyle(
                      color: _kTextDark,
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: (!reservation.canCancel || isCancelling)
                    ? null
                    : () => _confirmCancel(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kRed,
                  elevation: 0,
                  fixedSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: isCancelling
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.close_rounded,
                        color: Colors.white, size: 16),
                label: Text(
                  isCancelling ? 'Annulation...' : 'Annuler reservation',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _timeBlock(String val, String label, {double width = 62}) {
    return Column(children: [
      Container(
        width: width,
        height: 50,
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(10)),
        child: Center(
          child: Text(
            val,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: _kTextDark,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: _kTextMid,
          letterSpacing: 0.5,
        ),
      ),
    ]);
  }

  Widget _colon() => const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: Text(' : ',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w300, color: _kTextMid)),
      );

  void _confirmCancel(BuildContext context) {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
                color: _kRedBg, borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.cancel_outlined, color: _kRed, size: 28),
          ),
          const SizedBox(height: 14),
          const Text(
            'Annuler la reservation ?',
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: _kTextDark),
          ),
          const SizedBox(height: 8),
          const Text(
            'Cette action est irreversible. Votre place sera liberee.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: _kTextMid, height: 1.5),
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
                        color: _kTextDark, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await onCancel();
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
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final ReservationModel reservation;
  final String badgeLabel;
  final Color badgeBg;
  final Color badgeFg;

  const _HistoryCard({
    required this.reservation,
    required this.badgeLabel,
    required this.badgeBg,
    required this.badgeFg,
  });

  String _fmt(DateTime? dt) {
    if (dt == null) {
      return '';
    }

    return '${dt.day.toString().padLeft(2, '0')} ${_monthFr(dt.month)} ${dt.year}';
  }

  String _monthFr(int m) => const <String>[
        '',
        'Jan',
        'Fev',
        'Mar',
        'Avr',
        'Mai',
        'Jun',
        'Jul',
        'Aou',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1FB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                reservation.parkingImageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Image.asset(
                  'assets/images/parking.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                reservation.parkingName,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _kTextDark),
              ),
              const SizedBox(height: 3),
              Text(reservation.spotLabel,
                  style: const TextStyle(fontSize: 12, color: _kTextMid)),
              const SizedBox(height: 3),
              Text(
                'Debut: ${_fmt(reservation.startDate)} - Fin: ${_fmt(reservation.endDate)}',
                style: const TextStyle(fontSize: 11, color: _kTextMid),
              ),
              const SizedBox(height: 8),
              Text(
                reservation.type == ReservationType.courteDuree &&
                        reservation.montant <= 0
                    ? 'Paiement a la sortie'
                    : '${reservation.montant.toStringAsFixed(2).replaceAll('.', ',')} DA',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _kTextDark),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
              color: badgeBg, borderRadius: BorderRadius.circular(16)),
          child: Text(
            badgeLabel,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: badgeFg),
          ),
        ),
      ]),
    );
  }
}
