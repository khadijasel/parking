import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:latlong2/latlong.dart';

import 'package:parking_front/features/auth/data/auth_local_storage.dart';
import 'package:parking_front/features/auth/data/auth_repository.dart';
import 'package:parking_front/features/auth/presentation/login_screen.dart';
import 'package:parking_front/core/services/location_service.dart';
import 'package:parking_front/features/parking/data/parking_data.dart';
import 'package:parking_front/features/profile/data/profile_repository.dart';
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
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthRepository _authRepository = AuthRepository();
  final AuthLocalStorage _authLocalStorage = AuthLocalStorage();
  final ProfileRepository _profileRepository = ProfileRepository();

  String _displayName = 'Utilisateur';
  String _displayMatricule = 'Matricule non renseigne';
  String _displayCity = 'Ville non renseignee';
  String? _avatarDataUrl;

  @override
  void initState() {
    super.initState();
    _loadUserFromSession();
    _detectCityFromLocation();
  }

  Future<void> _loadUserFromSession() async {
    final Map<String, dynamic>? localUser = await _authLocalStorage.readUser();
    if (!mounted || localUser == null) {
      return;
    }

    _applyUser(localUser);

    try {
      final Map<String, dynamic> remoteUser =
          await _profileRepository.fetchProfile();
      if (!mounted) {
        return;
      }
      _applyUser(remoteUser);
    } catch (_) {
      // Keep local fallback if backend refresh fails.
    }
  }

  void _applyUser(Map<String, dynamic> user) {
    final String name = (user['name'] ?? '').toString().trim();
    final String matricule = (user['matricule'] ?? '').toString().trim();
    final String city = (user['city'] ?? '').toString().trim();
    final String avatarDataUrl =
        (user['avatar_data_url'] ?? '').toString().trim();

    setState(() {
      _displayName = name.isEmpty ? 'Utilisateur' : name;
      _displayMatricule =
          matricule.isEmpty ? 'Matricule non renseigne' : matricule;
      _displayCity = city.isEmpty ? 'Ville non renseignee' : city;
      _avatarDataUrl = avatarDataUrl.isEmpty ? null : avatarDataUrl;
    });
  }

  Future<void> _detectCityFromLocation() async {
    final LatLng? current = await LocationService.getCurrentLocation();
    if (!mounted || current == null) {
      return;
    }

    final String city = _resolveNearestCity(current);
    if (city.isEmpty) {
      return;
    }

    setState(() {
      _displayCity = city;
    });

    // Keep profile city synchronized with automatic GPS detection when possible.
    try {
      await _profileRepository.updateProfile(city: city);
    } catch (_) {
      // Non-blocking: UI keeps detected city even if server update fails.
    }
  }

  String _resolveNearestCity(LatLng current) {
    double nearestDistance = double.infinity;
    String nearestAddress = '';

    for (final parking in ParkingData.parkings) {
      final double d = LocationService.distanceKm(current, parking.location);
      if (d < nearestDistance) {
        nearestDistance = d;
        nearestAddress = parking.address;
      }
    }

    final String lower = nearestAddress.toLowerCase();
    if (lower.contains('tlemcen')) {
      return 'Tlemcen';
    }
    if (lower.contains('alger')) {
      return 'Alger';
    }

    return current.latitude < 35.5 ? 'Tlemcen' : 'Alger';
  }

  ImageProvider<Object>? _avatarProvider() {
    final String? dataUrl = _avatarDataUrl;
    if (dataUrl == null || dataUrl.isEmpty) {
      return null;
    }

    try {
      final int commaIndex = dataUrl.indexOf(',');
      if (commaIndex <= 0 || commaIndex >= dataUrl.length - 1) {
        return null;
      }
      final String base64Part = dataUrl.substring(commaIndex + 1);
      final bytes = base64Decode(base64Part);
      if (bytes.isEmpty) {
        return null;
      }
      return MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  void _openAvatarPreview(ImageProvider<Object> avatar) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (BuildContext dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Stack(
            alignment: Alignment.topRight,
            children: [
              Center(
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                    image: DecorationImage(
                      image: avatar,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 30),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openEditProfile() async {
    final bool? hasChanged = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const EditProfileScreen()),
    );

    if (hasChanged == true && mounted) {
      await _loadUserFromSession();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ImageProvider<Object>? avatar = _avatarProvider();

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
              GestureDetector(
                onTap: avatar != null ? () => _openAvatarPreview(avatar) : null,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: const Color(0xFFD6E6F7), width: 3),
                  ),
                  child: ClipOval(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF1FB),
                        image: avatar != null
                            ? DecorationImage(
                                image: avatar,
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: avatar == null
                          ? const Icon(Icons.person_rounded,
                              size: 70, color: _kBlue)
                          : null,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 2,
                right: 2,
                child: GestureDetector(
                  onTap: _openEditProfile,
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
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // ── Nom + plaque + ville ────────────────────────────────────────
          Text(_displayName,
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w800, color: _kDark)),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.directions_car_rounded, size: 16, color: _kBlue),
            const SizedBox(width: 6),
            Text(_displayMatricule,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: _kDark)),
          ]),
          const SizedBox(height: 4),
          Text(_displayCity,
              style: const TextStyle(fontSize: 14, color: _kMid)),
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
            subtitle: 'Nom, email, telephone, matricule, photo',
            onTap: () async {
              final bool? hasChanged = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (_) => const EditProfileScreen()),
              );

              if (hasChanged == true && mounted) {
                await _loadUserFromSession();
              }
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
              await _authRepository.logout();
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
