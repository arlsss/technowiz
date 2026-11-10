import 'dart:async';

import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

// NOTE: i-adjust ang path kung lahi ang folder sa final_ranking_screen.dart
// pananglitan: '../quizmaster/final_ranking_screen.dart'
import 'final_ranking_screen.dart';
import 'contestant_readiness_page.dart';
import 'quizmaster_dashboard.dart';
import 'quizmaster_theme.dart';
import '../../utils/refresh_blocker.dart';

class QuizControlScreen extends StatefulWidget {
  final String quizCode;
  final bool startImmediately;

  const QuizControlScreen({
    super.key,
    required this.quizCode,
    this.startImmediately = false,
  });

  @override
  State<QuizControlScreen> createState() => _QuizControlScreenState();
}

class _QuizControlScreenState extends State<QuizControlScreen> {
  static const String _quizMasterLastPageKey = 'technowiz_quizmaster_last_page';
  static const String _quizMasterCurrentQuizCodeKey =
      'technowiz_quizmaster_current_quiz_code';

  static const Color primaryBlue = Color(0xFF1565D8);
  static const Color darkBlue = Color(0xFF0B2E6B);
  static const Color background = Color(0xFFF7F9FC);

  Timer? _timer;
  Timer? _readyCheckTimer;
  static const int _readyCheckDurationSeconds = 10;
  int _readyCheckSecondsLeft = 0;

  int _secondsLeft = 0;
  // Per-question timer duration configured by Admin for the current level.
  int _configuredTimerSeconds = 30;
  int _currentQuestion = 0;
  int _totalQuestions = 0;
  int _currentLevel = 1;

  bool _isRunning = false;
  bool _isFinished = false;
  bool _isManuallyPaused = false;
  bool _readyCheckActive = false;
  // True after Level 2+ readiness is confirmed and the contestant preparation
  // screen is shown. The Quiz Master must press START in Quiz Control to begin.
  bool _levelPreparedForStart = false;

  int _countdown = 0;

  // Question waiting to be started after all contestants are ready.
  int? _pendingQuestionIndex;
  int? _pendingLevel;

  bool _contestReviewActive = false;
  bool _contestReviewBusy = false;
  int? _contestReviewQuestionIndex;

  String _status = 'waiting';

  // Final ranking: how many of the lowest-ranked contestants to eliminate.
  int _eliminateCount = 0;

  // Prevent repeated taps from opening the ranking screen multiple times.
  bool _finalRankingOpening = false;
  // When START NEXT LEVEL is clicked on Final Ranking, replace that route
  // with Contestant Readiness so Quiz Control does not flash in between.
  bool _replaceFinalRankingWithReadiness = false;

  // Prevent overlapping async question transitions and duplicate finish writes.
  bool _isAdvancingQuestion = false;
  bool _isFinishingQuiz = false;

  Map<String, dynamic>? _quizData;

  List<QueryDocumentSnapshot> _questions = [];

  // Once a quiz has started, prevent Android/system back from leaving Quiz
  // Control. The saved startedAt marker also protects this after a refresh.
  bool get _hasQuizStarted {
    if (_quizData?['startedAt'] != null) return true;
    if (_currentQuestion > 0) return true;
    final s = _status.toLowerCase().trim().replaceAll('-', '_').replaceAll(' ', '_');
    if (s.isEmpty) return false;
    return s != 'waiting';
  }

  @override
  void initState() {
    super.initState();
    RefreshBlocker.block();
    _rememberQuizControlPage();
    _loadQuiz();
  }

