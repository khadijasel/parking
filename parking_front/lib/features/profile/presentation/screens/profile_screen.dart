import 'package:flutter/material.dart';
import 'package:parking_front/features/auth/data/auth_repository.dart';
import 'package:parking_front/features/auth/presentation/login_screen.dart';
import 'package:parking_front/features/profile/presentation/screens/my_reservations_screen.dart';
import 'parking_history_screen.dart';
import 'edit_profile_screen.dart';

const _kBlue = Color(0xFF4A90E2);
const _kDark = Color(0xFF1A1A2E);
const _kMid = Color(0xFF8A9BB5);
const _kBgRow = Color(0xFFF4F7FC);
const _kRed = Color(0xFFE53935);
const _kRedBg = Color(0xFFFFF0EE);

/// Écran Profil — fidèle à la maquette image 2
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AuthRepository authRepository = AuthRepository();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.maybePop(context),
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
        title: const Text('Profil',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: _kDark)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(children: [
          const SizedBox(height: 24),

          // ── Avatar ──────────────────────────────────────────────────────
          Center(
            child: Stack(children: [
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFD6E6F7), width: 3),
                ),
                child: ClipOval(
                  child: Container(
                    color: const Color(0xFFEAF1FB),
                    child: const Icon(Icons.person_rounded,
                        size: 70, color: _kBlue),
                  ),
                ),
              ),
              Positioned(
                bottom: 2,
                right: 2,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _kBlue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.edit_rounded,
                      size: 15, color: Colors.white),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // ── Nom + plaque + ville ────────────────────────────────────────
          const Text('Ahmed Benali',
              style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w800, color: _kDark)),
          const SizedBox(height: 6),
          const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.directions_car_rounded, size: 16, color: _kBlue),
            SizedBox(width: 6),
            Text('16-12345-01-16',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: _kDark)),
          ]),
          const SizedBox(height: 4),
          const Text('Alger, Algérie',
              style: TextStyle(fontSize: 14, color: _kMid)),
          const SizedBox(height: 36),

          // ── ACTIVITÉS ───────────────────────────────────────────────────
          const _SectionLabel(label: 'ACTIVITÉS'),
          const SizedBox(height: 12),
          _MenuRow(
            iconBg: const Color(0xFFEAF1FB),
            icon: Icons.history_rounded,
            iconColor: _kBlue,
            title: 'Historique des parkings',
            subtitle: 'Voir vos arrêts passés',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ParkingHistoryScreen()),
              );
            },
          ),
          const SizedBox(height: 10),
          _MenuRow(
            iconBg: const Color(0xFFEAF1FB),
            icon: Icons.calendar_month_rounded,
            iconColor: _kBlue,
            title: 'Mes réservations',
            subtitle: 'Gérer vos réservations actives',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MyReservationsScreen()),
              );
            },
          ),
          const SizedBox(height: 28),

          // ── PARAMÈTRES ──────────────────────────────────────────────────
          const _SectionLabel(label: 'PARAMÈTRES'),
          const SizedBox(height: 12),
          _MenuRow(
            iconBg: const Color(0xFFF0F4FA),
            icon: Icons.person_outline_rounded,
            iconColor: _kMid,
            title: 'Modifier le profil',
            subtitle: 'Nom, email, véhicule',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EditProfileScreen()),
              );
            },
          ),
          const SizedBox(height: 10),

          // Déconnexion — fond rouge pâle
          _MenuRow(
            iconBg: _kRedBg,
            icon: Icons.logout_rounded,
            iconColor: _kRed,
            title: 'Déconnexion',
            titleColor: _kRed,
            onTap: () async {
              await authRepository.logout();
              if (!context.mounted) return;

              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            showArrow: false,
            bgColor: _kRedBg,
          ),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }
}

// ─── Widgets locaux ──────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _kMid,
                letterSpacing: 1.3)),
      );
}

class _MenuRow extends StatelessWidget {
  final Color iconBg;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Color? titleColor;
  final Color? bgColor;
  final bool showArrow;
  final VoidCallback onTap;

  const _MenuRow({
    required this.iconBg,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.titleColor,
    this.bgColor,
    this.showArrow = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bgColor ?? _kBgRow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, size: 22, color: iconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: titleColor ?? _kDark)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      style: const TextStyle(fontSize: 13, color: _kMid)),
                ],
              ])),
          if (showArrow)
            const Icon(Icons.chevron_right_rounded, color: _kMid, size: 22),
        ]),
      ),
    );
  }
}
