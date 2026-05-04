import 'dart:async';
import 'dart:ui' show Tangent;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:parking_front/features/guidance/presentation/utils/guidance_spot_layout.dart';
import 'package:parking_front/features/parking/models/parking.dart';

import 'vehicle_found_screen.dart';

const _kBg = Color(0xFFF0F4FA);
const _kBlue = Color(0xFF4A90E2);
const _kGreen = Color(0xFF2ECC71);
const _kOrange = Color(0xFFF5A623);
const _kRed = Color(0xFFE53935);
const _kDark = Color(0xFF1A1A2E);
const _kMid = Color(0xFF8A9BB5);
const _kCard = Colors.white;

class GuidanceToVehicleScreen extends StatefulWidget {
  final String spotLabel;
  final String parkingName;
  final String reservationId;
  final int durationMinutes;
  final List<ParkingIndoorSpot> spots;

  const GuidanceToVehicleScreen({
    super.key,
    this.spotLabel = 'B2',
    this.parkingName = 'Notre parking',
    this.reservationId = '',
    this.durationMinutes = 0,
    this.spots = const <ParkingIndoorSpot>[],
  });

  @override
  State<GuidanceToVehicleScreen> createState() =>
      _GuidanceToVehicleScreenState();
}

class _GuidanceToVehicleScreenState extends State<GuidanceToVehicleScreen>
    with SingleTickerProviderStateMixin {
  final FlutterTts _tts = FlutterTts();

  late final AnimationController _pathController;
  late final GuidanceSpotLayout _layout;
  late final GuidanceSpotViewData _targetSpotData;
  late final bool _resolvedIsTopRow;
  late final int _resolvedTargetColIndex;
  late final String _resolvedTargetLabel;
  Timer? _timer;

  bool _voiceEnabled = true;
  double _scale = 1.0;
  double _lastScale = 1.0;
  Offset _panOffset = Offset.zero;
  Offset _lastFocalPoint = Offset.zero;
  int _distanceMeters = 90;
  String _instruction = '';

  GuidanceSpotViewData _resolveTargetSpotData() {
    final String resolvedLabel = resolveSpotLabelFromTicketCode(
      widget.spotLabel,
      widget.spots,
      fallback: widget.spotLabel,
    );

    return _layout.findByLabel(resolvedLabel) ?? _layout.topRow.first;
  }

  @override
  void initState() {
    super.initState();
    _layout = GuidanceSpotLayout.fromIndoorSpots(widget.spots);
    _targetSpotData = _resolveTargetSpotData();
    _resolvedIsTopRow = _targetSpotData.rowIndex == 0;
    _resolvedTargetColIndex = _targetSpotData.colIndex;
    _resolvedTargetLabel = _targetSpotData.displayLabel;
    _pathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _configureVoice();
    _setInstruction(forceSpeak: true);

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _distanceMeters <= 0) return;
      setState(() {
        _distanceMeters = (_distanceMeters - 4).clamp(0, 10000);
      });
      _setInstruction();
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

  double get _progress => (90 - _distanceMeters) / 90;

  void _setInstruction({bool forceSpeak = false}) {
    final double p = _progress.clamp(0.0, 1.0);
    final String next;

    if (p < 0.35) {
      next = 'Entrez et avancez sur la voie de gauche.';
    } else if (p < 0.72) {
      next = _resolvedIsTopRow
          ? 'Tournez a droite et continuez vers les places du haut.'
          : 'Continuez tout droit vers les places du bas.';
    } else {
      next = 'Votre voiture est proche de la place $_resolvedTargetLabel.';
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
    setState(() => _voiceEnabled = !_voiceEnabled);
    if (_voiceEnabled) {
      _speak(_instruction);
    } else {
      _tts.stop();
    }
  }

  void _onArrived() {
    HapticFeedback.heavyImpact();
    Navigator.pushReplacement<void, bool>(
      context,
      MaterialPageRoute(
        builder: (_) => VehicleFoundScreen(
          spotLabel: _resolvedTargetLabel,
          reservationId: widget.reservationId,
          parkingName: widget.parkingName,
          dureeMinutes: widget.durationMinutes <= 0 ? 1 : widget.durationMinutes,
        ),
      ),
      result: true,
    );
  }

  void _resetMapView() {
    HapticFeedback.selectionClick();
    setState(() {
      _scale = 1.0;
      _lastScale = 1.0;
      _panOffset = Offset.zero;
      _lastFocalPoint = Offset.zero;
    });
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
          'Trouver ma voiture',
          style: TextStyle(
            color: _kDark,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          children: <Widget>[
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: GestureDetector(
                    onScaleStart: (ScaleStartDetails details) {
                      _lastScale = _scale;
                      _lastFocalPoint = details.focalPoint;
                    },
                    onScaleUpdate: (ScaleUpdateDetails details) {
                      setState(() {
                        _scale = (_lastScale * details.scale).clamp(0.8, 2.6);
                        final Offset delta = details.focalPoint - _lastFocalPoint;
                        _panOffset += delta;
                        _lastFocalPoint = details.focalPoint;
                      });
                    },
                    child: Stack(
                      children: <Widget>[
                        Center(
                          child: Transform.translate(
                            offset: _panOffset,
                            child: Transform.scale(
                              scale: _scale,
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
                                        painter: _TopViewParkingPainter(
                                          dashProgress: _pathController.value,
                                          travelProgress:
                                              _progress.clamp(0.0, 1.0),
                                          targetLabel: _resolvedTargetLabel,
                                          isTopRow: _resolvedIsTopRow,
                                          targetColIndex: _resolvedTargetColIndex,
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
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Column(
                            children: <Widget>[
                              _MapBtn(
                                icon: Icons.add,
                                onTap: () => setState(() {
                                  _scale = (_scale + 0.2).clamp(0.8, 2.6);
                                }),
                              ),
                              const SizedBox(height: 8),
                              _MapBtn(
                                icon: Icons.remove,
                                onTap: () => setState(() {
                                  _scale = (_scale - 0.2).clamp(0.8, 2.6);
                                }),
                              ),
                              const SizedBox(height: 8),
                              _MapBtn(
                                icon: Icons.my_location_rounded,
                                onTap: _resetMapView,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kCard,
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
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _kBlue.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.directions_walk_rounded, color: _kBlue),
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      _InfoChip(label: 'Distance: $_distanceMeters m'),
                      _InfoChip(label: 'Place: $_resolvedTargetLabel'),
                      _InfoChip(label: widget.parkingName),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '🔵 Votre voiture · 🟢 Libre · 🟠 Réservé · 🔴 Occupé',
                    style: TextStyle(
                      fontSize: 12,
                      color: _kMid,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      TextButton.icon(
                        onPressed: _toggleVoice,
                        icon: Icon(
                          _voiceEnabled
                              ? Icons.volume_up_rounded
                              : Icons.volume_off_rounded,
                          size: 18,
                        ),
                        label: Text(_voiceEnabled ? 'Voix ON' : 'Voix OFF'),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: 146,
                        height: 46,
                        child: ElevatedButton.icon(
                          onPressed: _onArrived,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kBlue,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.check_circle_outline_rounded,
                              color: Colors.white),
                          label: const Text(
                            'Arrivé',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Top-view parking map painter.
///
/// Layout (matches photo):
///   topRoad (y=0..roadW)
///   Row A: A3(col0) | A2(col1) | A1(col2)   — spots open downward
///   centerRoad with trees
///   Row B: B3(col0) | B2(col1) | B1(col2)   — spots open upward
///   bottomRoad (ENTRÉE left / SORTIE right)
///
/// Roads available for paths:
///   - leftRoad  (x=0..roadW)  — vertical, ENTRÉE side
///   - rightRoad (x=W-roadW..W) — vertical, SORTIE side
///   - topRoad   (y=0..roadW)  — horizontal
///   - centerRoad (between rows A and B)
///   - bottomRoad (y=H-roadW..H)
///
/// Path to reach a spot:
///   START at ENTRÉE = bottom-left corner of bottomRoad
///   → right along bottomRoad to leftRoad intersection
///   → up leftRoad
///   → for row A: continue up leftRoad past center, turn right on topRoad, drop down into spot
///   → for row B: turn right on bottomRoad directly to spot column, go up into spot
class _TopViewParkingPainter extends CustomPainter {
  final double dashProgress;
  final double travelProgress;
  final String targetLabel;
  final bool isTopRow;
  final int targetColIndex; // 0=left(A3/B3), 1=center(A2/B2), 2=right(A1/B1)
  final List<GuidanceSpotViewData> topRow;
  final List<GuidanceSpotViewData> bottomRow;

  _TopViewParkingPainter({
    required this.dashProgress,
    required this.travelProgress,
    required this.targetLabel,
    required this.isTopRow,
    required this.targetColIndex,
    required this.topRow,
    required this.bottomRow,
  });

  static const double _roadW = 28.0;
  static const double _treeR = 9.0;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    // ── Road geometry ──────────────────────────────────────────────────────
    final double topRoadTop = 0;
    final double topRoadBot = _roadW;
    final double bottomRoadTop = h - _roadW;
    final double bottomRoadBot = h;
    final double leftRoadLeft = 0;
    final double leftRoadRight = _roadW;
    final double rightRoadLeft = w - _roadW;
    final double rightRoadRight = w;

    // Inner width/height between roads
    final double innerW = w - 2 * _roadW;
    final double innerH = h - 2 * _roadW;

    // Spot rows occupy inner area
    // centerRoad is a horizontal band in the middle of innerH
    const double centerRoadH = 26.0;
    final double spotAreaH = (innerH - centerRoadH) / 2;
    // Row A occupies top part of inner area (below topRoad)
    final double rowATop = topRoadBot;
    final double rowABot = topRoadBot + spotAreaH;
    // Center road
    final double centerRoadTop = rowABot;
    final double centerRoadBot = rowABot + centerRoadH;
    // Row B
    final double rowBTop = centerRoadBot;
    final double rowBBot = bottomRoadTop;

    // ── Background ─────────────────────────────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = const Color(0xFF1C2333),
    );

    // ── Roads ──────────────────────────────────────────────────────────────
    final Paint roadPaint = Paint()..color = const Color(0xFF2E3A50);

    // Horizontal roads
    canvas.drawRect(Rect.fromLTWH(0, topRoadTop, w, _roadW), roadPaint);
    canvas.drawRect(Rect.fromLTWH(0, bottomRoadTop, w, _roadW), roadPaint);
    // Vertical roads
    canvas.drawRect(Rect.fromLTWH(leftRoadLeft, 0, _roadW, h), roadPaint);
    canvas.drawRect(Rect.fromLTWH(rightRoadLeft, 0, _roadW, h), roadPaint);
    // Center road
    canvas.drawRect(
      Rect.fromLTWH(_roadW, centerRoadTop, innerW, centerRoadH),
      roadPaint,
    );

    // ── Road markings (white dashes) ───────────────────────────────────────
    _drawDashedLine(
      canvas,
      Offset(w / 2, topRoadTop + 2),
      Offset(w / 2, topRoadBot - 2),
      horizontal: false,
      color: Colors.white38,
    );
    _drawDashedLine(
      canvas,
      Offset(w / 2, bottomRoadTop + 2),
      Offset(w / 2, bottomRoadBot - 2),
      horizontal: false,
      color: Colors.white38,
    );
    _drawDashedLine(
      canvas,
      Offset(leftRoadLeft + 2, h / 2),
      Offset(leftRoadRight - 2, h / 2),
      horizontal: true,
      color: Colors.white38,
    );
    _drawDashedLine(
      canvas,
      Offset(rightRoadLeft + 2, h / 2),
      Offset(rightRoadRight - 2, h / 2),
      horizontal: true,
      color: Colors.white38,
    );

    // ── Spot columns x-positions ───────────────────────────────────────────
    // 3 columns inside inner width, evenly spaced
    const int nCols = 3;
    final double colW = innerW / nCols;
    // col centers (x)
    final List<double> colCX = List.generate(
      nCols,
      (i) => leftRoadRight + colW * i + colW / 2,
    );

    // ── Row A spots (top row, spots open downward) ─────────────────────────
    const double spotMargin = 4.0;
    for (int c = 0; c < nCols; c++) {
      final GuidanceSpotViewData slot = topRow[c];
      final bool isTarget = slot.label == targetLabel;
      final Rect rect = Rect.fromLTWH(
        leftRoadRight + colW * c + spotMargin,
        rowATop + spotMargin,
        colW - spotMargin * 2,
        spotAreaH - spotMargin * 2,
      );
      _drawSpot(canvas, rect, slot, isTarget);
    }

    // ── Row B spots (bottom row, spots open upward) ────────────────────────
    for (int c = 0; c < nCols; c++) {
      final GuidanceSpotViewData slot = bottomRow[c];
      final bool isTarget = slot.label == targetLabel;
      final Rect rect = Rect.fromLTWH(
        leftRoadRight + colW * c + spotMargin,
        rowBTop + spotMargin,
        colW - spotMargin * 2,
        (rowBBot - rowBTop) - spotMargin * 2,
      );
      _drawSpot(canvas, rect, slot, isTarget);
    }

    // ── Trees in center road ───────────────────────────────────────────────
    final double treeCY = centerRoadTop + centerRoadH / 2;
    final List<double> treeCXList = [
      leftRoadRight + innerW * 0.17,
      leftRoadRight + innerW * 0.50,
      leftRoadRight + innerW * 0.83,
    ];
    for (final double tx in treeCXList) {
      _drawTree(canvas, Offset(tx, treeCY));
    }

    // ── ENTRÉE / SORTIE labels ─────────────────────────────────────────────
    _drawLabel(
      canvas,
      'ENTRÉE',
      Offset(leftRoadRight + 4, bottomRoadTop + _roadW / 2),
      color: const Color(0xFF4A90E2),
      fontSize: 9,
      bold: true,
    );
    _drawLabel(
      canvas,
      'SORTIE',
      Offset(rightRoadLeft - 46, bottomRoadTop + _roadW / 2),
      color: const Color(0xFF4A90E2),
      fontSize: 9,
      bold: true,
    );

    // ── Animated guidance path ─────────────────────────────────────────────
    // Entry point: bottom of leftRoad (ENTRÉE)
    final double entryX = leftRoadLeft + _roadW / 2;
    final double entryY = bottomRoadBot; // bottom of canvas = ENTRÉE

    // Target column center
    final double targetCX = colCX[targetColIndex];
    final double topRoadCY = topRoadTop + _roadW / 2;
    final double bottomRoadCY = bottomRoadTop + _roadW / 2;

    // Build path along roads only (no spot crossing).
    Path path;

    if (isTopRow) {
      // Row A: stay on top road.
      path = Path()
        ..moveTo(entryX, entryY)
        ..lineTo(entryX, topRoadCY)
        ..lineTo(targetCX, topRoadCY);
    } else {
      // Row B: stay on bottom road.
      path = Path()
        ..moveTo(entryX, entryY)
        ..lineTo(entryX, bottomRoadCY)
        ..lineTo(targetCX, bottomRoadCY);
    }

    _drawAnimatedPath(canvas, path);

    // ── Entry marker (red dot = user position) ────────────────────────────
    canvas.drawCircle(
      Offset(entryX, bottomRoadTop + _roadW / 2),
      6,
      Paint()..color = const Color(0xFFE53935),
    );
  }

  void _drawSpot(
    Canvas canvas,
    Rect rect,
    GuidanceSpotViewData slot,
    bool isTarget,
  ) {
    Color fillColor;
    if (isTarget) {
      fillColor = _kBlue;
    } else {
      switch (slot.state) {
        case GuidanceSpotState.available:
          fillColor = _kGreen;
        case GuidanceSpotState.reserved:
          fillColor = _kOrange;
        case GuidanceSpotState.occupied:
          fillColor = _kRed;
      }
    }

    final RRect rRect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    canvas.drawRRect(rRect, Paint()..color = fillColor);

    // Border for empty spots
    if (!isTarget && slot.state == GuidanceSpotState.available) {
      canvas.drawRRect(
        rRect,
        Paint()
          ..color = Colors.white24
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    // Destination pin icon for target
    if (isTarget) {
      canvas.drawCircle(
        Offset(rect.center.dx, rect.center.dy - 6),
        5,
        Paint()..color = Colors.white,
      );
    }

    // Label
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: slot.displayLabel,
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
      Offset(
        rect.center.dx - tp.width / 2,
        isTarget ? rect.center.dy + 2 : rect.center.dy - tp.height / 2,
      ),
    );
  }

  void _drawTree(Canvas canvas, Offset center) {
    canvas.drawCircle(
      center,
      _treeR + 2,
      Paint()..color = const Color(0xFF1A2810),
    );
    canvas.drawCircle(
      center,
      _treeR,
      Paint()..color = const Color(0xFF2D5016),
    );
    canvas.drawCircle(
      center,
      _treeR * 0.6,
      Paint()..color = const Color(0xFF3D6B1E),
    );
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end, {
    required bool horizontal,
    Color color = Colors.white30,
  }) {
    final Paint p = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    const double dashLen = 6;
    const double gapLen = 5;
    final double total =
        horizontal ? (end.dx - start.dx) : (end.dy - start.dy);
    double d = 0;
    while (d < total) {
      final double e = (d + dashLen).clamp(0.0, total);
      if (horizontal) {
        canvas.drawLine(
          Offset(start.dx + d, start.dy),
          Offset(start.dx + e, end.dy),
          p,
        );
      } else {
        canvas.drawLine(
          Offset(start.dx, start.dy + d),
          Offset(end.dx, start.dy + e),
          p,
        );
      }
      d += dashLen + gapLen;
    }
  }

  void _drawLabel(
    Canvas canvas,
    String text,
    Offset position, {
    Color color = Colors.white,
    double fontSize = 10,
    bool bold = false,
  }) {
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

    // Moving dot
    final Tangent? movingTangent = metric.getTangentForOffset(
      metric.length * travelProgress.clamp(0.0, 1.0),
    );
    if (movingTangent != null) {
      canvas.drawCircle(movingTangent.position, 8, Paint()..color = _kBlue);
      canvas.drawCircle(movingTangent.position, 3, Paint()..color = Colors.white);
    }

    // Destination dot
    final Tangent? destination = metric.getTangentForOffset(metric.length);
    if (destination != null) {
      canvas.drawCircle(destination.position, 6, Paint()..color = _kBlue);
    }
  }

  @override
  bool shouldRepaint(covariant _TopViewParkingPainter oldDelegate) {
    return oldDelegate.dashProgress != dashProgress ||
        oldDelegate.travelProgress != travelProgress ||
        oldDelegate.targetLabel != targetLabel;
  }
}

class _MapBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MapBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 20, color: const Color(0xFF3D4D6A)),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;

  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1FB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          color: _kMid,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
