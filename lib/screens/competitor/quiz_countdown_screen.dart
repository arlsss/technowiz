import 'package:flutter/material.dart';
import 'technowiz_theme.dart';

/// Standard synchronized countdown screen for Contestants
/// styled with the signature TechNoWiz light-mint circuit background.
class QuizCountdownScreen extends StatelessWidget {
  final int countdown;
  final int questionNumber;
  final int? currentLevel;

  const QuizCountdownScreen({
    super.key,
    required this.countdown,
    this.questionNumber = 1,
    this.currentLevel,
  });

  static const Color primaryGreen = Color(0xFF16A34A);
  static const Color darkGreen = Color(0xFF166534);
  static const Color lightGreen = Color(0xFFF0FDF4);
  static const Color softGreen = Color(0xFFE8F7EC);
  static const Color borderGreen = Color(0xFFDCEFE1);

  @override
  Widget build(BuildContext context) {
    final bool isGo = countdown <= 0;

    return TechCircuitBackground(
      baseColor: lightGreen,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SizedBox.expand(
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double shortestSide =
                    constraints.maxWidth < constraints.maxHeight
                        ? constraints.maxWidth
                        : constraints.maxHeight;
                final double headingSize = (shortestSide * 0.045).clamp(
                  16.0,
                  24.0,
                );
                final double numberSize = (shortestSide * 0.22).clamp(
                  68.0,
                  116.0,
                );

                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 24,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Pill badge with bolt icon
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: const Color(0xFF86EFAC),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.bolt_rounded,
                                size: 18,
                                color: Color(0xFF15803D),
                              ),
                              SizedBox(width: 6),
                              Text(
                                'READY!!',
                                style: TextStyle(
                                  color: Color(0xFF15803D),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: shortestSide * 0.075),
                        // Circular badge with animated countdown number
                        Container(
                          width: (numberSize * 1.5).clamp(130.0, 175.0),
                          height: (numberSize * 1.5).clamp(130.0, 175.0),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF86EFAC),
                              width: 3.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: primaryGreen.withValues(alpha: 0.12),
                                blurRadius: 24,
                                spreadRadius: 2,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 240),
                            transitionBuilder: (child, animation) =>
                                ScaleTransition(
                              scale: CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutBack,
                              ),
                              child: FadeTransition(
                                opacity: animation,
                                child: child,
                              ),
                            ),
                            child: Text(
                              isGo ? 'GO!' : '$countdown',
                              key: ValueKey<int>(countdown),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: darkGreen,
                                fontSize: isGo
                                    ? (headingSize * 2.0)
                                    : (numberSize * 0.85),
                                height: 1.0,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: shortestSide * 0.075),
                        // Clean card with instruction
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFFE2E8F0),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Text(
                            isGo
                                ? (currentLevel != null
                                    ? 'Get ready for Level $currentLevel, Question $questionNumber.'
                                    : 'Get ready for Question $questionNumber.')
                                : (currentLevel != null
                                    ? 'Please get ready for Level $currentLevel, Question $questionNumber.'
                                    : 'Please get ready for Question $questionNumber.'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: darkGreen,
                              fontSize:
                                  (shortestSide * 0.038).clamp(13.0, 16.0),
                              fontWeight: FontWeight.w700,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
