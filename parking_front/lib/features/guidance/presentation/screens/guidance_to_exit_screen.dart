import 'dart:async';
import 'dart:ui' show Tangent, PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:parking_front/core/widgets/app_feedback.dart';
import 'package:parking_front/features/parking/models/parking.dart';
import 'package:parking_front/features/reservation/data/reservation_repository.dart';
import 'package:parking_front/core/state/selected_spot_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parking_front/core/theme/app_colors.dart';
import 'package:parking_front/features/guidance/presentation/utils/parking_pathfinder.dart';

import 'exit_success_screen.dart';

const _kBg = Color(0xFFF0F4FA);
const _kBlue = Color(0xFF4A90E2);
const _kGreen = Color(0xFF2ECC71);
const _kDark = Color(0xFF1A1A2E);
const _kMid = Color(0xFF8A9BB5);

class GuidanceToExitScreen extends ConsumerStatefulWidget {
  final String spotLabel;
  final bool showMapComingSoon;
  final ParkingIndoorMap? indoorMap;

  const GuidanceToExitScreen({
    super.key,
    this.spotLabel = 'B2',
    this.showMapComingSoon = false,
    this.indoorMap,
  });

  @override
  ConsumerState<GuidanceToExitScreen> createState() => _GuidanceToExitScreenState();
}

