import 'dart:async';
import 'dart:ui' show Tangent;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:parking_front/core/widgets/app_feedback.dart';
import 'package:parking_front/features/guidance/presentation/utils/guidance_spot_layout.dart';
import 'package:parking_front/features/parking/models/parking.dart';
import 'package:parking_front/features/reservation/data/reservation_repository.dart';
import 'package:parking_front/features/scanner/presentation/screens/scanner_screen.dart';

import 'exit_success_screen.dart';

const _kBg = Color(0xFFF0F4FA);
const _kBlue = Color(0xFF4A90E2);
const _kGreen = Color(0xFF2ECC71);
const _kOrange = Color(0xFFF5A623);
const _kRed = Color(0xFFE53935);
const _kDark = Color(0xFF1A1A2E);
const _kMid = Color(0xFF8A9BB5);

class GuidanceToExitScreen extends StatefulWidget {
  final String spotLabel;
  final bool showMapComingSoon;
  final List<ParkingIndoorSpot> spots;

  const GuidanceToExitScreen({
    super.key,
    this.spotLabel = 'P05',
    this.showMapComingSoon = false,
    this.spots = const <ParkingIndoorSpot>[],
  });

  @override
  State<GuidanceToExitScreen> createState() => _GuidanceToExitScreenState();
}

