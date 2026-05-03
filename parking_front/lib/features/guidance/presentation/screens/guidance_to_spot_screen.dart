import 'dart:async';
import 'dart:ui' show Tangent, PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:parking_front/features/parking/models/parking.dart';
import 'package:parking_front/core/state/selected_spot_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parking_front/core/theme/app_colors.dart';
import 'package:parking_front/features/guidance/presentation/utils/parking_pathfinder.dart';

import 'vehicle_parked_confirmation_screen.dart';

const _kBg = Color(0xFFF0F4FA);
const _kBlue = Color(0xFF4A90E2);
const _kGreen = Color(0xFF2ECC71);
const _kDark = Color(0xFF1A1A2E);
const _kMid = Color(0xFF8A9BB5);

enum _SpotState {
  libre,
  reserve,
  occupe,
  destination,
}

class _ParkingSpot {
  final String label;
  final _SpotState state;

  const _ParkingSpot(this.label, this.state);
}

class GuidanceToSpotScreen extends ConsumerStatefulWidget {
  final String spotLabel;
  final String floor;
  final bool isGuideToFree;
  final ParkingIndoorMap? indoorMap;

  const GuidanceToSpotScreen({
    super.key,
    this.spotLabel = 'B2',
    this.floor = 'Niveau -1',
    this.isGuideToFree = true,
    this.indoorMap,
  });

  @override
  ConsumerState<GuidanceToSpotScreen> createState() => _GuidanceToSpotScreenState();
}

