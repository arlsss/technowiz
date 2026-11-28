import 'dart:math' as math;
import 'package:flutter/material.dart';

/// An animated celebratory party popper and confetti overlay that bursts from
/// bottom corners and showers multi-colored confetti, ribbons, and sparkle stars.
class CelebrationPartyPoppers extends StatefulWidget {
  final Duration duration;
  final bool loop;

  const CelebrationPartyPoppers({
    super.key,
    this.duration = const Duration(milliseconds: 4500),
    this.loop = true,
  });

  @override
  State<CelebrationPartyPoppers> createState() => _CelebrationPartyPoppersState();
}

class _CelebrationPartyPoppersState extends State<CelebrationPartyPoppers>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final List<_ConfettiParticle> _particles = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _initParticles();

    if (widget.loop) {
      _controller.repeat();
    } else {
      _controller.forward();
    }
  }

  void _initParticles() {
    _particles.clear();
    const int count = 90;
    for (int i = 0; i < count; i++) {
      _particles.add(_ConfettiParticle.random(_random, i % 2 == 0));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            size: Size.infinite,
            painter: _PartyPopperPainter(
              progress: _controller.value,
              particles: _particles,
            ),
          );
        },
      ),
    );
  }
}

enum _ParticleShape { rectangle, circle, ribbon, star }

class _ConfettiParticle {
  final bool fromLeft;
  final double launchAngle; // radians
  final double launchSpeed;
  final double gravity;
  final double drag;
  final Color color;
  final double size;
  final _ParticleShape shape;
  final double spinSpeed;
  final double flutterSpeed;
  final double delay; // 0.0 to 0.35 stagger
  final double opacityDecayStart;

  _ConfettiParticle({
    required this.fromLeft,
    required this.launchAngle,
    required this.launchSpeed,
    required this.gravity,
    required this.drag,
    required this.color,
    required this.size,
    required this.shape,
    required this.spinSpeed,
    required this.flutterSpeed,
    required this.delay,
    required this.opacityDecayStart,
  });

  factory _ConfettiParticle.random(math.Random random, bool fromLeft) {
    // Left popper fires up-right (-35° to -75°), Right popper fires up-left (-105° to -145°)
    final double angleDeg = fromLeft
        ? -30.0 - random.nextDouble() * 45.0
        : -105.0 - random.nextDouble() * 45.0;
    final double angleRad = angleDeg * math.pi / 180.0;

    const colors = [
      Color(0xFFF59E0B), // Gold
      Color(0xFF10B981), // Emerald
      Color(0xFF8B5CF6), // Purple
      Color(0xFFEC4899), // Pink
      Color(0xFF0EA5E9), // Cyan
      Color(0xFFF97316), // Orange
      Color(0xFFEF4444), // Coral Red
      Color(0xFFEAB308), // Yellow
      Color(0xFF06B6D4), // Teal
      Color(0xFFD946EF), // Magenta
    ];

    final shapeChoice = random.nextDouble();
    final _ParticleShape shape;
    if (shapeChoice < 0.45) {
      shape = _ParticleShape.rectangle;
    } else if (shapeChoice < 0.70) {
      shape = _ParticleShape.ribbon;
    } else if (shapeChoice < 0.85) {
      shape = _ParticleShape.star;
    } else {
      shape = _ParticleShape.circle;
    }

    return _ConfettiParticle(
      fromLeft: fromLeft,
      launchAngle: angleRad,
      launchSpeed: 700.0 + random.nextDouble() * 550.0,
      gravity: 580.0 + random.nextDouble() * 220.0,
      drag: 0.985 + random.nextDouble() * 0.008,
      color: colors[random.nextInt(colors.length)],
      size: 7.0 + random.nextDouble() * 9.0,
      shape: shape,
      spinSpeed: (random.nextDouble() - 0.5) * 14.0,
      flutterSpeed: 4.0 + random.nextDouble() * 8.0,
      delay: random.nextDouble() * 0.28,
      opacityDecayStart: 0.75 + random.nextDouble() * 0.2,
    );
  }
}

class _PartyPopperPainter extends CustomPainter {
  final double progress; // 0.0 to 1.0
  final List<_ConfettiParticle> particles;

