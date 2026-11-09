import 'package:flutter/material.dart';

import 'technowiz_theme.dart';

/// TechNoWiz Emerald Arena preparation UI shared by the contestant flow.
class QuizPreparationScreen extends StatelessWidget {
  final int currentQuestion;
  final int? currentLevel;

  const QuizPreparationScreen({
    super.key,
    required this.currentQuestion,
    this.currentLevel,
  });

  static const Color primaryGreen = Color(0xFF16A34A);

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

    return Scaffold(
      backgroundColor: primaryGreen,
      body: TechCircuitBackground(
        darkTheme: true,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const TechArenaBadge(
                        label: 'TECHNOWIZ • LIVE QUIZ ARENA',
                        icon: Icons.bolt_rounded,
                        darkTheme: true,
                      ),
                      const SizedBox(height: 26),
                      Container(
                        width: 122,
                        height: 122,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.24),
                            width: 1.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF4ADE80).withValues(alpha: 0.25),
                              blurRadius: 28,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFFFDE047).withValues(alpha: 0.65),
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.hourglass_top_rounded,
                            color: Colors.white,
                            size: 52,
                          ),
                        ),
                      ),
                      const SizedBox(height: 26),
                      Text(
                        heading,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
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
                          color: Color(0xFFD1FAE5),
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 20,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.38),
                            width: 1.4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Color(0xFFFDE047),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                preparationLabel,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
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
        ),
      ),
    );
  }
}
