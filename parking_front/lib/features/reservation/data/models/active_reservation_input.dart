class ActiveReservationInput {
  final String reservationId;
  final String parkingName;
  final String parkingAddress;
  final String durationType;
  final double amount;
  final DateTime createdAt;

  const ActiveReservationInput({
    required this.reservationId,
    required this.parkingName,
    required this.parkingAddress,
    required this.durationType,
    required this.amount,
    required this.createdAt,
  });

  bool get isShort => durationType == 'courte';

  int get guaranteeMinutes => isShort ? 30 : 60;

  DateTime get expiresAt => createdAt.add(Duration(minutes: guaranteeMinutes));
}
