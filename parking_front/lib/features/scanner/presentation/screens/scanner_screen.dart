import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../reservation/data/models/reservation_api_model.dart';
import '../../../reservation/data/reservation_repository.dart';

// ════════════════════════════════════════════════════════════
//  SCANNER SCREEN
//  — Cadre QR animé avec ligne de scan
//  — Bouton torche + galerie + historique
//  — Nécessite : mobile_scanner dans pubspec.yaml
//    flutter pub add mobile_scanner
//
//  Pour activer la vraie caméra, décommenter les imports
//  mobile_scanner et remplacer le fond noir par MobileScanner
// ════════════════════════════════════════════════════════════

// import 'package:mobile_scanner/mobile_scanner.dart'; // ← décommenter

const _kBlue = Color(0xFF4A90E2);

class ScannerScreen extends StatefulWidget {
  final VoidCallback? onScanSuccess;

  const ScannerScreen({super.key, this.onScanSuccess});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with SingleTickerProviderStateMixin {
  bool _torchOn = false;
  bool _isScanning = true;
  bool _isSubmitting = false;
  final ReservationRepository _reservationRepository = ReservationRepository();

  // Animation ligne de scan
  late AnimationController _scanCtrl;
  late Animation<double> _scanAnim;

  // Pour la vraie caméra :
  // final MobileScannerController _cameraCtrl = MobileScannerController();

  @override
  void initState() {
    super.initState();
    _scanCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _scanAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scanCtrl.dispose();
    // _cameraCtrl.dispose();
    super.dispose();
  }

  void _toggleTorch() {
    setState(() => _torchOn = !_torchOn);
    HapticFeedback.selectionClick();
    // _cameraCtrl.toggleTorch();
  }

  Future<void> _onQRDetected(String code) async {
    if (_isSubmitting) {
      return;
    }

    HapticFeedback.heavyImpact();
    setState(() => _isScanning = false);
    _scanCtrl.stop();

    setState(() => _isSubmitting = true);

    try {
      final ReservationApiModel reservation =
          await _reservationRepository.completeReservationByTicket(code);
      _showResultSheet(
        code,
        isValid: true,
        message: 'Votre ticket a ete scanne avec succes.',
        ticketReference: reservation.id,
        afterClose: widget.onScanSuccess,
      );
    } on ReservationException catch (error) {
      _showResultSheet(
        code,
        isValid: false,
        message: error.message,
      );
    } catch (_) {
      _showResultSheet(
        code,
        isValid: false,
        message: 'Impossible de valider ce ticket pour le moment.',
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showResultSheet(
    String code, {
    required bool isValid,
    required String message,
    String? ticketReference,
    VoidCallback? afterClose,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      builder: (_) => _ScanResultSheet(
        code: code,
        isValid: isValid,
        message: message,
        ticketReference: ticketReference,
        onRetry: () {
          Navigator.pop(context);
          setState(() {
            _isScanning = true;
            _isSubmitting = false;
          });
          _scanCtrl.repeat(reverse: true);
        },
        onClose: () {
          Navigator.pop(context);
          afterClose?.call();
        },
      ),
    );
  }

  Future<void> _simulateScanFromCurrentReservation() async {
    if (_isSubmitting) {
      return;
    }

    try {
      final List<ReservationApiModel> reservations =
          await _reservationRepository.fetchMyReservations();

      ReservationApiModel? candidate;
      for (final ReservationApiModel reservation in reservations) {
        if (reservation.reservationStatus.toLowerCase() == 'in_transit') {
          candidate = reservation;
          break;
        }
      }

      if (candidate == null) {
        for (final ReservationApiModel reservation in reservations) {
          if (reservation.reservationStatus.toLowerCase() == 'confirmed') {
            candidate = reservation;
            break;
          }
        }
      }

      if (candidate == null || candidate.id.isEmpty) {
        _showResultSheet(
          'AUCUNE-RESERVATION',
          isValid: false,
          message: 'Aucune reservation valide a scanner.',
        );
        return;
      }

      await _onQRDetected(candidate.id);
    } on ReservationException catch (error) {
      _showResultSheet(
        'ERREUR-SCAN',
        isValid: false,
        message: error.message,
      );
    } catch (_) {
      _showResultSheet(
        'ERREUR-SCAN',
        isValid: false,
        message: 'Impossible de recuperer une reservation a scanner.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final frameW = size.width * 0.72;
    final frameH = frameW * 1.25;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Fond caméra (simulé en noir) ──────────────────
          // Remplacer par :
          // MobileScanner(
          //   controller: _cameraCtrl,
          //   onDetect: (capture) {
          //     final code = capture.barcodes.first.rawValue ?? '';
          //     if (_isScanning && code.isNotEmpty) _onQRDetected(code);
          //   },
          // ),
          Container(color: Colors.black87),

          // ── Overlay foncé autour du cadre ──────────────────
          _buildOverlay(size, frameW, frameH),

          // ── Cadre QR avec coins bleus ─────────────────────
          Center(
            child: SizedBox(
              width: frameW,
              height: frameH,
              child: Stack(children: [
                // Fond semi-transparent dans le cadre
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                // Coins bleus
                _buildCorners(frameW, frameH),
                // Ligne de scan animée
                if (_isScanning)
                  AnimatedBuilder(
                    animation: _scanAnim,
                    builder: (_, __) => Positioned(
                      top: _scanAnim.value * (frameH - 4),
                      left: 16,
                      right: 16,
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          color: _kBlue,
                          borderRadius: BorderRadius.circular(1),
                          boxShadow: [
                            BoxShadow(
                                color: _kBlue.withOpacity(0.6),
                                blurRadius: 8,
                                spreadRadius: 2),
                          ],
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),

          // ── Texte instruction ─────────────────────────────
          Positioned(
            top: size.height / 2 - frameH / 2 - 52,
            left: 0,
            right: 0,
            child: const Text(
              'Placez le ticket dans le cadre',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  fontWeight: FontWeight.w500),
            ),
          ),

          // ── Bouton fermer (X) ─────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _circleBtn(
                    icon: Icons.close,
                    onTap: () => Navigator.pop(context),
                  ),
                  _circleBtn(
                    icon: _torchOn
                        ? Icons.flashlight_on_rounded
                        : Icons.flashlight_off_rounded,
                    onTap: _toggleTorch,
                  ),
                ],
              ),
            ),
          ),

          // ── Barre actions bas ─────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomBar(),
          ),
        ],
      ),
    );
  }

  // ── Overlay foncé ─────────────────────────────────────────
  Widget _buildOverlay(Size size, double frameW, double frameH) {
    final cx = size.width / 2 - frameW / 2;
    final cy = size.height / 2 - frameH / 2;

    return Stack(children: [
      // Haut
      Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: cy,
          child: Container(color: Colors.black.withOpacity(0.6))),
      // Bas
      Positioned(
          top: cy + frameH,
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(color: Colors.black.withOpacity(0.6))),
      // Gauche
      Positioned(
          top: cy,
          left: 0,
          width: cx,
          height: frameH,
          child: Container(color: Colors.black.withOpacity(0.6))),
      // Droite
      Positioned(
          top: cy,
          left: cx + frameW,
          right: 0,
          height: frameH,
          child: Container(color: Colors.black.withOpacity(0.6))),
    ]);
  }

