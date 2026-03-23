import 'package:flutter/material.dart';

const _kBlue = Color(0xFF4A90E2);
const _kDark = Color(0xFF1A1A2E);
const _kMid = Color(0xFF8A9BB5);

class ReservationScreen extends StatelessWidget {
  final String parkingName;
  final String parkingAddress;
  final List<String> equipments;

  const ReservationScreen({
    super.key,
    required this.parkingName,
    required this.parkingAddress,
    required this.equipments,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _kDark),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          'Reservation',
          style: TextStyle(
            color: _kDark,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              parkingName,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: _kDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              parkingAddress,
              style: const TextStyle(
                fontSize: 14,
                color: _kMid,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: equipments
                  .map(
                    (String eq) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF1FB),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        eq,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _kBlue,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Confirmer',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
