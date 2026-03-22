import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/routing_service.dart';
import '../../../theme/app_colors.dart';
import '../data/parking_data.dart';
import '../models/parking.dart';
import '../../auth/presentation/login_screen.dart';
import 'parking_detail_screen.dart';

class MapHomeScreen extends StatefulWidget {
  final Parking? autoNavigateParking;
  final bool isAuthenticated;
  const MapHomeScreen({super.key, this.autoNavigateParking, this.isAuthenticated = false});

  @override
  State<MapHomeScreen> createState() => _MapHomeScreenState();
}

class _MapHomeScreenState extends State<MapHomeScreen> {
  final MapController _mapController = MapController();
  Parking? _selectedParking;
  final List<String> _activeFilters = [];

  // Position utilisateur
  LatLng? _userLocation;
  bool _loadingLocation = true;

  // Itinéraire
  List<LatLng> _routePoints = [];
  bool _isNavigating = false;
  double? _routeDistanceKm;
  double? _routeDurationMin;
  bool _loadingRoute = false;

  final List<Map<String, dynamic>> _filters = [
    {'label': 'Électrique', 'icon': Icons.bolt},
    {'label': 'Tramway', 'icon': Icons.tram},
    {'label': '24h/7j', 'icon': Icons.access_time},
    {'label': 'Handicapé', 'icon': Icons.accessible},
  ];

  @override
  void initState() {
    super.initState();
    _initUserLocation();
  }

  Future<void> _initUserLocation() async {
    final loc = await LocationService.getCurrentLocation();
    if (mounted) {
      setState(() {
        _userLocation = loc ?? const LatLng(34.8828, -1.3147); // Fallback: centre Tlemcen
        _loadingLocation = false;
      });
      if (widget.autoNavigateParking != null && _userLocation != null) {
        _startNavigation(widget.autoNavigateParking!);
      }
    }
  }

