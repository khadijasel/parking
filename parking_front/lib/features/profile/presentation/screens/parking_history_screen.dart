import 'package:flutter/material.dart';
import '../../../../features/main/main_screen.dart';
import '../../../parking/data/parking_data.dart';
import '../../../parking/models/parking.dart';
import '../../../parking/presentation/parking_detail_screen.dart';
import '../../../reservation/data/models/parking_session_api_model.dart';
import '../../../reservation/data/reservation_repository.dart';

// ─── Constantes locales ─────────────────────────────────────────────────────
const _kBg = Color(0xFFF4F7FC);
const _kDark = Color(0xFF1A1A2E);
const _kMid = Color(0xFF8A9BB5);
const _kBlue = Color(0xFF4A90E2);
const _kGreen = Color(0xFF2ECC71);
const _kGreenBg = Color(0xFFE8F5E9);
const _kBlueBg = Color(0xFFEAF1FB);

// ─── Modèle simplifié ───────────────────────────────────────────────────────
enum _SessionStatus { enCours, termine }

enum _HistoryFilter { toutes, enCours, terminees }

class _ParkingSession {
  final String parkingName;
  final String parkingImageUrl;
  final String sessionId;
  final String dateHeure;
  final String duree;
  final int totalCost;
  final _SessionStatus status;

  const _ParkingSession({
    required this.parkingName,
    required this.parkingImageUrl,
    required this.sessionId,
    required this.dateHeure,
    required this.duree,
    required this.totalCost,
    required this.status,
  });
}

// ─── Données statiques ──────────────────────────────────────────────────────
// ─── ÉCRAN HISTORIQUE ───────────────────────────────────────────────────────
class ParkingHistoryScreen extends StatefulWidget {
  const ParkingHistoryScreen({super.key});

  @override
  State<ParkingHistoryScreen> createState() => _ParkingHistoryScreenState();
}

class _ParkingHistoryScreenState extends State<ParkingHistoryScreen> {
  static const Duration _screenCacheTtl = Duration(seconds: 20);
  static List<_ParkingSession>? _screenCache;
  static DateTime? _screenCacheAt;

  final ReservationRepository _reservationRepository = ReservationRepository();

  bool _isLoading = true;
  String? _errorMessage;
  List<_ParkingSession> _sessions = <_ParkingSession>[];
  _HistoryFilter _historyFilter = _HistoryFilter.toutes;

  @override
  void initState() {
    super.initState();
    final bool hasFreshScreenCache = _screenCache != null &&
        _screenCacheAt != null &&
        DateTime.now().difference(_screenCacheAt!) < _screenCacheTtl;

    if (hasFreshScreenCache) {
      _sessions = List<_ParkingSession>.from(_screenCache!);
      _isLoading = false;
    }

    _loadHistory();
  }

