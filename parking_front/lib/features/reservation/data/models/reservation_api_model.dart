class ReservationApiModel {
  final String id;
  final String userId;
  final String parkingId;
  final String parkingName;
  final String parkingAddress;
  final List<String> equipments;
  final String durationType;
  final int durationMinutes;
  final double amount;
  final bool depositRequired;
  final double depositAmount;
  final String reservationStatus;
  final String paymentStatus;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ReservationApiModel({
    required this.id,
    required this.userId,
    required this.parkingId,
    required this.parkingName,
    required this.parkingAddress,
    required this.equipments,
    required this.durationType,
    required this.durationMinutes,
    required this.amount,
    required this.depositRequired,
    required this.depositAmount,
    required this.reservationStatus,
    required this.paymentStatus,
    this.expiresAt,
    this.createdAt,
    this.updatedAt,
  });

  factory ReservationApiModel.fromJson(Map<String, dynamic> json) {
    return ReservationApiModel(
      id: (json['id'] ?? '').toString(),
      userId: (json['user_id'] ?? '').toString(),
      parkingId: (json['parking_id'] ?? '').toString(),
      parkingName: (json['parking_name'] ?? '').toString(),
      parkingAddress: (json['parking_address'] ?? '').toString(),
      equipments: (json['equipments'] is List)
          ? (json['equipments'] as List)
              .map((dynamic e) => e.toString())
              .toList(growable: false)
          : const <String>[],
      durationType: (json['duration_type'] ?? 'courte').toString(),
      durationMinutes: (json['duration_minutes'] is num)
          ? (json['duration_minutes'] as num).toInt()
          : 0,
      amount: (json['amount'] is num) ? (json['amount'] as num).toDouble() : 0,
      depositRequired: json['deposit_required'] == true,
      depositAmount: (json['deposit_amount'] is num)
          ? (json['deposit_amount'] as num).toDouble()
          : 0,
      reservationStatus:
          (json['reservation_status'] ?? 'pending_payment').toString(),
      paymentStatus: (json['payment_status'] ?? 'unpaid').toString(),
      expiresAt: _parseDate(json['expires_at']),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }

    return DateTime.tryParse(value);
  }
}
