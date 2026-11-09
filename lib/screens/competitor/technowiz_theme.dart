import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';

/// Shared TechNoWiz Emerald Green Tech-Circuit Background & Brand Widgets
/// for all Contestant screens.
class TechCircuitBackground extends StatelessWidget {
  final Widget child;
  final Color baseColor;
  final bool darkTheme;

  const TechCircuitBackground({
    super.key,
    required this.child,
    this.baseColor = const Color(0xFFF2FBF5),
    this.darkTheme = false,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: darkTheme ? null : baseColor,
        gradient: darkTheme
            ? const LinearGradient(
                colors: [
                  Color(0xFF064E3B),
                  Color(0xFF047857),
                  Color(0xFF15803D),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : LinearGradient(
                colors: [
                  const Color(0xFFF0FDF4),
                  baseColor,
                  const Color(0xFFE6F9ED),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: CustomPaint(
              painter: TechCircuitPainter(darkTheme: darkTheme),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class TechCircuitPainter extends CustomPainter {
  final bool darkTheme;

  const TechCircuitPainter({this.darkTheme = false});

  @override
  void paint(Canvas canvas, Size size) {
    final lineColor = darkTheme
        ? const Color(0x26FFFFFF)
        : const Color(0x1816A34A);
    final nodeColor = darkTheme
        ? const Color(0x40A7F3D0)
        : const Color(0x2816A34A);
    final glowColor = darkTheme
        ? const Color(0x1834D399)
        : const Color(0x1216A34A);

    // Subtle corner tech glow circles
    final glowPaint = Paint()
      ..color = glowColor
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(size.width * 0.9, size.height * 0.08),
      size.shortestSide * 0.32,
      glowPaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.08, size.height * 0.88),
      size.shortestSide * 0.28,
      glowPaint,
    );

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final nodePaint = Paint()
      ..color = nodeColor
      ..style = PaintingStyle.fill;

    final nodeRingPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke;

    void drawTrace(List<Offset> points) {
      if (points.length < 2) return;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(path, linePaint);

      final first = points.first;
      final last = points.last;
      canvas.drawCircle(first, 3.2, nodePaint);
      canvas.drawCircle(last, 3.8, nodePaint);
      canvas.drawCircle(last, 7.0, nodeRingPaint);
    }

    final w = size.width;
    final h = size.height;

    // Top-left circuit traces
    drawTrace([
      Offset(0, h * 0.12),
      Offset(w * 0.14, h * 0.12),
      Offset(w * 0.19, h * 0.17),
      Offset(w * 0.30, h * 0.17),
    ]);
    drawTrace([
      Offset(w * 0.06, 0),
      Offset(w * 0.06, h * 0.07),
      Offset(w * 0.12, h * 0.10),
    ]);

    // Top-right circuit traces
    drawTrace([
      Offset(w, h * 0.16),
      Offset(w * 0.84, h * 0.16),
      Offset(w * 0.78, h * 0.22),
      Offset(w * 0.68, h * 0.22),
    ]);
    drawTrace([
      Offset(w * 0.88, 0),
      Offset(w * 0.88, h * 0.09),
      Offset(w * 0.80, h * 0.13),
    ]);

    // Mid-side subtle traces
    drawTrace([
      Offset(0, h * 0.52),
      Offset(w * 0.08, h * 0.52),
      Offset(w * 0.13, h * 0.47),
      Offset(w * 0.20, h * 0.47),
    ]);
    drawTrace([
      Offset(w, h * 0.58),
      Offset(w * 0.91, h * 0.58),
      Offset(w * 0.86, h * 0.63),
      Offset(w * 0.78, h * 0.63),
    ]);

    // Bottom-left circuit traces
    drawTrace([
      Offset(0, h * 0.84),
      Offset(w * 0.15, h * 0.84),
      Offset(w * 0.21, h * 0.79),
      Offset(w * 0.32, h * 0.79),
    ]);

    // Bottom-right circuit traces
    drawTrace([
      Offset(w, h * 0.88),
      Offset(w * 0.82, h * 0.88),
      Offset(w * 0.76, h * 0.83),
      Offset(w * 0.64, h * 0.83),
    ]);
  }

  @override
  bool shouldRepaint(covariant TechCircuitPainter oldDelegate) {
    return oldDelegate.darkTheme != darkTheme;
  }
}

class TechArenaBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool darkTheme;

  const TechArenaBadge({
    super.key,
    required this.label,
    this.icon = Icons.memory_rounded,
    this.darkTheme = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(
        color: darkTheme
            ? Colors.white.withValues(alpha: 0.14)
            : const Color(0xFFE8FBEF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: darkTheme
              ? Colors.white.withValues(alpha: 0.32)
              : const Color(0xFFBBF7D0),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: darkTheme ? const Color(0xFFFDE047) : const Color(0xFF16A34A),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: darkTheme ? Colors.white : const Color(0xFF14532D),
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 3D TECH RANK TROPHY & BADGE SYSTEM
// Rank 1: 3D Gold Trophy
// Rank 2: 3D Silver Trophy
// Rank 3: 3D Bronze Trophy
// Rank 4-10: 3D Top 10 Badges
// ============================================================================

class TechRankStyle {
  final int rank;
  final IconData icon;
  final Color primaryColor;
  final Color secondaryColor;
  final Color bgColor;
  final Color borderColor;
  final String label;
  final bool isTrophy;
  final bool isBadge;

  const TechRankStyle({
    required this.rank,
    required this.icon,
    required this.primaryColor,
    required this.secondaryColor,
    required this.bgColor,
    required this.borderColor,
    required this.label,
    required this.isTrophy,
    required this.isBadge,
  });

  String? get assetPath {
    if (rank == 1) return 'assets/trophies/gold_trophy_3d.jpg';
    if (rank == 2) return 'assets/trophies/silver_trophy_3d.jpg';
    if (rank == 3) return 'assets/trophies/bronze_trophy_3d.jpg';
    if (rank >= 4 && rank <= 10) return 'assets/trophies/top10_badge_3d.jpg';
    return null;
  }

  static TechRankStyle forRank(int? rank) {
    if (rank == 1) {
      // 3D Gold Trophy (Rank 1)
      return const TechRankStyle(
        rank: 1,
        icon: Icons.emoji_events_rounded,
        primaryColor: Color(0xFFD97706),
        secondaryColor: Color(0xFFF59E0B),
        bgColor: Color(0xFFFFFBEB),
        borderColor: Color(0xFFFCD34D),
        label: "1ST PLACE - GOLD TROPHY",
        isTrophy: true,
        isBadge: false,
      );
    } else if (rank == 2) {
      // 3D Silver Trophy (Rank 2)
      return const TechRankStyle(
        rank: 2,
        icon: Icons.emoji_events_rounded,
        primaryColor: Color(0xFF475569),
        secondaryColor: Color(0xFF94A3B8),
        bgColor: Color(0xFFF8FAFC),
        borderColor: Color(0xFFCBD5E1),
        label: "2ND PLACE - SILVER TROPHY",
        isTrophy: true,
        isBadge: false,
      );
    } else if (rank == 3) {
      // 3D Bronze Trophy (Rank 3)
      return const TechRankStyle(
        rank: 3,
        icon: Icons.emoji_events_rounded,
        primaryColor: Color(0xFFB45309),
        secondaryColor: Color(0xFFD97706),
        bgColor: Color(0xFFFFF7ED),
        borderColor: Color(0xFFFDBA74),
        label: "3RD PLACE - BRONZE TROPHY",
        isTrophy: true,
        isBadge: false,
      );
    } else if (rank != null && rank >= 4 && rank <= 10) {
      // 3D Badges for Top 4 to 10
      return TechRankStyle(
        rank: rank,
        icon: Icons.workspace_premium_rounded,
        primaryColor: const Color(0xFF16A34A),
        secondaryColor: const Color(0xFF22C55E),
        bgColor: const Color(0xFFF0FDF4),
        borderColor: const Color(0xFF86EFAC),
        label: "TOP 10 BADGE - RANK #$rank",
        isTrophy: false,
        isBadge: true,
      );
    } else {
      // Other Participants (Rank > 10)
      return TechRankStyle(
        rank: rank ?? 0,
        icon: Icons.stars_rounded,
        primaryColor: const Color(0xFF14532D),
        secondaryColor: const Color(0xFF16A34A),
        bgColor: const Color(0xFFF0FDF4),
        borderColor: const Color(0xFFD1FAE5),
        label: rank != null ? "RANK #$rank" : "RANKING IN PROGRESS",
        isTrophy: false,
        isBadge: false,
      );
    }
  }
}

/// A prominent 3D Trophy Showcase centerpiece for MyScore and Winners Result
class Tech3DTrophyWidget extends StatelessWidget {
  final int rank;
  final double size;

  const Tech3DTrophyWidget({
    super.key,
    required this.rank,
    this.size = 125,
  });

  @override
  Widget build(BuildContext context) {
    final style = TechRankStyle.forRank(rank);
    final asset = style.assetPath;

    Widget trophyContent;
    if (asset != null) {
      final img = AssetImage(asset);
      img.evict();
      trophyContent = Image(
        key: UniqueKey(),
        image: img,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => CustomPaint(
          size: Size(size, size),
          painter: Tech3DTrophyPainter(rank: rank),
        ),
      );
    } else {
      trophyContent = CustomPaint(
        size: Size(size, size),
        painter: Tech3DTrophyPainter(rank: rank),
      );
    }

    return Container(
      width: size + 20,
      height: size + 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            style.bgColor,
            style.bgColor.withValues(alpha: 0.9),
            style.borderColor.withValues(alpha: 0.4),
          ],
          stops: const [0.4, 0.75, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: style.borderColor.withValues(alpha: 0.45),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(0, 7),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: style.borderColor,
          width: 2.8,
        ),
      ),
      child: Center(
        child: ClipOval(
          child: SizedBox(
            width: size,
            height: size,
            child: trophyContent,
          ),
        ),
      ),
    );
  }
}

/// Compact 3D Trophy & Badge icon for Leaderboard tables and lists
class TechRankLeaderboardIcon extends StatelessWidget {
  final int rank;
  final double size;

  const TechRankLeaderboardIcon({
    super.key,
    required this.rank,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    final style = TechRankStyle.forRank(rank);
    final asset = style.assetPath;

    if (style.isTrophy || style.isBadge) {
      final tooltipMsg = rank == 1
          ? '3D Gold Trophy (1st Place)'
          : rank == 2
          ? '3D Silver Trophy (2nd Place)'
          : rank == 3
          ? '3D Bronze Trophy (3rd Place)'
          : '3D Top 10 Badge (Rank #$rank)';

      Widget graphic;
      if (asset != null) {
        final img = AssetImage(asset);
        img.evict();
        graphic = Image(
          key: UniqueKey(),
          image: img,
          width: size + 4,
          height: size + 4,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => CustomPaint(
            size: Size(size + 4, size + 4),
            painter: Tech3DTrophyPainter(rank: rank),
          ),
        );
      } else {
        graphic = CustomPaint(
          size: Size(size + 4, size + 4),
          painter: Tech3DTrophyPainter(rank: rank),
        );
      }

      return Tooltip(
        message: tooltipMsg,
        child: Container(
          width: size + 8,
          height: size + 8,
          decoration: BoxDecoration(
            color: style.bgColor,
            shape: BoxShape.circle,
            border: Border.all(color: style.borderColor, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: style.borderColor.withValues(alpha: 0.35),
                blurRadius: 4,
                offset: const Offset(0, 1.5),
              ),
            ],
          ),
          child: Center(
            child: ClipOval(
              child: SizedBox(
                width: size + 4,
                height: size + 4,
                child: graphic,
              ),
            ),
          ),
        ),
      );
    }

    if (rank <= 0) {
      return const SizedBox.shrink();
    }

    return Text(
      '$rank',
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        color: Colors.black54,
        fontSize: 12,
      ),
    );
  }
}

/// Fallback custom vector painter for 3D Trophy and Badges
class Tech3DTrophyPainter extends CustomPainter {
  final int rank;

  Tech3DTrophyPainter({required this.rank});

  @override
  void paint(Canvas canvas, Size size) {
    if (rank >= 4 && rank <= 10) {
      _paint3DBadge(canvas, size, rank);
    } else {
      _paint3DTrophy(canvas, size, rank <= 0 ? 1 : rank);
    }
  }

  void _paint3DTrophy(Canvas canvas, Size size, int trophyRank) {
    final w = size.width;
    final h = size.height;

    final List<Color> bodyColors;
    final List<Color> rimColors;
    final Color highlightColor;
    final Color shadowColor;
    final Color baseColorDark;
    final Color baseColorLight;
    final Color plaqueColor;
    final Color plaqueTextColor;

    if (trophyRank == 1) {
      bodyColors = const [
        Color(0xFFFFF59D),
        Color(0xFFFFD54F),
        Color(0xFFFFB300),
        Color(0xFFFF8F00),
        Color(0xFFC47100),
      ];
      rimColors = const [Color(0xFFFFF9C4), Color(0xFFFFB300), Color(0xFFC47100)];
      highlightColor = const Color(0xFFFFFFFF);
      shadowColor = const Color(0xFF8D4F00);
      baseColorDark = const Color(0xFF261C12);
      baseColorLight = const Color(0xFF4E3723);
      plaqueColor = const Color(0xFFFFD54F);
      plaqueTextColor = const Color(0xFF5D3600);
    } else if (trophyRank == 2) {
      bodyColors = const [
        Color(0xFFFFFFFF),
        Color(0xFFE2E8F0),
        Color(0xFFCBD5E1),
        Color(0xFF94A3B8),
        Color(0xFF475569),
      ];
      rimColors = const [Color(0xFFFFFFFF), Color(0xFF94A3B8), Color(0xFF334155)];
      highlightColor = const Color(0xFFFFFFFF);
      shadowColor = const Color(0xFF334155);
      baseColorDark = const Color(0xFF0F172A);
      baseColorLight = const Color(0xFF1E293B);
      plaqueColor = const Color(0xFFE2E8F0);
      plaqueTextColor = const Color(0xFF0F172A);
    } else {
      bodyColors = const [
        Color(0xFFFFE0B2),
        Color(0xFFFFB74D),
        Color(0xFFFB8C00),
        Color(0xFFD84315),
        Color(0xFF8D2B0B),
      ];
      rimColors = const [Color(0xFFFFCC80), Color(0xFFE65100), Color(0xFF6D1B00)];
      highlightColor = const Color(0xFFFFF3E0);
      shadowColor = const Color(0xFF5D1500);
      baseColorDark = const Color(0xFF23100B);
      baseColorLight = const Color(0xFF442016);
      plaqueColor = const Color(0xFFFFB74D);
      plaqueTextColor = const Color(0xFF4E1605);
    }

    final groundShadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.94),
        width: w * 0.65,
        height: h * 0.12,
      ),
      groundShadowPaint,
    );

    final baseTopY = h * 0.77;
    final baseBottomY = h * 0.91;
    final baseWidth = w * 0.50;
    final baseRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(w * 0.5 - baseWidth / 2, baseTopY, w * 0.5 + baseWidth / 2, baseBottomY),
      const Radius.circular(7),
    );

    final basePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [baseColorLight, baseColorDark],
      ).createShader(baseRect.outerRect);
    canvas.drawRRect(baseRect, basePaint);

    final baseTopBevel = Paint()
      ..shader = LinearGradient(
        colors: [bodyColors[0], bodyColors[1], bodyColors[3]],
      ).createShader(Rect.fromLTWH(w * 0.5 - baseWidth / 2, baseTopY - 3, baseWidth, 5));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.5 - baseWidth * 0.46, baseTopY - 2.5, baseWidth * 0.92, 4),
        const Radius.circular(3),
      ),
      baseTopBevel,
    );

