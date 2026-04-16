import 'dart:async';
import 'dart:ui' show Tangent;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:parking_front/core/widgets/app_feedback.dart';
import 'package:parking_front/features/reservation/data/reservation_repository.dart';

import 'exit_success_screen.dart';

const _kBg = Color(0xFFF0F4FA);
const _kBlue = Color(0xFF4A90E2);
const _kGreen = Color(0xFF2ECC71);
const _kSpotGray = Color(0xFF98A7BB);
const _kDark = Color(0xFF1A1A2E);
const _kMid = Color(0xFF8A9BB5);

class GuidanceToExitScreen extends StatefulWidget {
  final String spotLabel;
  final bool showMapComingSoon;

  const GuidanceToExitScreen({
    super.key,
    this.spotLabel = 'B2',
    this.showMapComingSoon = false,
  });

  @override
  State<GuidanceToExitScreen> createState() => _GuidanceToExitScreenState();
}

class _GuidanceToExitScreenState extends State<GuidanceToExitScreen>
    with SingleTickerProviderStateMixin {
  final FlutterTts _tts = FlutterTts();
  final ReservationRepository _reservationRepository = ReservationRepository();

  late final AnimationController _pathController;
  Timer? _timer;

  bool _voiceEnabled = true;
  bool _isCompletingExit = false;
  int _distanceMeters = 70;
  String _instruction = '';

  String get _normalizedSpotLabel {
    final String source = widget.spotLabel.trim().toUpperCase();
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
    await _tts.setSpeechRate(0.47);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  double get _progress => (70 - _distanceMeters) / 70;

  void _refreshInstruction({bool forceSpeak = false}) {
    final double p = _progress.clamp(0.0, 1.0);
    final String next;

    if (p < 0.4) {
      next = 'Marchez tout droit vers l\'allee de sortie.';
    } else if (p < 0.75) {
      next = 'Continuez puis tournez legerement a droite.';
    } else {
      next = 'La sortie est en face. Continuez quelques pas.';
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
                            color: Colors.black.withValues(alpha: 0.06),
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
                              size: const Size(280, 360),
                              painter: _ExitPathPainter(
                                dashProgress: _pathController.value,
                                travelProgress: _progress.clamp(0.0, 1.0),
                                spotLabel: _normalizedSpotLabel,
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
                    color: Colors.black.withValues(alpha: 0.05),
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
                          color: _kBlue.withValues(alpha: 0.12),
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
                      '🟢 Votre place · ⚫ Autres places',
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
            color: Colors.black.withValues(alpha: 0.06),
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

  _ExitPathPainter({
    required this.dashProgress,
    required this.travelProgress,
    required this.spotLabel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint lane = Paint()..color = const Color(0xFFEBF0FA);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.4, 0, size.width * 0.2, size.height),
        const Radius.circular(8),
      ),
      lane,
    );

    const double top = 18;
    const double rowStep = 108;
    const double spotHeight = 82;
    final double leftX = size.width * 0.04;
    final double rightX = size.width * 0.66;
    final double spotWidth = size.width * 0.3;

    final bool targetOnRight = spotLabel.toUpperCase().startsWith('A');
    final Match? match = RegExp(r'(\d+)').firstMatch(spotLabel);
    final int rawSpotNumber = int.tryParse(match?.group(1) ?? '1') ?? 1;
    final int targetRowIndex = ((rawSpotNumber - 1) % 3);

    final List<String> leftLabels = <String>['B1', 'B2', 'B3'];
    final List<String> rightLabels = <String>['A1', 'A2', 'A3'];

    for (int i = 0; i < 3; i++) {
      final double y = top + (i * rowStep);
      final Rect leftRect = Rect.fromLTWH(leftX, y, spotWidth, spotHeight);
      final Rect rightRect = Rect.fromLTWH(rightX, y, spotWidth, spotHeight);

      final Color leftColor =
          (!targetOnRight && i == targetRowIndex) ? _kGreen : _kSpotGray;
      final Color rightColor =
          (targetOnRight && i == targetRowIndex) ? _kGreen : _kSpotGray;

      _drawSpot(canvas, leftRect, leftColor, leftLabels[i]);
      _drawSpot(canvas, rightRect, rightColor, rightLabels[i]);
    }

    final Paint exitPaint = Paint()..color = const Color(0xFFD0DCF0);
    final Rect exitRect = Rect.fromLTWH(
      size.width * 0.38,
      size.height * 0.88,
      size.width * 0.24,
      38,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        exitRect,
        const Radius.circular(8),
      ),
      exitPaint,
    );

    final TextPainter exitLabelPainter = TextPainter(
      text: const TextSpan(
        text: 'SORTIE',
        style: TextStyle(
          color: Color(0xFF52627A),
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    exitLabelPainter.paint(
      canvas,
      Offset(
        exitRect.center.dx - (exitLabelPainter.width / 2),
        exitRect.center.dy - (exitLabelPainter.height / 2),
      ),
    );

    final double targetY = top + (targetRowIndex * rowStep) + (spotHeight / 2);
    final double pathStartX = targetOnRight ? rightX : (leftX + spotWidth);
    final double pathStartY = targetY;

    final Path path = Path()
      ..moveTo(pathStartX, pathStartY)
      ..lineTo(size.width * 0.5, pathStartY)
      ..lineTo(size.width * 0.5, size.height * 0.88);

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
      canvas.drawCircle(
        movingTangent.position,
        8,
        Paint()..color = _kBlue,
      );
      canvas.drawCircle(
        movingTangent.position,
        3,
        Paint()..color = Colors.white,
      );
    }

    final Tangent? destination = metric.getTangentForOffset(metric.length);
    if (destination != null) {
      canvas.drawCircle(
        destination.position,
        6,
        Paint()..color = _kGreen,
      );
    }

    canvas.drawCircle(
      Offset(pathStartX, pathStartY),
      5,
      Paint()..color = _kGreen,
    );
  }

  void _drawSpot(Canvas canvas, Rect rect, Color color, String label) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      Paint()..color = color,
    );

    final TextPainter labelPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
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
  bool shouldRepaint(covariant _ExitPathPainter oldDelegate) {
    return oldDelegate.dashProgress != dashProgress ||
        oldDelegate.travelProgress != travelProgress ||
        oldDelegate.spotLabel != spotLabel;
  }
}
