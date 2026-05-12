import 'dart:async';
import 'dart:ui' show Tangent;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:parking_front/features/guidance/presentation/utils/guidance_spot_layout.dart';
import 'package:parking_front/features/parking/data/parking_repository.dart';
import 'package:parking_front/features/parking/models/parking.dart';

import 'vehicle_parked_confirmation_screen.dart';

const _kBg = Color(0xFFF0F4FA);
const _kBlue = Color(0xFF4A90E2);
const _kGreen = Color(0xFF2ECC71);
const _kOrange = Color(0xFFF5A623);
const _kRed = Color(0xFFE53935);
const _kDark = Color(0xFF1A1A2E);
const _kMid = Color(0xFF8A9BB5);

class GuidanceToSpotScreen extends StatefulWidget {
  final String spotLabel;
  final String floor;
  final bool isGuideToFree;
  final List<ParkingIndoorSpot> spots;
  final String? parkingId;
  final String? parkingName;

  const GuidanceToSpotScreen({
    super.key,
    this.spotLabel = 'A01',
    this.floor = 'Niveau -1',
    this.isGuideToFree = true,
    this.spots = const <ParkingIndoorSpot>[],
    this.parkingId,
    this.parkingName,
  });

  @override
  State<GuidanceToSpotScreen> createState() => _GuidanceToSpotScreenState();
}

