import 'dart:async';
import 'dart:ui' show Tangent;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'vehicle_parked_confirmation_screen.dart';

const _kBg = Color(0xFFF0F4FA);
const _kBlue = Color(0xFF4A90E2);
const _kGreen = Color(0xFF2ECC71);
const _kOrange = Color(0xFFF5A623);
const _kRed = Color(0xFFE53935);
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

class GuidanceToSpotScreen extends StatefulWidget {
  final String spotLabel;
  final String floor;
  final bool isGuideToFree;

  const GuidanceToSpotScreen({
    super.key,
    this.spotLabel = 'B2',
    this.floor = 'Niveau -1',
    this.isGuideToFree = true,
  });

  @override
  State<GuidanceToSpotScreen> createState() => _GuidanceToSpotScreenState();
}

class _GuidanceToSpotScreenState extends State<GuidanceToSpotScreen>
    with SingleTickerProviderStateMixin {
  final FlutterTts _tts = FlutterTts();
  final List<_ParkingSpot> _leftColumn = const <_ParkingSpot>[
    _ParkingSpot('B1', _SpotState.reserve),
    _ParkingSpot('B2', _SpotState.libre),
    _ParkingSpot('B3', _SpotState.libre),
  ];
  final List<_ParkingSpot> _rightColumn = const <_ParkingSpot>[
    _ParkingSpot('A1', _SpotState.destination),
    _ParkingSpot('A2', _SpotState.occupe),
    _ParkingSpot('A3', _SpotState.occupe),
  ];

  late final AnimationController _pathController;
  Timer? _timer;

  double _scale = 1.0;
  double _lastScale = 1.0;
  bool _voiceEnabled = true;
  int _distanceMeters = 120;
  String _currentInstruction = '';
  late final String _targetSpot;

  bool get _targetOnRight {
    final Match? match = RegExp(r'([AB])').firstMatch(_targetSpot.toUpperCase());
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
    _targetSpot = _resolveTargetSpot();

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
    await _tts.setSpeechRate(0.47);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  String _resolveTargetSpot() {
    if (!widget.isGuideToFree) {
      return _normalizeSpotLabel(widget.spotLabel);
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

  double get _progress => (120 - _distanceMeters) / 120;

  int get _targetRowIndex {
    final Match? match = RegExp(r'(\d+)').firstMatch(_targetSpot);
    final int spotNumber = int.tryParse(match?.group(1) ?? '1') ?? 1;
    final int normalized = ((spotNumber - 1) % 3) + 1;

    return normalized - 1;
  }

  void _updateInstruction({bool forceSpeak = false}) {
    final double p = _progress.clamp(0.0, 1.0);
    final String next;

    if (p < 0.45) {
      next = 'Marchez tout droit sur l\'allee centrale.';
    } else if (p < 0.78) {
      next = _targetOnRight
          ? 'Tournez a droite et continuez encore quelques metres.'
          : 'Tournez a gauche et continuez encore quelques metres.';
    } else {
      next = 'La place $_targetSpot est juste devant vous.';
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
                      color: Colors.black.withValues(alpha: 0.06),
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
                    color: Colors.black.withValues(alpha: 0.05),
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
                          color: _kGreen.withValues(alpha: 0.14),
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
                    '🟢 Libre · 🟠 Réservé · 🔴 Occupé · 🔵 Destination',
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
    final Paint lanePaint = Paint()..color = const Color(0xFFEBF0FA);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.41, 0, size.width * 0.18, size.height),
        const Radius.circular(9),
      ),
      lanePaint,
    );

    const double top = 16;
    const double rowStep = 110;
    const double spotHeight = 86;
    const double leftX = 12;
    final double rightX = size.width * 0.66;
    final double spotWidth = size.width * 0.32;

    for (int i = 0; i < 3; i++) {
      final double y = top + (i * rowStep);
      final _ParkingSpot left = leftSpots[i];
      final _ParkingSpot right = rightSpots[i];

      _drawSpot(
        canvas,
        rect: Rect.fromLTWH(leftX, y, spotWidth, spotHeight),
        spot: left,
      );
      _drawSpot(
        canvas,
        rect: Rect.fromLTWH(rightX, y, spotWidth, spotHeight),
        spot: right,
      );
    }

    final Paint pathPaint = Paint()
      ..color = _kBlue
      ..strokeWidth = 3.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final double startX = size.width * 0.50;
    final double startY = size.height * 0.90;
    final double targetY = (top + (targetRowIndex * rowStep) + (spotHeight / 2));
    final double endX = targetOnRight
        ? (rightX + (spotWidth * 0.18))
        : (leftX + (spotWidth * 0.82));

    final Path path = Path()
      ..moveTo(startX, startY)
      ..lineTo(startX, targetY)
      ..lineTo(endX, targetY);

    final metric = path.computeMetrics().first;
    const double dashLen = 10;
    const double gapLen = 7;
    double distance = dashProgress * (dashLen + gapLen);

    while (distance < metric.length) {
      final double end = (distance + dashLen).clamp(0.0, metric.length);
      canvas.drawPath(metric.extractPath(distance, end), pathPaint);
      distance += dashLen + gapLen;
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
      canvas.drawCircle(destination.position, 6, Paint()..color = _kGreen);
    }

    canvas.drawCircle(
      Offset(startX, startY),
      5,
      Paint()..color = const Color(0xFFE53935),
    );
  }

  void _drawSpot(
    Canvas canvas, {
    required Rect rect,
    required _ParkingSpot spot,
  }) {
    final bool isTarget = spot.label == targetSpot;
    final Color fillColor;

    if (isTarget) {
      fillColor = _kBlue;
    } else {
      switch (spot.state) {
        case _SpotState.libre:
          fillColor = _kGreen;
        case _SpotState.reserve:
          fillColor = _kOrange;
        case _SpotState.occupe:
          fillColor = _kRed;
        case _SpotState.destination:
          fillColor = _kRed;
      }
    }

    final RRect rRect = RRect.fromRectAndRadius(rect, const Radius.circular(12));

    canvas.drawRRect(rRect, Paint()..color = fillColor);

    final TextPainter labelPainter = TextPainter(
      text: TextSpan(
        text: spot.label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    labelPainter.paint(
      canvas,
      Offset(
        rect.center.dx - (labelPainter.width / 2),
        rect.center.dy - (labelPainter.height / 2),
      ),
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
              color: Colors.black.withValues(alpha: 0.1),
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
