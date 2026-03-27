import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/services/location_service.dart';
import '../../../theme/app_colors.dart';
import '../data/parking_data.dart';
import '../models/parking.dart';
import 'parking_detail_screen.dart';

class MapHomeScreen extends StatefulWidget {
  final Parking? autoNavigateParking;
  final bool isAuthenticated;
  final bool showRouteToSelected;
  final LatLng? initialUserLocation;

  const MapHomeScreen({
    super.key,
    this.autoNavigateParking,
    this.isAuthenticated = false,
    this.showRouteToSelected = false,
    this.initialUserLocation,
  });

  @override
  State<MapHomeScreen> createState() => _MapHomeScreenState();
}

class _MapHomeScreenState extends State<MapHomeScreen> {
  final MapController _mapController = MapController();
  Parking? _selectedParking;
  final List<String> _activeFilters = [];
  LatLng? _userLocation;
  bool _isLoadingLocation = false;
  bool _showRouteToSelected = false;
  bool _isLoadingRoute = false;
  List<LatLng> _routePoints = const [];
  double _routeDistanceKm = 0;
  int _routeDurationMinutes = 0;

  LatLng get _routeStartPoint => _userLocation ?? const LatLng(36.7650, 3.0570);

  double get _navigationDistanceKm {
    if (_routeDistanceKm > 0) return _routeDistanceKm;
    if (_selectedParking == null || _userLocation == null) return 0;
    return LocationService.distanceKm(_routeStartPoint, _selectedParking!.location);
  }

  int get _navigationMinutes {
    if (_routeDurationMinutes > 0) return _routeDurationMinutes;
    final minutes = (_navigationDistanceKm / 28.0 * 60).round();
    return minutes < 1 ? 1 : minutes;
  }

  @override
  void initState() {
    super.initState();
    _selectedParking = widget.autoNavigateParking;
    _userLocation = widget.initialUserLocation;
    _showRouteToSelected = widget.showRouteToSelected;
    _loadUserLocation();
  }

  final List<Map<String, dynamic>> _filters = [
    {'label': 'Électrique', 'icon': Icons.bolt},
    {'label': 'Tramway', 'icon': Icons.tram},
    {'label': '24h/7j', 'icon': Icons.access_time},
    {'label': 'Handicapé', 'icon': Icons.accessible},
  ];

  List<Parking> get _parkingsByDistance {
    final all = List<Parking>.from(ParkingData.parkings);
    if (_userLocation == null) return all;
    all.sort((a, b) {
      final da = LocationService.distanceKm(_userLocation!, a.location);
      final db = LocationService.distanceKm(_userLocation!, b.location);
      return da.compareTo(db);
    });
    return all;
  }

