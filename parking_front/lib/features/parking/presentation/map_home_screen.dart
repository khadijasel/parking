import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:parking_front/core/widgets/app_feedback.dart';
import '../../../core/services/location_service.dart';
import '../data/parking_availability_repository.dart';
import '../../../theme/app_colors.dart';
import '../data/parking_data.dart';
import '../models/parking.dart';
import 'parking_detail_screen.dart';

class MapHomeScreen extends StatefulWidget {
  final Parking? autoNavigateParking;
  final bool isAuthenticated;
  final bool isActive;
  final bool showRouteToSelected;
  final LatLng? initialUserLocation;
  final bool directReservationOnDetails;

  const MapHomeScreen({
    super.key,
    this.autoNavigateParking,
    this.isAuthenticated = false,
    this.isActive = true,
    this.showRouteToSelected = false,
    this.initialUserLocation,
    this.directReservationOnDetails = false,
  });

  @override
  State<MapHomeScreen> createState() => _MapHomeScreenState();
}

class _MapHomeScreenState extends State<MapHomeScreen> {
  final MapController _mapController = MapController();
  final ParkingAvailabilityRepository _availabilityRepository =
      ParkingAvailabilityRepository();
  Parking? _selectedParking;
  final List<String> _activeFilters = [];
  String _selectedVehicleType = 'car';
  String _searchQuery = '';
  double? _minPriceFilter;
  double? _maxPriceFilter;
  LatLng? _userLocation;
  bool _isLoadingLocation = false;
  bool _showRouteToSelected = false;
  bool _isLoadingRoute = false;
  List<LatLng> _routePoints = const [];
  double _routeDistanceKm = 0;
  int _routeDurationMinutes = 0;
  bool _isMapReady = false;
  LatLng? _pendingMapCenter;
  double? _pendingMapZoom;
  Map<String, int> _dynamicSpotsById = const <String, int>{};
  Map<String, int> _dynamicSpotsByName = const <String, int>{};
  Timer? _availabilityRefreshTimer;
  bool _isRefreshingAvailability = false;

  static const Duration _availabilityRefreshInterval = Duration(seconds: 15);

  LatLng get _routeStartPoint => _userLocation ?? const LatLng(36.7650, 3.0570);