class _GuidanceToExitScreenState extends State<GuidanceToExitScreen>
    with SingleTickerProviderStateMixin {
  final FlutterTts _tts = FlutterTts();
  final ReservationRepository _reservationRepository = ReservationRepository();

  late final AnimationController _pathController;
  late final GuidanceSpotLayout _layout;
  late final GuidanceSpotViewData _currentSpotData;
  Timer? _timer;

  bool _voiceEnabled = true;
  bool _isCompletingExit = false;
  int _distanceMeters = 70;
  String _instruction = '';

  // Spot column index (0=left, 1=center, 2=right)
  bool get _isTopRow => _currentSpotData.rowIndex == 0;

  int get _spotColIndex => _currentSpotData.colIndex;

  String get _normalizedSpotLabel => _currentSpotData.displayLabel;

  @override
  void initState() {
    super.initState();
    _layout = GuidanceSpotLayout.fromIndoorSpots(widget.spots);
    _currentSpotData = _resolveCurrentSpotData();

    _pathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    );

    if (widget.showMapComingSoon) {
      _voiceEnabled = false;
      _instruction =
          'Guidage carte et voix indisponibles pour ce parking non equipe.';
      return;
    }

    _pathController.repeat();
    _configureVoice();
    _refreshInstruction(forceSpeak: true);

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _distanceMeters <= 0) return;
      setState(() {
        _distanceMeters = (_distanceMeters - 4).clamp(0, 10000);
      });
      _refreshInstruction();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pathController.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _configureVoice() async {
    await _tts.setLanguage('fr-FR');
    await _tts.setSpeechRate(0.47);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  GuidanceSpotViewData _resolveCurrentSpotData() {
    final String resolvedLabel = resolveSpotLabelFromTicketCode(
      widget.spotLabel,
      widget.spots,
      fallback: widget.spotLabel,
    );

    return _layout.findByLabel(resolvedLabel) ?? _layout.topRow.first;
  }

  double get _progress => (70 - _distanceMeters) / 70;

  void _refreshInstruction({bool forceSpeak = false}) {
    final double p = _progress.clamp(0.0, 1.0);
    final String next;

    if (p < 0.4) {
      next = 'Marchez vers la voie centrale puis tournez à droite.';
    } else if (p < 0.75) {
      next = 'Continuez sur la voie droite vers la sortie.';
    } else {
      next = 'La sortie est en face. Continuez quelques pas.';
    }

    if (forceSpeak || next != _instruction) {
      _instruction = next;
      if (_voiceEnabled) _speak(next);
    }
  }

  Future<void> _speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  void _toggleVoice() {
    if (widget.showMapComingSoon) {
      AppFeedback.showInfo(
        context,
        'La voix est indisponible pour ce parking non equipe.',
      );
      return;
    }
    setState(() => _voiceEnabled = !_voiceEnabled);
    if (_voiceEnabled) {
      _speak(_instruction);
    } else {
      _tts.stop();
    }
  }

  Future<void> _onArrived() async {
    if (_isCompletingExit) return;
    setState(() => _isCompletingExit = true);
    _tts.stop();

    try {
      // Open exit scanner - session will close after successful ticket scan
      // Scanner auto-closes and returns true after exit validation
      final bool exitSuccessful = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => ScannerScreen(
                initialMode: ScanMode.exit,
                onScanSuccess: () {
                  // Empty callback - scanner handles exit session closure
                },
              ),
            ),
          ) ??
          false;

      if (!mounted) return;

      if (exitSuccessful) {
        HapticFeedback.heavyImpact();
        // Show exit success screen
        await Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const ExitSuccessScreen()),
        );
        // Pop back to main navigation
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showError(
        context,
        e is ReservationException ? e.message : 'Erreur lors de la sortie.',
      );
    } finally {
      if (mounted) setState(() => _isCompletingExit = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: _kDark),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          'Guider vers la sortie',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: _kDark,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          children: <Widget>[
            Expanded(
              child: widget.showMapComingSoon
                  ? _buildComingSoonCard()
                  : Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: AnimatedBuilder(
                          animation: _pathController,
                          builder: (_, __) {
                            return LayoutBuilder(
                              builder: (context, constraints) {
                                return CustomPaint(
                                  size: Size(
                                    constraints.maxWidth,
                                    constraints.maxHeight,
                                  ),
                                  painter: _ExitTopViewPainter(
                                    dashProgress: _pathController.value,
                                    travelProgress: _progress.clamp(0.0, 1.0),
                                    spotLabel: _normalizedSpotLabel,
                                    isTopRow: _isTopRow,
                                    spotColIndex: _spotColIndex,
                                    topRow: _layout.topRow,
                                    bottomRow: _layout.bottomRow,
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 9,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: _kBlue.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.exit_to_app_rounded,
                            color: _kBlue),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _instruction,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _kDark,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (widget.showMapComingSoon)
                    const Text(
                      'Carte et guidage vocal indisponibles pour ce parking.',
                      style: TextStyle(
                        fontSize: 13,
                        color: _kMid,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else ...<Widget>[
                    Row(
                      children: <Widget>[
                        Text(
                          'Distance: $_distanceMeters m',
                          style: const TextStyle(
                            fontSize: 13,
                            color: _kMid,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Place: $_normalizedSpotLabel',
                          style: const TextStyle(
                            fontSize: 13,
                            color: _kMid,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _toggleVoice,
                          icon: Icon(
                            _voiceEnabled
                                ? Icons.volume_up_rounded
                                : Icons.volume_off_rounded,
                            size: 18,
                          ),
                          label:
                              Text(_voiceEnabled ? 'Voix ON' : 'Voix OFF'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '🔵 Votre place · 🟢 Libre · 🟠 Réservé · 🔴 Occupé',
                      style: TextStyle(
                        fontSize: 12,
                        color: _kMid,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isCompletingExit ? null : _onArrived,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kBlue,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: _isCompletingExit
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white),
                              ),
                            )
                          : const Icon(Icons.meeting_room_outlined,
                              color: Colors.white),
                      label: Text(
                        _isCompletingExit ? 'Vérification...' : 'Arrivé',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComingSoonCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.map_outlined, size: 52, color: _kBlue),
              SizedBox(height: 12),
              Text(
                'La carte de ce parking sera affichée prochainement.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _kDark,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Top-view exit painter.
///
/// Layout: same as photo (A row top, B row bottom, center road with trees,
/// ENTRÉE bottom-left, SORTIE bottom-right).
///
/// Exit path rule: from the current spot, the user must reach the SORTIE
/// which is at bottom-right corner. Path uses ONLY roads:
///   - For row B: go right along bottom road to right road, down to SORTIE
///   - For row A: drop down through center road to bottom road,
///                then go right along bottom road to right road, down to SORTIE
class _ExitTopViewPainter extends CustomPainter {
  final double dashProgress;
  final double travelProgress;
  final String spotLabel;
  final bool isTopRow;
  final int spotColIndex; // 0=left(A3/B3), 1=center(A2/B2), 2=right(A1/B1)
  final List<GuidanceSpotViewData> topRow;
  final List<GuidanceSpotViewData> bottomRow;

  _ExitTopViewPainter({
    required this.dashProgress,
    required this.travelProgress,
    required this.spotLabel,
    required this.isTopRow,
    required this.spotColIndex,
    required this.topRow,
    required this.bottomRow,
  });

  static const double _roadW = 28.0;
  static const double _treeR = 9.0;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    final double topRoadBot = _roadW;
    final double bottomRoadTop = h - _roadW;
    final double leftRoadRight = _roadW;
    final double rightRoadLeft = w - _roadW;
    final double innerW = w - 2 * _roadW;
    final double innerH = h - 2 * _roadW;
    const double centerRoadH = 26.0;
    final double spotAreaH = (innerH - centerRoadH) / 2;
    final double rowATop = topRoadBot;
    final double rowABot = topRoadBot + spotAreaH;
    final double centerRoadTop = rowABot;
    final double centerRoadBot = rowABot + centerRoadH;
    final double rowBTop = centerRoadBot;
    final double rowBBot = bottomRoadTop;

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = const Color(0xFF1C2333),
    );

    // Roads
    final Paint roadPaint = Paint()..color = const Color(0xFF2E3A50);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, _roadW), roadPaint);
    canvas.drawRect(Rect.fromLTWH(0, bottomRoadTop, w, _roadW), roadPaint);
    canvas.drawRect(Rect.fromLTWH(0, 0, _roadW, h), roadPaint);
    canvas.drawRect(Rect.fromLTWH(rightRoadLeft, 0, _roadW, h), roadPaint);
    canvas.drawRect(
      Rect.fromLTWH(_roadW, centerRoadTop, innerW, centerRoadH),
      roadPaint,
    );

    // Spot columns
    const int nCols = 3;
    final double colW = innerW / nCols;
    final List<double> colCX = List.generate(
      nCols,
      (i) => leftRoadRight + colW * i + colW / 2,
    );

    const double spotMargin = 4.0;

    // Row A
    for (int c = 0; c < nCols; c++) {
      final GuidanceSpotViewData spot = topRow[c];
      final bool isTarget = spot.label == spotLabel;
      _drawSpot(
        canvas,
        Rect.fromLTWH(
          leftRoadRight + colW * c + spotMargin,
          rowATop + spotMargin,
          colW - spotMargin * 2,
          spotAreaH - spotMargin * 2,
        ),
        spot,
        isTarget,
      );
    }

    // Row B
    for (int c = 0; c < nCols; c++) {
      final GuidanceSpotViewData spot = bottomRow[c];
      final bool isTarget = spot.label == spotLabel;
      _drawSpot(
        canvas,
        Rect.fromLTWH(
          leftRoadRight + colW * c + spotMargin,
          rowBTop + spotMargin,
          colW - spotMargin * 2,
          (rowBBot - rowBTop) - spotMargin * 2,
        ),
        spot,
        isTarget,
      );
    }

    // Trees
    final double treeCY = centerRoadTop + centerRoadH / 2;
    for (final double tx in [
      leftRoadRight + innerW * 0.17,
      leftRoadRight + innerW * 0.50,
      leftRoadRight + innerW * 0.83,
    ]) {
      _drawTree(canvas, Offset(tx, treeCY));
    }

    // Labels
    _drawLabel(canvas, 'ENTRÉE',
        Offset(leftRoadRight + 4, bottomRoadTop + _roadW / 2),
        color: _kBlue, fontSize: 9, bold: true);
    _drawLabel(canvas, 'SORTIE',
        Offset(rightRoadLeft - 46, bottomRoadTop + _roadW / 2),
        color: _kBlue, fontSize: 9, bold: true);

    // Exit arrow at SORTIE
    _drawExitArrow(canvas, Offset(rightRoadLeft + _roadW / 2, h - 6));

    // Path: from current spot → exit via roads only (no tree zone)
    //
    // Row A (top spots): spot → up to top road → right along top road
    //                    → down right vertical road → SORTIE (bottom-right)
    //
    // Row B (bottom spots): spot → down to bottom road → right along bottom road
    //                       → down right vertical road → SORTIE (bottom-right)
    final double spotCX = colCX[spotColIndex];
    final double spotCY = isTopRow
        ? (rowATop + spotAreaH / 2)
        : (rowBTop + (rowBBot - rowBTop) / 2);

    final double rightRoadCX = rightRoadLeft + _roadW / 2;
    final double topRoadCY = _roadW / 2; // center of top horizontal road
    final double bottomRoadCY = bottomRoadTop + _roadW / 2;
    final double exitY = h; // bottom of canvas = SORTIE

    Path path;
    if (isTopRow) {
      // Row A: stay on top road, then right road.
      path = Path()
        ..moveTo(spotCX, topRoadCY)
        ..lineTo(rightRoadCX, topRoadCY)
        ..lineTo(rightRoadCX, exitY);
    } else {
      // Row B: stay on bottom road, then right road.
      path = Path()
        ..moveTo(spotCX, bottomRoadCY)
        ..lineTo(rightRoadCX, bottomRoadCY)
        ..lineTo(rightRoadCX, exitY);
    }

    _drawAnimatedPath(canvas, path);

    // Start marker (green = your spot)
    canvas.drawCircle(
      Offset(spotCX, spotCY),
      6,
      Paint()..color = _kBlue,
    );
  }

  void _drawSpot(
    Canvas canvas,
    Rect rect,
    GuidanceSpotViewData spot,
    bool isTarget,
  ) {
    final Color fillColor;
    if (isTarget) {
      fillColor = _kBlue;
    } else {
      switch (spot.state) {
        case GuidanceSpotState.available:
          fillColor = _kGreen;
        case GuidanceSpotState.reserved:
          fillColor = _kOrange;
        case GuidanceSpotState.occupied:
          fillColor = _kRed;
      }
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      Paint()..color = fillColor,
    );

    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: spot.displayLabel,
        style: TextStyle(
          color: isTarget ? Colors.white : Colors.white70,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(
      canvas,
      Offset(rect.center.dx - tp.width / 2, rect.center.dy - tp.height / 2),
    );
  }

  void _drawTree(Canvas canvas, Offset center) {
    canvas.drawCircle(center, _treeR + 2, Paint()..color = const Color(0xFF1A2810));
    canvas.drawCircle(center, _treeR, Paint()..color = const Color(0xFF2D5016));
    canvas.drawCircle(center, _treeR * 0.6, Paint()..color = const Color(0xFF3D6B1E));
  }

  void _drawExitArrow(Canvas canvas, Offset position) {
    final Paint arrowPaint = Paint()
      ..color = _kBlue
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(position.dx, position.dy - 10),
      Offset(position.dx, position.dy - 2),
      arrowPaint,
    );
    canvas.drawLine(
      Offset(position.dx - 4, position.dy - 6),
      Offset(position.dx, position.dy - 2),
      arrowPaint,
    );
    canvas.drawLine(
      Offset(position.dx + 4, position.dy - 6),
      Offset(position.dx, position.dy - 2),
      arrowPaint,
    );
  }

  void _drawLabel(Canvas canvas, String text, Offset position,
      {Color color = Colors.white, double fontSize = 10, bool bold = false}) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
          letterSpacing: 0.8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(position.dx, position.dy - tp.height / 2));
  }

  void _drawAnimatedPath(Canvas canvas, Path path) {
    final Paint pathPaint = Paint()
      ..color = _kBlue
      ..strokeWidth = 3.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final metric = path.computeMetrics().first;
    const double dash = 10;
    const double gap = 7;
    double distance = dashProgress * (dash + gap);

    while (distance < metric.length) {
      final double end = (distance + dash).clamp(0.0, metric.length);
      canvas.drawPath(metric.extractPath(distance, end), pathPaint);
      distance += dash + gap;
    }

    final Tangent? movingTangent = metric.getTangentForOffset(
      metric.length * travelProgress.clamp(0.0, 1.0),
    );
    if (movingTangent != null) {
      canvas.drawCircle(movingTangent.position, 8, Paint()..color = _kBlue);
      canvas.drawCircle(movingTangent.position, 3, Paint()..color = Colors.white);
    }

    final Tangent? destination = metric.getTangentForOffset(metric.length);
    if (destination != null) {
      canvas.drawCircle(destination.position, 6, Paint()..color = _kBlue.withOpacity(0.8));
    }
  }

  @override
  bool shouldRepaint(covariant _ExitTopViewPainter oldDelegate) {
    return oldDelegate.dashProgress != dashProgress ||
        oldDelegate.travelProgress != travelProgress ||
        oldDelegate.spotLabel != spotLabel;
  }
}