    final plaqueRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w * 0.5, (baseTopY + baseBottomY) / 2),
        width: baseWidth * 0.64,
        height: (baseBottomY - baseTopY) * 0.55,
      ),
      const Radius.circular(4),
    );
    final plaquePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [bodyColors[0], plaqueColor, bodyColors[3]],
      ).createShader(plaqueRect.outerRect);
    canvas.drawRRect(plaqueRect, plaquePaint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: '#$trophyRank',
        style: TextStyle(
          color: plaqueTextColor,
          fontSize: (baseBottomY - baseTopY) * 0.38,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(
        w * 0.5 - textPainter.width / 2,
        (baseTopY + baseBottomY) / 2 - textPainter.height / 2,
      ),
    );

    final stemTopY = h * 0.56;
    final stemBottomY = baseTopY;
    final stemWidthTop = w * 0.14;
    final stemWidthBottom = w * 0.20;

    final stemPath = Path()
      ..moveTo(w * 0.5 - stemWidthTop / 2, stemTopY)
      ..lineTo(w * 0.5 + stemWidthTop / 2, stemTopY)
      ..lineTo(w * 0.5 + stemWidthBottom / 2, stemBottomY)
      ..lineTo(w * 0.5 - stemWidthBottom / 2, stemBottomY)
      ..close();

    final stemPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [bodyColors[1], bodyColors[0], bodyColors[2], bodyColors[4]],
        stops: const [0.0, 0.3, 0.65, 1.0],
      ).createShader(stemPath.getBounds());
    canvas.drawPath(stemPath, stemPaint);

    final collarRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w * 0.5, (stemTopY + stemBottomY) / 2),
        width: w * 0.22,
        height: 6,
      ),
      const Radius.circular(3),
    );
    final collarPaint = Paint()
      ..shader = LinearGradient(
        colors: [bodyColors[0], bodyColors[2], bodyColors[4]],
      ).createShader(collarRect.outerRect);
    canvas.drawRRect(collarRect, collarPaint);

    final handlePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.08
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [bodyColors[0], bodyColors[2], bodyColors[4]],
      ).createShader(Rect.fromLTWH(0, h * 0.18, w, h * 0.38));

    final leftHandle = Path()
      ..moveTo(w * 0.30, h * 0.24)
      ..cubicTo(w * 0.03, h * 0.24, w * 0.05, h * 0.50, w * 0.32, h * 0.50);
    canvas.drawPath(leftHandle, handlePaint);

    final rightHandle = Path()
      ..moveTo(w * 0.70, h * 0.24)
      ..cubicTo(w * 0.97, h * 0.24, w * 0.95, h * 0.50, w * 0.68, h * 0.50);
    canvas.drawPath(rightHandle, handlePaint);

    final handleHighlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.025
      ..strokeCap = StrokeCap.round
      ..color = highlightColor.withValues(alpha: 0.85);
    final leftHighlight = Path()
      ..moveTo(w * 0.28, h * 0.23)
      ..cubicTo(w * 0.07, h * 0.23, w * 0.07, h * 0.38, w * 0.12, h * 0.44);
    canvas.drawPath(leftHighlight, handleHighlightPaint);

    final rightHighlight = Path()
      ..moveTo(w * 0.72, h * 0.23)
      ..cubicTo(w * 0.93, h * 0.23, w * 0.93, h * 0.38, w * 0.88, h * 0.44);
    canvas.drawPath(rightHighlight, handleHighlightPaint);

    final cupTopY = h * 0.16;
    final cupBottomY = stemTopY;
    final cupWidth = w * 0.54;

    final cupPath = Path()
      ..moveTo(w * 0.5 - cupWidth / 2, cupTopY)
      ..lineTo(w * 0.5 + cupWidth / 2, cupTopY)
      ..cubicTo(
        w * 0.5 + cupWidth / 2,
        cupBottomY - h * 0.08,
        w * 0.5 + cupWidth * 0.30,
        cupBottomY,
        w * 0.5,
        cupBottomY,
      )
      ..cubicTo(
        w * 0.5 - cupWidth * 0.30,
        cupBottomY,
        w * 0.5 - cupWidth / 2,
        cupBottomY - h * 0.08,
        w * 0.5 - cupWidth / 2,
        cupTopY,
      )
      ..close();

    final cupPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: bodyColors,
        stops: const [0.0, 0.25, 0.55, 0.85, 1.0],
      ).createShader(cupPath.getBounds());
    canvas.drawPath(cupPath, cupPaint);

    final reflectionPath = Path()
      ..moveTo(w * 0.38, cupTopY + 2)
      ..lineTo(w * 0.46, cupTopY + 2)
      ..cubicTo(w * 0.43, cupBottomY - 10, w * 0.42, cupBottomY - 8, w * 0.46, cupBottomY - 2)
      ..lineTo(w * 0.41, cupBottomY - 2)
      ..cubicTo(w * 0.37, cupBottomY - 8, w * 0.35, cupBottomY - 10, w * 0.38, cupTopY + 2)
      ..close();
    final reflectionPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.65),
          Colors.white.withValues(alpha: 0.15),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(cupPath.getBounds());
    canvas.drawPath(reflectionPath, reflectionPaint);

    final rimRect = Rect.fromCenter(
      center: Offset(w * 0.5, cupTopY),
      width: cupWidth,
      height: h * 0.08,
    );

    final interiorPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.0, -0.2),
        radius: 0.8,
        colors: [shadowColor, Color.alphaBlend(Colors.black.withValues(alpha: 0.55), shadowColor)],
      ).createShader(rimRect);
    canvas.drawOval(rimRect, interiorPaint);

    final rimLipPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: rimColors,
      ).createShader(rimRect);
    canvas.drawOval(rimRect, rimLipPaint);

    // 3-Pointed Crown (Coronet) emblem from user reference (NO number 6)
    final crownTopY = cupTopY + (cupBottomY - cupTopY) * 0.28;
    final crownBottomY = cupTopY + (cupBottomY - cupTopY) * 0.58;
    final crownCenterY = (crownTopY + crownBottomY) / 2;

    final crownPath = Path()
      ..moveTo(w * 0.40, crownTopY)
      ..lineTo(w * 0.43, crownBottomY)
      ..lineTo(w * 0.57, crownBottomY)
      ..lineTo(w * 0.60, crownTopY)
      ..lineTo(w * 0.54, crownCenterY)
      ..lineTo(w * 0.50, crownTopY - (crownBottomY - crownTopY) * 0.15)
      ..lineTo(w * 0.46, crownCenterY)
      ..close();

    final crownPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFFFFFFD),
          Color(0xFFFEF3C7),
          Color(0xFFFDE68A),
        ],
      ).createShader(crownPath.getBounds());
    canvas.drawPath(crownPath, crownPaint);

    final pearlPaint = Paint()..color = const Color(0xFFFFFFFD);
    canvas.drawCircle(Offset(w * 0.40, crownTopY), w * 0.024, pearlPaint);
    canvas.drawCircle(Offset(w * 0.50, crownTopY - (crownBottomY - crownTopY) * 0.15), w * 0.026, pearlPaint);
    canvas.drawCircle(Offset(w * 0.60, crownTopY), w * 0.024, pearlPaint);

    final sparkleCenter = Offset(w * 0.5 - cupWidth * 0.42, cupTopY - 2);
    _drawSparkle(canvas, sparkleCenter, w * 0.09, highlightColor);
  }

  void _paint3DBadge(Canvas canvas, Size size, int badgeRank) {
    final w = size.width;
    final h = size.height;

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    canvas.drawCircle(Offset(w * 0.5, h * 0.58), w * 0.36, shadowPaint);

    final ribbonPaintLeft = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF15803D), Color(0xFF166534)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    final ribbonLeft = Path()
      ..moveTo(w * 0.32, h * 0.60)
      ..lineTo(w * 0.22, h * 0.92)
      ..lineTo(w * 0.35, h * 0.85)
      ..lineTo(w * 0.42, h * 0.92)
      ..lineTo(w * 0.42, h * 0.60)
      ..close();
    canvas.drawPath(ribbonLeft, ribbonPaintLeft);

    final ribbonPaintRight = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF16A34A), Color(0xFF15803D)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    final ribbonRight = Path()
      ..moveTo(w * 0.58, h * 0.60)
      ..lineTo(w * 0.58, h * 0.92)
      ..lineTo(w * 0.65, h * 0.85)
      ..lineTo(w * 0.78, h * 0.92)
      ..lineTo(w * 0.68, h * 0.60)
      ..close();
    canvas.drawPath(ribbonRight, ribbonPaintRight);

    final center = Offset(w * 0.5, h * 0.46);
    final outerRadius = w * 0.36;

    final outerRingPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFDE047),
          Color(0xFFCA8A04),
          Color(0xFF16A34A),
          Color(0xFF14532D),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: outerRadius));
    canvas.drawCircle(center, outerRadius, outerRingPaint);

    final innerRadius = outerRadius * 0.86;
    final innerPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF22C55E),
          Color(0xFF16A34A),
          Color(0xFF14532D),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: innerRadius));
    canvas.drawCircle(center, innerRadius, innerPaint);

    final reflexPath = Path()
      ..addArc(
        Rect.fromCircle(center: center, radius: innerRadius * 0.95),
        math.pi * 1.1,
        math.pi * 0.8,
      )
      ..lineTo(center.dx, center.dy);
    final reflexPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white.withValues(alpha: 0.40), Colors.white.withValues(alpha: 0.0)],
      ).createShader(Rect.fromCircle(center: center, radius: innerRadius));
    canvas.drawPath(reflexPath, reflexPaint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: '#$badgeRank',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w900,
          shadows: [
            Shadow(
              color: Color(0x66000000),
              offset: Offset(0, 2.5),
              blurRadius: 4,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2),
    );

    _drawSparkle(canvas, Offset(center.dx + innerRadius * 0.65, center.dy - innerRadius * 0.65), w * 0.08, Colors.white);
  }

  void _drawSparkle(Canvas canvas, Offset center, double radius, Color color) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..cubicTo(center.dx + radius * 0.15, center.dy - radius * 0.15, center.dx + radius * 0.15, center.dy - radius * 0.15, center.dx + radius, center.dy)
      ..cubicTo(center.dx + radius * 0.15, center.dy + radius * 0.15, center.dx + radius * 0.15, center.dy + radius * 0.15, center.dx, center.dy + radius)
      ..cubicTo(center.dx - radius * 0.15, center.dy + radius * 0.15, center.dx - radius * 0.15, center.dy + radius * 0.15, center.dx - radius, center.dy)
      ..cubicTo(center.dx - radius * 0.15, center.dy - radius * 0.15, center.dx - radius * 0.15, center.dy - radius * 0.15, center.dx, center.dy - radius)
      ..close();

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(center, radius * 0.35, glowPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant Tech3DTrophyPainter oldDelegate) {
    return oldDelegate.rank != rank;
  }
}

