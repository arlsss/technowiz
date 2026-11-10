import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'quiz_control_screen.dart';
import 'contestant_readiness_page.dart';

import 'leaderboard_screen.dart';

import 'final_ranking_screen.dart';
import 'quizmaster_dashboard.dart';
import 'manage_participants_screen.dart';
import 'profile_screen.dart';
import 'quizmaster_theme.dart';

class QuizSessionsScreen extends StatefulWidget {
  final String? resultMode;

  const QuizSessionsScreen({super.key, this.resultMode});

  @override
  State<QuizSessionsScreen> createState() => _QuizSessionsScreenState();
}

class _QuizSessionsScreenState extends State<QuizSessionsScreen> {
  static const Color primaryBlue = Color(0xFF2196F3);

  static const Color darkBlue = Color(0xFF164E83);

  // Participant readiness confirmation window.
  static const int _readyCheckDurationSeconds = 15;

  // ======================================

  // PAGE TITLE

  // ======================================

  static const String _lastPageKey = 'technowiz_quizmaster_last_page';

  static const String _quizCodeKey = 'technowiz_quizmaster_current_quiz_code';

  // Always initialize hover state; avoids null Set runtime errors.
  final Set<int> _hoveredBottomItems = <int>{};

  bool _restoringSavedPage = false;
  bool _navigationInProgress = false;
  bool _readyCheckActivationInProgress = false;
  bool _levelOneStartInProgress = false;

  @override
  void initState() {
    super.initState();
    _restoreSavedPage();
  }

