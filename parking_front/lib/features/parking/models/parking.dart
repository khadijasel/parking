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
