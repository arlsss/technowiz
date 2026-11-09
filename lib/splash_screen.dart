import 'dart:async';
import 'package:flutter/material.dart';

import 'package:firebase_auth/firebase_auth.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'screens/login_screen.dart';

import 'screens/admin/admin_dashboard.dart';

import 'screens/admin/add_question_screen.dart';

import 'screens/admin/question_list_screen.dart';

import 'screens/admin/create_quiz_screen.dart';

import 'screens/admin/manage_users_screen.dart';

import 'screens/admin/admin_report_screen.dart';

import 'screens/admin/admin_leaderboard_screen.dart';

import 'screens/admin/manage_quiz_sessions_screen.dart';
import 'screens/admin/manage_quiz_screen.dart';
import 'screens/admin/edit_question_screen.dart';
import 'navigation_persistence.dart';

import 'screens/quizmaster/quizmaster_dashboard.dart';

import 'screens/quizmaster/quiz_control_screen.dart';
import 'screens/quizmaster/quiz_sessions_screen.dart';
import 'screens/quizmaster/leaderboard_screen.dart';
import 'screens/quizmaster/manage_participants_screen.dart';
import 'screens/quizmaster/profile_screen.dart';
import 'screens/quizmaster/contestant_readiness_page.dart';
import 'screens/quizmaster/submitted_answers_screen.dart';

import 'screens/competitor/competitor_dashboard.dart';
import 'screens/competitor/my_score_screen.dart';
import 'screens/competitor/quiz_history_score_screen.dart';

import 'screens/competitor/waiting_room_screen.dart';

import 'screens/competitor/quiz_screen.dart';

import 'screens/quizmaster/final_ranking_screen.dart';

class SplashScreen extends StatefulWidget {
  final bool showSplash;

  const SplashScreen({super.key, this.showSplash = true});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const String _adminLastPageKey = 'technowiz_admin_last_page';

  static const String _adminDetailQuizCodeKey =
      'technowiz_admin_detail_quiz_code';

  static const String _contestantLastPageKey = 'contestant_last_page';

  static const String _contestantQuizCodeKey = 'contestant_current_quiz_code';

  static const String _contestantQuizTitleKey = 'contestant_current_quiz_title';

  static const String _contestantQuizLevelKey = 'contestant_current_quiz_level';

  @override
  void initState() {
    super.initState();

    debugPrint('🔥 SPLASH STARTED (2.5 SECONDS DURATION)');

    _goToNextScreen();
  }

  Future<void> _goToNextScreen() async {
    final DateTime startTime = DateTime.now();

    // 1. Resolve Auth & Destination in background
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      try {
        user = await FirebaseAuth.instance
            .authStateChanges()
            .first
            .timeout(const Duration(milliseconds: 2000));
      } catch (_) {
        user = FirebaseAuth.instance.currentUser;
      }
    }

    Future<void> Function() navigateAction = _goToLogin;

    if (user == null) {
      debugPrint('❌ NO USER → DESTINATION IS LOGIN');
      navigateAction = _goToLogin;
    } else {
      try {
        debugPrint('✅ USER FOUND: ${user.uid}, GETTING ROLE...');

        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (!doc.exists) {
          debugPrint('❌ USER DOCUMENT NOT FOUND');
          await FirebaseAuth.instance.signOut();
          navigateAction = _goToLogin;
        } else {
          final data = doc.data() ?? {};
          final String rawRole = data['role']?.toString().trim() ?? '';
          final String role =
              rawRole.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

          debugPrint('🔥 ROLE: $role');

          if (role == 'admin') {
            navigateAction = _restoreAdminPage;
          } else if (role == 'quizmaster') {
            navigateAction = _restoreQuizMasterPage;
          } else if (role == 'contestant' || role == 'competitor') {
            navigateAction = _restoreContestantPage;
          } else {
            await FirebaseAuth.instance.signOut();
            navigateAction = _goToLogin;
          }
        }
      } catch (e) {
        debugPrint('❌ SPLASH ERROR: $e');
        navigateAction = _goToLogin;
      }
    }

    // 2. Guarantee exactly 2.5 full seconds before navigating away
    final int elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
    final int remainingMs = 2500 - elapsedMs;
    if (remainingMs > 0) {
      await Future.delayed(Duration(milliseconds: remainingMs));
    }

