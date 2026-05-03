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

import 'vehicle_found_screen.dart';

const _kBg = Color(0xFFF0F4FA);
const _kBlue = Color(0xFF4A90E2);
const _kSpotGray = Color(0xFF98A7BB);
const _kDark = Color(0xFF1A1A2E);
const _kMid = Color(0xFF8A9BB5);
const _kCard = Colors.white;

enum _SlotState {
  libre,
  reserve,
  occupe,
  offline,
}

class _ParkingSlot {
  final String label;
  final _SlotState state;

  const _ParkingSlot(this.label, this.state);
}

class GuidanceToVehicleScreen extends ConsumerStatefulWidget {
  final String spotLabel;
  final String parkingName;
  final String reservationId;
  final int durationMinutes;
  final ParkingIndoorMap? indoorMap;

  const GuidanceToVehicleScreen({
    super.key,
    this.spotLabel = 'B2',
    this.parkingName = 'Notre parking',
    this.reservationId = '',
    this.durationMinutes = 0,
    this.indoorMap,
  });

  @override
    ConsumerState<GuidanceToVehicleScreen> createState() =>
      _GuidanceToVehicleScreenState();
}

class _GuidanceToVehicleScreenState extends ConsumerState<GuidanceToVehicleScreen>
  with SingleTickerProviderStateMixin {
  final FlutterTts _tts = FlutterTts();
  late List<_ParkingSlot> _leftColumn;
  late List<_ParkingSlot> _rightColumn;

  late final AnimationController _pathController;
  Timer? _timer;

  bool _voiceEnabled = true;
  double _scale = 1.0;
  double _lastScale = 1.0;
  Offset _panOffset = Offset.zero;
  Offset _lastFocalPoint = Offset.zero;
  int _distanceMeters = 90;
  String _instruction = '';
  late String _resolvedTargetLabel;
  late bool _resolvedTargetOnRight;
  late int _resolvedTargetRowIndex;
  late String _requestedSpotLabel;

  Match? get _spotMatch {
    final Iterable<Match> matches =
        RegExp(r'([A-Z])(\d+)').allMatches(_requestedSpotLabel.toUpperCase());
    if (matches.isEmpty) {
      return null;
    }

    return matches.last;
  }

  String get _targetLetter => _spotMatch?.group(1) ?? 'B';

  int get _targetNumber => int.tryParse(_spotMatch?.group(2) ?? '2') ?? 2;

  bool get _targetOnRight {
    final String letter = _targetLetter;
    return letter == 'A';
  }

  int get _targetRowIndex {
    final int normalized = ((_targetNumber - 1) % 3) + 1;

    return normalized - 1;
  }

  String get _mappedTargetLabel => _resolvedTargetLabel;

  bool get _computedTargetOnRight => _resolvedTargetOnRight;

  int get _computedTargetRowIndex => _resolvedTargetRowIndex;

  @override
  void initState() {
    super.initState();

    final String? global = ref.read(selectedSpotProvider);
    _requestedSpotLabel = (global != null && global.trim().isNotEmpty)
        ? global.trim()
        : widget.spotLabel;

    _initializeMapFromIndoorData();
    ref.read(selectedSpotProvider.notifier).state = _resolvedTargetLabel;

    _pathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _configureVoice();
    _setInstruction(forceSpeak: true);

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _distanceMeters <= 0) {
        return;
      }

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
    await _tts.setSpeechRate(0.44);
    await _tts.setVolume(1.0);
    await _tts.setPitch(0.98);
  }

  double get _progress => (90 - _distanceMeters) / 90;

  void _setInstruction({bool forceSpeak = false}) {
    final double p = _progress.clamp(0.0, 1.0);
    final String next;

    if (p < 0.35) {
      next =
          'Suivez l\'allee principale en restant sur la voie de circulation.';
    } else if (p < 0.72) {
      next = _computedTargetOnRight
          ? 'A l\'intersection suivante, tournez a droite puis continuez sur la voie.'
          : 'A l\'intersection suivante, tournez a gauche puis continuez sur la voie.';
    } else {
      next =
          'Votre vehicule se trouve a proximite immediate de la place $_mappedTargetLabel.';
    }

    if (forceSpeak || next != _instruction) {
      _instruction = next;
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
          spotLabel: _mappedTargetLabel,
          reservationId: widget.reservationId,
          parkingName: widget.parkingName,
          dureeMinutes:
              widget.durationMinutes <= 0 ? 1 : widget.durationMinutes,
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

  void _initializeMapFromIndoorData() {
    const List<_ParkingSlot> fallbackTop = <_ParkingSlot>[
      _ParkingSlot('P01', _SlotState.occupe),
      _ParkingSlot('P03', _SlotState.libre),
      _ParkingSlot('P04', _SlotState.libre),
    ];
    const List<_ParkingSlot> fallbackBottom = <_ParkingSlot>[
      _ParkingSlot('P06', _SlotState.occupe),
      _ParkingSlot('B3', _SlotState.libre),
      _ParkingSlot('A3', _SlotState.libre),
    ];

    final ParkingIndoorMap? map = widget.indoorMap;
    if (map == null || map.spots.isEmpty) {
      _leftColumn = fallbackTop;
      _rightColumn = fallbackBottom;
      _resolvedTargetOnRight = _targetOnRight;
      _resolvedTargetRowIndex = _targetRowIndex > 1 ? 1 : 0;
      _resolvedTargetLabel = _requestedSpotLabel;
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
      _resolvedTargetOnRight = _targetOnRight;
      _resolvedTargetRowIndex = _targetRowIndex > 1 ? 1 : 0;
      _resolvedTargetLabel = _requestedSpotLabel;
      return;
    }

    final int topRowValue = rows.first;
    final int bottomRowValue = rows.length > 1 ? rows.last : rows.first;

    List<_ParkingSlot> toSlotsForRow(int row) {
      final List<ParkingIndoorSpot> spots = sorted
          .where((ParkingIndoorSpot spot) => spot.row == row)
          .take(3)
          .toList(growable: false);
      return spots
          .map((ParkingIndoorSpot spot) =>
              _ParkingSlot(spot.label, _slotStateFromApi(spot.state)))
          .toList(growable: false);
    }

    _leftColumn = toSlotsForRow(topRowValue);
    _rightColumn = toSlotsForRow(bottomRowValue);

    if (_leftColumn.isEmpty && _rightColumn.isEmpty) {
      _leftColumn = fallbackTop;
      _rightColumn = fallbackBottom;
    } else {
      if (_leftColumn.isEmpty) {
        _leftColumn = fallbackTop;
      }
      if (_rightColumn.isEmpty) {
        _rightColumn = fallbackBottom;
      }
    }

    final String normalizedTarget = _normalizeLabel(_requestedSpotLabel);
    _ParkingSlot? exact;
    for (final _ParkingSlot slot in <_ParkingSlot>[..._leftColumn, ..._rightColumn]) {
      if (_normalizeLabel(slot.label) == normalizedTarget) {
        exact = slot;
        break;
      }
    }

    _resolvedTargetLabel = exact?.label ?? _requestedSpotLabel;

    final int rightIndex =
        _rightColumn.indexWhere((_) => _.label == _resolvedTargetLabel);
    if (rightIndex >= 0) {
      _resolvedTargetOnRight = true;
      _resolvedTargetRowIndex = rightIndex.clamp(0, 2);
      return;
    }

    final int leftIndex =
        _leftColumn.indexWhere((_) => _.label == _resolvedTargetLabel);
    _resolvedTargetOnRight = false;
    _resolvedTargetRowIndex =
        (leftIndex >= 0 ? leftIndex : (_targetRowIndex > 1 ? 1 : 0)).clamp(0, 2);
  }

  _SlotState _slotStateFromApi(String rawState) {
    switch (rawState.trim().toUpperCase()) {
      case 'AVAILABLE':
        return _SlotState.libre;
      case 'RESERVED':
        return _SlotState.reserve;
      case 'OFFLINE':
        return _SlotState.offline;
      default:
        return _SlotState.occupe;
    }
  }

  String _normalizeLabel(String raw) {
    return raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  Widget _slotCard(_ParkingSlot slot) {
    final bool isTarget = slot.label == _mappedTargetLabel;
    final Color fillColor;

    if (isTarget) {
      fillColor = appBlue;
    } else {
      switch (slot.state) {
        case _SlotState.libre:
          fillColor = appGreen;
        case _SlotState.reserve:
          fillColor = appOrange;
        case _SlotState.occupe:
          fillColor = appRed;
        case _SlotState.offline:
          fillColor = appSpotGray;
      }
    }

    return Container(
      width: kSpotSize,
      height: kSpotSize,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(kSpotCornerRadius),
        border: (!isTarget && slot.state == _SlotState.libre)
            ? Border.all(color: Colors.white.withOpacity(0.08), width: 1.2)
            : null,
        boxShadow: isTarget
            ? <BoxShadow>[
                BoxShadow(
                  color: appBlue.withOpacity(0.30),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ]
            : <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.directions_car_rounded,
            size: 28,
            color: (fillColor == appSpotGray) ? _kMid : Colors.white,
          ),
          const SizedBox(height: 6),
          Text(
            slot.label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: (fillColor == appSpotGray) ? _kMid : Colors.white,
            ),
          ),
        ],
      ),
    );
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
                        final Offset delta =
                            details.focalPoint - _lastFocalPoint;
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
                              child: SizedBox(
                                width: 352,
                                height: 316,
                                child: Stack(
                                  children: <Widget>[
                                    Positioned.fill(
                                      child: AnimatedBuilder(
                                        animation: _pathController,
                                        builder: (_, __) {
                                          return CustomPaint(
                                            size: const Size(352, 316),
                                            painter: _VehicleLanePainter(
                                              dashProgress:
                                                  _pathController.value,
                                              travelProgress:
                                                  _progress.clamp(0.0, 1.0),
                                              targetOnRight:
                                                  _computedTargetOnRight,
                                              targetRowIndex:
                                                  _computedTargetRowIndex,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    Positioned(
                                      left: 14,
                                      right: 14,
                                      top: 18,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: _leftColumn
                                            .map<Widget>(_slotCard)
                                            .toList(growable: false),
                                      ),
                                    ),
                                    Positioned(
                                      left: 14,
                                      right: 14,
                                      top: 144,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: _rightColumn
                                            .map<Widget>(_slotCard)
                                            .toList(growable: false),
                                      ),
                                    ),
                                  ],
                                ),
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
                        child: const Icon(Icons.directions_walk_rounded,
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      _InfoChip(label: 'Distance: $_distanceMeters m'),
                      _InfoChip(label: 'Place: $_mappedTargetLabel'),
                      _InfoChip(label: widget.parkingName),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '🟢 Libre · 🟠 Réservé · 🔴 Occupé · 🔵 Destination · ⚫ Hors service',
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
                            'Arrive',
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

class _VehicleLanePainter extends CustomPainter {
  final double dashProgress;
  final double travelProgress;
  final bool targetOnRight;
  final int targetRowIndex;

  _VehicleLanePainter({
    required this.dashProgress,
    required this.travelProgress,
    required this.targetOnRight,
    required this.targetRowIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawEntryExit(canvas, size);

    const double spotSize = kSpotSize;
    const double rowGap = 38;
    const double topY = 18;
    final double bottomY = topY + spotSize + rowGap;
    const double horizontalPadding = 14;
    final double rowWidth = size.width - (horizontalPadding * 2);
    final double spacing = (rowWidth - (spotSize * 3)) / 2;

    final List<Rect> obstacles = <Rect>[];
    final List<List<Rect>> gridRects = <List<Rect>>[<Rect>[], <Rect>[]];

    for (int col = 0; col < 3; col++) {
      final double x = horizontalPadding + (col * (spotSize + spacing));
      final Rect topRect = Rect.fromLTWH(x, topY, spotSize, spotSize);
      final Rect bottomRect = Rect.fromLTWH(x, bottomY, spotSize, spotSize);
      gridRects[0].add(topRect);
      gridRects[1].add(bottomRect);
      obstacles.add(topRect);
      obstacles.add(bottomRect);
    }

    final int row = targetOnRight ? 1 : 0;
    final int col = targetRowIndex.clamp(0, 2);
    final Rect targetRect = gridRects[row][col];
    final Offset start = Offset(size.width / 2, size.height - 18);
    final Offset end = Offset(
      targetOnRight ? targetRect.right + 4 : targetRect.left - 4,
      targetRect.center.dy,
    );

    final List<Offset> pathPoints = ParkingPathfinder.findPath(
      canvasSize: size,
      start: start,
      end: end,
      obstacles: obstacles,
      cellSize: 8,
      obstaclePadding: 2,
    );

    final Path fallbackPath = Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(start.dx, topY - 10)
      ..lineTo(targetOnRight ? size.width - 12 : 12, topY - 10)
      ..lineTo(targetOnRight ? size.width - 12 : 12, end.dy)
      ..lineTo(end.dx, end.dy);

    final Path path = pathPoints.length >= 2
        ? ParkingPathfinder.pathFromPoints(pathPoints)
        : fallbackPath;

    _drawDashedPath(canvas, path);
    _drawMovingIndicator(canvas, path);
    _drawDestinationMarker(
      canvas,
      end,
    );
  }

  void _drawEntryExit(Canvas canvas, Size size) {
    const double bottomMargin = 14;
    const double height = 32;
    const double width = 90;

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

  void _drawDashedPath(Canvas canvas, Path path) {
    final Paint pathPaint = Paint()
      ..color = guideRed
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(
      path,
      Paint()
        ..color = guideRed.withOpacity(0.50)
        ..strokeWidth = 3.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final Iterable<PathMetric> metrics = path.computeMetrics();
    if (metrics.isEmpty) {
      return;
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
  }

  void _drawTextCentered(
    Canvas canvas,
    String text,
    Offset center, {
    double fontSize = 12,
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
          letterSpacing: 0.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  void _drawMovingIndicator(Canvas canvas, Path path) {
    final Iterable<PathMetric> metrics = path.computeMetrics();
    if (metrics.isEmpty) {
      return;
    }
    final PathMetric metric = metrics.first;
    final Tangent? movingTangent = metric.getTangentForOffset(
      metric.length * travelProgress.clamp(0.0, 1.0),
    );

    if (movingTangent != null) {
      canvas.drawCircle(
        movingTangent.position,
        7,
        Paint()..color = guideRed,
      );
      canvas.drawCircle(
        movingTangent.position,
        2.5,
        Paint()..color = Colors.white,
      );
    }
  }

  void _drawDestinationMarker(Canvas canvas, Offset position) {
    canvas.drawCircle(
      position,
      6.5,
      Paint()
        ..color = appBlue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(
      position,
      4,
      Paint()..color = appBlue,
    );
  }

  @override
  bool shouldRepaint(covariant _VehicleLanePainter oldDelegate) {
    return oldDelegate.dashProgress != dashProgress ||
        oldDelegate.travelProgress != travelProgress ||
        oldDelegate.targetOnRight != targetOnRight ||
        oldDelegate.targetRowIndex != targetRowIndex;
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
