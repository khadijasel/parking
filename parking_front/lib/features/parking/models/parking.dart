import 'package:latlong2/latlong.dart';

class Parking {
  final String id;
  final String name;
  final String address;
  final String walkingTime;
  final double rating;
  final double pricePerHour;
  final int availableSpots;
  final String lastUpdate;
  final bool isOpen24h;
  final LatLng location;
  final List<String> equipments;
  final List<String> tags;
  final String? imageUrl;
  final double maxVehicleHeightMeters;
  final List<String> supportedVehicleTypes;
  final bool nearTelepherique;

  const Parking({
    required this.id,
    required this.name,
    required this.address,
    required this.walkingTime,
    required this.rating,
    required this.pricePerHour,
    required this.availableSpots,
    required this.lastUpdate,
    required this.isOpen24h,
    required this.location,
    required this.equipments,
    required this.tags,
    this.imageUrl,
    this.maxVehicleHeightMeters = 1.9,
    this.supportedVehicleTypes = const <String>['car', 'moto'],
    this.nearTelepherique = false,
  });

  factory Parking.fromApi(Map<String, dynamic> json) {
    final String rawId = _toStringValue(json['parkingId']);
    final String fallbackId = _toStringValue(json['id']);
    final String name = _toStringValue(json['name']);
    final String resolvedId = rawId.isNotEmpty
      ? rawId
      : (fallbackId.isNotEmpty ? fallbackId : name);

    final Map<String, dynamic> location = _normalizeMap(json['location']);
    final double lat = _toDouble(location['lat'], 0.0);
    final double lng = _toDouble(location['lng'], 0.0);

    final String rawImageUrl = _toStringValue(json['imageUrl']);
    final List<String> supportedTypes =
        _toStringList(json['supportedVehicleTypes']);

    return Parking(
      id: resolvedId,
      name: name,
      address: _toStringValue(json['address']),
      walkingTime: _toStringValue(json['walkingTime']),
      rating: _toDouble(json['rating'], 0.0),
      pricePerHour: _toDouble(json['pricePerHour'], 0.0),
      availableSpots: _toInt(json['availableSpots'], 0),
      lastUpdate: _toStringValue(json['lastUpdate']),
      isOpen24h: json['isOpen24h'] == true,
      location: LatLng(lat, lng),
      equipments: _toStringList(json['equipments']),
      tags: _toStringList(json['tags']),
      imageUrl: rawImageUrl.isEmpty ? null : rawImageUrl,
      maxVehicleHeightMeters:
          _toDouble(json['maxVehicleHeightMeters'], 1.9),
      supportedVehicleTypes:
          supportedTypes.isEmpty ? const <String>['car', 'moto'] : supportedTypes,
      nearTelepherique: json['nearTelepherique'] == true,
    );
  }

  static Map<String, dynamic> _normalizeMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return value.map<String, dynamic>(
        (Object? key, Object? val) => MapEntry<String, dynamic>(
          key.toString(),
          val,
        ),
      );
    }

    return <String, dynamic>{};
  }

  static List<String> _toStringList(Object? value) {
    if (value is List) {
      return value
          .map((Object? item) => _toStringValue(item))
          .where((String item) => item.isNotEmpty)
          .toList(growable: false);
    }

    if (value is String && value.trim().isNotEmpty) {
      return value
          .split(RegExp(r'[\n,;]+'))
          .map((String item) => item.trim())
          .where((String item) => item.isNotEmpty)
          .toList(growable: false);
    }

    return const <String>[];
  }

  static double _toDouble(Object? value, double fallback) {
    if (value is num) {
      return value.toDouble();
    }

    final double? parsed = double.tryParse(value?.toString() ?? '');
    return parsed ?? fallback;
  }

  static int _toInt(Object? value, int fallback) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    final int? parsed = int.tryParse(value?.toString() ?? '');
    return parsed ?? fallback;
  }

  static String _toStringValue(Object? value) {
    return value?.toString().trim() ?? '';
  }

  Parking copyWith({
    String? id,
    String? name,
    String? address,
    String? walkingTime,
    double? rating,
    double? pricePerHour,
    int? availableSpots,
    String? lastUpdate,
    bool? isOpen24h,
    LatLng? location,
    List<String>? equipments,
    List<String>? tags,
    String? imageUrl,
    double? maxVehicleHeightMeters,
    List<String>? supportedVehicleTypes,
    bool? nearTelepherique,
  }) {
    return Parking(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      walkingTime: walkingTime ?? this.walkingTime,
      rating: rating ?? this.rating,
      pricePerHour: pricePerHour ?? this.pricePerHour,
      availableSpots: availableSpots ?? this.availableSpots,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      isOpen24h: isOpen24h ?? this.isOpen24h,
      location: location ?? this.location,
      equipments: equipments ?? this.equipments,
      tags: tags ?? this.tags,
      imageUrl: imageUrl ?? this.imageUrl,
      maxVehicleHeightMeters:
          maxVehicleHeightMeters ?? this.maxVehicleHeightMeters,
      supportedVehicleTypes:
          supportedVehicleTypes ?? this.supportedVehicleTypes,
      nearTelepherique: nearTelepherique ?? this.nearTelepherique,
    );
  }
}
