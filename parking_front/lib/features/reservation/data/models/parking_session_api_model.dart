class ParkingSessionApiModel {
  final String id;
  final String userId;
  final String reservationId;
  final String parkingName;
  final String parkingAddress;
  final String ticketCode;
  final String status;
  final String reservationStatus;
  final String reservationPaymentStatus;
  final String reservationDurationType;
  final double reservationAmount;
  final String sessionPaymentStatus;
  final int? durationSeconds;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ParkingSessionApiModel({
    required this.id,
    required this.userId,
    required this.reservationId,
    required this.parkingName,
    required this.parkingAddress,
    required this.ticketCode,
    required this.status,
    required this.reservationStatus,
    required this.reservationPaymentStatus,
    required this.reservationDurationType,
    required this.reservationAmount,
    required this.sessionPaymentStatus,
    this.durationSeconds,
    this.startedAt,
    this.endedAt,
    this.createdAt,
    this.updatedAt,
  });

  bool get isActive => status == 'active';

  factory ParkingSessionApiModel.fromJson(Map<String, dynamic> json) {
    return ParkingSessionApiModel(
      id: (json['id'] ?? '').toString(),
      userId: (json['user_id'] ?? '').toString(),
      reservationId: (json['reservation_id'] ?? '').toString(),
      parkingName: (json['parking_name'] ?? '').toString(),
      parkingAddress: (json['parking_address'] ?? '').toString(),
      ticketCode: (json['ticket_code'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      reservationStatus: (json['reservation_status'] ?? '').toString(),
      reservationPaymentStatus:
          (json['reservation_payment_status'] ?? '').toString(),
        reservationDurationType:
          (json['reservation_duration_type'] ?? '').toString(),
        reservationAmount: (json['reservation_amount'] is num)
          ? (json['reservation_amount'] as num).toDouble()
          : 0,
        sessionPaymentStatus: (json['session_payment_status'] ?? '').toString(),
      durationSeconds: (json['duration_seconds'] is num)
          ? (json['duration_seconds'] as num).toInt()
          : null,
      startedAt: _parseDate(json['started_at']),
      endedAt: _parseDate(json['ended_at']),
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