// ============================================================================
// TOP NOTIFICATION SYSTEM (CONTESTANT POPUPS APPEAR AT THE TOP)
// ============================================================================

/// Shows a modern, top-floating notification banner for Contestants.
/// Replaces bottom snackbars so all messages appear at the top of the screen.
void showTopNotice(
  BuildContext context,
  String message, {
  bool isError = false,
  Duration duration = const Duration(milliseconds: 3200),
}) {
  TopNotificationManager.show(
    context,
    message: message,
    isError: isError,
    duration: duration,
  );
}

/// Convenience method to route existing SnackBar calls to top notifications.
void showTopSnackBar(BuildContext context, SnackBar snackBar) {
  String text = '';
  final content = snackBar.content;
  if (content is Text) {
    text = content.data ?? content.textSpan?.toPlainText() ?? '';
  } else {
    text = content.toString();
  }

  final isError = snackBar.backgroundColor == Colors.red ||
      snackBar.backgroundColor == const Color(0xFFDC2626) ||
      snackBar.backgroundColor == Colors.redAccent ||
      snackBar.backgroundColor == const Color(0xFFB91C1C);

  showTopNotice(
    context,
    text,
    isError: isError,
    duration: snackBar.duration,
  );
}

class TopNotificationManager {
  static OverlayEntry? _activeEntry;
  static Timer? _activeTimer;