  Future<void> _loadUserLocation({bool force = false}) async {
    if (_userLocation != null && !force) return;
    setState(() => _isLoadingLocation = true);
    final location = await LocationService.getCurrentLocation();
    if (!mounted) return;
    setState(() {
      _userLocation = location;
      _isLoadingLocation = false;
    });
    if (location != null) {
      _mapController.move(location, 15.0);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Activez la localisation GPS et autorisez l\'application.'),
      ),
    );
  }

  Future<LatLng?> _ensureUserLocation() async {
    if (_userLocation != null) return _userLocation;
    await _loadUserLocation();
    return _userLocation;
  }

  void _fitRouteInView() {
    if (_routePoints.length < 2) return;
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(_routePoints),
        padding: const EdgeInsets.fromLTRB(48, 120, 48, 260),
      ),
    );
  }

  Future<void> _activateNavigation(Parking parking) async {
    setState(() {
      _selectedParking = parking;
      _showRouteToSelected = true;
      _isLoadingRoute = true;
      _routePoints = const [];
      _routeDistanceKm = 0;
      _routeDurationMinutes = 0;
    });

    final userLocation = await _ensureUserLocation();
    if (!mounted) return;

    if (userLocation == null) {
      setState(() {
        _isLoadingRoute = false;
        _showRouteToSelected = false;
        _routePoints = const [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Localisation introuvable. Activez le GPS puis réessayez.'),
        ),
      );
      return;
    }

    final start = userLocation;
    final route = await LocationService.getDrivingRoute(
      from: start,
      to: parking.location,
    );

    if (!mounted) return;

    if (route == null || route.points.length < 2) {
      setState(() {
        _isLoadingRoute = false;
        _showRouteToSelected = false;
        _routePoints = const [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible de calculer un vrai itinéraire pour le moment.'),
        ),
      );
      return;
    }

    setState(() {
      _routePoints = route.points;
      _routeDistanceKm = route.distanceKm;
      _routeDurationMinutes = route.durationMinutes;
      _isLoadingRoute = false;
    });

    _fitRouteInView();
  }

  void _centerOnUserLocation() {
    if (_userLocation == null) {
      _loadUserLocation(force: true);
      return;
    }
    _mapController.move(_userLocation!, 15.0);
  }

  Future<void> _openDetails(Parking parking) async {
    final action = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ParkingDetailScreen(
          parking: parking,
          isAuthenticated: widget.isAuthenticated,
          userLocation: _userLocation,
        ),
      ),
    );

    if (!mounted) return;
    if (action == 'navigate') {
      await _activateNavigation(parking);
    }
  }

  String _distanceLabel(Parking parking) {
    if (_userLocation == null) return parking.walkingTime;
    final km = LocationService.distanceKm(_userLocation!, parking.location);
    return '${km.toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Map
          _buildMap(),
          // Search bar + filters
          if (!_showRouteToSelected) _buildSearchOverlay(),
          // Zoom controls + locate button
          _buildMapControls(),
          // Bottom sheet for selected parking
          if (_showRouteToSelected && _selectedParking != null)
            _buildActiveNavigationPanel(),
          if (!_showRouteToSelected && _selectedParking != null)
            _buildParkingPreview(),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _userLocation ?? const LatLng(36.7650, 3.0570),
        initialZoom: 15.0,
        onTap: (_, __) {
          setState(() {
            _selectedParking = null;
            _showRouteToSelected = false;
            _routePoints = const [];
            _routeDistanceKm = 0;
            _routeDurationMinutes = 0;
            _isLoadingRoute = false;
          });
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.parking_front',
        ),
        if (_showRouteToSelected && _routePoints.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _routePoints,
                color: AppColors.blue,
                strokeWidth: 4,
              ),
            ],
          ),
        MarkerLayer(
          markers: _parkingsByDistance.map((parking) {
            return Marker(
              point: parking.location,
              width: 80,
              height: 40,
              child: GestureDetector(
                onTap: () => _activateNavigation(parking),
                child: _buildPriceMarker(parking),
              ),
            );
          }).toList()
            ..addAll(
              _userLocation == null
                  ? []
                  : [
                      Marker(
                        point: _userLocation!,
                        width: 22,
                        height: 22,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.blue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                        ),
                      ),
                    ],
            ),
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
            // Search bar
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
                        hintText: 'Rechercher à Alger...',
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
            if (_isLoadingLocation)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (_userLocation != null && _parkingsByDistance.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.near_me_rounded, size: 16, color: AppColors.blue),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Plus proche: ${_parkingsByDistance.first.name} (${_distanceLabel(_parkingsByDistance.first)})',
                          style: const TextStyle(fontSize: 12, color: AppColors.textDark),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // Filter chips
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
      bottom: _showRouteToSelected
          ? 235
          : (_selectedParking != null ? 280 : 40),
      child: Column(
        children: [
          _buildControlButton(Icons.add, () {
            // Zoom in - approximate by moving
          }),
          const SizedBox(height: 8),
          _buildControlButton(Icons.remove, () {
            // Zoom out
          }),
          const SizedBox(height: 16),
          _buildControlButton(Icons.navigation_outlined, () {
            _centerOnUserLocation();
          }),
        ],
      ),
    );
  }

  Widget _buildActiveNavigationPanel() {
    final parking = _selectedParking!;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF1FB),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.navigation_rounded,
                    color: AppColors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        parking.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.access_time_rounded,
                            size: 15,
                            color: Color(0xFF8A9BB5),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _isLoadingRoute ? 'Calcul...' : '$_navigationMinutes min',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF8A9BB5),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Icon(
                            Icons.straighten_rounded,
                            size: 15,
                            color: Color(0xFF8A9BB5),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _isLoadingRoute
                                ? '--.- km'
                                : '${_navigationDistanceKm.toStringAsFixed(1)} km',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF8A9BB5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _showRouteToSelected = false;
                    _routePoints = const [];
                    _routeDistanceKm = 0;
                    _routeDurationMinutes = 0;
                    _isLoadingRoute = false;
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                icon: const Icon(Icons.close_rounded),
                label: const Text(
                  'Arrêter la navigation',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
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

  Widget _buildParkingPreview() {
    final parking = _selectedParking!;
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
                // Parking image placeholder
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
                              '${parking.address} • ${_distanceLabel(parking)}',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Tags
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
                // Bookmark icon
                IconButton(
                  icon: const Icon(Icons.bookmark_border, color: AppColors.textDark),
                  onPressed: () {},
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Price & button
            Row(
              children: [
                Column(
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
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.blue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _openDetails(parking),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.blue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Voir détails',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
