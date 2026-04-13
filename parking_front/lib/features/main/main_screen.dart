import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../home/presentation/screens/home_screen.dart';
import '../home/presentation/screens/home_no_session_screen.dart';
import '../parking/models/parking.dart';
import '../parking/presentation/map_home_screen.dart';
import '../profile/presentation/screens/profile_screen.dart';
import '../reservation/data/models/parking_session_api_model.dart';
import '../reservation/data/reservation_repository.dart';
import '../scanner/presentation/screens/scanner_screen.dart';

const _kLabels = ['ACCUEIL', 'CARTE', 'SCANNER', 'PROFIL'];
const _kIcons = [
  Icons.home_outlined,
  Icons.map_outlined,
  Icons.qr_code_scanner,
  Icons.person_outline_rounded
];
const _kActiveIcons = [
  Icons.home_rounded,
  Icons.map_rounded,
  Icons.qr_code_scanner,
  Icons.person_rounded
];

class MainScreen extends StatefulWidget {
  final int initialIndex;
  final bool isAuthenticated;
  final Parking? initialMapParking;
  final bool initialMapRoute;

  const MainScreen({
    super.key,
    this.initialIndex = 0,
    this.isAuthenticated = false,
    this.initialMapParking,
    this.initialMapRoute = false,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late int _currentIndex;
  int _homeRefreshTick = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _onTap(int index) {
    if (index == _currentIndex) return;
    HapticFeedback.selectionClick();

    setState(() {
      _currentIndex = index;
      if (index == 0) {
        _homeRefreshTick++;
      }
    });
  }

  void _openHomeWithRefresh() {
    if (!mounted) {
      return;
    }

    setState(() {
      _homeRefreshTick++;
      _currentIndex = 0;
    });
  }

  Widget _buildHomeTab() {
    return _HomeTabGate(
      refreshToken: _homeRefreshTick,
      onSearchTap: () => _onTap(1),
    );
  }

  Widget _buildBody(int index) {
    switch (index) {
      case 0:
        return _buildHomeTab();
      case 1:
        return MapHomeScreen(
          isAuthenticated: widget.isAuthenticated,
          isActive: _currentIndex == 1,
          directReservationOnDetails: true,
          autoNavigateParking: widget.initialMapParking,
          showRouteToSelected: widget.initialMapRoute,
        );
      case 2:
        return ScannerScreen(onScanSuccess: _openHomeWithRefresh);
      case 3:
        return const ProfileScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: _currentIndex == 0 ? AppColors.pageBg : Colors.white,
        // ✅ PAS de AppBar ici — chaque body gère son propre header
        body: IndexedStack(
          index: _currentIndex,
          children: List.generate(4, _buildBody),
        ),
        bottomNavigationBar: _BottomNav(current: _currentIndex, onTap: _onTap),
      ),
    );
  }
}

class _HomeTabGate extends StatefulWidget {
  final int refreshToken;
  final VoidCallback onSearchTap;

  const _HomeTabGate({
    required this.refreshToken,
    required this.onSearchTap,
  });

  @override
  State<_HomeTabGate> createState() => _HomeTabGateState();
}

class _HomeTabGateState extends State<_HomeTabGate> {
  final ReservationRepository _reservationRepository = ReservationRepository();
  ParkingSessionApiModel? _session;
  bool _isBootstrapping = true;

  @override
  void initState() {
    super.initState();
    _loadSession(showLoader: true);
  }

  @override
  void didUpdateWidget(covariant _HomeTabGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _refreshSession();
    }
  }

  void _refreshSession() {
    _loadSession(retryOnNull: true);
  }

  Future<void> _loadSession({
    bool showLoader = false,
    bool forceRefresh = false,
    bool retryOnNull = false,
  }) async {
    final ParkingSessionApiModel? previousSession = _session;

    if (showLoader) {
      setState(() {
        _isBootstrapping = true;
      });
    }

    try {
      ParkingSessionApiModel? session =
          await _reservationRepository.fetchCurrentParkingSession(
        forceRefresh: forceRefresh,
      );

      if (!forceRefresh && retryOnNull && (session == null || !session.isActive)) {
        session = await _reservationRepository.fetchCurrentParkingSession(
          forceRefresh: true,
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _session = (session != null && session.isActive) ? session : null;
        _isBootstrapping = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _session = previousSession;
        _isBootstrapping = false;
      });
    }
  }

  void _handleSessionClosed() {
    if (!mounted) {
      return;
    }

    setState(() {
      _session = null;
      _isBootstrapping = false;
    });

    _loadSession(forceRefresh: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_isBootstrapping && _session == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final ParkingSessionApiModel? session = _session;
    if (session == null) {
      return HomeNoSessionScreen(onSearchTap: widget.onSearchTap);
    }

    return HomeScreen(
      initialSession: session,
      onSessionClosed: _handleSessionClosed,
    );
  }
}

// ─── Navbar ──────────────────────────────────────────────────────────────────
class _BottomNav extends StatelessWidget {
  final int current;
  final void Function(int) onTap;
  const _BottomNav({required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, -4))
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: List.generate(4, (i) {
              final active = i == current;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    margin:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.blue.withValues(alpha: 0.10)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(active ? _kActiveIcons[i] : _kIcons[i],
                              size: 22,
                              color:
                                  active ? AppColors.blue : AppColors.textMid),
                          const SizedBox(height: 3),
                          Text(_kLabels[i],
                              style: TextStyle(
                                  fontSize: 9,
                                  letterSpacing: 0.3,
                                  fontWeight: active
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                  color: active
                                      ? AppColors.blue
                                      : AppColors.textMid)),
                        ]),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