  static void show(
    BuildContext context, {
    required String message,
    required bool isError,
    required Duration duration,
  }) {
    // Dismiss any existing top notification immediately
    dismiss();

    final overlay = Overlay.maybeOf(context, rootOverlay: true) ??
        Overlay.maybeOf(context);
    if (overlay == null) {
      final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
      if (scaffoldMessenger != null) {
        final screenHeight = MediaQuery.of(context).size.height;
        scaffoldMessenger.hideCurrentSnackBar();
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: isError ? Colors.red : const Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              bottom: screenHeight > 180 ? screenHeight - 140 : 20,
              left: 16,
              right: 16,
            ),
          ),
        );
      }
      return;
    }

    final entry = OverlayEntry(
      builder: (ctx) => _TopNotificationWidget(
        message: message,
        isError: isError,
        onDismiss: dismiss,
      ),
    );

    _activeEntry = entry;
    overlay.insert(entry);

    _activeTimer = Timer(duration, () {
      dismiss();
    });
  }

  static void dismiss() {
    _activeTimer?.cancel();
    _activeTimer = null;
    if (_activeEntry != null) {
      final entry = _activeEntry!;
      _activeEntry = null;
      if (entry.mounted) {
        entry.remove();
      }
    }
  }
}

class _TopNotificationWidget extends StatefulWidget {
  final String message;
  final bool isError;
  final VoidCallback onDismiss;

