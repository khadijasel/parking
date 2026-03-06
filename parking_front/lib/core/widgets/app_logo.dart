import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

/// Logo SmartPark — identique au Splash Screen
/// Carte blanche avec logo voiture gradient bleu
class AppLogo extends StatelessWidget {
  final bool showTagline;
  final double logoSize;

  const AppLogo({
    super.key,
    this.showTagline = true,
    this.logoSize = 100,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Carte blanche avec ombre (identique au splash) ──────────────
        Container(
          width: logoSize,
          height: logoSize,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(logoSize * 0.31),
            border: Border.all(color: const Color(0xFFF1F5F9), width: 1),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2563EB).withOpacity(0.14),
                blurRadius: 40,
                spreadRadius: 0,
                offset: const Offset(0, 16),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: CustomPaint(
              size: Size(logoSize * 0.62, logoSize * 0.62),
              painter: _CarLogoPainter(),
            ),
          ),
        ),

        const SizedBox(height: 20),

        // ── Nom "SmartPark" avec gradient bleu ─────────────────────────
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF2563EB), Color(0xFF60A5FA)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          blendMode: BlendMode.srcIn,
          child: const Text(
            AppConstants.appName,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: Colors.white, // masqué par le shader gradient
            ),
          ),
        ),

        if (showTagline) ...[
          const SizedBox(height: 6),
          const Text(
            'A L G É R I E',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w300,
              letterSpacing: 7,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            AppConstants.appTagline,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF94A3B8),
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
//  PEINTRE — exactement le même que dans SplashScreen
// ════════════════════════════════════════════════════════════
class _CarLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gradient = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF2563EB), Color(0xFF60A5FA)],
    );

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // ── Trait principal ────────────────────────────────────────────────
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.065
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final s = size.width / 100;

    // ── Carrosserie voiture ────────────────────────────────────────────
    final bodyPath = Path();
    bodyPath.moveTo(30 * s, 35 * s);
    bodyPath.cubicTo(30 * s, 25 * s, 70 * s, 20 * s, 75 * s, 35 * s);
    bodyPath.cubicTo(78 * s, 45 * s, 60 * s, 50 * s, 50 * s, 50 * s);
    bodyPath.cubicTo(35 * s, 50 * s, 22 * s, 55 * s, 25 * s, 70 * s);
    bodyPath.cubicTo(28 * s, 85 * s, 70 * s, 80 * s, 75 * s, 70 * s);
    canvas.drawPath(bodyPath, paint);

    // ── Détails côté droit ─────────────────────────────────────────────
    canvas.drawLine(Offset(75 * s, 70 * s), Offset(85 * s, 70 * s), paint);
    canvas.drawLine(Offset(82 * s, 65 * s), Offset(82 * s, 75 * s), paint);
    canvas.drawLine(Offset(88 * s, 65 * s), Offset(88 * s, 75 * s), paint);

    // ── Roues (remplies) ───────────────────────────────────────────────
    final fillPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(38 * s, 72 * s), 3 * s, fillPaint);
    canvas.drawCircle(Offset(62 * s, 72 * s), 3 * s, fillPaint);

    // ── Carrés décoratifs ──────────────────────────────────────────────
    void drawSquare(double x, double y) => canvas.drawRect(
        Rect.fromLTWH(x * s, y * s, 2 * s, 2 * s), fillPaint);

    drawSquare(75, 64);
    drawSquare(79, 64);
    drawSquare(75, 74);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}