class _GuidanceToSpotScreenState extends State<GuidanceToSpotScreen>
    with SingleTickerProviderStateMixin {
  final FlutterTts _tts = FlutterTts();
  final ParkingRepository _parkingRepository = ParkingRepository();

  late final AnimationController _pathController;
  GuidanceSpotLayout _layout = const GuidanceSpotLayout(
    topRow: <GuidanceSpotViewData>[],
    bottomRow: <GuidanceSpotViewData>[],
  );
  GuidanceSpotViewData? _targetSpotData;
  bool _resolvedIsTopRow = false;
  int _resolvedTargetColIndex = 0;
  Timer? _timer;
  Timer? _refreshTimer;
  bool _isRefreshing = false;
  List<ParkingIndoorSpot> _spots = const <ParkingIndoorSpot>[];

  double _scale = 1.0;
  double _lastScale = 1.0;
  bool _voiceEnabled = true;
  int _distanceMeters = 120;
  String _currentInstruction = '';
  String _targetSpot = '';

  @override
  void initState() {
    super.initState();
    _spots = widget.spots;
    _rebuildLayoutAndTarget(forceAnnounce: true);
    _pathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();

    _configureVoice();
    _updateInstruction(forceSpeak: true);

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _distanceMeters <= 0) return;
      setState(() {
        _distanceMeters = (_distanceMeters - 5).clamp(0, 10000);
      });
      _updateInstruction();
    });

    // Live refresh des places (couleurs + place cible la plus proche)
    if ((widget.parkingId ?? '').isNotEmpty ||
        (widget.parkingName ?? '').isNotEmpty) {
      _refreshTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _refreshSpotsFromBackend(),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _refreshTimer?.cancel();
    _pathController.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _refreshSpotsFromBackend() async {
    if (!mounted || _isRefreshing) return;
    _isRefreshing = true;
    try {
      final List<Parking> parkings =
          await _parkingRepository.fetchParkings(forceRefresh: true);
      final String idNeedle = (widget.parkingId ?? '').trim().toLowerCase();
      final String nameNeedle = (widget.parkingName ?? '').trim().toLowerCase();
      Parking? match;
      for (final Parking p in parkings) {
        if (idNeedle.isNotEmpty && p.id.trim().toLowerCase() == idNeedle) {
          match = p;
          break;
        }
      }
      if (match == null && nameNeedle.isNotEmpty) {
        for (final Parking p in parkings) {
          if (p.name.trim().toLowerCase() == nameNeedle) {
            match = p;
            break;
          }
        }
      }
      final List<ParkingIndoorSpot> fresh =
          match?.indoorMap?.spots ?? const <ParkingIndoorSpot>[];
      if (!mounted || fresh.isEmpty) return;
      setState(() {
        _spots = fresh;
        _rebuildLayoutAndTarget();
      });
    } catch (_) {
      // Silent: keep previous snapshot until next tick.
    } finally {
      _isRefreshing = false;
    }
  }

  void _rebuildLayoutAndTarget({bool forceAnnounce = false}) {
    _layout = GuidanceSpotLayout.fromIndoorSpots(_spots);
    final GuidanceSpotViewData next = _resolveTargetSpotData();
    final bool changed = _targetSpotData == null ||
        _targetSpotData!.displayLabel != next.displayLabel ||
        _targetSpotData!.rowIndex != next.rowIndex ||
        _targetSpotData!.colIndex != next.colIndex;
    _targetSpotData = next;
    _resolvedIsTopRow = next.rowIndex == 0;
    _resolvedTargetColIndex = next.colIndex;
    _targetSpot = next.displayLabel;
    if (changed && !forceAnnounce) {
      // Recibler vers la nouvelle place: reset progression et annoncer.
      _distanceMeters = 120;
      _currentInstruction = '';
      _updateInstruction(forceSpeak: true);
    }
  }

  Future<void> _configureVoice() async {
    await _tts.setLanguage('fr-FR');
    await _tts.setSpeechRate(0.47);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  GuidanceSpotViewData _resolveTargetSpotData() {
    final String resolvedLabel = resolveSpotLabelFromTicketCode(
      widget.spotLabel,
      _spots,
      fallback: widget.spotLabel,
    );

    final GuidanceSpotViewData? resolved = _layout.findByLabel(resolvedLabel);
    final GuidanceSpotViewData? nearestFree = _layout.findNearestAvailable();

    if (widget.isGuideToFree) {
      // Toujours la place la plus proche de l'ENTRÉE (bottom-row d'abord)
      if (nearestFree != null) return nearestFree;
      return resolved ?? _layout.bottomRow.firstOrNull ?? _layout.topRow.first;
    }

    // Mode réservation: respecter la place réservée tant qu'elle est valide
    if (resolved != null &&
        (resolved.state == GuidanceSpotState.available ||
            resolved.state == GuidanceSpotState.reserved)) {
      return resolved;
    }

    return nearestFree ??
        resolved ??
        _layout.bottomRow.firstOrNull ??
        _layout.topRow.first;
  }

  double get _progress => (120 - _distanceMeters) / 120;

  void _updateInstruction({bool forceSpeak = false}) {
    final double p = _progress.clamp(0.0, 1.0);
    final String next;

    if (p < 0.35) {
      next = 'Entrez et avancez sur la voie de gauche.';
    } else if (p < 0.72) {
      next = _resolvedIsTopRow
          ? 'Montez sur la voie gauche puis tournez vers les places du haut.'
          : 'Continuez tout droit vers les places du bas.';
    } else {
      next = 'La place $_targetSpot est juste devant vous.';
    }

    if (forceSpeak || next != _currentInstruction) {
      _currentInstruction = next;
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
      _speak(_currentInstruction);
    } else {
      _tts.stop();
    }
  }

  Future<void> _onArrived() async {
    HapticFeedback.heavyImpact();
    final bool parkedConfirmed = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => VehicleParkedConfirmationScreen(
              spotLabel: _targetSpot,
              floor: widget.floor,
            ),
          ),
        ) ??
        false;

    if (!mounted || !parkedConfirmed) return;
    Navigator.pop(context, true);
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
        title: Text(
          widget.isGuideToFree
              ? 'Guider vers une place vide'
              : 'Guidage parking',
          style: const TextStyle(
            color: _kDark,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
        child: Column(
          children: <Widget>[
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 14,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: GestureDetector(
                    onScaleStart: (_) => _lastScale = _scale,
                    onScaleUpdate: (ScaleUpdateDetails details) {
                      setState(() {
                        _scale = (_lastScale * details.scale).clamp(0.8, 2.6);
                      });
                    },
                    child: Stack(
                      children: <Widget>[
                        Center(
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
                                      painter: _SpotFinderTopViewPainter(
                                        dashProgress: _pathController.value,
                                        travelProgress:
                                            _progress.clamp(0.0, 1.0),
                                        targetSpot: _targetSpot,
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
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Column(
                            children: <Widget>[
                              _MapCircleButton(
                                icon: Icons.add,
                                onTap: () => setState(() {
                                  _scale = (_scale + 0.2).clamp(0.8, 2.6);
                                }),
                              ),
                              const SizedBox(height: 8),
                              _MapCircleButton(
                                icon: Icons.remove,
                                onTap: () => setState(() {
                                  _scale = (_scale - 0.2).clamp(0.8, 2.6);
                                }),
                              ),
                              const SizedBox(height: 8),
                              _MapCircleButton(
                                icon: Icons.my_location_rounded,
                                onTap: () => setState(() => _scale = 1.0),
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
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _kGreen.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.navigation_rounded,
                            color: _kGreen),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _currentInstruction,
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
                  Row(
                    children: <Widget>[
                      Text(
                        'Distance: $_distanceMeters m',
                        style: const TextStyle(
                          color: _kMid,
                          fontSize: 13,
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
                        label: Text(_voiceEnabled ? 'Voix ON' : 'Voix OFF'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '🔵 Destination · 🟢 Libre · 🟠 Réservé · 🔴 Occupé',
                    style: TextStyle(
                      fontSize: 12,
                      color: _kMid,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _onArrived,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kBlue,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.check_circle_outline_rounded,
                          color: Colors.white),
                      label: const Text(
                        'Arrivé',
                        style: TextStyle(
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
}

class _SpotFinderTopViewPainter extends CustomPainter {
  final double dashProgress;
  final double travelProgress;
  final String targetSpot;
  final bool isTopRow;
  final int targetColIndex;
  final List<GuidanceSpotViewData> topRow;
  final List<GuidanceSpotViewData> bottomRow;

  _SpotFinderTopViewPainter({
    required this.dashProgress,
    required this.travelProgress,
    required this.targetSpot,
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
      final bool isTarget = spot.label == targetSpot;
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
      final bool isTarget = spot.label == targetSpot;
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
    _drawLabel(
        canvas, 'ENTRÉE', Offset(leftRoadRight + 4, bottomRoadTop + _roadW / 2),
        color: _kBlue, fontSize: 9, bold: true);
    _drawLabel(canvas, 'SORTIE',
        Offset(rightRoadLeft - 46, bottomRoadTop + _roadW / 2),
        color: _kBlue, fontSize: 9, bold: true);

    // Path: ENTRÉE (bottom-left) → target spot
    final double entryX = _roadW / 2;
    final double entryY = h; // bottom of canvas

    final double targetCX = colCX[targetColIndex];
    final double topRoadCY = _roadW / 2;
    final double bottomRoadCY = bottomRoadTop + _roadW / 2;

    Path path;
    if (isTopRow) {
      // Stay on top road to avoid crossing spots.
      path = Path()
        ..moveTo(entryX, entryY)
        ..lineTo(entryX, topRoadCY)
        ..lineTo(targetCX, topRoadCY);
    } else {
      // Stay on bottom road to avoid crossing spots.
      path = Path()
        ..moveTo(entryX, entryY)
        ..lineTo(entryX, bottomRoadCY)
        ..lineTo(targetCX, bottomRoadCY);
    }

    _drawAnimatedPath(canvas, path);

    // Entry marker
    canvas.drawCircle(
      Offset(entryX, bottomRoadTop + _roadW / 2),
      6,
      Paint()..color = _kRed,
    );
  }

  void _drawSpot(
    Canvas canvas,
    Rect rect,
    GuidanceSpotViewData spot,
    bool isTarget,
  ) {
    Color fillColor;
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

    final RRect rRect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    canvas.drawRRect(rRect, Paint()..color = fillColor);

    if (isTarget) {
      canvas.drawCircle(
        Offset(rect.center.dx, rect.center.dy - 8),
        5,
        Paint()..color = Colors.white,
      );
    }

    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: spot.displayLabel,
        style: const TextStyle(
          color: Colors.white,
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
        isTarget ? rect.center.dy - 2 : rect.center.dy - tp.height / 2,
      ),
    );
  }

  void _drawTree(Canvas canvas, Offset center) {
    canvas.drawCircle(
        center, _treeR + 2, Paint()..color = const Color(0xFF1A2810));
    canvas.drawCircle(center, _treeR, Paint()..color = const Color(0xFF2D5016));
    canvas.drawCircle(
        center, _treeR * 0.6, Paint()..color = const Color(0xFF3D6B1E));
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
      canvas.drawCircle(
          movingTangent.position, 3, Paint()..color = Colors.white);
    }

    final Tangent? destination = metric.getTangentForOffset(metric.length);
    if (destination != null) {
      canvas.drawCircle(destination.position, 6, Paint()..color = _kGreen);
    }
  }

  @override
  bool shouldRepaint(covariant _SpotFinderTopViewPainter oldDelegate) {
    return oldDelegate.dashProgress != dashProgress ||
        oldDelegate.travelProgress != travelProgress ||
        oldDelegate.targetSpot != targetSpot;
  }
}

class _MapCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MapCircleButton({required this.icon, required this.onTap});

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