  _PartyPopperPainter({
    required this.progress,
    required this.particles,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // Draw bursting party popper icons at bottom corners during initial burst
    _drawPopperIcons(canvas, size);

    final leftOrigin = Offset(size.width * 0.04, size.height * 0.94);
    final rightOrigin = Offset(size.width * 0.96, size.height * 0.94);

    for (final p in particles) {
      if (progress < p.delay) continue;

      final double t = (progress - p.delay) / (1.0 - p.delay);
      if (t <= 0 || t > 1.0) continue;

      // Elapsed time in virtual seconds (~3.5s cycle)
      final double time = t * 3.4;

      // Physics calculation with drag & gravity
      final double effectiveSpeed =
          p.launchSpeed * (1.0 - math.pow(p.drag, time * 60).toDouble()) /
              (1.0 - p.drag) /
              60;
      final double vx = math.cos(p.launchAngle) * effectiveSpeed;
      final double vy =
          math.sin(p.launchAngle) * effectiveSpeed + 0.5 * p.gravity * time * time;

      final Offset origin = p.fromLeft ? leftOrigin : rightOrigin;
      final double x = origin.dx + vx;
      final double y = origin.dy + vy;

      // Offscreen culling
      if (y > size.height + 40 || x < -30 || x > size.width + 30) continue;

      // Opacity calculation with gentle fade near end
      double alpha = 1.0;
      if (t > p.opacityDecayStart) {
        alpha = (1.0 - (t - p.opacityDecayStart) / (1.0 - p.opacityDecayStart))
            .clamp(0.0, 1.0);
      }

      final paint = Paint()
        ..color = p.color.withValues(alpha: alpha)
        ..style = PaintingStyle.fill;

      // Rotation & 3D flutter
      final double rotation = p.spinSpeed * time;
      final double flutter = math.sin(p.flutterSpeed * time);

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);
      canvas.scale(flutter.abs().clamp(0.15, 1.0), 1.0);

      switch (p.shape) {
        case _ParticleShape.rectangle:
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset.zero,
              width: p.size * 1.5,
              height: p.size * 0.7,
            ),
            paint,
          );
          break;
        case _ParticleShape.circle:
          canvas.drawCircle(Offset.zero, p.size * 0.45, paint);
          break;
        case _ParticleShape.ribbon:
          final path = Path()
            ..moveTo(-p.size * 0.8, -p.size * 0.4)
            ..quadraticBezierTo(0, p.size * 0.5, p.size * 0.8, -p.size * 0.3)
            ..lineTo(p.size * 0.7, p.size * 0.3)
            ..quadraticBezierTo(0, -p.size * 0.2, -p.size * 0.7, p.size * 0.4)
            ..close();
          canvas.drawPath(path, paint);
          break;
        case _ParticleShape.star:
          _drawStar(canvas, p.size * 0.7, paint);
          break;
      }

      canvas.restore();
    }
  }

  void _drawStar(Canvas canvas, double radius, Paint paint) {
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final double outerAngle = -math.pi / 2 + i * 4 * math.pi / 5;
      final double x = radius * math.cos(outerAngle);
      final double y = radius * math.sin(outerAngle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawPopperIcons(Canvas canvas, Size size) {
    // Emojis / popper visual effect that pulses during initial burst (progress < 0.45)
    final double burstFade = (1.0 - (progress / 0.5)).clamp(0.0, 1.0);
    if (burstFade <= 0.05) return;

    final double scale = 1.0 + math.sin(progress * math.pi * 3) * 0.25;

    // Left Popper Text (🎉)
    _drawEmojiText(
      canvas,
      '🎉',
      Offset(size.width * 0.04, size.height * 0.91),
      fontSize: 32.0 * scale,
      opacity: burstFade,
      rotation: -0.25,
    );

    // Right Popper Text (🎉 flipped)
    _drawEmojiText(
      canvas,
      '🎉',
      Offset(size.width * 0.96, size.height * 0.91),
      fontSize: 32.0 * scale,
      opacity: burstFade,
      rotation: 0.25,
      flipHorizontal: true,
    );
  }

  void _drawEmojiText(
    Canvas canvas,
    String emoji,
    Offset position, {
    required double fontSize,
    required double opacity,
    double rotation = 0.0,
    bool flipHorizontal = false,
  }) {
    canvas.save();
    canvas.translate(position.dx, position.dy);
    if (flipHorizontal) canvas.scale(-1, 1);
    canvas.rotate(rotation);

    final textPainter = TextPainter(
      text: TextSpan(
        text: emoji,
        style: TextStyle(
          fontSize: fontSize,
          color: Colors.white.withValues(alpha: opacity),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(-textPainter.width / 2, -textPainter.height / 2),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PartyPopperPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