class _GuidanceToSpotScreenState extends ConsumerState<GuidanceToSpotScreen>
  with SingleTickerProviderStateMixin {
  final FlutterTts _tts = FlutterTts();
  late List<_ParkingSpot> _leftColumn;
  late List<_ParkingSpot> _rightColumn;

  late final AnimationController _pathController;
  Timer? _timer;

  double _scale = 1.0;
  double _lastScale = 1.0;
  bool _voiceEnabled = true;
  int _distanceMeters = 120;
  String _currentInstruction = '';
  late final String _targetSpot;

  bool get _targetOnRight {
    final Match? match =
        RegExp(r'([AB])').firstMatch(_targetSpot.toUpperCase());
    final String letter = match?.group(1) ?? 'A';

    return letter == 'A';
  }

  String _normalizeSpotLabel(String rawValue) {
    final String source = rawValue.trim().toUpperCase();
    final Iterable<Match> matches =
        RegExp(r'([AB])\s*-?\s*(\d+)').allMatches(source);
    if (matches.isEmpty) {
      return 'A1';
    }

    final Match last = matches.last;
    final String letter = last.group(1) ?? 'A';
    final int raw = int.tryParse(last.group(2) ?? '1') ?? 1;
    final int normalized = ((raw - 1) % 3) + 1;

    return '$letter$normalized';
  }

  @override
  void initState() {
    super.initState();
    _initializeMapFromIndoorData();
    // Keep global spot only if it exists in current indoor map, otherwise resolve safely.
    final String? global = ref.read(selectedSpotProvider);
    String candidate = (global != null && global.trim().isNotEmpty)
        ? global.trim()
        : _resolveTargetSpot();
    if (!_spotExistsInGrid(candidate)) {
      candidate = _resolveTargetSpot();
    }
    _targetSpot = candidate;
    ref.read(selectedSpotProvider.notifier).state = _targetSpot;

    _pathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();

    _configureVoice();
    _updateInstruction(forceSpeak: true);

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _distanceMeters <= 0) {
        return;
      }

      setState(() {
        _distanceMeters = (_distanceMeters - 5).clamp(0, 10000);
      });
      _updateInstruction();
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
    await _tts.setSpeechRate(0.44);
    await _tts.setVolume(1.0);
    await _tts.setPitch(0.98);
  }

  void _initializeMapFromIndoorData() {
    const List<_ParkingSpot> fallbackTop = <_ParkingSpot>[
      _ParkingSpot('P01', _SpotState.libre),
      _ParkingSpot('P03', _SpotState.reserve),
      _ParkingSpot('P04', _SpotState.libre),
    ];
    const List<_ParkingSpot> fallbackBottom = <_ParkingSpot>[
      _ParkingSpot('P06', _SpotState.destination),
      _ParkingSpot('B3', _SpotState.occupe),
      _ParkingSpot('A3', _SpotState.occupe),
    ];

    final ParkingIndoorMap? map = widget.indoorMap;
    if (map == null || map.spots.isEmpty) {
      _leftColumn = fallbackTop;
      _rightColumn = fallbackBottom;
      return;
    }

    final List<ParkingIndoorSpot> sorted =
        List<ParkingIndoorSpot>.from(map.spots)
          ..sort((ParkingIndoorSpot a, ParkingIndoorSpot b) {
            final int byRow = a.row.compareTo(b.row);
            if (byRow != 0) {
              return byRow;
            }
            return a.col.compareTo(b.col);
          });

    final List<int> rows =
        sorted.map((ParkingIndoorSpot s) => s.row).toSet().toList()..sort();
    if (rows.isEmpty) {
      _leftColumn = fallbackTop;
      _rightColumn = fallbackBottom;
      return;
    }

    final int topRowValue = rows.first;
    final int bottomRowValue = rows.length > 1 ? rows.last : rows.first;

    List<_ParkingSpot> toSpots(int row) {
      return sorted
          .where((ParkingIndoorSpot spot) => spot.row == row)
          .take(3)
          .map(
            (ParkingIndoorSpot spot) =>
                _ParkingSpot(spot.label, _mapSpotState(spot.state)),
          )
          .toList(growable: false);
    }

    _leftColumn = toSpots(topRowValue);
    _rightColumn = toSpots(bottomRowValue);

    if (_leftColumn.isEmpty) {
      _leftColumn = fallbackTop;
    }
    if (_rightColumn.isEmpty) {
      _rightColumn = fallbackBottom;
    }
  }

  _SpotState _mapSpotState(String state) {
    switch (state.trim().toUpperCase()) {
      case 'AVAILABLE':
        return _SpotState.libre;
      case 'RESERVED':
        return _SpotState.reserve;
      default:
        return _SpotState.occupe;
    }
  }

  String _resolveTargetSpot() {
    if (!widget.isGuideToFree) {
      final String wanted = _normalizeSpotLabel(widget.spotLabel);
      for (final _ParkingSpot spot in <_ParkingSpot>[
        ..._leftColumn,
        ..._rightColumn
      ]) {
        if (_normalizeSpotLabel(spot.label) == wanted) {
          return spot.label;
        }
      }
      return wanted;
    }

    for (final _ParkingSpot spot in _rightColumn) {
      if (spot.state == _SpotState.libre) {
        return spot.label;
      }
    }

    for (final _ParkingSpot spot in _leftColumn) {
      if (spot.state == _SpotState.libre) {
        return spot.label;
      }
    }

    return widget.spotLabel;
  }

  bool _spotExistsInGrid(String label) {
    final String normalized = _normalizeSpotLabel(label);
    for (final _ParkingSpot spot in <_ParkingSpot>[..._leftColumn, ..._rightColumn]) {
      if (_normalizeSpotLabel(spot.label) == normalized) {
        return true;
      }
    }
    return false;
  }

  double get _progress => (120 - _distanceMeters) / 120;

  int get _targetRowIndex {
    final int topIndex = _leftColumn.indexWhere(
      (_ParkingSpot spot) => _normalizeSpotLabel(spot.label) == _targetSpot,
    );
    if (topIndex >= 0) {
      return 0;
    }

    final int bottomIndex = _rightColumn.indexWhere(
      (_ParkingSpot spot) => _normalizeSpotLabel(spot.label) == _targetSpot,
    );
    if (bottomIndex >= 0) {
      return 1;
    }

    final Match? match = RegExp(r'(\d+)').firstMatch(_targetSpot);
    final int spotNumber = int.tryParse(match?.group(1) ?? '1') ?? 1;
    return spotNumber > 3 ? 1 : 0;
  }

  void _updateInstruction({bool forceSpeak = false}) {
    final double p = _progress.clamp(0.0, 1.0);
    final String next;

    if (p < 0.45) {
      next = 'Suivez la voie centrale et maintenez une progression reguliere.';
    } else if (p < 0.78) {
      next = _targetOnRight
          ? 'A l\'intersection, tournez a droite puis restez sur la voie.'
          : 'A l\'intersection, tournez a gauche puis restez sur la voie.';
    } else {
      next = 'La place $_targetSpot est maintenant devant vous.';
    }

    if (forceSpeak || next != _currentInstruction) {
      _currentInstruction = next;
      if (_voiceEnabled) {
        _speak(next);
      }
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

    if (!mounted || !parkedConfirmed) {
      return;
    }

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
                                return CustomPaint(
                                  size: const Size(300, 360),
                                  painter: _SpotFinderPainter(
                                    dashProgress: _pathController.value,
                                    travelProgress: _progress.clamp(0.0, 1.0),
                                    targetSpot: _targetSpot,
                                    targetOnRight: _targetOnRight,
                                    targetRowIndex: _targetRowIndex,
                                    leftSpots: _leftColumn,
                                    rightSpots: _rightColumn,
                                  ),
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
                                onTap: () => setState(() {
                                  _scale = 1.0;
                                }),
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
                    '🟢 Libre · 🟠 Réservé · 🔴 Occupé · 🔵 Destination · ⚫ Hors service',
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
                        'Arrive',
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

class _SpotFinderPainter extends CustomPainter {
  final double dashProgress;
  final double travelProgress;
  final String targetSpot;
  final bool targetOnRight;
  final int targetRowIndex;
  final List<_ParkingSpot> leftSpots;
  final List<_ParkingSpot> rightSpots;

  _SpotFinderPainter({
    required this.dashProgress,
    required this.travelProgress,
    required this.targetSpot,
    required this.targetOnRight,
    required this.targetRowIndex,
    required this.leftSpots,
    required this.rightSpots,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double spotSize = kSpotSize;
    const double spacing = 12;
    const double topPadding = 18;
    const double sidePadding = 12;
    const double rowGap = 42;

    final double totalWidth = (spotSize * 3) + (spacing * 2);
    final double startX = (size.width - totalWidth) / 2;
    final double topRowY = topPadding;
    final double bottomRowY = topRowY + spotSize + rowGap;

    _drawEntryExit(canvas, size);

    for (int col = 0; col < 3; col++) {
      final double x = startX + (col * (spotSize + spacing));
      if (col < leftSpots.length) {
        _drawSpot(
          canvas,
          rect: Rect.fromLTWH(x, topRowY, spotSize, spotSize),
          spot: leftSpots[col],
        );
      }
      if (col < rightSpots.length) {
        _drawSpot(
          canvas,
          rect: Rect.fromLTWH(x, bottomRowY, spotSize, spotSize),
          spot: rightSpots[col],
        );
      }
    }

    _drawPathToDestination(
      canvas,
      size,
      startX,
      topRowY,
      bottomRowY,
      spotSize,
      spacing,
      sidePadding,
    );
  }

  void _drawEntryExit(Canvas canvas, Size size) {
    const double bottomMargin = 14;
    const double height = 32;
    const double width = 90;

    // Entrance (left)
    final Rect entranceRect = Rect.fromLTWH(
      size.width * 0.12,
      size.height - height - bottomMargin,
      width,
      height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(entranceRect, const Radius.circular(6)),
      Paint()..color = const Color(0xFFE8EEF7),
    );
    _drawTextCentered(
      canvas,
      'ENTRÉE',
      entranceRect.center,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: const Color(0xFF5A6B7A),
    );

    // Exit (right)
    final Rect exitRect = Rect.fromLTWH(
      size.width * 0.88 - width,
      size.height - height - bottomMargin,
      width,
      height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(exitRect, const Radius.circular(6)),
      Paint()..color = const Color(0xFFD4E8F0),
    );
    _drawTextCentered(
      canvas,
      'SORTIE',
      exitRect.center,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: _kBlue,
    );
  }

  void _drawPathToDestination(
    Canvas canvas,
    Size size,
    double startX,
    double topRowY,
    double bottomRowY,
    double spotSize,
    double spacing,
    double sidePadding,
  ) {
    final List<Rect> spotRects = <Rect>[];
    final Map<String, Rect> byLabel = <String, Rect>{};

    for (int col = 0; col < 3; col++) {
      final double x = startX + (col * (spotSize + spacing));
      if (col < leftSpots.length) {
        final Rect rect = Rect.fromLTWH(x, topRowY, spotSize, spotSize);
        spotRects.add(rect);
        byLabel[leftSpots[col].label] = rect;
      }
      if (col < rightSpots.length) {
        final Rect rect = Rect.fromLTWH(x, bottomRowY, spotSize, spotSize);
        spotRects.add(rect);
        byLabel[rightSpots[col].label] = rect;
      }
    }

    if (spotRects.isEmpty) {
      return;
    }

    final Rect targetRect = byLabel[targetSpot] ??
        spotRects[(targetRowIndex == 0 ? 0 : 3).clamp(0, spotRects.length - 1)];
    final Offset start = Offset(size.width / 2, size.height - 36);
    final Offset end = Offset(
      (targetOnRight ? targetRect.right + 4 : targetRect.left - 4)
          .clamp(6.0, size.width - 6.0),
      targetRect.center.dy,
    );

    final List<Offset> pathPoints = ParkingPathfinder.findPath(
      canvasSize: size,
      start: start,
      end: end,
      obstacles: spotRects,
      cellSize: 8,
      obstaclePadding: 2,
    );

    final Path fallbackPath = Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(start.dx, topRowY - 10)
      ..lineTo(targetOnRight ? size.width - sidePadding : sidePadding, topRowY - 10)
      ..lineTo(targetOnRight ? size.width - sidePadding : sidePadding, end.dy)
      ..lineTo(end.dx, end.dy);

    final Path path = pathPoints.length >= 2
        ? ParkingPathfinder.pathFromPoints(pathPoints)
        : fallbackPath;

    final Paint pathPaint = Paint()
      ..color = guideRed
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Always draw a faint full line first so guidance remains visible.
    canvas.drawPath(
      path,
      Paint()
        ..color = guideRed.withOpacity(0.50)
        ..strokeWidth = 3.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    Iterable<PathMetric> metrics = path.computeMetrics();
    if (metrics.isEmpty) {
      metrics = fallbackPath.computeMetrics();
      if (metrics.isEmpty) {
        return;
      }
    }
    final PathMetric metric = metrics.first;
    const double dashLen = 8;
    const double gapLen = 5;
    double distance = dashProgress * (dashLen + gapLen);

    while (distance < metric.length) {
      final double end = (distance + dashLen).clamp(0.0, metric.length);
      canvas.drawPath(metric.extractPath(distance, end), pathPaint);
      distance += dashLen + gapLen;
    }

    // Draw moving indicator
    final Tangent? movingTangent = metric.getTangentForOffset(
      metric.length * travelProgress.clamp(0.0, 1.0),
    );
    if (movingTangent != null) {
      canvas.drawCircle(movingTangent.position, 7, Paint()..color = guideRed);
      canvas.drawCircle(movingTangent.position, 2.5, Paint()..color = Colors.white);
    }

    canvas.drawCircle(end, 6, Paint()..color = appBlue);
  }

  void _drawSpot(
    Canvas canvas, {
    required Rect rect,
    required _ParkingSpot spot,
  }) {
    final bool isTarget = spot.label == targetSpot;
    final Color fillColor;

    if (isTarget) {
      fillColor = appBlue;
    } else {
      switch (spot.state) {
        case _SpotState.libre:
          fillColor = appGreen;
        case _SpotState.reserve:
          fillColor = appOrange;
        case _SpotState.occupe:
          fillColor = appRed;
        case _SpotState.destination:
          fillColor = appBlue;
      }
    }

    // subtle shadow / outer contour
    final RRect outer = RRect.fromRectAndRadius(
      rect.inflate(3),
      const Radius.circular(kSpotCornerRadius + 3),
    );
    canvas.drawRRect(
      outer,
      Paint()..color = Colors.black.withOpacity(0.04),
    );

    // Draw background fill
    final RRect rrect = RRect.fromRectAndRadius(rect, const Radius.circular(kSpotCornerRadius));
    canvas.drawRRect(rrect, Paint()..color = fillColor);

    // Draw light border contour
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Colors.white.withOpacity(0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );

    // Highlight target with colorful gradient stroke
    if (isTarget) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = Colors.transparent
          ..strokeWidth = 2.8
          ..style = PaintingStyle.stroke
          ..shader = const LinearGradient(colors: [appGreen, appBlue]).createShader(rect),
      );
    }

    // Draw label (use darker text on light gray spots)
    final Color labelColor = (fillColor == appSpotGray) ? _kDark : Colors.white;
    _drawTextCentered(
      canvas,
      spot.label,
      rect.center,
      fontSize: 14,
      fontWeight: FontWeight.w900,
      color: labelColor,
    );
  }

  void _drawTextCentered(
    Canvas canvas,
    String text,
    Offset center, {
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w700,
    Color color = Colors.white,
  }) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _SpotFinderPainter oldDelegate) {
    return oldDelegate.dashProgress != dashProgress ||
        oldDelegate.travelProgress != travelProgress ||
        oldDelegate.targetSpot != targetSpot ||
        oldDelegate.targetOnRight != targetOnRight ||
        oldDelegate.targetRowIndex != targetRowIndex;
  }
}

class _MapCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MapCircleButton({
    required this.icon,
    required this.onTap,
  });

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
