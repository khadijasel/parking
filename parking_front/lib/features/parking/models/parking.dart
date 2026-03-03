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
  });
}
