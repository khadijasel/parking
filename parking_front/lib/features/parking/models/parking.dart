import 'package:latlong2/latlong.dart';

class ParkingIndoorGrid {
  final int rows;
  final int cols;
  final List<int> laneRows;
  final List<int> laneCols;

  const ParkingIndoorGrid({
    required this.rows,
    required this.cols,
    required this.laneRows,
    required this.laneCols,
  });

  factory ParkingIndoorGrid.fromJson(Map<String, dynamic> json) {
    return ParkingIndoorGrid(
      rows: Parking._toInt(json['rows'], 0),
      cols: Parking._toInt(json['cols'], 0),
      laneRows: Parking._toIntList(json['laneRows']),
      laneCols: Parking._toIntList(json['laneCols']),
    );
  }
}

class ParkingIndoorSpot {
  final String spotId;
  final String label;
  final int row;
  final int col;
  final String type;
  final String state;

  const ParkingIndoorSpot({
    required this.spotId,
    required this.label,
    required this.row,
    required this.col,
    required this.type,
    required this.state,
  });

  factory ParkingIndoorSpot.fromJson(Map<String, dynamic> json) {
    return ParkingIndoorSpot(
      spotId: Parking._toStringValue(json['spotId']),
      label: Parking._toStringValue(json['label']),
      row: Parking._toInt(json['row'], 0),
      col: Parking._toInt(json['col'], 0),
      type: Parking._toStringValue(json['type']),
      state: Parking._toStringValue(json['state']),
    );
  }
}

class ParkingIndoorMap {
  final String floor;
  final String zone;
  final ParkingIndoorGrid grid;
  final List<ParkingIndoorSpot> spots;

  const ParkingIndoorMap({
    required this.floor,
    required this.zone,
    required this.grid,
    required this.spots,
  });

  factory ParkingIndoorMap.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> gridRaw = Parking._normalizeMap(json['grid']);
    final List<ParkingIndoorSpot> mappedSpots =
        Parking._toMapList(json['spots'])
            .map(ParkingIndoorSpot.fromJson)
            .where((ParkingIndoorSpot spot) => spot.label.isNotEmpty)
            .toList(growable: false);

    return ParkingIndoorMap(
      floor: Parking._toStringValue(json['floor']),
      zone: Parking._toStringValue(json['zone']),
      grid: ParkingIndoorGrid.fromJson(gridRaw),
      spots: mappedSpots,
    );
  }
}

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
  final ParkingIndoorMap? indoorMap;

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
    this.indoorMap,
  });

  factory Parking.fromApi(Map<String, dynamic> json) {
    final String rawId = _toStringValue(json['parkingId']);
    final String fallbackId = _toStringValue(json['id']);
    final String name = _toStringValue(json['name']);
    final String resolvedId =
        rawId.isNotEmpty ? rawId : (fallbackId.isNotEmpty ? fallbackId : name);

    final Map<String, dynamic> location = _normalizeMap(json['location']);
    final double lat = _toDouble(location['lat'], 0.0);
    final double lng = _toDouble(location['lng'], 0.0);

    final String rawImageUrl = _toStringValue(json['imageUrl']);
    final List<String> supportedTypes =
        _toStringList(json['supportedVehicleTypes']);
    final Map<String, dynamic> indoorMapRaw = _normalizeMap(json['indoorMap']);

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
      maxVehicleHeightMeters: _toDouble(json['maxVehicleHeightMeters'], 1.9),
      supportedVehicleTypes: supportedTypes.isEmpty
          ? const <String>['car', 'moto']
          : supportedTypes,
      nearTelepherique: json['nearTelepherique'] == true,
      indoorMap:
          indoorMapRaw.isEmpty ? null : ParkingIndoorMap.fromJson(indoorMapRaw),
    );
  }

  static List<Map<String, dynamic>> _toMapList(Object? value) {
    if (value is List) {
      return value.whereType<Map>().map((Map<dynamic, dynamic> item) {
        return item.map<String, dynamic>(
          (dynamic key, dynamic val) => MapEntry<String, dynamic>(
            key.toString(),
            val,
          ),
        );
      }).toList(growable: false);
    }

    return const <Map<String, dynamic>>[];
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

  static List<int> _toIntList(Object? value) {
    if (value is List) {
      return value
          .map((Object? item) => _toInt(item, -1))
          .where((int item) => item >= 0)
          .toList(growable: false);
    }

    return const <int>[];
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
    ParkingIndoorMap? indoorMap,
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
      indoorMap: indoorMap ?? this.indoorMap,
    );
  }
}
