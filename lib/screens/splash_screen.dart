import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'login_screen.dart';
import 'admin/admin_dashboard.dart';
import 'quizmaster/quizmaster_dashboard.dart';
import 'quizmaster/quiz_sessions_screen.dart';
import 'quizmaster/quiz_control_screen.dart';
import 'quizmaster/leaderboard_screen.dart';
import 'quizmaster/final_ranking_screen.dart';
import 'quizmaster/manage_participants_screen.dart';
import 'quizmaster/profile_screen.dart';
import 'quizmaster/contestant_readiness_page.dart';
import 'quizmaster/submitted_answers_screen.dart';
import 'competitor/competitor_dashboard.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    debugPrint('🔥 SPLASH SCREEN IS RUNNING');
    // Resolve the signed-in user's destination immediately. Avoid a fixed
    // splash delay and avoid showing the dashboard before restoring a saved page.
    checkLoginStatus();
  }

  /// Restore the last Quiz Master destination directly after a browser refresh.
  /// These keys match the values saved by the Quiz Master screens.
  Future<void> _restoreQuizMasterDestination() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    const lastPageKey = 'technowiz_quizmaster_last_page';
    const quizCodeKey = 'technowiz_quizmaster_current_quiz_code';

    final savedPage = prefs.getString(lastPageKey);
    final quizCode = (prefs.getString(quizCodeKey) ?? '').trim();

    Widget destination = const QuizMasterDashboard();

    switch (savedPage) {
      case 'dashboard':
      case null:
      case '':
        destination = const QuizMasterDashboard();
        break;
      case 'profile':
        destination = const QuizMasterProfileScreen();
        break;
      case 'quiz_sessions':
        destination = const QuizSessionsScreen();
        break;
      case 'leaderboard':
      case 'leaderboard_history':
        final String savedLevel =
            prefs.getString('technowiz_quizmaster_leaderboard_level') ??
            'Level 1';
        destination = LeaderboardScreen(
          quizCode: quizCode,
          initialShowHistory: savedPage == 'leaderboard_history',
          initialLevel: savedLevel,
        );
        break;
      case 'participants':
      case 'contestant':
      case 'participants_history':
        destination = ManageParticipantsScreen(
          quizCode: quizCode,
          initialShowHistory: savedPage == 'participants_history',
        );
        break;
      case 'submitted_answers':
        if (quizCode.isNotEmpty) {
          final int? qIndex =
              prefs.getInt('technowiz_quizmaster_submitted_question_index');
          destination = SubmittedAnswersScreen(
            quizCode: quizCode,
            questionIndex: qIndex,
          );
        } else {
          destination = const QuizSessionsScreen();
        }
        break;
      case 'ranking':
      case 'final_ranking':
        if (quizCode.isNotEmpty) {
          final int savedLevel =
              prefs.getInt('technowiz_quizmaster_ranking_level') ?? 1;
          final bool isFinal =
              prefs.getBool('technowiz_quizmaster_ranking_is_final') ?? true;
          destination = FinalRankingScreen(
            quizCode: quizCode,
            level: savedLevel,
            isFinal: isFinal,
          );
        } else {
          destination = const QuizSessionsScreen();
        }
        break;
      case 'participant_readiness':
      case 'contestant_readiness':
      case 'quizmaster_overview':
        if (quizCode.isNotEmpty) {
          final int savedLevel =
              prefs.getInt('technowiz_quizmaster_readiness_level') ?? 1;
          destination = ContestantReadinessPage(
            quizCode: quizCode,
            startLevel: savedLevel,
            onStartQuiz: () async {
              if (!mounted) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => QuizControlScreen(quizCode: quizCode),
                ),
              );
            },
            onReturnToSessions: () async {
              if (!mounted) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const QuizSessionsScreen()),
              );
            },
          );
        } else {
          destination = const QuizSessionsScreen();
        }
        break;
      case 'quiz_control':
        if (quizCode.isNotEmpty) {
          destination = QuizControlScreen(quizCode: quizCode);
        } else {
          destination = const QuizSessionsScreen();
        }
        break;
      default:
        destination = const QuizMasterDashboard();
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => destination,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        transitionsBuilder: (_, animation, secondaryAnimation, child) => child,
      ),
    );
  }

  Future<void> checkLoginStatus() async {
    if (!mounted) return;

    final User? user = FirebaseAuth.instance.currentUser;

    debugPrint('======================================');
    debugPrint('SPLASH LOGIN CHECK');
    debugPrint('USER UID: ${user?.uid}');
    debugPrint('USER EMAIL: ${user?.email}');
    debugPrint('USER NULL: ${user == null}');
    debugPrint('======================================');

    if (user == null) {
      debugPrint('NO USER → LOGIN SCREEN');
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }

    try {
      debugPrint('USER EXISTS → GETTING FIRESTORE ROLE');
      final DocumentSnapshot<Map<String, dynamic>> userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

      if (!mounted) return;

      if (!userDoc.exists) {
        debugPrint('USER DOCUMENT NOT FOUND');
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
        return;
      }

      final Map<String, dynamic> data = userDoc.data() ?? {};
      final String role = data['role']?.toString() ?? '';
      debugPrint('USER ROLE: $role');

      if (role == 'Admin') {
        debugPrint('→ ADMIN DASHBOARD');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminDashboard()),
        );
        return;
      }

      if (role == 'Quiz Master') {
        debugPrint('→ RESTORING QUIZ MASTER DESTINATION');
        await _restoreQuizMasterDestination();
        return;
      }

      if (role == 'Contestant') {
        debugPrint('→ CONTESTANT DASHBOARD');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const CompetitorDashboard()),
        );
        return;
      }

      debugPrint('UNKNOWN ROLE: $role');
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } catch (e) {
      debugPrint('======================================');
      debugPrint('SPLASH ERROR');
      debugPrint('$e');
      debugPrint('======================================');

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F6FF),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double screenWidth = constraints.maxWidth;
          final double horizontalPadding = screenWidth < 360 ? 16.0 : 24.0;
          final double maxCardWidth = 400.0;
          final double cardWidth = (screenWidth - (horizontalPadding * 2)).clamp(260.0, maxCardWidth);

          return Stack(
            fit: StackFit.expand,
            children: [
              // 1. Radiant Clean Sky-Blue Tech Background
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFFE8F3FF),
                      Color(0xFFDCEBFC),
                      Color(0xFFD0E4FB),
                      Color(0xFFE5F1FE),
                      Color(0xFFF2F7FE),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.0, 0.25, 0.55, 0.82, 1.0],
                  ),
                ),
              ),

              // 2. High-Tech PCB Electronic Circuit Traces & Nodes
              CustomPaint(
                painter: _TechCircuitBackgroundPainter(),
              ),

              // 3. Center Content
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                      vertical: 20,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: cardWidth),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // 3D Robot Mascot (Heroic Splash Size)
                          Stack(
                            alignment: Alignment.center,
                            clipBehavior: Clip.none,
                            children: [
                              // Soft Cyber Ambient Glow behind the robot
                              Positioned(
                                bottom: 12,
                                child: Container(
                                  width: 140,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF00E5FF).withValues(alpha: 0.45),
                                        blurRadius: 36,
                                        spreadRadius: 8,
                                      ),
                                      BoxShadow(
                                        color: const Color(0xFF2563EB).withValues(alpha: 0.35),
                                        blurRadius: 46,
                                        spreadRadius: 14,
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // Free-standing Transparent 3D Robot Mascot Image
                              Image.asset(
                                'assets/images/robot_peeking.png',
                                width: 165,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return Image.asset(
                                    'assets/images/robot_mascot.png',
                                    width: 150,
                                    fit: BoxFit.contain,
                                    errorBuilder: (ctx, err, st) => const Icon(
                                      Icons.smart_toy_rounded,
                                      color: Color(0xFF2563EB),
                                      size: 88,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),

                          // 3D Extruded Metallic "TechNoWiz" Typography Logo
                          Transform.translate(
                            offset: const Offset(0, -10),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      // Ambient Floor Drop Shadow with Cyan Glow
                                      Transform.translate(
                                        offset: const Offset(0, 8),
                                        child: Text(
                                          "TechNoWiz",
                                          style: TextStyle(
                                            fontSize: 52,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 1.6,
                                            foreground: Paint()
                                              ..style = PaintingStyle.fill
                                              ..color = const Color(0xFF00E5FF).withValues(alpha: 0.35)
                                              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
                                          ),
                                        ),
                                      ),

                                      // 3D Extrusion Layer 4: Deep Midnight Blue Base
                                      Transform.translate(
                                        offset: const Offset(0, 5.0),
                                        child: const Text(
                                          "TechNoWiz",
                                          style: TextStyle(
                                            fontSize: 52,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 1.6,
                                            color: Color(0xFF091E42),
                                          ),
                                        ),
                                      ),

                                      // 3D Extrusion Layer 3: Dark Navy Bevel
                                      Transform.translate(
                                        offset: const Offset(0, 3.8),
                                        child: const Text(
                                          "TechNoWiz",
                                          style: TextStyle(
                                            fontSize: 52,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 1.6,
                                            color: Color(0xFF0F3E8A),
                                          ),
                                        ),
                                      ),

                                      // 3D Extrusion Layer 2: Cobalt Mid-Tone Bevel
                                      Transform.translate(
                                        offset: const Offset(0, 2.4),
                                        child: const Text(
                                          "TechNoWiz",
                                          style: TextStyle(
                                            fontSize: 52,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 1.6,
                                            color: Color(0xFF1D4ED8),
                                          ),
                                        ),
                                      ),

                                      // 3D Extrusion Layer 1: Bright Blue Top Bevel
                                      Transform.translate(
                                        offset: const Offset(0, 1.2),
                                        child: const Text(
                                          "TechNoWiz",
                                          style: TextStyle(
                                            fontSize: 52,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 1.6,
                                            color: Color(0xFF3B82F6),
                                          ),
                                        ),
                                      ),

                                      // 3D Front Face: Radiant Metallic Ice-Cyan to Deep Cobalt Gradient
                                      ShaderMask(
                                        shaderCallback: (bounds) => const LinearGradient(
                                          colors: [
                                            Color(0xFFF0F9FF),
                                            Color(0xFF38BDF8),
                                            Color(0xFF2563EB),
                                            Color(0xFF1E40AF),
                                          ],
                                          stops: [0.0, 0.25, 0.65, 1.0],
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                        ).createShader(bounds),
                                        child: Text(
                                          "TechNoWiz",
                                          style: TextStyle(
                                            fontSize: 52,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 1.6,
                                            color: Colors.white,
                                            shadows: [
                                              Shadow(
                                                color: Colors.white.withValues(alpha: 0.9),
                                                offset: const Offset(0, -1),
                                                blurRadius: 1.5,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 8),

                                // Tech Subtitle Pill Badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4.5),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.92),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: const Color(0xFFBFDBFE),
                                      width: 1.2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF2563EB).withValues(alpha: 0.10),
                                        blurRadius: 10,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.hub_rounded, color: Color(0xFF2563EB), size: 14),
                                        SizedBox(width: 6),
                                        Text(
                                          "TECH QUIZ ARENA  •  COMPETE  •  WIN",
                                          style: TextStyle(
                                            color: Color(0xFF1E40AF),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1.1,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 22),

                          // Clean Light Glass Loading Card
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 20,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.94),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: const Color(0xFFBFDBFE),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF1E40AF).withValues(alpha: 0.09),
                                  blurRadius: 32,
                                  offset: const Offset(0, 10),
                                ),
                                BoxShadow(
                                  color: const Color(0xFF3B82F6).withValues(alpha: 0.06),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      "Loading TechNoWiz...",
                                      style: TextStyle(
                                        color: Color(0xFF0F172A),
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: const SizedBox(
                                    height: 6,
                                    child: LinearProgressIndicator(
                                      backgroundColor: Color(0xFFE2E8F0),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Color(0xFF2563EB),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  "A Multi-level Technology Competition",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 22),

                          // Slogan Footer
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF2563EB),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  "TECHNOWIZ",
                                  style: TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF2563EB),
                                    shape: BoxShape.circle,
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
            ],
          );
        },
      ),
    );
  }
}

