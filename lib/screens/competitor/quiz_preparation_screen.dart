import 'package:flutter/material.dart';

import 'technowiz_theme.dart';

/// TechNoWiz Emerald Arena preparation UI shared by the contestant flow,
/// styled with the signature TechNoWiz light-mint circuit countdown UI.
class QuizPreparationScreen extends StatelessWidget {
  final int currentQuestion;
  final int? currentLevel;

  const QuizPreparationScreen({
    super.key,
    required this.currentQuestion,
    this.currentLevel,
  });

  static const Color primaryGreen = Color(0xFF16A34A);
  static const Color darkGreen = Color(0xFF166534);
  static const Color lightGreen = Color(0xFFF0FDF4);
  static const Color softGreen = Color(0xFFE8F7EC);
  static const Color borderGreen = Color(0xFFDCEFE1);

  @override
  Widget build(BuildContext context) {
    final int questionNumber = (currentQuestion + 1).clamp(1, 999).toInt();

    final String preparationLabel;
    if (currentLevel != null) {
      final int qNum = currentLevel == 1 ? questionNumber : 1;
      preparationLabel = 'GET READY FOR LEVEL $currentLevel • QUESTION $qNum';
    } else {
      preparationLabel = 'GET READY FOR QUESTION $questionNumber';
    }

    final String heading;
    if (currentLevel != null) {
      heading = 'LEVEL $currentLevel IS ABOUT TO START!';
    } else {
      heading = 'QUIZ IS ABOUT TO BEGIN!';
    }

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
                        // Pill badge with bolt icon (matching Countdown Screen)
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
                                'TECHNOWIZ • LIVE QUIZ ARENA',
                                style: TextStyle(
                                  color: Color(0xFF15803D),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: shortestSide * 0.075),
                        // Circular badge with hourglass icon (matching Countdown Screen)
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
                          child: Container(
                            width: (numberSize * 1.05).clamp(88.0, 120.0),
                            height: (numberSize * 1.05).clamp(88.0, 120.0),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0FDF4),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFBBF7D0),
                                width: 1.5,
                              ),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.hourglass_top_rounded,
                                color: primaryGreen,
                                size: 50,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: shortestSide * 0.075),
                        // Heading text
                        Text(
                          heading,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: darkGreen,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Please prepare yourself. Stay focused!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF475569),
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                        SizedBox(height: shortestSide * 0.06),
                        // Clean card with spinner and instruction (matching Countdown Screen)
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
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: primaryGreen,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(
                                  preparationLabel,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: darkGreen,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.3,
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
              },
            ),
          ),
        ),
      ),
    );
  }
}