  const _TopNotificationWidget({
    required this.message,
    required this.isError,
    required this.onDismiss,
  });

  @override
  State<_TopNotificationWidget> createState() => _TopNotificationWidgetState();
}

class _TopNotificationWidgetState extends State<_TopNotificationWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.6),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _controller.forward();
  }

  Future<void> _handleDismiss() async {
    if (!mounted) return;
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 10,
      left: 16,
      right: 16,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Material(
            color: Colors.transparent,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: GestureDetector(
                  onTap: _handleDismiss,
                  onVerticalDragEnd: (details) {
                    if (details.primaryVelocity != null &&
                        details.primaryVelocity! < 0) {
                      _handleDismiss();
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: widget.isError
                            ? const [Color(0xFF991B1B), Color(0xFFDC2626)]
                            : const [Color(0xFF064E3B), Color(0xFF059669)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: widget.isError
                            ? const Color(0xFFFCA5A5)
                            : const Color(0xFF86EFAC),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (widget.isError
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFF059669))
                              .withValues(alpha: 0.35),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            widget.isError
                                ? Icons.error_outline_rounded
                                : Icons.check_circle_outline_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(
                            widget.message,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: _handleDismiss,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.close_rounded,
                              color: Colors.white.withValues(alpha: 0.8),
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}