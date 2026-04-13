class ParkingAvailabilityApiModel {
  final String parkingId;
  final String parkingName;
  final int totalSpots;
  final int availableSpots;
  final bool isArduino;

  const ParkingAvailabilityApiModel({
    required this.parkingId,
    required this.parkingName,
    required this.totalSpots,
    required this.availableSpots,
    required this.isArduino,
  });

  factory ParkingAvailabilityApiModel.fromJson(Map<String, dynamic> json) {
    final int total = (json['total_spots'] is num)
        ? (json['total_spots'] as num).toInt()
        : 0;
    final int available = (json['available_spots'] is num)
        ? (json['available_spots'] as num).toInt()
        : 0;

    return ParkingAvailabilityApiModel(
      parkingId: (json['parking_id'] ?? '').toString(),
      parkingName: (json['parking_name'] ?? '').toString(),
      totalSpots: total < 0 ? 0 : total,
      availableSpots: available < 0 ? 0 : available,
      isArduino: json['is_arduino'] == true,
    );
  }
}