  Future<void> _restoreSavedPage() async {
    if (_restoringSavedPage || widget.resultMode != null) {
      await _saveCurrentPage();
      return;
    }

    _restoringSavedPage = true;
    final prefs = await SharedPreferences.getInstance();
    final savedPage = prefs.getString(_lastPageKey);
    final savedQuizCode = prefs.getString(_quizCodeKey);

    if (!mounted) return;

    // Restore the last saved page after a browser refresh. This change is
    // intentionally limited to page restoration; other quiz behavior remains
    // unchanged.
    Widget? destination;

    if (savedPage == 'dashboard') {
      destination = const QuizMasterDashboard();
    } else if (savedPage == 'profile') {
      destination = const QuizMasterDashboard();
    } else if (savedQuizCode != null && savedQuizCode.trim().isNotEmpty) {
      switch (savedPage) {
        case 'quizmaster_overview':
          destination = ParticipantReadinessPage(
            quizCode: savedQuizCode,
            onStartQuiz: () =>
                _startLevelOneFromSession(context, savedQuizCode),
            onBeginQuizEvent: () =>
                _activateParticipantReadyCheck(context, savedQuizCode),
          );
          break;
        case 'participant_readiness':
          destination = ContestantReadinessPage(
            quizCode: savedQuizCode,
            onStartQuiz: () => openQuiz(context, savedQuizCode),
            onReturnToSessions: () async {
              if (!context.mounted) return;
              Navigator.of(context).pushReplacement(
                PageRouteBuilder<void>(
                  pageBuilder: (_, _, _) => const QuizSessionsScreen(),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                  transitionsBuilder:
                      (_, animation, secondaryAnimation, child) => child,
                ),
              );
            },
          );
          break;
        case 'quiz_control':
          destination = QuizControlScreen(quizCode: savedQuizCode);
          break;
        case 'leaderboard':
          destination = LeaderboardScreen(quizCode: savedQuizCode);
          break;
        case 'ranking':
          destination = FinalRankingScreen(
            quizCode: savedQuizCode,
            isFinal: true,
          );
          break;
        case 'contestant':
          destination = ManageParticipantsScreen(quizCode: savedQuizCode);
          break;
      }
    }

    if (destination != null) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => destination!,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, animation, secondaryAnimation, child) =>
              child,
        ),
      );
      return;
    }

    await _saveCurrentPage();
  }

  Future<void> _saveCurrentPage() async {
    final prefs = await SharedPreferences.getInstance();

    String page = 'quiz_sessions';

    if (widget.resultMode == 'leaderboard') {
      page = 'leaderboard';
    } else if (widget.resultMode == 'ranking') {
      page = 'ranking';
    }

    await prefs.setString(_lastPageKey, page);
  }

  Future<void> _saveChildPage(String page, String quizCode) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_lastPageKey, page);

    await prefs.setString(_quizCodeKey, quizCode);
  }

  Future<void> _saveDashboardPage() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_lastPageKey, 'dashboard');

    await prefs.remove(_quizCodeKey);
  }

  String get pageTitle {
    switch (widget.resultMode) {
      case 'leaderboard':
        return 'Live Leaderboard';

      case 'ranking':
        return 'Final Ranking';

      default:
        return 'Quiz Sessions';
    }
  }

  // ======================================

  // OPEN QUIZ

  // ======================================

  Future<void> _openQuizmasterOverview(
    BuildContext context,
    String quizCode, {
    Map<String, dynamic>? initialQuizData,
  }) async {
    if (!context.mounted || _navigationInProgress) return;
    _navigationInProgress = true;

    // Start saving the restore state, but don't block opening the page on
    // SharedPreferences I/O. The event details are already available from
    // the tapped quiz card.
    final savePageFuture = _saveChildPage('quizmaster_overview', quizCode);

    try {
      if (!context.mounted) return;

      final routeFuture = Navigator.of(context).push<void>(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => ParticipantReadinessPage(
            quizCode: quizCode,
            initialQuizData: initialQuizData,
            onStartQuiz: () => _startLevelOneFromSession(context, quizCode),
            onBeginQuizEvent: () =>
                _activateParticipantReadyCheck(context, quizCode),
          ),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, animation, secondaryAnimation, child) =>
              child,
        ),
      );

      // Don't wait for the destination route to close before releasing the
      // guard; this prevents the tap guard remaining locked on the overview.
      _navigationInProgress = false;
      await Future.wait<void>([savePageFuture, routeFuture]);
    } finally {
      _navigationInProgress = false;
    }
  }

  Future<void> _activateParticipantReadyCheck(
    BuildContext context,
    String quizCode,
  ) async {
    // Prevent rapid repeated taps while the first request is being processed.
    if (_readyCheckActivationInProgress) return;
    _readyCheckActivationInProgress = true;

    try {
      final quizRef = FirebaseFirestore.instance
          .collection('quiz_sessions')
          .doc(quizCode);
      final quizSnapshot = await quizRef.get();

      if (!quizSnapshot.exists) {
        if (context.mounted) {
          showQuizMasterTopNotification(
            context,
            'Quiz session not found.',
            isError: true,
          );
        }
        return;
      }

      final approved = await quizRef
          .collection('join_requests')
          .where('status', isEqualTo: 'approved')
          .get();

      final readyCheckId = DateTime.now().millisecondsSinceEpoch.toString();
      final batch = FirebaseFirestore.instance.batch();

      for (final participant in approved.docs) {
        batch.update(participant.reference, {
          'ready': false,
          'readyResponded': false,
          'readyAt': null,
          'readyCheckId': readyCheckId,
          'readyForLevel': 1,
          'eliminated': false,
          'isEliminated': false,
          'contestantDecision': null,
        });
      }

      final readyDeadline = Timestamp.fromDate(
        DateTime.now().add(const Duration(seconds: _readyCheckDurationSeconds)),
      );

      batch.update(quizRef, {
        'readyCheckActive': true,
        'readyCheckId': readyCheckId,
        'readyCheckType': 'event',
        'readyCheckStartedAt': FieldValue.serverTimestamp(),
        'readyCheckDeadline': readyDeadline,
        'readyCheckDurationSeconds': _readyCheckDurationSeconds,
        'readyCheckCompleted': false,
        // Persist this flag so the initial event Ready Check is triggered once.
        'initialReadyCheckTriggered': true,
        'countdownActive': false,
        'countdown': 0,
        'status': 'waiting',
        'eventStatus': 'waiting',
        'currentLevel': 1,
        'level': 1,
        'preparedLevel': 1,
        'currentQuestion': 0,
        'timer': 0,
        'isFinished': false,
        'isCompleted': false,
        'completed': false,
        'finished': false,
      });

      try {
        final existingScores = await quizRef.collection('scores').get();
        for (final scoreDoc in existingScores.docs) {
          batch.delete(scoreDoc.reference);
        }
      } catch (err) {
        debugPrint('Unable to clear scores for new quiz event: $err');
      }

      await batch.commit();

      // Each explicit START QUIZ EVENT click creates a fresh readiness round.
      // The new ID lets WaitingRoomScreen detect and display the new dialog.
      _autoMarkUnconfirmedParticipantsReady(quizRef, readyCheckId);
    } catch (error) {
      if (context.mounted) {
        showQuizMasterTopNotification(
          context,
          'Unable to open Contestant Status: $error',
          isError: true,
        );
      }
    } finally {
      _readyCheckActivationInProgress = false;
    }
  }

  /// Starts Level 1 directly from Quiz Sessions after all approved
  /// contestants have confirmed READY. The contestant WaitingRoomScreen
  /// listens to this quiz document's status/countdown fields.
  /// START LEVEL 1 prepares the contestant screen and opens Quiz Control.
  /// The synchronized countdown must only begin when START is pressed
  /// inside QuizControlScreen.
  Future<void> _startLevelOneFromSession(
    BuildContext context,
    String quizCode,
  ) async {
    if (_levelOneStartInProgress || !context.mounted) return;
    _levelOneStartInProgress = true;

    final quizRef = FirebaseFirestore.instance
        .collection('quiz_sessions')
        .doc(quizCode);

    try {
      final snapshot = await quizRef.get();
      if (!snapshot.exists) {
        if (context.mounted) {
          showQuizMasterTopNotification(
            context,
            'Quiz session not found.',
            isError: true,
          );
        }
        return;
      }

      final data = snapshot.data() ?? <String, dynamic>{};
      final currentStatus = (data['status'] ?? 'waiting')
          .toString()
          .trim()
          .toLowerCase();

      // If the event is already running, do not restart or alter its countdown.
      if (currentStatus == 'countdown' || currentStatus == 'active') {
        if (context.mounted) await openQuiz(context, quizCode);
        return;
      }

      // Notify contestants to show "QUIZ IS ABOUT TO BEGIN" without starting
      // the countdown. Keep existing participant READY values unchanged.
      await quizRef.update({
        'status': 'waiting',
        'eventStatus': 'preparing_to_begin',
        // The contestant WaitingRoomScreen detects a NEW preparation command
        // by comparing this timestamp with the value captured on entry.
        'preparationStartedAt': FieldValue.serverTimestamp(),
        'readyCheckType': 'level',
        'readyCheckActive': false,
        'countdownActive': false,
        'countdown': 0,
        'level': 1,
        'currentLevel': 1,
        'preparedLevel': 1,
        'currentQuestion': 0,
        'timer': 0,
        'isFinished': false,
        'isCompleted': false,
        'completed': false,
        'finished': false,
      });

      // Navigate the Quiz Master to Quiz Control. Its START button owns the
      // synchronized countdown; this function must not run a timer/countdown.
      if (context.mounted) await openQuiz(context, quizCode);
    } catch (error) {
      if (context.mounted) {
        showQuizMasterTopNotification(
          context,
          'Unable to prepare Level 1: $error',
          isError: true,
        );
      }
    } finally {
      _levelOneStartInProgress = false;
    }
  }

  Future<void> _autoMarkUnconfirmedParticipantsReady(
    DocumentReference<Map<String, dynamic>> quizRef,
    String readyCheckId,
  ) async {
    await Future<void>.delayed(
      const Duration(seconds: _readyCheckDurationSeconds),
    );

    try {
      final quizSnapshot = await quizRef.get();
      final quizData = quizSnapshot.data();
      if (!quizSnapshot.exists || quizData == null) return;

      // Do not let a delayed callback from an older round affect a new round.
      if (quizData['readyCheckId']?.toString() != readyCheckId) return;

      final participants = await quizRef
          .collection('join_requests')
          .where('status', isEqualTo: 'approved')
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (final participant in participants.docs) {
        final data = participant.data();
        if (data['readyCheckId']?.toString() != readyCheckId) continue;

        // Auto-ready only those who did not respond during the time limit.
        if (data['readyResponded'] != true) {
          batch.update(participant.reference, {
            'ready': true,
            'readyResponded': true,
            'readyAt': FieldValue.serverTimestamp(),
            'readyAutomatically': true,
          });
        }
      }

      batch.update(quizRef, {
        'readyCheckActive': false,
        'readyCheckCompleted': true,
        'readyCheckEndedAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
    } catch (error) {
      // The live Firestore status panel continues to show current status;
      // avoid crashing the Quiz Master screen if the fallback update fails.
      debugPrint('Unable to complete readiness confirmation: $error');
    }
  }

  Future<void> openQuiz(BuildContext context, String quizCode) async {
    if (!context.mounted || _navigationInProgress) return;
    _navigationInProgress = true;

    try {
      String page = 'quiz_control';

      if (widget.resultMode == 'leaderboard') {
        page = 'leaderboard';
      } else if (widget.resultMode == 'ranking') {
        page = 'ranking';
      }

      await _saveChildPage(page, quizCode);
      if (!context.mounted) return;

      final Widget destination = widget.resultMode == 'leaderboard'
          ? LeaderboardScreen(quizCode: quizCode)
          : widget.resultMode == 'ranking'
          ? FinalRankingScreen(quizCode: quizCode, isFinal: true)
          : QuizControlScreen(quizCode: quizCode);

      final routeFuture = Navigator.of(context).push<void>(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => destination,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, animation, secondaryAnimation, child) =>
              child,
        ),
      );

      _navigationInProgress = false;
      await routeFuture;

      if (!mounted) return;
      await _saveCurrentPage();
    } finally {
      _navigationInProgress = false;
    }
  }

  // BUTTON TEXT

  // ======================================

  String buttonText() {
    switch (widget.resultMode) {
      case 'leaderboard':
        return 'VIEW LIVE LEADERBOARD';

      case 'ranking':
        return 'VIEW FINAL RANKING';

      default:
        return 'START';
    }
  }

  // ======================================

  // BUTTON ICON

  // ======================================

  IconData buttonIcon() {
    switch (widget.resultMode) {
      case 'leaderboard':
        return Icons.leaderboard_rounded;

      case 'ranking':
        return Icons.emoji_events_outlined;

      default:
        return Icons.play_circle_fill_rounded;
    }
  }

  // ======================================

  // OPEN HISTORY

  // ======================================

  void openHistory() {
    showQuizMasterHistorySideSheet(context);
  }

  // ======================================

  // MAIN BUILD

  // ======================================

  @override
  Widget build(BuildContext context) {
    if (widget.resultMode == 'leaderboard') {
      return _buildLiveRankingPage(context);
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      bottomNavigationBar: _buildBottomNavigation(),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: widget.resultMode != null
            ? IconButton(
                tooltip: 'Back to Dashboard',
                icon: const Icon(Icons.arrow_back_rounded, color: darkBlue),
                onPressed: () async {
                  await _saveDashboardPage();
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (_) => const QuizMasterDashboard(),
                    ),
                    (route) => false,
                  );
                },
              )
            : const SizedBox.shrink(),
        leadingWidth: widget.resultMode != null ? 48 : 12,
        titleSpacing: 0,
        backgroundColor: Colors.white,
        foregroundColor: darkBlue,
        elevation: 0,
        toolbarHeight: widget.resultMode == null ? 62 : kToolbarHeight,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Color(0xFFDCEAF5)),
        ),
        title: widget.resultMode == null
            ? const QuizMasterBrandTitle(subtitle: 'Quiz Events')
            : Text(
                pageTitle,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: darkBlue,
                ),
              ),
      ),
      body: QuizMasterCircuitBackground(
        child: LayoutBuilder(
          builder: (context, pageConstraints) {
            final sessionsContent = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('quiz_sessions')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: primaryBlue),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(25),
                      child: Text(
                        '${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final allDocs = snapshot.data?.docs ?? [];

                // Show only quizzes that are still waiting, ongoing, or paused.
                // Finished/completed quizzes belong in Quiz History, not Quiz Sessions.
                final docs = allDocs.where((quiz) {
                  final data = quiz.data();

                  // Check whether the quiz was published by Admin or Quiz Master.
                  final isPublished =
                      data['published'] == true ||
                      data['isPublished'] == true ||
                      data['is_published'] == true ||
                      data['published'] == 1 ||
                      data['isPublished'] == 1 ||
                      data['published']?.toString().trim().toLowerCase() ==
                          'true' ||
                      data['isPublished']?.toString().trim().toLowerCase() ==
                          'true' ||
                      (data['status'] ?? '').toString().trim().toLowerCase() ==
                          'published' ||
                      (data['sessionStatus'] ?? '')
                              .toString()
                              .trim()
                              .toLowerCase() ==
                          'published' ||
                      (data['quizStatus'] ?? '')
                              .toString()
                              .trim()
                              .toLowerCase() ==
                          'published' ||
                      (data['eventStatus'] ?? '')
                              .toString()
                              .trim()
                              .toLowerCase() ==
                          'published';

                  // Only show quizzes that have actually been published by the Admin!
                  if (!isPublished) {
                    return false;
                  }

                  // Keep only sessions that are genuinely unfinished.
                  // Finished sessions must appear in Quiz History instead.
                  final status =
                      (data['status'] ??
                              data['quizStatus'] ??
                              data['sessionStatus'] ??
                              data['eventStatus'] ??
                              '')
                          .toString()
                          .trim()
                          .toLowerCase()
                          .replaceAll('-', '_')
                          .replaceAll(' ', '_');

                  final isMarkedFinished =
                      data['isFinished'] == true ||
                      data['isCompleted'] == true ||
                      data['completed'] == true ||
                      data['finished'] == true ||
                      data['isArchived'] == true ||
                      data['archived'] == true;

                  const finishedStatuses = {
                    'finished',
                    'finish',
                    'completed',
                    'complete',
                    'ended',
                    'end',
                    'closed',
                    'close',
                    'archived',
                    'archive',
                    'quiz_finished',
                    'quiz_completed',
                    'finished_quiz',
                  };

                  // Finished/completed quizzes belong strictly in Quiz History, NOT in active Quizzes!
                  if (isMarkedFinished || finishedStatuses.contains(status)) {
                    return false;
                  }

                  return true;
                }).toList();

                // Sort in memory by updatedAt or createdAt descending so newest is first
                docs.sort((a, b) {
                  final aData = a.data();
                  final bData = b.data();
                  final aDate = _dateValue(
                    aData['updatedAt'] ?? aData['createdAt'],
                  );
                  final bDate = _dateValue(
                    bData['updatedAt'] ?? bData['createdAt'],
                  );
                  return bDate.compareTo(aDate);
                });

                if (docs.isEmpty) {
                  return _quizSessionsEmptyState();
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 800;

                    return Center(
                      child: SizedBox(
                        width: isWide ? 1000 : double.infinity,
                        child: ListView.separated(
                          padding: EdgeInsets.fromLTRB(
                            isWide ? 24 : 16,
                            18,
                            isWide ? 24 : 16,
                            35,
                          ),
                          itemCount: docs.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            return _activeQuizDetailsCard(context, docs[index]);
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            );

            return sessionsContent;
          },
        ),
      ),
    );
  }

  // Bottom navigation intentionally mirrors QuizMasterDashboard styling.
  Widget _buildBottomNavigation() {
    final items = <({IconData icon, String title, int index})>[
      (icon: Icons.dashboard_outlined, title: 'Dashboard', index: 0),
      (icon: Icons.assignment_outlined, title: 'Quizzes', index: 1),
      (icon: Icons.bar_chart_outlined, title: 'Leaderboard', index: 2),
      (icon: Icons.people_outline, title: 'Contestant', index: 3),
      (icon: Icons.person_outline, title: 'Profile', index: 4),
    ];

    return StatefulBuilder(
      builder: (context, setNavState) => SafeArea(
        top: false,
        child: Material(
          color: Colors.white,
          elevation: 12,
          child: Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFD8EAF8))),
            ),
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 5),
            child: Row(
              children: items.map((item) {
                final selected = item.index == 1;
                final hovered = _hoveredBottomItems.contains(item.index);
                return Expanded(
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    onEnter: (_) =>
                        setNavState(() => _hoveredBottomItems.add(item.index)),
                    onExit: (_) => setNavState(
                      () => _hoveredBottomItems.remove(item.index),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _handleBottomNavigation(item.index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: selected || hovered
                              ? const Color(0xFFE5F4FF)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              item.icon,
                              size: 20,
                              color: selected || hovered
                                  ? const Color(0xFF168BEB)
                                  : const Color(0xFF718096),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: selected || hovered
                                    ? const Color(0xFF168BEB)
                                    : const Color(0xFF718096),
                                fontSize: 10,
                                fontWeight: selected || hovered
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleBottomNavigation(int index) async {
    if (!mounted || _navigationInProgress) return;
    if (index == 1) return; // Already on Quizzes.
    if (index == 4) {
      showQuizMasterProfileSideSheet(context);
      return;
    }
    _navigationInProgress = true;

    if (index == 0) {
      await _saveDashboardPage();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => const QuizMasterDashboard(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, animation, secondaryAnimation, child) =>
              child,
        ),
      );
      return;
    }

    try {
      final sessions = await FirebaseFirestore.instance
          .collection('quiz_sessions')
          .get();
      final sortedDocs = sessions.docs.toList()
        ..sort((a, b) {
          final aDate = _dateValue(
            a.data()['updatedAt'] ?? a.data()['createdAt'],
          );
          final bDate = _dateValue(
            b.data()['updatedAt'] ?? b.data()['createdAt'],
          );
          return bDate.compareTo(aDate);
        });
      QueryDocumentSnapshot<Map<String, dynamic>>? active;
      for (final doc in sortedDocs) {
        final data = doc.data();
        final status = (data['status'] ?? '')
            .toString()
            .trim()
            .toLowerCase()
            .replaceAll('-', '_')
            .replaceAll(' ', '_');
        final isPub =
            data['published'] == true ||
            data['isPublished'] == true ||
            data['is_published'] == true ||
            data['published']?.toString().toLowerCase() == 'true' ||
            data['isPublished']?.toString().toLowerCase() == 'true' ||
            status == 'published';
        final isFinished =
            data['isFinished'] == true ||
            data['isCompleted'] == true ||
            data['completed'] == true ||
            data['finished'] == true ||
            status == 'finished' ||
            status == 'completed';
        if (isPub && !isFinished) {
          active = doc;
          break;
        }
      }
      if (!mounted) return;
      final chosen = active;
      final quizCode = chosen != null
          ? (chosen.data()['quizCode'] ?? chosen.id).toString().trim()
          : '';
      if (index == 2) {
        await _saveChildPage('leaderboard', quizCode);
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => LeaderboardScreen(quizCode: quizCode),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            transitionsBuilder: (_, animation, secondaryAnimation, child) =>
                child,
          ),
        );
      } else if (index == 3) {
        await _saveChildPage('contestant', quizCode);
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          PageRouteBuilder<void>(
            pageBuilder: (_, _, _) =>
                ManageParticipantsScreen(quizCode: quizCode),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            transitionsBuilder: (_, animation, secondaryAnimation, child) =>
                child,
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      _navigationInProgress = false;
      showQuizMasterTopNotification(
        context,
        'Unable to open page: $error',
        isError: true,
      );
    }
  }

  Widget _activeQuizDetailsCard(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> quiz,
  ) {
    final data = quiz.data();
    final title = _firstValue(data, ['title', 'quizTitle', 'name']);
    final description = _firstValue(data, [
      'description',
      'details',
      'quizDescription',
    ]);
    final venue = _firstValue(data, ['location', 'venue', 'where', 'address']);
    final date = _formatQuizDate(
      _firstRawValue(data, ['date', 'quizDate', 'startDate', 'scheduledDate']),
    );
    final startTime = _formatQuizTime(
      _firstRawValue(data, ['time', 'quizTime', 'startTime', 'scheduledTime']),
    );
    final endTime = _formatQuizTime(
      _firstRawValue(data, [
        'endTime',
        'quizEndTime',
        'finishTime',
        'scheduledEndTime',
      ]),
    );
    final status = data['status']?.toString().trim().toLowerCase() ?? 'waiting';
    final quizCode = data['quizCode']?.toString().trim().isNotEmpty == true
        ? data['quizCode'].toString().trim()
        : quiz.id;

    final isLive =
        status == 'active' ||
        status == 'live' ||
        status == 'started' ||
        status == 'ongoing';
    final isPaused = status == 'paused' || status == 'level_pause';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 560;
        final cardPadding = isMobile ? 18.0 : 24.0;

        final Color statusAccentColor = isLive
            ? const Color(0xFF10B981)
            : isPaused
            ? const Color(0xFFF59E0B)
            : const Color(0xFF2563EB);

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: statusAccentColor.withValues(alpha: 0.25),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1565D8).withValues(alpha: 0.08),
                blurRadius: 28,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top glowing status strip
              Container(
                height: 4,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(22),
                  ),
                  gradient: LinearGradient(
                    colors: [
                      statusAccentColor.withValues(alpha: 0.7),
                      statusAccentColor,
                      statusAccentColor.withValues(alpha: 0.9),
                    ],
                  ),
                ),
              ),

              Padding(
                padding: EdgeInsets.all(cardPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: Tech Tag, Status Badge, and Quiz Code Copy Pill
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isLive
                                    ? Icons.sensors_rounded
                                    : Icons.quiz_rounded,
                                size: 12,
                                color: const Color(0xFF2563EB),
                              ),
                              const SizedBox(width: 5),
                              const Text(
                                'QUIZ ARENA',
                                style: TextStyle(
                                  color: Color(0xFF2563EB),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _statusBadge(status),
                        const Spacer(),

                        // 1-Tap Copy Quiz Code Pill
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: quizCode));
                            showQuizMasterTopNotification(
                              context,
                              'Quiz code "$quizCode" copied to clipboard!',
                              isSuccess: true,
                            );
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.tag_rounded,
                                  size: 13,
                                  color: Color(0xFF64748B),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  quizCode,
                                  style: const TextStyle(
                                    color: Color(0xFF1E293B),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                const Icon(
                                  Icons.copy_rounded,
                                  size: 11,
                                  color: Color(0xFF64748B),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Main Header Row: Glowing Icon + Title
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: isMobile ? 46 : 52,
                          height: isMobile ? 46 : 52,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: isLive
                                  ? [
                                      const Color(0xFF10B981),
                                      const Color(0xFF047857),
                                    ]
                                  : isPaused
                                  ? [
                                      const Color(0xFFF59E0B),
                                      const Color(0xFFD97706),
                                    ]
                                  : [
                                      const Color(0xFF2563EB),
                                      const Color(0xFF1D4ED8),
                                    ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: statusAccentColor.withValues(
                                  alpha: 0.25,
                                ),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              isLive
                                  ? Icons.play_arrow_rounded
                                  : Icons.sports_esports_rounded,
                              color: Colors.white,
                              size: isMobile ? 26 : 30,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: const Color(0xFF0F2B5C),
                                  fontSize: isMobile ? 17 : 20,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                  height: 1.25,
                                ),
                              ),
                              if (description != 'Not set' &&
                                  description.isNotEmpty) ...[
                                const SizedBox(height: 5),
                                Text(
                                  description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 12.5,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Metadata Chips (Date, Time, Venue)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildMetaPill(
                          icon: Icons.calendar_today_rounded,
                          label: date,
                        ),
                        _buildMetaPill(
                          icon: Icons.access_time_rounded,
                          label: '$startTime - $endTime',
                        ),
                        if (venue != 'Not set' && venue.isNotEmpty)
                          _buildMetaPill(
                            icon: Icons.location_on_rounded,
                            label: venue,
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Bottom Action Button
                    Container(
                      width: double.infinity,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF2563EB,
                            ).withValues(alpha: 0.28),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () {
                          if (widget.resultMode == null) {
                            _openQuizmasterOverview(
                              context,
                              quizCode,
                              initialQuizData: data,
                            );
                          } else {
                            openQuiz(context, quizCode);
                          }
                        },
                        icon: const Icon(
                          Icons.visibility_rounded,
                          size: 19,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'ENTER QUIZ EVENT',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            letterSpacing: 0.5,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetaPill({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6.5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13.5, color: const Color(0xFF2563EB)),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quizSessionsEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 480),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFD6E8F7), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1565D8).withValues(alpha: 0.08),
                blurRadius: 32,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Accent Gradient Line
              Container(
                height: 4,
                width: double.infinity,
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF38BDF8),
                      Color(0xFF2563EB),
                      Color(0xFF1D4ED8),
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(28, 26, 28, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Tech Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 4.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.sensors_off_rounded,
                            size: 13,
                            color: Color(0xFF2563EB),
                          ),
                          SizedBox(width: 6),
                          Text(
                            'TECHNOWIZ • ARENA STANDBY',
                            style: TextStyle(
                              color: Color(0xFF2563EB),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Glowing Icon Hub
                    Container(
                      width: 82,
                      height: 82,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFE0F2FE), Color(0xFFBAE6FD)],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF0284C7,
                            ).withValues(alpha: 0.22),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                        border: Border.all(color: Colors.white, width: 3.5),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.school_rounded,
                          size: 38,
                          color: Color(0xFF0284C7),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Title
                    const Text(
                      'No Active Quiz',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF0F2B5C),
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Subtitle
                    const Text(
                      'There is currently no ongoing or scheduled quiz session.\nNew events published by the admin will appear here ready for launch.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12.5,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Standby Status Pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF94A3B8),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Awaiting Active Event',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  dynamic _firstRawValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];

      if (value == null) continue;
      if (value is String && value.trim().isEmpty) continue;

      return value;
    }

    return null;
  }

  String _firstValue(Map<String, dynamic> data, List<String> keys) {
    final value = _firstRawValue(data, keys);

    if (value == null) return 'Not set';

    final text = value.toString().trim();

    return text.isEmpty ? 'Not set' : text;
  }

  DateTime _dateValue(dynamic val) {
    if (val is Timestamp) return val.toDate();
    if (val is DateTime) return val;
    if (val is String) {
      final parsed = DateTime.tryParse(val);
      if (parsed != null) return parsed;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _formatQuizDate(dynamic value) {
    if (value == null) return 'Not set';

    DateTime? date;

    if (value is Timestamp) {
      date = value.toDate();
    } else if (value is DateTime) {
      date = value;
    }

    if (date == null) {
      return value.toString();
    }

    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatQuizTime(dynamic value) {
    if (value == null) return 'Not set';

    DateTime? date;

    if (value is Timestamp) {
      date = value.toDate();
    } else if (value is DateTime) {
      date = value;
    }

    if (date == null) {
      return value.toString();
    }

    final hour = date.hour;
    final minute = date.minute;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;

    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
  }

  Widget _buildLiveRankingPage(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      drawer: _buildLiveRankingDrawer(context),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: darkBlue,
        elevation: 0,
        leading: Builder(
          builder: (drawerContext) => IconButton(
            tooltip: 'Navigation',
            icon: const Icon(Icons.menu_rounded, color: darkBlue),
            onPressed: () => Scaffold.of(drawerContext).openDrawer(),
          ),
        ),
        title: const Text(
          'Live Ranking',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: darkBlue,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded, color: primaryBlue),
            onPressed: () => setState(() {}),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: QuizMasterCircuitBackground(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('quiz_sessions')
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: primaryBlue),
              );
            }
            if (snapshot.hasError) {
              return _liveStateCard(
                icon: Icons.error_outline_rounded,
                title: 'Unable to load Live Ranking',
                message: 'Please try again.',
                iconColor: Colors.red,
              );
            }

            final activeSessions =
                snapshot.data?.docs.where((doc) {
                  final data = doc.data();
                  final status =
                      data['status']?.toString().trim().toLowerCase() ?? '';
                  final isFinished =
                      data['isFinished'] == true ||
                      data['isCompleted'] == true ||
                      data['completed'] == true ||
                      data['finished'] == true ||
                      status == 'finished' ||
                      status == 'completed' ||
                      status == 'closed' ||
                      status == 'archived';
                  if (isFinished) return false;
                  final isPub =
                      data['published'] == true ||
                      data['isPublished'] == true ||
                      data['is_published'] == true ||
                      data['published'] == 1 ||
                      data['isPublished'] == 1 ||
                      data['published']?.toString().trim().toLowerCase() ==
                          'true' ||
                      data['isPublished']?.toString().trim().toLowerCase() ==
                          'true' ||
                      status == 'published';

                  if (!isPub) return false;
                  return true;
                }).toList() ??
                [];

            activeSessions.sort((a, b) {
              final aDate = _dateValue(
                a.data()['updatedAt'] ?? a.data()['createdAt'],
              );
              final bDate = _dateValue(
                b.data()['updatedAt'] ?? b.data()['createdAt'],
              );
              return bDate.compareTo(aDate);
            });

            if (activeSessions.isEmpty) {
              return _noActiveQuizCard();
            }

            final activeQuiz = activeSessions.first;
            final data = activeQuiz.data();

            final status =
                data['status']?.toString().trim().toLowerCase() ?? 'active';

            final title = data['title']?.toString().trim().isNotEmpty == true
                ? data['title'].toString().trim()
                : 'Untitled Quiz';

            final description = data['description']?.toString().trim() ?? '';

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('quiz_sessions')
                  .doc(activeQuiz.id)
                  .collection('join_requests')
                  .snapshots(),
              builder: (context, requestSnapshot) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('quiz_sessions')
                      .doc(activeQuiz.id)
                      .collection('scores')
                      .snapshots(),
                  builder: (context, scoreSnapshot) {
                    if (requestSnapshot.hasError || scoreSnapshot.hasError) {
                      return _liveStateCard(
                        icon: Icons.error_outline_rounded,
                        title: 'Unable to load Live Ranking',
                        message: 'Please try again.',
                        iconColor: Colors.red,
                      );
                    }

                    return _liveRankingContent(
                      title: title,
                      description: description,
                      status: status,
                      entries: _buildLiveRanking(
                        requests: requestSnapshot.data?.docs ?? [],
                        scores: scoreSnapshot.data?.docs ?? [],
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildLiveRankingDrawer(BuildContext context) {
    return _buildConsistentNavigationDrawer(
      context,
      selectedItem: 'Leaderboard',
    );
  }

  Widget _buildConsistentNavigationDrawer(
    BuildContext context, {
    required String selectedItem,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final drawerWidth = (screenWidth * 0.82).clamp(0.0, 300.0).toDouble();

    return Drawer(
      width: drawerWidth,
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5F4FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.school_rounded,
                      color: Color(0xFF168BEB),
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'TechNoWiz',
                    style: TextStyle(
                      color: Color(0xFF07549A),
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            _sidebarItem(
              icon: Icons.dashboard_outlined,
              title: 'Dashboard',
              selected: selectedItem == 'Dashboard',
              onTap: () async {
                await _saveDashboardPage();
                if (!context.mounted) return;
                // Keep the active QuizControlScreen underneath this page.
                // Clearing the whole navigation stack would dispose it and
                // cancel its in-memory timer/countdown.
                Navigator.of(context).pushReplacement(
                  PageRouteBuilder<void>(
                    pageBuilder: (_, _, _) => const QuizMasterDashboard(),
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
                    transitionsBuilder:
                        (_, animation, secondaryAnimation, child) => child,
                  ),
                );
              },
            ),
            _sidebarItem(
              icon: Icons.quiz_outlined,
              title: 'Quizzes',
              selected: selectedItem == 'Quizzes',
              onTap: () async {
                if (selectedItem == 'Quizzes') {
                  Navigator.of(context).pop();
                  return;
                }

                final navigator = Navigator.of(context);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString(_lastPageKey, 'quiz_sessions');

                if (!context.mounted) return;

                // Replace the current page so the navigation drawer closes
                // consistently and pages do not stack on repeated selections.
                navigator.pushReplacement(
                  PageRouteBuilder<void>(
                    pageBuilder: (_, _, _) => const QuizSessionsScreen(),
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
                    transitionsBuilder:
                        (_, animation, secondaryAnimation, child) => child,
                  ),
                );
              },
            ),
            _sidebarItem(
              icon: Icons.leaderboard_outlined,
              title: 'Leaderboard',
              selected: selectedItem == 'Leaderboard',
              onTap: () async {
                if (selectedItem == 'Leaderboard') {
                  Navigator.pop(context);
                  return;
                }

                final navigator = Navigator.of(context);
                navigator.pop();

                try {
                  final prefs = await SharedPreferences.getInstance();
                  String? quizCode = prefs.getString(_quizCodeKey);

                  if (quizCode != null && quizCode.trim().isNotEmpty) {
                    final savedQuiz = await FirebaseFirestore.instance
                        .collection('quiz_sessions')
                        .doc(quizCode)
                        .get();

                    if (savedQuiz.exists) {
                      final savedData = savedQuiz.data() ?? {};
                      final savedStatus = (savedData['status'] ?? '')
                          .toString()
                          .trim()
                          .toLowerCase()
                          .replaceAll('-', '_')
                          .replaceAll(' ', '_');
                      final isPub =
                          savedData['published'] == true ||
                          savedData['isPublished'] == true ||
                          savedStatus == 'published';
                      final isFinished =
                          savedData['isFinished'] == true ||
                          savedData['isCompleted'] == true ||
                          savedStatus == 'finished' ||
                          savedStatus == 'completed';

                      if (isFinished || !isPub) {
                        quizCode = null;
                      }
                    } else {
                      quizCode = null;
                    }
                  }

                  if (quizCode == null || quizCode.trim().isEmpty) {
                    final sessions = await FirebaseFirestore.instance
                        .collection('quiz_sessions')
                        .get();

                    final sortedDocs = sessions.docs.toList()
                      ..sort((a, b) {
                        final aDate = _dateValue(
                          a.data()['updatedAt'] ?? a.data()['createdAt'],
                        );
                        final bDate = _dateValue(
                          b.data()['updatedAt'] ?? b.data()['createdAt'],
                        );
                        return bDate.compareTo(aDate);
                      });

                    QueryDocumentSnapshot<Map<String, dynamic>>? chosen;
                    for (final doc in sortedDocs) {
                      final data = doc.data();
                      final isPub =
                          data['published'] == true ||
                          data['isPublished'] == true ||
                          data['is_published'] == true ||
                          data['published'] == 1 ||
                          data['isPublished'] == 1 ||
                          data['published']
                                  ?.toString()
                                  .trim()
                                  .toLowerCase() ==
                              'true' ||
                          data['isPublished']
                                  ?.toString()
                                  .trim()
                                  .toLowerCase() ==
                              'true' ||
                          (data['status'] ?? '').toString().toLowerCase() ==
                              'published';
                      final isFinished =
                          data['isFinished'] == true ||
                          data['isCompleted'] == true ||
                          data['completed'] == true ||
                          data['finished'] == true ||
                          data['status'] == 'finished' ||
                          data['status'] == 'completed';
                      if (isPub && !isFinished) {
                        chosen = doc;
                        break;
                      }
                    }

                    if (chosen != null) {
                      quizCode = (chosen.data()['quizCode'] ?? chosen.id)
                          .toString()
                          .trim();
                    } else {
                      quizCode = '';
                    }
                  }

                  if (!context.mounted) return;

                  await _saveChildPage('leaderboard', quizCode);
                  if (!context.mounted) return;

                  navigator.pushReplacement(
                    PageRouteBuilder<void>(
                      pageBuilder: (_, _, _) =>
                          LeaderboardScreen(quizCode: quizCode!),
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                      transitionsBuilder:
                          (_, animation, secondaryAnimation, child) => child,
                    ),
                  );
                } catch (error) {
                  if (!context.mounted) return;
                  showQuizMasterTopNotification(
                    context,
                    'Unable to open leaderboard: $error',
                    isError: true,
                  );
                }
              },
            ),
            _sidebarItem(
              icon: Icons.people_outline_rounded,
              title: 'Contestant',
              selected: selectedItem == 'Contestant',
              onTap: () async {
                final navigator = Navigator.of(context);
                navigator.pop();
                try {
                  final sessions = await FirebaseFirestore.instance
                      .collection('quiz_sessions')
                      .get();
                  final sortedDocs = sessions.docs.toList()
                    ..sort((a, b) {
                      final aDate = _dateValue(
                        a.data()['updatedAt'] ?? a.data()['createdAt'],
                      );
                      final bDate = _dateValue(
                        b.data()['updatedAt'] ?? b.data()['createdAt'],
                      );
                      return bDate.compareTo(aDate);
                    });
                  final active = sortedDocs.where((doc) {
                    final data = doc.data();
                    final isPub =
                        data['published'] == true ||
                        data['isPublished'] == true ||
                        data['is_published'] == true ||
                        data['published'] == 1 ||
                        data['isPublished'] == 1 ||
                        data['published']
                                ?.toString()
                                .trim()
                                .toLowerCase() ==
                            'true' ||
                        data['isPublished']
                                ?.toString()
                                .trim()
                                .toLowerCase() ==
                            'true' ||
                        (data['status'] ?? '').toString().toLowerCase() ==
                            'published';
                    final isFinished =
                        data['isFinished'] == true ||
                        data['isCompleted'] == true ||
                        data['completed'] == true ||
                        data['finished'] == true ||
                        data['status'] == 'finished' ||
                        data['status'] == 'completed';
                    return isPub && !isFinished;
                  }).toList();

                  if (!context.mounted) return;
                  final quizCode = active.isNotEmpty
                      ? (active.first.data()['quizCode'] ?? active.first.id)
                            .toString()
                            .trim()
                      : '';

                  await _saveChildPage('contestant', quizCode);
                  if (!context.mounted) return;

                  navigator.pushReplacement(
                    PageRouteBuilder<void>(
                      pageBuilder: (_, _, _) =>
                          ManageParticipantsScreen(quizCode: quizCode),
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                      transitionsBuilder:
                          (_, animation, secondaryAnimation, child) => child,
                    ),
                  );
                } catch (error) {
                  if (!context.mounted) return;
                  showQuizMasterTopNotification(
                    context,
                    'Unable to open contestant: $error',
                    isError: true,
                  );
                }
              },
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _sidebarItem({
    required IconData icon,
    required String title,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 1),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: AnimatedContainer(
          duration: Duration.zero,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFE4F2FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? primaryBlue : const Color(0xFF68737D),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  color: selected ? primaryBlue : const Color(0xFF4D5964),
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _liveRankingContent({
    required String title,
    required String description,
    required String status,
    required List<_LiveRankEntry> entries,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 700;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            mobile ? 16 : 28,
            mobile ? 16 : 24,
            mobile ? 16 : 28,
            30,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _activeQuizInfoCard(
                    title: title,
                    description: description,
                    status: status,
                  ),
                  const SizedBox(height: 18),
                  _liveRankingCard(entries),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _activeQuizInfoCard({
    required String title,
    required String description,
    required String status,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.blue.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.quiz_rounded, color: primaryBlue, size: 26),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'ACTIVE QUIZ',
                        style: TextStyle(
                          color: primaryBlue,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .5,
                        ),
                      ),
                    ),
                    _liveQuizStatusBadge(status),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: darkBlue,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveQuizStatusBadge(String status) {
    final normalized = status.trim().toLowerCase();

    String label;
    Color color;

    switch (normalized) {
      case 'level_pause':
      case 'paused':
        label = 'PAUSED';
        color = Colors.orange;
        break;
      case 'waiting':
        label = 'WAITING';
        color = primaryBlue;
        break;
      case 'countdown':
        label = 'COUNTDOWN';
        color = Colors.deepPurple;
        break;
      case 'ongoing':
      case 'active':
      case 'live':
      case 'started':
      default:
        label = 'LIVE';
        color = Colors.green;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _liveRankingCard(List<_LiveRankEntry> entries) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.blue.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.leaderboard_rounded,
                color: primaryBlue,
                size: 23,
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'LIVE RANKING',
                  style: TextStyle(
                    color: darkBlue,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${entries.length} contestant',
                style: const TextStyle(
                  color: Colors.black45,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Text(
                  'Waiting for contestant...',
                  style: TextStyle(color: Colors.black45, fontSize: 12),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = entries[index];
                final rank = index + 1;
                final medal = rank == 1
                    ? '🥇'
                    : rank == 2
                    ? '🥈'
                    : rank == 3
                    ? '🥉'
                    : '$rank';

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 38,
                        child: Text(
                          medal,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: rank <= 3 ? 19 : 12,
                            fontWeight: FontWeight.bold,
                            color: rank <= 3 ? primaryBlue : darkBlue,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: darkBlue,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '${entry.score} pts',
                        style: const TextStyle(
                          color: primaryBlue,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _noActiveQuizCard() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 480),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFD6E8F7), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1565D8).withValues(alpha: 0.08),
                blurRadius: 32,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 4,
                width: double.infinity,
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF38BDF8),
                      Color(0xFF2563EB),
                      Color(0xFF1D4ED8),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 26, 28, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 82,
                      height: 82,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFE0F2FE), Color(0xFFBAE6FD)],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF0284C7,
                            ).withValues(alpha: 0.22),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                        border: Border.all(color: Colors.white, width: 3.5),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.leaderboard_rounded,
                          size: 38,
                          color: Color(0xFF0284C7),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'No Active Quiz',
                      style: TextStyle(
                        color: Color(0xFF0F2B5C),
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'There is currently no live quiz to rank.\nLive scores will stream here once a quiz session begins.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12.5,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _liveStateCard({
    required IconData icon,
    required String title,
    required String message,
    required Color iconColor,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 480),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFD6E8F7), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1565D8).withValues(alpha: 0.08),
                blurRadius: 32,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: iconColor.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: Center(child: Icon(icon, color: iconColor, size: 36)),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF0F2B5C),
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12.5,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isApproved(dynamic value) {
    final status = value?.toString().trim().toLowerCase() ?? '';
    return status == 'approved' || status == 'accepted';
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  List<_LiveRankEntry> _buildLiveRanking({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> requests,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> scores,
  }) {
    final Map<String, _LiveRankEntry> grouped = {};

    for (final doc in requests) {
      final data = doc.data();
      if (!_isApproved(data['status'])) continue;

      final uid = data['uid']?.toString() ?? doc.id;
      final teamName = data['teamName']?.toString().trim() ?? '';
      final name = data['displayName']?.toString().trim().isNotEmpty == true
          ? data['displayName'].toString().trim()
          : data['name']?.toString().trim() ?? 'Contestant';

      final key = teamName.isNotEmpty ? 'team:$teamName' : 'user:$uid';
      final display = teamName.isNotEmpty ? teamName : name;

      grouped.putIfAbsent(key, () => _LiveRankEntry(name: display, score: 0));
    }

    for (final doc in scores) {
      final data = doc.data();
      final uid = data['uid']?.toString() ?? doc.id;
      final teamName = data['teamName']?.toString().trim() ?? '';

      final rawName =
          data['teamName'] ??
          data['participantName'] ??
          data['displayName'] ??
          data['name'] ??
          'Contestant';

      final name = rawName.toString().trim().isEmpty
          ? 'Contestant'
          : rawName.toString().trim();

      final key = teamName.isNotEmpty ? 'team:$teamName' : 'user:$uid';
      final score = _toInt(data['score']);

      final current = grouped[key];

      if (current == null) {
        grouped[key] = _LiveRankEntry(name: name, score: score);
      } else {
        grouped[key] = _LiveRankEntry(
          name: current.name,
          score: current.score + score,
        );
      }
    }

    final result = grouped.values.toList();

    result.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return result;
  }

  // CURRENT QUIZ HEADER

  // ======================================

  // ======================================

  // EMPTY MAIN SCREEN

  // ======================================

  // ======================================

  // CURRENT QUIZ CARD

  // ======================================

  // ======================================

  // EMPTY CURRENT QUIZ

  // ======================================

  // ======================================

  // STATUS BADGE

  // ======================================

  Widget _statusBadge(String status) {
    final normalized = status
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    Color color;

    switch (normalized) {
      case 'active':
      case 'live':
      case 'started':
      case 'ongoing':
        color = Colors.green;

        break;

      case 'finished':
        color = Colors.grey;

        break;

      case 'level_pause':
        color = Colors.orange;

        break;

      case 'waiting':
        color = primaryBlue;

        break;

      case 'paused':
        color = Colors.orange;

        break;

      default:
        color = primaryBlue;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            normalized.replaceAll('_', ' ').toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveRankEntry {
  final String name;
  final int score;

  const _LiveRankEntry({required this.name, required this.score});
}

// ===========================================
// QUIZ HISTORY SCREEN & SLIDE-OUT SIDE SHEET
// ===========================================

/// Shows Quiz History as a smooth, high-tech slide-out side panel from the right.
void showQuizMasterHistorySideSheet(BuildContext context) {
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Quiz History',
    barrierColor: Colors.black45,
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (dialogContext, _, _) {
      final screenWidth = MediaQuery.of(dialogContext).size.width;
      final panelWidth = screenWidth < 520 ? screenWidth * 0.92 : 460.0;

      return Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: panelWidth,
            height: double.infinity,
            child: ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(20),
              ),
              child: QuizHistoryScreen(
                embedded: true,
                onClose: () {
                  if (Navigator.of(dialogContext).canPop()) {
                    Navigator.of(dialogContext).pop();
                  }
                },
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, anim, _, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

class QuizHistoryScreen extends StatelessWidget {
  final bool embedded;
  final VoidCallback? onClose;

  const QuizHistoryScreen({super.key, this.embedded = false, this.onClose});

  static const Color primaryBlue = Color(0xFF2196F3);

  static const Color darkBlue = Color(0xFF164E83);

  DateTime _dateValue(dynamic val) {
    if (val is Timestamp) return val.toDate();
    if (val is DateTime) return val;
    if (val is String) {
      final parsed = DateTime.tryParse(val);
      if (parsed != null) return parsed;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  // ======================================

  // OPEN FINISHED QUIZ

  // ======================================

  Future<void> openQuiz(BuildContext context, String quizCode) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('technowiz_quizmaster_last_page', 'quiz_control');
    await prefs.setString('technowiz_quizmaster_current_quiz_code', quizCode);

    // Viewing a finished quiz from History keeps its code for restoration.

    if (!context.mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => QuizControlScreen(quizCode: quizCode)),
    );

    if (!context.mounted) return;

    await prefs.setString('technowiz_quizmaster_last_page', 'quiz_sessions');
  }

  // ======================================

  // DELETE QUIZ

  // ======================================

  Future<void> deleteQuiz(
    BuildContext context,

    QueryDocumentSnapshot<Map<String, dynamic>> quiz,

    String title,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,

      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),

          title: const Row(
            children: [
              Icon(Icons.delete_outline_rounded, color: Colors.red, size: 27),

              SizedBox(width: 10),

              Text(
                'Delete Quiz?',

                style: TextStyle(fontWeight: FontWeight.bold, color: darkBlue),
              ),
            ],
          ),

          content: Text(
            'Are you sure you want to delete "$title" from quiz history?\n\nThis action cannot be undone.',

            style: const TextStyle(color: Colors.black54, height: 1.4),
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },

              child: const Text(
                'CANCEL',

                style: TextStyle(color: darkBlue, fontWeight: FontWeight.bold),
              ),
            ),

            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },

              icon: const Icon(Icons.delete_outline, size: 18),

              label: const Text(
                'DELETE',

                style: TextStyle(fontWeight: FontWeight.bold),
              ),

              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,

                foregroundColor: Colors.white,

                elevation: 0,

                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        );
      },
    );

    // ====================================

    // CANCELLED

    // ====================================

    if (confirmed != true) {
      return;
    }

    // ====================================

    // DELETE FROM FIRESTORE

    // ====================================

    try {
      await quiz.reference.delete();

      if (!context.mounted) return;

      showQuizMasterTopNotification(
        context,
        '"$title" has been deleted.',
        isSuccess: true,
      );
    } catch (e) {
      if (!context.mounted) return;

      showQuizMasterTopNotification(
        context,
        'Unable to delete quiz: $e',
        isError: true,
      );

      debugPrint('Error deleting quiz: $e');
    }
  }

  // ======================================

  // BUILD

  // ======================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,

      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: darkBlue,
        elevation: 0,
        centerTitle: false,
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        leading: IconButton(
          icon: Icon(
            embedded ? Icons.close_rounded : Icons.arrow_back_rounded,
            color: darkBlue,
          ),
          onPressed: () async {
            if (embedded) {
              if (onClose != null) {
                onClose!();
              } else if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
              return;
            }

            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(
              'technowiz_quizmaster_last_page',
              'quiz_sessions',
            );
            await prefs.remove('technowiz_quizmaster_current_quiz_code');

            if (!context.mounted) return;
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              Navigator.of(context).pushReplacement(
                PageRouteBuilder<void>(
                  pageBuilder: (_, _, _) => const QuizSessionsScreen(),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                  transitionsBuilder:
                      (_, animation, secondaryAnimation, child) => child,
                ),
              );
            }
          },
        ),
        title: const Text(
          'Quiz History',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: darkBlue,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
        ),
      ),

      body: QuizMasterCircuitBackground(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('quiz_sessions')
              .snapshots(),

          builder: (context, snapshot) {
            // ================================

            // LOADING

            // ================================

            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: primaryBlue),
              );
            }

            // ================================

            // ERROR

            // ================================

            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(25),

                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,

                    children: [
                      Container(
                        width: 70,

                        height: 70,

                        decoration: BoxDecoration(
                          color: Colors.red.shade50,

                          shape: BoxShape.circle,
                        ),

                        child: const Icon(
                          Icons.error_outline_rounded,

                          color: Colors.red,

                          size: 38,
                        ),
                      ),

                      const SizedBox(height: 16),

                      const Text(
                        'Unable to load quiz history.',

                        textAlign: TextAlign.center,

                        style: TextStyle(
                          fontSize: 17,

                          fontWeight: FontWeight.bold,

                          color: darkBlue,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        '${snapshot.error}',

                        textAlign: TextAlign.center,

                        style: const TextStyle(
                          fontSize: 12,

                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            // ================================

            // NO DATA

            // ================================

            if (!snapshot.hasData) {
              return const SizedBox();
            }

            // ================================

            // FINISHED ONLY

            // ================================

            final finishedQuizzes = snapshot.data!.docs.where((quiz) {
              final data = quiz.data();
              final status =
                  (data['status'] ??
                          data['quizStatus'] ??
                          data['sessionStatus'] ??
                          '')
                      .toString()
                      .trim()
                      .toLowerCase()
                      .replaceAll('-', '_')
                      .replaceAll(' ', '_');

              return {
                    'finished',
                    'finish',
                    'completed',
                    'complete',
                    'ended',
                    'closed',
                    'quiz_finished',
                    'quiz_completed',
                    'finished_quiz',
                  }.contains(status) ||
                  data['isFinished'] == true ||
                  data['isCompleted'] == true ||
                  data['completed'] == true ||
                  data['finished'] == true;
            }).toList();

            finishedQuizzes.sort((a, b) {
              final aData = a.data();
              final bData = b.data();
              final aDate = _dateValue(
                aData['updatedAt'] ?? aData['createdAt'],
              );
              final bDate = _dateValue(
                bData['updatedAt'] ?? bData['createdAt'],
              );
              return bDate.compareTo(aDate);
            });

            // ================================

            // EMPTY HISTORY

            // ================================

            if (finishedQuizzes.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(25),

                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,

                    children: [
                      Container(
                        width: 75,

                        height: 75,

                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,

                          shape: BoxShape.circle,
                        ),

                        child: const Icon(
                          Icons.history_rounded,

                          size: 38,

                          color: Colors.black26,
                        ),
                      ),

                      const SizedBox(height: 16),

                      const Text(
                        'No Finished Quizzes',

                        style: TextStyle(
                          fontSize: 18,

                          fontWeight: FontWeight.bold,

                          color: darkBlue,
                        ),
                      ),

                      const SizedBox(height: 6),

                      const Text(
                        'Finished quiz sessions will appear here.',

                        textAlign: TextAlign.center,

                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              );
            }

            // ================================

            // HISTORY LIST

            // ================================

            return LayoutBuilder(
              builder: (context, constraints) {
                final bool isWide = constraints.maxWidth > 800;

                final double contentWidth = isWide ? 900 : double.infinity;

                return Center(
                  child: SizedBox(
                    width: contentWidth,

                    child: ListView.builder(
                      padding: EdgeInsets.fromLTRB(
                        isWide ? 24 : 16,

                        18,

                        isWide ? 24 : 16,

                        30,
                      ),

                      itemCount: finishedQuizzes.length,

                      itemBuilder: (context, index) {
                        final quiz = finishedQuizzes[index];

                        final data = quiz.data();

                        final String title =
                            data['title']?.toString() ?? 'Untitled Quiz';

                        final String quizCode =
                            data['quizCode']?.toString() ?? quiz.id;

                        return _historyQuizCard(context, quiz, title, quizCode);
                      },
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  // ======================================

  // HISTORY QUIZ CARD

  // ======================================

  Widget _historyQuizCard(
    BuildContext context,

    QueryDocumentSnapshot<Map<String, dynamic>> quiz,

    String title,

    String quizCode,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(18),

        border: Border.all(color: Colors.grey.shade200),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),

            blurRadius: 8,

            offset: const Offset(0, 3),
          ),
        ],
      ),

      child: Padding(
        padding: const EdgeInsets.all(15),

        child: Row(
          children: [
            // ============================

            // HISTORY ICON

            // ============================
            Container(
              width: 50,

              height: 50,

              decoration: BoxDecoration(
                color: Colors.grey.shade100,

                borderRadius: BorderRadius.circular(14),
              ),

              child: const Icon(
                Icons.history_rounded,

                color: Colors.grey,

                size: 27,
              ),
            ),

            const SizedBox(width: 14),

            // ============================

            // QUIZ DETAILS

            // ============================
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Text(
                    title,

                    maxLines: 1,

                    overflow: TextOverflow.ellipsis,

                    style: const TextStyle(
                      fontSize: 16,

                      fontWeight: FontWeight.bold,

                      color: darkBlue,
                    ),
                  ),

                  const SizedBox(height: 5),

                  Text(
                    'Code: $quizCode',

                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),

                  const SizedBox(height: 7),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,

                      vertical: 5,
                    ),

                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.10),

                      borderRadius: BorderRadius.circular(20),
                    ),

                    child: const Text(
                      'FINISHED',

                      style: TextStyle(
                        color: Colors.grey,

                        fontSize: 9,

                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // ============================

            // DELETE + OPEN BUTTONS

            // ============================
            Row(
              mainAxisSize: MainAxisSize.min,

              children: [
                // ============================

                // DELETE

                // ============================
                Container(
                  width: 36,

                  height: 36,

                  decoration: BoxDecoration(
                    color: Colors.red.shade50,

                    shape: BoxShape.circle,
                  ),

                  child: IconButton(
                    padding: EdgeInsets.zero,

                    tooltip: 'Delete Quiz',

                    onPressed: () {
                      deleteQuiz(context, quiz, title);
                    },

                    icon: const Icon(
                      Icons.delete_outline_rounded,

                      size: 18,

                      color: Colors.red,
                    ),
                  ),
                ),

                const SizedBox(width: 7),

                // ============================

                // OPEN

                // ============================
                Container(
                  width: 36,

                  height: 36,

                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,

                    shape: BoxShape.circle,
                  ),

                  child: IconButton(
                    padding: EdgeInsets.zero,

                    tooltip: 'Open Quiz',

                    onPressed: () {
                      openQuiz(context, quizCode);
                    },

                    icon: const Icon(
                      Icons.arrow_forward_ios_rounded,

                      size: 15,

                      color: primaryBlue,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ParticipantReadinessPage extends StatelessWidget {
  final String quizCode;
  final Future<void> Function() onStartQuiz;
  final Future<void> Function() onBeginQuizEvent;
  final Map<String, dynamic>? initialQuizData;

  const ParticipantReadinessPage({
    super.key,
    required this.quizCode,
    required this.onStartQuiz,
    required this.onBeginQuizEvent,
    this.initialQuizData,
  });

  static const Color _primaryBlue = Color(0xFF2196F3);
  static const Color _darkBlue = Color(0xFF164E83);



  Widget _eventInformation(Map<String, dynamic> data) {
    final guidelines = <Map<String, dynamic>>[
      {
        'icon': Icons.checklist_rounded,
        'title': 'BEFORE STARTING',
        'bullets': <String>[
          'Check the quiz event details.',
          'Confirm all approved contestants are listed.',
        ],
      },
      {
        'icon': Icons.groups_rounded,
        'title': 'CONTESTANT READINESS',
        'bullets': <String>[
          'Watch each contestant’s READY or WAITING status.',
          'The Ready Check lasts 15 seconds.',
        ],
      },
      {
        'icon': Icons.tune_rounded,
        'title': 'LEVEL SETTINGS',
        'bullets': <String>[
          'Review each level’s timer and points.',
          'Check the difficulty and elimination count.',
        ],
      },
      {
        'icon': Icons.play_circle_outline_rounded,
        'title': 'START LEVEL 1',
        'bullets': <String>[
          'Make sure all approved contestants are READY.',
          'Select START THE QUIZ to continue.',
        ],
      },
      {
        'icon': Icons.shield_outlined,
        'title': 'DURING THE QUIZ',
        'bullets': <String>[
          'Follow the configured quiz rules.',
          'Avoid changing settings while the quiz is running.',
        ],
      },
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDCEAF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...guidelines.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(item['icon'] as IconData, color: _primaryBlue, size: 21),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['title'] as String,
                          style: const TextStyle(
                            color: _darkBlue,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ...((item['bullets'] as List<String>).map(
                          (bullet) => Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '• ',
                                  style: TextStyle(
                                    color: _primaryBlue,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    bullet,
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      fontSize: 12,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )),
                        if ((item['title'] as String) == 'LEVEL SETTINGS') ...[
                          const SizedBox(height: 8),
                          _levelSettingsSection(data),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _levelSettingsSection(Map<String, dynamic> data) {
    final rawSettings = data['levelSettings'];
    final Map<String, dynamic> settingsByLevel = rawSettings is Map
        ? Map<String, dynamic>.from(rawSettings)
        : <String, dynamic>{};

    if (settingsByLevel.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF5FAFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDCEAF5)),
        ),
        child: const Text(
          'No saved level settings are available for this quiz event yet.',
          style: TextStyle(color: Colors.black54, fontSize: 12, height: 1.35),
        ),
      );
    }

    final entries = settingsByLevel.entries.toList()
      ..sort((a, b) {
        final aNumber =
            int.tryParse(a.key.toLowerCase().replaceAll('level', '').trim()) ??
            999;
        final bNumber =
            int.tryParse(b.key.toLowerCase().replaceAll('level', '').trim()) ??
            999;
        return aNumber.compareTo(bNumber);
      });

    String valueOrNotSet(dynamic value, {String suffix = ''}) {
      if (value == null || value.toString().trim().isEmpty) {
        return 'Not set';
      }
      return '${value.toString().trim()}$suffix';
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('quiz_sessions')
          .doc(quizCode)
          .collection('questions')
          .snapshots(),
      builder: (context, questionSnapshot) {
        final questionDocs = questionSnapshot.data?.docs ?? [];

        String normalizeLevel(dynamic value) =>
            value.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

        List<QueryDocumentSnapshot<Map<String, dynamic>>> questionsForLevel(
          String levelKey,
        ) {
          final target = normalizeLevel(levelKey);
          return questionDocs.where((doc) {
            final question = doc.data();
            // Admin saves the assignment level as sessionLevel when questions
            // are added to a quiz event. Check it first, then legacy fields.
            for (final key in [
              'sessionLevel',
              'assignedLevel',
              'level',
              'levelName',
              'quizLevel',
              'levelNumber',
              'levelNo',
            ]) {
              final value = question[key];
              if (value == null || value.toString().trim().isEmpty) continue;
              final normalized = normalizeLevel(value);
              if (normalized == target ||
                  normalized == target.replaceFirst('level', '')) {
                return true;
              }
              // sessionLevel is the assignment field, so don't fall through
              // to the question-bank difficulty when it is present.
              if (key == 'sessionLevel') return false;
            }
            return false;
          }).toList();
        }

        int? questionCountForLevel(
          String levelKey,
          Map<String, dynamic> settings,
        ) {
          // The Admin stores the actual assigned question IDs on the quiz event.
          final rawAssignments = data['levelQuestions'];
          if (rawAssignments is Map) {
            dynamic assigned;
            for (final entry in rawAssignments.entries) {
              if (normalizeLevel(entry.key) == normalizeLevel(levelKey)) {
                assigned = entry.value;
                break;
              }
            }
            if (assigned is List) return assigned.length;
          }

          // Fall back to any explicit assignment list stored in level settings.
          for (final key in [
            'questions',
            'questionIds',
            'assignedQuestions',
            'assignedQuestionIds',
          ]) {
            final value = settings[key];
            if (value is List) return value.length;
          }

          final count = questionsForLevel(levelKey).length;
          if (count > 0) return count;

          for (final key in [
            'questionCount',
            'numberOfQuestions',
            'totalQuestions',
            'questionsCount',
          ]) {
            final value = settings[key];
            if (value is num) return value.toInt();
            final parsed = int.tryParse(value?.toString() ?? '');
            if (parsed != null) return parsed;
          }

          return null;
        }

        return Column(
          children: entries.map((entry) {
            final levelKey = entry.key;
            final settings = entry.value is Map
                ? Map<String, dynamic>.from(entry.value as Map)
                : <String, dynamic>{};

            final count = questionCountForLevel(levelKey, settings);
            final questionCountText = count != null
                ? '$count ${count == 1 ? 'question' : 'questions'}'
                : 'Not set';

            final questionType = settings['questionType'] ??
                settings['type'] ??
                settings['category'];
            final timerSeconds = settings['timerSeconds'] ??
                settings['timer'] ??
                settings['timeLimit'];
            final points = settings['pointsPerCorrectAnswer'] ??
                settings['points'] ??
                settings['pts'];
            final difficulty = settings['difficulty'];
            final eliminateCount = settings['eliminateCount'];

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF7FAFD),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFDCEAF5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    levelKey,
                    style: const TextStyle(
                      color: _darkBlue,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _levelSettingRow(
                    Icons.format_list_bulleted_rounded,
                    'Number of Questions',
                    questionCountText,
                  ),
                  const SizedBox(height: 7),
                  _levelSettingRow(
                    Icons.account_tree_outlined,
                    'Question Type',
                    valueOrNotSet(questionType),
                  ),
                  const SizedBox(height: 7),
                  _levelSettingRow(
                    Icons.timer_outlined,
                    'Question Timer',
                    valueOrNotSet(timerSeconds, suffix: ' seconds'),
                  ),
                  const SizedBox(height: 7),
                  _levelSettingRow(
                    Icons.stars_rounded,
                    'Points per Correct Answer',
                    valueOrNotSet(points, suffix: ' pts'),
                  ),
                  const SizedBox(height: 7),
                  _levelSettingRow(
                    Icons.tune_rounded,
                    'Difficulty',
                    valueOrNotSet(difficulty),
                  ),
                  const SizedBox(height: 7),
                  _levelSettingRow(
                    Icons.person_remove_outlined,
                    'Elimination Count',
                    valueOrNotSet(eliminateCount),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _levelSettingRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: _primaryBlue),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.black54, fontSize: 11),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: _darkBlue,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: QuizMasterAppBar(
        title: 'Events Guidelines',
        subtitle: 'Code: $quizCode',
        badgeText: 'TECHNOWIZ • QUIZMASTER COMMAND',
        badgeIcon: Icons.checklist_rounded,
        onBack: () => Navigator.of(context).pop(),
      ),
      body: QuizMasterCircuitBackground(
        child: SafeArea(
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('quiz_sessions')
                .doc(quizCode)
                .snapshots(),
            builder: (context, quizSnapshot) {
              // Render the level/event details from the tapped card immediately,
              // then let the live Firestore snapshot refresh them when available.
              final quizData =
                  quizSnapshot.data?.data() ??
                  initialQuizData ??
                  <String, dynamic>{};
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('quiz_sessions')
                    .doc(quizCode)
                    .collection('join_requests')
                    .where('status', isEqualTo: 'approved')
                    .snapshots(),
                builder: (context, snapshot) {
                  final participants = snapshot.data?.docs ?? [];
                  final readyCount = participants
                      .where((doc) => doc.data()['ready'] == true)
                      .length;
                  final allReady =
                      participants.isNotEmpty &&
                      readyCount == participants.length;
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: ListView(
                                children: [
                                  _eventInformation(quizData),
                                  const SizedBox(height: 14),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed: () async {
                                  // Starting the quiz event from the overview
                                  // always begins at Level 1, resetting any stale
                                  // state from previous test runs.
                                  await onBeginQuizEvent();
                                  if (!context.mounted) return;

                                  final prefs =
                                      await SharedPreferences.getInstance();
                                  await prefs.setString(
                                    'technowiz_quizmaster_last_page',
                                    'participant_readiness',
                                  );
                                  await prefs.setString(
                                    'technowiz_quizmaster_current_quiz_code',
                                    quizCode,
                                  );
                                  if (!context.mounted) return;

                                  Navigator.of(context).push(
                                    PageRouteBuilder<void>(
                                      pageBuilder: (_, _, _) =>
                                          ContestantReadinessPage(
                                            quizCode: quizCode,
                                            startLevel: 1,
                                            onStartQuiz: () async {
                                              await onStartQuiz();
                                            },
                                            onReturnToSessions: () async {
                                              if (!context.mounted) return;
                                              Navigator.of(
                                                context,
                                              ).pushReplacement(
                                                PageRouteBuilder<void>(
                                                  pageBuilder: (_, _, _) =>
                                                      const QuizSessionsScreen(),
                                                  transitionDuration:
                                                      Duration.zero,
                                                  reverseTransitionDuration:
                                                      Duration.zero,
                                                  transitionsBuilder:
                                                      (
                                                        _,
                                                        animation,
                                                        secondaryAnimation,
                                                        child,
                                                      ) => child,
                                                ),
                                              );
                                            },
                                          ),
                                      transitionDuration: Duration.zero,
                                      reverseTransitionDuration: Duration.zero,
                                      transitionsBuilder:
                                          (
                                            _,
                                            animation,
                                            secondaryAnimation,
                                            child,
                                          ) => child,
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primaryBlue,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text('START QUIZ EVENT'),
                              ),
                            ),
                            if (!allReady)
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  'The quiz can start when all approved contestant are ready.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Separate participant readiness screen. The existing Quizmaster Overview
/// remains unchanged; its START THE QUIZ button opens this page.
