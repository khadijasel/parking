import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../../theme/app_colors.dart';
import '../../auth/presentation/login_screen.dart';
import '../../reservation/presentation/screens/reservation_screen.dart';
import 'map_home_screen.dart';
import '../../main/main_screen.dart';
import '../models/parking.dart';

class ParkingDetailScreen extends StatelessWidget {
  final Parking parking;
  final bool isAuthenticated;
  final LatLng? userLocation;
  // ✅ NOUVEAU : masque le bouton "Réserver" quand on vient de Mes Réservations
  final bool hideReserveButton;

  const ParkingDetailScreen({
    super.key,
    required this.parking,
    this.isAuthenticated = false,
    this.userLocation,
    this.hideReserveButton = false, // false par défaut = comportement normal
  });

  void _navigateToLogin(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  void _navigateToReservation(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReservationScreen(
          parkingName: parking.name,
          parkingAddress: parking.address,
          equipments: parking.equipments,
        ),
      ),
    );
  }

  String _distanceText() {
    if (userLocation == null) return '1.2 km';
    final d = const Distance()
        .as(LengthUnit.Kilometer, userLocation!, parking.location);
    return '${d.toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          'Détails du parking',
          style: TextStyle(
            color: AppColors.textDark,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, color: AppColors.textDark),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildImage(),
                  const SizedBox(height: 20),
                  _buildHeader(),
                  const SizedBox(height: 8),
                  _buildSubInfo(),
                  const SizedBox(height: 20),
                  _buildAvailabilityCard(),
                  const SizedBox(height: 24),
                  _buildEquipments(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          // ✅ Boutons bas : adaptatifs selon hideReserveButton
          _buildBottomButtons(context),
        ],
      ),
    );
  }

  Widget _buildImage() {
    return Container(
      width: double.infinity,
      height: 200,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.grey.shade200,
        image: const DecorationImage(
          image: NetworkImage(
            'https://images.unsplash.com/photo-1590674899484-d5640e854abe?w=800',
          ),
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              parking.name,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star_border,
                    size: 18, color: Color(0xFFFFA000)),
                const SizedBox(width: 4),
                Text(
                  parking.rating.toString(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Color(0xFFFFA000),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(Icons.navigation_outlined,
              size: 16, color: Colors.grey.shade500),
          const SizedBox(width: 4),
          Text(
            _distanceText(),
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(width: 16),
          Icon(Icons.access_time, size: 16, color: Colors.grey.shade500),
          const SizedBox(width: 4),
          Text(
            parking.isOpen24h ? 'Ouvert 24h/7j' : 'Horaires limités',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailabilityCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: AppColors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${parking.availableSpots} places disponibles',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              parking.lastUpdate,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.local_parking,
                  size: 18, color: AppColors.textDark),
              const SizedBox(width: 6),
              Text(
                '${parking.pricePerHour.toInt()} DA',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              Text(
                '/heure',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEquipments() {
    final equipmentIcons = {
      'GPL Autorisé': Icons.local_gas_station_outlined,
      'Sécurité 24/7': Icons.shield_outlined,
      'Vidéosurveillance': Icons.videocam_outlined,
      'Accessible Handi': Icons.accessible,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Équipements',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: parking.equipments.map((equip) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      equipmentIcons[equip] ?? Icons.check_circle_outline,
                      size: 20,
                      color: AppColors.blue,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      equip,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textDark,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButtons(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // ✅ Bouton Réserver : masqué si hideReserveButton = true
          if (!hideReserveButton) ...[
            Expanded(
              flex: 1,
              child: OutlinedButton.icon(
                onPressed: () {
                  if (isAuthenticated) {
                    _navigateToReservation(context);
                    return;
                  }
                  _navigateToLogin(context);
                },
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: const Text('Réserver'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.blue,
                  side: const BorderSide(color: AppColors.blue, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          // Bouton S'y rendre : toujours visible
          Expanded(
            flex: hideReserveButton ? 1 : 2,
            child: ElevatedButton.icon(
              onPressed: () {
                if (!isAuthenticated) {
                  _navigateToLogin(context);
                } else {
                  if (hideReserveButton) {
                    // On vient de "Mes réservations", on navigue vers la carte principale
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MainScreen(
                          initialIndex: 1, // Onglet Map
                          isAuthenticated: true,
                        ),
                      ),
                      (route) => false,
                    );
                  } else {
                    // On vient de la carte, on retourne le mot 'navigate' pour tracer l'itinéraire
                    Navigator.pop(context, 'navigate');
                  }
                }
              },
              icon: const Icon(Icons.navigation_rounded, size: 18),
              label: const Text("S'y rendre"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blue,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