// =========================================================
// HIGH-TECH PCB ELECTRONIC CIRCUIT BACKGROUND PAINTER
// =========================================================
class _TechCircuitBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    final tracePaint = Paint()
      ..color = const Color(0xFF2563EB).withValues(alpha: 0.22)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final glowPaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.12)
      ..strokeWidth = 3.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final nodeFillPaint = Paint()
      ..color = const Color(0xFF2563EB).withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;

    final nodeRingPaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.40)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = const Color(0xFF1D4ED8).withValues(alpha: 0.30)
      ..style = PaintingStyle.fill;

    void drawCircuitTrace(List<Offset> points, {bool endRing = true, bool drawGlow = true}) {
      if (points.length < 2) return;
      final path = Path()..moveTo(points[0].dx, points[0].dy);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      if (drawGlow) {
        canvas.drawPath(path, glowPaint);
      }
      canvas.drawPath(path, tracePaint);

      // Solder via pads
      canvas.drawCircle(points.first, 3.2, nodeFillPaint);
      canvas.drawCircle(points.last, 3.8, nodeFillPaint);
      if (endRing) {
        canvas.drawCircle(points.last, 7.5, nodeRingPaint);
      }
    }

    void drawChipFootprint(Offset center, double width, double height, int pinsPerSide) {
      final chipRect = Rect.fromCenter(center: center, width: width, height: height);
      final chipPaint = Paint()
        ..color = const Color(0xFF1E40AF).withValues(alpha: 0.16)
        ..style = PaintingStyle.fill;
      final chipBorder = Paint()
        ..color = const Color(0xFF2563EB).withValues(alpha: 0.35)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;

      canvas.drawRRect(RRect.fromRectAndRadius(chipRect, const Radius.circular(3)), chipPaint);
      canvas.drawRRect(RRect.fromRectAndRadius(chipRect, const Radius.circular(3)), chipBorder);

      final pinPaint = Paint()
        ..color = const Color(0xFF2563EB).withValues(alpha: 0.35)
        ..strokeWidth = 1.0;
      final pinStep = height / (pinsPerSide + 1);
      for (int i = 1; i <= pinsPerSide; i++) {
        final py = chipRect.top + i * pinStep;
        canvas.drawLine(Offset(chipRect.left - 4, py), Offset(chipRect.left, py), pinPaint);
        canvas.drawLine(Offset(chipRect.right, py), Offset(chipRect.right + 4, py), pinPaint);
      }
    }

    // Top-Left PCB Traces
    drawCircuitTrace([
      Offset(0, h * 0.08),
      Offset(w * 0.16, h * 0.08),
      Offset(w * 0.24, h * 0.16),
      Offset(w * 0.38, h * 0.16),
    ]);
    drawCircuitTrace([
      Offset(0, h * 0.12),
      Offset(w * 0.13, h * 0.12),
      Offset(w * 0.19, h * 0.18),
      Offset(w * 0.28, h * 0.18),
    ], endRing: false);
    drawCircuitTrace([
      Offset(w * 0.09, 0),
      Offset(w * 0.09, h * 0.05),
      Offset(w * 0.15, h * 0.11),
    ]);

    // Top-Right PCB Traces
    drawCircuitTrace([
      Offset(w, h * 0.09),
      Offset(w * 0.84, h * 0.09),
      Offset(w * 0.76, h * 0.17),
      Offset(w * 0.62, h * 0.17),
    ]);
    drawCircuitTrace([
      Offset(w, h * 0.14),
      Offset(w * 0.86, h * 0.14),
      Offset(w * 0.79, h * 0.21),
      Offset(w * 0.70, h * 0.21),
    ], endRing: false);
    drawCircuitTrace([
      Offset(w * 0.91, 0),
      Offset(w * 0.91, h * 0.06),
      Offset(w * 0.85, h * 0.12),
    ]);

    // Mid-Left Traces
    drawCircuitTrace([
      Offset(0, h * 0.36),
      Offset(w * 0.08, h * 0.36),
      Offset(w * 0.14, h * 0.42),
      Offset(w * 0.22, h * 0.42),
    ]);
    drawCircuitTrace([
      Offset(0, h * 0.62),
      Offset(w * 0.09, h * 0.62),
      Offset(w * 0.15, h * 0.56),
      Offset(w * 0.20, h * 0.56),
    ], endRing: false);

    // Mid-Right Traces
    drawCircuitTrace([
      Offset(w, h * 0.38),
      Offset(w * 0.91, h * 0.38),
      Offset(w * 0.84, h * 0.45),
      Offset(w * 0.78, h * 0.45),
    ]);
    drawCircuitTrace([
      Offset(w, h * 0.66),
      Offset(w * 0.89, h * 0.66),
      Offset(w * 0.83, h * 0.60),
      Offset(w * 0.76, h * 0.60),
    ], endRing: false);

    // Bottom-Left Traces
    drawCircuitTrace([
      Offset(0, h * 0.88),
      Offset(w * 0.16, h * 0.88),
      Offset(w * 0.23, h * 0.81),
      Offset(w * 0.36, h * 0.81),
    ]);
    drawCircuitTrace([
      Offset(w * 0.08, h),
      Offset(w * 0.08, h * 0.93),
      Offset(w * 0.14, h * 0.87),
    ]);

    // Bottom-Right Traces
    drawCircuitTrace([
      Offset(w, h * 0.86),
      Offset(w * 0.82, h * 0.86),
      Offset(w * 0.75, h * 0.79),
      Offset(w * 0.62, h * 0.79),
    ]);
    drawCircuitTrace([
      Offset(w * 0.90, h),
      Offset(w * 0.90, h * 0.92),
      Offset(w * 0.83, h * 0.85),
    ]);

    // SMD IC Chip Footprints along the motherboard
    drawChipFootprint(Offset(w * 0.38, h * 0.16), 18, 14, 3);
    drawChipFootprint(Offset(w * 0.62, h * 0.17), 18, 14, 3);
    drawChipFootprint(Offset(w * 0.22, h * 0.42), 16, 12, 2);
    drawChipFootprint(Offset(w * 0.78, h * 0.45), 16, 12, 2);
    drawChipFootprint(Offset(w * 0.36, h * 0.81), 20, 15, 3);
    drawChipFootprint(Offset(w * 0.62, h * 0.79), 20, 15, 3);

    // Micro Solder Vias (Scattered in tech clusters)
    final viaPoints = [
      Offset(w * 0.05, h * 0.22),
      Offset(w * 0.07, h * 0.25),
      Offset(w * 0.93, h * 0.24),
      Offset(w * 0.95, h * 0.28),
      Offset(w * 0.06, h * 0.72),
      Offset(w * 0.94, h * 0.74),
    ];
    for (final pt in viaPoints) {
      canvas.drawCircle(pt, 2.4, dotPaint);
      canvas.drawCircle(pt, 5.0, nodeRingPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