  Future<void> _startNavigation(Parking parking) async {
    if (_userLocation == null) return;

    setState(() {
      _loadingRoute = true;
      _isNavigating = true;
      _selectedParking = parking;
    });

    // Récupérer l'itinéraire et les infos en parallèle
    final results = await Future.wait([
      RoutingService.getRoute(_userLocation!, parking.location),
      RoutingService.getRouteInfo(_userLocation!, parking.location),
    ]);

    final route = results[0] as List<LatLng>;
    final info = results[1] as Map<String, double>?;

    if (mounted) {
      setState(() {
        _routePoints = route;
        _routeDistanceKm = info?['distance'];
        _routeDurationMin = info?['duration'];
        _loadingRoute = false;
      });

      // Ajuster la vue pour montrer tout l'itinéraire
      if (route.isNotEmpty) {
        final bounds = LatLngBounds.fromPoints([_userLocation!, parking.location]);
        _mapController.fitCamera(
          CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(80)),
        );
      }
    }
  }

  void _stopNavigation() {
    if (widget.autoNavigateParking != null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _isNavigating = false;
      _routePoints = [];
      _routeDistanceKm = null;
      _routeDurationMin = null;
      _selectedParking = null;
    });
  }

  void _centerOnUser() {
    if (_userLocation != null) {
      _mapController.move(_userLocation!, 15.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildMap(),
          if (!_isNavigating) _buildSearchOverlay(),
          _buildMapControls(),
          if (_isNavigating) _buildNavigationBar(),
          if (_selectedParking != null && !_isNavigating) _buildParkingPreview(),
          if (_loadingRoute) _buildLoadingOverlay(),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: const LatLng(34.8828, -1.3147), // Centre Tlemcen
        initialZoom: 14.0,
        onTap: (_, __) {
          if (!_isNavigating) {
            setState(() => _selectedParking = null);
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.parking_front',
        ),
        // Itinéraire (polyline bleue)
        if (_routePoints.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _routePoints,
                strokeWidth: 5.0,
                color: AppColors.blue,
              ),
            ],
          ),
        // Marqueurs parkings
        MarkerLayer(
          markers: [
            // Position utilisateur
            if (_userLocation != null)
              Marker(
                point: _userLocation!,
                width: 30,
                height: 30,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.blue.withOpacity(0.3),
                        blurRadius: 10,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                ),
              ),
            // Parkings
            ...ParkingData.parkings.map((parking) {
              return Marker(
                point: parking.location,
                width: 80,
                height: 40,
                child: GestureDetector(
                  onTap: () {
                    if (!_isNavigating) {
                      setState(() => _selectedParking = parking);
                    }
                  },
                  child: _buildPriceMarker(parking),
                ),
              );
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildPriceMarker(Parking parking) {
    final isSelected = _selectedParking?.id == parking.id;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.blue : const Color(0xFF2ECC71),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        '${parking.pricePerHour.toInt()} DA',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildSearchOverlay() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Rechercher à Tlemcen...',
                        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 15),
                        prefixIcon: const Icon(Icons.search, color: Colors.grey),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.tune, color: AppColors.textDark),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _filters.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final filter = _filters[index];
                  final isActive = _activeFilters.contains(filter['label']);
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isActive) {
                          _activeFilters.remove(filter['label']);
                        } else {
                          _activeFilters.add(filter['label'] as String);
                        }
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isActive ? AppColors.blue : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            filter['icon'] as IconData,
                            size: 16,
                            color: isActive ? Colors.white : AppColors.blue,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            filter['label'] as String,
                            style: TextStyle(
                              color: isActive ? Colors.white : AppColors.textDark,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          if (isActive) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.close, size: 14, color: Colors.white),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapControls() {
    return Positioned(
      right: 16,
      bottom: _isNavigating
          ? 150
          : (_selectedParking != null ? 280 : 40),
      child: Column(
        children: [
          _buildControlButton(Icons.add, () {
            final zoom = _mapController.camera.zoom + 1;
            _mapController.move(_mapController.camera.center, zoom);
          }),
          const SizedBox(height: 8),
          _buildControlButton(Icons.remove, () {
            final zoom = _mapController.camera.zoom - 1;
            _mapController.move(_mapController.camera.center, zoom);
          }),
          const SizedBox(height: 16),
          _buildControlButton(Icons.my_location, _centerOnUser),
        ],
      ),
    );
  }

  Widget _buildControlButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: AppColors.textDark),
      ),
    );
  }

  // ─── Barre de navigation en cours ──────────────────────────────────────
  Widget _buildNavigationBar() {
    final parking = _selectedParking!;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Barre de poignée
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            // Info itinéraire
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.navigation_rounded, color: AppColors.blue),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        parking.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 14, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(
                            _routeDurationMin != null
                                ? '${_routeDurationMin!.toStringAsFixed(0)} min'
                                : '...',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          ),
                          const SizedBox(width: 12),
                          Icon(Icons.straighten, size: 14, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(
                            _routeDistanceKm != null
                                ? '${_routeDistanceKm!.toStringAsFixed(1)} km'
                                : '...',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Bouton arrêter
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _stopNavigation,
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Arrêter la navigation'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Aperçu parking sélectionné ────────────────────────────────────────
  Widget _buildParkingPreview() {
    final parking = _selectedParking!;
    final distanceText = _userLocation != null
        ? '${LocationService.distanceKm(_userLocation!, parking.location).toStringAsFixed(1)} km'
        : '';

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 16,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      colors: [Colors.orange.shade200, Colors.orange.shade100],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Icon(Icons.local_parking, color: Colors.white, size: 36),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        parking.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined, size: 14, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${parking.address} • $distanceText',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (parking.tags.isNotEmpty)
                        Wrap(
                          spacing: 6,
                          children: parking.tags.map((tag) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: tag.contains('Élec')
                                    ? const Color(0xFFE8F5E9)
                                    : const Color(0xFFE3F2FD),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    tag.contains('Élec') ? Icons.bolt : Icons.tram,
                                    size: 12,
                                    color: tag.contains('Élec')
                                        ? AppColors.green
                                        : AppColors.blue,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    tag,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: tag.contains('Élec')
                                          ? AppColors.green
                                          : AppColors.blue,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.bookmark_border, color: AppColors.textDark),
                  onPressed: () {},
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Prix + boutons
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TARIF HORAIRE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade500,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${parking.pricePerHour.toInt()} DA / heure',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Bouton Détails
                OutlinedButton(
                  onPressed: () async {
                    final result = await Navigator.push<Map<String, dynamic>>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ParkingDetailScreen(parking: parking, isAuthenticated: widget.isAuthenticated),
                      ),
                    );
                    if (result != null && result['navigate'] == true) {
                      final p = result['parking'] as Parking;
                      _startNavigation(p);
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.blue,
                    side: const BorderSide(color: AppColors.blue, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Détails', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                ),
                const SizedBox(width: 8),
                // Bouton S'y rendre
                ElevatedButton.icon(
                  onPressed: () {
                    if (!widget.isAuthenticated) {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
                    } else {
                      _startNavigation(parking);
                    }
                  },
                  icon: const Icon(Icons.navigation_rounded, size: 18),
                  label: const Text("S'y rendre"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.blue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.3),
        child: const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.blue),
                  SizedBox(height: 16),
                  Text(
                    'Calcul de l\'itinéraire...',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
