import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:parking_front/features/main/main_screen.dart';

// ════════════════════════════════════════════════════════════
//  COULEURS LOCALES SPLASH (séparées pour pas polluer AppColors)
// ════════════════════════════════════════════════════════════
class _SplashColors {
  static const gradientStart = Color(0xFF2563EB);
  static const gradientEnd = Color(0xFF60A5FA);
  static const slate400 = Color(0xFF94A3B8);
  static const slate300 = Color(0xFFCBD5E1);

  static const LinearGradient logoGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gradientStart, gradientEnd],
  );
}

// ════════════════════════════════════════════════════════════
//  SPLASH SCREEN — ton code original + navigation ajoutée
// ════════════════════════════════════════════════════════════
class SplashScreen extends StatefulWidget {
  final Widget?
      nextRoute; // <-- On ajoute ce paramètre pour choisir l'écran suivant

  const SplashScreen({super.key, this.nextRoute});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoController;
  late final AnimationController _textController;
  late final AnimationController _barController;
  late final AnimationController _bottomController;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoShadow;

  late final Animation<double> _titleOpacity;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _subtitleOpacity;
  late final Animation<Offset> _subtitleSlide;
  late final Animation<double> _descOpacity;

  late final Animation<double> _bottomOpacity;
  late final Animation<Offset> _bottomSlide;

  late final Animation<double> _barProgress;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startSequence();
  }

  void _setupAnimations() {
    _logoController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(
        CurvedAnimation(parent: _logoController, curve: Curves.elasticOut));
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut)));
    _logoShadow = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.4, 1.0, curve: Curves.easeOut)));

    _textController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _titleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
        parent: _textController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut)));
    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _textController,
            curve: const Interval(0.0, 0.7, curve: Curves.easeOut)));
    _subtitleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: _textController,
            curve: const Interval(0.2, 0.8, curve: Curves.easeOut)));
    _subtitleSlide =
        Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(
            CurvedAnimation(
                parent: _textController,
                curve: const Interval(0.2, 0.8, curve: Curves.easeOut)));
    _descOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
        parent: _textController,
        curve: const Interval(0.5, 1.0, curve: Curves.easeOut)));

    _barController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat();
    _barProgress = Tween<double>(begin: -0.4, end: 1.0).animate(
        CurvedAnimation(parent: _barController, curve: Curves.easeInOut));

    _bottomController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _bottomOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _bottomController, curve: Curves.easeOut));
    _bottomSlide = Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _bottomController, curve: Curves.easeOut));
  }

  Future<void> _startSequence() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _logoController.forward();
    await Future.delayed(const Duration(milliseconds: 500));
    _textController.forward();
    await Future.delayed(const Duration(milliseconds: 400));
    _bottomController.forward();
    await Future.delayed(const Duration(milliseconds: 2800));

    if (mounted) {
      // ✅ Navigation vers l'écran passé en paramètre, sinon MainScreen par défaut
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, animation, __) =>
              widget.nextRoute ?? const MainScreen(),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    _barController.dispose();
    _bottomController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 16),
                Column(children: [
                  _buildLogo(),
                  const SizedBox(height: 48),
                  _buildText(),
                ]),
                _buildBottom(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return AnimatedBuilder(
      animation: _logoController,
      builder: (_, __) => Opacity(
        opacity: _logoOpacity.value,
        child: Transform.scale(
          scale: _logoScale.value,
          child: Container(
            width: 128,
            height: 128,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(40),
              border: Border.all(color: const Color(0xFFF1F5F9), width: 1),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF2563EB)
                        .withOpacity(0.12 * _logoShadow.value),
                    blurRadius: 50,
                    offset: const Offset(0, 20)),
                BoxShadow(
                    color: Colors.black.withOpacity(0.04 * _logoShadow.value),
                    blurRadius: 20,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: const Center(child: _ParkSVGLogo(size: 80)),
          ),
        ),
      ),
    );
  }

  Widget _buildText() {
    return AnimatedBuilder(
      animation: _textController,
      builder: (_, __) => Column(children: [
        FadeTransition(
          opacity: _titleOpacity,
          child: SlideTransition(
            position: _titleSlide,
            child: ShaderMask(
              shaderCallback: (bounds) =>
                  _SplashColors.logoGradient.createShader(bounds),
              blendMode: BlendMode.srcIn,
              child: const Text('SmartPark',
                  style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      height: 1,
                      color: Colors.white)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        FadeTransition(
          opacity: _subtitleOpacity,
          child: SlideTransition(
            position: _subtitleSlide,
            child: const Text('A L G É R I A',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 8,
                    color: _SplashColors.slate400)),
          ),
        ),
        const SizedBox(height: 32),
        FadeTransition(
          opacity: _descOpacity,
          child: const Text('Votre solution de parking intelligent',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, color: _SplashColors.slate400, height: 1.5)),
        ),
      ]),
    );
  }

  Widget _buildBottom() {
    return AnimatedBuilder(
      animation: _bottomController,
      builder: (_, __) => FadeTransition(
        opacity: _bottomOpacity,
        child: SlideTransition(
          position: _bottomSlide,
          child: Column(children: [
            _buildLoadingBar(),
            const SizedBox(height: 48),
            const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.location_on_outlined,
                  size: 16, color: _SplashColors.slate300),
              SizedBox(width: 6),
              Text('ALGER, ALGÉRIE',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 4,
                      color: _SplashColors.slate300)),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _buildLoadingBar() {
    return AnimatedBuilder(
      animation: _barController,
      builder: (_, __) => SizedBox(
        width: 140,
        height: 2,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(1),
          child: Stack(children: [
            Container(color: const Color(0xFFF1F5F9)),
            FractionallySizedBox(
              widthFactor: 0.4,
              child: FractionalTranslation(
                translation: Offset(_barProgress.value * 2.5, 0),
                child: Container(
                    decoration: const BoxDecoration(
                        gradient: _SplashColors.logoGradient)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  LOGO SVG — ton code original inchangé
// ════════════════════════════════════════════════════════════
class _ParkSVGLogo extends StatelessWidget {
  final double size;
  const _ParkSVGLogo({required this.size});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size), painter: _LogoPainter());
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const gradient = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF2563EB), Color(0xFF60A5FA)]);
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.065
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final s = size.width / 100;
    final bodyPath = Path();
    bodyPath.moveTo(30 * s, 35 * s);
    bodyPath.cubicTo(30 * s, 25 * s, 70 * s, 20 * s, 75 * s, 35 * s);
    bodyPath.cubicTo(78 * s, 45 * s, 60 * s, 50 * s, 50 * s, 50 * s);
    bodyPath.cubicTo(35 * s, 50 * s, 22 * s, 55 * s, 25 * s, 70 * s);
    bodyPath.cubicTo(28 * s, 85 * s, 70 * s, 80 * s, 75 * s, 70 * s);
    canvas.drawPath(bodyPath, paint);
    canvas.drawLine(Offset(75 * s, 70 * s), Offset(85 * s, 70 * s), paint);
    canvas.drawLine(Offset(82 * s, 65 * s), Offset(82 * s, 75 * s), paint);
    canvas.drawLine(Offset(88 * s, 65 * s), Offset(88 * s, 75 * s), paint);
    final fillPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(38 * s, 72 * s), 3 * s, fillPaint);
    canvas.drawCircle(Offset(62 * s, 72 * s), 3 * s, fillPaint);
    void drawSquare(double x, double y) =>
        canvas.drawRect(Rect.fromLTWH(x * s, y * s, 2 * s, 2 * s), fillPaint);
    drawSquare(75, 64);
    drawSquare(79, 64);
    drawSquare(75, 74);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
