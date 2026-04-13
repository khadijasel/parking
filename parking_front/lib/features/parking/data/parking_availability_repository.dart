import 'models/parking_availability_api_model.dart';
import 'parking_availability_api_service.dart';

class ParkingAvailabilityRepository {
  static const Duration _cacheTtl = Duration(seconds: 10);
  static List<ParkingAvailabilityApiModel>? _availabilityCache;
  static DateTime? _availabilityCacheAt;

  final ParkingAvailabilityApiService _apiService;

  ParkingAvailabilityRepository({ParkingAvailabilityApiService? apiService})
      : _apiService = apiService ?? ParkingAvailabilityApiService();

  Future<List<ParkingAvailabilityApiModel>> fetchAvailability({
    bool forceRefresh = false,
  }) async {
    final bool hasFreshCache = _availabilityCache != null &&
        _availabilityCacheAt != null &&
        DateTime.now().difference(_availabilityCacheAt!) < _cacheTtl;

    if (!forceRefresh && hasFreshCache) {
      return _availabilityCache!;
    }

    final List<Map<String, dynamic>> raw = await _apiService.fetchAvailability();

    final List<ParkingAvailabilityApiModel> mapped = raw
        .map((Map<String, dynamic> item) =>
            ParkingAvailabilityApiModel.fromJson(item))
        .toList(growable: false);

    _availabilityCache = mapped;
    _availabilityCacheAt = DateTime.now();
    return mapped;
  }
}