  Future<void> _rememberQuizControlPage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_quizMasterLastPageKey, 'quiz_control');
      await prefs.setString(_quizMasterCurrentQuizCodeKey, widget.quizCode);
    } catch (e) {
      debugPrint('Quiz Master control page save error: $e');
    }
  }

  @override
  void dispose() {
    RefreshBlocker.unblock();
    _timer?.cancel();
    _readyCheckTimer?.cancel();
    super.dispose();
  }

  // ============================================================
  // GET LEVEL FROM SELECTED QUESTION
  //
  // ADMIN'S SELECTED QUESTIONS USE:
  // sessionLevel: "Level 1" / "Level 2" / "Level 3"
  // ============================================================

  int _getQuestionLevel(QueryDocumentSnapshot question) {
    final data = question.data() as Map<String, dynamic>;

    final value = data['sessionLevel'] ?? data['level'] ?? 1;

    // Read any configured level number (Level 1, Level 2, Level 10, etc.).
    // Do not hard-code the flow to only Levels 1–3.
    if (value is num) {
      final numericLevel = value.toInt();
      return numericLevel > 0 ? numericLevel : 1;
    }

    final text = value.toString().trim();
    final match = RegExp(r'(\d+)').firstMatch(text);
    final parsedLevel = match == null ? null : int.tryParse(match.group(1)!);
    return (parsedLevel != null && parsedLevel > 0) ? parsedLevel : 1;
  }

  // ============================================================
  // GET LEVEL FROM QUESTION INDEX
  // ============================================================

  int _getLevel(int questionIndex) {
    if (_questions.isEmpty ||
        questionIndex < 0 ||
        questionIndex >= _questions.length) {
      return _currentLevel;
    }

    return _getQuestionLevel(_questions[questionIndex]);
  }

  // ============================================================
  // DISPLAY QUESTION NUMBER WITHIN ITS LEVEL
  // ============================================================

  int _getQuestionNumberWithinLevel(int questionIndex) {
    if (_questions.isEmpty ||
        questionIndex < 0 ||
        questionIndex >= _questions.length) {
      return 0;
    }

    final level = _getLevel(questionIndex);
    var number = 0;

    for (int i = 0; i <= questionIndex; i++) {
      if (_getQuestionLevel(_questions[i]) == level) {
        number++;
      }
    }

    return number;
  }

  // ============================================================
  // GET FIRST QUESTION INDEX OF LEVEL
  // ============================================================

  int? _getFirstQuestionIndexForLevel(int level) {
    for (int i = 0; i < _questions.length; i++) {
      if (_getQuestionLevel(_questions[i]) == level) {
        return i;
      }
    }

    return null;
  }

  // ============================================================
  // GET LAST QUESTION INDEX OF LEVEL
  // ============================================================

  int? _getLastQuestionIndexForLevel(int level) {
    int? lastIndex;

    for (int i = 0; i < _questions.length; i++) {
      if (_getQuestionLevel(_questions[i]) == level) {
        lastIndex = i;
      }
    }

    return lastIndex;
  }

  // ============================================================
  // CHECK IF LEVEL EXISTS
  // ============================================================

  bool _hasLevel(int level) {
    return _getFirstQuestionIndexForLevel(level) != null;
  }

  // ============================================================
  // SORT SELECTED QUESTIONS
  //
  // Already selected by Admin and copied into:
  // quiz_sessions/{quizCode}/questions
  // We only sort them by Admin's "order" field.
  // ============================================================

  List<QueryDocumentSnapshot> _sortSelectedQuestions(
    List<QueryDocumentSnapshot> docs,
  ) {
    final result = [...docs];

    int getLevel(QueryDocumentSnapshot doc) {
      // Use the same level parser used by the question screen and level flow,
      // so missing/alternate level values cannot sort differently from display.
      return _getQuestionLevel(doc);
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

    result.sort((a, b) {
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

    return result;
  }

  // ============================================================
  // FIND QUIZ SESSION
  // ============================================================

  Future<DocumentSnapshot<Map<String, dynamic>>?> _getQuizSession() async {
    // Prefer the quizCode document ID because the Quiz Master readiness
    // StreamBuilders listen to quiz_sessions/{quizCode}/join_requests.
    final directDoc = await FirebaseFirestore.instance
        .collection('quiz_sessions')
        .doc(widget.quizCode)
        .get();

    if (directDoc.exists) {
      return directDoc;
    }

    // Backward-compatible fallback for sessions whose document ID differs
    // from quizCode but whose quizCode field matches.
    final query = await FirebaseFirestore.instance
        .collection('quiz_sessions')
        .where('quizCode', isEqualTo: widget.quizCode)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      return query.docs.first;
    }

    return null;
  }

  // ============================================================
  // LOAD QUIZ
  // ============================================================

  Future<void> _loadQuiz() async {
    try {
      final quizDoc = await _getQuizSession();

      if (quizDoc == null || !quizDoc.exists) {
        if (!mounted) return;

        setState(() {
          _quizData = {'title': 'Quiz', 'status': 'waiting'};
          _status = 'waiting';
          _questions = [];
          _totalQuestions = 0;
        });

        return;
      }

      // LOAD ONLY ADMIN-SELECTED QUESTIONS
      final questionsSnapshot = await quizDoc.reference
          .collection('questions')
          .get();

      final sortedQuestions = _sortSelectedQuestions(questionsSnapshot.docs);

      final quizData = quizDoc.data() ?? {};

      final status = quizData['status']?.toString().toLowerCase() ?? 'waiting';

      final savedQuestion = quizData['currentQuestion'];
      final savedLevel = quizData['currentLevel'];
      final savedTimer = quizData['timer'];

      // A quiz with status 'paused' is always a manual pause.
      final savedManualPause =
          quizData['manuallyPaused'] == true || status == 'paused';
      // Normalize a persisted manual pause even if status was left as
      // 'active' by an earlier version. This keeps RESUME available after refresh.
      final restoredStatus = savedManualPause ? 'paused' : status;

      final savedReadyCheck = quizData['readyCheckActive'] == true;
      final savedCountdown = quizData['countdown'];
      final savedCountdownActive = quizData['countdownActive'] == true;

      // Restore the explicit START LEVEL button after the readiness page
      // prepares a new level. This marker is persisted in Firestore so the
      // button does not become disabled if Quiz Control rebuilds or reopens.
      final savedLevelPreparedForStart =
          status == 'waiting' &&
          quizData['readyCheckType']?.toString() == 'level' &&
          (quizData['eventStatus']?.toString() == 'preparing_to_begin' ||
              quizData['levelStartedAt'] != null);

      int restoredQuestion = 0;

      if (savedQuestion is num) {
        final savedIndex = savedQuestion.toInt();

        if (savedIndex >= 0 && savedIndex < sortedQuestions.length) {
          restoredQuestion = savedIndex;
        }
      }

      // The selected question's level is the source of truth.
      // A stale/mismatched Firestore currentLevel must not override the
      // level assigned to the actual question at currentQuestion.
      int restoredLevel = 1;

      if (sortedQuestions.isNotEmpty) {
        restoredLevel = _getQuestionLevel(sortedQuestions[restoredQuestion]);
      } else if (savedLevel is num) {
        final savedLevelNumber = savedLevel.toInt();
        if (savedLevelNumber >= 1) {
          restoredLevel = savedLevelNumber;
        }
      }

      int restoredTimer = 0;
      int restoredCountdown = 0;

      if (savedCountdown is num) {
        restoredCountdown = savedCountdown.toInt().clamp(0, 3).toInt();
      }

      if (savedTimer is num) {
        final timerValue = savedTimer.toInt();
        if (timerValue >= 0) {
          restoredTimer = timerValue;
        }
      }

      // Never show a running timer before the Quiz Master starts the question.
      if (restoredStatus == 'waiting' ||
          restoredStatus == 'countdown' ||
          (restoredStatus == 'level_pause' && !savedManualPause) ||
          restoredStatus == 'contest_review' ||
          restoredStatus == 'finished') {
        restoredTimer = 0;
      } else if ((restoredStatus == 'active' || restoredStatus == 'paused') &&
          restoredTimer <= 0) {
        restoredTimer = await _getLevelTimerSeconds(restoredLevel);
      }

      final configuredTimerSeconds = await _getLevelTimerSeconds(restoredLevel);
      if (!mounted) return;

      setState(() {
        _quizData = quizData;
        _configuredTimerSeconds = configuredTimerSeconds;
        _questions = sortedQuestions;
        _totalQuestions = sortedQuestions.length;
        _currentQuestion = restoredQuestion;
        _currentLevel = restoredLevel;
        _secondsLeft = restoredTimer;
        _isManuallyPaused =
            savedManualPause || (status == 'level_pause' && restoredTimer > 0);
        _readyCheckActive = savedReadyCheck;
        _countdown = restoredCountdown;

        if ((savedReadyCheck ||
                savedCountdownActive ||
                savedLevelPreparedForStart) &&
            sortedQuestions.isNotEmpty) {
          _pendingQuestionIndex = restoredQuestion;
          _pendingLevel = restoredLevel;
        } else {
          _pendingQuestionIndex = null;
          _pendingLevel = null;
        }

        _levelPreparedForStart = savedLevelPreparedForStart;

        // Old manual pauses were saved as 'level_pause' + manuallyPaused.
        // Treat them as 'paused' so the Resume button shows up.
        _status =
            (restoredStatus == 'level_pause' &&
                (savedManualPause || restoredTimer > 0))
            ? 'paused'
            : restoredStatus;
        _isRunning = restoredStatus == 'active';
        _isFinished = restoredStatus == 'finished';
      });

      // RESUME TIMER ONLY IF ACTIVE
      if (_isRunning && !_isFinished) {
        _startTimer();
      } else if (widget.startImmediately &&
          status == 'waiting' &&
          sortedQuestions.isNotEmpty) {
        // START NOW! has already checked that every approved contestant is
        // READY. Verify against Firestore again before starting Question 1.
        final everyoneReady = await _allApprovedContestantsReady();
        if (!mounted) return;

        if (!everyoneReady) {
          _showMessage(
            'Not all approved participants are READY yet. Please run Ready Check again.',
          );
          return;
        }

        final firstQuestion = _getFirstQuestionIndexForLevel(1);
        if (firstQuestion == null) {
          _showMessage('No Level 1 questions were selected.');
          return;
        }

        await _startQuestionCountdown(
          questionIndex: firstQuestion,
          level: _getLevel(firstQuestion),
        );
      }
    } catch (e) {
      if (!mounted) return;

      showQuizMasterTopNotification(
        context,
        'Unable to load quiz: $e',
        isError: true,
      );
    }
  }

  // ============================================================
  // START BUTTON: BEGIN LEVEL 1 COUNTDOWN
  // ============================================================

  bool _startingFromMainButton = false;

  Future<void> _startInitialCountdownFromButton() async {
    if (_startingFromMainButton || _isFinished || _isRunning) return;

    _startingFromMainButton = true;
    try {
      // If a readiness dialog was closed before starting, reuse the pending
      // question instead of accidentally returning to Question 1.
      final targetQuestion =
          _pendingQuestionIndex ?? _getFirstQuestionIndexForLevel(1);
      if (targetQuestion == null) {
        _showMessage('No questions are ready to start.');
        return;
      }
      final targetLevel = _pendingLevel ?? _getLevel(targetQuestion);

      // Initial Level 1 and a level already prepared through the
      // Contestant Readiness page must start directly after verifying READY.
      // Do not call _openReadyCheck here: _openReadyCheck resets every
      // approved contestant to ready=false, which would undo their Level 2+
      // confirmations and leave Quiz Control waiting again.
      final bool canStartPreparedLevel =
          _status == 'waiting' &&
          (targetLevel == 1 ||
              (_levelPreparedForStart && targetLevel == _currentLevel));

      if (canStartPreparedLevel) {
        final everyoneReady = await _allApprovedContestantsReady();
        if (!mounted) return;

        if (!everyoneReady) {
          _showMessage(
            'Not all approved contestants are READY yet. Please check the participant list.',
          );
          return;
        }

        setState(() => _levelPreparedForStart = false);

        await _startQuestionCountdown(
          questionIndex: targetQuestion,
          level: targetLevel,
        );
      } else {
        await _openReadyCheck(
          levelStart: targetLevel > _currentLevel,
          questionIndex: targetQuestion,
          level: targetLevel,
        );
      }
    } catch (e) {
      debugPrint('START READY CHECK ERROR: $e');
      if (mounted) {
        _showMessage('Unable to start the readiness check. Please try again.');
      }
    } finally {
      _startingFromMainButton = false;
    }
  }

  // ============================================================
  // READY CHECK
  // ============================================================

  Future<void> _startReadyCheck({
    int? questionIndex,
    int? level,
    bool levelStart = false,
  }) async {
    if (_isFinished || (_status != 'waiting' && _status != 'level_pause')) {
      return;
    }

    try {
      final quizDoc = await _getQuizSession();

      if (quizDoc == null) {
        _showMessage('Quiz session not found.');
        return;
      }

      final requests = await quizDoc.reference
          .collection('join_requests')
          .get();
      final scores = await quizDoc.reference
          .collection('scores')
          .get();
      final eliminatedScoreIds = <String>{
        for (final s in scores.docs)
          if (s.data()['eliminated'] == true ||
              s.data()['isEliminated'] == true ||
              s.data()['status']?.toString().toLowerCase() == 'eliminated')
            s.id,
      };

      final activeRequests = requests.docs.where((doc) {
        final data = doc.data();
        final status = (data['status'] ?? '').toString().trim().toLowerCase();
        if (status != 'approved' && status != 'proceeding' && status.isNotEmpty) {
          return false;
        }
        return !_isDocEliminated(doc, eliminatedScoreIds);
      }).toList();

      if (activeRequests.isEmpty) {
        _showMessage('No active approved contestants yet.');
        return;
      }

      final targetQuestion =
          questionIndex ?? _pendingQuestionIndex ?? _currentQuestion;

      final targetLevel = level ?? _pendingLevel ?? _getLevel(targetQuestion);

      if (_questions.isEmpty ||
          targetQuestion < 0 ||
          targetQuestion >= _questions.length) {
        _showMessage('No question is ready to start.');
        return;
      }

      final readyCheckId =
          '${DateTime.now().millisecondsSinceEpoch}_${targetQuestion}_$targetLevel';

      final batch = FirebaseFirestore.instance.batch();

      for (final doc in activeRequests) {
        batch.update(doc.reference, {
          'ready': false,
          'readyResponded': false,
          'readyAt': null,
          'readyCheckId': readyCheckId,
        });
      }

      batch.update(quizDoc.reference, {
        'readyCheckActive': true,
        'readyCheckType': levelStart ? 'level' : 'question',
        'readyCheckTitle': levelStart
            ? 'Level $targetLevel is about to begin'
            : 'Question ${targetQuestion + 1} is about to begin',
        'readyCheckMessage': levelStart
            ? 'Please review Level $targetLevel instructions and confirm that you are ready.'
            : 'The next question is about to begin. Please confirm that you are ready.',
        'readyCheckId': readyCheckId,
        'readyCheckStartedAt': FieldValue.serverTimestamp(),
        'readyCheckDeadline': Timestamp.fromDate(
          DateTime.now().add(
            const Duration(seconds: _readyCheckDurationSeconds),
          ),
        ),
        'readyCheckDurationSeconds': _readyCheckDurationSeconds,
        'readyCheckExpired': false,
        'countdownActive': false,
        'countdown': 0,
        'status': 'waiting',
        'currentQuestion': targetQuestion,
        'currentLevel': targetLevel,
        'timer': 0,
      });

      await batch.commit();

      _startReadyCheckTimer(
        quizRef: quizDoc.reference,
        readyCheckId: readyCheckId,
      );

      if (!mounted) return;

      setState(() {
        _readyCheckActive = true;
        _status = 'waiting';
        _isRunning = false;
        _pendingQuestionIndex = targetQuestion;
        _pendingLevel = targetLevel;
        _currentQuestion = targetQuestion;
        _currentLevel = targetLevel;
        _countdown = 0;
        _secondsLeft = 0;
      });

      // Readiness is shown directly on the Quiz Master screen
      // below the controls. It updates in real time.
    } catch (e) {
      debugPrint('START READY CHECK ERROR: $e');

      _showMessage('Unable to start ready check.');
    }
  }

  void _startReadyCheckTimer({
    required DocumentReference<Map<String, dynamic>> quizRef,
    required String readyCheckId,
  }) {
    _readyCheckTimer?.cancel();
    if (!mounted) return;

    setState(() => _readyCheckSecondsLeft = _readyCheckDurationSeconds);

    _readyCheckTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_readyCheckSecondsLeft > 1) {
        setState(() => _readyCheckSecondsLeft--);
        return;
      }

      timer.cancel();
      setState(() => _readyCheckSecondsLeft = 0);

      try {
        final requests = await quizRef
            .collection('join_requests')
            .get();
        final scores = await quizRef
            .collection('scores')
            .get();
        final eliminatedScoreIds = <String>{
          for (final s in scores.docs)
            if (s.data()['eliminated'] == true ||
                s.data()['isEliminated'] == true ||
                s.data()['status']?.toString().toLowerCase() == 'eliminated')
              s.id,
        };

        final activeRequests = requests.docs.where((doc) {
          final data = doc.data();
          final status = (data['status'] ?? '').toString().trim().toLowerCase();
          if (status != 'approved' && status != 'proceeding' && status.isNotEmpty) {
            return false;
          }
          return !_isDocEliminated(doc, eliminatedScoreIds);
        }).toList();

        final batch = FirebaseFirestore.instance.batch();
        for (final doc in activeRequests) {
          final data = doc.data();
          // Do not overwrite a newer readiness check.
          if (data['readyCheckId'] == readyCheckId && data['ready'] != true) {
            batch.update(doc.reference, {
              'ready': true,
              'readyResponded': true,
              'readyAt': FieldValue.serverTimestamp(),
              'readyAutomatically': true,
            });
          }
        }

        batch.set(quizRef, {
          'readyCheckActive': true,
          'readyCheckExpired': true,
          'readyCheckEndedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await batch.commit();
        if (mounted) {
          _showMessage(
            'Readiness time expired. All approved participants are now marked READY.',
          );
        }
      } catch (e) {
        debugPrint('AUTO-MARK READY ERROR: $e');
      }
    });
  }

  Future<bool> _allApprovedContestantsReady() async {
    final quizDoc = await _getQuizSession();

    if (quizDoc == null) return false;

    final requests = await quizDoc.reference
        .collection('join_requests')
        .get();
    final scores = await quizDoc.reference
        .collection('scores')
        .get();
    final eliminatedScoreIds = <String>{
      for (final s in scores.docs)
        if (s.data()['eliminated'] == true ||
            s.data()['isEliminated'] == true ||
            s.data()['status']?.toString().toLowerCase() == 'eliminated')
          s.id,
    };

    final eligibleDocs = requests.docs.where((doc) {
      if (eliminatedScoreIds.contains(doc.id)) return false;
      final data = doc.data();
      final status = (data['status'] ?? '').toString().trim().toLowerCase();
      final decision = (data['contestantDecision'] ?? '')
          .toString()
          .trim()
          .toLowerCase();

      if (status == 'left' ||
          status == 'rejected' ||
          status == 'declined' ||
          data['leftQuiz'] == true) {
        return false;
      }
      if (status == 'pending') {
        return false;
      }
      if (decision == 'eliminated' ||
          status == 'eliminated' ||
          data['eliminated'] == true ||
          data['isEliminated'] == true) {
        return false;
      }
      if (decision == 'proceeding' || status == 'proceeding') {
        return true;
      }
      return status == 'approved' || status.isEmpty;
    }).toList();

    if (eligibleDocs.isEmpty) return false;

    return eligibleDocs.every((doc) => doc.data()['ready'] == true);
  }

  Future<void> _resetReadyCheck() async {
    _readyCheckTimer?.cancel();
    if (mounted) setState(() => _readyCheckSecondsLeft = 0);
    try {
      final quizDoc = await _getQuizSession();

      if (quizDoc == null) return;

      final requests = await quizDoc.reference
          .collection('join_requests')
          .where('status', isEqualTo: 'approved')
          .get();

      final batch = FirebaseFirestore.instance.batch();

      for (final doc in requests.docs) {
        batch.update(doc.reference, {
          'ready': false,
          'readyResponded': false,
          'readyAt': null,
        });
      }

      batch.update(quizDoc.reference, {
        'readyCheckActive': false,
        'countdownActive': false,
        'readyCheckEndedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      if (!mounted) return;

      setState(() {
        _readyCheckActive = false;
      });
    } catch (_) {}
  }

  Future<void> _startQuestionCountdown({
    required int questionIndex,
    required int level,
  }) async {
    if (_isFinished) return;

    _timer?.cancel();

    final configuredSeconds = await _getLevelTimerSeconds(level);

    final quizDoc = await _getQuizSession();

    if (quizDoc == null) {
      _showMessage('Quiz session not found.');
      return;
    }

    await quizDoc.reference.update({
      'status': 'countdown',
      'eventStatus': 'countdown',
      'preparedLevel': FieldValue.delete(),
      'currentQuestion': questionIndex,
      'currentLevel': level,
      'countdown': 3,
      'countdownActive': true,
      'timer': 0,
      'readyCheckActive': false,
      'manuallyPaused': false,
      // Reset sa elimination announcement para sa bag-ong question/level
      'eliminationPublished': false,
    });

    if (!mounted) return;

    setState(() {
      _status = 'countdown';
      _isRunning = false;
      _currentQuestion = questionIndex;
      _currentLevel = level;
      _configuredTimerSeconds = configuredSeconds;
      _countdown = 3;
      _secondsLeft = 0;
      _readyCheckActive = false;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final next = _countdown - 1;

      if (next > 0) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        setState(() => _countdown = next);

        try {
          await quizDoc.reference.update({'countdown': next});
        } catch (_) {}

        return;
      }

      timer.cancel();

      // Keep the synchronized countdown screen on GO! for one second
      // before revealing the question.
      try {
        await quizDoc.reference.update({
          'status': 'countdown',
          'countdown': 0,
          'countdownActive': true,
          'timer': 0,
        });
      } catch (_) {
        return;
      }

      if (mounted) {
        setState(() => _countdown = 0);
      }

      await Future.delayed(const Duration(seconds: 1));

      try {
        await quizDoc.reference.update({
          'status': 'active',
          'countdown': 0,
          'countdownActive': false,
          'timer': configuredSeconds,
          'startedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {
        return;
      }

      if (!mounted) return;

      setState(() {
        _status = 'active';
        _isRunning = true;
        _countdown = 0;
        _secondsLeft = configuredSeconds;
      });

      _startTimer();
    });
  }

  // ============================================================
  // END CURRENT LEVEL AND OPEN ELIMINATION DIRECTLY
  // ============================================================

  Future<void> _endLevelAndOpenElimination() async {
    // END LEVEL is a Quiz Master-only navigation action. Do not call
    // _nextQuestion() here because it changes the shared Firestore quiz status
    // to level_pause/finished, which can force the contestant screen to change.
    if (_isFinished || _isAdvancingQuestion || _finalRankingOpening) return;

    ScaffoldMessenger.of(context).clearSnackBars();

    // Apply this level's configured elimination, then open Final Ranking.
    // Keep the quiz session status/current question unchanged so contestants
    // remain on their existing screen until the Quiz Master explicitly starts
    // the next level from Final Ranking.
    await _applyLevelElimination(_currentLevel);

    if (!mounted) return;
    await _openFinalRanking();
  }

  // ============================================================
  // START NEXT LEVEL
  // ============================================================

  Future<void> _startNextLevel() async {
    if (_isFinished) return;

    try {
      final quizDoc = await _getQuizSession();
      if (quizDoc == null) {
        _showMessage('Quiz session not found.');
        return;
      }
      if (!mounted) return;

      // Use the latest saved level as a fallback if the local Quiz Control
      // state is stale after returning from Final Ranking.
      final quizData = quizDoc.data() ?? <String, dynamic>{};
      final rawSavedLevel = quizData['currentLevel'] ?? quizData['level'];
      int savedLevel = _currentLevel;
      if (rawSavedLevel is num) {
        savedLevel = rawSavedLevel.toInt();
      } else if (rawSavedLevel != null) {
        final parsed = int.tryParse(
          rawSavedLevel.toString().replaceAll(RegExp(r'[^0-9]'), ''),
        );
        if (parsed != null) savedLevel = parsed;
      }
      final int nextLevel =
          savedLevel > _currentLevel ? savedLevel : _currentLevel + 1;

      // Refresh the session questions so any newly configured level is included.
      final freshQuestionsSnap = await quizDoc.reference
          .collection('questions')
          .get();
      final freshSortedQuestions = _sortSelectedQuestions(
        freshQuestionsSnap.docs,
      );
      if (mounted && freshSortedQuestions.isNotEmpty) {
        setState(() {
          _questions = freshSortedQuestions;
          _totalQuestions = freshSortedQuestions.length;
        });
      }

      // Continue dynamically for every configured level. The quiz ends only
      // when there is no next-level question in the selected question list.
      final nextQuestion = _getFirstQuestionIndexForLevel(nextLevel);

      if (nextQuestion == null) {
        _replaceFinalRankingWithReadiness = false;
        await _finishQuiz();
        return;
      }

      // Prepare the next level without starting its countdown.
      // Contestants who press NEXT LEVEL report READY while reviewing
      // that level's instructions. The Quiz Master starts the announcement.
      await quizDoc.reference.update({
        'status': 'waiting',
        'eventStatus': 'waiting_for_readiness',
        'preparedLevel': FieldValue.delete(),
        'currentQuestion': nextQuestion,
        'currentLevel': nextLevel,
        'level': nextLevel,
        'timer': 0,
        'countdown': 0,
        'countdownActive': false,
        'readyCheckActive': false,
        'readyCheckType': 'level',
        'readyCheckTitle': 'Level $nextLevel is about to begin',
        'readyCheckMessage':
            'Please review Level $nextLevel instructions and get ready.',
        'manuallyPaused': false,
      });

      if (!mounted) return;
      setState(() {
        _status = 'waiting';
        _isRunning = false;
        _isManuallyPaused = false;
        _secondsLeft = 0;
        _countdown = 0;
        _readyCheckActive = false;
        _currentQuestion = nextQuestion;
        _currentLevel = nextLevel;
        _pendingQuestionIndex = nextQuestion;
        _pendingLevel = nextLevel;
      });

      // Remember that the Quiz Master is on the readiness page for this event.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_quizMasterLastPageKey, 'participant_readiness');
      await prefs.setString(_quizMasterCurrentQuizCodeKey, widget.quizCode);

      if (!mounted) return;

      // Reuse the existing readiness page. Start the next level only after
      // that page confirms all approved contestants are READY.
      final readinessRoute = PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => ContestantReadinessPage(
          quizCode: widget.quizCode,
          startLevel: nextLevel,
          closeParentPagesOnStart: false,
          onStartQuiz: () async {
            final everyoneReady = await _allApprovedContestantsReady();
            if (!everyoneReady) {
              _showMessage('All approved contestants must be READY first.');
              return;
            }

            // Tell the contestant Waiting Room to show the green
            // "QUIZ IS ABOUT TO BEGIN!" screen for this level.
            // This is a preparation state, not a new Ready Check, so do
            // not set readyCheckActive=true (that would reopen the popup).
            final latestQuizDoc = await _getQuizSession();
            if (latestQuizDoc == null) {
              _showMessage('Quiz session not found.');
              return;
            }

            await latestQuizDoc.reference.update({
              'status': 'waiting',
              'eventStatus': 'preparing_to_begin',
              'preparedLevel': nextLevel,
              'preparationStartedAt': FieldValue.serverTimestamp(),
              // Fresh level-start marker so the contestant Waiting Room can
              // detect this preparation command for every level.
              'levelStartedAt': FieldValue.serverTimestamp(),
              'readyCheckActive': false,
              'readyCheckType': 'level',
              'readyCheckTitle': 'Level $nextLevel is about to begin',
              'readyCheckMessage':
                  'Please get ready. Level $nextLevel will begin shortly.',
              'countdownActive': false,
              'countdown': 0,
              'timer': 0,
              'currentQuestion': nextQuestion,
              'currentLevel': nextLevel,
            });

            // This click only announces preparation to contestants. Do not
            // start the countdown here: return the Quiz Master to Quiz Control
            // so START is the explicit trigger for the synchronized countdown.
            if (!mounted) return;
            setState(() {
              _levelPreparedForStart = true;
              _status = 'waiting';
              _isRunning = false;
              _readyCheckActive = false;
              _currentQuestion = nextQuestion;
              _currentLevel = nextLevel;
              _pendingQuestionIndex = nextQuestion;
              _pendingLevel = nextLevel;
              _countdown = 0;
              _secondsLeft = 0;
            });
            Navigator.of(context).pop();
          },
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        transitionsBuilder: (_, animation, secondaryAnimation, child) => child,
      );

      final replaceFinalRanking = _replaceFinalRankingWithReadiness;
      _replaceFinalRankingWithReadiness = false;

      if (replaceFinalRanking) {
        // Replace Final Ranking in-place. Quiz Control stays underneath, so
        // there is no visible return to its dashboard before readiness opens.
        await Navigator.of(context).pushReplacement(readinessRoute);
      } else {
        await Navigator.of(context).push(readinessRoute);
      }

      // Restore the saved page marker if the Quiz Master returns to controls.
      final updatedPrefs = await SharedPreferences.getInstance();
      await updatedPrefs.setString(_quizMasterLastPageKey, 'quiz_control');
      await updatedPrefs.setString(
        _quizMasterCurrentQuizCodeKey,
        widget.quizCode,
      );
    } catch (e, stackTrace) {
      _replaceFinalRankingWithReadiness = false;
      debugPrint('START NEXT LEVEL ERROR: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        _showMessage('Unable to start next level: $e');
      }
    }
  }

  // ============================================================
  // TIMER
  // ============================================================

  void _startTimer() {
    _timer?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isRunning || _isFinished) {
        timer.cancel();
        return;
      }

      if (_secondsLeft <= 1) {
        timer.cancel();

        if (mounted) {
          setState(() {
            _secondsLeft = 0;
          });
        }

        // Do NOT automatically move to the next question here.
        // The contestant must first see the Result screen.
        // The Quiz Master can proceed to the next question after
        // the contestant confirms.
        return;
      }

      if (mounted) {
        setState(() {
          _secondsLeft--;
        });
      }
    });
  }

  // ============================================================
  // PAUSE MANUALLY
  //
  // FIX: uses its own 'paused' status so it is no longer confused
  // with 'level_pause' (which means "level finished").
  // NOTE: the Contestant app must also handle status == 'paused'.
  // ============================================================

  Future<void> _pauseQuiz() async {
    _timer?.cancel();

    await _updateSession({
      'status': 'paused',
      'timer': _secondsLeft,
      'currentQuestion': _currentQuestion,
      'currentLevel': _currentLevel,
      'manuallyPaused': true,
    });

    if (!mounted) return;

    setState(() {
      _status = 'paused';
      _isRunning = false;
      _isManuallyPaused = true;
    });
  }

  // ============================================================
  // RESUME SAME QUESTION
  // ============================================================

  Future<void> _resumeQuiz() async {
    if (_isFinished) return;

    try {
      // Re-read the saved pause state so Resume still works after refresh,
      // even if this screen's local timer state was not restored correctly.
      final quizDoc = await _getQuizSession();
      if (quizDoc == null || !quizDoc.exists) {
        _showMessage('Quiz session not found. Please reopen Quiz Control.');
        return;
      }

      final data = quizDoc.data() ?? <String, dynamic>{};
      final rawTimer = data['timer'];
      var remaining = rawTimer is num ? rawTimer.toInt() : _secondsLeft;
      if (remaining <= 0) {
        remaining = _secondsLeft > 0
            ? _secondsLeft
            : await _getLevelTimerSeconds(_currentLevel);
      }

      await quizDoc.reference.update({
        'status': 'active',
        'timer': remaining,
        'currentQuestion': _currentQuestion,
        'currentLevel': _currentLevel,
        'manuallyPaused': false,
      });

      if (!mounted) return;
      setState(() {
        _status = 'active';
        _secondsLeft = remaining;
        _isRunning = true;
        _isManuallyPaused = false;
        _quizData = {
          ...?_quizData,
          ...data,
          'status': 'active',
          'timer': remaining,
          'manuallyPaused': false,
        };
      });

      _startTimer();
    } catch (e) {
      debugPrint('RESUME QUIZ ERROR: $e');
      _showMessage('Unable to resume quiz. Please try again.');
    }
  }

  // ============================================================
  // CONTEST REVIEW
  // ============================================================

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _getContestRequestsForQuestion(int questionIndex) async {
    final quizDoc = await _getQuizSession();

    if (quizDoc == null) {
      return [];
    }

    final snapshot = await quizDoc.reference
        .collection('contest_requests')
        .get();

    final requests = snapshot.docs.where((doc) {
      final data = doc.data();

      final questionNumber = data['questionNumber'];
      final status = data['status']?.toString().toLowerCase() ?? '';

      int? number;
      if (questionNumber is num) {
        number = questionNumber.toInt();
      } else {
        number = int.tryParse(questionNumber?.toString() ?? '');
      }

      return number == questionIndex + 1 &&
          (status == 'pending' ||
              status == 'approved' ||
              status == 'rejected' ||
              status == 'declined' ||
              status == 'invalid');
    }).toList();

    requests.sort((a, b) {
      final aCreated = a.data()['createdAt'];
      final bCreated = b.data()['createdAt'];

      if (aCreated is Timestamp && bCreated is Timestamp) {
        return aCreated.compareTo(bCreated);
      }

      return a.id.compareTo(b.id);
    });

    return requests;
  }

  Future<bool> _hasPendingContestRequests(int questionIndex) async {
    final requests = await _getContestRequestsForQuestion(questionIndex);

    return requests.any(
      (doc) => doc.data()['status']?.toString().toLowerCase() == 'pending',
    );
  }

  Future<void> _reviewContestRequest({
    required DocumentSnapshot<Map<String, dynamic>> request,
    required bool approve,
  }) async {
    if (_contestReviewBusy) {
      return;
    }

    setState(() {
      _contestReviewBusy = true;
    });

    try {
      final status = approve ? 'approved' : 'rejected';

      await request.reference.update({
        'status': status,
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': FirebaseAuth.instance.currentUser?.uid,
        'scoreApplied': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _showMessage(
          approve
              ? 'Contest checked and approved.'
              : 'Contest reviewed and rejected.',
        );
      }
    } catch (e) {
      debugPrint('REVIEW CONTEST ERROR: $e');

      if (mounted) {
        _showMessage('Unable to review this contest.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _contestReviewBusy = false;
        });
      }
    }
  }

  Future<void> _continueAfterContestReview() async {
    if (_contestReviewQuestionIndex == null || _contestReviewBusy) {
      return;
    }

    final questionIndex = _contestReviewQuestionIndex!;

    final hasPending = await _hasPendingContestRequests(questionIndex);

    if (hasPending) {
      _showMessage(
        'Please review all contestant contest requests before continuing.',
      );
      return;
    }

    if (!mounted) return;

    setState(() {
      _contestReviewActive = false;
      _contestReviewQuestionIndex = null;
    });

    await _nextQuestion(ignoreContestReview: true);
  }

  Widget _contestReviewCard() {
    if (!_contestReviewActive || _contestReviewQuestionIndex == null) {
      return const SizedBox.shrink();
    }

    final questionIndex = _contestReviewQuestionIndex!;
    final sessionRef = FirebaseFirestore.instance
        .collection('quiz_sessions')
        .doc(widget.quizCode);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: sessionRef.collection('join_requests').snapshots(),
      builder: (context, joinSnap) {
        final joinDocs = joinSnap.data?.docs ?? [];
        final Map<String, Map<String, dynamic>> joinByUid = {
          for (final j in joinDocs) j.id: j.data(),
        };

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: sessionRef.collection('contest_requests').snapshots(),
          builder: (context, snapshot) {
            final docs = (snapshot.data?.docs ?? []).where((doc) {
              final data = doc.data();
              final questionNumber = data['questionNumber'];

              int? number;
              if (questionNumber is num) {
                number = questionNumber.toInt();
              } else {
                number = int.tryParse(questionNumber?.toString() ?? '');
              }

              final status = data['status']?.toString().toLowerCase() ?? '';

              return number == questionIndex + 1 &&
                  (status == 'pending' ||
                      status == 'approved' ||
                      status == 'rejected' ||
                      status == 'declined' ||
                      status == 'invalid');
            }).toList();

            docs.sort((a, b) {
              final aCreated = a.data()['createdAt'];
              final bCreated = b.data()['createdAt'];

              if (aCreated is Timestamp && bCreated is Timestamp) {
                return aCreated.compareTo(bCreated);
              }

              return a.id.compareTo(b.id);
            });

            final pending = docs.where((doc) {
              return doc.data()['status']?.toString().toLowerCase() == 'pending';
            }).length;

            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.gavel_rounded,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'CONTEST REVIEW — QUESTION ${questionIndex + 1}',
                          style: const TextStyle(
                            color: darkBlue,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    pending > 0
                        ? '\$pending contestant contest request(s) need review.'
                        : 'All contest requests for this question have been reviewed.',
                    style: const TextStyle(color: Colors.black54, height: 1.35),
                  ),
                  const SizedBox(height: 14),
                  if (docs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No contest requests were submitted.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    )
                  else
                    ...docs.map((doc) {
                      final data = doc.data();
                      final uid = (data['contestantUid'] ?? doc.id.split('_').first).toString();
                      final jData = joinByUid[uid];

                      final rawTeam = (data['teamName'] ?? jData?['teamName'] ?? '').toString().trim();
                      final contestantType = (data['contestantType'] ?? jData?['contestantType'] ?? '').toString().trim().toLowerCase();
                      final bool isTeam = data['isTeam'] == true ||
                          contestantType == 'team' ||
                          jData?['isTeam'] == true ||
                          rawTeam.isNotEmpty;

                      final personalName = (jData?['realName'] ??
                              jData?['fullName'] ??
                              jData?['displayName'] ??
                              jData?['name'] ??
                              data['realName'] ??
                              data['contestantName'] ??
                              data['displayName'] ??
                              data['name'] ??
                              data['email'] ??
                              uid)
                          .toString().trim();

                      final teamName = rawTeam.isNotEmpty ? rawTeam : (isTeam ? personalName : '');
                      final displayName = isTeam
                          ? (teamName.isNotEmpty ? teamName : personalName)
                          : (personalName.isNotEmpty ? personalName : 'Contestant');

                      final rawMembers = data['teamMembers'] ?? data['members'] ?? jData?['teamMembers'] ?? jData?['members'];
                      final List<String> teamMembers = [];
                      if (rawMembers is List) {
                        for (final m in rawMembers) {
                          final s = m is Map ? (m['name'] ?? m['displayName'] ?? '').toString().trim() : m.toString().trim();
                          if (s.isNotEmpty && !teamMembers.contains(s)) teamMembers.add(s);
                        }
                      }

                      final answer =
                          data['contestantAnswer']?.toString().trim() ?? '';
                      final expected =
                          data['expectedAnswer']?.toString().trim() ?? '';
                      final explanation =
                          data['explanation']?.toString().trim() ?? '';
                      final status =
                          data['status']?.toString().toLowerCase() ?? 'pending';

                      final isPending = status == 'pending';
                      final isApproved = status == 'approved';

                      return Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: background,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: isPending
                                ? Colors.orange.shade200
                                : Colors.blue.shade100,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  isTeam ? Icons.groups_rounded : Icons.person_rounded,
                                  color: primaryBlue,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              displayName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: darkBlue,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                          if (isTeam) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: primaryBlue.withValues(alpha: 0.10),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Text(
                                                'TEAM',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  color: primaryBlue,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      if (isTeam && teamMembers.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 3),
                                          child: Text(
                                            'Members: ' + teamMembers.join(', '),
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade600,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isPending
                                        ? Colors.orange.withValues(alpha: 0.10)
                                        : isApproved
                                        ? Colors.green.withValues(alpha: 0.10)
                                        : Colors.red.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    isPending
                                        ? 'PENDING'
                                        : isApproved
                                        ? 'CHECKED'
                                        : 'REJECTED',
                                    style: TextStyle(
                                      color: isPending
                                          ? Colors.orange
                                          : isApproved
                                          ? Colors.green
                                          : Colors.red,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Contestant Answer',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              answer.isEmpty ? 'No answer provided.' : answer,
                              style: const TextStyle(
                                color: darkBlue,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              'Expected Answer',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              expected.isEmpty ? 'Not available.' : expected,
                              style: const TextStyle(color: darkBlue),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              'Explanation',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              explanation.isEmpty
                                  ? 'No explanation provided.'
                                  : explanation,
                              style: const TextStyle(color: darkBlue, height: 1.35),
                            ),
                            if (isPending) ...[
                              const SizedBox(height: 13),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _contestReviewBusy
                                          ? null
                                          : () => _reviewContestRequest(
                                              request: doc,
                                              approve: false,
                                            ),
                                      icon: const Icon(Icons.close_rounded),
                                      label: const Text('REJECT'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.red,
                                        side: const BorderSide(color: Colors.red),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 11,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _contestReviewBusy
                                          ? null
                                          : () => _reviewContestRequest(
                                              request: doc,
                                              approve: true,
                                            ),
                                      icon: const Icon(Icons.check_rounded),
                                      label: const Text('APPROVE'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 11,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: pending == 0 && !_contestReviewBusy
                          ? _continueAfterContestReview
                          : null,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text(
                        'CONTINUE TO NEXT QUESTION',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryBlue,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade300,
                        disabledForegroundColor: Colors.grey.shade600,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
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
  }

  // ============================================================
  // LEVEL TIMER SETTINGS
  // Reads the timer configured by Admin in:
  // quiz_sessions/{quizCode}.levelSettings["Level X"].timerSeconds
  // ============================================================

  Future<int> _getLevelTimerSeconds(int level) async {
    try {
      final quizDoc = await _getQuizSession();
      if (quizDoc == null) return 30;

      final data = quizDoc.data() ?? {};
      final rawSettings = data['levelSettings'];
      if (rawSettings is! Map) return 30;

      final rawLevelSettings = rawSettings['Level $level'];
      if (rawLevelSettings is! Map) return 30;

      final configured = _asInt(rawLevelSettings['timerSeconds']);
      if (configured == null || configured <= 0) return 30;

      return configured;
    } catch (e) {
      debugPrint('GET LEVEL TIMER ERROR: $e');
      return 30;
    }
  }

  // ============================================================
  // LEVEL ELIMINATION SETTINGS
  //
  // Reads the elimination count configured by Admin in:
  // quiz_sessions/{quizCode}.levelSettings["Level X"].eliminateCount
  // ============================================================

  Future<int> _getLevelEliminateCount(int level) async {
    try {
      final quizDoc = await _getQuizSession();

      if (quizDoc == null) return 0;

      final data = quizDoc.data() ?? {};
      final rawSettings = data['levelSettings'];

      if (rawSettings is! Map) return 0;

      final rawLevelSettings = rawSettings['Level $level'];

      if (rawLevelSettings is! Map) return 0;

      final value = rawLevelSettings['eliminateCount'];

      final count = _asInt(value) ?? 0;

      return count < 0 ? 0 : count;
    } catch (e) {
      debugPrint('GET LEVEL ELIMINATION ERROR: $e');
      return 0;
    }
  }

  // ============================================================
  // APPLY LEVEL ELIMINATION
  //
  // Called after the last question of a level and BEFORE the next
  // level starts.
  //
  // The lowest-scoring approved contestants are marked as
  // eliminated. At least one contestant is always kept.
  // ============================================================

  Future<int> _applyLevelElimination(int level) async {
    try {
      final quizDoc = await _getQuizSession();

      if (quizDoc == null) return 0;

      final eliminateCount = await _getLevelEliminateCount(level);

      if (eliminateCount <= 0) {
        await quizDoc.reference.set({
          'lastEliminationLevel': level,
          'lastEliminationCount': 0,
          'eliminationPublished': false,
        }, SetOptions(merge: true));

        return 0;
      }

      final requestsSnapshot = await quizDoc.reference
          .collection('join_requests')
          .where('status', isEqualTo: 'approved')
          .get();

      final contestants = requestsSnapshot.docs;

      if (contestants.length <= 1) {
        await quizDoc.reference.set({
          'lastEliminationLevel': level,
          'lastEliminationCount': 0,
          'eliminationPublished': false,
        }, SetOptions(merge: true));

        return 0;
      }

      final scoresSnapshot = await quizDoc.reference.collection('scores').get();

      final scoreById = <String, Map<String, dynamic>>{
        for (final doc in scoresSnapshot.docs) doc.id: doc.data(),
      };

      final rows = contestants.map((doc) {
        final data = doc.data();
        final scoreData = scoreById[doc.id];

        final score = _asInt(scoreData?['score']) ?? 0;

        final name =
            (data['displayName'] ??
                    data['name'] ??
                    scoreData?['name'] ??
                    data['email'] ??
                    doc.id)
                .toString();

        return {'doc': doc, 'score': score, 'name': name};
      }).toList();

      // Lowest score first because these are the contestants to eliminate.
      rows.sort((a, b) {
        final scoreCompare = (a['score'] as int).compareTo(b['score'] as int);

        if (scoreCompare != 0) return scoreCompare;

        return (a['name'] as String).compareTo(b['name'] as String);
      });

      // Never eliminate everyone.
      final maxEliminate = rows.length - 1;
      final actualEliminateCount = eliminateCount
          .clamp(0, maxEliminate)
          .toInt();

      if (actualEliminateCount <= 0) {
        await quizDoc.reference.set({
          'lastEliminationLevel': level,
          'lastEliminationCount': 0,
          'eliminationPublished': false,
        }, SetOptions(merge: true));

        return 0;
      }

      final batch = FirebaseFirestore.instance.batch();

      for (int i = 0; i < actualEliminateCount; i++) {
        final row = rows[i];
        final doc = row['doc'] as QueryDocumentSnapshot<Map<String, dynamic>>;
        final score = row['score'] as int;

        batch.update(doc.reference, {
          'status': 'eliminated',
          'eliminated': true,
          'eliminatedAfterLevel': level,
          'eliminatedScore': score,
          'eliminationReason': 'Lowest score after Level $level',
          'eliminatedAt': FieldValue.serverTimestamp(),
          'ready': false,
          'readyResponded': false,
          'readyAt': null,
          'resultConfirmed': false,
        });
      }

      batch.set(quizDoc.reference, {
        'lastEliminationLevel': level,
        'lastEliminationCount': actualEliminateCount,
        'eliminationPublished': true,
        'eliminationPublishedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();

      return actualEliminateCount;
    } catch (e) {
      debugPrint('APPLY LEVEL ELIMINATION ERROR: $e');

      if (mounted) {
        _showMessage('Unable to apply Level $level elimination.');
      }

      return 0;
    }
  }

  // ============================================================
  // NEXT QUESTION
  //
  // Detects the actual last selected question of the current level
  // and pauses there (level_pause) before the next level.
  // ============================================================

  Future<void> _nextQuestion({
    bool ignoreContestReview = false,
    bool skipReadyCheck = false,
    bool showLevelFinishedMessage = true,
  }) async {
    if (_totalQuestions == 0 || _isAdvancingQuestion || _isFinished) return;

    // Only one question transition may run at a time.
    _isAdvancingQuestion = true;
    if (mounted) setState(() {});
    try {
      if (!ignoreContestReview) {
        final hasPendingContest = await _hasPendingContestRequests(
          _currentQuestion,
        );

        if (hasPendingContest) {
          _timer?.cancel();

          await _updateSession({
            'status': 'contest_review',
            'timer': 0,
            'countdown': 0,
            'countdownActive': false,
            'readyCheckActive': false,
          });

          if (!mounted) return;

          setState(() {
            _status = 'contest_review';
            _isRunning = false;
            _contestReviewActive = true;
            _contestReviewQuestionIndex = _currentQuestion;
            _secondsLeft = 0;
          });

          return;
        }
      }

      if (_currentQuestion < 0 || _currentQuestion >= _questions.length) {
        await _finishQuiz();
        return;
      }

      final currentLevel = _getLevel(_currentQuestion);

      final lastQuestionOfCurrentLevel = _getLastQuestionIndexForLevel(
        currentLevel,
      );

      // CURRENT LEVEL FINISHED
      if (lastQuestionOfCurrentLevel != null &&
          _currentQuestion >= lastQuestionOfCurrentLevel) {
        _timer?.cancel();

        // Apply the elimination configured for this level before
        // allowing the next level to start.
        final eliminatedCount = await _applyLevelElimination(currentLevel);

        final nextLevel = currentLevel + 1;

        final nextQuestion = _getFirstQuestionIndexForLevel(nextLevel);

        if (nextQuestion == null) {
          await _finishQuiz();
          return;
        }

        await _updateSession({
          'status': 'level_pause',
          'currentQuestion': _currentQuestion,
          'currentLevel': currentLevel,
          'timer': 0,
          'countdown': 0,
          'countdownActive': false,
          'readyCheckActive': false,
          'manuallyPaused': false,
        });

        if (!mounted) return;

        setState(() {
          _status = 'level_pause';
          _isRunning = false;
          _isManuallyPaused = false;
          _currentLevel = currentLevel;
          _secondsLeft = 0;
          _pendingQuestionIndex = nextQuestion;
          _pendingLevel = nextLevel;
        });

        if (showLevelFinishedMessage) {
          if (eliminatedCount > 0) {
            _showMessage(
              'Level $currentLevel finished. '
              '$eliminatedCount contestant(s) eliminated. '
              'Press START LEVEL $nextLevel to continue.',
            );
          } else {
            _showMessage(
              'Level $currentLevel finished. '
              'No contestants were eliminated. '
              'Press START LEVEL $nextLevel to continue.',
            );
          }
        }

        return;
      }

      // NORMAL NEXT QUESTION
      // Start a fresh readiness round before each question transition.
      final next = _currentQuestion + 1;

      if (next >= _totalQuestions) {
        await _finishQuiz();
        return;
      }

      final nextLevel = _getLevel(next);

      _timer?.cancel();

      if (!mounted) return;

      setState(() {
        _isManuallyPaused = false;
        _pendingQuestionIndex = next;
        _pendingLevel = nextLevel;
      });

      // Switch back to waiting before opening a fresh readiness round.
      // The NEXT QUESTION flow stays in Quiz Control; the question countdown
      // starts only after every approved contestant is READY.
      await _updateSession({
        'status': 'waiting',
        'timer': 0,
        'countdown': 0,
        'countdownActive': false,
        'readyCheckActive': false,
        'manuallyPaused': false,
        'currentQuestion': next,
        'currentLevel': nextLevel,
      });

      if (!mounted) return;
      setState(() {
        _status = 'waiting';
        _isRunning = false;
        _secondsLeft = 0;
        _pendingQuestionIndex = next;
        _pendingLevel = nextLevel;
      });

      if (skipReadyCheck) {
        // Quiz Master explicitly chose to continue even if contestants have
        // not confirmed readiness. Start the synchronized countdown directly.
        await _startQuestionCountdown(questionIndex: next, level: nextLevel);
      } else {
        await _openReadyCheck(questionIndex: next, level: nextLevel);
      }
    } finally {
      _isAdvancingQuestion = false;
      if (mounted) setState(() {});
    }
  }

  // ============================================================
  // FINISH QUIZ
  // ============================================================

  Future<void> _finishQuiz() async {
    if (_isFinishingQuiz) return;
    _isFinishingQuiz = true;
    _timer?.cancel();

    try {
      final quizDoc = await _getQuizSession();

      if (quizDoc == null) {
        _showMessage('Quiz session not found.', isError: true);
        return;
      }

      final quizRef = quizDoc.reference;

      final data = quizDoc.data() ?? {};

      final String quizTitle =
          data['title']?.toString().trim().isNotEmpty == true
          ? data['title'].toString().trim()
          : 'Quiz';

      await quizRef.update({
        'status': 'finished',
        'isFinished': true,
        'countdownActive': false,
        'readyCheckActive': false,
        'manuallyPaused': false,
        'currentQuestion': _currentQuestion,
        'currentLevel': _getLevel(_currentQuestion),
        'finishedAt': FieldValue.serverTimestamp(),
        'timer': 0,
      });

      // Compute final rankings and update all participants so they instantly see their rank
      try {
        final scoresSnap = await quizRef.collection('scores').get();
        final requestsSnap = await quizRef.collection('join_requests').get();

        final List<Map<String, dynamic>> participantScores = [];
        for (final doc in scoresSnap.docs) {
          final sData = doc.data();
          final int score =
              int.tryParse(sData['score']?.toString() ?? '') ?? 0;
          final rawUpdated = sData['updatedAt'];
          final int timeMs =
              rawUpdated is Timestamp ? rawUpdated.millisecondsSinceEpoch : 0;
          participantScores.add({
            'uid': doc.id,
            'score': score,
            'timeMs': timeMs,
            'name': (sData['name'] ?? sData['teamName'] ?? doc.id).toString(),
          });
        }

        final existingUids = participantScores.map((p) => p['uid']).toSet();
        for (final req in requestsSnap.docs) {
          if (!existingUids.contains(req.id)) {
            final rData = req.data();
            final int score =
                int.tryParse(rData['score']?.toString() ?? '') ?? 0;
            participantScores.add({
              'uid': req.id,
              'score': score,
              'timeMs': 0,
              'name': (rData['teamName'] ?? rData['name'] ?? req.id).toString(),
            });
          }
        }

        // Sort: highest score first, earlier time on tie, then name
        participantScores.sort((a, b) {
          final int scoreCompare =
              (b['score'] as int).compareTo(a['score'] as int);
          if (scoreCompare != 0) return scoreCompare;
          final int timeA = a['timeMs'] as int;
          final int timeB = b['timeMs'] as int;
          if (timeA > 0 && timeB > 0 && timeA != timeB) {
            return timeA.compareTo(timeB);
          }
          return (a['name'] as String).compareTo(b['name'] as String);
        });

        final Map<String, int> ranksByUid = {};
        for (int i = 0; i < participantScores.length; i++) {
          final uid = participantScores[i]['uid'] as String;
          ranksByUid[uid] = i + 1;
        }

        if (requestsSnap.docs.isNotEmpty || scoresSnap.docs.isNotEmpty) {
          final Map<String, int> scoresByUid = {
            for (final p in participantScores)
              p['uid'] as String: p['score'] as int,
          };

          final batch = FirebaseFirestore.instance.batch();
          for (final req in requestsSnap.docs) {
            final int assignedRank =
                ranksByUid[req.id] ?? (ranksByUid.length + 1);
            final int score = scoresByUid[req.id] ??
                (int.tryParse(req.data()['score']?.toString() ?? '') ?? 0);
            batch.set(req.reference, {
              'quizFinished': true,
              'quizEnded': true,
              'finalRank': assignedRank,
              'rank': assignedRank,
              'levelRank': assignedRank,
              'currentRank': assignedRank,
              'finalScore': score,
              'score': score,
              'rankUpdatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
          for (final doc in scoresSnap.docs) {
            final int assignedRank =
                ranksByUid[doc.id] ?? (ranksByUid.length + 1);
            final int score = scoresByUid[doc.id] ??
                (int.tryParse(doc.data()['score']?.toString() ?? '') ?? 0);
            batch.set(doc.reference, {
              'finalRank': assignedRank,
              'rank': assignedRank,
              'levelRank': assignedRank,
              'currentRank': assignedRank,
              'finalScore': score,
            }, SetOptions(merge: true));
          }
          await batch.commit();
        }
      } catch (e) {
        debugPrint('UPDATE FINAL RANKS ON FINISH ERROR: $e');
      }

      try {
        await FirebaseFirestore.instance.collection('notifications').add({
          'type': 'quiz_ended',
          'title': 'Quiz Ended',
          'message': '$quizTitle has ended.',
          'quizCode': widget.quizCode,
          'quizTitle': quizTitle,
          'createdAt': FieldValue.serverTimestamp(),
          'isRead': false,
        });
      } catch (e) {
        debugPrint('NOTIFICATION ADD ERROR: $e');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_quizMasterLastPageKey, 'ranking');
      await prefs.setString(_quizMasterCurrentQuizCodeKey, widget.quizCode);

      if (!mounted) return;

      setState(() {
        _status = 'finished';
        _isRunning = false;
        _isFinished = true;
        _isManuallyPaused = false;
        _secondsLeft = 0;
        _quizData = {...?_quizData, 'status': 'finished', 'isFinished': true};
      });

      _showMessage('Quiz finished.', isSuccess: true);
    } catch (e) {
      debugPrint('FINISH QUIZ ERROR: $e');
      _showMessage('Unable to finish quiz.', isError: true);
    } finally {
      _isFinishingQuiz = false;
    }
  }

  // ============================================================
  // FIRESTORE UPDATE
  // ============================================================

  Future<void> _updateSession(Map<String, dynamic> data) async {
    final quizDoc = await _getQuizSession();

    if (quizDoc == null) return;

    await quizDoc.reference.update(data);
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(
    String message, {
    bool isError = false,
    bool isSuccess = false,
    bool isWarning = false,
  }) {
    if (!mounted) return;

    showQuizMasterTopNotification(
      context,
      message,
      isError: isError,
      isSuccess: isSuccess,
      isWarning: isWarning,
    );
  }

  // ============================================================
  // OPEN PARTIAL RANKING & ELIMINATION SCREEN
  // ============================================================

  Future<void> _openFinalRanking({bool isFinal = false}) async {
    if (!mounted || _finalRankingOpening) return;

    _finalRankingOpening = true;
    try {
      await Navigator.of(context).push<void>(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => FinalRankingScreen(
            quizCode: widget.quizCode,
            level: _currentLevel,
            isFinal: isFinal,
            onStartNextLevel: isFinal
                ? null
                : () async {
                    // Keep the result route visible until _startNextLevel replaces it
                    // with Contestant Readiness. This avoids flashing the dashboard.
                    if (!mounted) return;
                    _replaceFinalRankingWithReadiness = true;
                    await _startNextLevel();
                  },
          ),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
    } finally {
      _finalRankingOpening = false;
    }
  }

  // ============================================================
  // FORMAT TIMER
  // ============================================================

  String _formatTimer(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;

    return '${minutes.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')}';
  }

  // ============================================================
  // GET CURRENT QUESTION
  // ============================================================

  // Total questions assigned to the currently selected level by Admin.
  int get _currentLevelQuestionCount {
    return _questions
        .where((question) => _getQuestionLevel(question) == _currentLevel)
        .length;
  }

  String get _questionText {
    if (_questions.isEmpty ||
        _currentQuestion < 0 ||
        _currentQuestion >= _questions.length) {
      return 'No question available.';
    }

    final data = _questions[_currentQuestion].data() as Map<String, dynamic>;

    return data['question']?.toString() ?? 'No question text.';
  }

  // ============================================================
  // GET CURRENT QUESTION TYPE
  // ============================================================

  String get _questionType {
    if (_questions.isEmpty ||
        _currentQuestion < 0 ||
        _currentQuestion >= _questions.length) {
      return 'Multiple Choice';
    }

    final data = _questions[_currentQuestion].data() as Map<String, dynamic>;

    return data['questionType']?.toString() ?? 'Multiple Choice';
  }

  String get _correctAnswerText {
    if (_questions.isEmpty ||
        _currentQuestion < 0 ||
        _currentQuestion >= _questions.length) {
      return 'No answer available.';
    }

    final data = _questions[_currentQuestion].data() as Map<String, dynamic>;
    final value =
        data['correctAnswer'] ?? data['correctAnswers'] ?? data['answer'];

    if (value == null) return 'No answer available.';

    String clean(dynamic item) => item?.toString().trim() ?? '';

    // Resolve a stored option letter (A/B/C/D) to the actual option text.
    // Question documents can store choices as a list, a map, or separate fields.
    String optionText(String letter) {
      final upper = letter.trim().toUpperCase();
      if (!RegExp(r'^[A-Z]$').hasMatch(upper)) return '';

      final index = upper.codeUnitAt(0) - 'A'.codeUnitAt(0);

      for (final key in ['options', 'choices', 'answers', 'answerOptions']) {
        final options = data[key];

        if (options is List && index >= 0 && index < options.length) {
          final item = options[index];
          if (item is Map) {
            final text = clean(
              item['text'] ?? item['label'] ?? item['answer'] ?? item['value'],
            );
            if (text.isNotEmpty) return text;
          } else {
            final text = clean(item);
            if (text.isNotEmpty) return text;
          }
        }

        if (options is Map) {
          final item = options[upper] ?? options[upper.toLowerCase()];
          if (item != null) {
            if (item is Map) {
              final text = clean(
                item['text'] ??
                    item['label'] ??
                    item['answer'] ??
                    item['value'],
              );
              if (text.isNotEmpty) return text;
            } else {
              final text = clean(item);
              if (text.isNotEmpty) return text;
            }
          }
        }
      }

      final number = index + 1;
      final candidateKeys = [
        'option$upper',
        'option_${upper.toLowerCase()}',
        'choice$upper',
        'choice_${upper.toLowerCase()}',
        'answer$upper',
        'answer_${upper.toLowerCase()}',
        'option$number',
        'choice$number',
        'answer$number',
        upper,
        upper.toLowerCase(),
      ];

      for (final key in candidateKeys) {
        final text = clean(data[key]);
        if (text.isNotEmpty) return text;
      }

      return '';
    }

    if (value is List) {
      return value
          .map((item) {
            final raw = clean(item);
            final resolved = optionText(raw);
            return resolved.isNotEmpty ? resolved : raw;
          })
          .where((item) => item.isNotEmpty)
          .join(', ');
    }

    final answer = clean(value);
    if (answer.isEmpty) return 'No answer available.';

    final resolved = optionText(answer);
    return resolved.isNotEmpty ? resolved : answer;
  }

  // ============================================================
  // READY CHECK UI
  // ============================================================

  Future<void> _openReadyCheck({
    bool levelStart = false,
    int? questionIndex,
    int? level,
  }) async {
    if (_isFinished) return;

    // This method is called only when the Quiz Master explicitly presses
    // the Ready Check control. Start a fresh check here even if Firestore
    // contains a stale readyCheckActive=true value from an earlier attempt.
    // This also resets each approved contestant's readiness for this check.
    await _startReadyCheck(
      questionIndex: questionIndex,
      level: level,
      levelStart: levelStart,
    );

    if (!mounted) return;

    // If no approved contestants or no valid question is available,
    // _startReadyCheck shows a message and leaves the check inactive.
    if (!_readyCheckActive) return;

    // Keep the readiness list in a popup. For the initial event check,
    // the next action opens a level-specific readiness check. For a level
    // check, the level starts only after all approved participants are ready.
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 650),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('quiz_sessions')
                    .doc(widget.quizCode)
                    .collection('join_requests')
                    .where('status', isEqualTo: 'approved')
                    .snapshots(),
                builder: (context, snapshot) {
                  final docs = snapshot.data?.docs ?? [];
                  final readyCount = docs
                      .where((doc) => doc.data()['ready'] == true)
                      .length;
                  final allReady = docs.isNotEmpty && readyCount == docs.length;

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: primaryBlue.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.groups_rounded,
                              color: primaryBlue,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'PARTICIPANT STATUS',
                              style: TextStyle(
                                color: darkBlue,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          allReady
                              ? 'All participants are ready. You can start the quiz.'
                              : 'Waiting for all approved participants to confirm.',
                          style: const TextStyle(
                            color: Colors.black54,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: _readyCheckSecondsLeft > 0
                              ? Colors.orange.withValues(alpha: 0.10)
                              : Colors.green.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              color: _readyCheckSecondsLeft > 0
                                  ? Colors.orange
                                  : Colors.green,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _readyCheckSecondsLeft > 0
                                    ? 'Readiness confirmation ends in $_readyCheckSecondsLeft seconds.'
                                    : 'Readiness confirmation period has ended.',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: darkBlue,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: allReady
                              ? Colors.green.withValues(alpha: 0.08)
                              : background,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              allReady
                                  ? Icons.check_circle_rounded
                                  : Icons.hourglass_top_rounded,
                              color: allReady ? Colors.green : Colors.orange,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                '$readyCount / ${docs.length} PARTICIPANTS READY',
                                style: TextStyle(
                                  color: allReady ? Colors.green : darkBlue,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Flexible(
                        child: docs.isEmpty
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text(
                                    'No approved participants found. Approve participants in the Waiting Room first.',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: docs.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 7),
                                itemBuilder: (context, index) {
                                  final doc = docs[index];
                                  final data = doc.data();
                                  final ready = data['ready'] == true;
                                  final name =
                                      (data['displayName'] ??
                                              data['name'] ??
                                              data['email'] ??
                                              doc.id)
                                          .toString();

                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: ready
                                            ? Colors.green.shade100
                                            : Colors.orange.shade100,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          ready
                                              ? Icons.check_circle_rounded
                                              : Icons.hourglass_empty_rounded,
                                          color: ready
                                              ? Colors.green
                                              : Colors.orange,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            name,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          ready ? 'READY' : 'WAITING',
                                          style: TextStyle(
                                            color: ready
                                                ? Colors.green
                                                : Colors.orange,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: allReady
                              ? () async {
                                  // Do not proceed before the readiness
                                  // countdown has expired.
                                  if (_readyCheckSecondsLeft > 0) {
                                    _showMessage(
                                      'Please wait until the readiness countdown ends.',
                                    );
                                    return;
                                  }

                                  // Re-check Firestore directly before proceeding.
                                  // The StreamBuilder can briefly display a stale snapshot.
                                  final everyoneReady =
                                      await _allApprovedContestantsReady();
                                  if (!everyoneReady) {
                                    _showMessage(
                                      'Not all approved participants are READY yet.',
                                    );
                                    return;
                                  }

                                  if (!dialogContext.mounted) return;
                                  Navigator.pop(dialogContext);

                                  if (levelStart || questionIndex != null) {
                                    final targetQuestion =
                                        questionIndex ??
                                        _pendingQuestionIndex ??
                                        _getFirstQuestionIndexForLevel(
                                          level ?? _pendingLevel ?? 1,
                                        );
                                    final targetLevel =
                                        level ??
                                        _pendingLevel ??
                                        (targetQuestion == null
                                            ? 1
                                            : _getLevel(targetQuestion));

                                    if (targetQuestion != null) {
                                      // START LEVEL 1 / START LEVEL 2 from the
                                      // readiness page only announces preparation.
                                      // The separate Quiz Control START button is
                                      // the sole trigger for the synchronized countdown.
                                      final latestQuizDoc =
                                          await _getQuizSession();
                                      if (latestQuizDoc == null) {
                                        _showMessage('Quiz session not found.');
                                        return;
                                      }
                                      await _resetReadyCheck();
                                      await latestQuizDoc.reference.update({
                                        'status': 'waiting',
                                        'eventStatus': 'preparing_to_begin',
                                        'preparedLevel': targetLevel,
                                        'preparationStartedAt':
                                            FieldValue.serverTimestamp(),
                                        // Refresh the explicit level-start marker
                                        // for the contestant Waiting Room listener.
                                        'levelStartedAt':
                                            FieldValue.serverTimestamp(),
                                        'readyCheckActive': false,
                                        'readyCheckType': 'level',
                                        'currentQuestion': targetQuestion,
                                        'currentLevel': targetLevel,
                                        'countdownActive': false,
                                        'countdown': 0,
                                        'timer': 0,
                                      });
                                      if (!mounted) return;
                                      setState(() {
                                        _levelPreparedForStart = true;
                                        _status = 'waiting';
                                        _isRunning = false;
                                        _readyCheckActive = false;
                                        _currentQuestion = targetQuestion;
                                        _currentLevel = targetLevel;
                                        _pendingQuestionIndex = targetQuestion;
                                        _pendingLevel = targetLevel;
                                        _countdown = 0;
                                        _secondsLeft = 0;
                                      });
                                    }
                                  } else {
                                    // Initial event readiness completed:
                                    // start the Level 1 readiness round.
                                    final firstQuestion =
                                        _getFirstQuestionIndexForLevel(1);
                                    if (firstQuestion == null) {
                                      _showMessage(
                                        'No Level 1 questions were selected.',
                                      );
                                      return;
                                    }
                                    await _openReadyCheck(
                                      levelStart: true,
                                      questionIndex: firstQuestion,
                                      level: 1,
                                    );
                                  }
                                }
                              : null,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text(
                            levelStart
                                ? 'START LEVEL ${level ?? _pendingLevel ?? 1}'
                                : questionIndex != null
                                ? 'START QUESTION ${questionIndex + 1}'
                                : 'START LEVEL 1',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryBlue,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey.shade300,
                            disabledForegroundColor: Colors.grey.shade600,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _contestantReadinessCard() {
    if ((!_readyCheckActive && _status != 'waiting') || _isFinished) {
      return const SizedBox.shrink();
    }

    final sessionRef = FirebaseFirestore.instance
        .collection('quiz_sessions')
        .doc(widget.quizCode);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: sessionRef.collection('join_requests').snapshots(),
      builder: (context, requestsSnapshot) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: sessionRef.collection('scores').snapshots(),
          builder: (context, scoresSnapshot) {
            final rawRequests = requestsSnapshot.data?.docs ?? [];
            final scoreDocs = scoresSnapshot.data?.docs ?? [];

            final eliminatedScoreIds = <String>{
              for (final s in scoreDocs)
                if (s.data()['eliminated'] == true ||
                    s.data()['isEliminated'] == true ||
                    s.data()['status']?.toString().toLowerCase() == 'eliminated')
                  s.id,
            };

            final docs = rawRequests.where((doc) {
              final data = doc.data();
              final status = (data['status'] ?? '').toString().trim().toLowerCase();
              if (status != 'approved' && status != 'proceeding' && status.isNotEmpty) {
                return false;
              }
              return !_isDocEliminated(doc, eliminatedScoreIds);
            }).toList();

            final readyCount = docs
                .where((doc) => doc.data()['ready'] == true)
                .length;
            final allReady = docs.isNotEmpty && readyCount == docs.length;

            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: allReady ? Colors.green.shade200 : Colors.blue.shade100,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: allReady
                              ? Colors.green.withValues(alpha: 0.10)
                              : primaryBlue.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          allReady
                              ? Icons.check_circle_rounded
                              : Icons.people_alt_rounded,
                          color: allReady ? Colors.green : primaryBlue,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'CONTESTANT READINESS',
                          style: TextStyle(
                            color: darkBlue,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    allReady
                        ? (_currentQuestion == 0
                              ? 'All contestants are ready. Use START in Quiz Controls to begin.'
                              : 'All contestants are ready. Use the Quiz Controls to continue.')
                        : (_currentQuestion == 0
                              ? 'Waiting for contestants to confirm they are ready.'
                              : 'Waiting for contestants to confirm they are ready. The quiz controls will proceed when everyone is READY.'),
                    style: const TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: allReady ? Colors.green.withValues(alpha: 0.08) : background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          allReady
                              ? Icons.play_circle_fill_rounded
                              : Icons.hourglass_empty_rounded,
                          color: allReady ? Colors.green : Colors.orange,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$readyCount / ${docs.length} CONTESTANTS READY',
                          style: TextStyle(
                            color: allReady ? Colors.green : darkBlue,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...docs.map((doc) {
                    final data = doc.data();
                    final ready = data['ready'] == true;
                    final name =
                        (data['displayName'] ??
                                data['name'] ??
                                data['email'] ??
                                doc.id)
                            .toString();

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Icon(
                            ready
                                ? Icons.check_circle_rounded
                                : Icons.hourglass_empty_rounded,
                            color: ready ? Colors.green : Colors.orange,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Text(
                            ready ? 'READY' : 'WAITING',
                            style: TextStyle(
                              color: ready ? Colors.green : Colors.orange,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  // This card is status-only. START is handled in Quiz Controls.
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ============================================================
  // LIVE CONTEST REQUESTS
  //
  // Shows pending contest requests for the CURRENT question in real
  // time (while the quiz is running or paused), each with
  // REJECT / APPROVE buttons.
  // ============================================================

  Widget _liveContestRequestsCard() {
    if (_isFinished || _contestReviewActive || _questions.isEmpty) {
      return const SizedBox.shrink();
    }

    final questionNumber = _currentQuestion + 1;
    final sessionRef = FirebaseFirestore.instance
        .collection('quiz_sessions')
        .doc(widget.quizCode);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: sessionRef.collection('join_requests').snapshots(),
      builder: (context, joinSnap) {
        final joinDocs = joinSnap.data?.docs ?? [];
        final Map<String, Map<String, dynamic>> joinByUid = {
          for (final j in joinDocs) j.id: j.data(),
        };

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: sessionRef.collection('contest_requests').snapshots(),
          builder: (context, snapshot) {
            final docs = (snapshot.data?.docs ?? []).where((doc) {
              final data = doc.data();
              final raw = data['questionNumber'];

              final number = raw is num
                  ? raw.toInt()
                  : int.tryParse(raw?.toString() ?? '');

              final status = data['status']?.toString().toLowerCase() ?? '';

              return number == questionNumber && status == 'pending';
            }).toList();

            docs.sort((a, b) {
              final aCreated = a.data()['createdAt'];
              final bCreated = b.data()['createdAt'];

              if (aCreated is Timestamp && bCreated is Timestamp) {
                return aCreated.compareTo(bCreated);
              }

              return a.id.compareTo(b.id);
            });

            // No contest: still show the card with a message.
            if (docs.isEmpty) {
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.gavel_rounded, color: Colors.grey),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'CONTEST REQUESTS',
                            style: TextStyle(
                              color: darkBlue,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'No contest for Question \$questionNumber.',
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.gavel_rounded,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'CONTEST REQUESTS (${docs.length})',
                          style: const TextStyle(
                            color: darkBlue,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Question \$questionNumber — a contestant is contesting.',
                    style: const TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  ...docs.map((doc) {
                    final data = doc.data();
                    final uid = (data['contestantUid'] ?? doc.id.split('_').first).toString();
                    final jData = joinByUid[uid];

                    final rawTeam = (data['teamName'] ?? jData?['teamName'] ?? '').toString().trim();
                    final contestantType = (data['contestantType'] ?? jData?['contestantType'] ?? '').toString().trim().toLowerCase();
                    final bool isTeam = data['isTeam'] == true ||
                        contestantType == 'team' ||
                        jData?['isTeam'] == true ||
                        rawTeam.isNotEmpty;

                    final personalName = (jData?['realName'] ??
                            jData?['fullName'] ??
                            jData?['displayName'] ??
                            jData?['name'] ??
                            data['realName'] ??
                            data['contestantName'] ??
                            data['displayName'] ??
                            data['name'] ??
                            data['email'] ??
                            uid)
                        .toString().trim();

                    final teamName = rawTeam.isNotEmpty ? rawTeam : (isTeam ? personalName : '');
                    final displayName = isTeam
                        ? (teamName.isNotEmpty ? teamName : personalName)
                        : (personalName.isNotEmpty ? personalName : 'Contestant');

                    final rawMembers = data['teamMembers'] ?? data['members'] ?? jData?['teamMembers'] ?? jData?['members'];
                    final List<String> teamMembers = [];
                    if (rawMembers is List) {
                      for (final m in rawMembers) {
                        final s = m is Map ? (m['name'] ?? m['displayName'] ?? '').toString().trim() : m.toString().trim();
                        if (s.isNotEmpty && !teamMembers.contains(s)) teamMembers.add(s);
                      }
                    }

                    final answer =
                        data['contestantAnswer']?.toString().trim() ?? '';
                    final expected =
                        data['expectedAnswer']?.toString().trim() ?? '';
                    final explanation =
                        data['explanation']?.toString().trim() ?? '';

                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: background,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                isTeam ? Icons.groups_rounded : Icons.person_rounded,
                                color: primaryBlue,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            displayName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: darkBlue,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        if (isTeam) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: primaryBlue.withValues(alpha: 0.10),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Text(
                                              'TEAM',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: primaryBlue,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (isTeam && teamMembers.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 3),
                                        child: Text(
                                          'Members: ' + teamMembers.join(', '),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Contestant Answer',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            answer.isEmpty ? 'No answer provided.' : answer,
                            style: const TextStyle(
                              color: darkBlue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 9),
                          Text(
                            'Expected Answer',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            expected.isEmpty ? 'Not available.' : expected,
                            style: const TextStyle(color: darkBlue),
                          ),
                          const SizedBox(height: 9),
                          Text(
                            'Explanation',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            explanation.isEmpty
                                ? 'No explanation provided.'
                                : explanation,
                            style: const TextStyle(color: darkBlue, height: 1.35),
                          ),
                          const SizedBox(height: 13),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _contestReviewBusy
                                      ? null
                                      : () => _reviewContestRequest(
                                          request: doc,
                                          approve: false,
                                        ),
                                  icon: const Icon(Icons.close_rounded),
                                  label: const Text('REJECT'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    side: const BorderSide(color: Colors.red),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 11,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _contestReviewBusy
                                      ? null
                                      : () => _reviewContestRequest(
                                          request: doc,
                                          approve: true,
                                        ),
                                  icon: const Icon(Icons.check_rounded),
                                  label: const Text('APPROVE'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 11,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ============================================================
  // CONFIRMED CHECK
  //
  // A contestant counts as confirmed when:
  //  - Ready Check phase (status 'waiting'): join_requests.ready == true
  //  - Result phase (running / paused): the contestant app saved
  //    resultConfirmed == true for the CURRENT question.
  // ============================================================

  int? _asInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  bool _isConfirmed(Map<String, dynamic> data) {
    if (_status == 'waiting') {
      return data['ready'] == true;
    }

    return data['resultConfirmed'] == true &&
        _asInt(data['resultConfirmedQuestion']) == _currentQuestion;
  }

  bool _isDocEliminated(
    DocumentSnapshot<Map<String, dynamic>> doc,
    Set<String> eliminatedScoreIds,
  ) {
    if (eliminatedScoreIds.contains(doc.id)) return true;
    final data = doc.data() ?? {};
    final status = (data['status'] ?? '').toString().trim().toLowerCase();
    final decision =
        (data['contestantDecision'] ?? '').toString().trim().toLowerCase();
    return data['eliminated'] == true ||
        data['isEliminated'] == true ||
        status == 'eliminated' ||
        decision == 'eliminated' ||
        status == 'left' ||
        status == 'rejected' ||
        status == 'declined' ||
        data['leftQuiz'] == true;
  }

  // ============================================================
  // NEXT QUESTION CARD
  //
  // Same look as the CONTESTANT READINESS card: shows who has
  // confirmed the result. The main Quiz Controls button handles
  // START / NEXT QUESTION; this card keeps the confirmation list.
  // ============================================================

  Widget _nextQuestionButton() {
    final sessionRef = FirebaseFirestore.instance
        .collection('quiz_sessions')
        .doc(widget.quizCode);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: sessionRef.collection('join_requests').snapshots(),
      builder: (context, requestsSnapshot) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: sessionRef.collection('scores').snapshots(),
          builder: (context, scoresSnapshot) {
            final rawRequests = requestsSnapshot.data?.docs ?? [];
            final scoreDocs = scoresSnapshot.data?.docs ?? [];

            final eliminatedScoreIds = <String>{
              for (final s in scoreDocs)
                if (s.data()['eliminated'] == true ||
                    s.data()['isEliminated'] == true ||
                    s.data()['status']?.toString().toLowerCase() == 'eliminated')
                  s.id,
            };

            final docs = rawRequests.where((doc) {
              final data = doc.data();
              final status = (data['status'] ?? '').toString().trim().toLowerCase();
              if (status != 'approved' && status != 'proceeding' && status.isNotEmpty) {
                return false;
              }
              return !_isDocEliminated(doc, eliminatedScoreIds);
            }).toList();

            final confirmed = docs.where((doc) => _isConfirmed(doc.data())).length;
            final allConfirmed = docs.isNotEmpty && confirmed == docs.length;

            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: allConfirmed
                      ? Colors.green.shade200
                      : Colors.blue.shade100,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: allConfirmed
                              ? Colors.green.withValues(alpha: 0.10)
                              : primaryBlue.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          allConfirmed
                              ? Icons.check_circle_rounded
                              : Icons.people_alt_rounded,
                          color: allConfirmed ? Colors.green : primaryBlue,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'CONTESTANT CONFIRMATION',
                          style: TextStyle(
                            color: darkBlue,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    allConfirmed
                        ? 'All contestants confirmed. You can continue.'
                        : 'Waiting for contestants to confirm the result. '
                              'You can continue anytime.',
                    style: const TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: allConfirmed
                          ? Colors.green.withValues(alpha: 0.08)
                          : background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          allConfirmed
                              ? Icons.check_circle_rounded
                              : Icons.hourglass_empty_rounded,
                          color: allConfirmed ? Colors.green : Colors.orange,
                          size: 21,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$confirmed / ${docs.length} CONTESTANTS CONFIRMED',
                          style: TextStyle(
                            color: allConfirmed ? Colors.green : darkBlue,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...docs.map((doc) {
                    final data = doc.data();
                    final isConfirmed = _isConfirmed(data);
                    final name =
                        (data['displayName'] ??
                                data['name'] ??
                                data['email'] ??
                                doc.id)
                            .toString();

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Icon(
                            isConfirmed
                                ? Icons.check_circle_rounded
                                : Icons.hourglass_empty_rounded,
                            color: isConfirmed ? Colors.green : Colors.orange,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Text(
                            isConfirmed ? 'CONFIRMED' : 'WAITING',
                            style: TextStyle(
                              color: isConfirmed ? Colors.green : Colors.orange,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  // The NEXT QUESTION action is kept in the main Quiz Controls.
                  // This card remains dedicated to the contestant confirmation list.
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ============================================================
  // NEXT QUESTION CONFIRMATION (CANCEL / CONFIRM)
  // ============================================================

  Future<void> _confirmNextQuestion() async {
    if (_isAdvancingQuestion || _isFinished) return;

    // Show the warning only when NO approved contestant has confirmed
    // the current result/readiness. If at least one has confirmed, proceed
    // directly without showing the dialog.
    try {
      final quizDoc = await _getQuizSession();
      if (quizDoc == null || !mounted) return;

      final requests = await quizDoc.reference
          .collection('join_requests')
          .get();
      final scores = await quizDoc.reference
          .collection('scores')
          .get();

      if (!mounted) return;

      final eliminatedScoreIds = <String>{
        for (final s in scores.docs)
          if (s.data()['eliminated'] == true ||
              s.data()['isEliminated'] == true ||
              s.data()['status']?.toString().toLowerCase() == 'eliminated')
            s.id,
      };

      final activeDocs = requests.docs.where((doc) {
        final data = doc.data();
        final status = (data['status'] ?? '').toString().trim().toLowerCase();
        if (status != 'approved' && status != 'proceeding' && status.isNotEmpty) {
          return false;
        }
        return !_isDocEliminated(doc, eliminatedScoreIds);
      }).toList();

      final confirmed = activeDocs
          .where((doc) => _isConfirmed(doc.data()))
          .length;

      if (confirmed > 0 || activeDocs.isEmpty) {
        await _nextQuestion(skipReadyCheck: true);
        return;
      }
    } catch (e) {
      debugPrint('CHECK CONTESTANT CONFIRMATION ERROR: $e');
      if (mounted) {
        _showMessage(
          'Unable to check contestant confirmation. Please try again.',
        );
      }
      return;
    }

    if (!mounted) return;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Proceed to Next Question'),
          content: const Text(
            'Some contestants are not ready. Continue anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _nextQuestion(skipReadyCheck: true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryBlue,
                foregroundColor: Colors.white,
              ),
              child: const Text('CONTINUE'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // FINISH QUIZ -> GO DIRECTLY TO ELIMINATION PAGE
  // ============================================================

  Future<void> _finishQuizAndOpenFinalRanking() async {
    if (_finalRankingOpening) return;

    ScaffoldMessenger.of(context).clearSnackBars();

    await _finishQuiz();

    if (!mounted) return;
    await _openFinalRanking(isFinal: true);
  }

  void _confirmFinishQuiz() {
    final currentLevel = _getLevel(_currentQuestion);
    final isLastQuestionOfLevel =
        _getLastQuestionIndexForLevel(currentLevel) == _currentQuestion;
    final hasNextLevel = _hasLevel(currentLevel + 1);
    final isFinalQuestionOfQuiz =
        isLastQuestionOfLevel &&
        !hasNextLevel &&
        (_totalQuestions == 0 || _currentQuestion >= _totalQuestions - 1);

    // On the last question of the final level, go directly to Final Ranking.
    if (isFinalQuestionOfQuiz) {
      _finishQuizAndOpenFinalRanking();
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Finish Quiz Early?',
            style: TextStyle(color: darkBlue, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'There are still remaining questions or levels in this quiz.\n\n'
            'Do you want to end the quiz now and proceed directly to the Final Ranking?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _finishQuizAndOpenFinalRanking();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('FINISH NOW'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // QUIZ INFORMATION MENU
  // ============================================================

  void _showQuizInfoMenu() {
    // Overlay a compact panel from the right instead of opening a bottom sheet.
    // The Quiz Control screen remains mounted underneath, so its timer/state
    // continues running while this menu is open.
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close quiz information menu',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final screenWidth = MediaQuery.of(dialogContext).size.width;
        final panelWidth = screenWidth < 420 ? screenWidth * 0.88 : 360.0;

        return SafeArea(
          child: Align(
            alignment: Alignment.centerRight,
            child: Material(
              color: Colors.white,
              elevation: 12,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: panelWidth,
                height: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 10, 12),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'QUIZ INFORMATION',
                              style: TextStyle(
                                color: darkBlue,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.checklist_rounded,
                                  color: primaryBlue,
                                  size: 23,
                                ),
                                const SizedBox(width: 9),
                                const Expanded(
                                  child: Text(
                                    'Participant Answers',
                                    style: TextStyle(
                                      color: darkBlue,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _participantAnswersView(),
                            const SizedBox(height: 22),
                            const Divider(height: 1),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                const Icon(
                                  Icons.leaderboard_outlined,
                                  color: primaryBlue,
                                  size: 23,
                                ),
                                const SizedBox(width: 9),
                                const Expanded(
                                  child: Text(
                                    'Current Standings',
                                    style: TextStyle(
                                      color: darkBlue,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _currentStandingsView(),
                          ],
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(14),
                      child: Text(
                        'Quiz remains ongoing while viewing information.',
                        style: TextStyle(color: Colors.black54, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final slide =
            Tween<Offset>(
              begin: const Offset(0.12, 0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
        return SlideTransition(position: slide, child: child);
      },
    );
  }

  Widget _participantAnswersView() {
    final quizRef = FirebaseFirestore.instance
        .collection('quiz_sessions')
        .doc(widget.quizCode);

    // QuizScreen saves each contestant's actual answer records at:
    // quiz_sessions/{quizCode}/answers/{uid}/responses/question_{index}
    // Count those records directly rather than relying on the unused
    // submitted_answers collection, so the totals match saved answer results.
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: quizRef.collection('join_requests').snapshots(),
      builder: (context, contestantsSnapshot) {
        if (contestantsSnapshot.hasError) {
          return const Text('Unable to load contestants.');
        }
        if (contestantsSnapshot.connectionState == ConnectionState.waiting &&
            !contestantsSnapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final contestants = [...?contestantsSnapshot.data?.docs];
        contestants.sort((a, b) {
          final aData = a.data();
          final bData = b.data();
          final aName =
              (aData['displayName'] ?? aData['name'] ?? aData['email'] ?? a.id)
                  .toString();
          final bName =
              (bData['displayName'] ?? bData['name'] ?? bData['email'] ?? b.id)
                  .toString();
          return aName.toLowerCase().compareTo(bName.toLowerCase());
        });

        if (contestants.isEmpty) {
          return const Text(
            'No contestants found for this quiz yet.',
            style: TextStyle(color: Colors.black54),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: contestants.map((contestantDoc) {
            final contestant = contestantDoc.data();
            final name =
                (contestant['displayName'] ??
                        contestant['name'] ??
                        contestant['email'] ??
                        contestantDoc.id)
                    .toString();
            final contestantStatus = (contestant['status'] ?? 'approved')
                .toString()
                .toLowerCase();
            final responsesRef = quizRef
                .collection('answers')
                .doc(contestantDoc.id)
                .collection('responses');

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: responsesRef.snapshots(),
              builder: (context, responsesSnapshot) {
                if (responsesSnapshot.hasError) {
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade100),
                    ),
                    child: Text(
                      '$name\nUnable to load saved answer results.',
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }

                final responseDocs = responsesSnapshot.data?.docs ?? [];
                var correctCount = 0;
                var wrongCount = 0;
                var unansweredCount = 0;

                for (final responseDoc in responseDocs) {
                  final data = responseDoc.data();
                  final answerStatus = (data['answerStatus'] ?? '')
                      .toString()
                      .toLowerCase();
                  final rawCorrect = data['isCorrect'];

                  if (answerStatus == 'correct' || rawCorrect == true) {
                    correctCount++;
                  } else if (answerStatus == 'wrong' ||
                      (answerStatus.isEmpty && rawCorrect == false)) {
                    wrongCount++;
                  } else if (answerStatus == 'unanswered') {
                    unansweredCount++;
                  }
                }

                final isLoading =
                    responsesSnapshot.connectionState ==
                        ConnectionState.waiting &&
                    !responsesSnapshot.hasData;

                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.person_rounded,
                            color: primaryBlue,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(
                                color: darkBlue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (contestantStatus == 'eliminated')
                            const Text(
                              'ELIMINATED',
                              style: TextStyle(
                                color: Colors.red,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (isLoading)
                        const LinearProgressIndicator(minHeight: 2)
                      else
                        Row(
                          children: [
                            Expanded(
                              child: _answerCountChip(
                                icon: Icons.check_circle_rounded,
                                label: 'Correct: $correctCount',
                                color: Colors.green,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: _answerCountChip(
                                icon: Icons.cancel_rounded,
                                label: 'Wrong: $wrongCount',
                                color: Colors.red,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: _answerCountChip(
                                icon: Icons.help_outline_rounded,
                                label: 'Unanswered: $unansweredCount',
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                );
              },
            );
          }).toList(),
        );
      },
    );
  }

  Widget _answerCountChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _currentStandingsView() {
    final quizRef = FirebaseFirestore.instance
        .collection('quiz_sessions')
        .doc(widget.quizCode);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: quizRef.collection('scores').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text('Unable to load current standings.');
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final rows =
            (snapshot.data?.docs ?? []).map((doc) {
              final data = doc.data();
              return <String, dynamic>{
                'name':
                    (data['name'] ??
                            data['displayName'] ??
                            data['contestantName'] ??
                            doc.id)
                        .toString(),
                'score': _asInt(data['score']) ?? 0,
              };
            }).toList()..sort(
              (a, b) => (b['score'] as int).compareTo(a['score'] as int),
            );

        if (rows.isEmpty) {
          return const Text(
            'Standings will appear when participant scores are recorded.',
          );
        }

        return Column(
          children: [
            for (int i = 0; i < rows.length; i++)
              ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 15,
                  backgroundColor: Colors.blue.shade50,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      color: primaryBlue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(rows[i]['name'] as String),
                trailing: Text(
                  '${rows[i]['score']} pts',
                  style: const TextStyle(
                    color: darkBlue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    // A real "level finished" always has timer = 0.
    // If level_pause still has time left, it is a manual pause.
    final bool isPaused =
        !_isFinished &&
        (_status == 'paused' ||
            (_isManuallyPaused && _secondsLeft > 0) ||
            (_status == 'level_pause' && _secondsLeft > 0));
    final bool isLevelPause = _status == 'level_pause' && !isPaused;
    final bool isWaiting = _status == 'waiting';
    final bool isCountdown = _status == 'countdown';

    // Keep the timer hidden until the Quiz Master starts the question.
    // Once started, keep it visible during active play and manual pause.

    final isWideLayout = MediaQuery.of(context).size.width >= 1000;

    return PopScope<Object?>(
      canPop: !_hasQuizStarted,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _hasQuizStarted) {
          _showMessage('The quiz is in progress. Back navigation is disabled.');
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F8FE),
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF26364D),
          elevation: 0,
          toolbarHeight: 78,
          centerTitle: false,
          automaticallyImplyLeading: false,
          titleSpacing: 16,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const QuizMasterBadge(
                label: 'TECHNOWIZ • QUIZ CONTROL COMMAND',
                icon: Icons.tune_rounded,
              ),
              const SizedBox(height: 4),
              const Text(
                'Quiz Control',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isPaused
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFF16A34A),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isPaused ? 'PAUSED' : 'ONGOING',
                    style: TextStyle(
                      color: isPaused
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFF16A34A),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ],
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(
              height: 1,
              color: QuizMasterColors.borderBlue.withValues(alpha: 0.4),
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Open quiz information menu',
              icon: const Icon(Icons.playlist_add_check_rounded, size: 28),
              onPressed: _showQuizInfoMenu,
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: QuizMasterCircuitBackground(
          child: SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(isWideLayout ? 20 : 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ==================================================
                      // MANUAL PAUSE MESSAGE
                      // ==================================================
                      if (isPaused && !_isFinished)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.pause_circle_filled,
                                color: Colors.orange.shade700,
                                size: 38,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'QUIZ PAUSED\n'
                                  'Press RESUME QUIZ to continue from '
                                  '${_formatTimer(_secondsLeft)}.',
                                  style: TextStyle(
                                    color: Colors.orange.shade900,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      if (isPaused && !_isFinished) const SizedBox(height: 20),

                      // ==================================================
                      // LEVEL PAUSE MESSAGE
                      // ==================================================
                      if (isLevelPause)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.pause_circle_filled,
                                color: Colors.orange.shade700,
                                size: 38,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'LEVEL $_currentLevel FINISHED\n'
                                  'Waiting for the next level to start.',
                                  style: TextStyle(
                                    color: Colors.orange.shade900,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      if (isLevelPause) const SizedBox(height: 20),

                      // ==================================================
                      // LEVEL INFO  (blue icon square removed)
                      // ==================================================
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.blue.shade100),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              'LEVEL $_currentLevel',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: darkBlue,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Question $_currentLevelQuestionCount of $_currentLevelQuestionCount',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Type: $_questionType',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Admin-configured timer for the currently selected level.
                      // Displayed as a circle between the level summary and question.
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 12),
                        child: Center(
                          child: Container(
                            width: 116,
                            height: 116,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.orange.shade50,
                              border: Border.all(
                                color: Colors.orange.shade300,
                                width: 1.8,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isCountdown
                                      ? Icons.hourglass_top_rounded
                                      : Icons.timer_outlined,
                                  color: isCountdown
                                      ? primaryBlue
                                      : Colors.orange.shade800,
                                  size: 25,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  isCountdown
                                      ? (_countdown > 0 ? '$_countdown' : 'GO!')
                                      : (_isRunning || isPaused)
                                      ? _formatTimer(_secondsLeft)
                                      : _quizData == null
                                      ? '...'
                                      : '$_configuredTimerSeconds',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: isCountdown
                                        ? primaryBlue
                                        : Colors.orange.shade900,
                                    fontSize: isCountdown ? 24 : 19,
                                    fontWeight: FontWeight.bold,
                                    height: 1,
                                  ),
                                ),
                                Text(
                                  isCountdown
                                      ? 'GET READY'
                                      : (_isRunning || isPaused)
                                      ? 'remaining'
                                      : 'sec',
                                  style: TextStyle(
                                    color: isCountdown
                                        ? primaryBlue
                                        : Colors.orange.shade800,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.blue.shade100),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'QUESTION ${_getQuestionNumberWithinLevel(_currentQuestion)}',
                              style: const TextStyle(
                                color: primaryBlue,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 15),
                            Text(
                              _questionText,
                              style: const TextStyle(
                                color: darkBlue,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _questionType,
                                style: const TextStyle(
                                  color: primaryBlue,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'CORRECT ANSWER',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.green.shade200,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: Colors.green,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _correctAnswerText,
                                      style: const TextStyle(
                                        color: Colors.green,
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

                      const SizedBox(height: 20),

                      // ==================================================
                      // QUIZ CONTROLS
                      // ==================================================
                      const Text(
                        'Quiz Controls',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: darkBlue,
                        ),
                      ),

                      const SizedBox(height: 12),

                      // --------------------------------------------------
                      // COMPACT RESPONSIVE QUIZ CONTROLS
                      // --------------------------------------------------
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 560;
                          final columns = compact ? 2 : 4;
                          const gap = 8.0;
                          final buttonWidth =
                              (constraints.maxWidth - gap * (columns - 1)) /
                              columns;
                          final currentLevel = _getLevel(_currentQuestion);
                          final lastQuestionOfCurrentLevel =
                              _getLastQuestionIndexForLevel(currentLevel) ==
                              _currentQuestion;
                          final hasNextLevelAfterCurrent = _hasLevel(
                            currentLevel + 1,
                          );
                          final shouldShowNextLevel =
                              lastQuestionOfCurrentLevel &&
                              hasNextLevelAfterCurrent;

                          return Wrap(
                            spacing: gap,
                            runSpacing: gap,
                            children: [
                              SizedBox(
                                width: buttonWidth,
                                child: _compactControlButton(
                                  icon:
                                      (_currentQuestion == 0 &&
                                          isWaiting &&
                                          _quizData?['startedAt'] == null)
                                      ? Icons.play_arrow_rounded
                                      : shouldShowNextLevel
                                      ? Icons.play_circle_fill_rounded
                                      : Icons.skip_next_rounded,
                                  label: _levelPreparedForStart
                                      ? 'START LEVEL $_currentLevel'
                                      : (_currentQuestion == 0 &&
                                            isWaiting &&
                                            _quizData?['startedAt'] == null)
                                      ? 'START'
                                      : shouldShowNextLevel
                                      ? 'END LEVEL'
                                      : 'NEXT QUESTION',
                                  color:
                                      _levelPreparedForStart ||
                                          (_currentQuestion == 0 &&
                                              isWaiting &&
                                              _quizData?['startedAt'] ==
                                                  null) ||
                                          shouldShowNextLevel
                                      ? Colors.green
                                      : ((_totalQuestions > 0 &&
                                                _currentQuestion >=
                                                    _totalQuestions - 1)
                                            ? Colors.grey
                                            : primaryBlue),
                                  enabled:
                                      !_isFinished &&
                                      !_isAdvancingQuestion &&
                                      !_startingFromMainButton &&
                                      (_levelPreparedForStart ||
                                          ((_currentQuestion == 0 &&
                                                  isWaiting &&
                                                  _quizData?['startedAt'] ==
                                                      null)
                                              ? isWaiting
                                              : shouldShowNextLevel
                                              ? true
                                              : !isWaiting &&
                                                    !isCountdown &&
                                                    !_contestReviewActive &&
                                                    !_isManuallyPaused &&
                                                    _totalQuestions > 0 &&
                                                    _currentQuestion <
                                                        _totalQuestions - 1)),
                                  // One primary control starts the next question or level.
                                  onTap: _levelPreparedForStart
                                      ? () async {
                                          final targetQuestion =
                                              _pendingQuestionIndex ??
                                              _currentQuestion;
                                          final targetLevel =
                                              _pendingLevel ?? _currentLevel;
                                          setState(
                                            () =>
                                                _levelPreparedForStart = false,
                                          );
                                          await _startQuestionCountdown(
                                            questionIndex: targetQuestion,
                                            level: targetLevel,
                                          );
                                        }
                                      : (_currentQuestion == 0 &&
                                            isWaiting &&
                                            _quizData?['startedAt'] == null)
                                      ? _startInitialCountdownFromButton
                                      : shouldShowNextLevel
                                      ? _endLevelAndOpenElimination
                                      : _confirmNextQuestion,
                                ),
                              ),
                              SizedBox(
                                width: buttonWidth,
                                child: _compactControlButton(
                                  icon: Icons.pause_rounded,
                                  label: 'PAUSE',
                                  color: Colors.orange,
                                  // Restore clickability after browser refresh:
                                  // the Firestore status/remaining time can be active
                                  // even if the local periodic timer flag has not
                                  // resumed yet. Do not enable PAUSE in waiting,
                                  // countdown, paused, level-finished, or review states.
                                  enabled:
                                      !_isFinished &&
                                      !isPaused &&
                                      !isWaiting &&
                                      !isCountdown &&
                                      !isLevelPause &&
                                      !_contestReviewActive &&
                                      (_isRunning ||
                                          _status == 'active' ||
                                          _secondsLeft > 0),
                                  onTap: _pauseQuiz,
                                ),
                              ),
                              SizedBox(
                                width: buttonWidth,
                                child: _compactControlButton(
                                  icon: Icons.play_circle_outline_rounded,
                                  label: 'RESUME',
                                  color: Colors.teal,
                                  enabled: isPaused && !_isFinished,
                                  onTap: _resumeQuiz,
                                ),
                              ),
                              SizedBox(
                                width: buttonWidth,
                                child: _compactControlButton(
                                  icon: Icons.flag_rounded,
                                  label: 'FINISH',
                                  color: Colors.red,
                                  enabled: !_isFinished && !_isFinishingQuiz,
                                  onTap: _confirmFinishQuiz,
                                ),
                              ),
                            ],
                          );
                        },
                      ),

                      // --------------------------------------------------
                      // PAUSE / RESUME  +  FINISH
                      //
                      // FIX: the first button toggles between PAUSE QUIZ
                      // (while running) and RESUME QUIZ (while paused).
                      // --------------------------------------------------
                      const SizedBox(height: 14),

                      // --------------------------------------------------
                      // LIVE CONTEST REQUESTS (REJECT / APPROVE)
                      // --------------------------------------------------
                      _liveContestRequestsCard(),

                      // --------------------------------------------------
                      // CONTEST REVIEW (before moving to next question)
                      // --------------------------------------------------
                      _contestReviewCard(),

                      // --------------------------------------------------
                      // NEXT QUESTION
                      // --------------------------------------------------
                      if (!_isFinished &&
                          !isWaiting &&
                          !isCountdown &&
                          !_contestReviewActive &&
                          _questions.isNotEmpty) ...[
                        _nextQuestionButton(),
                        const SizedBox(height: 14),
                      ],

                      // --------------------------------------------------
                      // FINISHED
                      // --------------------------------------------------
                      if (_isFinished)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                    size: 30,
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'This quiz has already finished.',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: darkBlue,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 48,
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    await prefs.setString(
                                      _quizMasterLastPageKey,
                                      'dashboard',
                                    );
                                    await prefs.remove(
                                      _quizMasterCurrentQuizCodeKey,
                                    );
                                    if (!context.mounted) return;
                                    Navigator.of(context).pushAndRemoveUntil(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const QuizMasterDashboard(),
                                      ),
                                      (route) => false,
                                    );
                                  },
                                  icon: const Icon(Icons.dashboard_rounded),
                                  label: const Text(
                                    'BACK TO DASHBOARD',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primaryBlue,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // FINAL RANKING + ELIMINATION
                      _finalRankingCard(),

                      const SizedBox(height: 10),

                      if (isWaiting) ...[
                        _contestantReadinessCard(),
                        const SizedBox(height: 25),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ), // SafeArea
      ), // QuizMasterCircuitBackground
    ), // Scaffold
  ); // PopScope
}

  // ============================================================
  // SUBMITTED ANSWERS POPUP (live Firestore updates)
  // ============================================================
  // ============================================================
  // ELIMINATION POPUP (contestants eliminated in any level)
  // ============================================================
  // ============================================================
  // FINAL RANKING + ELIMINATION (shown after the quiz is finished)
  //
  // Lists every approved contestant with rank and score. The Quiz
  // Master chooses how many of the LOWEST-ranked contestants are
  // eliminated; they are marked in red.
  //
  // This card is a PREVIEW only. The real elimination (which the
  // contestants see) is done in FinalRankingScreen.
  // ============================================================

  Widget _finalRankingCard() {
    if (!_isFinished) return const SizedBox.shrink();

    final session = FirebaseFirestore.instance
        .collection('quiz_sessions')
        .doc(widget.quizCode);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: session
          .collection('join_requests')
          .where('status', isEqualTo: 'approved')
          .snapshots(),
      builder: (context, contestantSnap) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: session.collection('scores').snapshots(),
          builder: (context, scoreSnap) {
            final contestants = contestantSnap.data?.docs ?? [];
            final scoreDocs = scoreSnap.data?.docs ?? [];

            final scoreById = <String, Map<String, dynamic>>{
              for (final d in scoreDocs) d.id: d.data(),
            };

            final rows = <Map<String, dynamic>>[];

            for (final c in contestants) {
              final data = c.data();
              final sc = scoreById[c.id];
              final rawTeam = (data['teamName'] ?? sc?['teamName'] ?? '').toString().trim();
              final contestantType = (data['contestantType'] ?? '').toString().trim().toLowerCase();
              final isTeam = contestantType == 'team' || rawTeam.isNotEmpty;

              final personalName = (data['displayName'] ??
                      data['name'] ??
                      sc?['name'] ??
                      data['email'] ??
                      c.id)
                  .toString();

              final teamName = rawTeam.isNotEmpty ? rawTeam : (isTeam ? personalName : '');
              final displayName = isTeam ? (teamName.isNotEmpty ? teamName : personalName) : personalName;

              final rawMembers = data['teamMembers'] ?? data['members'] ?? sc?['teamMembers'] ?? sc?['members'];
              final List<String> teamMembers = [];
              if (rawMembers is List) {
                for (final m in rawMembers) {
                  final s = m is Map ? (m['name'] ?? '').toString().trim() : m.toString().trim();
                  if (s.isNotEmpty && !teamMembers.contains(s)) teamMembers.add(s);
                }
              }

              rows.add({
                'name': displayName,
                'team': isTeam ? teamName : '',
                'isTeam': isTeam,
                'teamMembers': teamMembers,
                'score': int.tryParse(sc?['score']?.toString() ?? '') ?? 0,
              });
            }

            rows.sort((a, b) {
              final byScore = (b['score'] as int).compareTo(a['score'] as int);
              if (byScore != 0) return byScore;
              return (a['name'] as String).compareTo(b['name'] as String);
            });

            // Competition ranking: equal scores share the same rank.
            final ranks = <int>[];
            for (int i = 0; i < rows.length; i++) {
              if (i > 0 && rows[i]['score'] == rows[i - 1]['score']) {
                ranks.add(ranks[i - 1]);
              } else {
                ranks.add(i + 1);
              }
            }

            // Keep at least one contestant safe.
            final maxEliminate = rows.length > 1 ? rows.length - 1 : 0;
            final eliminate = _eliminateCount.clamp(0, maxEliminate).toInt();
            final cutoff = rows.length - eliminate;

            final tieAtCutoff =
                eliminate > 0 &&
                cutoff > 0 &&
                cutoff < rows.length &&
                rows[cutoff - 1]['score'] == rows[cutoff]['score'];

            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: primaryBlue.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.emoji_events_rounded,
                          color: primaryBlue,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'FINAL RANKING & ELIMINATION',
                          style: TextStyle(
                            color: darkBlue,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Eliminate the lowest',
                            style: TextStyle(
                              color: darkBlue,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: eliminate > 0
                              ? () => setState(
                                  () => _eliminateCount = eliminate - 1,
                                )
                              : null,
                          icon: const Icon(Icons.remove_circle_outline),
                          color: primaryBlue,
                        ),
                        Text(
                          '$eliminate',
                          style: const TextStyle(
                            color: darkBlue,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          onPressed: eliminate < maxEliminate
                              ? () => setState(
                                  () => _eliminateCount = eliminate + 1,
                                )
                              : null,
                          icon: const Icon(Icons.add_circle_outline),
                          color: primaryBlue,
                        ),
                      ],
                    ),
                  ),
                  if (tieAtCutoff) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Note: there is a tie at the elimination cutoff.',
                      style: TextStyle(
                        color: Colors.orange.shade800,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No contestants to rank.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    )
                  else
                    ...List.generate(rows.length, (i) {
                      final row = rows[i];
                      final eliminated = i >= cutoff;
                      final team = row['team'] as String;

                      return Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: eliminated
                              ? Colors.red.withValues(alpha: 0.06)
                              : background,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: eliminated
                                ? Colors.red.shade200
                                : Colors.blue.shade100,
                          ),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 34,
                              child: Text(
                                '#${ranks[i]}',
                                style: TextStyle(
                                  color: eliminated ? Colors.red : primaryBlue,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    row['name'] as String,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: darkBlue,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if ((row['teamMembers'] as List).isNotEmpty)
                                    Text(
                                      'Members: ' + (row['teamMembers'] as List).join(', '),
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFF5B7A9C),
                                        fontSize: 10.5,
                                      ),
                                    )
                                  else if (team.isNotEmpty && team != row['name'])
                                    Text(
                                      team,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.black54,
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              '${row['score']} pts',
                              style: const TextStyle(
                                color: darkBlue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (eliminated) ...[
                              const SizedBox(width: 8),
                              _statusChipSimple('ELIMINATED', Colors.red),
                            ],
                          ],
                        ),
                      );
                    }),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _openFinalRanking,
                      icon: const Icon(Icons.how_to_reg_rounded),
                      label: const Text(
                        'OPEN ELIMINATION SCREEN',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
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
  }

  Widget _statusChipSimple(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ============================================================
  // INFO CHIP
  // ============================================================

  // ============================================================
  // COMPACT RESPONSIVE CONTROL BUTTON
  // ============================================================

  Widget _compactControlButton({
    required IconData icon,
    required String label,
    required Color color,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: enabled ? onTap : null,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade300,
          disabledForegroundColor: Colors.grey.shade600,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
