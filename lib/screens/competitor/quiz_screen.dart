import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'competitor_dashboard.dart';
import 'quiz_instructions_screen.dart';
import 'quiz_preparation_screen.dart';
import 'quiz_countdown_screen.dart';
import 'technowiz_theme.dart';

class QuizScreen extends StatefulWidget {
  final String quizCode;

  const QuizScreen({super.key, required this.quizCode});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  Timer? timer;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _contestantDecisionSubscription;
  String? _contestantDecision;
  int? _contestantDecisionLevel;
  int? _contestantDecisionRank;
  bool _showNextLevelInstructions = false;
  int? _nextLevelInstructionsLevel;

  // ==========================================================
  // CONTESTANT QUIZ PAGE PERSISTENCE
  // ==========================================================

  static const String _contestantLastPageKey = 'contestant_last_page';
  static const String _contestantQuizCodeKey = 'contestant_current_quiz_code';
  static const String _contestantQuizInstructionsKey =
      'contestant_quiz_instructions_viewed';
  static const String _contestantQuizNextReadyKey =
      'contestant_quiz_next_ready';
  static const String _contestantLastProceededLevelKey =
      'contestant_last_proceeded_level';

  int? _lastProceededDecisionLevel;
  bool _hasExitedToDashboard = false;
  bool _quizFinishedForContestant = false;

  void _handleQuizFinishedAndExit() {
    if (_hasExitedToDashboard) return;
    timer?.cancel();
    answered = true;
    submitting = false;
    if (mounted) {
      setState(() {
        _quizFinishedForContestant = true;
      });
    }
  }

  int timeLeft = 0;
  int previousQuestion = -1;

  int get currentQuestion {
    if (timerStartedForQuestion >= 0) {
      return timerStartedForQuestion;
    }
    final raw =
        int.tryParse(_latestQuizData['currentQuestion']?.toString() ?? '');
    if (raw != null && raw >= 0) {
      return raw;
    }
    if (previousQuestion >= 0) {
      return previousQuestion;
    }
    return 0;
  }

  // Fetch questions when QuizScreen opens and refresh if needed.
  late Future<QuerySnapshot> _questionsFuture;
  List<QueryDocumentSnapshot> _sortedSessionQuestions = const [];
  Map<String, dynamic> _latestQuizData = const {};
  bool _loadingSessionQuestions = false;

  @override
  void initState() {
    super.initState();
    // Start loading questions immediately when this screen is opened,
    // including while the synchronized countdown is still running.
    _loadSessionQuestions();
    _rememberQuizScreen();
    _restoreQuizLocalState();
    _listenForContestantDecision();
  }

  @override
  void reassemble() {
    super.reassemble();
    if (_sortedSessionQuestions.isEmpty) {
      _loadSessionQuestions();
    }
  }

  void _loadSessionQuestions() {
    if (_loadingSessionQuestions) return;
    _loadingSessionQuestions = true;
    _questionsFuture = FirebaseFirestore.instance
        .collection('quiz_sessions')
        .doc(widget.quizCode)
        .collection('questions')
        .get()
      ..then((snapshot) {
        _loadingSessionQuestions = false;
        final sorted = sortSessionQuestions(snapshot.docs);
        if (!mounted) return;
        setState(() {
          _sortedSessionQuestions = sorted;
        });
      }).catchError((Object e) {
        _loadingSessionQuestions = false;
        debugPrint('LOAD SESSION QUESTIONS ERROR: $e');
      });
  }