  Future<void> _loadHistory({
    bool forceRefresh = false,
  }) async {
    final bool shouldShowBlockingLoader = _sessions.isEmpty;

    setState(() {
      _isLoading = shouldShowBlockingLoader;
      _errorMessage = null;
    });

    try {
      final Future<ParkingSessionApiModel?> currentSessionFuture =
          _reservationRepository.fetchCurrentParkingSession(
        forceRefresh: forceRefresh,
      );
      final Future<List<ParkingSessionApiModel>> historyFuture =
          _reservationRepository.fetchParkingSessionHistory(
        forceRefresh: forceRefresh,
      );

      final ParkingSessionApiModel? currentSession = await currentSessionFuture;
      final List<ParkingSessionApiModel> history = await historyFuture;

      final List<_ParkingSession> mapped = <_ParkingSession>[];

      if (currentSession != null && currentSession.isActive) {
        final int liveDurationSeconds =
            _computeLiveDurationSeconds(currentSession);

        mapped.add(_ParkingSession(
          parkingName: currentSession.parkingName.isEmpty
              ? 'Session parking'
              : currentSession.parkingName,
          parkingImageUrl: _resolveParkingImageUrl(
            currentSession.parkingName,
          ),
          sessionId: currentSession.ticketCode.isEmpty
              ? currentSession.id
              : currentSession.ticketCode,
          dateHeure: _formatDate(currentSession.startedAt),
          duree: _formatDuration(liveDurationSeconds),
          totalCost: _computeSessionCost(
            currentSession,
            durationSecondsOverride: liveDurationSeconds,
          ),
          status: _SessionStatus.enCours,
        ));
      }

      mapped.addAll(history.map((ParkingSessionApiModel item) {
        return _ParkingSession(
          parkingName:
              item.parkingName.isEmpty ? 'Session parking' : item.parkingName,
          parkingImageUrl: _resolveParkingImageUrl(item.parkingName),
          sessionId: item.ticketCode.isEmpty ? item.id : item.ticketCode,
          dateHeure: _formatDate(item.endedAt ?? item.startedAt),
          duree: _formatDuration(item.durationSeconds),
          totalCost: _computeSessionCost(item),
          status: _SessionStatus.termine,
        );
      }));

      if (!mounted) {
        return;
      }

      setState(() {
        _sessions = mapped;
        _isLoading = false;
      });

      _screenCache = List<_ParkingSession>.from(mapped);
      _screenCacheAt = DateTime.now();
    } on ReservationException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        if (_sessions.isEmpty) {
          _sessions = <_ParkingSession>[];
        }
        _isLoading = false;
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        if (_sessions.isEmpty) {
          _sessions = <_ParkingSession>[];
        }
        _isLoading = false;
        _errorMessage = 'Impossible de charger l\'historique.';
      });
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) {
      return 'Date inconnue';
    }

    final DateTime local = date.toLocal();
    final String dd = local.day.toString().padLeft(2, '0');
    final String mm = local.month.toString().padLeft(2, '0');
    final String yyyy = local.year.toString();
    final String hh = local.hour.toString().padLeft(2, '0');
    final String min = local.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy, $hh:$min';
  }

  String _formatDuration(int? durationSeconds) {
    if (durationSeconds == null || durationSeconds <= 0) {
      return '0h 00min';
    }

    final int totalMinutes = durationSeconds ~/ 60;
    final int hours = totalMinutes ~/ 60;
    final int minutes = totalMinutes % 60;
    return '${hours}h ${minutes.toString().padLeft(2, '0')}min';
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

  String _resolveParkingImageUrl(String parkingName) {
    final String needle = parkingName.trim().toLowerCase();
    if (needle.isEmpty) {
      return kParkingPreviewImageUrl;
    }

    for (final Parking parking in ParkingData.parkings) {
      final String candidate = parking.name.trim().toLowerCase();
      if (candidate == needle ||
          candidate.contains(needle) ||
          needle.contains(candidate)) {
        final String? imageUrl = parking.imageUrl?.trim();
        if (imageUrl != null && imageUrl.isNotEmpty) {
          return imageUrl;
        }
        return kParkingPreviewImageUrl;
      }
    }

    return kParkingPreviewImageUrl;
  }

  int _computeLiveDurationSeconds(ParkingSessionApiModel session) {
    final DateTime? start = session.startedAt ?? session.createdAt;
    if (start == null) {
      return (session.durationSeconds ?? 0).clamp(0, 2147483647).toInt();
    }

    final int live = DateTime.now().difference(start).inSeconds;
    return live < 0 ? 0 : live;
  }

  int _computeSessionCost(
    ParkingSessionApiModel session, {
    int? durationSecondsOverride,
  }) {
    final int durationSeconds =
        durationSecondsOverride ?? session.durationSeconds ?? 0;
    if (durationSeconds <= 0) {
      return 0;
    }

    final double total =
        _resolveParkingRate(session.parkingName) * (durationSeconds / 3600.0);
    return total < 0 ? 0 : total.round();
  }

  @override
  Widget build(BuildContext context) {
    final List<_ParkingSession> filteredSessions = switch (_historyFilter) {
      _HistoryFilter.toutes => _sessions,
      _HistoryFilter.enCours => _sessions
          .where((s) => s.status == _SessionStatus.enCours)
          .toList(growable: false),
      _HistoryFilter.terminees => _sessions
          .where((s) => s.status == _SessionStatus.termine)
          .toList(growable: false),
    };

    final List<_ParkingSession> enCours = filteredSessions
        .where((s) => s.status == _SessionStatus.enCours)
        .toList(growable: false);
    final List<_ParkingSession> terminees = filteredSessions
        .where((s) => s.status == _SessionStatus.termine)
        .toList(growable: false);

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
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 18, color: _kDark),
          ),
        ),
        centerTitle: true,
        title: const Text(
          'Historique',
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w700, color: _kDark),
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
            child: PopupMenuButton<_HistoryFilter>(
              tooltip: 'Filtrer',
              initialValue: _historyFilter,
              onSelected: (_HistoryFilter selected) {
                setState(() {
                  _historyFilter = selected;
                });
              },
              itemBuilder: (BuildContext context) =>
                  const <PopupMenuEntry<_HistoryFilter>>[
                PopupMenuItem<_HistoryFilter>(
                  value: _HistoryFilter.toutes,
                  child: Text('Toutes'),
                ),
                PopupMenuItem<_HistoryFilter>(
                  value: _HistoryFilter.enCours,
                  child: Text('En cours'),
                ),
                PopupMenuItem<_HistoryFilter>(
                  value: _HistoryFilter.terminees,
                  child: Text('Terminees'),
                ),
              ],
              icon: const Icon(
                Icons.filter_list_rounded,
                size: 20,
                color: _kDark,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!_isLoading && _errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 12),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: _kMid, fontSize: 13),
                ),
              ),

            // ── Section EN COURS ──────────────────────────────────────
            if (!_isLoading && enCours.isNotEmpty) ...[
              const _SectionTitle(title: 'EN COURS'),
              const SizedBox(height: 12),
              ...enCours.map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ActiveSessionCard(
                      session: s,
                      onManage: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (BuildContext context) => const MainScreen(
                              initialIndex: 0,
                              isAuthenticated: true,
                            ),
                          ),
                        );

                        if (!mounted) {
                          return;
                        }

                        await _loadHistory(forceRefresh: true);
                      },
                    ),
                  )),
              const SizedBox(height: 12),
            ],

            // ── Section TERMINÉES ─────────────────────────────────────
            if (!_isLoading && terminees.isNotEmpty) ...[
              const _SectionTitle(title: 'TERMINÉES'),
              const SizedBox(height: 12),
              ...terminees.map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _CompletedSessionCard(session: s),
                  )),
            ],
            if (!_isLoading && enCours.isEmpty && terminees.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Center(
                  child: Text(
                    _historyFilter == _HistoryFilter.toutes
                        ? 'Aucune session de parking.'
                        : 'Aucun resultat pour ce filtre.',
                    style: const TextStyle(color: _kMid, fontSize: 13),
                  ),
                ),
              ),
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
  final Future<void> Function() onManage;

  const _ActiveSessionCard({
    required this.session,
    required this.onManage,
  });

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
              _buildParkingIcon(
                imageUrl: session.parkingImageUrl,
                isActive: true,
              ),
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
              _buildInfoColumn('DURÉE ACTUELLE', session.duree,
                  valueColor: _kBlue),
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
                onPressed: () {
                  onManage();
                },
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('Gérer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
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
              _buildParkingIcon(
                imageUrl: session.parkingImageUrl,
                isActive: false,
              ),
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
          // Coût total
          const Text(
            'COÛT TOTAL',
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
Widget _buildParkingIcon({required String imageUrl, required bool isActive}) {
  return Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      color: const Color(0xFFEAF1FB),
      borderRadius: BorderRadius.circular(14),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Image.asset(
          'assets/images/parking.png',
          fit: BoxFit.contain,
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