  double get _navigationDistanceKm {
    if (_routeDistanceKm > 0) return _routeDistanceKm;
    if (_selectedParking == null || _userLocation == null) return 0;
    return LocationService.distanceKm(
        _routeStartPoint, _selectedParking!.location);
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
    _loadDynamicAvailability();
    if (widget.showRouteToSelected && widget.autoNavigateParking != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        _activateNavigation(widget.autoNavigateParking!);
      });
    }
    _setAvailabilityAutoRefreshEnabled(widget.isActive);
  }

  @override
  void didUpdateWidget(covariant MapHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      _setAvailabilityAutoRefreshEnabled(widget.isActive);
      if (widget.isActive) {
        _loadDynamicAvailability();
      }
    }
  }

  @override
  void dispose() {
    _availabilityRefreshTimer?.cancel();
    super.dispose();
  }

  void _setAvailabilityAutoRefreshEnabled(bool enabled) {
    _availabilityRefreshTimer?.cancel();
    _availabilityRefreshTimer = null;

    if (!enabled) {
      return;
    }

    _availabilityRefreshTimer = Timer.periodic(
      _availabilityRefreshInterval,
      (_) => _loadDynamicAvailability(),
    );
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

  Future<void> _loadDynamicAvailability() async {
    if (_isRefreshingAvailability) {
      return;
    }

    _isRefreshingAvailability = true;
    try {
      final availability = await _availabilityRepository.fetchAvailability();
      if (!mounted) {
        return;
      }

      final Map<String, int> mapped = <String, int>{};
      final Map<String, int> byId = <String, int>{};
      for (final item in availability) {
        final String id = item.parkingId.trim();
        if (id.isNotEmpty) {
          byId[id] = item.availableSpots;
        }

        final String key = _normalizeParkingName(item.parkingName);
        if (key.isEmpty) {
          continue;
        }

        mapped[key] = item.availableSpots;
      }

      setState(() {
        _dynamicSpotsById = byId;
        _dynamicSpotsByName = mapped;
      });
    } catch (_) {
      // Keep static data if server availability is temporarily unreachable.
    } finally {
      _isRefreshingAvailability = false;
    }
  }

  int _resolveAvailableSpots(Parking parking) {
    final int? byId = _dynamicSpotsById[parking.id];
    if (byId != null) {
      return byId;
    }

    return _dynamicSpotsByName[_normalizeParkingName(parking.name)] ??
        parking.availableSpots;
  }

  Parking _withDynamicAvailability(Parking parking) {
    final int dynamicSpots = _resolveAvailableSpots(parking);
    if (dynamicSpots == parking.availableSpots) {
      return parking;
    }

    return parking.copyWith(
      availableSpots: dynamicSpots,
      lastUpdate: 'Mis a jour via serveur',
    );
  }

  void _moveMap(LatLng center, double zoom) {
    if (_isMapReady) {
      _mapController.move(center, zoom);
      return;
    }
    _pendingMapCenter = center;
    _pendingMapZoom = zoom;
  }

  void _focusOnNearestParking() {
    if (_userLocation == null || _visibleParkings.isEmpty) return;
    final nearest = _visibleParkings.first;
    _moveMap(nearest.location, 14.8);
  }

  final List<Map<String, dynamic>> _filters = [
    {'label': 'Électrique', 'icon': Icons.bolt},
    {'label': 'Tramway', 'icon': Icons.tram},
    {'label': 'Téléphérique', 'icon': Icons.cable_rounded},
    {'label': '24h/7j', 'icon': Icons.access_time},
    {'label': 'Handicapé', 'icon': Icons.accessible},
  ];

  List<Parking> get _parkingsByDistance {
    final all = ParkingData.parkings
        .map(_withDynamicAvailability)
        .toList(growable: false);
    if (_userLocation == null) return all;
    all.sort((a, b) {
      final da = LocationService.distanceKm(_userLocation!, a.location);
      final db = LocationService.distanceKm(_userLocation!, b.location);
      return da.compareTo(db);
    });
    return all;
  }

  bool _matchesFilter(Parking parking, String filter) {
    final String tags = parking.tags.join(' ').toLowerCase();
    final String equipments = parking.equipments.join(' ').toLowerCase();
    final String nameAndAddress =
        '${parking.name} ${parking.address}'.toLowerCase();

    switch (filter) {
      case 'Électrique':
        return tags.contains('élec') ||
            tags.contains('elec') ||
            tags.contains('borne') ||
            equipments.contains('élec') ||
            equipments.contains('elec');
      case 'Tramway':
        return tags.contains('tram') || nameAndAddress.contains('tram');
      case 'Téléphérique':
        return parking.nearTelepherique ||
            tags.contains('téléph') ||
            tags.contains('teleph');
      case '24h/7j':
        return parking.isOpen24h;
      case 'Handicapé':
        return tags.contains('handi') ||
            equipments.contains('handi') ||
            equipments.contains('accessible');
      default:
        return true;
    }
  }

  bool _supportsVehicleConstraints(Parking parking) {
    final Set<String> supported = parking.supportedVehicleTypes
        .map((String value) => value.trim().toLowerCase())
        .where((String value) => value.isNotEmpty)
        .toSet();

    if (supported.isNotEmpty && !supported.contains(_selectedVehicleType)) {
      return false;
    }

    return true;
  }

  IconData _vehicleTypeIconFor(String type) {
    switch (type) {
      case 'moto':
        return Icons.motorcycle_rounded;
      case 'truck':
        return Icons.local_shipping_rounded;
      default:
        return Icons.directions_car_filled_rounded;
    }
  }

  Future<void> _showPriceFilterSheet() async {
    final Map<String, double?>? result =
        await showModalBottomSheet<Map<String, double?>>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      isScrollControlled: true,
      builder: (_) => _PriceFilterBottomSheet(
        initialMin: _minPriceFilter,
        initialMax: _maxPriceFilter,
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      _minPriceFilter = result['min'];
      _maxPriceFilter = result['max'];

      if (_selectedParking != null && !_isSelectedParkingVisible()) {
        _selectedParking = null;
        _showRouteToSelected = false;
        _routePoints = const [];
        _routeDistanceKm = 0;
        _routeDurationMinutes = 0;
      }
    });
  }

  Future<void> _showVehicleFilterSheet() async {
    String tempType = _selectedVehicleType;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Filtrer par vehicule',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Map<String, String>>[
                        <String, String>{'value': 'car', 'label': 'Voiture'},
                        <String, String>{'value': 'moto', 'label': 'Moto'},
                        <String, String>{'value': 'truck', 'label': 'Camion'},
                      ].map((Map<String, String> item) {
                        final bool active = tempType == item['value'];
                        return ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                _vehicleTypeIconFor(item['value']!),
                                size: 16,
                                color: active
                                    ? AppColors.blue
                                    : AppColors.textDark,
                              ),
                              const SizedBox(width: 6),
                              Text(item['label']!),
                            ],
                          ),
                          selected: active,
                          onSelected: (_) {
                            setModalState(() => tempType = item['value']!);
                          },
                          selectedColor: AppColors.blue.withValues(alpha: 0.14),
                          labelStyle: TextStyle(
                            color: active ? AppColors.blue : AppColors.textDark,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }).toList(growable: false),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _selectedVehicleType = tempType;

                            if (_selectedParking != null &&
                                !_isSelectedParkingVisible()) {
                              _selectedParking = null;
                              _showRouteToSelected = false;
                              _routePoints = const [];
                              _routeDistanceKm = 0;
                              _routeDurationMinutes = 0;
                            }
                          });
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          'Appliquer',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<Parking> get _visibleParkings {
    final String query = _searchQuery.trim().toLowerCase();

    return _parkingsByDistance.where((Parking parking) {
      if (!_supportsVehicleConstraints(parking)) {
        return false;
      }

      if (_activeFilters.isNotEmpty) {
        final bool passesAllFilters = _activeFilters
            .every((String filter) => _matchesFilter(parking, filter));
        if (!passesAllFilters) {
          return false;
        }
      }

      final double price = parking.pricePerHour;
      if (_minPriceFilter != null && price < _minPriceFilter!) {
        return false;
      }

      if (_maxPriceFilter != null && price > _maxPriceFilter!) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      final String haystack =
          '${parking.name} ${parking.address} ${parking.tags.join(' ')} ${parking.equipments.join(' ')}'
              .toLowerCase();
      return haystack.contains(query);
    }).toList(growable: false);
  }

  String get _searchCityHint {
    if (_visibleParkings.isEmpty) {
      return 'votre ville';
    }

    final String source =
        '${_visibleParkings.first.name} ${_visibleParkings.first.address}'
            .toLowerCase();

    if (source.contains('tlemcen')) {
      return 'Tlemcen';
    }

    if (source.contains('alger')) {
      return 'Alger';
    }

    return 'votre ville';
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
      _moveMap(location, 15.0);
      _focusOnNearestParking();
      return;
    }

    AppFeedback.showWarning(
      context,
      'Activez la localisation GPS et autorisez l\'application.',
    );
  }

  Future<LatLng?> _ensureUserLocation() async {
    if (_userLocation != null) return _userLocation;
    await _loadUserLocation();
    return _userLocation;
  }

  void _fitRouteInView() {
    if (_routePoints.length < 2 || !_isMapReady) return;
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

    final LatLng start = userLocation ?? const LatLng(36.7650, 3.0570);
    final route = await LocationService.getDrivingRoute(
      from: start,
      to: parking.location,
    );

    if (!mounted) return;

    if (route == null || route.points.length < 2) {
      final double fallbackDistance =
          LocationService.distanceKm(start, parking.location);
      final int fallbackDuration =
          ((fallbackDistance / 28.0) * 60).round().clamp(1, 9999);

      setState(() {
        _routePoints = <LatLng>[start, parking.location];
        _routeDistanceKm = fallbackDistance;
        _routeDurationMinutes = fallbackDuration;
        _isLoadingRoute = false;
      });

      _fitRouteInView();
      AppFeedback.showInfo(
        context,
        'Itineraire simplifie active (mode hors ligne).',
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

  void _selectParking(Parking parking) {
    setState(() {
      _selectedParking = parking;
      _showRouteToSelected = false;
      _isLoadingRoute = false;
      _routePoints = const [];
      _routeDistanceKm = 0;
      _routeDurationMinutes = 0;
    });
  }

  void _centerOnUserLocation() {
    if (_userLocation == null) {
      _loadUserLocation(force: true);
      return;
    }
    _moveMap(_userLocation!, 15.0);
  }

  void _zoomBy(double delta) {
    if (!_isMapReady) {
      return;
    }

    final MapCamera camera = _mapController.camera;
    final double nextZoom = (camera.zoom + delta).clamp(5.0, 18.5);
    _mapController.move(camera.center, nextZoom);
  }

  bool _isSelectedParkingVisible() {
    final String? selectedId = _selectedParking?.id;
    if (selectedId == null) {
      return false;
    }

    return _visibleParkings.any((Parking parking) => parking.id == selectedId);
  }

  Future<void> _openDetails(Parking parking) async {
    final action = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ParkingDetailScreen(
          parking: parking,
          isAuthenticated: widget.isAuthenticated,
          userLocation: _userLocation,
          directReservation: widget.directReservationOnDetails,
        ),
      ),
    );

    if (!mounted) return;
    if (action == 'navigate') {
      await _activateNavigation(parking);
    }

    await _loadDynamicAvailability();
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
        onMapReady: () {
          _isMapReady = true;
          if (_pendingMapCenter != null && _pendingMapZoom != null) {
            _mapController.move(_pendingMapCenter!, _pendingMapZoom!);
            _pendingMapCenter = null;
            _pendingMapZoom = null;
          }
        },
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
          markers: _visibleParkings.map((parking) {
            return Marker(
              point: parking.location,
              width: 156,
              height: 76,
              child: GestureDetector(
                onTap: () => _selectParking(parking),
                child: _buildParkingMarker(parking),
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

  Widget _buildParkingMarker(Parking parking) {
    final bool isSelected = _selectedParking?.id == parking.id;
    final bool isNotreParking = parking.id == 'arduino-sim' ||
        _normalizeParkingName(parking.name).contains('notre parking');
    final Color markerColor = isSelected
        ? AppColors.blue
        : (isNotreParking ? const Color(0xFFEF8D22) : const Color(0xFF2ECC71));
    final IconData vehicleIcon = _vehicleTypeIconFor(_selectedVehicleType);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: markerColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white,
              width: 1.2,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 7,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                vehicleIcon,
                size: 15,
                color: Colors.white,
              ),
              const SizedBox(width: 5),
              Text(
                '${parking.pricePerHour.toInt()} DA/h',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Container(
          constraints: const BoxConstraints(maxWidth: 148),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: markerColor.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white, width: 1),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            parking.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ],
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
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      onChanged: (String value) {
                        setState(() {
                          _searchQuery = value;

                          if (_selectedParking != null &&
                              !_isSelectedParkingVisible()) {
                            _selectedParking = null;
                            _showRouteToSelected = false;
                            _routePoints = const [];
                            _routeDistanceKm = 0;
                            _routeDurationMinutes = 0;
                          }
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Rechercher a $_searchCityHint...',
                        hintStyle: TextStyle(
                            color: Colors.grey.shade400, fontSize: 15),
                        prefixIcon:
                            const Icon(Icons.search, color: Colors.grey),
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  height: 46,
                  width: 46,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: GestureDetector(
                    onTap: _showVehicleFilterSheet,
                    child: Icon(
                      _vehicleTypeIconFor(_selectedVehicleType),
                      color: AppColors.textDark,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 46,
                  width: 46,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: GestureDetector(
                    onTap: _showPriceFilterSheet,
                    child: const Icon(Icons.payments_rounded,
                        color: AppColors.textDark),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_isLoadingLocation)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (_userLocation != null && _visibleParkings.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.near_me_rounded,
                          size: 16, color: AppColors.blue),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Plus proche: ${_visibleParkings.first.name} (${_distanceLabel(_visibleParkings.first)})',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textDark),
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

                        if (_selectedParking != null &&
                            !_isSelectedParkingVisible()) {
                          _selectedParking = null;
                          _showRouteToSelected = false;
                          _routePoints = const [];
                          _routeDistanceKm = 0;
                          _routeDurationMinutes = 0;
                        }
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isActive ? AppColors.blue : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
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
                              color:
                                  isActive ? Colors.white : AppColors.textDark,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          if (isActive) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.close,
                                size: 14, color: Colors.white),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_visibleParkings.isEmpty)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: AppColors.textMid, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Aucun parking ne correspond a votre recherche.',
                        style:
                            TextStyle(fontSize: 12, color: AppColors.textMid),
                      ),
                    ),
                  ],
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
      bottom:
          _showRouteToSelected ? 235 : (_selectedParking != null ? 280 : 40),
      child: Column(
        children: [
          _buildControlButton(Icons.add, () {
            _zoomBy(0.8);
          }),
          const SizedBox(height: 8),
          _buildControlButton(Icons.remove, () {
            _zoomBy(-0.8);
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
                            _isLoadingRoute
                                ? 'Calcul...'
                                : '$_navigationMinutes min',
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
              color: Colors.black.withValues(alpha: 0.1),
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
    final String imageUrl =
        (parking.imageUrl != null && parking.imageUrl!.trim().isNotEmpty)
            ? parking.imageUrl!.trim()
            : kParkingPreviewImageUrl;

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
              color: Colors.black.withValues(alpha: 0.12),
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
                    color: const Color(0xFFEAF1FB),
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
                          Icon(Icons.location_on_outlined,
                              size: 14, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${parking.address} • ${_distanceLabel(parking)}',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600),
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
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
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
                                    tag.contains('Élec')
                                        ? Icons.bolt
                                        : Icons.tram,
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
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
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

class _PriceFilterBottomSheet extends StatefulWidget {
  const _PriceFilterBottomSheet({
    required this.initialMin,
    required this.initialMax,
  });

  final double? initialMin;
  final double? initialMax;

  @override
  State<_PriceFilterBottomSheet> createState() =>
      _PriceFilterBottomSheetState();
}

class _PriceFilterBottomSheetState extends State<_PriceFilterBottomSheet> {
  late final TextEditingController _minController;
  late final TextEditingController _maxController;
  String? _inputError;

  @override
  void initState() {
    super.initState();
    _minController = TextEditingController(
      text: _formatPriceValue(widget.initialMin),
    );
    _maxController = TextEditingController(
      text: _formatPriceValue(widget.initialMax),
    );
  }

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  String _formatPriceValue(double? value) {
    if (value == null) {
      return '';
    }

    final double rounded = value.roundToDouble();
    if ((value - rounded).abs() < 0.01) {
      return rounded.toInt().toString();
    }

    return value.toStringAsFixed(1);
  }

  double? _parsePriceInput(String rawValue) {
    final String normalized = rawValue.trim().replaceAll(',', '.');
    if (normalized.isEmpty) {
      return null;
    }

    final double? parsed = double.tryParse(normalized);
    if (parsed == null || parsed < 0) {
      return null;
    }

    return parsed;
  }

  void _clearError() {
    if (_inputError == null) {
      return;
    }

    setState(() {
      _inputError = null;
    });
  }

  void _apply() {
    final double? parsedMin = _parsePriceInput(_minController.text);
    final double? parsedMax = _parsePriceInput(_maxController.text);

    if (_minController.text.trim().isNotEmpty && parsedMin == null) {
      setState(() {
        _inputError = 'Le prix minimum est invalide.';
      });
      return;
    }

    if (_maxController.text.trim().isNotEmpty && parsedMax == null) {
      setState(() {
        _inputError = 'Le prix maximum est invalide.';
      });
      return;
    }

    if (parsedMin != null && parsedMax != null && parsedMin > parsedMax) {
      setState(() {
        _inputError = 'Le prix min doit etre inferieur au prix max.';
      });
      return;
    }

    Navigator.of(context).pop(<String, double?>{
      'min': parsedMin,
      'max': parsedMax,
    });
  }

  @override
  Widget build(BuildContext context) {
    final double keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 14, 18, 20 + keyboardInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Filtrer par prix',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _minController,
                    onChanged: (_) => _clearError(),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Prix min (DA)',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _maxController,
                    onChanged: (_) => _clearError(),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Prix max (DA)',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_inputError != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _inputError!,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).pop(<String, double?>{
                        'min': null,
                        'max': null,
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text('Reinitialiser'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _apply,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text(
                      'Appliquer',
                      style: TextStyle(fontWeight: FontWeight.w700),
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
