import 'dart:async';
import 'dart:ui' show Tangent;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'vehicle_found_screen.dart';

const _kBg = Color(0xFFF0F4FA);
const _kBlue = Color(0xFF4A90E2);
const _kGreen = Color(0xFF2ECC71);
const _kSpotGray = Color(0xFF98A7BB);
const _kDark = Color(0xFF1A1A2E);
const _kMid = Color(0xFF8A9BB5);
const _kCard = Colors.white;

enum _SlotState {
  libre,
  occupe,
}

class _ParkingSlot {
  final String label;
  final _SlotState state;

  const _ParkingSlot(this.label, this.state);
}

class GuidanceToVehicleScreen extends StatefulWidget {
  final String spotLabel;
  final String parkingName;
  final String reservationId;
  final int durationMinutes;

  const GuidanceToVehicleScreen({
    super.key,
    this.spotLabel = 'B2',
    this.parkingName = 'Notre parking',
    this.reservationId = '',
    this.durationMinutes = 0,
  });

  @override
  State<GuidanceToVehicleScreen> createState() =>
      _GuidanceToVehicleScreenState();
}

class _GuidanceToVehicleScreenState extends State<GuidanceToVehicleScreen>
    with SingleTickerProviderStateMixin {
  final FlutterTts _tts = FlutterTts();
  final List<_ParkingSlot> _leftColumn = const <_ParkingSlot>[
    _ParkingSlot('B1', _SlotState.occupe),
    _ParkingSlot('B2', _SlotState.libre),
    _ParkingSlot('B3', _SlotState.libre),
  ];
  final List<_ParkingSlot> _rightColumn = const <_ParkingSlot>[
    _ParkingSlot('A1', _SlotState.occupe),
    _ParkingSlot('A2', _SlotState.occupe),
    _ParkingSlot('A3', _SlotState.occupe),
  ];

  late final AnimationController _pathController;
  Timer? _timer;

  bool _voiceEnabled = true;
  double _scale = 1.0;
  double _lastScale = 1.0;
  Offset _panOffset = Offset.zero;
  Offset _lastFocalPoint = Offset.zero;
  int _distanceMeters = 90;
  String _instruction = '';

  Match? get _spotMatch {
    final Iterable<Match> matches =
        RegExp(r'([A-Z])(\d+)').allMatches(widget.spotLabel.toUpperCase());
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

  String get _mappedTargetLabel =>
      '${_targetOnRight ? 'A' : 'B'}${_targetRowIndex + 1}';

  @override
  void initState() {
    super.initState();

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
    await _tts.setSpeechRate(0.47);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  double get _progress => (90 - _distanceMeters) / 90;

  void _setInstruction({bool forceSpeak = false}) {
    final double p = _progress.clamp(0.0, 1.0);
    final String next;

    if (p < 0.35) {
      next = 'Marchez tout droit sur l\'allee principale.';
    } else if (p < 0.72) {
      next = _targetOnRight
          ? 'Tournez a droite, puis avancez quelques pas.'
          : 'Tournez a gauche, puis avancez quelques pas.';
    } else {
      next = 'Votre voiture est proche de la place $_mappedTargetLabel.';
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
          spotLabel: widget.spotLabel,
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

  Widget _slotCard(_ParkingSlot slot) {
    final bool isTarget = slot.label == _mappedTargetLabel;
    final Color fillColor;
    final bool isFreeSlot = !isTarget && slot.state == _SlotState.libre;

    if (isTarget) {
      fillColor = _kGreen;
    } else {
      switch (slot.state) {
        case _SlotState.libre:
          fillColor = Colors.white;
        case _SlotState.occupe:
          fillColor = _kSpotGray;
      }
    }

    return Container(
      width: 96,
      height: 96,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(15),
        border: (!isTarget && slot.state == _SlotState.libre)
            ? Border.all(color: const Color(0xFFD0DCF0), width: 1.2)
            : null,
        boxShadow: isTarget
            ? <BoxShadow>[
                BoxShadow(
                  color: _kGreen.withOpacity(0.30),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.directions_car_rounded,
            size: 28,
            color: isFreeSlot ? _kMid : Colors.white,
          ),
          const SizedBox(height: 6),
          Text(
            slot.label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: isFreeSlot ? _kMid : Colors.white,
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
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 20,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Column(
                                      children: _leftColumn
                                          .map<Widget>(_slotCard)
                                          .toList(growable: false),
                                    ),
                                    SizedBox(
                                      width: 74,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: <Widget>[
                                          Container(
                                            width: 52,
                                            height: 340,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEBF0FA),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          AnimatedBuilder(
                                            animation: _pathController,
                                            builder: (_, __) {
                                              return CustomPaint(
                                                size: const Size(74, 340),
                                                painter: _VehicleLanePainter(
                                                  dashProgress:
                                                      _pathController.value,
                                                  travelProgress:
                                                      _progress.clamp(0.0, 1.0),
                                                  targetOnRight: _targetOnRight,
                                                  targetRowIndex:
                                                      _targetRowIndex,
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      children: _rightColumn
                                          .map<Widget>(_slotCard)
                                          .toList(growable: false),
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
                    '🟢 Votre voiture · ⚪ Libre · ⚫ Occupé',
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
    final Paint lane = Paint()..color = const Color(0xFFEBF0FA);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.15, 0, size.width * 0.70, size.height),
        const Radius.circular(8),
      ),
      lane,
    );

    final double startX = size.width / 2;
    final double startY = size.height * 0.90;
    final double targetY = 49 + (targetRowIndex * 110);
    final double endX = targetOnRight ? size.width * 0.95 : size.width * 0.05;

    final Path path = Path()
      ..moveTo(startX, startY)
      ..lineTo(startX, targetY)
      ..lineTo(endX, targetY);

    final Paint pathPaint = Paint()
      ..color = _kBlue
      ..strokeWidth = 3.3
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

    canvas.drawCircle(
      Offset(startX, startY),
      5,
      Paint()..color = _kGreen,
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