  // ── Coins du cadre ────────────────────────────────────────
  Widget _buildCorners(double w, double h) {
    const r = 16.0;
    const t = 4.0;
    const l = 28.0;
    return Stack(children: [
      // Haut gauche
      Positioned(
          top: 0, left: 0, child: _corner(l, l, t, r, top: true, left: true)),
      // Haut droit
      Positioned(
          top: 0, right: 0, child: _corner(l, l, t, r, top: true, left: false)),
      // Bas gauche
      Positioned(
          bottom: 0,
          left: 0,
          child: _corner(l, l, t, r, top: false, left: true)),
      // Bas droit
      Positioned(
          bottom: 0,
          right: 0,
          child: _corner(l, l, t, r, top: false, left: false)),
    ]);
  }

  Widget _corner(double w, double h, double t, double r,
      {required bool top, required bool left}) {
    return SizedBox(
      width: w,
      height: h,
      child: CustomPaint(
        painter: _CornerPainter(
            top: top, left: left, thickness: t, radius: r, color: _kBlue),
      ),
    );
  }

  // ── Bouton circulaire ─────────────────────────────────────
  Widget _circleBtn({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  // ── Barre du bas : galerie + photo + historique ───────────
  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 16,
        top: 20,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Galerie
          _bottomBtn(
            icon: Icons.photo_outlined,
            onTap: () {
              // Ouvrir galerie pour scanner image
            },
          ),
          // Bouton principal scan
          GestureDetector(
            onTap: () {
              // Test : simuler un scan
              _simulateScanFromCurrentReservation();
            },
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: _kBlue,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: _kBlue.withOpacity(0.4),
                      blurRadius: 16,
                      spreadRadius: 2),
                ],
              ),
              child: const Icon(Icons.camera_alt_rounded,
                  color: Colors.white, size: 30),
            ),
          ),
          // Historique
          _bottomBtn(
            icon: Icons.history_rounded,
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _bottomBtn({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  CORNER PAINTER — dessine un coin du cadre
// ════════════════════════════════════════════════════════════

class _CornerPainter extends CustomPainter {
  final bool top, left;
  final double thickness, radius;
  final Color color;

  _CornerPainter({
    required this.top,
    required this.left,
    required this.thickness,
    required this.radius,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final w = size.width;
    final h = size.height;

    if (top && left) {
      path.moveTo(0, h);
      path.lineTo(0, radius);
      path.arcToPoint(Offset(radius, 0),
          radius: Radius.circular(radius), clockwise: true);
      path.lineTo(w, 0);
    } else if (top && !left) {
      path.moveTo(0, 0);
      path.lineTo(w - radius, 0);
      path.arcToPoint(Offset(w, radius),
          radius: Radius.circular(radius), clockwise: true);
      path.lineTo(w, h);
    } else if (!top && left) {
      path.moveTo(w, h);
      path.lineTo(radius, h);
      path.arcToPoint(Offset(0, h - radius),
          radius: Radius.circular(radius), clockwise: true);
      path.lineTo(0, 0);
    } else {
      path.moveTo(0, h);
      path.lineTo(w - radius, h);
      path.arcToPoint(Offset(w, h - radius),
          radius: Radius.circular(radius), clockwise: false);
      path.lineTo(w, 0);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => false;
}

// ════════════════════════════════════════════════════════════
//  RESULT BOTTOM SHEET
// ════════════════════════════════════════════════════════════

class _ScanResultSheet extends StatelessWidget {
  final String code;
  final bool isValid;
  final String message;
  final String? ticketReference;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  const _ScanResultSheet({
    required this.code,
    required this.isValid,
    required this.message,
    this.ticketReference,
    required this.onRetry,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Poignée
        Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),

        // Icône résultat
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: isValid
                ? const Color(0xFF2ECC71).withOpacity(0.12)
                : const Color(0xFFE53935).withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isValid
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
            size: 40,
            color: isValid ? const Color(0xFF2ECC71) : const Color(0xFFE53935),
          ),
        ),
        const SizedBox(height: 16),

        Text(
          isValid ? 'Ticket validé !' : 'QR code invalide',
          style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A2E)),
        ),
        const SizedBox(height: 6),
        Text(
          isValid ? message : '$message\nVeuillez réessayer.',
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 14, color: Color(0xFF8A9BB5), height: 1.5),
        ),

        if (isValid) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1FB),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              const Icon(Icons.confirmation_number_outlined,
                  color: Color(0xFF4A90E2), size: 20),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Référence ticket',
                    style: TextStyle(fontSize: 11, color: Color(0xFF8A9BB5))),
                Text(ticketReference ?? code,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E))),
              ]),
            ]),
          ),
        ],

        const SizedBox(height: 24),

        if (isValid)
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: onClose,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A90E2),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Continuer',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ),
          )
        else
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onClose,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFE2ECF9)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Fermer',
                    style: TextStyle(color: Color(0xFF1A1A2E))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A90E2),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Réessayer',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
      ]),
    );
  }
}
