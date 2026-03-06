import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_colors.dart';
import '../home/presentation/screens/home_no_session_screen.dart';
import '../parking/presentation/map_home_screen.dart';
import '../profile/presentation/screens/profile_screen.dart';
//import '../scanner/presentation/scanner_screen.dart';

const _kLabels      = ['ACCUEIL', 'CARTE', 'SCANNER', 'PROFIL'];
const _kIcons       = [Icons.home_outlined, Icons.map_outlined, Icons.qr_code_scanner, Icons.person_outline_rounded];
const _kActiveIcons = [Icons.home_rounded,  Icons.map_rounded,  Icons.qr_code_scanner, Icons.person_rounded];

class MainScreen extends StatefulWidget {
  final int initialIndex;
  const MainScreen({super.key, this.initialIndex = 0});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _onTap(int index) {
    if (index == _currentIndex) return;
    HapticFeedback.selectionClick();
    setState(() => _currentIndex = index);
  }

  Widget _buildBody(int index) {
    switch (index) {
      case 0: return HomeNoSessionScreen(onSearchTap: () => _onTap(1));
      case 1: return const MapHomeScreen();
      //case 2: return const ScannerScreen();
     case 3: return const ProfileScreen();
      default: return const SizedBox.shrink();
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
          BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, -4))
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
                    margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                    decoration: BoxDecoration(
                      color: active ? AppColors.blue.withOpacity(0.10) : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(active ? _kActiveIcons[i] : _kIcons[i], size: 22,
                          color: active ? AppColors.blue : AppColors.textMid),
                      const SizedBox(height: 3),
                      Text(_kLabels[i], style: TextStyle(
                          fontSize: 9, letterSpacing: 0.3,
                          fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                          color: active ? AppColors.blue : AppColors.textMid)),
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

// ─── Placeholder Carte ────────────────────────────────────────────────────────
class _MapBody extends StatelessWidget {
  const _MapBody();
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.map_rounded, size: 64, color: AppColors.textMid),
        const SizedBox(height: 16),
        Text('Carte des parkings',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.dark)),
        const SizedBox(height: 8),
        Text('Connecte MapHomeScreen ici',
            style: TextStyle(fontSize: 13, color: AppColors.textMid)),
      ])),
    );
  }
}