  void _listenForContestantDecision() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _contestantDecisionSubscription = _joinRequestRef(user.uid)
        .snapshots()
        .listen(
          (snapshot) async {
            final data = snapshot.data();
            if (data?['quizFinished'] == true ||
                data?['quizEnded'] == true ||
                data?['status'] == 'finished') {
              _handleQuizFinishedAndExit();
              return;
            }
            final decision = data?['contestantDecision']?.toString();
            final rawReadyForLevel = data?['readyForLevel'];
            final readyForLevel = rawReadyForLevel is num
                ? rawReadyForLevel.toInt()
                : int.tryParse(rawReadyForLevel?.toString() ?? '');

            final decisionLevel = int.tryParse(
              data?['decisionLevel']?.toString() ?? '',
            );

            final rawRank = data?['rank'] ??
                data?['levelRank'] ??
                data?['currentRank'] ??
                data?['rankAtProceed'] ??
                data?['rankAtElimination'];
            final int? assignedRank = rawRank is num
                ? rawRank.toInt()
                : int.tryParse(rawRank?.toString() ?? '');

            final int currentSessionLevel = int.tryParse(
                  _latestQuizData['currentLevel']?.toString() ?? '',
                ) ??
                1;

            final sessionStatus =
                _latestQuizData['status']?.toString().toLowerCase() ?? '';
            final isCountdown =
                _latestQuizData['countdownActive'] == true ||
                sessionStatus == 'countdown';
            final isActive = sessionStatus == 'active';
            final bool targetLevelIsActivelyPlaying = decisionLevel != null &&
                currentSessionLevel > decisionLevel &&
                (isActive || isCountdown);

            // Kung ang contestant nakapadayon na para ani nga decision level,
            // ayaw na sila ibalik sa decision screen o i-reset ang instructions.
            final bool alreadyProceededForLevel = decisionLevel != null &&
                ((_lastProceededDecisionLevel != null &&
                        _lastProceededDecisionLevel! >= decisionLevel) ||
                    (_nextLevelInstructionsLevel != null &&
                        _nextLevelInstructionsLevel! > decisionLevel) ||
                    (readyForLevel != null && readyForLevel > decisionLevel) ||
                    targetLevelIsActivelyPlaying);

            if (decision != 'proceeding' && decision != 'eliminated') {
              return;
            }

            if (decision == 'proceeding' && alreadyProceededForLevel) {
              if (!mounted) return;
              // If the target level has already actively begun playing, do NOT reopen instructions!
              if (targetLevelIsActivelyPlaying) {
                setState(() {
                  _contestantDecision = null;
                  _showNextLevelInstructions = false;
                  _nextLevelInstructionsLevel = null;
                });
                return;
              }
              final targetNext = decisionLevel + 1;
              setState(() {
                _contestantDecision = null;
                _showNextLevelInstructions = true;
                _nextLevelInstructionsLevel = targetNext;
                _showLocalLevelResults = false;
                answered = false;
                resultRevealed = false;
              });
              return;
            }

            // Show the decision immediately when Firestore publishes it.
            // Also retire the completed level's last question result/waiting
            // state so it cannot reappear when transitioning to the next level.
            if (!mounted) return;
            setState(() {
              _contestantDecision = decision;
              _contestantDecisionLevel = decisionLevel;
              if (assignedRank != null && assignedRank > 0) {
                _contestantDecisionRank = assignedRank;
                currentRank = assignedRank;
              }
              _showNextLevelInstructions = false;
              _showLocalLevelResults = false;
              answered = false;
              submitting = false;
              resultRevealed = false;
              nextReadyConfirmed = false;
              nextQuestionConfirmed = false;
              confirmedQuestionIndex = -1;
            });
            timer?.cancel();

            SharedPreferences.getInstance().then((prefs) async {
              if (prefs.getString(_contestantQuizCodeKey) == widget.quizCode) {
                await prefs.setBool(_contestantQuizNextReadyKey, false);
                await prefs.remove('contestant_quiz_confirmed_question');
              }
            });

            // Rank refresh is secondary UI data; it must never delay the
            // contestant's Proceeding/Eliminated decision screen.
            try {
              if (assignedRank == null || assignedRank <= 0) {
                final sessionSnap = await _sessionRef.get();
                final officialRanks = sessionSnap.data()?['officialRanks'];
                if (officialRanks is Map && officialRanks.containsKey(user.uid)) {
                  final offRank = officialRanks[user.uid];
                  final sRank = offRank is num ? offRank.toInt() : int.tryParse(offRank?.toString() ?? '');
                  if (sRank != null && sRank > 0 && mounted) {
                    setState(() {
                      _contestantDecisionRank = sRank;
                      currentRank = sRank;
                    });
                  }
                }

                if (_contestantDecisionRank == null || _contestantDecisionRank! <= 0) {
                  final scoreSnap = await _sessionRef
                      .collection('scores')
                      .doc(user.uid)
                      .get();
                  if (scoreSnap.exists) {
                    final sData = scoreSnap.data();
                    final sRaw = sData?['rank'] ??
                        sData?['levelRank'] ??
                        sData?['currentRank'] ??
                        sData?['rankAtProceed'];
                    final int? sRank = sRaw is num
                        ? sRaw.toInt()
                        : int.tryParse(sRaw?.toString() ?? '');
                    if (sRank != null && sRank > 0 && mounted) {
                      setState(() {
                        _contestantDecisionRank = sRank;
                        currentRank = sRank;
                      });
                    }
                  }
                }
              }
              await updateLiveRank();
            } catch (e) {
              debugPrint('REFRESH LIVE RANK AFTER DECISION ERROR: $e');
            }
          },
          onError: (Object error) {
            debugPrint('CONTESTANT DECISION LISTENER ERROR: $error');
          },
        );
  }

  Widget _contestantDecisionScreen({
    required bool eliminated,
    required int nextLevel,
    int? officialRank,
  }) {
    return TechCircuitBackground(
      baseColor: lightGreen,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TechArenaBadge(
                      label: eliminated
                          ? 'TECHNOWIZ • STAGE RESULT'
                          : 'TECHNOWIZ • ADVANCING TO LEVEL $nextLevel',
                      icon: eliminated
                          ? Icons.flag_rounded
                          : Icons.military_tech_rounded,
                    ),
                    const SizedBox(height: 24),
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: eliminated
                            ? const Color(0xFFFEE2E2)
                            : const Color(0xFFDCFCE7),
                        border: Border.all(
                          color: eliminated
                              ? const Color(0xFFFCA5A5)
                              : const Color(0xFF86EFAC),
                          width: 3.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (eliminated
                                    ? Colors.red
                                    : const Color(0xFF16A34A))
                                .withValues(alpha: 0.22),
                            blurRadius: 30,
                            spreadRadius: 3,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: eliminated
                                  ? const [
                                      Color(0xFFEF4444),
                                      Color(0xFFB91C1C),
                                    ]
                                  : const [
                                      Color(0xFF22C55E),
                                      Color(0xFF15803D),
                                    ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Icon(
                            eliminated
                                ? Icons.sentiment_dissatisfied_rounded
                                : Icons.emoji_events_rounded,
                            color: Colors.white,
                            size: 52,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      eliminated
                          ? "YOU'VE BEEN ELIMINATED"
                          : "CONGRATULATIONS!",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: eliminated ? const Color(0xFF991B1B) : darkGreen,
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      eliminated
                          ? "Thank you for participating! We appreciate your great effort and dedication."
                          : "You will be proceeding to Level $nextLevel!",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14.5,
                        height: 1.4,
                      ),
                    ),
                    if (eliminated) ...[
                      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: _sessionRef.snapshots(),
                        builder: (context, sessSnap) {
                          final sessData = sessSnap.data?.data();
                          final officialRanks = sessData?['officialRanks'];
                          final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
                          int? liveOfficialRank = officialRank;
                          if (officialRanks is Map && officialRanks.containsKey(myUid)) {
                            final raw = officialRanks[myUid];
                            final parsed = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
                            if (parsed != null && parsed > 0) {
                              liveOfficialRank = parsed;
                            }
                          }

                          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                            stream: _joinRequestRef(myUid).snapshots(),
                            builder: (context, reqSnap) {
                              final reqData = reqSnap.data?.data();
                              final rawRank = reqData?['rank'] ??
                                  reqData?['levelRank'] ??
                                  reqData?['currentRank'] ??
                                  reqData?['rankAtProceed'] ??
                                  reqData?['rankAtElimination'] ??
                                  _contestantDecisionRank;
                              final int? liveRank = rawRank is num
                                  ? rawRank.toInt()
                                  : int.tryParse(rawRank?.toString() ?? '');
                              final finalRank = liveOfficialRank ??
                                  liveRank ??
                                  (_contestantDecisionRank ??
                                      (currentRank > 0 ? currentRank : null));

                              if (finalRank == null) return const SizedBox.shrink();

                              return Padding(
                                padding: const EdgeInsets.only(top: 18),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: const Color(0xFFFECACA),
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.red.withValues(alpha: 0.08),
                                        blurRadius: 14,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.flag_rounded,
                                        size: 18,
                                        color: Colors.red.shade700,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'FINAL RANK: #$finalRank',
                                        style: TextStyle(
                                          color: Colors.red.shade900,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            timer?.cancel();
                            await _clearQuizScreenPersistence();
                            if (!mounted) return;
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute<void>(
                                builder: (_) => const CompetitorDashboard(),
                              ),
                              (route) => false,
                            );
                          },
                          icon: const Icon(Icons.dashboard_rounded, size: 20),
                          label: const Text(
                            'BACK TO DASHBOARD',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryGreen,
                            foregroundColor: Colors.white,
                            elevation: 3,
                            shadowColor: primaryGreen.withValues(alpha: 0.35),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (!eliminated) ...[
                      const SizedBox(height: 24),
                      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: _sessionRef.snapshots(),
                        builder: (context, sessSnap) {
                          final sessData = sessSnap.data?.data();
                          final officialRanks = sessData?['officialRanks'];
                          final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
                          int? liveOfficialRank = officialRank;
                          if (officialRanks is Map && officialRanks.containsKey(myUid)) {
                            final raw = officialRanks[myUid];
                            final parsed = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
                            if (parsed != null && parsed > 0) {
                              liveOfficialRank = parsed;
                            }
                          }

                          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                            stream: _joinRequestRef(myUid).snapshots(),
                            builder: (context, reqSnap) {
                              final reqData = reqSnap.data?.data();
                              final rawRank = reqData?['rank'] ??
                                  reqData?['levelRank'] ??
                                  reqData?['currentRank'] ??
                                  reqData?['rankAtProceed'] ??
                                  reqData?['rankAtElimination'] ??
                                  _contestantDecisionRank;
                              final int? liveRank = rawRank is num
                                  ? rawRank.toInt()
                                  : int.tryParse(rawRank?.toString() ?? '');
                              final finalRank = liveOfficialRank ??
                                  liveRank ??
                                  (_contestantDecisionRank ??
                                      (currentRank > 0 ? currentRank : null));

                              return Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 20,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                    color: const Color(0xFFBBF7D0),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF16A34A).withValues(alpha: 0.08),
                                      blurRadius: 18,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.emoji_events_rounded,
                                          size: 17,
                                          color: Colors.amber.shade700,
                                        ),
                                        const SizedBox(width: 7),
                                        Text(
                                          'RANK — LEVEL ${_contestantDecisionLevel ?? 1}',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1.1,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      finalRank != null
                                          ? 'RANK: #$finalRank'
                                          : (currentRank > 0 ? 'RANK: #$currentRank' : 'RANK: --'),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Color(0xFF14532D),
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            if (!mounted) return;

                            final nextLevel =
                                (_contestantDecisionLevel ?? 1) + 1;
                            final currentDecisionLevel =
                                _contestantDecisionLevel ?? 1;
                            final user = FirebaseAuth.instance.currentUser;

                            // Pressing PROCEED means this contestant
                            // has moved on and is ready while reading the
                            // next level's instructions. This lets the
                            // Quiz Master's readiness list update live.
                            if (user != null) {
                              try {
                                await _joinRequestRef(user.uid).set({
                                  'ready': true,
                                  'readyResponded': true,
                                  'readyAt': FieldValue.serverTimestamp(),
                                  'readyForLevel': nextLevel,
                                  'status': 'approved',
                                  'eliminated': false,
                                  'isEliminated': false,
                                  // Clear the completed level's decision
                                  // so the listener cannot replay the old
                                  // Congratulations page after moving on.
                                  'contestantDecision': FieldValue.delete(),
                                  'decisionLevel': FieldValue.delete(),
                                  'nextLevel': FieldValue.delete(),
                                  'decisionMessage': FieldValue.delete(),
                                  'decisionAt': FieldValue.delete(),
                                }, SetOptions(merge: true));
                              } catch (e) {
                                debugPrint(
                                  'SAVE NEXT LEVEL READY ERROR: $e',
                                );
                                if (!mounted) return;
                                showTopSnackBar(context, 
                                  const SnackBar(
                                    content: Text(
                                      'Unable to save your Level readiness. Please try again.',
                                    ),
                                  ),
                                );
                                return;
                              }
                            }

                            if (!mounted) return;
                            setState(() {
                              _lastProceededDecisionLevel = currentDecisionLevel;
                              _nextLevelInstructionsLevel = nextLevel;
                              _showNextLevelInstructions = true;
                              _showLocalLevelResults = false;
                              _contestantDecision = null;
                              contestantReady = true;
                              answered = false;
                              submitting = false;
                              resultRevealed = false;
                              nextReadyConfirmed = false;
                              nextQuestionConfirmed = false;
                              confirmedQuestionIndex = -1;
                              previousQuestion = currentQuestion;
                            });
                            SharedPreferences.getInstance().then((
                              prefs,
                            ) async {
                              if (prefs.getString(_contestantQuizCodeKey) ==
                                  widget.quizCode) {
                                await prefs.setBool(
                                  _contestantQuizNextReadyKey,
                                  false,
                                );
                                await prefs.remove('contestant_quiz_confirmed_question');
                                await prefs.setInt(
                                  _contestantLastProceededLevelKey,
                                  currentDecisionLevel,
                                );
                                await prefs.setInt(
                                  'contestant_next_instructions_level',
                                  nextLevel,
                                );
                              }
                            });
                          },
                          icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                          label: const Text(
                            'PROCEED',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.7,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryGreen,
                            foregroundColor: Colors.white,
                            elevation: 3,
                            shadowColor: primaryGreen.withValues(alpha: 0.35),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    const Text(
                      "TechNoWiz • Competition Arena",
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _rememberQuizScreen() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_contestantLastPageKey, 'quiz_screen');
    await prefs.setString(_contestantQuizCodeKey, widget.quizCode);
  }

  Future<void> _restoreQuizLocalState() async {
    final prefs = await SharedPreferences.getInstance();
    final savedQuizCode = prefs.getString(_contestantQuizCodeKey);

    if (savedQuizCode != widget.quizCode || !mounted) {
      return;
    }

    final instructionsViewed =
        prefs.getBool(_contestantQuizInstructionsKey) ?? false;
    final savedConfirmedQuestion =
        prefs.getInt('contestant_quiz_confirmed_question') ?? -1;
    final nextReady = (prefs.getBool(_contestantQuizNextReadyKey) ?? false) &&
        (savedConfirmedQuestion == currentQuestion);
    final savedProceededLevel =
        prefs.getInt(_contestantLastProceededLevelKey);
    final savedInstructionsLevel =
        prefs.getInt('contestant_next_instructions_level');

    if (!mounted) return;

    setState(() {
      instructionsShownThisSession = instructionsViewed;
      nextReadyConfirmed = nextReady;
      confirmedQuestionIndex = nextReady ? currentQuestion : -1;
      if (savedProceededLevel != null) {
        _lastProceededDecisionLevel = savedProceededLevel;
      }
      if (savedInstructionsLevel != null && savedInstructionsLevel > 1) {
        _nextLevelInstructionsLevel = savedInstructionsLevel;
      }
    });
  }

  Future<void> _clearQuizScreenPersistence() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_contestantLastPageKey);
    await prefs.remove(_contestantQuizCodeKey);
    await prefs.remove(_contestantQuizInstructionsKey);
    await prefs.remove(_contestantQuizNextReadyKey);
    await prefs.remove('contestant_quiz_confirmed_question');
    await prefs.remove(_contestantLastProceededLevelKey);
    await prefs.remove('contestant_next_instructions_level');
    await prefs.setString(_contestantLastPageKey, 'dashboard');
  }

  bool answered = false;
  bool submitting = false;
  bool showHurryUp = false;

  // Prevent a timer-expiry race when an answer is still being saved.
  bool _timerExpiredWhileSubmitting = false;

  // Set to true while the Quiz Master has the quiz manually paused.
  // Used to restart the question timer from the remaining seconds
  // when the Quiz Master resumes.
  bool wasPaused = false;

  // ==========================================================
  // RESULT STATE
  // ==========================================================

  // The result is revealed as soon as the contestant submits an answer
  // (or when the timer reaches 0 if the contestant did not answer).
  bool resultRevealed = false;

  bool currentAnswerTimedOut = false;

  // ==========================================================
  // CONTEST STATE
  // ==========================================================

  bool lastAnswerCorrect = false;
  bool contestSubmitting = false;
  bool contestProcessingApproval = false;

  String contestStatus = "none";
  String? contestRequestId;

  String? selectedAnswer;
  String currentCorrectAnswer = "";
  String currentQuestionType = "Multiple Choice";

  // The question currently being controlled by Quizmaster.
  // This always comes from quiz_sessions/{quizCode}/questions.
  Map<String, dynamic>? currentQuestionData;
  String? currentQuestionDocId;

  final TextEditingController answerInputController = TextEditingController();

  final TextEditingController contestExplanationController =
      TextEditingController();

  int currentScore = 0;
  int currentRank = 0;
  int totalPlayers = 0;

  // Cached level position for the result screen, which is rendered
  // before the questions FutureBuilder in build().
  int _currentLevelQuestionNumber = 0;
  int _currentLevelQuestionTotal = 0;
  int _currentQuestionLevel = 1;
  bool _showLocalLevelResults = false;

  // ==========================================================
  // READY CHECK / SYNCHRONIZED COUNTDOWN STATE
  // ==========================================================

  bool readyCheckDialogShown = false;
  bool contestantReady = false;
  String? lastReadyCheckId;

  // Shows the instructions only once during this quiz session.
  // Ready Check repeats for every question, but the instructions do not.
  bool showQuizInstructions = false;
  bool instructionsShownThisSession = false;

  // Internal flag: true when the contestant is allowed to move on from
  // the result screen to the next question. It is set automatically
  // when the Quiz Master moves on (next question / level pause / finish).
  bool nextQuestionConfirmed = false;
  String? nextQuestionReadySavedForId;
  String? readyStatusSavedForId;
  String? currentReadyCheckId;

  // NEW: true after the contestant presses CONFIRM on the result screen
  // ("YOU ARE READY?" card). CANCEL sets it back to false.
  bool nextReadyConfirmed = false;
  int confirmedQuestionIndex = -1;

  // Prevent the 30-second question timer from starting while
  // the Quiz Master is still running the ready check/countdown.
  int timerStartedForQuestion = -1;

  // Displayed countdown value coming from Firestore.
  int synchronizedCountdown = 0;

  // Keeps the GO screen visible during the short Firestore hand-off after
  // countdownActive becomes false, so the waiting room cannot flash briefly.
  bool _countdownWasActive = false;

  // First question only: once the initial countdown has started, do not send
  // the contestant back to Waiting Room while Firestore updates the first
  // question's status/timer in separate snapshots.
  bool _firstQuestionCountdownHandoff = false;

  static const Color primaryGreen = Color(0xFF16A34A);
  static const Color darkGreen = Color(0xFF166534);
  static const Color lightGreen = Color(0xFFF0FDF4);
  static const Color softGreen = Color(0xFFE8F7EC);
  static const Color borderGreen = Color(0xFFDCEFE1);
  static const Color textDark = Color(0xFF172033);

  // ==========================================================
  // LEVEL / POINTS
  // ==========================================================

  int getLevelFromQuestionNumber(int questionNumber) {
    if (questionNumber <= 0) return 1;
    return ((questionNumber - 1) ~/ 10) + 1;
  }

  int getLevelFromSessionQuestion(
    Map<String, dynamic> question, {
    int fallbackQuestionNumber = 1,
  }) {
    final raw = question['sessionLevel'] ?? question['level'];

    if (raw is num) {
      final value = raw.toInt();
      if (value > 0) return value;
    }

    final text = raw?.toString().trim() ?? '';
    final match = RegExp(r'(\d+)').firstMatch(text);

    if (match != null) {
      final value = int.tryParse(match.group(1)!);
      if (value != null && value > 0) return value;
    }

    return getLevelFromQuestionNumber(fallbackQuestionNumber);
  }

  int getPointsForLevel(int level) {
    switch (level) {
      case 1:
        return 1;
      case 2:
        return 2;
      case 3:
        return 3;
      default:
        return level > 0 ? level : 0;
    }
  }

  // ==========================================================
  // USER PROFILE CACHE FOR LIVE RANKING
  // ==========================================================
  static final Map<String, Map<String, dynamic>> _userProfileCache = {};

  void _prefetchUserProfile(String uid) {
    if (uid.isEmpty || _userProfileCache.containsKey(uid)) return;
    _userProfileCache[uid] = const {};
    FirebaseFirestore.instance.collection('users').doc(uid).get().then((snap) {
      if (snap.exists && snap.data() != null) {
        _userProfileCache[uid] = snap.data()!;
        if (mounted) setState(() {});
      }
    }).catchError((e) {
      debugPrint("PREFETCH USER ERROR: $e");
    });
  }

  // ==========================================================
  // USER NAME
  // ==========================================================

  Future<String> getUserName(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (doc.exists) {
        final data = doc.data();

        if (data != null && data['name'] != null) {
          return data['name'].toString();
        }
      }
    } catch (e) {
      debugPrint("GET USER NAME ERROR: $e");
    }

    final user = FirebaseAuth.instance.currentUser;

    return user?.displayName ?? uid;
  }

  // ==========================================================
  // NORMALIZE & MATCH HELPERS
  // ==========================================================

  String normalizeAnswer(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\u2010-\u2015]'), '-')
        .replaceAll(RegExp(r'[\u2018\u2019]'), "'")
        .replaceAll(RegExp(r'[\u201C\u201D]'), '"')
        .replaceAll(RegExp(r'\[|\{'), '(')
        .replaceAll(RegExp(r'\]|\}'), ')')
        .replaceAll(RegExp(r'\s*\(\s*'), ' ( ')
        .replaceAll(RegExp(r'\s*\)\s*'), ' ) ')
        .replaceAll(RegExp(r'\s*:\s*'), ' : ')
        .replaceAll(RegExp(r'\s*-\s*'), ' - ')
        .replaceAll(RegExp(r'\s*/\s*'), ' / ')
        .replaceAll(RegExp(r'\s*,\s*'), ' , ')
        .replaceAll(RegExp(r'(?<=\w)\.(?=\s|$)'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _stripPunctuation(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[\u2010-\u2015]'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _sortTokens(String value) {
    final tokens =
        _stripPunctuation(value).split(' ').where((t) => t.isNotEmpty).toList();
    tokens.sort();
    return tokens.join(' ');
  }

  List<String> getExpandedAnswerVariants(String rawAnswer) {
    final variants = <String>{};
    final trimmed = rawAnswer.trim();
    if (trimmed.isEmpty) return [];

    variants.add(trimmed);

    // 1. Parentheses/brackets: e.g. "DNS (Domain Name System)" or "DNS(Domain Name System)"
    final parenMatch =
        RegExp(r'^(.*?)\s*[\(\[\{](.*?)[\)\]\}]\s*$').firstMatch(trimmed);
    if (parenMatch != null) {
      final part1 = parenMatch.group(1)?.trim() ?? '';
      final part2 = parenMatch.group(2)?.trim() ?? '';
      if (part1.isNotEmpty && part2.isNotEmpty) {
        variants.add('$part1 ($part2)');
        variants.add('$part2 ($part1)');
        variants.add('$part1 - $part2');
        variants.add('$part2 - $part1');
        variants.add('$part1 $part2');
        variants.add('$part2 $part1');
        // Do NOT add part1 or part2 alone. The complete answer is required!
      }
    }

    // 2. Dash, colon, or slash: e.g. "DNS - Domain Name System"
    final delimMatch = RegExp(r'^(.*?)\s*[:\-\/]\s*(.*?)$').firstMatch(trimmed);
    if (delimMatch != null) {
      final part1 = delimMatch.group(1)?.trim() ?? '';
      final part2 = delimMatch.group(2)?.trim() ?? '';
      if (part1.isNotEmpty && part2.isNotEmpty) {
        variants.add('$part1 ($part2)');
        variants.add('$part2 ($part1)');
        variants.add('$part1 - $part2');
        variants.add('$part2 - $part1');
        variants.add('$part1 $part2');
        variants.add('$part2 $part1');
      }
    }

    return variants.toList();
  }

  bool _isAnswerMatch(String submitted, String accepted) {
    final subTrim = submitted.trim();
    final accTrim = accepted.trim();
    if (subTrim.isEmpty || accTrim.isEmpty) return false;

    // 1. Exact case-insensitive match
    if (subTrim.toLowerCase() == accTrim.toLowerCase()) {
      return true;
    }

    // 2. Spacing around delimiters normalized match
    final normSub = normalizeAnswer(subTrim);
    final normAcc = normalizeAnswer(accTrim);
    if (normSub == normAcc) {
      return true;
    }

    // 3. Punctuation stripped match
    final stripSub = _stripPunctuation(subTrim);
    final stripAcc = _stripPunctuation(accTrim);
    if (stripSub.isNotEmpty && stripSub == stripAcc) {
      return true;
    }

    // 4. Token-sorted match (handles "Domain Name System (DNS)" vs "DNS (Domain Name System)")
    final sortSub = _sortTokens(subTrim);
    final sortAcc = _sortTokens(accTrim);
    if (sortSub.isNotEmpty && sortSub == sortAcc) {
      return true;
    }

    return false;
  }

  // ==========================================================
  // QUESTION TYPE
  // ==========================================================

  String getQuestionType(Map<String, dynamic> question) {
    final type = question['questionType']?.toString().trim();

    if (type != null && type.isNotEmpty) {
      if (type.toLowerCase() == 'true/false' ||
          type.toLowerCase() == 'true or false') {
        return "True or False";
      }
      return type;
    }

    // Admin's assigned-session copy keeps the original answer/options
    // data even on older sessions where questionType was not copied.
    // Infer the type so the contestant still sees the correct UI.
    final options = question['options'];
    if (options is List && options.isNotEmpty) {
      return "Multiple Choice";
    }

    final rawCorrect = question['correctAnswer'];

    if (rawCorrect is List) {
      return "Enumeration";
    }

    final correctText = rawCorrect?.toString().trim().toLowerCase() ?? '';

    if (correctText == 'true' || correctText == 'false') {
      return "True or False";
    }

    return "Identification";
  }

  // ==========================================================
  // SESSION QUESTION ORDER
  //
  // IMPORTANT:
  // Only questions assigned by Admin to this quiz are used.
  // The Admin stores them in:
  // quiz_sessions/{quizCode}/questions/{questionId}
  // with sessionLevel + order.
  // ==========================================================

  List<QueryDocumentSnapshot> sortSessionQuestions(
    List<QueryDocumentSnapshot> docs,
  ) {
    // MUST match QuizControlScreen._sortSelectedQuestions exactly:
    // level -> order -> createdAt -> document ID.
    // currentQuestion is a global index into this sorted list.
    final sorted = [...docs];

    int getLevel(QueryDocumentSnapshot doc) {
      final data = doc.data() as Map<String, dynamic>;
      final raw = data['sessionLevel'] ?? data['level'];

      if (raw is num && raw.toInt() > 0) return raw.toInt();

      final text = raw?.toString().trim().toLowerCase() ?? '';
      final match = RegExp(r'\d+').firstMatch(text);
      if (match != null) {
        final parsed = int.tryParse(match.group(0)!);
        if (parsed != null && parsed > 0) return parsed;
      }

      // Keep missing levels at the end, as in QuizControlScreen.
      return 999999;
    }

    int? getOrder(QueryDocumentSnapshot doc) {
      final raw = (doc.data() as Map<String, dynamic>)['order'];
      if (raw is num) return raw.toInt();
      return int.tryParse(raw?.toString() ?? '');
    }

    DateTime? getCreatedAt(QueryDocumentSnapshot doc) {
      final raw = (doc.data() as Map<String, dynamic>)['createdAt'];
      if (raw is Timestamp) return raw.toDate();
      return null;
    }

    sorted.sort((a, b) {
      final levelCompare = getLevel(a).compareTo(getLevel(b));
      if (levelCompare != 0) return levelCompare;

      final aOrder = getOrder(a);
      final bOrder = getOrder(b);
      if (aOrder != null && bOrder != null && aOrder != bOrder) {
        return aOrder.compareTo(bOrder);
      }
      if (aOrder != null && bOrder == null) return -1;
      if (aOrder == null && bOrder != null) return 1;

      final aCreated = getCreatedAt(a);
      final bCreated = getCreatedAt(b);
      if (aCreated != null && bCreated != null) {
        final dateCompare = aCreated.compareTo(bCreated);
        if (dateCompare != 0) return dateCompare;
      } else if (aCreated != null) {
        return -1;
      } else if (bCreated != null) {
        return 1;
      }

      return a.id.compareTo(b.id);
    });

    return sorted;
  }

  // ==========================================================
  // QUESTION OPTIONS
  // ==========================================================

  List<String> getQuestionOptions(Map<String, dynamic> question) {
    final rawOptions = question['options'];

    if (rawOptions is List) {
      return rawOptions
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    return [
      question['optionA']?.toString().trim() ?? '',
      question['optionB']?.toString().trim() ?? '',
      question['optionC']?.toString().trim() ?? '',
      question['optionD']?.toString().trim() ?? '',
    ].where((e) => e.isNotEmpty).toList();
  }

  // ==========================================================
  // CORRECT ANSWER
  // ==========================================================

  String getCorrectAnswer(Map<String, dynamic> question) {
    final rawValue = question['correctAnswer'];

    if (rawValue is List) {
      return rawValue
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .join(', ');
    }

    final rawCorrect = rawValue?.toString().trim() ?? '';
    final options = getQuestionOptions(question);

    switch (rawCorrect.toUpperCase()) {
      case 'A':
        return options.isNotEmpty ? options[0] : rawCorrect;
      case 'B':
        return options.length > 1 ? options[1] : rawCorrect;
      case 'C':
        return options.length > 2 ? options[2] : rawCorrect;
      case 'D':
        return options.length > 3 ? options[3] : rawCorrect;
    }

    for (final option in options) {
      if (rawCorrect.toLowerCase() == option.toLowerCase()) {
        return option;
      }
    }

    return rawCorrect;
  }

  // ==========================================================
  // ACCEPTED ANSWERS
  // ==========================================================

  List<String> getAcceptedAnswers(Map<String, dynamic> question) {
    // IMPORTANT:
    // Always include the Admin's main correctAnswer and expanded variants.
    // Handles parentheses (e.g. "DNS (Domain Name System)"), acronyms,
    // swapped word orders, and punctuation-spacing variations.
    final accepted = <String>{};

    void addAnswer(dynamic value) {
      if (value == null) return;
      if (value is List) {
        for (final item in value) {
          addAnswer(item);
        }
        return;
      }

      final raw = value.toString().trim();
      if (raw.isEmpty) return;

      final variants = getExpandedAnswerVariants(raw);
      for (final v in variants) {
        final normalized = normalizeAnswer(v);
        if (normalized.isNotEmpty) {
          accepted.add(normalized);
        }
      }
    }

    // Main Admin answer — MUST be accepted first.
    addAnswer(question['correctAnswer']);

    // Also accept the resolved/displayed answer.
    final resolvedCorrectAnswer = getCorrectAnswer(question);
    if (resolvedCorrectAnswer.isNotEmpty) {
      addAnswer(resolvedCorrectAnswer);
    }

    // Additional accepted/alternate answers, if Admin stored them.
    addAnswer(question['correctAnswers']);
    addAnswer(question['answer']);
    addAnswer(question['acceptedAnswers']);
    addAnswer(question['alternateAnswers']);

    return accepted.toList();
  }

  // ==========================================================
  // ENUMERATION
  // ==========================================================

  List<String> parseEnumerationAnswers(String input) {
    return input
        .split(RegExp(r'[,;\n]'))
        .map((s) => s.trim())
        .where((answer) => answer.isNotEmpty)
        .toList();
  }

  List<String> getEnumerationCorrectItems(Map<String, dynamic> question) {
    final items = <String>[];
    void extract(dynamic val) {
      if (val == null) return;
      if (val is List) {
        for (final item in val) {
          extract(item);
        }
        return;
      }
      final str = val.toString().trim();
      if (str.isEmpty) return;
      if (str.contains(',') || str.contains(';') || str.contains('\n')) {
        final split = str
            .split(RegExp(r'[,;\n]'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty);
        items.addAll(split);
      } else {
        items.add(str);
      }
    }

    extract(question['correctAnswer']);
    if (items.isEmpty) {
      extract(question['correctAnswers']);
    }
    return items;
  }

  // ==========================================================
  // CHECK ANSWER
  // ==========================================================

  bool isAnswerCorrect(Map<String, dynamic> question, String submittedAnswer) {
    final questionType = getQuestionType(question);

    if (submittedAnswer.trim().isEmpty) {
      return false;
    }

    if (questionType == "Enumeration") {
      final submittedAnswers = parseEnumerationAnswers(submittedAnswer);
      final correctItems = getEnumerationCorrectItems(question);

      if (submittedAnswers.isEmpty || correctItems.isEmpty) {
        return false;
      }

      if (submittedAnswers.length != correctItems.length) {
        return false;
      }

      final matchedIndices = <int>{};
      for (final sub in submittedAnswers) {
        int found = -1;
        for (int i = 0; i < correctItems.length; i++) {
          if (!matchedIndices.contains(i)) {
            final variants = getExpandedAnswerVariants(correctItems[i]);
            bool match = _isAnswerMatch(sub, correctItems[i]);
            if (!match) {
              for (final v in variants) {
                if (_isAnswerMatch(sub, v)) {
                  match = true;
                  break;
                }
              }
            }
            if (match) {
              found = i;
              break;
            }
          }
        }
        if (found != -1) {
          matchedIndices.add(found);
        } else {
          return false;
        }
      }

      return matchedIndices.length == correctItems.length;
    }

    if (questionType == "Identification") {
      final acceptedList = getAcceptedAnswers(question);
      for (final accepted in acceptedList) {
        if (_isAnswerMatch(submittedAnswer, accepted)) {
          return true;
        }
      }
      return false;
    }

    if (questionType == "True or False") {
      final sub = submittedAnswer.trim().toLowerCase();
      final cor = getCorrectAnswer(question).trim().toLowerCase();
      if (sub == cor) return true;
      if ((sub == "true" || sub == "t") && (cor == "true" || cor == "t")) {
        return true;
      }
      if ((sub == "false" || sub == "f") && (cor == "false" || cor == "f")) {
        return true;
      }
      return _isAnswerMatch(submittedAnswer, cor);
    }

    final correctAnswer = getCorrectAnswer(question);
    if (_isAnswerMatch(submittedAnswer, correctAnswer)) {
      return true;
    }

    final acceptedList = getAcceptedAnswers(question);
    for (final accepted in acceptedList) {
      if (_isAnswerMatch(submittedAnswer, accepted)) {
        return true;
      }
    }

    return false;
  }

  // ==========================================================
  // START TIMER
  //
  // IMPORTANT:
  // The timer belongs to the current question.
  //
  // Submitting an answer stops the timer and the result is
  // revealed right away. If the contestant does not answer, the
  // result is revealed when the timer reaches 0.
  //
  // startFrom lets the timer continue from the remaining seconds
  // after the Quiz Master resumes a manual pause.
  // ==========================================================

  void startTimer({int startFrom = 0}) {
    timer?.cancel();
    if (_hasExitedToDashboard) return;

    previousQuestion = currentQuestion;
    nextQuestionConfirmed = false;
    nextReadyConfirmed = false;
    confirmedQuestionIndex = -1;

    timeLeft = startFrom;
    showHurryUp = startFrom <= 5 && startFrom > 0 && !answered;

    if (mounted) {
      setState(() {});
    }

    timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (timeLeft > 0) {
        setState(() {
          timeLeft--;

          if (timeLeft == 5) {
            showHurryUp = true;
          }
        });

        return;
      }

      // ======================================================
      // TIME IS FINISHED
      // ======================================================

      timer.cancel();

      if (!answered && submitting) {
        // The contestant submitted just as the timer reached zero.
        // Wait for saveAnswer() to finish, then reveal the saved result.
        _timerExpiredWhileSubmitting = true;
        return;
      }

      if (!answered) {
        // No answer was saved before time expired. Save an unanswered
        // response and let saveAnswer() reveal the result after the write.
        await saveAnswer(currentQuestion, "", timedOut: true);
      } else {
        revealResult();
      }
    });
  }

  // ==========================================================
  // REVEAL RESULT
  // ==========================================================

  void revealResult() {
    if (!mounted) return;

    timer?.cancel();

    setState(() {
      previousQuestion = currentQuestion;
      resultRevealed = true;
      showHurryUp = false;
      nextQuestionConfirmed = false;
      nextReadyConfirmed = false;
      confirmedQuestionIndex = -1;
    });

    updateLiveRank();

    // Result is visible, but the contestant has NOT confirmed yet.
    // Only the CONFIRM button sets resultConfirmed to true.
    saveResultConfirmed(false);
  }

  // ==========================================================
  // HURRY UP
  // ==========================================================

  Widget hurryUpBanner() {
    if (!showHurryUp || answered) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      color: Colors.red,
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.warning_rounded, color: Colors.white, size: 25),
          SizedBox(width: 9),
          Text(
            "HURRY! ONLY 5 SECONDS LEFT!",
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // READY CHECK / SYNCHRONIZED COUNTDOWN
  // ==========================================================

  DocumentReference<Map<String, dynamic>> get _sessionRef => FirebaseFirestore
      .instance
      .collection('quiz_sessions')
      .doc(widget.quizCode);

  DocumentReference<Map<String, dynamic>> _joinRequestRef(String uid) =>
      _sessionRef.collection('join_requests').doc(uid);

  Future<void> saveReadyStatus({
    required bool ready,
    required String readyCheckId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    try {
      await _joinRequestRef(user.uid).set({
        'ready': ready,
        'readyCheckId': readyCheckId,
        'status': 'approved',
        'readyAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      setState(() {
        contestantReady = ready;
      });
    } catch (e) {
      debugPrint("SAVE READY STATUS ERROR: $e");

      if (!mounted) return;

      showTopSnackBar(context, 
        SnackBar(
          content: Text("Unable to save ready status: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ==========================================================
  // RESULT CONFIRMED
  //
  // Saved AUTOMATICALLY as soon as the contestant sees the
  // result (no button needed). The Quiz Master shows a green check
  // once this is true for the current question.
  // ==========================================================

  Future<void> saveResultConfirmed(bool confirmed) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    try {
      await _joinRequestRef(user.uid).set({
        'resultConfirmed': confirmed,
        'resultConfirmedQuestion': previousQuestion,
        'resultConfirmedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("SAVE RESULT CONFIRMED ERROR: $e");
    }
  }

  // ==========================================================
  // NEXT QUESTION READY (CONFIRM / CANCEL ON RESULT SCREEN)
  //
  // CONFIRM -> nextQuestionReady: true
  // CANCEL  -> nextQuestionReady: false
  //
  // Quiz Master side can read:
  //   join_requests/{uid}.nextQuestionReady == true
  //   join_requests/{uid}.nextQuestionReadyFor == currentQuestion + 1
  // ==========================================================

  Future<void> setNextQuestionReady(bool ready) async {
    setState(() {
      nextReadyConfirmed = ready;
      confirmedQuestionIndex = ready ? currentQuestion : -1;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_contestantLastPageKey, 'quiz_screen');
    await prefs.setString(_contestantQuizCodeKey, widget.quizCode);
    await prefs.setBool(_contestantQuizNextReadyKey, ready);
    await prefs.setInt(
      'contestant_quiz_confirmed_question',
      ready ? currentQuestion : -1,
    );

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await _joinRequestRef(user.uid).set({
        'nextQuestionReady': ready,
        // 0-based index of the next question
        'nextQuestionReadyFor': previousQuestion + 1,
        'nextQuestionReadyAt': FieldValue.serverTimestamp(),
        // The Quiz Master's "CONTESTANT CONFIRMATION" card reads these.
        'resultConfirmed': ready,
        'resultConfirmedQuestion': previousQuestion,
        'resultConfirmedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("SAVE NEXT READY ERROR: $e");

      if (!mounted) return;

      setState(() {
        nextReadyConfirmed = !ready; // revert if it failed
        confirmedQuestionIndex = !ready ? currentQuestion : -1;
      });

      showTopSnackBar(context, 
        SnackBar(
          content: Text("Unable to save ready status: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ==========================================================
  // CANCEL ON RESULT SCREEN
  //
  // The contestant does NOT continue to the next question.
  // They are taken back to the contestant dashboard.
  // ==========================================================

  Future<void> cancelAndLeave() async {
    await _leaveQuizAndRequireApproval();
  }

  /// Records a real departure from this quiz before navigating away.
  /// The join-request / admin approval flow must treat status == "left"
  /// as requiring a fresh request and explicit approval.
  Future<void> _leaveQuizAndRequireApproval() async {
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      showTopSnackBar(context, 
        const SnackBar(
          content: Text('Please sign in again before leaving the quiz.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    timer?.cancel();

    try {
      await _joinRequestRef(user.uid).set({
        'status': 'left',
        'approved': false,
        'leftQuiz': true,
        'leftAt': FieldValue.serverTimestamp(),
        'ready': false,
        'nextQuestionReady': false,
        'resultConfirmed': false,
        'cancelledNextQuestion': true,
        'cancelledAfterQuestion': previousQuestion + 1,
        'contestantDecision': FieldValue.delete(),
        'decisionLevel': FieldValue.delete(),
      }, SetOptions(merge: true));

      await _clearQuizScreenPersistence();

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('LEAVE QUIZ ERROR: $e');
      if (!mounted) return;

      showTopSnackBar(context, 
        const SnackBar(
          content: Text(
            'Could not leave the quiz safely. Please check your connection and try again.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<bool> hasViewedInstructions() async {
    // IMPORTANT:
    // This local flag is the source of truth for the current quiz session.
    // It prevents the instructions from appearing again on Question 2,
    // Question 3, and all succeeding questions.
    return instructionsShownThisSession;
  }

  Future<void> markInstructionsViewed() async {
    // Mark immediately in local state. Do NOT reset this when a new
    // Ready Check starts, because the instructions are one-time only.
    instructionsShownThisSession = true;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_contestantLastPageKey, 'quiz_screen');
    await prefs.setString(_contestantQuizCodeKey, widget.quizCode);
    await prefs.setBool(_contestantQuizInstructionsKey, true);

    // Keep the Firestore flag as metadata, but it does not control the
    // one-time display during the current QuizScreen session.
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    try {
      await _joinRequestRef(user.uid).set({
        'instructionsViewed': true,
        'instructionsViewedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("SAVE INSTRUCTIONS ERROR: $e");
      // Do not block the quiz if this metadata save fails.
    }
  }

  Future<void> showReadyCheckDialog({required String readyCheckId}) async {
    // Deprecated: contestants no longer receive the old "Are You Ready?"
    // popup. Readiness is handled by the Instructions/result CONFIRM flow.
    currentReadyCheckId = readyCheckId;
  }

  String _currentReadyCheckId() {
    return currentReadyCheckId?.trim() ?? '';
  }

  Widget readyWaitingScreen({
    required int currentQuestion,
    bool levelStart = false,
    int currentLevel = 1,
    Map<String, dynamic>? quizData,
  }) {
    timer?.cancel();

    // The CONFIRM + Instructions screens are for Question 1 ONLY.
    // From Question 2 on, contestants see the result (with CONFIRM / CANCEL)
    // and then wait for the Quiz Master's countdown.
    final bool isFirstQuestion = currentQuestion == 0;

    // A level start uses a waiting page without a readiness button.
    // The Quiz Master's existing readiness timeout/countdown remains unchanged.
    if (levelStart) {
      return TechCircuitBackground(
        baseColor: lightGreen,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            centerTitle: true,
            automaticallyImplyLeading: false,
            title: const Text(
              "Get Ready",
              style: TextStyle(color: textDark, fontWeight: FontWeight.bold),
            ),
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 115,
                    height: 115,
                    decoration: const BoxDecoration(
                      color: softGreen,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.rocket_launch_rounded,
                      color: primaryGreen,
                      size: 62,
                    ),
                  ),
                  const SizedBox(height: 25),
                  const Text(
                    "QUIZ IS ABOUT TO START!",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: darkGreen,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Level $currentLevel is about to begin. Please get ready!",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // ==========================================================
    // FIRST READY CHECK: CONFIRM FIRST, THEN INSTRUCTIONS
    // ==========================================================
    // When the Quiz Master sends the first Ready Check, the contestant
    // must first press CONFIRM. Only after that click are the quiz
    // instructions shown. There is NO second instruction confirmation.
    if (isFirstQuestion &&
        !instructionsShownThisSession &&
        !showQuizInstructions) {
      return TechCircuitBackground(
        baseColor: lightGreen,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            centerTitle: true,
            automaticallyImplyLeading: false,
            title: const Text(
              "Ready Check",
              style: TextStyle(color: textDark, fontWeight: FontWeight.bold),
            ),
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 115,
                    height: 115,
                    decoration: const BoxDecoration(
                      color: softGreen,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle_outline_rounded,
                      color: primaryGreen,
                      size: 68,
                    ),
                  ),
                  const SizedBox(height: 25),
                  const Text(
                    "YOU ARE READY?",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: darkGreen,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Press CONFIRM to continue. Quiz instructions will appear before Question 1.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final readyCheckId = _currentReadyCheckId();
                        if (readyCheckId.isEmpty) return;

                        // This first CONFIRM is the only confirmation before
                        // the Instructions. No second button is required.
                        await saveReadyStatus(
                          ready: true,
                          readyCheckId: readyCheckId,
                        );
                        await markInstructionsViewed();

                        if (!mounted) return;
                        setState(() {
                          showQuizInstructions = true;
                          contestantReady = true;
                          readyStatusSavedForId = readyCheckId;
                          lastReadyCheckId = readyCheckId;
                        });
                      },
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      label: const Text(
                        "CONFIRM",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // ==========================================================
    // QUIZ INSTRUCTIONS (QUESTION 1 ONLY)
    // ==========================================================

    if (isFirstQuestion && showQuizInstructions) {
      return QuizInstructionsScreen(
        quizData: quizData ?? <String, dynamic>{},
        level: currentLevel,
        quizCode: widget.quizCode,
      );
    }

  // ==========================================================
  // PLEASE WAIT FOR QUIZ MASTER
  // ==========================================================

  return TechCircuitBackground(
    baseColor: lightGreen,
    child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: const Text(
          "Waiting",
          style: TextStyle(color: textDark, fontWeight: FontWeight.bold),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 115,
                height: 115,
                decoration: const BoxDecoration(
                  color: softGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.hourglass_top_rounded,
                  color: primaryGreen,
                  size: 68,
                ),
              ),
              const SizedBox(height: 25),
              const Text(
                "PLEASE WAIT",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: darkGreen,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "Please wait for the Quiz Master to start the quiz.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16, height: 1.5),
              ),
              const SizedBox(height: 25),
              const CircularProgressIndicator(color: primaryGreen),
            ],
          ),
        ),
      ),
    ),
  );
  }

  Widget synchronizedCountdownScreen(int countdown, {int questionNumber = 1}) {
    timer?.cancel();
    int activeLevel = _currentQuestionLevel;
    if (activeLevel <= 0 && previousQuestion >= 0) {
      final pos = _getLevelPositionForGlobalIndex(previousQuestion);
      activeLevel = pos.level;
    }
    if (activeLevel <= 0) {
      final parsed =
          int.tryParse(_latestQuizData['currentLevel']?.toString() ?? '');
      if (parsed != null && parsed > 0) activeLevel = parsed;
    }
    if (activeLevel <= 0) activeLevel = 1;

    return QuizCountdownScreen(
      countdown: countdown,
      questionNumber: questionNumber,
      currentLevel: activeLevel,
    );
  }

  // ==========================================================
  // RESET CONTEST STATE
  // ==========================================================

  void resetContestState() {
    contestStatus = "none";
    contestRequestId = null;
    lastAnswerCorrect = false;
    contestSubmitting = false;
    contestProcessingApproval = false;
    nextReadyConfirmed = false; // NEW: reset CONFIRM state per question
  }

  // ==========================================================
  // LOAD EXISTING RESPONSE
  // ==========================================================

  Future<void> loadExistingResponse(int questionIndex) async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return;
    }

    try {
      final responseRef = FirebaseFirestore.instance
          .collection('quiz_sessions')
          .doc(widget.quizCode)
          .collection('answers')
          .doc(currentUser.uid)
          .collection('responses')
          .doc('question_$questionIndex');

      final responseSnapshot = await responseRef.get();

      if (!responseSnapshot.exists || !mounted) {
        return;
      }

      final data = responseSnapshot.data();

      if (data == null) {
        return;
      }

      final savedContestStatus = data['contestStatus']?.toString() ?? "none";

      final savedAnswerStatus = data['answerStatus']?.toString() ?? "";

      final savedAnswer = data['selectedAnswer']?.toString() ?? '';

      bool isCurrentlyCorrect =
          data['isCorrect'] == true || savedAnswerStatus == "correct";

      final Map<String, dynamic>? questionForEval = currentQuestionData ??
          (questionIndex < _sortedSessionQuestions.length
              ? _sortedSessionQuestions[questionIndex].data()
                  as Map<String, dynamic>?
              : null);

      if (questionForEval != null && savedAnswer.trim().isNotEmpty) {
        final bool shouldBeCorrect =
            isAnswerCorrect(questionForEval, savedAnswer);

        if (isCurrentlyCorrect &&
            !shouldBeCorrect &&
            savedContestStatus != "approved") {
          // If an answer is incomplete (e.g. only "CPU" when "CPU (Central Processing Unit)" was required),
          // ensure it is marked WRONG with 0 points.
          isCurrentlyCorrect = false;
          final int existingPoints = (data['points'] as num?)?.toInt() ?? 0;
          try {
            responseRef.update({
              'isCorrect': false,
              'answerStatus': 'wrong',
              'points': 0,
              'autoCorrected': true,
              'updatedAt': FieldValue.serverTimestamp(),
            }).catchError((e) {
              debugPrint("CORRECT TO WRONG RESPONSE ERROR: $e");
            });
            if (existingPoints > 0) {
              updateScore(currentUser.uid, -existingPoints, questionIndex + 1)
                  .catchError((e) {
                debugPrint("DEDUCT INCOMPLETE SCORE ERROR: $e");
              });
            }
          } catch (e) {
            debugPrint("CORRECT TO WRONG EVAL ERROR: $e");
          }
        } else if (!isCurrentlyCorrect && shouldBeCorrect) {
          // If an answer is complete (e.g. "DNS(Domain Name System)"),
          // self-heal and award points.
          isCurrentlyCorrect = true;
          try {
            final sessionLevel = getLevelFromSessionQuestion(
              questionForEval,
              fallbackQuestionNumber: questionIndex + 1,
            );
            final earnedPoints = getPointsForLevel(sessionLevel);
            responseRef.update({
              'isCorrect': true,
              'answerStatus': 'correct',
              'points': earnedPoints,
              'autoCorrected': true,
              'updatedAt': FieldValue.serverTimestamp(),
            }).catchError((e) {
              debugPrint("AUTO-CORRECT RESPONSE UPDATE ERROR: $e");
            });
            updateScore(currentUser.uid, earnedPoints, questionIndex + 1)
                .catchError((e) {
              debugPrint("AUTO-CORRECT UPDATE SCORE ERROR: $e");
            });
          } catch (e) {
            debugPrint("AUTO-CORRECT EVAL ERROR: $e");
          }
        }
      }

      setState(() {
        answered = true;

        lastAnswerCorrect = isCurrentlyCorrect;

        contestStatus = savedContestStatus;

        contestRequestId = data['contestRequestId']?.toString();

        currentAnswerTimedOut = data['timedOut'] == true;

        if (currentQuestionType == "Identification" ||
            currentQuestionType == "Enumeration") {
          answerInputController.text = savedAnswer;
        } else {
          selectedAnswer = savedAnswer.isEmpty ? null : savedAnswer;
        }

        // Existing response means the answer has already
        // been processed. Reveal its result.
        resultRevealed = true;
      });

      if (contestStatus == "approved" &&
          !lastAnswerCorrect &&
          savedAnswerStatus == "contested") {
        await applyApprovedContest(questionIndex: questionIndex);
      }
    } catch (e) {
      debugPrint("LOAD EXISTING RESPONSE ERROR: $e");
    }
  }

  // ==========================================================
  // SAVE ANSWER
  //
  // IMPORTANT:
  // Submitting an answer locks it AND reveals the result right
  // away. The timer is stopped for this contestant.
  // ==========================================================

  Future<void> saveAnswer(
    int questionIndex,
    String answer, {
    bool timedOut = false,
  }) async {
    if (answered || submitting) {
      return;
    }

    setState(() {
      submitting = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser == null) {
        if (mounted) {
          setState(() {
            submitting = false;
          });
        }

        return;
      }

      final uid = currentUser.uid;

      final questionNumber = questionIndex + 1;

      final answerDoc = FirebaseFirestore.instance
          .collection('quiz_sessions')
          .doc(widget.quizCode)
          .collection('answers')
          .doc(uid);

      final responseRef = answerDoc
          .collection('responses')
          .doc('question_$questionIndex');

      final existingResponse = await responseRef.get();

      if (existingResponse.exists) {
        final existingData = existingResponse.data();

        if (mounted) {
          setState(() {
            answered = true;
            submitting = false;
            showHurryUp = false;
            resultRevealed = true;

            if (existingData != null) {
              final savedAnswer =
                  existingData['selectedAnswer']?.toString() ?? '';
              final savedContestStatus =
                  existingData['contestStatus']?.toString() ?? "none";
              bool isCurrentlyCorrect = existingData['isCorrect'] == true ||
                  existingData['answerStatus'] == "correct";

              final Map<String, dynamic>? questionForEval =
                  currentQuestionData ??
                      (questionIndex < _sortedSessionQuestions.length
                          ? _sortedSessionQuestions[questionIndex].data()
                              as Map<String, dynamic>?
                          : null);

              if (questionForEval != null && savedAnswer.trim().isNotEmpty) {
                final bool shouldBeCorrect =
                    isAnswerCorrect(questionForEval, savedAnswer);

                if (isCurrentlyCorrect &&
                    !shouldBeCorrect &&
                    savedContestStatus != "approved") {
                  // Incomplete answer (e.g. "CPU"): Mark WRONG and deduct points if awarded
                  isCurrentlyCorrect = false;
                  final int existingPoints =
                      (existingData['points'] as num?)?.toInt() ?? 0;
                  responseRef.update({
                    'isCorrect': false,
                    'answerStatus': 'wrong',
                    'points': 0,
                    'autoCorrected': true,
                    'updatedAt': FieldValue.serverTimestamp(),
                  }).catchError((e) {
                    debugPrint("CORRECT TO WRONG RESPONSE ERROR: $e");
                  });
                  if (existingPoints > 0) {
                    updateScore(uid, -existingPoints, questionNumber)
                        .catchError((e) {
                      debugPrint("DEDUCT INCOMPLETE SCORE ERROR: $e");
                    });
                  }
                } else if (!isCurrentlyCorrect && shouldBeCorrect) {
                  // Complete answer (e.g. "DNS(Domain Name System)"): Mark CORRECT
                  isCurrentlyCorrect = true;
                  final sessionLevel = getLevelFromSessionQuestion(
                    questionForEval,
                    fallbackQuestionNumber: questionNumber,
                  );
                  final earnedPoints = getPointsForLevel(sessionLevel);
                  responseRef.update({
                    'isCorrect': true,
                    'answerStatus': 'correct',
                    'points': earnedPoints,
                    'autoCorrected': true,
                    'updatedAt': FieldValue.serverTimestamp(),
                  }).catchError((e) {
                    debugPrint("AUTO-CORRECT RESPONSE UPDATE ERROR: $e");
                  });
                  updateScore(uid, earnedPoints, questionNumber)
                      .catchError((e) {
                    debugPrint("AUTO-CORRECT UPDATE SCORE ERROR: $e");
                  });
                }
              }

              lastAnswerCorrect = isCurrentlyCorrect;

              contestStatus = savedContestStatus;

              contestRequestId = existingData['contestRequestId']?.toString();

              currentAnswerTimedOut = existingData['timedOut'] == true;
            }
          });
        }

        return;
      }

      // ======================================================
      // USE THE CURRENT ADMIN-ASSIGNED SESSION QUESTION
      // ======================================================

      final question = currentQuestionData ??
          (questionIndex >= 0 && questionIndex < _sortedSessionQuestions.length
              ? _sortedSessionQuestions[questionIndex].data()
                  as Map<String, dynamic>?
              : null);

      if (question == null || questionIndex < 0) {
        if (mounted) {
          setState(() {
            submitting = false;
          });
        }

        return;
      }

      final questionType = getQuestionType(question);

      final correctAnswer = getCorrectAnswer(question);

      // If the timer expires, evaluate the answer the contestant had
      // selected/typed instead of forcing every timed-out response wrong.
      // A truly empty answer remains unanswered and earns no points.
      final String effectiveAnswer = timedOut
          ? ((questionType == "Identification" || questionType == "Enumeration")
                ? answerInputController.text.trim()
                : (selectedAnswer?.trim() ?? ''))
          : answer.trim();

      final bool hasAnswer = effectiveAnswer.trim().isNotEmpty;
      final bool correct =
          hasAnswer && isAnswerCorrect(question, effectiveAnswer);

      final sessionLevel = getLevelFromSessionQuestion(
        question,
        fallbackQuestionNumber: questionNumber,
      );
      final earnedPoints = correct ? getPointsForLevel(sessionLevel) : 0;

      await answerDoc.set({
        'uid': uid,
        'submitted': true,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await responseRef.set({
        'questionNumber': questionNumber,
        'level': sessionLevel,
        'questionType': questionType,
        'selectedAnswer': effectiveAnswer,
        'correctAnswer': correctAnswer,
        'correctAnswers': question['correctAnswers'],
        'isCorrect': correct,
        'answerStatus': !hasAnswer
            ? 'unanswered'
            : (correct ? 'correct' : 'wrong'),
        'contestStatus': 'none',
        'points': earnedPoints,
        'timedOut': timedOut,
        'answeredAt': FieldValue.serverTimestamp(),
      });

      if (correct) {
        await updateScore(uid, earnedPoints, questionNumber);
      }

      if (!mounted) return;

      // IMPORTANT: do NOT cancel the timer here. The contestant must
      // wait until the timer reaches 0 before the result is revealed.

      setState(() {
        answered = true;
        submitting = false;
        showHurryUp = false;
        previousQuestion = currentQuestion;
        nextQuestionConfirmed = false;
        nextReadyConfirmed = false;
        confirmedQuestionIndex = -1;

        lastAnswerCorrect = correct;

        currentAnswerTimedOut = timedOut;

        contestStatus = "none";
        contestRequestId = null;

        // ====================================================
        // After submitting, the result stays hidden until the
        // timer reaches 0. startTimer() calls revealResult()
        // at 0. If this save came from the timer running out
        // (timedOut), reveal right away.
        // ====================================================

        resultRevealed = timedOut || _timerExpiredWhileSubmitting;
        _timerExpiredWhileSubmitting = false;
      });

      if (timedOut || resultRevealed) {
        updateLiveRank();

        // Not confirmed yet. Only the CONFIRM button confirms.
        saveResultConfirmed(false);
      }
    } catch (e) {
      debugPrint("SAVE ANSWER ERROR: $e");

      if (mounted) {
        setState(() {
          submitting = false;
        });

        showTopSnackBar(context, 
          SnackBar(
            content: Text("Error saving answer: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ==========================================================
  // RESULT SCREEN
  // ==========================================================

  Widget resultScreen({
    required int points,
    required bool readyCheckActive,
    required String readyCheckId,
    bool isLastQuestionInLevel = false,
    int currentLevel = 1,
  }) {
    timer?.cancel();

    final bool isThisQuestionConfirmed =
        nextReadyConfirmed && (confirmedQuestionIndex == currentQuestion);

    if (isLastQuestionInLevel && isThisQuestionConfirmed) {
      return levelPauseScreen(currentLevel);
    }

    if (isThisQuestionConfirmed &&
        !isLastQuestionInLevel &&
        _contestantDecision != 'proceeding' &&
        _contestantDecision != 'eliminated' &&
        !_showNextLevelInstructions) {
      return _greenWaitingForNextQuestionScreen();
    }

    final yourAnswer =
        currentQuestionType == "Identification" ||
            currentQuestionType == "Enumeration"
        ? answerInputController.text.trim()
        : (selectedAnswer?.trim() ?? '');

    return TechCircuitBackground(
      baseColor: lightGreen,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // Removed the "Question Result" header only.
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                resultCard(points: points, yourAnswer: yourAnswer),
                const SizedBox(height: 12),
                contestAnswerButton(),
                if (contestStatus != "none" && contestRequestId != null)
                  contestStatusListener(questionIndex: previousQuestion),
                const SizedBox(height: 12),
                waitingForNextQuestion(
                  readyCheckActive: readyCheckActive,
                  readyCheckId: readyCheckId,
                  isLastQuestionInLevel: isLastQuestionInLevel,
                  currentLevel: currentLevel,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // RESULT CARD
  // ==========================================================

  Widget resultCard({required int points, String? yourAnswer}) {
    if (!answered || !resultRevealed) {
      return const SizedBox.shrink();
    }

    final displayAnswer = (yourAnswer ?? '').trim().isEmpty
        ? "No answer"
        : yourAnswer!.trim();
    final bool noAnswer = displayAnswer.toLowerCase() == 'no answer';
    final Color resultAccent = noAnswer
        ? Colors.orange.shade700
        : (lastAnswerCorrect ? primaryGreen : Colors.red.shade600);
    final Color resultBackground = noAnswer
        ? Colors.orange.shade50
        : (lastAnswerCorrect ? softGreen : Colors.red.shade50);
    final Color resultBorder = noAnswer
        ? Colors.orange.shade200
        : (lastAnswerCorrect ? const Color(0xFF86C995) : Colors.red.shade200);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: resultBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: resultBorder, width: 1.5),
      ),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: resultAccent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              noAnswer
                  ? Icons.hourglass_empty_rounded
                  : (lastAnswerCorrect
                        ? Icons.check_rounded
                        : Icons.close_rounded),
              color: Colors.white,
              size: 42,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            noAnswer ? "NO ANSWER" : (lastAnswerCorrect ? "CORRECT!" : "WRONG"),
            style: TextStyle(
              color: resultAccent,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            lastAnswerCorrect
                ? "+$points POINT${points == 1 ? '' : 'S'}"
                : "0 POINTS",
            style: TextStyle(
              color: resultAccent,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 18),
          _resultAnswerBox(
            title: "CORRECT ANSWER",
            value: currentCorrectAnswer.isEmpty
                ? "Not available"
                : currentCorrectAnswer,
          ),
          const SizedBox(height: 10),
          _resultAnswerBox(title: "YOUR ANSWER", value: displayAnswer),
        ],
      ),
    );
  }

  // ==========================================================
  // ANSWER SUBMITTED - WAITING FOR TIMER TO FINISH
  // ==========================================================

  Widget submittedWaitingCard() {
    if (!answered || resultRevealed) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: softGreen,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderGreen, width: 1.5),
      ),
      child: const Row(
        children: [
          Icon(Icons.check_circle_rounded, color: primaryGreen, size: 30),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              "Answer submitted! The result will be shown when the timer ends.",
              style: TextStyle(
                color: darkGreen,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultAnswerBox({required String title, required String value}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: textDark,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // "YOU ARE READY?" CARD AFTER RESULT
  //
  // CONFIRM -> contestant is ready for the next question.
  // CANCEL  -> undo the ready status.
  // The app still moves on automatically when the Quiz Master
  // starts the next question.
  // ==========================================================

  ({int level, int numberInLevel, int totalInLevel})
  _getLevelPositionForGlobalIndex(int globalQuestionIndex) {
    // 1. Prefer the sorted session questions subcollection when loaded.
    if (_sortedSessionQuestions.isNotEmpty &&
        globalQuestionIndex >= 0 &&
        globalQuestionIndex < _sortedSessionQuestions.length) {
      final targetData =
          _sortedSessionQuestions[globalQuestionIndex].data()
              as Map<String, dynamic>;
      final targetLevel = getLevelFromSessionQuestion(
        targetData,
        fallbackQuestionNumber: globalQuestionIndex + 1,
      );

      var numberInLevel = 0;
      var totalInLevel = 0;
      for (var i = 0; i < _sortedSessionQuestions.length; i++) {
        final itemData =
            _sortedSessionQuestions[i].data() as Map<String, dynamic>;
        final itemLevel = getLevelFromSessionQuestion(
          itemData,
          fallbackQuestionNumber: i + 1,
        );
        if (itemLevel == targetLevel) {
          totalInLevel++;
          if (i <= globalQuestionIndex) {
            numberInLevel++;
          }
        }
      }

      if (numberInLevel > 0) {
        return (
          level: targetLevel,
          numberInLevel: numberInLevel,
          totalInLevel: totalInLevel,
        );
      }
    }

    // 2. Use quizData['levelQuestions'] from the session document so every
    // configured level (Level 1, Level 2, Level 3, Level 4, ...) always
    // restarts numbering at 1 even before _sortedSessionQuestions finishes loading.
    final rawLevelQuestions = _latestQuizData['levelQuestions'];
    if (rawLevelQuestions is Map && globalQuestionIndex >= 0) {
      final entries = <({int level, int count})>[];
      rawLevelQuestions.forEach((key, value) {
        final match = RegExp(r'(\d+)').firstMatch(key.toString());
        final levelNum = match == null ? null : int.tryParse(match.group(1)!);
        final count = value is List ? value.length : 0;
        if (levelNum != null && levelNum > 0 && count > 0) {
          entries.add((level: levelNum, count: count));
        }
      });
      entries.sort((a, b) => a.level.compareTo(b.level));

      var startIndex = 0;
      for (final entry in entries) {
        if (globalQuestionIndex >= startIndex &&
            globalQuestionIndex < startIndex + entry.count) {
          return (
            level: entry.level,
            numberInLevel: (globalQuestionIndex - startIndex) + 1,
            totalInLevel: entry.count,
          );
        }
        startIndex += entry.count;
      }
    }

    final fallbackLevel =
        int.tryParse(_latestQuizData['currentLevel']?.toString() ?? '') ??
        (_currentQuestionLevel > 0 ? _currentQuestionLevel : 1);

    if (_currentLevelQuestionNumber > 0) {
      return (
        level: fallbackLevel,
        numberInLevel: _currentLevelQuestionNumber,
        totalInLevel: _currentLevelQuestionTotal,
      );
    }

    return (
      level: fallbackLevel,
      numberInLevel: 1,
      totalInLevel: _currentLevelQuestionTotal,
    );
  }

  int _getQuestionNumberWithinLevel(int globalQuestionIndex) {
    return _getLevelPositionForGlobalIndex(
      globalQuestionIndex,
    ).numberInLevel.clamp(1, 999).toInt();
  }

  int _getNextQuestionNumberInLevel() {
    if (previousQuestion < 0) {
      return 1;
    }

    final currentPos = _getLevelPositionForGlobalIndex(previousQuestion);
    if (currentPos.totalInLevel > 0 &&
        currentPos.numberInLevel >= currentPos.totalInLevel) {
      return 1;
    }

    final nextIndex = previousQuestion + 1;
    final nextPos = _getLevelPositionForGlobalIndex(nextIndex);
    if (nextPos.level != currentPos.level) {
      return 1;
    }

    return nextPos.numberInLevel.clamp(1, 999).toInt();
  }

  Widget _greenWaitingForNextQuestionScreen() {
    // Restart question numbering at 1 for each level (Level 1, Level 2, Level 3).
    final int nextQuestionNumber = _getNextQuestionNumberInLevel();

    int activeLevel = _currentQuestionLevel;
    if (activeLevel <= 0 && previousQuestion >= 0) {
      final pos = _getLevelPositionForGlobalIndex(previousQuestion);
      activeLevel = pos.level;
    }
    if (activeLevel <= 0) {
      final parsed =
          int.tryParse(_latestQuizData['currentLevel']?.toString() ?? '');
      if (parsed != null && parsed > 0) activeLevel = parsed;
    }
    if (activeLevel <= 0) activeLevel = 1;

    return TechCircuitBackground(
      baseColor: lightGreen,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: softGreen,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: borderGreen, width: 1.2),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.bolt_rounded,
                            color: primaryGreen,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'LEVEL $activeLevel • PREPARATION',
                            style: const TextStyle(
                              color: darkGreen,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: 108,
                      height: 108,
                      decoration: const BoxDecoration(
                        color: softGreen,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.hourglass_top_rounded,
                        color: primaryGreen,
                        size: 58,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'PREPARE FOR LEVEL $activeLevel: QUESTION $nextQuestionNumber!',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: darkGreen,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: borderGreen),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                primaryGreen,
                              ),
                            ),
                          ),
                          SizedBox(width: 14),
                          Flexible(
                            child: Text(
                              'Waiting for the Quiz Master...',
                              style: TextStyle(
                                color: darkGreen,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                height: 1.4,
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
    );
  }

  Widget waitingForNextQuestion({
    required bool readyCheckActive,
    required String readyCheckId,
    bool isLastQuestionInLevel = false,
    int currentLevel = 1,
  }) {
    if (!answered || !resultRevealed) {
      return const SizedBox.shrink();
    }

    final nextQuestionNumber = _getNextQuestionNumberInLevel();
    final bool isConfirmed =
        nextReadyConfirmed && (confirmedQuestionIndex == currentQuestion);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 15),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderGreen, width: 1.5),
      ),
      child: Column(
        children: [
          Icon(
            isConfirmed
                ? Icons.check_circle_rounded
                : Icons.play_circle_outline_rounded,
            color: primaryGreen,
            size: 44,
          ),
          const SizedBox(height: 10),
          if (!isLastQuestionInLevel) ...[
            Text(
              isConfirmed ? "YOU ARE READY!" : "YOU ARE READY?",
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: darkGreen,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            isLastQuestionInLevel
                ? (isConfirmed
                      ? "Waiting for the Quiz Master to show the Level $currentLevel results."
                      : "Please see the Level $currentLevel results.")
                : (isConfirmed
                      ? "Waiting for the Quiz Master to start Question $nextQuestionNumber."
                      : "Review the result above, then press CONFIRM when you are ready for the next question."),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey,
              fontSize: isLastQuestionInLevel ? 22 : 15,
              fontWeight: isLastQuestionInLevel
                  ? FontWeight.w600
                  : FontWeight.normal,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isConfirmed
                  ? null
                  : () {
                      if (isLastQuestionInLevel) {
                        setState(() {
                          nextReadyConfirmed = true;
                          confirmedQuestionIndex = currentQuestion;
                          _showLocalLevelResults = true;
                        });
                      } else {
                        setNextQuestionReady(true);
                      }
                    },
              icon: const Icon(Icons.check, size: 20),
              label: Text(
                isConfirmed
                    ? (isLastQuestionInLevel ? "NEXT" : "READY")
                    : (isLastQuestionInLevel ? "NEXT" : "CONFIRM"),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryGreen,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFB7D8C0),
                disabledForegroundColor: Colors.white,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // CONTEST ANSWER
  // ==========================================================

  Future<void> showContestDialog() async {
    if (!answered ||
        !resultRevealed ||
        lastAnswerCorrect ||
        contestStatus != "none" ||
        previousQuestion < 0) {
      return;
    }

    contestExplanationController.clear();

    final explanation = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.gavel_rounded, color: primaryGreen),
              SizedBox(width: 10),
              Expanded(child: Text("Contest Answer")),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Your answer was marked incorrect.",
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  "If you believe your answer should "
                  "be accepted, explain why. The Quiz "
                  "Master will review your contest.",
                  style: TextStyle(color: Colors.grey, height: 1.4),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: contestExplanationController,
                  maxLines: 5,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: "Reason / Explanation",
                    hintText:
                        "Explain why your answer "
                        "should be considered correct...",
                    alignLabelWithHint: true,
                    filled: true,
                    fillColor: lightGreen,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: borderGreen),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: borderGreen),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: primaryGreen,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text("CANCEL"),
            ),
            ElevatedButton.icon(
              onPressed: () {
                final text = contestExplanationController.text.trim();

                if (text.isEmpty) {
                  showTopSnackBar(dialogContext, 
                    const SnackBar(
                      content: Text(
                        "Please explain why you "
                        "want to contest the answer.",
                      ),
                    ),
                  );

                  return;
                }

                Navigator.pop(dialogContext, text);
              },
              icon: const Icon(Icons.send_rounded),
              label: const Text("SUBMIT CONTEST"),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryGreen,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );

    if (explanation == null || explanation.trim().isEmpty || !mounted) {
      return;
    }

    await submitContest(explanation.trim());
  }

  // ==========================================================
  // SUBMIT CONTEST
  // ==========================================================

  Future<void> submitContest(String explanation) async {
    if (contestSubmitting ||
        contestStatus != "none" ||
        !answered ||
        !resultRevealed ||
        lastAnswerCorrect) {
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return;
    }

    final uid = currentUser.uid;
    final questionIndex = previousQuestion;
    final questionNumber = questionIndex + 1;

    setState(() {
      contestSubmitting = true;
    });

    try {
      final question = currentQuestionData;

      if (question == null || questionIndex != previousQuestion) {
        throw Exception("Current session question is not available.");
      }

      final questionId =
          currentQuestionDocId ??
          question['questionId']?.toString() ??
          'question_$questionIndex';

      final userName = await getUserName(uid);

      String teamName = '';
      List<String> teamMembers = [];
      String personalName = userName;
      bool isTeam = false;

      try {
        final joinSnap = await FirebaseFirestore.instance
            .collection('quiz_sessions')
            .doc(widget.quizCode)
            .collection('join_requests')
            .doc(uid)
            .get();
        if (joinSnap.exists) {
          final jData = joinSnap.data();
          final rawTeam = (jData?['teamName'] ?? '').toString().trim();
          final cType = (jData?['contestantType'] ?? '').toString().trim().toLowerCase();
          final rawMembers = jData?['teamMembers'] ?? jData?['members'];
          if (rawMembers is List) {
            for (final m in rawMembers) {
              final s = m is Map ? (m['name'] ?? m['displayName'] ?? '').toString().trim() : m.toString().trim();
              if (s.isNotEmpty && !teamMembers.contains(s)) teamMembers.add(s);
            }
          }
          isTeam = cType == 'team' || jData?['isTeam'] == true || rawTeam.isNotEmpty || teamMembers.isNotEmpty;
          teamName = rawTeam;
          final rName = (jData?['realName'] ?? jData?['fullName'] ?? '').toString().trim();
          if (rName.isNotEmpty) personalName = rName;
        }

        if (teamName.isEmpty || teamMembers.isEmpty) {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get();
          if (userDoc.exists) {
            final uData = userDoc.data();
            final rawTeam = (uData?['teamName'] ?? '').toString().trim();
            final cType = (uData?['contestantType'] ?? '').toString().trim().toLowerCase();
            final rawMembers = uData?['teamMembers'] ?? uData?['members'];
            if (rawMembers is List) {
              for (final m in rawMembers) {
                final s = m is Map ? (m['name'] ?? m['displayName'] ?? '').toString().trim() : m.toString().trim();
                if (s.isNotEmpty && !teamMembers.contains(s)) teamMembers.add(s);
              }
            }
            if (rawTeam.isNotEmpty) teamName = rawTeam;
            if (cType == 'team' || rawTeam.isNotEmpty || teamMembers.isNotEmpty) isTeam = true;
            final rName = (uData?['fullName'] ?? uData?['name'] ?? '').toString().trim();
            if (rName.isNotEmpty) personalName = rName;
          }
        }
      } catch (e) {
        debugPrint("GET TEAM INFO FOR CONTEST ERROR: $e");
      }

      final String effectiveDisplayName = isTeam
          ? (teamName.isNotEmpty ? teamName : personalName)
          : personalName;

      final requestId = '${uid}_question_$questionIndex';

      final requestRef = FirebaseFirestore.instance
          .collection('quiz_sessions')
          .doc(widget.quizCode)
          .collection('contest_requests')
          .doc(requestId);

      final responseRef = FirebaseFirestore.instance
          .collection('quiz_sessions')
          .doc(widget.quizCode)
          .collection('answers')
          .doc(uid)
          .collection('responses')
          .doc('question_$questionIndex');

      final existingRequest = await requestRef.get();

      if (existingRequest.exists) {
        final existingData = existingRequest.data();

        if (mounted) {
          setState(() {
            contestSubmitting = false;
            contestRequestId = requestId;
            contestStatus = existingData?['status']?.toString() ?? "pending";
          });
        }

        return;
      }

      final acceptedAnswers = getAcceptedAnswers(question);

      String contestantAnswer = questionTypeSafeAnswer();
      if (contestantAnswer.isEmpty) {
        try {
          final savedResp = await responseRef.get();
          if (savedResp.exists) {
            contestantAnswer = (savedResp.data()?['selectedAnswer'] ??
                    savedResp.data()?['answer'] ??
                    '')
                .toString()
                .trim();
          }
        } catch (_) {}
      }

      await requestRef.set({
        'contestantUid': uid,
        'contestantName': effectiveDisplayName,
        'displayName': effectiveDisplayName,
        'realName': personalName,
        'teamName': isTeam ? teamName : '',
        'isTeam': isTeam,
        'contestantType': isTeam ? 'team' : 'solo',
        'teamMembers': teamMembers,
        'questionId': questionId,
        'questionNumber': questionNumber,
        'questionText': question['question']?.toString() ?? '',
        'questionType': getQuestionType(question),
        'expectedAnswer': getCorrectAnswer(question),
        'acceptedAnswers': acceptedAnswers,
        'contestantAnswer': contestantAnswer,
        'explanation': explanation,
        'status': 'pending',
        'scoreApplied': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await responseRef.set({
        'answerStatus': 'contested',
        'contestStatus': 'pending',
        'contestRequestId': requestId,
        'contestSubmittedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      setState(() {
        contestSubmitting = false;
        contestRequestId = requestId;
        contestStatus = "pending";
      });

      showTopSnackBar(context, 
        const SnackBar(
          content: Text(
            "Contest submitted. Please wait for "
            "the Quiz Master to review your answer.",
          ),
          backgroundColor: primaryGreen,
        ),
      );
    } catch (e) {
      debugPrint("SUBMIT CONTEST ERROR: $e");

      if (mounted) {
        setState(() {
          contestSubmitting = false;
        });

        showTopSnackBar(context, 
          SnackBar(
            content: Text("Unable to submit contest: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ==========================================================
  // GET CURRENT CONTESTANT ANSWER
  // ==========================================================

  String questionTypeSafeAnswer() {
    if (currentQuestionType == "Identification" ||
        currentQuestionType == "Enumeration") {
      return answerInputController.text.trim();
    }

    return selectedAnswer?.trim() ?? "";
  }

  // ==========================================================
  // APPLY APPROVED CONTEST
  // ==========================================================

  Future<void> applyApprovedContest({required int questionIndex}) async {
    if (contestProcessingApproval) {
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return;
    }

    final uid = currentUser.uid;
    final questionNumber = questionIndex + 1;
    final contestLevel = getLevelFromSessionQuestion(
      currentQuestionData ?? {},
      fallbackQuestionNumber: questionNumber,
    );
    final points = getPointsForLevel(contestLevel);

    final requestId = contestRequestId ?? '${uid}_question_$questionIndex';

    final requestRef = FirebaseFirestore.instance
        .collection('quiz_sessions')
        .doc(widget.quizCode)
        .collection('contest_requests')
        .doc(requestId);

    final responseRef = FirebaseFirestore.instance
        .collection('quiz_sessions')
        .doc(widget.quizCode)
        .collection('answers')
        .doc(uid)
        .collection('responses')
        .doc('question_$questionIndex');

    setState(() {
      contestProcessingApproval = true;
    });

    try {
      bool shouldAwardPoints = false;

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final requestSnapshot = await transaction.get(requestRef);

        final responseSnapshot = await transaction.get(responseRef);

        if (!requestSnapshot.exists || !responseSnapshot.exists) {
          return;
        }

        final requestData = requestSnapshot.data();

        final responseData = responseSnapshot.data();

        if (requestData == null || responseData == null) {
          return;
        }

        final requestStatus = requestData['status']?.toString().toLowerCase();

        if (requestStatus != "approved") {
          return;
        }

        final alreadyCorrect = responseData['isCorrect'] == true;

        final alreadyApplied = requestData['scoreApplied'] == true;

        if (alreadyCorrect) {
          if (!alreadyApplied) {
            transaction.update(requestRef, {
              'scoreApplied': true,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }

          return;
        }

        transaction.update(responseRef, {
          'isCorrect': true,
          'answerStatus': 'correct',
          'contestStatus': 'approved',
          'points': points,
          'contestApprovedAt': FieldValue.serverTimestamp(),
        });

        transaction.update(requestRef, {
          'scoreApplied': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        shouldAwardPoints = true;
      });

      if (shouldAwardPoints) {
        await updateScore(uid, points, questionNumber);
      }

      if (mounted) {
        setState(() {
          contestProcessingApproval = false;
          contestStatus = "approved";
          lastAnswerCorrect = true;
        });
      }
    } catch (e) {
      debugPrint("APPLY APPROVED CONTEST ERROR: $e");

      if (mounted) {
        setState(() {
          contestProcessingApproval = false;
        });
      }
    }
  }

  // ==========================================================
  // CONTEST STATUS LISTENER
  // ==========================================================

  Widget contestStatusListener({required int questionIndex}) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null || contestRequestId == null) {
      return const SizedBox.shrink();
    }

    final requestRef = FirebaseFirestore.instance
        .collection('quiz_sessions')
        .doc(widget.quizCode)
        .collection('contest_requests')
        .doc(contestRequestId);

    return StreamBuilder<DocumentSnapshot>(
      stream: requestRef.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;

          final status = data?['status']?.toString().toLowerCase() ?? "pending";

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;

            if (status == "approved") {
              if (contestStatus != "approved") {
                setState(() {
                  contestStatus = "approved";
                });
              }

              if (!lastAnswerCorrect) {
                applyApprovedContest(questionIndex: questionIndex);
              }
            } else if (status == "rejected" ||
                status == "declined" ||
                status == "invalid") {
              if (contestStatus != status) {
                setState(() {
                  contestStatus = status;
                });
              }
            } else if (status == "pending") {
              if (contestStatus != "pending") {
                setState(() {
                  contestStatus = "pending";
                });
              }
            }
          });
        }

        return contestStatusWidget();
      },
    );
  }

  // ==========================================================
  // CONTEST STATUS WIDGET
  // ==========================================================

  Widget contestStatusWidget() {
    if (contestStatus == "none") {
      return const SizedBox.shrink();
    }

    if (contestStatus == "pending") {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: const Row(
          children: [
            Icon(Icons.hourglass_top_rounded, color: Colors.orange),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                "Contest submitted. Waiting for "
                "Quiz Master review.",
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (contestStatus == "approved") {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: softGreen,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0xFF86C995)),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified_rounded, color: primaryGreen),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                contestProcessingApproval
                    ? "Contest approved. Updating score..."
                    : "Contest approved! Your answer "
                          "has been accepted.",
                style: const TextStyle(
                  color: darkGreen,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: const Row(
        children: [
          Icon(Icons.cancel_rounded, color: Colors.red),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "Contest rejected. Your original answer "
              "remains incorrect.",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // CONTEST BUTTON
  // ==========================================================

  Widget contestAnswerButton() {
    if (!answered ||
        !resultRevealed ||
        lastAnswerCorrect ||
        contestStatus != "none") {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      child: OutlinedButton.icon(
        onPressed: contestSubmitting ? null : showContestDialog,
        icon: contestSubmitting
            ? const SizedBox(
                width: 19,
                height: 19,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.gavel_rounded),
        label: Text(
          contestSubmitting ? "SUBMITTING CONTEST..." : "CONTEST ANSWER",
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.orange.shade800,
          side: BorderSide(color: Colors.orange.shade400, width: 1.5),
          minimumSize: const Size(double.infinity, 55),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // UPDATE SCORE
  // ==========================================================

  Future<void> updateScore(String uid, int points, int questionNumber) async {
    final name = await getUserName(uid);

    // Get the contestant's team name and members from the users collection.
    String teamName = '';
    List<String> teamMembers = [];

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data();
        teamName = userData?['teamName']?.toString().trim() ?? '';
        final rawMembers = userData?['teamMembers'] ?? userData?['members'];
        if (rawMembers is List) {
          teamMembers = rawMembers
              .map((e) => e is Map ? (e['name'] ?? '').toString().trim() : e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList();
        }
      }
    } catch (e) {
      debugPrint("GET TEAM NAME ERROR: $e");
    }

    final scoreRef = FirebaseFirestore.instance
        .collection('quiz_sessions')
        .doc(widget.quizCode)
        .collection('scores')
        .doc(uid);

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final scoreDoc = await transaction.get(scoreRef);

      int oldScore = 0;

      if (scoreDoc.exists) {
        final data = scoreDoc.data();

        if (data != null && data['score'] != null) {
          oldScore = int.tryParse(data['score'].toString()) ?? 0;
        }
      }

      final newScore = (oldScore + points) < 0 ? 0 : (oldScore + points);

      transaction.set(scoreRef, {
        'uid': uid,
        'name': name,
        'teamName': teamName,
        'teamMembers': teamMembers,
        'members': teamMembers,
        'score': newScore,
        'lastQuestion': questionNumber,
        'lastPoints': points,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

    if (mounted) {
      setState(() {
        currentScore =
            (currentScore + points) < 0 ? 0 : (currentScore + points);
      });
    }
  }

  // ==========================================================
  // LIVE RANK
  // ==========================================================

  Future<void> updateLiveRank() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      final scoresRef = _sessionRef.collection('scores');
      final joinRequestsRef = _sessionRef.collection('join_requests');

      final List<QuerySnapshot<Map<String, dynamic>>> results =
          await Future.wait<QuerySnapshot<Map<String, dynamic>>>([
            scoresRef.get(),
            joinRequestsRef.get(),
          ]);

      final scoresSnapshot = results[0];
      final joinRequestsSnapshot = results[1];

      // Kon naa nay gi-sync o gi-assign nga accurate rank gikan sa quizmaster,
      // gamita kana dayon aron 100% mag-match sa quizmaster screen.
      int? directRank;
      try {
        final sessionSnap = await _sessionRef.get();
        final officialRanks = sessionSnap.data()?['officialRanks'];
        if (officialRanks is Map && officialRanks.containsKey(currentUser.uid)) {
          final offRank = officialRanks[currentUser.uid];
          final parsed = offRank is num
              ? offRank.toInt()
              : int.tryParse(offRank?.toString() ?? '');
          if (parsed != null && parsed > 0) {
            directRank = parsed;
          }
        }
      } catch (_) {}

      if (directRank == null) {
        for (final doc in scoresSnapshot.docs) {
          if (doc.id == currentUser.uid) {
            final data = doc.data();
            final raw = data['rank'] ??
                data['levelRank'] ??
                data['currentRank'] ??
                data['rankAtProceed'];
            if (raw != null) {
              directRank =
                  raw is num ? raw.toInt() : int.tryParse(raw.toString());
            }
            break;
          }
        }
      }
      if (directRank == null) {
        for (final doc in joinRequestsSnapshot.docs) {
          if (doc.id == currentUser.uid) {
            final data = doc.data();
            final raw = data['rank'] ??
                data['levelRank'] ??
                data['currentRank'] ??
                data['rankAtProceed'];
            if (raw != null) {
              directRank =
                  raw is num ? raw.toInt() : int.tryParse(raw.toString());
            }
            break;
          }
        }
      }

      final scoreByUid = <String, int>{};
      final submissionTimeByUid = <String, int>{};

      for (final doc in scoresSnapshot.docs) {
        final data = doc.data();
        final rawScore = data['score'];
        scoreByUid[doc.id] = rawScore is num
            ? rawScore.toInt()
            : int.tryParse(rawScore?.toString() ?? '') ?? 0;

        final rawTime = data['updatedAt'] ??
            data['answeredAt'] ??
            data['lastAnsweredAt'];
        if (rawTime is Timestamp) {
          submissionTimeByUid[doc.id] = rawTime.millisecondsSinceEpoch;
        } else if (rawTime is num) {
          submissionTimeByUid[doc.id] = rawTime.toInt();
        }
      }

      for (final doc in joinRequestsSnapshot.docs) {
        scoreByUid.putIfAbsent(doc.id, () => 0);
      }

      scoreByUid.putIfAbsent(currentUser.uid, () => 0);

      final ranked = scoreByUid.entries.toList()
        ..sort((a, b) {
          final scoreCompare = b.value.compareTo(a.value);
          if (scoreCompare != 0) return scoreCompare;

          // Tie-breaker parehas sa Quizmaster: kinsay mas paspas ni-submit
          final timeA = submissionTimeByUid[a.key] ?? 0;
          final timeB = submissionTimeByUid[b.key] ?? 0;
          if (timeA > 0 && timeB > 0 && timeA != timeB) {
            return timeA.compareTo(timeB);
          } else if (timeA > 0 && timeB == 0) {
            return -1;
          } else if (timeB > 0 && timeA == 0) {
            return 1;
          }

          return a.key.compareTo(b.key);
        });

      final rankIndex = ranked.indexWhere(
        (entry) => entry.key == currentUser.uid,
      );
      final rank = directRank ?? (rankIndex >= 0 ? rankIndex + 1 : 1);
      final score = scoreByUid[currentUser.uid] ?? 0;

      if (!mounted) return;
      setState(() {
        currentRank = rank;
        if (_contestantDecisionRank == null || _contestantDecisionRank! <= 0) {
          if (directRank != null && directRank > 0) {
            _contestantDecisionRank = directRank;
          }
        }
        totalPlayers = ranked.length;
        currentScore = score;
      });
    } catch (e) {
      debugPrint("LIVE RANK ERROR: $e");
    }
  }

  // ==========================================================
  // ANSWER BUTTON
  // ==========================================================

  Widget answerButton(String answer) {
    final isSelected = selectedAnswer == answer;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: 56,
          minWidth: double.infinity,
        ),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: isSelected ? primaryGreen : Colors.white,
            foregroundColor: isSelected ? Colors.white : textDark,
            elevation: isSelected ? 4 : 1,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            side: BorderSide(
              color: isSelected ? primaryGreen : const Color(0xFFDDE5DF),
              width: 1.5,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: answered || submitting
              ? null
              : () {
                  setState(() {
                    selectedAnswer = answer;
                  });
                },
          child: Row(
            children: [
              Icon(
                isSelected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: isSelected ? Colors.white : primaryGreen,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  answer,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: 22),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // TRUE / FALSE
  // ==========================================================

  Widget trueFalseButton(String answer) {
    final isSelected = selectedAnswer == answer;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: 56,
          minWidth: double.infinity,
        ),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: isSelected ? primaryGreen : Colors.white,
            foregroundColor: isSelected ? Colors.white : textDark,
            elevation: isSelected ? 4 : 1,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            side: BorderSide(
              color: isSelected ? primaryGreen : const Color(0xFFDDE5DF),
              width: 1.5,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: answered || submitting
              ? null
              : () {
                  setState(() {
                    selectedAnswer = answer;
                  });
                },
          child: Row(
            children: [
              Icon(
                isSelected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: isSelected ? Colors.white : primaryGreen,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  answer,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: 22),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // TEXT ANSWER
  // ==========================================================

  Widget textAnswerField() {
    final isEnumeration = currentQuestionType == "Enumeration";

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderGreen, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: softGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.edit_rounded, color: primaryGreen),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isEnumeration ? "Enter all your answers" : "Type your answer",
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: answerInputController,
            enabled: !answered && !submitting,
            onChanged: (_) {
              setState(() {});
            },
            maxLines: isEnumeration ? 4 : 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: isEnumeration
                  ? "Example: CPU, RAM, SSD"
                  : "Type your answer here...",
              hintStyle: const TextStyle(color: Colors.grey),
              filled: true,
              fillColor: lightGreen,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: borderGreen),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: borderGreen),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: primaryGreen, width: 2),
              ),
            ),
          ),
          if (isEnumeration) ...[
            const SizedBox(height: 10),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: primaryGreen),
                SizedBox(width: 7),
                Expanded(
                  child: Text(
                    "You may enter answers in any order. "
                    "Separate each answer with a comma, "
                    "semicolon, or new line.",
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 10),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: primaryGreen),
                SizedBox(width: 7),
                Expanded(
                  child: Text(
                    "Your answer must match one of the "
                    "accepted answers configured by the Quiz Master.",
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ==========================================================
  // SUBMIT
  // ==========================================================

  Widget submitButton() {
    final isTextQuestion =
        currentQuestionType == "Identification" ||
        currentQuestionType == "Enumeration";

    final hasAnswer = isTextQuestion
        ? answerInputController.text.trim().isNotEmpty
        : selectedAnswer != null;

    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton.icon(
        icon: submitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.send_rounded),
        onPressed: answered || submitting || !hasAnswer
            ? null
            : () {
                final answer = isTextQuestion
                    ? answerInputController.text.trim()
                    : selectedAnswer!;

                saveAnswer(currentQuestion, answer);
              },
        label: Text(
          submitting ? "SUBMITTING..." : "SUBMIT ANSWER",
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryGreen,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFB7D8C0),
          disabledForegroundColor: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // EXIT
  // ==========================================================

  Future<void> confirmExit() async {
    final exit = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Leave Quiz?"),
          content: const Text(
            "Are you sure you want to leave "
            "the quiz?\n\n"
            "Your submitted answers and score "
            "will remain saved.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("CANCEL"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryGreen,
                foregroundColor: Colors.white,
              ),
              child: const Text("LEAVE"),
            ),
          ],
        );
      },
    );

    if (exit == true && mounted) {
      await _leaveQuizAndRequireApproval();
    }
  }

  Future<int> _getContestantLevelPoints(int level) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0;

    final snapshot = await _sessionRef
        .collection('answers')
        .doc(user.uid)
        .collection('responses')
        .where('level', isEqualTo: level)
        .get();

    var total = 0;
    for (final response in snapshot.docs) {
      final data = response.data();
      final value = data['points'];
      if (value is num) total += value.toInt();
    }
    return total;
  }

  // ==========================================================
  // LEVEL PAUSE SCREEN
  // ==========================================================

  Widget levelPauseScreen(int currentLevel) {
    timer?.cancel();

    return TechCircuitBackground(
      baseColor: lightGreen,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // No "Quiz Paused" AppBar on the level-complete waiting page.
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const TechArenaBadge(
                      label: 'STAGE CLEARED • WELL DONE',
                      icon: Icons.military_tech_rounded,
                    ),
                    const SizedBox(height: 24),
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFDCFCE7),
                        border: Border.all(
                          color: const Color(0xFF86EFAC),
                          width: 3.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF16A34A).withValues(alpha: 0.22),
                            blurRadius: 30,
                            spreadRadius: 3,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 90,
                          height: 90,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                Color(0xFF22C55E),
                                Color(0xFF15803D),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: const Icon(
                            Icons.emoji_events_rounded,
                            color: Colors.white,
                            size: 52,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      "LEVEL $currentLevel COMPLETE!",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: darkGreen,
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Outstanding work! Your level score has been recorded.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FutureBuilder<int>(
                      future: _getContestantLevelPoints(currentLevel),
                      builder: (context, snapshot) {
                        final points = snapshot.data;
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 22,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: const Color(0xFFBBF7D0),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF16A34A).withValues(alpha: 0.08),
                                blurRadius: 20,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.stars_rounded,
                                    size: 16,
                                    color: Colors.amber.shade600,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    "YOUR LEVEL SCORE",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting)
                                const SizedBox(
                                  width: 26,
                                  height: 26,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: primaryGreen,
                                  ),
                                )
                              else
                                Text(
                                  "${points ?? 0} ${points == 1 ? 'POINT' : 'POINTS'}",
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: primaryGreen,
                                    fontSize: 32,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: _sessionRef.snapshots(),
                      builder: (context, snapshot) {
                        final sessionData = snapshot.data?.data() ?? _latestQuizData;
                        final sessionStatus =
                            sessionData['status']?.toString().toLowerCase().trim() ?? '';
                        final bool isQuizFinished = sessionStatus == 'finished' ||
                            sessionStatus == 'completed' ||
                            sessionStatus == 'ended' ||
                            sessionData['isFinished'] == true;

                        if (isQuizFinished) {
                          return Column(
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFF86EFAC),
                                    width: 1.5,
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.check_circle_rounded,
                                      color: primaryGreen,
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        "Quiz finished! You can view the final ranking now.",
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Color(0xFF14532D),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.emoji_events_rounded, size: 24),
                                  label: const Text(
                                    "FINAL RESULTS",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primaryGreen,
                                    foregroundColor: Colors.white,
                                    elevation: 4,
                                    shadowColor: primaryGreen.withValues(alpha: 0.4),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => PartialRankingScreen(
                                          quizCode: widget.quizCode,
                                          isFinal: true,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          );
                        }

                        return Column(
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFD1FAE5),
                                  width: 1.3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF16A34A).withValues(alpha: 0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: primaryGreen,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Flexible(
                                    child: Text(
                                      "Waiting for Quiz Master to start next round...",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Color(0xFF14532D),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: OutlinedButton.icon(
                                icon: const Icon(
                                  Icons.leaderboard_rounded,
                                  color: primaryGreen,
                                  size: 20,
                                ),
                                label: const Text(
                                  "VIEW CURRENT RANKING",
                                  style: TextStyle(
                                    color: primaryGreen,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: Color(0xFF86EFAC),
                                    width: 1.5,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  backgroundColor: Colors.white.withValues(alpha: 0.9),
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => PartialRankingScreen(
                                        quizCode: widget.quizCode,
                                        isFinal: false,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "TechNoWiz • Competition Arena",
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // MANUAL PAUSE SCREEN
  //
  // Shown while the Quiz Master has paused the quiz (status
  // 'paused'). The question timer is stopped and will continue
  // from the remaining seconds when the Quiz Master resumes.
  // ==========================================================

  Widget pausedScreen() {
    timer?.cancel();

    return TechCircuitBackground(
      baseColor: lightGreen,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // Removed the top "Quiz Paused" header bar as requested.
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(25),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 116,
                    height: 116,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF86EFAC),
                        width: 3.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF16A34A).withValues(alpha: 0.2),
                          blurRadius: 26,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.pause_circle_rounded,
                      color: primaryGreen,
                      size: 68,
                    ),
                  ),
                  const SizedBox(height: 25),
                  const Text(
                    "QUIZ PAUSED",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: darkGreen,
                      fontSize: 27,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    "Please wait for the Quiz Master to resume.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 16, height: 1.4),
                  ),
                  const SizedBox(height: 28),
                  const CircularProgressIndicator(color: primaryGreen),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // FINISHED SCREEN
  // ==========================================================

  Widget finishedScreen() {
    timer?.cancel();
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: lightGreen,
      body: TechCircuitBackground(
        child: SafeArea(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _sessionRef.collection('scores').snapshots(),
        builder: (context, scoreSnap) {
          int liveScore = currentScore;
          int liveRank = currentRank;

          final docs = [...?scoreSnap.data?.docs];
          if (docs.isNotEmpty) {
            bool isElim(Map<String, dynamic> d) =>
                d['eliminated'] == true ||
                d['status']?.toString().toLowerCase() == 'eliminated';
            int scoreOf(Map<String, dynamic> d) =>
                int.tryParse(d['score']?.toString() ?? '') ?? 0;

            docs.sort((a, b) {
              final aElim = isElim(a.data());
              final bElim = isElim(b.data());
              if (aElim != bElim) return aElim ? 1 : -1;
              final byScore = scoreOf(b.data()).compareTo(scoreOf(a.data()));
              if (byScore != 0) return byScore;
              return (a.data()['name']?.toString() ?? a.id).compareTo(
                b.data()['name']?.toString() ?? b.id,
              );
            });

            final ranks = <int>[];
            for (int i = 0; i < docs.length; i++) {
              final raw = docs[i].data()['rank'] ??
                  docs[i].data()['levelRank'] ??
                  docs[i].data()['currentRank'];
              final int? saved = raw is num
                  ? raw.toInt()
                  : int.tryParse(raw?.toString() ?? '');
              ranks.add(saved ?? (i + 1));
            }

            if (myUid != null) {
              final myIndex = docs.indexWhere((d) => d.id == myUid);
              if (myIndex >= 0) {
                liveScore = scoreOf(docs[myIndex].data());
                liveRank = ranks[myIndex];
              }
            }
          }

          final String placementTitle = liveRank == 1
              ? "CHAMPION • RANK #1"
              : liveRank == 2
              ? "1ST RUNNER-UP • RANK #2"
              : liveRank == 3
              ? "2ND RUNNER-UP • RANK #3"
              : (liveRank > 0 ? "FINAL RANK: #$liveRank" : "FINAL RANK: --");

          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(25),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const TechArenaBadge(
                      label: 'TECHNOWIZ • OFFICIAL QUIZ RESULT',
                      icon: Icons.verified_rounded,
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        color: liveRank == 1
                            ? const Color(0xFFFFFBEB)
                            : softGreen,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: liveRank == 1
                              ? Colors.amber.shade400
                              : const Color(0xFFB7D8C0),
                          width: 2.2,
                        ),
                      ),
                      child: Icon(
                        Icons.emoji_events_rounded,
                        color: liveRank == 1
                            ? Colors.amber.shade700
                            : primaryGreen,
                        size: 62,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      liveRank <= 3 && liveRank > 0
                          ? "CONGRATULATIONS!"
                          : "QUIZ FINISHED!",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: darkGreen,
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      liveRank == 1
                          ? "You finished at Rank #1 • Champion! 🏆"
                          : liveRank == 2
                              ? "You finished at Rank #2 • 1st Runner-Up! 🥈"
                              : liveRank == 3
                                  ? "You finished at Rank #3 • 2nd Runner-Up! 🥉"
                                  : (liveRank > 0
                                      ? "You finished at Rank #$liveRank! 🎖️"
                                      : "Thank you for completing the quiz!"),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey, fontSize: 15),
                    ),
                    const SizedBox(height: 22),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: borderGreen),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            "YOUR FINAL SCORE",
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            "$liveScore",
                            style: const TextStyle(
                              color: primaryGreen,
                              fontSize: 52,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: liveRank == 1
                                  ? const Color(0xFFFFFBEB)
                                  : softGreen,
                              borderRadius: BorderRadius.circular(20),
                              border: liveRank == 1
                                  ? Border.all(color: Colors.amber.shade300)
                                  : null,
                            ),
                            child: Text(
                              placementTitle,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: liveRank == 1
                                    ? Colors.amber.shade900
                                    : darkGreen,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),
                    SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.emoji_events_rounded),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PartialRankingScreen(
                                quizCode: widget.quizCode,
                                isFinal: true,
                              ),
                            ),
                          );
                        },
                        label: const Text(
                          "FINAL RESULTS",
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryGreen,
                          foregroundColor: Colors.white,
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(17),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // WAITING SCREEN
  // ==========================================================

  Widget waitingScreen({Map<String, dynamic>? quizData, int? level}) {
    timer?.cancel();

    final int targetLevel = level ?? _nextLevelInstructionsLevel ?? 1;

    return QuizInstructionsScreen(
      quizData: quizData ?? <String, dynamic>{},
      level: targetLevel,
      quizCode: widget.quizCode,
    );
  }

  // ==========================================================
  // QUIZ SIDE MENU DRAWER (LIVE RANKING & LEAVE QUIZ)
  // ==========================================================

  Widget _buildQuizSideMenuDrawer() {
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return Drawer(
      backgroundColor: Colors.white,
      elevation: 16,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: LIVE RANKING + Close button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.leaderboard_rounded,
                      color: primaryGreen,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'LIVE RANKING',
                      style: TextStyle(
                        color: textDark,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.black54),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),

            // Body: Live Ranking Stream (directly visible)
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _sessionRef.collection('scores').snapshots(),
                builder: (context, scoreSnap) {
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _sessionRef
                        .collection('join_requests')
                        .snapshots(),
                    builder: (context, contestantSnap) {
                      if (scoreSnap.connectionState == ConnectionState.waiting &&
                          !scoreSnap.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(color: primaryGreen),
                        );
                      }

                      final scoreDocs = scoreSnap.data?.docs ?? [];
                      final contestants = contestantSnap.data?.docs ?? [];

                      final Map<String, Map<String, dynamic>> scoreById = {
                        for (final s in scoreDocs) s.id: s.data(),
                      };
                      final Map<String, Map<String, dynamic>> contestantById = {
                        for (final c in contestants) c.id: c.data(),
                      };

                      final Set<String> allUids = {
                        ...contestantById.keys,
                        ...scoreById.keys,
                      };

                      final rows = <Map<String, dynamic>>[];

                      for (final uid in allUids) {
                        final cData = contestantById[uid] ?? const <String, dynamic>{};
                        final sData = scoreById[uid] ?? const <String, dynamic>{};
                        final uData = _userProfileCache[uid] ?? const <String, dynamic>{};

                        final status = (cData['status'] ?? sData['status'] ?? '').toString().trim().toLowerCase();
                        final decision = (cData['contestantDecision'] ?? sData['contestantDecision'] ?? '').toString().trim().toLowerCase();

                        // Skip users who left, were rejected, or are still pending
                        if (status == 'left' ||
                            status == 'rejected' ||
                            status == 'declined' ||
                            cData['leftQuiz'] == true ||
                            sData['leftQuiz'] == true ||
                            status == 'pending') {
                          continue;
                        }

                        final isElim = cData['eliminated'] == true ||
                            cData['isEliminated'] == true ||
                            sData['eliminated'] == true ||
                            status == 'eliminated' ||
                            decision == 'eliminated';
                        if (isElim) continue;

                        final rawTeam = (cData['teamName'] ?? sData['teamName'] ?? uData['teamName'] ?? '').toString().trim();
                        final contestantType = (cData['contestantType'] ?? sData['contestantType'] ?? uData['contestantType'] ?? '').toString().trim().toLowerCase();

                        final rawMembers = cData['teamMembers'] ??
                            cData['members'] ??
                            sData['teamMembers'] ??
                            sData['members'] ??
                            uData['teamMembers'] ??
                            uData['members'];

                        final List<String> teamMembers = [];
                        if (rawMembers is List) {
                          for (final m in rawMembers) {
                            final s = m is Map
                                ? (m['name'] ?? m['displayName'] ?? m['fullName'] ?? '').toString().trim()
                                : m.toString().trim();
                            if (s.isNotEmpty && !teamMembers.contains(s)) {
                              teamMembers.add(s);
                            }
                          }
                        }

                        final bool isTeam = contestantType == 'team' ||
                            cData['isTeam'] == true ||
                            sData['isTeam'] == true ||
                            uData['isTeam'] == true ||
                            rawTeam.isNotEmpty ||
                            teamMembers.isNotEmpty;

                        // If it's a team and we don't have members or team info yet, prefetch user profile
                        if (isTeam && teamMembers.isEmpty && !uData.containsKey('teamMembers')) {
                          _prefetchUserProfile(uid);
                        }

                        final personalName = (cData['realName'] ??
                                cData['fullName'] ??
                                uData['fullName'] ??
                                uData['name'] ??
                                sData['fullName'] ??
                                cData['displayName'] ??
                                cData['name'] ??
                                sData['name'] ??
                                cData['email'] ??
                                uid)
                            .toString()
                            .trim();

                        final teamName = rawTeam.isNotEmpty
                            ? rawTeam
                            : (isTeam && teamMembers.isNotEmpty ? (rawTeam.isNotEmpty ? rawTeam : personalName) : '');

                        final displayName = isTeam
                            ? (teamName.isNotEmpty ? teamName : personalName)
                            : personalName;

                        final scoreVal = int.tryParse((sData['score'] ?? cData['score'])?.toString() ?? '') ?? 0;

                        rows.add({
                          'uid': uid,
                          'name': displayName,
                          'team': isTeam ? teamName : '',
                          'isTeam': isTeam,
                          'teamMembers': teamMembers,
                          'score': scoreVal,
                        });
                      }

                      rows.sort((a, b) {
                        final byScore =
                            (b['score'] as int).compareTo(a['score'] as int);
                        if (byScore != 0) return byScore;
                        return (a['name'] as String).compareTo(b['name'] as String);
                      });

                      // Competition ranking: equal scores share the same rank
                      final ranks = <int>[];
                      for (int i = 0; i < rows.length; i++) {
                        if (i > 0 && rows[i]['score'] == rows[i - 1]['score']) {
                          ranks.add(ranks[i - 1]);
                        } else {
                          ranks.add(i + 1);
                        }
                      }

                      if (rows.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No active contestants yet.',
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final item = rows[i];
                          final rank = ranks[i];
                          final isMe = item['uid'] == myUid;
                          final isTeam = item['isTeam'] == true;
                          final List<String> members = (item['teamMembers'] as List<String>?) ?? [];

                          Color rankBadgeColor;
                          Color rankTextColor;
                          if (rank == 1) {
                            rankBadgeColor = const Color(0xFFFEF3C7);
                            rankTextColor = const Color(0xFFB45309);
                          } else if (rank == 2) {
                            rankBadgeColor = const Color(0xFFF3F4F6);
                            rankTextColor = const Color(0xFF4B5563);
                          } else if (rank == 3) {
                            rankBadgeColor = const Color(0xFFFFEDD5);
                            rankTextColor = const Color(0xFFC2410C);
                          } else {
                            rankBadgeColor = const Color(0xFFE5F4FF);
                            rankTextColor = const Color(0xFF1565D8);
                          }

                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isMe ? const Color(0xFFF0FDF4) : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isMe ? primaryGreen : const Color(0xFFE5E7EB),
                                width: isMe ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: rankBadgeColor,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '$rank',
                                    style: TextStyle(
                                      color: rankTextColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              item['name'],
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: textDark,
                                                fontWeight: isMe
                                                    ? FontWeight.w800
                                                    : FontWeight.w600,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                          if (isMe) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: primaryGreen,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: const Text(
                                                'YOU',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      if (isTeam && members.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Text(
                                            'Members: ${members.join(', ')}',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFF5B7A9C),
                                              fontSize: 10,
                                              fontWeight: FontWeight.w500,
                                              height: 1.25,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${item['score']} pts',
                                  style: const TextStyle(
                                    color: primaryGreen,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),

            const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),

            // Footer: LEAVE QUIZ BUTTON
            Padding(
              padding: const EdgeInsets.all(14),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.exit_to_app_rounded, size: 20),
                  label: const Text(
                    'LEAVE QUIZ',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade300, width: 1.2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop(); // Close drawer
                    confirmExit();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    // Lock system/back navigation while the contestant is inside the quiz.
    // This blocks Android/iOS back gestures and the app's route-pop action.
    // Browser refresh is controlled by the browser itself; quiz progress must
    // therefore be restored from the existing Firestore session after reload.
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop || !mounted) return;
        showTopSnackBar(
          context,
          const SnackBar(
            content: Text(
              'Back navigation is disabled while the quiz is in progress.',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('quiz_sessions')
            .doc(widget.quizCode)
            .snapshots(),
        builder: (context, quizSnapshot) {
          if (!quizSnapshot.hasData) {
            return const Scaffold(
              backgroundColor: lightGreen,
              body: Center(
                child: CircularProgressIndicator(color: primaryGreen),
              ),
            );
          }

          final quizData =
              quizSnapshot.data!.data() as Map<String, dynamic>? ?? {};
          _latestQuizData = quizData;

          final rawQuestionIds = quizData['questionIds'];
          final expectedQuestionCount = rawQuestionIds is List
              ? rawQuestionIds.length
              : 0;
          if (!_loadingSessionQuestions &&
              (_sortedSessionQuestions.isEmpty ||
                  (expectedQuestionCount > 0 &&
                      _sortedSessionQuestions.length !=
                          expectedQuestionCount))) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _loadSessionQuestions();
            });
          }

          final rawStatus =
              (quizData['status'] ?? '').toString().trim().toLowerCase();
          final bool isQuizFinished = rawStatus == 'finished' ||
              rawStatus == 'ended' ||
              rawStatus == 'completed' ||
              rawStatus == 'closed' ||
              quizData['isFinished'] == true ||
              quizData['finished'] == true ||
              quizData['completed'] == true ||
              quizData['isCompleted'] == true;

          if (isQuizFinished || _quizFinishedForContestant) {
            timer?.cancel();
            final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
            return _buildFinishedCongratulationsScreen(context, currentUid);
          }

          final status = quizData['status']?.toString() ?? 'waiting';

          final currentQuestion =
              int.tryParse(quizData['currentQuestion']?.toString() ?? '0') ?? 0;

          final readyCheckActive = quizData['readyCheckActive'] == true;

          final readyCheckId =
              quizData['readyCheckId']?.toString().trim() ?? '';

          final countdownActive = quizData['countdownActive'] == true;

          final countdown =
              int.tryParse(quizData['countdown']?.toString() ?? '0') ?? 0;

          // Remember that the synchronized countdown has started. Do not
          // clear this marker as soon as countdownActive becomes false:
          // Firestore may publish the countdown, ready-check, quiz status,
          // and question timer in separate snapshots. Clearing it too early
          // can briefly render the waiting room before the question appears.
          if (countdownActive) {
            _countdownWasActive = true;
            if (currentQuestion == 0) {
              _firstQuestionCountdownHandoff = true;
            }
          }

          final currentLevel =
              int.tryParse(quizData['currentLevel']?.toString() ?? '1') ?? 1;
          final int? preparedLevel = int.tryParse(
            quizData['preparedLevel']?.toString() ?? '',
          );
          final int? sessionLevel = int.tryParse(
            quizData['level']?.toString() ?? '',
          );

          final int sessionEffectiveLevel = [
            currentLevel,
            preparedLevel ?? 1,
            sessionLevel ?? 1,
          ].reduce((a, b) => a > b ? a : b);

          // Quiz Master writes the configured level duration to the session
          // when the synchronized countdown finishes. A zero timer means
          // the question has not started yet.
          final rawSessionTimer =
              int.tryParse(quizData['timer']?.toString() ?? '0') ?? 0;
          final rawStartedAt = quizData['startedAt'];
          // Calculate the live remaining time from the shared Firestore start
          // timestamp. This avoids giving contestants a fresh full timer when
          // their active snapshot arrives a few seconds after Quiz Control.
          final int sessionTimer;
          if (status == 'active' &&
              rawStartedAt is Timestamp &&
              rawSessionTimer > 0) {
            final elapsedSeconds = DateTime.now()
                .difference(rawStartedAt.toDate())
                .inSeconds
                .clamp(0, rawSessionTimer)
                .toInt();
            sessionTimer = (rawSessionTimer - elapsedSeconds)
                .clamp(0, rawSessionTimer)
                .toInt();
          } else {
            sessionTimer = rawSessionTimer;
          }

          final int? targetNextLevel = _nextLevelInstructionsLevel ??
              (_lastProceededDecisionLevel != null
                  ? _lastProceededDecisionLevel! + 1
                  : null);

          // If the contestant clicked PROCEED, they belong to the next level instructions.
          // An active question from a LOWER level (e.g. Question 2 of Level 2 whose timer ran out)
          // must NEVER override the contestant's progression to Level 3!
          final int effectiveContestantLevel;
          if (_showNextLevelInstructions && targetNextLevel != null) {
            effectiveContestantLevel = targetNextLevel;
          } else if (_lastProceededDecisionLevel != null &&
              _lastProceededDecisionLevel! >= currentLevel) {
            effectiveContestantLevel = _lastProceededDecisionLevel! + 1;
          } else if (_nextLevelInstructionsLevel != null &&
              _nextLevelInstructionsLevel! > currentLevel) {
            effectiveContestantLevel = _nextLevelInstructionsLevel!;
          } else if (status == 'active' || countdownActive || status == 'countdown') {
            effectiveContestantLevel = currentLevel;
          } else {
            effectiveContestantLevel = sessionEffectiveLevel;
          }

          // PRIORITY: show this contestant's Proceed/Eliminated decision before
          // preparation, instructions, result, waiting-room, or countdown UI.
          // The decision screen remains visible until the contestant taps NEXT LEVEL / PROCEED.
          final myContestantUid = FirebaseAuth.instance.currentUser?.uid ?? '';
          final officialRanksRaw = quizData['officialRanks'];
          int? sessionOfficialRank;
          if (officialRanksRaw is Map && officialRanksRaw.containsKey(myContestantUid)) {
            final raw = officialRanksRaw[myContestantUid];
            sessionOfficialRank = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
          }

          if (_contestantDecision == 'eliminated') {
            return _contestantDecisionScreen(
              eliminated: true,
              nextLevel: (_contestantDecisionLevel ?? currentLevel) + 1,
              officialRank: sessionOfficialRank,
            );
          }

          final bool alreadyProceededForLevel = _contestantDecisionLevel != null && (
            (_lastProceededDecisionLevel != null && _lastProceededDecisionLevel! >= _contestantDecisionLevel!) ||
            (_nextLevelInstructionsLevel != null && _nextLevelInstructionsLevel! > _contestantDecisionLevel!) ||
            (_showNextLevelInstructions && effectiveContestantLevel > _contestantDecisionLevel!)
          );

          if (_contestantDecision == 'proceeding' &&
              _contestantDecisionLevel != null &&
              !_showNextLevelInstructions &&
              !alreadyProceededForLevel) {
            return _contestantDecisionScreen(
              eliminated: false,
              nextLevel: _contestantDecisionLevel! + 1,
              officialRank: sessionOfficialRank,
            );
          }

          synchronizedCountdown = countdown;

          // ==================================================
          // LEVEL PREPARATION COMMAND (QUIZ MASTER STARTED LEVEL)
          // ==================================================
          // When the Quiz Master clicks START LEVEL 2 (or any level) from Contestant Readiness,
          // Firestore sets:
          //   eventStatus: 'preparing_to_begin'
          //   readyCheckType: 'level'
          //   preparedLevel: targetLevel
          //   status: 'waiting'
          // ALL contestants MUST immediately see the QuizPreparationScreen ("LEVEL X IS ABOUT TO START!"),
          // replacing any instructions screen or decision screen!
          final eventStatus = quizData['eventStatus']
              ?.toString()
              .trim()
              .toLowerCase();
          final readyCheckType = quizData['readyCheckType']
              ?.toString()
              .trim()
              .toLowerCase();
          final int effectivePreparedLevel = preparedLevel ??
              int.tryParse(quizData['currentLevel']?.toString() ?? '') ??
              currentLevel;
          final int targetInstructionsLevel = targetNextLevel ?? effectiveContestantLevel;
          final bool isLevelPreparationCommand =
              eventStatus == 'preparing_to_begin' &&
              (readyCheckType == 'level' || quizData['readyCheckType'] == null) &&
              status == 'waiting' &&
              !countdownActive &&
              effectivePreparedLevel >= targetInstructionsLevel;

          if (isLevelPreparationCommand &&
              status != 'active' &&
              status != 'ended' &&
              status != 'finished') {
            _showNextLevelInstructions = false;
            _nextLevelInstructionsLevel = null;
            _showLocalLevelResults = false;
            answered = false;
            submitting = false;
            resultRevealed = false;
            nextReadyConfirmed = false;
            nextQuestionConfirmed = false;
            confirmedQuestionIndex = -1;
            final int preparationLevel = effectivePreparedLevel;

            return QuizPreparationScreen(
              currentQuestion: currentQuestion,
              currentLevel: preparationLevel,
            );
          }

          // ==================================================
          // NEXT LEVEL INSTRUCTIONS DIRECT FLOW
          // ==================================================
          // When the contestant clicks PROCEED to advance to the next level:
          // They MUST see the next level instructions screen directly, while waiting
          // for the Quiz Master to start the next level preparation from contestant readiness.
          final bool nextLevelHasActuallyStarted = targetNextLevel != null &&
              currentLevel >= targetNextLevel &&
              (status == 'active' || status == 'countdown' || countdownActive);

          if (_showNextLevelInstructions &&
              targetNextLevel != null &&
              !nextLevelHasActuallyStarted &&
              !isLevelPreparationCommand &&
              status != 'finished') {
            return QuizInstructionsScreen(
              quizData: quizData,
              level: targetNextLevel,
              quizCode: widget.quizCode,
            );
          }

          // Once the level begins (Level 2, 3, etc.), mark the transition as complete.
          // The contestant is now actively playing this level and must never be shown
          // the level instructions screen again during gameplay or results.
          final bool levelHasBegun = currentLevel >= effectiveContestantLevel &&
              (status == 'active' || status == 'countdown' || countdownActive);

          if (levelHasBegun) {
            _showNextLevelInstructions = false;
            _nextLevelInstructionsLevel = null;
            instructionsShownThisSession = true;
          }

          // If sessionTimer reaches 0 during an active question, ensure result is revealed immediately
          if (status == 'active' && sessionTimer <= 0 && !readyCheckActive && !countdownActive) {
            if (answered && !resultRevealed) {
              resultRevealed = true;
            } else if (!answered && !submitting) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !answered && !submitting) {
                  saveAnswer(currentQuestion, "", timedOut: true);
                }
              });
            }
          }

          // ==================================================
          // QUIZ MASTER MOVED ON
          // ==================================================
          // The result screen stays visible (with the CONFIRM / CANCEL
          // card) until the Quiz Master moves on. Then the contestant
          // joins the 3-2-1-GO countdown together with everyone else.
          if (previousQuestion >= 0 &&
              previousQuestion != currentQuestion &&
              (countdownActive || status == "countdown" || status == "active" || status == "finished")) {
            previousQuestion = currentQuestion;
            nextQuestionConfirmed = false;
            nextQuestionReadySavedForId = null;
            nextReadyConfirmed = false;
            confirmedQuestionIndex = -1;
            _showLocalLevelResults = false;

            SharedPreferences.getInstance().then((prefs) async {
              if (prefs.getString(_contestantQuizCodeKey) == widget.quizCode) {
                await prefs.setBool(_contestantQuizNextReadyKey, false);
                await prefs.remove('contestant_quiz_confirmed_question');
              }
            });

            answered = false;
            submitting = false;
            selectedAnswer = null;
            showHurryUp = false;
            resultRevealed = false;
            _timerExpiredWhileSubmitting = false;
            currentAnswerTimedOut = false;
            resetContestState(); // also resets nextReadyConfirmed

            answerInputController.clear();
            contestExplanationController.clear();

            timer?.cancel();
            timerStartedForQuestion = -1;

            // New question: clear the old "confirmed" flag in Firestore.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) saveResultConfirmed(false);
            });
          }

          // ==================================================
          // LEVEL START WAITING PAGE HAS PRIORITY
          // ==================================================
          // When the Quiz Master presses START LEVEL 1 (or starts a later
          // level), show this page immediately, even if the contestant still
          // has stale first-question instructions/result state in memory.
          // This is intentionally limited to level-start ready checks.
          final isLevelStartReadyCheck =
              readyCheckActive &&
              quizData['readyCheckType']?.toString().trim().toLowerCase() ==
                  'level';

          if (isLevelStartReadyCheck && !countdownActive) {
            currentReadyCheckId = readyCheckId;

            // Do not flash the level waiting room after GO. Keep the GO
            // screen until Firestore finishes closing the ready check.
            if (_countdownWasActive) {
              return synchronizedCountdownScreen(
                0,
                questionNumber: _getQuestionNumberWithinLevel(currentQuestion),
              );
            }

            return readyWaitingScreen(
              currentQuestion: currentQuestion,
              levelStart: true,
              currentLevel: currentLevel,
              quizData: quizData,
            );
          }

          final int activeQuestionIndexForMetrics =
              (answered && resultRevealed && previousQuestion >= 0)
              ? previousQuestion
              : currentQuestion;
          final activeLevelMetrics = _getLevelPositionForGlobalIndex(
            activeQuestionIndexForMetrics,
          );
          if (activeLevelMetrics.totalInLevel > 0) {
            _currentLevelQuestionNumber = activeLevelMetrics.numberInLevel;
            _currentLevelQuestionTotal = activeLevelMetrics.totalInLevel;
            _currentQuestionLevel = activeLevelMetrics.level;
          }

          // ==================================================
          // LAST QUESTION: NEXT OPENS THIS LEVEL'S SCORE DIRECTLY
          // ==================================================
          if (_showLocalLevelResults) {
            return levelPauseScreen(_currentQuestionLevel);
          }

          // ==================================================
          // RESULT SCREEN HAS PRIORITY
          // ==================================================
          // Once the contestant submits (or time runs out), show the
          // result immediately. Do not let Ready Check or Countdown
          // hide it.
          if (answered && resultRevealed) {
            final resultLevel = activeLevelMetrics.level > 0
                ? activeLevelMetrics.level
                : (currentQuestionData != null &&
                          currentQuestionData!.isNotEmpty
                      ? getLevelFromSessionQuestion(
                          currentQuestionData!,
                          fallbackQuestionNumber: (previousQuestion >= 0 ? previousQuestion : currentQuestion) + 1,
                        )
                      : getLevelFromQuestionNumber((previousQuestion >= 0 ? previousQuestion : currentQuestion) + 1));

            final resultPoints = getPointsForLevel(resultLevel);

            return resultScreen(
              points: resultPoints,
              readyCheckActive: readyCheckActive,
              readyCheckId: readyCheckId,
              isLastQuestionInLevel:
                  _currentLevelQuestionTotal > 0 &&
                  _currentLevelQuestionNumber == _currentLevelQuestionTotal,
              currentLevel: _currentQuestionLevel,
            );
          }

          // ==================================================
          // READY CHECK
          //
          // First question: CONFIRM -> Instructions -> WAIT.
          // Later questions: Result (CONFIRM / CANCEL) -> countdown.
          // Quiz Master still controls the synchronized countdown.
          // ==================================================
          if (readyCheckActive && readyCheckId.isNotEmpty) {
            currentReadyCheckId = readyCheckId;

            if (instructionsShownThisSession &&
                nextQuestionConfirmed &&
                readyStatusSavedForId != readyCheckId) {
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                if (!mounted) return;

                await saveReadyStatus(ready: true, readyCheckId: readyCheckId);

                if (mounted) {
                  setState(() {
                    readyStatusSavedForId = readyCheckId;
                    lastReadyCheckId = readyCheckId;
                  });
                }
              });
            }
          }

          // ==================================================
          // FINISHED
          // ==================================================

          if (status == "finished") {
            return finishedScreen();
          }

          // ==================================================
          // LEVEL PAUSE
          // ==================================================

          if (status == "level_pause") {
            final level =
                int.tryParse(quizData['currentLevel']?.toString() ?? '') ??
                getLevelFromQuestionNumber(currentQuestion + 1);

            // Once the contestant has clicked PROCEED to next level,
            // keep them on the next level instructions screen rather than
            // showing an old completion card or waiting screen.
            if (effectiveContestantLevel > level) {
              return QuizInstructionsScreen(
                quizData: quizData,
                level: effectiveContestantLevel,
                quizCode: widget.quizCode,
              );
            }

            return levelPauseScreen(level);
          }

          // ==================================================
          // MANUAL PAUSE (Quiz Master pressed PAUSE QUIZ)
          //
          // The timer is stopped while paused. When the Quiz Master
          // resumes, the timer continues from the remaining seconds.
          // ==================================================

          if (status == "paused") {
            timer?.cancel();
            wasPaused = true;

            return pausedScreen();
          }

          if (wasPaused && status == "active") {
            wasPaused = false;

            final remaining =
                int.tryParse(quizData['timer']?.toString() ?? '') ?? timeLeft;

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;

              // Continue only if the result is not revealed yet.
              if (!resultRevealed) {
                startTimer(startFrom: remaining);
              }
            });
          }

          // ==================================================
          // SYNCHRONIZED COUNTDOWN
          //
          // This takes priority over the question UI. The
          // contestant must not see or answer the question
          // while the Quiz Master countdown is active.
          // ==================================================

          if (countdownActive) {
            return synchronizedCountdownScreen(
              countdown,
              questionNumber: _getQuestionNumberWithinLevel(currentQuestion),
            );
          }

          // FIRST QUESTION ONLY: keep the countdown/GO hand-off latched while
          // the initial ready check is being closed. Once the ready check is
          // off, continue directly to the question UI instead of returning to
          // Waiting Room just because status/timer snapshots are not in sync.
          if (_firstQuestionCountdownHandoff &&
              currentQuestion == 0 &&
              readyCheckActive) {
            return synchronizedCountdownScreen(
              0,
              questionNumber: _getQuestionNumberWithinLevel(currentQuestion),
            );
          }

          // For later questions, keep GO visible until Firestore has finished
          // handing off to the active question. The first question is handled
          // by the dedicated latch above so it can render without a Waiting
          // Room flash even if the status/timer update arrives a little later.
          if (_countdownWasActive &&
              !_firstQuestionCountdownHandoff &&
              (readyCheckActive || status != "active" || sessionTimer <= 0)) {
            return synchronizedCountdownScreen(
              0,
              questionNumber: _getQuestionNumberWithinLevel(currentQuestion),
            );
          }

          // Release the first-question latch only after its active status and
          // timer are both available; otherwise keep the direct question flow.
          if (_firstQuestionCountdownHandoff &&
              currentQuestion == 0 &&
              status == "active" &&
              sessionTimer > 0 &&
              !readyCheckActive) {
            _firstQuestionCountdownHandoff = false;
          }

          if (_countdownWasActive && status == "active" && sessionTimer > 0) {
            _countdownWasActive = false;
          }

          // ==================================================
          // READY WAITING
          //
          // After pressing CONFIRM, the contestant stays here until
          // the Quiz Master starts the synchronized countdown.
          // ==================================================

          if (readyCheckActive) {
            return readyWaitingScreen(
              currentQuestion: currentQuestion,
              levelStart: quizData['readyCheckType']?.toString() == 'level',
              currentLevel: currentLevel,
              quizData: quizData,
            );
          }

          // ==================================================
          // WAITING
          // ==================================================

          if (status != "active" &&
              !(_firstQuestionCountdownHandoff && currentQuestion == 0)) {
            final int targetWaitingLevel = effectiveContestantLevel;
            final isFirstQuestionInLevel = _getQuestionNumberWithinLevel(currentQuestion) <= 1;
            if (isFirstQuestionInLevel &&
                !instructionsShownThisSession &&
                currentQuestion == 0 &&
                currentLevel == 1 &&
                quizData['startedAt'] == null) {
              return QuizInstructionsScreen(
                quizData: quizData,
                level: targetWaitingLevel,
                quizCode: widget.quizCode,
              );
            }
            return _greenWaitingForNextQuestionScreen();
          }

          // ==================================================
          // NEW QUESTION
          //
          // This happens ONLY when Quizmaster changes
          // currentQuestion.
          // ==================================================

          if (previousQuestion != currentQuestion &&
              !readyCheckActive &&
              !countdownActive) {
            previousQuestion = currentQuestion;
            nextQuestionConfirmed = false;
            nextReadyConfirmed = false;
            confirmedQuestionIndex = -1;
            nextQuestionReadySavedForId = null;
            _showLocalLevelResults = false;

            answered = false;
            submitting = false;
            selectedAnswer = null;

            showHurryUp = false;

            resultRevealed = false;
            _timerExpiredWhileSubmitting = false;
            currentAnswerTimedOut = false;

            resetContestState(); // also resets nextReadyConfirmed

            answerInputController.clear();

            contestExplanationController.clear();

            timer?.cancel();
            timerStartedForQuestion = -1;

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;

              // The question may already have been selected by the
              // Quiz Master while contestants were still in Ready
              // Check. Do not start the 30-second timer until the
              // synchronized countdown has finished.
              if (!readyCheckActive &&
                  !countdownActive &&
                  status == 'active' &&
                  sessionTimer > 0) {
                startTimer(startFrom: sessionTimer);
                timerStartedForQuestion = currentQuestion;
              }

              updateLiveRank();

              // New question: clear the old "confirmed" flag in Firestore.
              saveResultConfirmed(false);

              loadExistingResponse(currentQuestion);
            });
          } else if (!readyCheckActive &&
              !countdownActive &&
              timerStartedForQuestion != currentQuestion) {
            // The currentQuestion can stay the same while the
            // Quiz Master runs the ready check/countdown. Once the
            // countdown ends, start the 30-second timer exactly once.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;

              if (!readyCheckActive &&
                  !countdownActive &&
                  status == 'active' &&
                  sessionTimer > 0 &&
                  timerStartedForQuestion != currentQuestion) {
                startTimer(startFrom: sessionTimer);
                timerStartedForQuestion = currentQuestion;
              }
            });
          }

          // ==================================================
          // LOAD QUESTIONS
          // ==================================================

          return FutureBuilder<QuerySnapshot>(
            future: _questionsFuture,
            builder: (context, questionSnapshot) {
              if (!questionSnapshot.hasData) {
                return const Scaffold(
                  backgroundColor: lightGreen,
                  body: Center(
                    child: CircularProgressIndicator(color: primaryGreen),
                  ),
                );
              }

              final questions = sortSessionQuestions(
                questionSnapshot.data!.docs,
              );
              _sortedSessionQuestions = questions;

              if (questions.isEmpty) {
                return const Scaffold(
                  backgroundColor: lightGreen,
                  body: Center(
                    child: Text(
                      "No Questions Available",
                      style: TextStyle(
                        color: textDark,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              }

              if (currentQuestion < 0 || currentQuestion >= questions.length) {
                return const Scaffold(
                  backgroundColor: lightGreen,
                  body: Center(
                    child: Text(
                      "Waiting for Quiz Master...",
                      style: TextStyle(
                        color: darkGreen,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              }

              final displayQuestionIndex = currentQuestion;

              final question = questions[displayQuestionIndex];

              final questionData = question.data() as Map<String, dynamic>;

              currentQuestionType = getQuestionType(questionData);

              currentCorrectAnswer = getCorrectAnswer(questionData);

              // The session list uses a global index, but the displayed
              // question number should restart at 1 for each level.
              final questionNumber = displayQuestionIndex + 1;

              final currentLevel = getLevelFromSessionQuestion(
                questionData,
                fallbackQuestionNumber: questionNumber,
              );

              var levelQuestionNumber = 0;
              var levelQuestionTotal = 0;
              for (var i = 0; i < questions.length; i++) {
                final itemData = questions[i].data() as Map<String, dynamic>;
                final itemLevel = getLevelFromSessionQuestion(
                  itemData,
                  fallbackQuestionNumber: i + 1,
                );
                if (itemLevel == currentLevel) {
                  levelQuestionTotal++;
                  if (i <= displayQuestionIndex) {
                    levelQuestionNumber++;
                  }
                }
              }

              final rawQuestionText =
                  questionData['question']?.toString() ?? '';
              final displayQuestionText = rawQuestionText.replaceFirst(
                RegExp(r'^\\s*QUESTION\\s+\\d+', caseSensitive: false),
                'QUESTION $levelQuestionNumber',
              );

              final points = getPointsForLevel(currentLevel);

              // Cache the level-specific question position for resultScreen,
              // which is checked earlier in the build method.
              _currentLevelQuestionNumber = levelQuestionNumber;
              _currentLevelQuestionTotal = levelQuestionTotal;
              _currentQuestionLevel = currentLevel;

              currentQuestionData = questionData;
              currentQuestionDocId = question.id;

              final isTextQuestion =
                  currentQuestionType == "Identification" ||
                  currentQuestionType == "Enumeration";

              final isTrueFalse = currentQuestionType == "True or False";

              // ==================================================
              // MAIN QUIZ SCREEN
              // ==================================================

              return Scaffold(
                backgroundColor: lightGreen,
                endDrawer: _buildQuizSideMenuDrawer(),
                appBar: AppBar(
                  backgroundColor: Colors.white,
                  elevation: 0,
                  surfaceTintColor: Colors.transparent,
                  centerTitle: true,
                  automaticallyImplyLeading: false,
                  toolbarHeight: 52,
                  title: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          "Question $levelQuestionNumber / $levelQuestionTotal",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: textDark,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: currentLevel == 1
                              ? const Color(0xFFE8F7EC)
                              : currentLevel == 2
                              ? const Color(0xFFEDE7FF)
                              : const Color(0xFFFFF3D6),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: currentLevel == 1
                                ? const Color(0xFFB7E4C7)
                                : currentLevel == 2
                                ? const Color(0xFFD5C7FF)
                                : const Color(0xFFFFD98A),
                          ),
                        ),
                        child: Text(
                          "LEVEL $currentLevel",
                          maxLines: 1,
                          style: TextStyle(
                            color: currentLevel == 1
                                ? const Color(0xFF168447)
                                : currentLevel == 2
                                ? const Color(0xFF7038C9)
                                : const Color(0xFF9A6700),
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  iconTheme: const IconThemeData(color: primaryGreen),
                  actions: [
                    Builder(
                      builder: (scaffoldContext) => IconButton(
                        tooltip: 'Live Ranking & Menu',
                        icon: const Icon(Icons.menu_rounded),
                        onPressed: () {
                          Scaffold.of(scaffoldContext).openEndDrawer();
                        },
                      ),
                    ),
                  ],
                ),
                body: Stack(
                  children: [
                    const Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(painter: TechCircuitPainter()),
                      ),
                    ),
                    Positioned.fill(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          MediaQuery.sizeOf(context).width >= 700 ? 28 : 14,
                          MediaQuery.sizeOf(context).height < 600 ? 6 : 10,
                          MediaQuery.sizeOf(context).width >= 700 ? 28 : 14,
                          MediaQuery.sizeOf(context).height < 600 ? 76 : 90,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // ==================================================
                                // TIMER
                                // ==================================================
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: timeLeft <= 5
                                          ? Colors.red
                                          : borderGreen,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        timeLeft <= 5
                                            ? Icons.timer_off_rounded
                                            : Icons.timer_rounded,
                                        color: timeLeft <= 5
                                            ? Colors.red
                                            : primaryGreen,
                                        size: 28,
                                      ),
                                      const SizedBox(height: 3),
                                      const Text(
                                        "TIME LEFT",
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        resultRevealed ? "0" : "$timeLeft",
                                        style: TextStyle(
                                          fontSize: 32,
                                          fontWeight: FontWeight.bold,
                                          color: timeLeft <= 5
                                              ? Colors.red
                                              : primaryGreen,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 14),

                                // ==================================================
                                // QUESTION
                                // ==================================================
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: borderGreen),
                                  ),
                                  // Give Text the full card width so centered
                                  // alignment is calculated against the card,
                                  // not just the text's intrinsic width.
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: Text(
                                      displayQuestionText,
                                      style: const TextStyle(
                                        color: textDark,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        height: 1.35,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 14),

                                // ==================================================
                                // ANSWERS
                                // ==================================================
                                if (isTextQuestion)
                                  textAnswerField()
                                else if (isTrueFalse) ...[
                                  trueFalseButton("True"),
                                  trueFalseButton("False"),
                                ] else ...[
                                  ...getQuestionOptions(
                                    questionData,
                                  ).map((option) => answerButton(option)),
                                ],

                                // ==================================================
                                // RESULT
                                // ==================================================
                                submittedWaitingCard(),

                                resultCard(points: points),

                                // ==================================================
                                // CONTEST
                                // ==================================================
                                contestAnswerButton(),

                                // ==================================================
                                // CONTEST REALTIME STATUS
                                // ==================================================
                                if (contestStatus != "none" &&
                                    contestRequestId != null)
                                  contestStatusListener(
                                    questionIndex: displayQuestionIndex,
                                  ),

                                // ==================================================
                                // YOU ARE READY? (CONFIRM / CANCEL)
                                // ==================================================
                                waitingForNextQuestion(
                                  readyCheckActive: readyCheckActive,
                                  readyCheckId: readyCheckId,
                                  isLastQuestionInLevel:
                                      levelQuestionNumber == levelQuestionTotal,
                                  currentLevel: currentLevel,
                                ),

                                // ==================================================
                                // CORRECT AFTER CONTEST
                                // ==================================================
                                if (answered &&
                                    resultRevealed &&
                                    contestStatus == "approved" &&
                                    lastAnswerCorrect)
                                  Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(top: 12),
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: softGreen,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: const Color(0xFF86C995),
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.verified_rounded,
                                          color: primaryGreen,
                                        ),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            "Contest approved! "
                                            "Your answer is now correct "
                                            "and points have been awarded.",
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: darkGreen,
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
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

                    // ==================================================
                    // FIXED DOWN SUBMIT BUTTON
                    // ==================================================
                    if (!answered)
                      Positioned(
                        right: 14,
                        bottom: 18,
                        child: Builder(
                          builder: (context) {
                            final isTextQuestion =
                                currentQuestionType == "Identification" ||
                                currentQuestionType == "Enumeration";

                            final hasAnswer = isTextQuestion
                                ? answerInputController.text.trim().isNotEmpty
                                : selectedAnswer != null;

                            final disabled =
                                submitting || !hasAnswer || answered;

                            return Material(
                              color: Colors.transparent,
                              elevation: 7,
                              shape: const CircleBorder(),
                              child: InkWell(
                                onTap: disabled
                                    ? null
                                    : () {
                                        final answer = isTextQuestion
                                            ? answerInputController.text.trim()
                                            : selectedAnswer!;

                                        saveAnswer(currentQuestion, answer);
                                      },
                                customBorder: const CircleBorder(),
                                child: Container(
                                  width: 58,
                                  height: 58,
                                  decoration: BoxDecoration(
                                    color: disabled
                                        ? const Color(0xFFB7D8C0)
                                        : primaryGreen,
                                    shape: BoxShape.circle,
                                  ),
                                  child: submitting
                                      ? const Padding(
                                          padding: EdgeInsets.all(17),
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.arrow_forward_rounded,
                                          color: Colors.white,
                                          size: 30,
                                        ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ==========================================================
  // CONGRATULATIONS RANKING SCREEN (When Quizmaster finishes quiz)
  // ==========================================================
  Widget _buildFinishedCongratulationsScreen(BuildContext context, String uid) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _joinRequestRef(uid).snapshots(),
        builder: (context, joinSnap) {
          final jData = joinSnap.data?.data() ?? const <String, dynamic>{};

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('quiz_sessions')
                .doc(widget.quizCode)
                .collection('scores')
                .snapshots(),
            builder: (context, scoresSnap) {
              final scoreDocs = scoresSnap.data?.docs ?? [];

              // Calculate rank dynamically if not yet synced in join request
              int computedRank = 1;
              if (scoreDocs.isNotEmpty) {
                final sorted = [...scoreDocs]
                  ..sort((a, b) {
                    final int sA =
                        int.tryParse(a.data()['score']?.toString() ?? '') ?? 0;
                    final int sB =
                        int.tryParse(b.data()['score']?.toString() ?? '') ?? 0;
                    if (sB != sA) return sB.compareTo(sA);
                    final rawA = a.data()['updatedAt'];
                    final rawB = b.data()['updatedAt'];
                    final int tA =
                        rawA is Timestamp ? rawA.millisecondsSinceEpoch : 0;
                    final int tB =
                        rawB is Timestamp ? rawB.millisecondsSinceEpoch : 0;
                    if (tA > 0 && tB > 0 && tA != tB) return tA.compareTo(tB);
                    return a.id.compareTo(b.id);
                  });
                final myIdx = sorted.indexWhere((d) => d.id == uid);
                if (myIdx >= 0) computedRank = myIdx + 1;
              }

              final rawRank = jData['finalRank'] ?? jData['rank'];
              final int finalRank = (rawRank is num && rawRank > 0)
                  ? rawRank.toInt()
                  : computedRank;

              final rawTeam = (jData['teamName'] ?? '').toString().trim();
              final rawMembers = jData['teamMembers'] ?? jData['members'];
              final List<String> members = [];
              if (rawMembers is List) {
                for (final m in rawMembers) {
                  final s = m is Map
                      ? (m['name'] ?? m['displayName'] ?? '').toString().trim()
                      : m.toString().trim();
                  if (s.isNotEmpty) members.add(s);
                }
              }
              final bool isTeam = jData['isTeam'] == true ||
                  jData['contestantType'] == 'team' ||
                  rawTeam.isNotEmpty ||
                  members.isNotEmpty;
              final String displayName = isTeam
                  ? (rawTeam.isNotEmpty ? rawTeam : (jData['name'] ?? 'Team'))
                  : (jData['realName'] ??
                      jData['fullName'] ??
                      jData['name'] ??
                      'Contestant');

              final int finalScore = int.tryParse(
                      (jData['finalScore'] ?? jData['score'] ?? '')
                          .toString()) ??
                  (scoreDocs.where((d) => d.id == uid).isNotEmpty
                      ? (int.tryParse(scoreDocs
                                  .firstWhere((d) => d.id == uid)
                                  .data()['score']
                                  ?.toString() ??
                              '') ??
                          0)
                      : 0);

              final isTop3 = finalRank >= 1 && finalRank <= 3;

              String trophyAsset;
              Color rankColor;
              String rankSubtitle;
              if (finalRank == 1) {
                trophyAsset = 'assets/trophies/gold_trophy_3d.jpg';
                rankColor = const Color(0xFFF59E0B);
                rankSubtitle = "CHAMPION • 1ST PLACE";
              } else if (finalRank == 2) {
                trophyAsset = 'assets/trophies/silver_trophy_3d.jpg';
                rankColor = const Color(0xFF94A3B8);
                rankSubtitle = "1ST RUNNER-UP • 2ND PLACE";
              } else if (finalRank == 3) {
                trophyAsset = 'assets/trophies/bronze_trophy_3d.jpg';
                rankColor = const Color(0xFFD97706);
                rankSubtitle = "2ND RUNNER-UP • 3RD PLACE";
              } else {
                trophyAsset = 'assets/trophies/top10_badge_3d.jpg';
                rankColor = const Color(0xFF3B82F6);
                rankSubtitle = "COMPETITOR • RANK #$finalRank";
              }

              return TechCircuitBackground(
                child: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 28),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: rankColor.withValues(alpha: 0.25),
                                blurRadius: 28,
                                offset: const Offset(0, 10),
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            border: Border.all(
                              color: rankColor.withValues(alpha: 0.4),
                              width: 1.8,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Top Tag: QUIZ COMPLETED
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color: const Color(0xFFCBD5E1)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.flag_rounded,
                                        color: Color(0xFF0F172A), size: 14),
                                    SizedBox(width: 6),
                                    Text(
                                      "QUIZ COMPLETED",
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.0,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 18),

                              // Trophy / Badge Image with glow
                              Container(
                                width: 130,
                                height: 130,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: rankColor.withValues(alpha: 0.35),
                                      blurRadius: 24,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: ClipOval(
                                  child: Image.asset(
                                    trophyAsset,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: rankColor.withValues(alpha: 0.15),
                                      child: Icon(
                                        isTop3
                                            ? Icons.emoji_events_rounded
                                            : Icons.military_tech_rounded,
                                        size: 72,
                                        color: rankColor,
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Header: CONGRATULATIONS!
                              Text(
                                isTop3 ? "CONGRATULATIONS!" : "WELL DONE!",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                  color: isTop3
                                      ? const Color(0xFFD97706)
                                      : const Color(0xFF1E3A8A),
                                ),
                              ),

                              const SizedBox(height: 6),

                              // Big Rank Banner: "YOU'RE RANK 1!"
                              Container(
                                margin:
                                    const EdgeInsets.symmetric(vertical: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 8),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: isTop3
                                        ? [
                                            rankColor,
                                            rankColor.withValues(alpha: 0.8)
                                          ]
                                        : [
                                            const Color(0xFF2563EB),
                                            const Color(0xFF1D4ED8)
                                          ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: rankColor.withValues(alpha: 0.4),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  "YOU'RE RANK $finalRank!",
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),

                              Text(
                                rankSubtitle,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: rankColor,
                                  letterSpacing: 0.5,
                                ),
                              ),

                              const SizedBox(height: 18),
                              const Divider(
                                  height: 1, color: Color(0xFFE2E8F0)),
                              const SizedBox(height: 16),

                              // Name / Team
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isTeam
                                        ? Icons.groups_rounded
                                        : Icons.person_rounded,
                                    size: 20,
                                    color: const Color(0xFF2563EB),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      displayName,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              if (isTeam && members.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  "Members: ${members.join(', ')}",
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],

                              const SizedBox(height: 16),

                              // Score Box
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color: const Color(0xFFE2E8F0)),
                                ),
                                child: Column(
                                  children: [
                                    const Text(
                                      "FINAL SCORE",
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.0,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "$finalScore PTS",
                                      style: const TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF16A34A),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 22),

                              // Action: Return to Dashboard button
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    await _clearQuizScreenPersistence();
                                    if (!context.mounted) return;
                                    Navigator.of(context).pushAndRemoveUntil(
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              const CompetitorDashboard()),
                                      (route) => false,
                                    );
                                  },
                                  icon: const Icon(Icons.dashboard_rounded,
                                      color: Colors.white, size: 20),
                                  label: const Text(
                                    "RETURN TO DASHBOARD",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14.5,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2563EB),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(25),
                                    ),
                                    elevation: 4,
                                    shadowColor: const Color(0xFF2563EB)
                                        .withValues(alpha: 0.4),
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
              );
            },
          );
        },
      ),
    );
  }

  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    timer?.cancel();
    _contestantDecisionSubscription?.cancel();

    answerInputController.dispose();

    contestExplanationController.dispose();

    super.dispose();
  }
}

// ============================================================
// PARTIAL RANKING (CONTESTANT, VIEW ONLY)
//
// Shows rank, name and points only. There are no ELIMINATE or
// ANNOUNCE controls here. Those stay on the Quiz Master side.
// ============================================================

class PartialRankingScreen extends StatelessWidget {
  final String quizCode;
  final bool isFinal;

  const PartialRankingScreen({
    super.key,
    required this.quizCode,
    this.isFinal = false,
  });

  static const Color primaryGreen = Color(0xFF16A34A);
  static const Color darkGreen = Color(0xFF166534);
  static const Color lightGreen = Color(0xFFF0FDF4);
  static const Color softGreen = Color(0xFFE8F7EC);
  static const Color borderGreen = Color(0xFFDCEFE1);
  static const Color textDark = Color(0xFF172033);

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    final session = FirebaseFirestore.instance
        .collection('quiz_sessions')
        .doc(quizCode);

    return TechCircuitBackground(
      baseColor: lightGreen,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: !isFinal
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: primaryGreen),
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                )
              : null,
          leadingWidth: !isFinal ? 44 : 16,
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
          titleSpacing: !isFinal ? 0 : 16,
          iconTheme: const IconThemeData(color: primaryGreen),
          title: Text(
            isFinal ? "Final Results" : "Partial Ranking",
            style: const TextStyle(
              color: textDark,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: session.snapshots(),
          builder: (context, sessSnap) {
            final sessionData = sessSnap.data?.data();
            final sessionStatus =
                sessionData?['status']?.toString().toLowerCase().trim() ?? '';
            final bool isActuallyFinal = isFinal ||
                sessionStatus == 'finished' ||
                sessionStatus == 'completed';
            final officialRanks = sessionData?['officialRanks'];

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: session.collection('scores').snapshots(),
              builder: (context, scoreSnap) {
                if (!scoreSnap.hasData && !scoreSnap.hasError) {
                  return const Center(
                    child: CircularProgressIndicator(color: primaryGreen),
                  );
                }

                // Approved contestants are used only to also list people who
                // have 0 points (no score document yet). If it cannot be read,
                // the ranking still works using the scores only.
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: session
                      .collection('join_requests')
                      .where('status', isEqualTo: 'approved')
                      .snapshots(),
                  builder: (context, contestantSnap) {
                    final scoreDocs = scoreSnap.data?.docs ?? [];
                    final contestants = contestantSnap.hasError
                        ? <QueryDocumentSnapshot<Map<String, dynamic>>>[]
                        : (contestantSnap.data?.docs ?? []);

                    final scoreById = <String, Map<String, dynamic>>{
                      for (final s in scoreDocs) s.id: s.data(),
                    };
                    final contestantById = <String, Map<String, dynamic>>{
                      for (final c in contestants) c.id: c.data(),
                    };
                    final allUids = <String>{
                      ...scoreById.keys,
                      ...contestantById.keys,
                    };

                    final rows = <Map<String, dynamic>>[];

                    for (final uid in allUids) {
                      final sData = scoreById[uid] ?? const <String, dynamic>{};
                      final cData = contestantById[uid] ?? const <String, dynamic>{};

                      final status = (cData['status'] ?? sData['status'] ?? '').toString().trim().toLowerCase();
                      if (status == 'left' || status == 'rejected' || status == 'declined' || status == 'pending') {
                        continue;
                      }

                      final rawR = sData['rank'] ??
                          sData['levelRank'] ??
                          sData['currentRank'] ??
                          sData['rankAtProceed'] ??
                          cData['rank'] ??
                          cData['levelRank'] ??
                          cData['currentRank'] ??
                          cData['rankAtProceed'];
                      int? assignedR = rawR is num
                          ? rawR.toInt()
                          : int.tryParse(rawR?.toString() ?? '');
                      if (officialRanks is Map && officialRanks.containsKey(uid)) {
                        final offR = officialRanks[uid];
                        final parsed = offR is num
                            ? offR.toInt()
                            : int.tryParse(offR?.toString() ?? '');
                        if (parsed != null && parsed > 0) assignedR = parsed;
                      }

                      final rawTime = sData['updatedAt'] ??
                          sData['answeredAt'] ??
                          sData['lastAnsweredAt'];
                      final int timeVal = rawTime is Timestamp
                          ? rawTime.millisecondsSinceEpoch
                          : (rawTime is num ? rawTime.toInt() : 0);

                      final rawMembers = cData['teamMembers'] ??
                          cData['members'] ??
                          sData['teamMembers'] ??
                          sData['members'];
                      final List<String> membersList = [];
                      if (rawMembers is List) {
                        for (final m in rawMembers) {
                          final s = m is Map
                              ? (m['name'] ?? m['displayName'] ?? m['fullName'] ?? '').toString().trim()
                              : m.toString().trim();
                          if (s.isNotEmpty && !membersList.contains(s)) membersList.add(s);
                        }
                      }

                      final rawTeam = (cData['teamName'] ?? sData['teamName'] ?? '').toString().trim();
                      final cType = (cData['contestantType'] ?? sData['contestantType'] ?? '').toString().trim().toLowerCase();
                      final bool isTeam = cType == 'team' ||
                          cData['isTeam'] == true ||
                          sData['isTeam'] == true ||
                          rawTeam.isNotEmpty ||
                          membersList.isNotEmpty;

                      final personalName = (cData['realName'] ??
                              cData['fullName'] ??
                              sData['fullName'] ??
                              cData['displayName'] ??
                              cData['name'] ??
                              sData['name'] ??
                              cData['email'] ??
                              uid)
                          .toString()
                          .trim();

                      final teamName = rawTeam.isNotEmpty
                          ? rawTeam
                          : (isTeam && membersList.isNotEmpty ? (rawTeam.isNotEmpty ? rawTeam : personalName) : '');

                      final displayName = isTeam
                          ? (teamName.isNotEmpty ? teamName : personalName)
                          : personalName;

                      final isElim = sData['eliminated'] == true ||
                          sData['status']?.toString().toLowerCase() == 'eliminated' ||
                          cData['eliminated'] == true ||
                          cData['isEliminated'] == true ||
                          cData['status']?.toString().toLowerCase() == 'eliminated';

                      rows.add({
                        'uid': uid,
                        'name': displayName,
                        'personalName': personalName,
                        'team': isTeam ? teamName : '',
                        'isTeam': isTeam,
                        'members': membersList,
                        'score': int.tryParse((sData['score'] ?? cData['score'])?.toString() ?? '') ?? 0,
                        'rank': assignedR,
                        'time': timeVal,
                        'eliminated': isElim,
                      });
                    }

              rows.sort((a, b) {
                if (isActuallyFinal) {
                  final aElim = a['eliminated'] == true;
                  final bElim = b['eliminated'] == true;
                  if (aElim != bElim) return aElim ? 1 : -1;
                }
                final byScore = (b['score'] as int).compareTo(
                  a['score'] as int,
                );
                if (byScore != 0) return byScore;

                final rA = a['rank'] as int?;
                final rB = b['rank'] as int?;
                if (rA != null && rB != null && rA != rB) {
                  return rA.compareTo(rB);
                } else if (rA != null) {
                  return -1;
                } else if (rB != null) {
                  return 1;
                }

                final tA = a['time'] as int? ?? 0;
                final tB = b['time'] as int? ?? 0;
                if (tA > 0 && tB > 0 && tA != tB) {
                  return tA.compareTo(tB);
                } else if (tA > 0 && tB == 0) {
                  return -1;
                } else if (tB > 0 && tA == 0) {
                  return 1;
                }

                return (a['name'] as String).compareTo(b['name'] as String);
              });

              // Competition ranking: equal scores share the same rank
              final ranks = <int>[];
              for (int i = 0; i < rows.length; i++) {
                if (officialRanks is Map && officialRanks.containsKey(rows[i]['uid'])) {
                  final offR = officialRanks[rows[i]['uid']];
                  final parsed = offR is num ? offR.toInt() : int.tryParse(offR?.toString() ?? '');
                  if (parsed != null && parsed > 0) {
                    ranks.add(parsed);
                    continue;
                  }
                }
                if (i > 0 && rows[i]['score'] == rows[i - 1]['score']) {
                  ranks.add(ranks[i - 1]);
                } else {
                  ranks.add(i + 1);
                }
              }

              final myIndex = rows.indexWhere((r) => r['uid'] == myUid);
              final myRow = myIndex >= 0 ? rows[myIndex] : null;
              final myRank = myIndex >= 0 ? ranks[myIndex] : null;
              final isMyEliminated =
                  myIndex >= 0 && rows[myIndex]['eliminated'] == true;

              return SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(18),
                        children: [
                          if (isActuallyFinal && myRank != null) ...[
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 20,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: isMyEliminated
                                      ? [const Color(0xFFF1F5F9), const Color(0xFFE2E8F0)]
                                      : (myRank == 1
                                          ? [const Color(0xFFFEF3C7), const Color(0xFFFDE68A)]
                                          : (myRank == 2
                                              ? [const Color(0xFFF1F5F9), const Color(0xFFE2E8F0)]
                                              : (myRank == 3
                                                  ? [const Color(0xFFFFEDD5), const Color(0xFFFED7AA)]
                                                  : [const Color(0xFFDCFCE7), const Color(0xFFBBF7D0)]))),
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: isMyEliminated
                                      ? Colors.grey.shade400
                                      : (myRank == 1
                                          ? const Color(0xFFF59E0B)
                                          : (myRank == 2
                                              ? const Color(0xFF94A3B8)
                                              : (myRank == 3
                                                  ? const Color(0xFFF97316)
                                                  : const Color(0xFF86EFAC)))),
                                  width: 2.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: (myRank == 1
                                            ? const Color(0xFFF59E0B)
                                            : primaryGreen)
                                        .withValues(alpha: 0.16),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    width: 70,
                                    height: 70,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isMyEliminated
                                            ? Colors.grey.shade400
                                            : (myRank == 1
                                                ? const Color(0xFFF59E0B)
                                                : (myRank == 2
                                                    ? const Color(0xFF94A3B8)
                                                    : (myRank == 3
                                                        ? const Color(0xFFF97316)
                                                        : primaryGreen))),
                                        width: 2.5,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.08),
                                          blurRadius: 10,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Icon(
                                        isMyEliminated
                                            ? Icons.sentiment_neutral_rounded
                                            : (myRank == 1
                                                ? Icons.emoji_events_rounded
                                                : (myRank == 2 || myRank == 3
                                                    ? Icons.military_tech_rounded
                                                    : Icons.stars_rounded)),
                                        size: 40,
                                        color: isMyEliminated
                                            ? Colors.grey.shade600
                                            : (myRank == 1
                                                ? const Color(0xFFD97706)
                                                : (myRank == 2
                                                    ? const Color(0xFF475569)
                                                    : (myRank == 3
                                                        ? const Color(0xFFC2410C)
                                                        : primaryGreen))),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    isMyEliminated
                                        ? "QUIZ COMPLETED"
                                        : (myRank <= 3
                                            ? "CONGRATULATIONS!"
                                            : "GREAT EFFORT!"),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: isMyEliminated
                                          ? Colors.grey.shade800
                                          : (myRank == 1
                                              ? const Color(0xFF78350F)
                                              : (myRank == 2
                                                  ? const Color(0xFF1E293B)
                                                  : (myRank == 3
                                                      ? const Color(0xFF7C2D12)
                                                      : darkGreen))),
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: isMyEliminated
                                            ? Colors.grey.shade400
                                            : (myRank == 1
                                                ? const Color(0xFFF59E0B)
                                                : (myRank == 2
                                                    ? const Color(0xFF94A3B8)
                                                    : (myRank == 3
                                                        ? const Color(0xFFF97316)
                                                        : primaryGreen))),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Text(
                                      isMyEliminated
                                          ? "PARTICIPANT"
                                          : (myRank == 1
                                              ? "YOU ARE RANK 1 • CHAMPION 🏆"
                                              : (myRank == 2
                                                  ? "YOU ARE RANK 2 • 1ST RUNNER-UP 🥈"
                                                  : (myRank == 3
                                                      ? "YOU ARE RANK 3 • 2ND RUNNER-UP 🥉"
                                                      : "YOU ARE RANK $myRank 🎖️"))),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: isMyEliminated
                                            ? Colors.grey.shade700
                                            : (myRank == 1
                                                ? const Color(0xFF92400E)
                                                : (myRank == 2
                                                    ? const Color(0xFF1E293B)
                                                    : (myRank == 3
                                                        ? const Color(0xFF9A3412)
                                                        : darkGreen))),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                  if (myRow != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      "Final Score: ${myRow['score']} pts",
                                      style: TextStyle(
                                        color: Colors.black.withValues(alpha: 0.7),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                          if (isActuallyFinal) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF064E25),
                                    Color(0xFF07883D),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryGreen.withValues(alpha: 0.22),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: Colors.amber.withValues(alpha: 0.18),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.amber.shade300,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.emoji_events_rounded,
                                          color: Colors.amber,
                                          size: 26,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "OFFICIAL WINNERS PODIUM",
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 0.6,
                                              ),
                                            ),
                                            SizedBox(height: 2),
                                            Text(
                                              "Congratulations to our top performers!",
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  if (rows.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 20,
                                      ),
                                      child: Center(
                                        child: Text(
                                          "No scores yet.",
                                          style: TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ),
                                    )
                                  else
                                    ...List.generate(rows.length, (i) {
                                      final row = rows[i];
                                      final rank = ranks[i];
                                      final isMe = row['uid'] == myUid;
                                      final eliminated =
                                          row['eliminated'] == true;

                                      final String titleLabel = eliminated
                                          ? 'ELIMINATED'
                                          : rank == 1
                                          ? 'CHAMPION • RANK 1'
                                          : rank == 2
                                          ? '1ST RUNNER-UP • RANK 2'
                                          : rank == 3
                                          ? '2ND RUNNER-UP • RANK 3'
                                          : 'FINALIST • RANK $rank';

                                      final Color badgeColor = eliminated
                                          ? Colors.grey.shade600
                                          : rank == 1
                                          ? Colors.amber.shade600
                                          : rank == 2
                                          ? Colors.blueGrey.shade300
                                          : rank == 3
                                          ? Colors.orange.shade400
                                          : Colors.white24;

                                      return Container(
                                        width: double.infinity,
                                        margin: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 13,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 
                                            rank == 1 ? 0.20 : 0.12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: rank == 1
                                                ? Colors.amber.shade300
                                                : isMe
                                                ? Colors.greenAccent.shade200
                                                : Colors.white24,
                                            width: (rank == 1 || isMe)
                                                ? 1.6
                                                : 1.0,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            if (eliminated)
                                              Container(
                                                width: 42,
                                                height: 42,
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade600,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Center(
                                                  child: Icon(
                                                    Icons.close_rounded,
                                                    color: Colors.white,
                                                    size: 20,
                                                  ),
                                                ),
                                              )
                                            else if (rank <= 10)
                                              TechRankLeaderboardIcon(
                                                rank: rank,
                                                size: 34,
                                              )
                                            else
                                              Container(
                                                width: 42,
                                                height: 42,
                                                decoration: BoxDecoration(
                                                  color: badgeColor,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    '#$rank',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.w900,
                                                      fontSize: 15,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      if (!eliminated &&
                                                          rank <= 3) ...[
                                                        Icon(
                                                          Icons
                                                              .workspace_premium_rounded,
                                                          size: 14,
                                                          color: rank == 1
                                                              ? Colors
                                                                    .amber
                                                                    .shade300
                                                              : Colors.white70,
                                                        ),
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                      ],
                                                      Flexible(
                                                        child: Text(
                                                          titleLabel,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            color: rank == 1
                                                                ? Colors
                                                                      .amber
                                                                      .shade300
                                                                : Colors
                                                                      .white70,
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            letterSpacing: 0.5,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    isMe
                                                        ? '${row['name']} (You)'
                                                        : row['name'] as String,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  if (row['isTeam'] == true &&
                                                      (row['members'] as List<String>?)?.isNotEmpty == true) ...[
                                                    Padding(
                                                      padding: const EdgeInsets.only(top: 2),
                                                      child: Text(
                                                        'Members: ${(row['members'] as List<String>).join(', ')}',
                                                        maxLines: 2,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: const TextStyle(
                                                          color: Colors.white70,
                                                          fontSize: 11,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 11,
                                                    vertical: 6,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: rank == 1
                                                    ? Colors.amber.shade400
                                                    : Colors.white.withValues(alpha: 
                                                        0.16,
                                                      ),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: Text(
                                                '${row['score']} pts',
                                                style: TextStyle(
                                                  color: rank == 1
                                                      ? const Color(0xFF173426)
                                                      : Colors.white,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                ],
                              ),
                            ),
                          ] else ...[
                            if (rows.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 30),
                                child: Center(
                                  child: Text(
                                    "No scores yet.",
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ),
                              )
                            else
                              ...List.generate(rows.length, (i) {
                                final row = rows[i];
                                final rank = ranks[i];
                                final isMe = row['uid'] == myUid;

                                Color rankBadgeColor;
                                Color rankBorderColor;
                                Color rankTextColor;

                                if (rank == 1) {
                                  rankBadgeColor = const Color(0xFFFEF3C7);
                                  rankBorderColor = const Color(0xFFF59E0B);
                                  rankTextColor = const Color(0xFFB45309);
                                } else if (rank == 2) {
                                  rankBadgeColor = const Color(0xFFF1F5F9);
                                  rankBorderColor = const Color(0xFF94A3B8);
                                  rankTextColor = const Color(0xFF334155);
                                } else if (rank == 3) {
                                  rankBadgeColor = const Color(0xFFFFEDD5);
                                  rankBorderColor = const Color(0xFFF97316);
                                  rankTextColor = const Color(0xFFC2410C);
                                } else {
                                  rankBadgeColor = const Color(0xFFDCFCE7);
                                  rankBorderColor = primaryGreen;
                                  rankTextColor = darkGreen;
                                }

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isMe ? softGreen : Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isMe ? primaryGreen : borderGreen,
                                      width: isMe ? 1.8 : 1.2,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      if (rank <= 10)
                                        TechRankLeaderboardIcon(
                                          rank: rank,
                                          size: 32,
                                        )
                                      else
                                        Container(
                                          width: 40,
                                          height: 40,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: primaryGreen,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: const Color(0xFF86EFAC),
                                              width: 1.5,
                                            ),
                                          ),
                                          child: Text(
                                            '$rank',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  margin: const EdgeInsets.only(bottom: 3),
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 1.5,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: rankBadgeColor,
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(
                                                      color: rankBorderColor.withValues(alpha: 0.5),
                                                      width: 0.8,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    rank == 1
                                                        ? '🏆 RANK 1 • LEADER'
                                                        : (rank == 2
                                                            ? '🥈 RANK 2 • 2ND'
                                                            : (rank == 3
                                                                ? '🥉 RANK 3 • 3RD'
                                                                : 'RANK $rank')),
                                                    style: TextStyle(
                                                      color: rankTextColor,
                                                      fontSize: 9.5,
                                                      fontWeight: FontWeight.w800,
                                                      letterSpacing: 0.3,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Text(
                                              isMe
                                                  ? '${row['name']} (You)'
                                                  : row['name'] as String,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: textDark,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                              ),
                                            ),
                                            if (row['isTeam'] == true &&
                                                (row['members'] as List<String>?)?.isNotEmpty == true) ...[
                                              Padding(
                                                padding: const EdgeInsets.only(top: 2),
                                                child: Text(
                                                  'Members: ${(row['members'] as List<String>).join(', ')}',
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Color(0xFF5B7A9C),
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      Text(
                                        '${row['score']} pts',
                                        style: const TextStyle(
                                          color: darkGreen,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                          ],
                        ],
                      ),
                    ),
                    if (isActuallyFinal)
                      Container(
                        padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
                        decoration: const BoxDecoration(
                          color: Colors.transparent,
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final prefs =
                                  await SharedPreferences.getInstance();
                              await prefs.setString(
                                'contestant_last_page',
                                'dashboard',
                              );
                              await prefs.remove(
                                'contestant_current_quiz_code',
                              );
                              await prefs.remove(
                                'contestant_current_quiz_title',
                              );
                              await prefs.remove(
                                'contestant_current_quiz_level',
                              );
                              if (!context.mounted) return;
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(
                                  builder: (_) => const CompetitorDashboard(),
                                ),
                                (route) => false,
                              );
                            },
                            icon: const Icon(Icons.dashboard_rounded),
                            label: const Text(
                              'BACK TO DASHBOARD',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryGreen,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
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
}