class _GuidanceToExitScreenState extends ConsumerState<GuidanceToExitScreen>
  with SingleTickerProviderStateMixin {
  final FlutterTts _tts = FlutterTts();
  final ReservationRepository _reservationRepository = ReservationRepository();

  late final AnimationController _pathController;
  Timer? _timer;

  bool _voiceEnabled = true;
  bool _isCompletingExit = false;
  int _distanceMeters = 70;
  String _instruction = '';
  late String _effectiveSpotLabel;

  String get _normalizedSpotLabel {
    final String source = _effectiveSpotLabel.trim().toUpperCase();
    final Iterable<Match> matches =
        RegExp(r'([AB])\s*-?\s*(\d+)').allMatches(source);
    if (matches.isEmpty) {
      return 'A1';
    }

    final Match match = matches.last;
    final String letter = match.group(1) ?? 'A';
    final int raw = int.tryParse(match.group(2) ?? '1') ?? 1;
    final int normalized = ((raw - 1) % 3) + 1;

    return '$letter$normalized';
  }

  @override
  void initState() {
    super.initState();

    _pathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    );

    final String? global = ref.read(selectedSpotProvider);
    _effectiveSpotLabel = (global != null && global.trim().isNotEmpty)
        ? global.trim()
        : widget.spotLabel;
    ref.read(selectedSpotProvider.notifier).state = _effectiveSpotLabel;

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
      if (!mounted || _distanceMeters <= 0) {
        return;
      }
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
    await _tts.setSpeechRate(0.44);
    await _tts.setVolume(1.0);
    await _tts.setPitch(0.98);
  }

  double get _progress => (70 - _distanceMeters) / 70;

  void _refreshInstruction({bool forceSpeak = false}) {
    final double p = _progress.clamp(0.0, 1.0);
    final String next;

    if (p < 0.4) {
      next = 'Suivez la voie de circulation en direction de la sortie.';
    } else if (p < 0.75) {
      next = 'Continuez sur la voie puis prenez la bifurcation vers la sortie.';
    } else {
      next = 'La sortie se trouve juste devant vous. Avancez prudemment.';
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
    if (_isCompletingExit) {
      return;
    }

    setState(() => _isCompletingExit = true);

    try {
      await _reservationRepository.exitCurrentParkingSession();

      if (!mounted) {
        return;
      }

      HapticFeedback.heavyImpact();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ExitSuccessScreen()),
      );
    } on ReservationException catch (error) {
      if (!mounted) {
        return;
      }
      AppFeedback.showError(context, error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      AppFeedback.showError(context, 'Impossible de terminer la sortie.');
    } finally {
      if (mounted) {
        setState(() => _isCompletingExit = false);
      }
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
                            return CustomPaint(
                              size: const Size(320, 360),
                              painter: _ExitPathPainter(
                                dashProgress: _pathController.value,
                                travelProgress: _progress.clamp(0.0, 1.0),
                                spotLabel: _normalizedSpotLabel,
                                indoorMap: widget.indoorMap,
                              ),
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
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.meeting_room_outlined,
                              color: Colors.white),
                      label: Text(
                        _isCompletingExit ? 'Verification...' : 'Arrive',
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
              Icon(
                Icons.map_outlined,
                size: 52,
                color: _kBlue,
              ),
              SizedBox(height: 12),
              Text(
                'La carte de ce parking sera affichee prochainement.',
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

class _ExitPathPainter extends CustomPainter {
  final double dashProgress;
  final double travelProgress;
  final String spotLabel;
  final ParkingIndoorMap? indoorMap;

  _ExitPathPainter({
    required this.dashProgress,
    required this.travelProgress,
    required this.spotLabel,
    required this.indoorMap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double spotSize = kSpotSize;
    const double spacing = 10;
    const double topPadding = 18;

    // Draw entry/exit at bottom
    _drawEntryExit(canvas, size);

    // Calculate grid positions
    final double totalWidth = (spotSize * 3) + (spacing * 2);
    final double startX = (size.width - totalWidth) / 2;
    final double startY = topPadding;
    final double rowHeight = (spotSize + spacing + 10);

    // Get labels from indoor map or use defaults
    final ({List<String> left, List<String> right}) labels =
        _resolveColumnsFromIndoorMap();
    final Map<String, String> statesByLabel = _resolveStatesFromIndoorMap();
    final List<String> leftLabels = labels.left;
    final List<String> rightLabels = labels.right;

    // Determine target position
    final bool targetOnRight = spotLabel.toUpperCase().startsWith('A');
    final Match? match = RegExp(r'(\d+)').firstMatch(spotLabel);
    final int rawSpotNumber = int.tryParse(match?.group(1) ?? '1') ?? 1;
    final int targetRowIndex = ((rawSpotNumber - 1) % 3);

    // Draw spots in 3x2 grid
    for (int row = 0; row < 2; row++) {
      for (int col = 0; col < 3; col++) {
        final double x = startX + (col * (spotSize + spacing));
        final double y = startY + (row * rowHeight);

        String label = '';
        bool isTarget = false;

        if (row == 0 && col < leftLabels.length) {
          label = leftLabels[col];
          isTarget = !targetOnRight && col == targetRowIndex;
        } else if (row == 1 && col < rightLabels.length) {
          label = rightLabels[col];
          isTarget = targetOnRight && col == targetRowIndex;
        }

        if (label.isNotEmpty) {
          _drawSpot(
            canvas,
            rect: Rect.fromLTWH(x, y, spotSize, spotSize),
            label: label,
            isTarget: isTarget,
            state: statesByLabel[label],
          );
        }
      }
    }

    // Draw path to exit through lanes only (A* around spot obstacles).
    _drawPathToExit(
      canvas,
      size,
      startX,
      startY,
      spotSize,
      spacing,
      targetRowIndex,
      targetOnRight,
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

  void _drawPathToExit(
    Canvas canvas,
    Size size,
    double startX,
    double startY,
    double spotSize,
    double spacing,
    int targetRowIndex,
    bool targetOnRight,
  ) {
    final double targetY = startY + (targetOnRight ? (spotSize + spacing + 10) : 0) + (spotSize / 2);
    final double targetX = startX + (targetRowIndex * (spotSize + spacing)) + (spotSize / 2);
    final double exitCenterX = size.width / 2;
    final double exitCenterY = size.height - 30;

    final List<Rect> obstacles = <Rect>[];
    final double rowHeight = (spotSize + spacing + 10);
    for (int row = 0; row < 2; row++) {
      for (int col = 0; col < 3; col++) {
        final Rect rect = Rect.fromLTWH(
          startX + (col * (spotSize + spacing)),
          startY + (row * rowHeight),
          spotSize,
          spotSize,
        );
        obstacles.add(rect);
      }
    }

    final Offset start = Offset(targetX, targetY);
    final Offset end = Offset(exitCenterX, exitCenterY);
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
      ..lineTo(start.dx, startY - 10)
      ..lineTo(size.width - 12, startY - 10)
      ..lineTo(size.width - 12, end.dy)
      ..lineTo(end.dx, end.dy);

    final Paint pathPaint = Paint()
      ..color = guideRed
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Path path = pathPoints.length >= 2
        ? ParkingPathfinder.pathFromPoints(pathPoints)
        : fallbackPath;

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

    final Tangent? movingTangent = metric.getTangentForOffset(
      metric.length * travelProgress.clamp(0.0, 1.0),
    );
    if (movingTangent != null) {
      canvas.drawCircle(
        movingTangent.position,
        6,
        Paint()..color = guideRed,
      );
      canvas.drawCircle(
        movingTangent.position,
        2.5,
        Paint()..color = Colors.white,
      );
    }

    canvas.drawCircle(
      Offset(exitCenterX, exitCenterY),
      5.5,
      Paint()..color = _kGreen,
    );
  }

  void _drawSpot(
    Canvas canvas, {
    required Rect rect,
    required String label,
    required bool isTarget,
    String? state,
  }) {
    final Color fillColor = isTarget
        ? appBlue
        : switch (state?.trim().toUpperCase()) {
            'AVAILABLE' => appGreen,
            'RESERVED' => appOrange,
            'OCCUPIED' => appRed,
            'OFFLINE' => appSpotGray,
            _ => appSpotGray,
          };

    // subtle outer contour/shadow
    final RRect outer = RRect.fromRectAndRadius(
      rect.inflate(3),
      const Radius.circular(kSpotCornerRadius + 3),
    );
    canvas.drawRRect(outer, Paint()..color = Colors.black.withOpacity(0.04));

    // background fill
    final RRect rrect = RRect.fromRectAndRadius(rect, const Radius.circular(kSpotCornerRadius));
    canvas.drawRRect(rrect, Paint()..color = fillColor);

    // light border contour
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Colors.white.withOpacity(0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // label color: darker text for gray spots
    final Color labelColor = (fillColor == appSpotGray) ? _kDark : Colors.white;
    _drawTextCentered(
      canvas,
      label,
      rect.center,
      fontSize: 12,
      fontWeight: FontWeight.w900,
      color: labelColor,
    );
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

  ({List<String> left, List<String> right}) _resolveColumnsFromIndoorMap() {
    final ParkingIndoorMap? map = indoorMap;
    if (map == null || map.spots.isEmpty) {
      return (
        left: <String>['B1', 'B2', 'B3'],
        right: <String>['A1', 'A2', 'A3'],
      );
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

    final List<int> cols =
        sorted.map((ParkingIndoorSpot s) => s.col).toSet().toList()..sort();
    if (cols.isEmpty) {
      return (
        left: <String>['B1', 'B2', 'B3'],
        right: <String>['A1', 'A2', 'A3'],
      );
    }

    final int leftCol = cols.first;
    final int rightCol = cols.length > 1 ? cols.last : cols.first;

    List<String> labelsForCol(int col, String prefix) {
      final List<String> labels = sorted
          .where((ParkingIndoorSpot s) => s.col == col)
          .take(3)
          .map((ParkingIndoorSpot s) => s.label)
          .toList(growable: true);
      if (labels.isNotEmpty) {
        while (labels.length < 3) {
          labels.add('$prefix${labels.length + 1}');
        }
        return labels;
      }
      return <String>['${prefix}1', '${prefix}2', '${prefix}3'];
    }

    return (
      left: labelsForCol(leftCol, 'B'),
      right: labelsForCol(rightCol, 'A'),
    );
  }

  Map<String, String> _resolveStatesFromIndoorMap() {
    final ParkingIndoorMap? map = indoorMap;
    if (map == null || map.spots.isEmpty) {
      return <String, String>{};
    }

    final Map<String, String> result = <String, String>{};
    for (final ParkingIndoorSpot spot in map.spots) {
      result[spot.label] = spot.state;
    }
    return result;
  }

  @override
  bool shouldRepaint(covariant _ExitPathPainter oldDelegate) {
    return oldDelegate.dashProgress != dashProgress ||
        oldDelegate.travelProgress != travelProgress ||
        oldDelegate.spotLabel != spotLabel;
  }
}
