import '../models/parking.dart';
import 'parking_api_service.dart';

class ParkingRepository {
  static const Duration _cacheTtl = Duration(seconds: 20);
  static List<Parking>? _cache;
  static DateTime? _cacheAt;

  // Requete reseau en cours partagee : si plusieurs ecrans demandent les
  // parkings en meme temps (carte + accueil au demarrage), ils attendent le
  // meme appel au lieu d'en declencher un chacun.
  static Future<List<Parking>>? _inFlight;

  final ParkingApiService _apiService;

  ParkingRepository({ParkingApiService? apiService})
      : _apiService = apiService ?? ParkingApiService();

  Future<List<Parking>> fetchParkings({bool forceRefresh = false}) async {
    final bool hasFreshCache = _cache != null &&
        _cacheAt != null &&
        DateTime.now().difference(_cacheAt!) < _cacheTtl;

    if (!forceRefresh && hasFreshCache) {
      return _cache!;
    }

    final Future<List<Parking>>? pending = _inFlight;
    if (pending != null) {
      return pending;
    }

    final Future<List<Parking>> request = _fetchParkingsFromApi();
    _inFlight = request;
    try {
      return await request;
    } finally {
      _inFlight = null;
    }
  }

  Future<List<Parking>> _fetchParkingsFromApi() async {
    final List<Map<String, dynamic>> raw = await _apiService.fetchParkings();

    final List<Parking> mapped = raw
        .map((Map<String, dynamic> item) => Parking.fromApi(item))
        .where(_hasValidLocation)
        .toList(growable: false);

    _cache = mapped;
    _cacheAt = DateTime.now();
    return mapped;
  }

  static List<Parking> get cachedParkings => _cache ?? const <Parking>[];

  bool _hasValidLocation(Parking parking) {
    return _isValidCoordinate(parking.location.latitude, 90.0) &&
        _isValidCoordinate(parking.location.longitude, 180.0) &&
        (parking.location.latitude != 0 || parking.location.longitude != 0);
  }

  bool _isValidCoordinate(double value, double maxAbs) {
    if (value.isNaN || value.isInfinite) {
      return false;
    }

    return value.abs() <= maxAbs;
  }
}