    if (!mounted) return;

    // 3. Execute navigation to destination
    await navigateAction();
  }

  // ==========================================================

  // RESTORE ADMIN PAGE

  // ==========================================================

  // ==========================================================

  // ==========================================================

  // RESTORE CONTESTANT PAGE

  // ==========================================================

  Future<void> _restoreContestantPage() async {
    final prefs = await SharedPreferences.getInstance();

    final String? page = prefs.getString(_contestantLastPageKey);

    final String? quizCode = prefs.getString(_contestantQuizCodeKey);

    final String? quizTitle = prefs.getString(_contestantQuizTitleKey);

    final int? level = prefs.getInt(_contestantQuizLevelKey);

    debugPrint('🔥 SAVED CONTESTANT PAGE: $page');

    debugPrint('🔥 SAVED CONTESTANT QUIZ CODE: $quizCode');

    if (!mounted) return;

    // Restore dashboard tabs through CompetitorDashboard itself.
    // It reads contestant_last_page and restores Dashboard, Leaderboard,
    // Badges, History, or Profile without forcing the user back to Dashboard.
    if (page == 'dashboard' ||
        page == 'leaderboard' ||
        page == 'badges' ||
        page == 'history' ||
        page == 'profile') {
      debugPrint('✅ RESTORING CONTESTANT DASHBOARD TAB: $page');
      _replaceWith(const CompetitorDashboard());
      return;
    }

    if (page == 'waiting_room' &&
        quizCode != null &&
        quizCode.trim().isNotEmpty) {
      try {
        final quizDoc = await FirebaseFirestore.instance
            .collection('quiz_sessions')
            .doc(quizCode.trim())
            .get();

        if (!mounted) return;

        if (quizDoc.exists) {
          final data = quizDoc.data() ?? {};
          final title = quizTitle ?? data['title']?.toString() ?? 'Quiz';

          debugPrint('âœ… RESTORING CONTESTANT WAITING ROOM: ');

          _replaceWith(
            WaitingRoomScreen(
              quizCode: quizCode.trim(),
              level: level ?? 1,
              quizTitle: title,
            ),
          );
          return;
        }
      } catch (e) {
        debugPrint('Waiting room restore query error: ');
        if (!mounted) return;
        _replaceWith(
          WaitingRoomScreen(
            quizCode: quizCode.trim(),
            level: level ?? 1,
            quizTitle: quizTitle ?? 'Quiz',
          ),
        );
        return;
      }
    }

    if (page == 'quiz_screen' &&
        quizCode != null &&
        quizCode.trim().isNotEmpty) {
      final quizDoc = await FirebaseFirestore.instance
          .collection('quiz_sessions')
          .doc(quizCode.trim())
          .get();

      if (!mounted) return;

      if (quizDoc.exists) {
        debugPrint('âœ… RESTORING CONTESTANT QUIZ SCREEN: ');

        _replaceWith(QuizScreen(quizCode: quizCode.trim()));

        return;
      }
    }

    if (page == 'my_score' &&
        quizCode != null &&
        quizCode.trim().isNotEmpty) {
      debugPrint('âœ… RESTORING CONTESTANT MY SCORE: ');
      _replaceWith(MyScoreScreen(quizCode: quizCode.trim()));
      return;
    }

        if (page == 'quiz_history_score' &&
        quizCode != null &&
        quizCode.trim().isNotEmpty) {
      debugPrint('RESTORING CONTESTANT QUIZ HISTORY SCORE: $quizCode');
      _replaceWith(QuizHistoryScoreScreen(quizCode: quizCode.trim()));
      return;
    }

    if ((page == 'final_ranking' || page == 'winners_result') &&
        quizCode != null &&
        quizCode.trim().isNotEmpty) {
      debugPrint('âœ… RESTORING CONTESTANT WINNERS RESULT: ');
      _replaceWith(PartialRankingScreen(quizCode: quizCode.trim(), isFinal: true));
      return;
    }

    await prefs.setString(_contestantLastPageKey, 'dashboard');
    await prefs.remove(_contestantQuizCodeKey);
    await prefs.remove(_contestantQuizTitleKey);
    await prefs.remove(_contestantQuizLevelKey);

    _replaceWith(const CompetitorDashboard());
  }

  // RESTORE QUIZ MASTER PAGE

  // ==========================================================

  Future<void> _restoreQuizMasterPage() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    const String lastPageKey = 'technowiz_quizmaster_last_page';
    const String quizCodeKey = 'technowiz_quizmaster_current_quiz_code';

    final String? page = prefs.getString(lastPageKey);
    final String? rawQuizCode = prefs.getString(quizCodeKey);
    final String quizCode = rawQuizCode?.trim() ?? '';

    debugPrint('🔥 SAVED QUIZ MASTER PAGE: $page');
    debugPrint('🔥 SAVED QUIZ CODE: $quizCode');

    if (!mounted) return;

    // 1. Dashboard
    if (page == 'dashboard' || page == null || page.isEmpty) {
      _replaceWith(const QuizMasterDashboard());
      return;
    }

    // 2. Profile
    if (page == 'profile') {
      _replaceWith(const QuizMasterProfileScreen());
      return;
    }

    // 3. Quizzes / Quiz Sessions
    if (page == 'quiz_sessions') {
      _replaceWith(const QuizSessionsScreen());
      return;
    }

    // 4. Leaderboard & Leaderboard History (works with or without a specific quiz code)
    if (page == 'leaderboard' || page == 'leaderboard_history') {
      final String savedLevel =
          prefs.getString('technowiz_quizmaster_leaderboard_level') ?? 'Level 1';
      _replaceWith(
        LeaderboardScreen(
          quizCode: quizCode,
          initialShowHistory: page == 'leaderboard_history',
          initialLevel: savedLevel,
        ),
      );
      return;
    }

    // 5. Participants / Contestants (works with or without a specific quiz code)
    if (page == 'participants' ||
        page == 'contestant' ||
        page == 'participants_history') {
      _replaceWith(
        ManageParticipantsScreen(
          quizCode: quizCode,
          initialShowHistory: page == 'participants_history',
        ),
      );
      return;
    }

    // 6. Submitted Answers
    if (page == 'submitted_answers') {
      if (quizCode.isNotEmpty) {
        final int? qIndex =
            prefs.getInt('technowiz_quizmaster_submitted_question_index');
        _replaceWith(
          SubmittedAnswersScreen(quizCode: quizCode, questionIndex: qIndex),
        );
        return;
      }
      _replaceWith(const QuizSessionsScreen());
      return;
    }

    // 7. Ranking / Final Ranking
    if (page == 'ranking' || page == 'final_ranking') {
      if (quizCode.isNotEmpty) {
        final int savedLevel =
            prefs.getInt('technowiz_quizmaster_ranking_level') ?? 1;
        final bool isFinal =
            prefs.getBool('technowiz_quizmaster_ranking_is_final') ?? true;
        _replaceWith(
          FinalRankingScreen(
            quizCode: quizCode,
            level: savedLevel,
            isFinal: isFinal,
          ),
        );
        return;
      }
      _replaceWith(const QuizSessionsScreen());
      return;
    }

    // 8. Contestant Readiness / Overview
    if (page == 'participant_readiness' ||
        page == 'contestant_readiness' ||
        page == 'quizmaster_overview') {
      if (quizCode.isNotEmpty) {
        final int savedLevel =
            prefs.getInt('technowiz_quizmaster_readiness_level') ?? 1;
        _replaceWith(
          ContestantReadinessPage(
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
          ),
        );
        return;
      }
      _replaceWith(const QuizSessionsScreen());
      return;
    }

    // 9. History
    if (page == 'history') {
      _replaceWith(const QuizHistoryScreen());
      return;
    }

    // 10. Quiz Control (Directly restore quiz control if code exists)
    if (page == 'quiz_control') {
      if (quizCode.isNotEmpty) {
        _replaceWith(QuizControlScreen(quizCode: quizCode));
        return;
      }
      _replaceWith(const QuizSessionsScreen());
      return;
    }

    // Safe fallback
    _replaceWith(const QuizMasterDashboard());
  }

  Future<void> _restoreAdminPage() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final String? page = prefs.getString(_adminLastPageKey);

    debugPrint('🔥 SAVED ADMIN PAGE: $page');

    if (!mounted) return;

    switch (page) {
      // ======================================================

      // MANAGE USERS

      // ======================================================

      case 'manage_users':
        _replaceWith(const ManageUsersScreen());

        return;

      // ======================================================

      // ADD QUESTION

      // ======================================================

      case 'add_question':
        _replaceWith(const AddQuestionScreen());

        return;

      // ======================================================

      // QUESTION LIST

      // ======================================================

      case 'question_list':
        _replaceWith(const QuestionListScreen());

        return;

      // ======================================================

      // CREATE QUIZ

      // ======================================================

      case 'create_quiz':
        _replaceWith(const CreateQuizScreen());

        return;

      // ======================================================

      // QUIZ SESSIONS

      // ======================================================

      case 'quiz_sessions':
        _replaceWith(const ManageQuizSessionsScreen());

        return;

      // ======================================================

      // LEADERBOARD

      // ======================================================

      case 'leaderboard':
        _replaceWith(const AdminLeaderboardScreen());

        return;

      // ======================================================

      // REPORTS

      // ======================================================

      case 'reports':
        _replaceWith(const AdminReportScreen());

        return;

      // ======================================================

      // MANAGE QUIZ

      // ======================================================

      case 'manage_quiz':
        _replaceWith(const ManageQuizScreen());

        return;

      // ======================================================

      // QUIZ HISTORY

      // ======================================================

      case 'quiz_history':
        _replaceWith(const AdminQuizHistoryScreen());

        return;

      // ======================================================

      // QUIZ HISTORY RESULTS

      // ======================================================

      case 'quiz_history_results':
        final String? historyQuizCode =
            prefs.getString(AdminNavPersistence.historyQuizCodeKey);
        final String historyQuizTitle =
            prefs.getString(AdminNavPersistence.historyQuizTitleKey) ??
                'Quiz Results';
        final String historyQuizDate =
            prefs.getString(AdminNavPersistence.historyQuizDateKey) ?? '';
        final String historyDocId =
            prefs.getString(AdminNavPersistence.historyDocIdKey) ??
                (historyQuizCode ?? '');

        if (historyQuizCode == null || historyQuizCode.trim().isEmpty) {
          await prefs.setString(_adminLastPageKey, 'quiz_history');
          _replaceWith(const AdminQuizHistoryScreen());
          return;
        }

        debugPrint('✅ RESTORING QUIZ HISTORY RESULTS: $historyQuizCode');
        _replaceWith(
          AdminFinishedQuizResultsScreen(
            quizCode: historyQuizCode,
            quizTitle: historyQuizTitle,
            quizDate: historyQuizDate,
            docId: historyDocId.isNotEmpty ? historyDocId : historyQuizCode,
          ),
        );
        return;

      // ======================================================

      // EDIT QUESTION

      // ======================================================

      case 'edit_question':
        final String? questionId =
            prefs.getString(AdminNavPersistence.editQuestionIdKey);
        if (questionId == null || questionId.trim().isEmpty) {
          await prefs.setString(_adminLastPageKey, 'question_list');
          _replaceWith(const QuestionListScreen());
          return;
        }

        final DocumentSnapshot<Map<String, dynamic>> questionDoc =
            await FirebaseFirestore.instance
                .collection('questions')
                .doc(questionId)
                .get();

        if (!mounted) return;

        if (!questionDoc.exists) {
          await prefs.setString(_adminLastPageKey, 'question_list');
          _replaceWith(const QuestionListScreen());
          return;
        }

        debugPrint('✅ RESTORING EDIT QUESTION: $questionId');
        _replaceWith(
          EditQuestionScreen(
            questionId: questionId,
            questionData: questionDoc.data() ?? <String, dynamic>{},
          ),
        );
        return;

      // ======================================================

      // QUIZ LEADERBOARD

      // ======================================================

      case 'quiz_leaderboard':
        final String? lbQuizCode =
            prefs.getString(AdminNavPersistence.leaderboardQuizCodeKey);
        if (lbQuizCode == null || lbQuizCode.trim().isEmpty) {
          await prefs.setString(_adminLastPageKey, 'leaderboard');
          _replaceWith(const AdminLeaderboardScreen());
          return;
        }

        debugPrint('✅ RESTORING QUIZ LEADERBOARD: $lbQuizCode');
        _replaceWith(
          AdminQuizLeaderboardScreen(quizCode: lbQuizCode),
        );
        return;

      // ======================================================

      // QUIZ SESSION DETAIL

      // ======================================================

      case 'quiz_session_detail':
        final String? quizCode = prefs.getString(_adminDetailQuizCodeKey);

        if (quizCode == null || quizCode.trim().isEmpty) {
          debugPrint('⚠️ NO SAVED QUIZ CODE → QUIZ SESSIONS');

          await prefs.setString(_adminLastPageKey, 'quiz_sessions');

          _replaceWith(const ManageQuizSessionsScreen());

          return;
        }

        final DocumentSnapshot<Map<String, dynamic>> quizDoc =
            await FirebaseFirestore.instance
                .collection('quiz_sessions')
                .doc(quizCode)
                .get();

        if (!mounted) return;

        if (!quizDoc.exists) {
          debugPrint('⚠️ SAVED QUIZ NO LONGER EXISTS');

          await prefs.setString(_adminLastPageKey, 'quiz_sessions');

          await prefs.remove(_adminDetailQuizCodeKey);

          _replaceWith(const ManageQuizSessionsScreen());

          return;
        }

        debugPrint('✅ RESTORING QUIZ DETAIL: $quizCode');

        _replaceWith(
          QuizSessionDetailScreen(
            quizCode: quizCode,

            quizData: quizDoc.data() ?? <String, dynamic>{},
          ),
        );

        return;

      // ======================================================

      // DASHBOARD

      // ======================================================

      case null:
      case 'dashboard':
      default:
        _replaceWith(const AdminDashboard(restoreLastPage: false));

        return;
    }
  }

  // ==========================================================

  // RESTORE NORMAL ADMIN PAGE

  // ==========================================================

  // ==========================================================

  // RESTORE QUIZ DETAIL

  // ==========================================================

  // ==========================================================

  // REPLACE CURRENT PAGE

  // ==========================================================

  void _replaceWith(Widget page) {
    if (!mounted) return;

    // Restore the saved page directly after refresh. Do not briefly build
    // the dashboard underneath it, which can cause a visible dashboard flash.
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => page,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  // ==========================================================

  // LOGIN

  // ==========================================================

  Future<void> _goToLogin() async {
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => const LoginScreen(),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  // ==========================================================

  // SPLASH UI

  // =================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F6FF),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double screenWidth = constraints.maxWidth;
          final double screenHeight = constraints.maxHeight;
          final bool isCompact = screenHeight < 680 || screenWidth < 360;
          final bool isLandscape = screenWidth > screenHeight && screenHeight < 550;

          final double horizontalPadding = screenWidth < 360 ? 14.0 : 20.0;
          final double maxCardWidth = screenWidth > 800 ? 440.0 : 400.0;
          final double cardWidth =
              (screenWidth - (horizontalPadding * 2)).clamp(260.0, maxCardWidth);

          final double robotWidth = isLandscape
              ? 100.0
              : (isCompact ? 130.0 : 165.0);
          final double verticalSpacing = isLandscape
              ? 10.0
              : (isCompact ? 14.0 : 22.0);

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
                                width: robotWidth,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return Image.asset(
                                    'assets/images/robot_mascot.png',
                                    width: robotWidth * 0.9,
                                    fit: BoxFit.contain,
                                    errorBuilder: (ctx, err, st) => Icon(
                                      Icons.smart_toy_rounded,
                                      color: const Color(0xFF2563EB),
                                      size: robotWidth * 0.55,
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

                          SizedBox(height: verticalSpacing),

                          // Clean Light Glass Loading Card (2.5s Duration)
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(
                              horizontal: isCompact ? 18 : 24,
                              vertical: isCompact ? 14 : 18,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.95),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: const Color(0xFFBFDBFE),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF1E40AF).withValues(alpha: 0.09),
                                  blurRadius: 30,
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
                              mainAxisSize: MainAxisSize.min,
                              children: [
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

