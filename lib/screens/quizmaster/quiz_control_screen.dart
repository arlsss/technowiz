import 'dart:async';

import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

// NOTE: i-adjust ang path kung lahi ang folder sa final_ranking_screen.dart
// pananglitan: '../quizmaster/final_ranking_screen.dart'
import 'final_ranking_screen.dart';
import 'final_tally_screen.dart';
import 'contestant_readiness_page.dart';
import 'quizmaster_dashboard.dart';
import 'quizmaster_theme.dart';
import '../../utils/refresh_blocker.dart';
import '../../navigation_persistence.dart';

class QuizControlScreen extends StatefulWidget {
  final String quizCode;
  final bool startImmediately;
  final bool isTieBreaker;

  const QuizControlScreen({
    super.key,
    required this.quizCode,
    this.startImmediately = false,
    this.isTieBreaker = false,
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
  final Set<String> _busyContestRequestIds = {};
  bool get _contestReviewBusy => _busyContestRequestIds.isNotEmpty;
  int? _contestReviewQuestionIndex;

  String _status = 'waiting';

  // Prevent repeated taps from opening the ranking screen multiple times.
  bool _finalRankingOpening = false;
  // When START NEXT LEVEL is clicked on Final Ranking, replace that route
  // with Contestant Readiness so Quiz Control does not flash in between.
  bool _replaceFinalRankingWithReadiness = false;

  // Prevent overlapping async question transitions and duplicate finish writes.
  bool _isAdvancingQuestion = false;
  bool _isFinishingQuiz = false;

  bool get _isTieBreakerActive =>
      widget.isTieBreaker || _quizData?['tieBreakerActive'] == true;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _scoresSubscription;
  bool _tieBreakerBroken = false;
  String? _tieBreakerLeadingName;
  int _tieBreakerLeadingScore = -1;

  final Map<String, Map<int, int>> _levelScoresCache = {};
  final Map<String, StreamSubscription> _responseSubs = {};
  String? _lastSyncedQuizCode;

  Map<String, dynamic>? _quizData;

  List<QueryDocumentSnapshot> _questions = [];

  // Once a quiz has started, prevent Android/system back from leaving Quiz
  // Control. The saved startedAt marker also protects this after a refresh.
  bool get _hasQuizStarted {
    if (_quizData?['startedAt'] != null) return true;
    if (_currentQuestion > 0) return true;
    final s = _status
        .toLowerCase()
        .trim()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    if (s.isEmpty) return false;
    return s != 'waiting';
  }

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _sessionDeletionSubscription;
  bool _isExitingDueToDeletion = false;

  @override
  void initState() {
    super.initState();
    RefreshBlocker.block();
    _rememberQuizControlPage();
    _listenForSessionDeletion();
    _listenForScores();
    _loadQuiz();
  }

  void _listenForScores() {
    _scoresSubscription = FirebaseFirestore.instance
        .collection('quiz_sessions')
        .doc(widget.quizCode)
        .collection('scores')
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          _syncOrFetchLevelScores(
            widget.quizCode,
            snap.docs,
            quizData: _quizData,
          );
          _updateTieBreakerScoreState(snap.docs);
        });
  }

  void _updateTieBreakerScoreState(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> scoreDocs,
  ) {
    if (!_isTieBreakerActive) return;
    final tiedUids = List<String>.from(
      _quizData?['tieBreakerContestantUids'] ?? [],
    );
    if (tiedUids.length < 2) return;

    final scoresMap = <String, int>{};
    final namesMap = <String, String>{};

    for (final doc in scoreDocs) {
      if (tiedUids.contains(doc.id)) {
        final data = doc.data();
        final s = _getContestantEffectiveScore(data, uid: doc.id);
        final rawTeam = (data['teamName'] ?? '').toString().trim();
        final String n = rawTeam.isNotEmpty
            ? rawTeam
            : [
                data['displayName'],
                data['realName'],
                data['fullName'],
                data['name'],
                data['contestantName'],
                doc.id,
              ].firstWhere(
                (v) => v != null && v.toString().trim().isNotEmpty,
                orElse: () => doc.id,
              ).toString().trim();
        scoresMap[doc.id] = s;
        namesMap[doc.id] = n;
      }
    }

    if (scoresMap.length >= 2) {
      final values = scoresMap.values.toList();
      final firstVal = values.first;
      final allEqual = values.every((v) => v == firstVal);

      String? leadName;
      int leadScore = -1;
      if (!allEqual) {
        String? leadUid;
        for (final entry in scoresMap.entries) {
          if (entry.value > leadScore) {
            leadScore = entry.value;
            leadUid = entry.key;
          }
        }
        if (leadUid != null) {
          leadName = namesMap[leadUid];
        }
      }

      setState(() {
        _tieBreakerBroken = !allEqual;
        _tieBreakerLeadingName = leadName;
        _tieBreakerLeadingScore = leadScore;
      });
    }
  }

  Future<void> _endTieBreakerAndOpenFinalTally() async {
    if (_isFinishingQuiz) return;
    _isFinishingQuiz = true;

    try {
      final quizDoc = await _getQuizSession();
      if (quizDoc != null) {
        final scoresSnap = await quizDoc.reference.collection('scores').get();
        final tiedUids = List<String>.from(
          _quizData?['tieBreakerContestantUids'] ?? [],
        );
        String? winnerUid;
        int highestScore = -1;
        bool isBroken = false;

        for (final doc in scoresSnap.docs) {
          if (tiedUids.contains(doc.id)) {
            final s = _getContestantEffectiveScore(doc.data(), uid: doc.id);
            if (s > highestScore) {
              highestScore = s;
              winnerUid = doc.id;
              isBroken = true;
            } else if (s == highestScore) {
              isBroken = false;
            }
          }
        }

        final batch = FirebaseFirestore.instance.batch();
        batch.update(quizDoc.reference, {
          'tieBreakerActive': false,
          'tieBreakerResolved': true,
          'tieBreakerEnded': true,
          'showTieBreakerResult': true,
          'status': 'tie_breaker_ended',
          'eventStatus': 'tie_breaker_ended',
          'isFinished': false,
          'finished': false,
          'timer': 0,
          'countdownActive': false,
          'readyCheckActive': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        if (winnerUid != null && isBroken) {
          final winnerScoreRef =
              quizDoc.reference.collection('scores').doc(winnerUid);
          batch.set(winnerScoreRef, {
            'tieBreakerWon': true,
            'tieBreakerResolved': true,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }

        await batch.commit();
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => FinalTallyScreen(
            quizCode: widget.quizCode,
            level: _currentLevel,
            isFinal: true,
            onFinishQuiz: () async {
              await _finishQuiz();
            },
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error ending tie breaker: $e');
      if (mounted) {
        _showMessage('Error ending tie breaker: $e');
      }
    } finally {
      _isFinishingQuiz = false;
    }
  }

  void _listenForSessionDeletion() {
    _sessionDeletionSubscription = FirebaseFirestore.instance
        .collection('quiz_sessions')
        .doc(widget.quizCode)
        .snapshots()
        .listen((snapshot) {
          final isDeleted = !snapshot.exists ||
              snapshot.data()?['deleted'] == true ||
              snapshot.data()?['isDeleted'] == true ||
              snapshot.data()?['status'] == 'deleted';
          if (isDeleted && mounted && !_isExitingDueToDeletion) {
            _handleQuizDeletedByAdmin();
          }
        });
  }

  Future<void> _handleQuizDeletedByAdmin() async {
    if (_isExitingDueToDeletion) return;
    _isExitingDueToDeletion = true;
    _timer?.cancel();
    _readyCheckTimer?.cancel();

    await QuizMasterNavPersistence.savePage('dashboard');

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('This quiz was deleted by the Admin.'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 4),
      ),
    );

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const QuizMasterDashboard(
          restoreLastPage: false,
        ),
      ),
      (route) => false,
    );
  }

  Future<void> _rememberQuizControlPage() async {
    try {
      await QuizMasterNavPersistence.savePage(
        'quiz_control',
        quizCode: widget.quizCode,
      );
    } catch (e) {
      debugPrint('Quiz Master control page save error: $e');
    }
  }

  @override
  void dispose() {
    RefreshBlocker.unblock();
    _sessionDeletionSubscription?.cancel();
    _scoresSubscription?.cancel();
    for (final sub in _responseSubs.values) {
      sub.cancel();
    }
    _responseSubs.clear();
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

    // 1. Check if the question is assigned to a specific level in levelQuestions mapping
    final qId = question.id;
    final rawLevelQuestions = _quizData?['levelQuestions'];
    if (rawLevelQuestions is Map) {
      for (final entry in rawLevelQuestions.entries) {
        if (entry.value is List && (entry.value as List).contains(qId)) {
          final m = RegExp(r'(\d+)').firstMatch(entry.key.toString());
          if (m != null) {
            final parsed = int.tryParse(m.group(1)!);
            if (parsed != null && parsed > 0) return parsed;
          }
        }
      }
    }

    // 2. Check sessionLevel explicitly
    final rawSessionLevel = data['sessionLevel'];
    if (rawSessionLevel is num && rawSessionLevel.toInt() > 0) {
      return rawSessionLevel.toInt();
    }
    if (rawSessionLevel != null) {
      final text = rawSessionLevel.toString().trim();
      final m = RegExp(r'(\d+)').firstMatch(text);
      if (m != null) {
        final parsed = int.tryParse(m.group(1)!);
        if (parsed != null && parsed > 0) return parsed;
      }
    }

    // 3. Fallback to question's level
    final value = data['level'] ?? _currentLevel;
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
    if (_getFirstQuestionIndexForLevel(level) != null) return true;
    for (int i = 0; i < _questions.length; i++) {
      if (_getQuestionLevel(_questions[i]) >= level) return true;
    }
    return false;
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
    final isTieBreakerActive = _isTieBreakerActive;
    final filtered = docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final isTB = data['isTieBreaker'] == true;
      final sessionLevel =
          (data['sessionLevel'] ?? '').toString().trim().toLowerCase();
      final isTieLevel = sessionLevel == 'tie breaker';
      if (isTieBreakerActive) {
        return isTB || isTieLevel;
      }
      if (isTB || isTieLevel) return false;
      return true;
    }).toList();

    final result = (isTieBreakerActive && filtered.isEmpty) ? docs : filtered;

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

      final quizData = quizDoc.data() ?? {};
      _quizData = quizData;

      final sortedQuestions = _sortSelectedQuestions(questionsSnapshot.docs);

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
        restoredTimer = await _getLevelTimerSeconds(
          restoredLevel,
          questionData: sortedQuestions.length > restoredQuestion
              ? (sortedQuestions[restoredQuestion].data()
                  as Map<String, dynamic>?)
              : null,
        );
      }

      final configuredTimerSeconds = await _getLevelTimerSeconds(
        restoredLevel,
        questionData: sortedQuestions.length > restoredQuestion
            ? (sortedQuestions[restoredQuestion].data()
                as Map<String, dynamic>?)
            : null,
      );
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
            'Not all approved contestants are READY yet. Please run Ready Check again.',
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
      if (_isTieBreakerActive) {
        if (_questions.isEmpty) {
          _showMessage('No tie breaker questions available.');
          return;
        }
        await _startQuestionCountdown(
          questionIndex: 0,
          level: _getLevel(0),
        );
        return;
      }

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
            'Not all approved contestants are READY yet. Please check the contestant list.',
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
      final scores = await quizDoc.reference.collection('scores').get();
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
        if (status != 'approved' &&
            status != 'proceeding' &&
            status.isNotEmpty) {
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
        final requests = await quizRef.collection('join_requests').get();
        final scores = await quizRef.collection('scores').get();
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
          if (status != 'approved' &&
              status != 'proceeding' &&
              status.isNotEmpty) {
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
            'Readiness time expired. All approved contestants are now marked READY.',
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

    final requests = await quizDoc.reference.collection('join_requests').get();
    final scores = await quizDoc.reference.collection('scores').get();
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

    final configuredSeconds = await _getLevelTimerSeconds(
      level,
      questionData: _questions.length > questionIndex
          ? (_questions[questionIndex].data() as Map<String, dynamic>?)
          : null,
    );

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

    // Auto-elimination disabled: The Quiz Master manually clicks
    // Proceed or Eliminate on the Final Ranking screen.

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
      final int nextLevel = savedLevel > _currentLevel
          ? savedLevel
          : _currentLevel + 1;

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
      await QuizMasterNavPersistence.savePage(
        'participant_readiness',
        quizCode: widget.quizCode,
        readinessLevel: nextLevel,
      );

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
            : await _getLevelTimerSeconds(
                _currentLevel,
                questionData: _questions.length > _currentQuestion
                    ? (_questions[_currentQuestion].data()
                        as Map<String, dynamic>?)
                    : null,
              );
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
    final requestId = request.id;
    if (_busyContestRequestIds.contains(requestId)) {
      return;
    }

    String? comment;

    if (approve) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.green, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Approve Contest Request?',
                  style: TextStyle(
                    color: darkBlue,
                    fontWeight: FontWeight.bold,
                    fontSize: 16.5,
                  ),
                ),
              ),
            ],
          ),
          content: const Text(
            'Are you sure you want to approve this contest request?\n\n'
            'The contestant\'s answer will be accepted and points will be awarded.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: Colors.black87,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('CONFIRM'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    } else {
      final commentController = TextEditingController();
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: const Row(
            children: [
              Icon(Icons.cancel_rounded, color: Colors.red, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Reject Contest Request',
                  style: TextStyle(
                    color: darkBlue,
                    fontWeight: FontWeight.bold,
                    fontSize: 16.5,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter comments or reason why this contest request was not approved:',
                style: TextStyle(color: Colors.black87, fontSize: 13.5),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: commentController,
                maxLines: 3,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Enter reason or comment for rejection...',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.red, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, null),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () {
                Navigator.pop(dialogContext, {
                  'confirmed': true,
                  'comment': commentController.text.trim(),
                });
              },
              child: const Text('CONFIRM'),
            ),
          ],
        ),
      );

      if (result == null || result['confirmed'] != true) return;
      comment = (result['comment'] as String?)?.trim();
    }

    setState(() {
      _busyContestRequestIds.add(requestId);
    });

    try {
      final status = approve ? 'approved' : 'rejected';
      final updateData = <String, dynamic>{
        'status': status,
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': FirebaseAuth.instance.currentUser?.uid,
        'scoreApplied': false,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (!approve && comment != null && comment.isNotEmpty) {
        updateData['comment'] = comment;
        updateData['quizmasterComment'] = comment;
        updateData['rejectionReason'] = comment;
      }

      await request.reference.update(updateData);

      // Also update the contestant's responses document if it exists so real-time sync is immediate
      final reqData = request.data();
      final contestantUid = reqData?['contestantUid']?.toString();
      final questionNumber = reqData?['questionNumber'];
      final qIndex = questionNumber is num
          ? (questionNumber.toInt() - 1)
          : (int.tryParse(questionNumber?.toString() ?? '') != null
              ? int.parse(questionNumber.toString()) - 1
              : null);

      if (contestantUid != null && qIndex != null && qIndex >= 0) {
        final respRef = FirebaseFirestore.instance
            .collection('quiz_sessions')
            .doc(widget.quizCode)
            .collection('answers')
            .doc(contestantUid)
            .collection('responses')
            .doc('question_$qIndex');

        final respUpdate = <String, dynamic>{
          'contestStatus': status,
          'answerStatus': approve ? 'correct' : 'wrong',
          'isCorrect': approve,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (!approve && comment != null && comment.isNotEmpty) {
          respUpdate['contestComment'] = comment;
          respUpdate['quizmasterComment'] = comment;
          respUpdate['rejectionReason'] = comment;
        }
        // When approved, award points directly to the contestant's score
        if (approve) {
          int pointsToAward = 1;
          if (qIndex < _questions.length) {
            final qDoc = _questions[qIndex];
            final qData = qDoc.data() as Map<String, dynamic>;
            final p = qData['points'] ??
                qData['pointValue'] ??
                qData['pts'] ??
                qData['score'];
            if (p is num && p > 0) {
              pointsToAward = p.toInt();
            } else if (p != null) {
              final parsed = int.tryParse(p.toString());
              if (parsed != null && parsed > 0) pointsToAward = parsed;
            }
          }

          respUpdate['points'] = pointsToAward;

          final scoreRef = FirebaseFirestore.instance
              .collection('quiz_sessions')
              .doc(widget.quizCode)
              .collection('scores')
              .doc(contestantUid);

          final qLevel = _getLevel(qIndex);
          final scoreUpdate = <String, dynamic>{
            'score': FieldValue.increment(pointsToAward),
            'totalScore': FieldValue.increment(pointsToAward),
            'level${qLevel}Score': FieldValue.increment(pointsToAward),
            'levelScores': {
              'Level $qLevel': FieldValue.increment(pointsToAward),
            },
            'updatedAt': FieldValue.serverTimestamp(),
          };
          if (_isTieBreakerActive) {
            scoreUpdate['tieBreakerScore'] = FieldValue.increment(pointsToAward);
          }
          await scoreRef.set(scoreUpdate, SetOptions(merge: true));

          await request.reference.update({
            'scoreApplied': true,
          });
        }

        await respRef.set(respUpdate, SetOptions(merge: true));
      }

      if (mounted) {
        _showMessage(
          approve
              ? 'Contest approved.'
              : 'Contest rejected.',
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
          _busyContestRequestIds.remove(requestId);
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
              return doc.data()['status']?.toString().toLowerCase() ==
                  'pending';
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
                        ? '$pending contestant contest request(s) need review.'
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
                      final uid =
                          (data['contestantUid'] ?? doc.id.split('_').first)
                              .toString();
                      final jData = joinByUid[uid];

                      final rawTeam =
                          (data['teamName'] ?? jData?['teamName'] ?? '')
                              .toString()
                              .trim();
                      final contestantType =
                          (data['contestantType'] ??
                                  jData?['contestantType'] ??
                                  '')
                              .toString()
                              .trim()
                              .toLowerCase();
                      final bool isTeam =
                          data['isTeam'] == true ||
                          contestantType == 'team' ||
                          jData?['isTeam'] == true ||
                          rawTeam.isNotEmpty;

                      final personalName =
                          (jData?['realName'] ??
                                  jData?['fullName'] ??
                                  jData?['displayName'] ??
                                  jData?['name'] ??
                                  data['realName'] ??
                                  data['contestantName'] ??
                                  data['displayName'] ??
                                  data['name'] ??
                                  data['email'] ??
                                  uid)
                              .toString()
                              .trim();

                      final teamName = rawTeam.isNotEmpty
                          ? rawTeam
                          : (isTeam ? personalName : '');
                      final displayName = isTeam
                          ? (teamName.isNotEmpty ? teamName : personalName)
                          : (personalName.isNotEmpty
                                ? personalName
                                : 'Contestant');

                      final rawMembers =
                          data['teamMembers'] ??
                          data['members'] ??
                          jData?['teamMembers'] ??
                          jData?['members'];
                      final List<String> teamMembers = [];
                      if (rawMembers is List) {
                        for (final m in rawMembers) {
                          final s = m is Map
                              ? (m['name'] ?? m['displayName'] ?? '')
                                    .toString()
                                    .trim()
                              : m.toString().trim();
                          if (s.isNotEmpty && !teamMembers.contains(s)) {
                            teamMembers.add(s);
                          }
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
                      final requestId = doc.id;
                      final bool isThisRequestBusy =
                          _busyContestRequestIds.contains(requestId);

                      return Container(
                        key: ValueKey('review_contest_$requestId'),
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
                                  isTeam
                                      ? Icons.groups_rounded
                                      : Icons.person_rounded,
                                  color: primaryBlue,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: primaryBlue.withValues(
                                                  alpha: 0.10,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(6),
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
                                          padding: const EdgeInsets.only(
                                            top: 3,
                                          ),
                                          child: Text(
                                            'Members: ${teamMembers.join(', ')}',
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
                              style: const TextStyle(
                                color: darkBlue,
                                height: 1.35,
                              ),
                            ),
                            if (isPending) ...[
                              const SizedBox(height: 13),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: isThisRequestBusy
                                          ? null
                                          : () => _reviewContestRequest(
                                              request: doc,
                                              approve: false,
                                            ),
                                      icon: const Icon(Icons.close_rounded),
                                      label: const Text('REJECT'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.red,
                                        side: const BorderSide(
                                          color: Colors.red,
                                        ),
                                        disabledForegroundColor:
                                            Colors.red.withValues(alpha: 0.5),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 11,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: isThisRequestBusy
                                          ? null
                                          : () => _reviewContestRequest(
                                              request: doc,
                                              approve: true,
                                            ),
                                      icon: isThisRequestBusy
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(Icons.check_rounded),
                                      label: Text(
                                        isThisRequestBusy ? 'APPROVING...' : 'APPROVE',
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                        disabledBackgroundColor:
                                            Colors.green.withValues(alpha: 0.7),
                                        disabledForegroundColor: Colors.white,
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

  Future<int> _getLevelTimerSeconds(
    int level, {
    dynamic questionData,
  }) async {
    try {
      if (questionData != null && questionData is Map) {
        final qTimer = _asInt(
          questionData['timerSeconds'] ??
              questionData['timer'] ??
              questionData['timeLimit'],
        );
        if (qTimer != null && qTimer > 0) return qTimer;
      }

      final quizDoc = await _getQuizSession();
      if (quizDoc == null) return 30;

      final data = quizDoc.data() ?? {};

      if (_isTieBreakerActive) {
        final tbTimer = _asInt(
          data['tieBreakerTimerSeconds'] ??
              data['tieBreakerSettings']?['timerSeconds'] ??
              data['levelSettings']?['Tie Breaker']?['timerSeconds'] ??
              data['levelSettings']?['tie_breaker']?['timerSeconds'],
        );
        if (tbTimer != null && tbTimer > 0) return tbTimer;
      }

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

        // Auto-elimination disabled: The Quiz Master manually clicks
        // Proceed or Eliminate on the Final Ranking screen.

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
          _showMessage(
            'Level $currentLevel finished. '
            'Press START LEVEL $nextLevel to continue.',
          );
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
        'publishedWinners': true,
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
          final int score = _getContestantEffectiveScore(sData, uid: doc.id);
          final rawUpdated = sData['updatedAt'];
          final int timeMs = rawUpdated is Timestamp
              ? rawUpdated.millisecondsSinceEpoch
              : 0;
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
          final int scoreCompare = (b['score'] as int).compareTo(
            a['score'] as int,
          );
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
            final int score =
                scoresByUid[req.id] ??
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
            final int score =
                scoresByUid[doc.id] ??
                _getContestantEffectiveScore(doc.data(), uid: doc.id);
            batch.set(doc.reference, {
              'finalRank': assignedRank,
              'rank': assignedRank,
              'levelRank': assignedRank,
              'currentRank': assignedRank,
              'finalScore': score,
              'score': score,
              'totalScore': score,
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

      await QuizMasterNavPersistence.savePage(
        'ranking',
        quizCode: widget.quizCode,
        rankingLevel: _currentLevel,
        rankingIsFinal: true,
      );

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
  // OPEN FINAL TALLY (TABLE FORM WITH CONTESTANT STATS & TIE BREAKER)
  // ============================================================

  Future<void> _openFinalTally({bool isFinal = false}) async {
    if (!mounted || _finalRankingOpening) return;

    _finalRankingOpening = true;
    try {
      await Navigator.of(context).push<void>(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => FinalTallyScreen(
            quizCode: widget.quizCode,
            level: _currentLevel,
            isFinal: isFinal,
            onFinishQuiz: () async {
              await _finishQuiz();
            },
            onProceedToNextLevel: () async {},
          ),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
      if (mounted) {
        await _rememberQuizControlPage();
      }
    } finally {
      _finalRankingOpening = false;
    }
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
      if (mounted) {
        await _rememberQuizControlPage();
      }
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
                              'CONTESTANT STATUS',
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
                              ? 'All contestants are ready. You can start the quiz.'
                              : 'Waiting for all approved contestants to confirm.',
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
                                '$readyCount / ${docs.length} CONTESTANTS READY',
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
                                    'No approved contestants found. Approve contestants in the Waiting Room first.',
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
                                      'Not all approved contestants are READY yet.',
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
                    s.data()['status']?.toString().toLowerCase() ==
                        'eliminated')
                  s.id,
            };

            final docs = rawRequests.where((doc) {
              final data = doc.data();
              final status = (data['status'] ?? '')
                  .toString()
                  .trim()
                  .toLowerCase();
              if (status != 'approved' &&
                  status != 'proceeding' &&
                  status.isNotEmpty) {
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
                  color: allReady
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
                      color: allReady
                          ? Colors.green.withValues(alpha: 0.08)
                          : background,
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
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
                      child: const Icon(
                        Icons.gavel_rounded,
                        color: Colors.grey,
                      ),
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
                            'No contest for Question $questionNumber.',
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
                    'Question $questionNumber — a contestant is contesting.',
                    style: const TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  ...docs.map((doc) {
                    final data = doc.data();
                    final uid =
                        (data['contestantUid'] ?? doc.id.split('_').first)
                            .toString();
                    final jData = joinByUid[uid];

                    final rawTeam =
                        (data['teamName'] ?? jData?['teamName'] ?? '')
                            .toString()
                            .trim();
                    final contestantType =
                        (data['contestantType'] ??
                                jData?['contestantType'] ??
                                '')
                            .toString()
                            .trim()
                            .toLowerCase();
                    final bool isTeam =
                        data['isTeam'] == true ||
                        contestantType == 'team' ||
                        jData?['isTeam'] == true ||
                        rawTeam.isNotEmpty;

                    final personalName =
                        (jData?['realName'] ??
                                jData?['fullName'] ??
                                jData?['displayName'] ??
                                jData?['name'] ??
                                data['realName'] ??
                                data['contestantName'] ??
                                data['displayName'] ??
                                data['name'] ??
                                data['email'] ??
                                uid)
                            .toString()
                            .trim();

                    final teamName = rawTeam.isNotEmpty
                        ? rawTeam
                        : (isTeam ? personalName : '');
                    final displayName = isTeam
                        ? (teamName.isNotEmpty ? teamName : personalName)
                        : (personalName.isNotEmpty
                              ? personalName
                              : 'Contestant');

                    final rawMembers =
                        data['teamMembers'] ??
                        data['members'] ??
                        jData?['teamMembers'] ??
                        jData?['members'];
                    final List<String> teamMembers = [];
                    if (rawMembers is List) {
                      for (final m in rawMembers) {
                        final s = m is Map
                            ? (m['name'] ?? m['displayName'] ?? '')
                                  .toString()
                                  .trim()
                            : m.toString().trim();
                        if (s.isNotEmpty && !teamMembers.contains(s)) {
                          teamMembers.add(s);
                        }
                      }
                    }

                    final answer =
                        data['contestantAnswer']?.toString().trim() ?? '';
                    final expected =
                        data['expectedAnswer']?.toString().trim() ?? '';
                    final explanation =
                        data['explanation']?.toString().trim() ?? '';
                    final requestId = doc.id;
                    final bool isThisRequestBusy =
                        _busyContestRequestIds.contains(requestId);

                    return Container(
                      key: ValueKey('live_contest_$requestId'),
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
                                isTeam
                                    ? Icons.groups_rounded
                                    : Icons.person_rounded,
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
                                              color: primaryBlue.withValues(
                                                alpha: 0.10,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(6),
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
                                          'Members: ${teamMembers.join(', ')}',
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
                            style: const TextStyle(
                              color: darkBlue,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 13),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: isThisRequestBusy
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
                                    disabledForegroundColor:
                                        Colors.red.withValues(alpha: 0.5),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 11,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: isThisRequestBusy
                                      ? null
                                      : () => _reviewContestRequest(
                                          request: doc,
                                          approve: true,
                                        ),
                                  icon: isThisRequestBusy
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.check_rounded),
                                  label: Text(
                                    isThisRequestBusy ? 'APPROVING...' : 'APPROVE',
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor:
                                        Colors.green.withValues(alpha: 0.7),
                                    disabledForegroundColor: Colors.white,
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
    final decision = (data['contestantDecision'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return data['eliminated'] == true ||
        data['isEliminated'] == true ||
        status == 'eliminated' ||
        decision == 'eliminated' ||
        status == 'left' ||
        status == 'rejected' ||
        status == 'declined' ||
        data['leftQuiz'] == true;
  }

  int _getAdminPointsForLevel(int level, Map<String, dynamic>? quizData) {
    if (quizData == null) return level;
    final rawSettings = quizData['levelSettings'] ?? quizData['levels'];
    if (rawSettings is Map) {
      final target = 'level$level';
      for (final entry in rawSettings.entries) {
        final norm = entry.key
            .toString()
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '');
        if ((norm == target || norm == '$level') && entry.value is Map) {
          final val = entry.value['pointsPerCorrectAnswer'] ??
              entry.value['points_per_correct_answer'] ??
              entry.value['pointsPerQuestion'] ??
              entry.value['points'];
          if (val is num && val > 0) return val.toInt();
          if (val != null) {
            final p = int.tryParse(val.toString());
            if (p != null && p > 0) return p;
          }
        }
      }
    }
    for (final key in [
      'level${level}Points',
      'level${level}PointsPerCorrectAnswer',
      'level${level}PointsPerQuestion',
      'level_${level}_points',
    ]) {
      final val = quizData[key];
      if (val is num && val > 0) return val.toInt();
      if (val != null) {
        final p = int.tryParse(val.toString());
        if (p != null && p > 0) return p;
      }
    }
    return level;
  }

  int _resolveResponseQuestionLevel(
    String docId,
    Map<String, dynamic> rData,
    Map<String, dynamic>? quizData,
  ) {
    final effectiveQuizData = quizData ?? _quizData;
    final rawLevelQuestions = effectiveQuizData?['levelQuestions'] ??
        effectiveQuizData?['level_questions'];

    // 1. Check by questionId in levelQuestions
    final qId = (rData['questionId'] ?? rData['id'] ?? '').toString().trim();
    if (qId.isNotEmpty && rawLevelQuestions is Map) {
      for (final entry in rawLevelQuestions.entries) {
        if (entry.value is List && (entry.value as List).contains(qId)) {
          final m = RegExp(r'(\d+)').firstMatch(entry.key.toString());
          if (m != null) {
            final p = int.tryParse(m.group(1)!);
            if (p != null && p > 0) return p;
          }
        }
      }
    }

    // 2. Check by question index from docId or questionNumber
    final matchQ = RegExp(r'question_(\d+)').firstMatch(docId);
    int qIndex = matchQ != null ? (int.tryParse(matchQ.group(1)!) ?? -1) : -1;
    if (qIndex < 0 && rData['questionNumber'] is num) {
      qIndex = (rData['questionNumber'] as num).toInt() - 1;
    }

    if (qIndex >= 0) {
      if (rawLevelQuestions is Map) {
        int accumulated = 0;
        for (int l = 1; l <= 20; l++) {
          final target = 'level$l';
          int count = 0;
          for (final entry in rawLevelQuestions.entries) {
            final norm = entry.key
                .toString()
                .toLowerCase()
                .replaceAll(RegExp(r'[^a-z0-9]'), '');
            if ((norm == target || norm == '$l') && entry.value is List) {
              count = (entry.value as List).length;
              break;
            }
          }
          if (count > 0) {
            if (qIndex < accumulated + count) {
              return l;
            }
            accumulated += count;
          }
        }
      }
      if (qIndex < _questions.length) {
        return _getLevel(qIndex);
      }
    }

    // 3. Fallback to sessionLevel or level in rData
    final rawLvl = rData['sessionLevel'] ?? rData['level'];
    if (rawLvl is num) {
      final v = rawLvl.toInt();
      if (v > 0) return v;
    } else if (rawLvl != null) {
      final m = RegExp(r'(\d+)').firstMatch(rawLvl.toString());
      if (m != null) {
        final v = int.tryParse(m.group(1)!);
        if (v != null && v > 0) return v;
      }
    }

    return 1;
  }

  void _syncOrFetchLevelScores(
    String quizCode,
    List<QueryDocumentSnapshot> scoreDocs, {
    Map<String, dynamic>? quizData,
  }) {
    if (quizCode.isEmpty) return;

    if (_lastSyncedQuizCode != quizCode) {
      _lastSyncedQuizCode = quizCode;
      _levelScoresCache.clear();
      for (final sub in _responseSubs.values) {
        sub.cancel();
      }
      _responseSubs.clear();
    }

    for (final doc in scoreDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final uid = (data['uid'] ?? doc.id).toString();

      if (!_responseSubs.containsKey(uid)) {
        final sub = FirebaseFirestore.instance
            .collection('quiz_sessions')
            .doc(quizCode)
            .collection('answers')
            .doc(uid)
            .collection('responses')
            .snapshots()
            .listen((responsesSnap) {
          if (!mounted) return;
          final Map<int, int> userLevelScores = {};
          int totalRespPoints = 0;
          for (final r in responsesSnap.docs) {
            final rData = r.data();
            int lvl = 1;
            final rawLvl = rData['level'] ?? rData['sessionLevel'];
            if (rawLvl is num && rawLvl > 0) {
              lvl = rawLvl.toInt();
            } else if (rawLvl != null) {
              final m = RegExp(r'(\d+)').firstMatch(rawLvl.toString());
              if (m != null) {
                final p = int.tryParse(m.group(1)!);
                if (p != null && p > 0) lvl = p;
              }
            } else {
              lvl = _resolveResponseQuestionLevel(r.id, rData, quizData ?? _quizData);
            }

            final isCorrect = rData['isCorrect'] == true ||
                (rData['answerStatus'] ?? '').toString().toLowerCase() ==
                    'correct' ||
                (rData['contestStatus'] ?? '').toString().toLowerCase() ==
                    'approved';
            if (isCorrect) {
              int pts = 0;
              final rawPts = rData['points'];
              if (rawPts is num && rawPts > 0) {
                pts = rawPts.toInt();
              } else if (rawPts != null &&
                  int.tryParse(rawPts.toString()) != null &&
                  int.tryParse(rawPts.toString())! > 0) {
                pts = int.tryParse(rawPts.toString())!;
              } else {
                final adminPts =
                    _getAdminPointsForLevel(lvl, quizData ?? _quizData);
                pts = adminPts > 0 ? adminPts : 1;
              }
              userLevelScores[lvl] = (userLevelScores[lvl] ?? 0) + pts;
              totalRespPoints += pts;
            }
          }

          if (responsesSnap.docs.isNotEmpty || userLevelScores.isNotEmpty) {
            setState(() {
              _levelScoresCache[uid] = userLevelScores;
            });

            final updateData = <String, dynamic>{};
            for (final entry in userLevelScores.entries) {
              updateData['level${entry.key}Score'] = entry.value;
              updateData['level_${entry.key}'] = entry.value;
            }
            updateData['levelScores'] = {
              for (final entry in userLevelScores.entries)
                'Level ${entry.key}': entry.value,
            };
            final int tiePts = _asInt(data['tieBreakerScore']) ?? 0;
            final int realTotal = totalRespPoints + tiePts;
            final int existingDocScore = _asInt(data['score']) ?? _asInt(data['totalScore']) ?? 0;
            final int bestTotal = realTotal >= existingDocScore ? realTotal : existingDocScore;
            updateData['score'] = bestTotal;
            updateData['totalScore'] = bestTotal;
            doc.reference
                .set(updateData, SetOptions(merge: true))
                .catchError((_) {});
          }
        }, onError: (_) {});
        _responseSubs[uid] = sub;
      }
    }
  }

  int _getContestantEffectiveScore(
    Map<String, dynamic> sData, {
    Map<String, dynamic>? jData,
    String? uid,
  }) {
    final tiePts = _asInt(sData['tieBreakerScore']) ??
        _asInt(jData?['tieBreakerScore']) ??
        0;

    final stored = _asInt(sData['score']) ??
        _asInt(sData['totalScore']) ??
        _asInt(jData?['score']) ??
        0;

    // 1. If we have live cached response scores from responses subcollection
    if (uid != null && _levelScoresCache.containsKey(uid)) {
      final cached = _levelScoresCache[uid];
      if (cached != null) {
        final cachedSum = cached.values.fold<int>(0, (acc, val) => acc + val);
        final int calculated = cachedSum + tiePts;
        return calculated > stored ? calculated : stored;
      }
    }

    // 2. Sum up configured level scores from levelScores map and level1Score..level20Score
    final Map<int, int> levelPointsMap = {};
    if (sData['levelScores'] is Map) {
      (sData['levelScores'] as Map).forEach((k, v) {
        final m = RegExp(r'\d+').firstMatch(k.toString());
        final lvlNum = m != null ? int.tryParse(m.group(0)!) ?? 0 : 0;
        final p = _asInt(v) ?? 0;
        if (lvlNum > 0 && p > 0) {
          levelPointsMap[lvlNum] = p;
        }
      });
    }

    for (int l = 1; l <= 20; l++) {
      final val = _asInt(sData['level${l}Score']) ??
          _asInt(sData['level_$l']) ??
          _asInt(sData['level$l']) ??
          0;
      if (val > 0 &&
          (!levelPointsMap.containsKey(l) || levelPointsMap[l]! < val)) {
        levelPointsMap[l] = val;
      }
    }

    final int sumOfLevels =
        levelPointsMap.values.fold<int>(0, (acc, val) => acc + val);

    final int calculated = sumOfLevels + tiePts;
    return calculated > stored ? calculated : stored;
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

    if (_isTieBreakerActive) {
      final rawTiedUids = _quizData?['tieBreakerContestantUids'];
      final tiedUids = rawTiedUids is List
          ? rawTiedUids.map((e) => e.toString()).toList()
          : <String>[];
      final rawTiedNames = _quizData?['tieBreakerContestantNames'];
      final tiedNames = rawTiedNames is List
          ? rawTiedNames.map((e) => e.toString()).toList()
          : <String>[];

      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: sessionRef.collection('join_requests').snapshots(),
        builder: (context, requestsSnapshot) {
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: sessionRef.collection('scores').snapshots(),
            builder: (context, scoresSnapshot) {
              final reqDocs = requestsSnapshot.data?.docs ?? [];
              final scoreDocs = scoresSnapshot.data?.docs ?? [];

              final tiedData = <Map<String, dynamic>>[];
              for (int i = 0; i < tiedUids.length; i++) {
                final uid = tiedUids[i];
                final fallbackName =
                    (i < tiedNames.length && tiedNames[i].trim().isNotEmpty)
                        ? tiedNames[i].trim()
                        : 'Contestant ${i + 1}';

                final reqDoc = reqDocs.where((d) {
                  final data = d.data();
                  if (d.id == uid) return true;
                  if ((data['uid'] ?? '').toString() == uid) return true;
                  if ((data['userId'] ?? '').toString() == uid) return true;
                  if (fallbackName.isNotEmpty) {
                    final target = fallbackName.toLowerCase();
                    final dName = (data['teamName'] ??
                            data['displayName'] ??
                            data['realName'] ??
                            data['name'] ??
                            '')
                        .toString()
                        .trim()
                        .toLowerCase();
                    if (dName.isNotEmpty && dName == target) return true;
                  }
                  return false;
                }).firstOrNull;
                final req = reqDoc?.data() ?? {};

                final scDoc = scoreDocs.where((d) {
                  final data = d.data();
                  if (d.id == uid) return true;
                  if ((data['uid'] ?? '').toString() == uid) return true;
                  if ((data['userId'] ?? '').toString() == uid) return true;
                  if (fallbackName.isNotEmpty) {
                    final target = fallbackName.toLowerCase();
                    final dName = (data['teamName'] ??
                            data['displayName'] ??
                            data['realName'] ??
                            data['name'] ??
                            data['contestantName'] ??
                            '')
                        .toString()
                        .trim()
                        .toLowerCase();
                    if (dName.isNotEmpty && dName == target) return true;
                  }
                  return false;
                }).firstOrNull;
                final sc = scDoc?.data() ?? {};

                final rawTeam =
                    (sc['teamName'] ?? req['teamName'] ?? '').toString().trim();
                final contestantType =
                    (sc['contestantType'] ?? req['contestantType'] ?? '')
                        .toString()
                        .trim()
                        .toLowerCase();
                final bool isTeam = sc['isTeam'] == true ||
                    req['isTeam'] == true ||
                    contestantType == 'team' ||
                    rawTeam.isNotEmpty;

                final String personalFullName = [
                  req['realName'],
                  req['fullName'],
                  req['displayName'],
                  req['name'],
                  sc['realName'],
                  sc['fullName'],
                  sc['displayName'],
                  sc['name'],
                  sc['contestantName'],
                  req['email'],
                  sc['email'],
                  fallbackName,
                ].firstWhere(
                  (v) => v != null && v.toString().trim().isNotEmpty,
                  orElse: () => fallbackName,
                ).toString().trim();

                final String finalTeamName = rawTeam.isNotEmpty
                    ? rawTeam
                    : (isTeam ? personalFullName : '');

                final String displayName = isTeam
                    ? (finalTeamName.isNotEmpty
                        ? finalTeamName
                        : personalFullName)
                    : (personalFullName.isNotEmpty
                        ? personalFullName
                        : fallbackName);

                final rawMembers = sc['teamMembers'] ??
                    sc['members'] ??
                    req['teamMembers'] ??
                    req['members'];
                final List<String> teamMembers = [];
                if (rawMembers is List) {
                  for (final m in rawMembers) {
                    final s = m is Map
                        ? (m['name'] ?? m['displayName'] ?? '')
                            .toString()
                            .trim()
                        : m.toString().trim();
                    if (s.isNotEmpty && !teamMembers.contains(s)) {
                      teamMembers.add(s);
                    }
                  }
                }

                final score =
                    _getContestantEffectiveScore(sc, jData: req, uid: uid);
                final isReady = req['tieBreakerReady'] == true ||
                    sc['tieBreakerReady'] == true ||
                    _isConfirmed(req) ||
                    _isConfirmed(sc);
                tiedData.add({
                  'uid': uid,
                  'name': displayName,
                  'isTeam': isTeam,
                  'teamName': finalTeamName,
                  'personalFullName': personalFullName,
                  'teamMembers': teamMembers,
                  'score': score,
                  'isReady': isReady,
                });
              }

              final scores =
                  tiedData.map((t) => t['score'] as int).toList();
              final isBroken =
                  scores.length >= 2 && scores.toSet().length > 1;
              final maxScore = scores.isNotEmpty
                  ? scores.reduce((a, b) => a > b ? a : b)
                  : 0;

              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isBroken
                        ? Colors.green.shade400
                        : Colors.amber.shade400,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (isBroken ? Colors.green : Colors.amber)
                          .withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: (isBroken ? Colors.green : Colors.amber)
                                .shade100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isBroken
                                ? Icons.emoji_events_rounded
                                : Icons.balance_rounded,
                            color: isBroken
                                ? Colors.green.shade800
                                : Colors.amber.shade900,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isBroken
                                    ? 'TIE BROKEN — WINNER FOUND!'
                                    : 'TIE BREAKER SHOWDOWN IN PROGRESS',
                                style: TextStyle(
                                  color: isBroken
                                      ? Colors.green.shade900
                                      : Colors.amber.shade900,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13.5,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              Text(
                                isBroken
                                    ? 'A contestant has broken the tie! Tap END TIE BREAKER to finalize results.'
                                    : 'Sudden-Death Rule: Higher point wins immediately.',
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...tiedData.map((item) {
                      final name = item['name'] as String;
                      final score = item['score'] as int;
                      final isReady = item['isReady'] as bool;
                      final isTeam = item['isTeam'] == true;
                      final teamMembers =
                          (item['teamMembers'] as List<String>?) ?? [];
                      final isLeading = isBroken && score == maxScore;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isLeading
                              ? const Color(0xFFF0FDF4)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isLeading
                                ? Colors.green.shade300
                                : const Color(0xFFE2E8F0),
                            width: isLeading ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              isReady
                                  ? Icons.check_circle_rounded
                                  : Icons.hourglass_empty_rounded,
                              color:
                                  isReady ? Colors.green : Colors.orange,
                              size: 18,
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
                                          name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: isLeading
                                                ? FontWeight.w900
                                                : FontWeight.w700,
                                            color: isLeading
                                                ? Colors.green.shade900
                                                : darkBlue,
                                            fontSize: 13.5,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      if (isTeam)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 1.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: primaryBlue.withValues(
                                              alpha: 0.10,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(5),
                                            border: Border.all(
                                              color: primaryBlue.withValues(
                                                alpha: 0.25,
                                              ),
                                            ),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.groups_rounded,
                                                size: 10,
                                                color: primaryBlue,
                                              ),
                                              SizedBox(width: 2.5),
                                              Text(
                                                'TEAM',
                                                style: TextStyle(
                                                  color: primaryBlue,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 0.3,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      else
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 1.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF10B981)
                                                .withValues(alpha: 0.10),
                                            borderRadius:
                                                BorderRadius.circular(5),
                                            border: Border.all(
                                              color: const Color(0xFF10B981)
                                                .withValues(alpha: 0.25),
                                            ),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.person_rounded,
                                                size: 10,
                                                color: Color(0xFF059669),
                                              ),
                                              SizedBox(width: 2.5),
                                              Text(
                                                'SOLO',
                                                style: TextStyle(
                                                  color: Color(0xFF059669),
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 0.3,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (isTeam && teamMembers.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2.5),
                                      child: Text(
                                        'Members: ${teamMembers.join(', ')}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF5B7A9C),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: isLeading
                                    ? Colors.green
                                    : primaryBlue,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                score == 0
                                    ? '0'
                                    : (score == 1 ? '1 PT' : '$score PTS'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isReady ? 'CONFIRMED' : 'WAITING',
                              style: TextStyle(
                                color: isReady
                                    ? Colors.green
                                    : Colors.orange,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
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
                    s.data()['status']?.toString().toLowerCase() ==
                        'eliminated')
                  s.id,
            };

            final docs = rawRequests.where((doc) {
              final data = doc.data();
              final status = (data['status'] ?? '')
                  .toString()
                  .trim()
                  .toLowerCase();
              if (status != 'approved' &&
                  status != 'proceeding' &&
                  status.isNotEmpty) {
                return false;
              }
              return !_isDocEliminated(doc, eliminatedScoreIds);
            }).toList();

            final confirmed = docs
                .where((doc) => _isConfirmed(doc.data()))
                .length;
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
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
      final scores = await quizDoc.reference.collection('scores').get();

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
        if (status != 'approved' &&
            status != 'proceeding' &&
            status.isNotEmpty) {
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

    if (!mounted) return;
    await _openFinalTally(isFinal: true);
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

    // 1. On the last question of an intermediate level, proceed to Intermediate Level Result / Elimination.
    if (isLastQuestionOfLevel && hasNextLevel) {
      _endLevelAndOpenElimination();
      return;
    }

    // 2. On the last question of the final level, go directly to Final Tally.
    if (isFinalQuestionOfQuiz) {
      _finishQuizAndOpenFinalRanking();
      return;
    }

    // 3. If clicked early (questions still remain in the level):
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            hasNextLevel
                ? 'End Level $currentLevel Early?'
                : 'Finish Quiz Early?',
            style: const TextStyle(
              color: darkBlue,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            hasNextLevel
                ? 'There are still remaining questions in Level $currentLevel.\n\n'
                    'Do you want to end Level $currentLevel now and proceed to level results?'
                : 'There are still remaining questions or levels in this quiz.\n\n'
                    'Do you want to end the quiz now and proceed directly to Final Tally?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                if (hasNextLevel) {
                  _endLevelAndOpenElimination();
                } else {
                  _finishQuizAndOpenFinalRanking();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('END LEVEL'),
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
                            const SizedBox(height: 22),
                            const Divider(height: 1),
                            const SizedBox(height: 16),
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
                                    'Contestant Answers',
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
          final aRawTeam = (aData['teamName'] ?? '').toString().trim();
          final aType = (aData['contestantType'] ?? '').toString().trim().toLowerCase();
          final bool aIsTeam = aData['isTeam'] == true || aType == 'team' || aRawTeam.isNotEmpty;
          final aName = aIsTeam && aRawTeam.isNotEmpty
              ? aRawTeam
              : (aData['realName'] ?? aData['fullName'] ?? aData['displayName'] ?? aData['name'] ?? aData['email'] ?? a.id).toString();

          final bRawTeam = (bData['teamName'] ?? '').toString().trim();
          final bType = (bData['contestantType'] ?? '').toString().trim().toLowerCase();
          final bool bIsTeam = bData['isTeam'] == true || bType == 'team' || bRawTeam.isNotEmpty;
          final bName = bIsTeam && bRawTeam.isNotEmpty
              ? bRawTeam
              : (bData['realName'] ?? bData['fullName'] ?? bData['displayName'] ?? bData['name'] ?? bData['email'] ?? b.id).toString();

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
            final rawTeam = (contestant['teamName'] ?? '').toString().trim();
            final contestantType = (contestant['contestantType'] ?? '').toString().trim().toLowerCase();
            final bool isTeam = contestant['isTeam'] == true ||
                contestantType == 'team' ||
                rawTeam.isNotEmpty;
            final personalFullName = (contestant['realName'] ??
                    contestant['fullName'] ??
                    contestant['displayName'] ??
                    contestant['name'] ??
                    contestant['email'] ??
                    contestantDoc.id)
                .toString()
                .trim();
            final teamName = rawTeam.isNotEmpty
                ? rawTeam
                : (isTeam ? personalFullName : '');
            final name = isTeam
                ? (teamName.isNotEmpty ? teamName : personalFullName)
                : (personalFullName.isNotEmpty ? personalFullName : 'Contestant');

            final rawMembers =
                contestant['teamMembers'] ?? contestant['members'];
            final List<String> teamMembers = [];
            if (rawMembers is List) {
              for (final m in rawMembers) {
                final s = m is Map
                    ? (m['name'] ?? m['displayName'] ?? '').toString().trim()
                    : m.toString().trim();
                if (s.isNotEmpty && !teamMembers.contains(s)) teamMembers.add(s);
              }
            }

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
                var pendingContestCount = 0;

                for (final responseDoc in responseDocs) {
                  final data = responseDoc.data();
                  final answerStatus = (data['answerStatus'] ?? '')
                      .toString()
                      .toLowerCase();
                  final rawCorrect = data['isCorrect'];
                  final contestStatus = (data['contestStatus'] ?? '')
                      .toString()
                      .toLowerCase();

                  final bool isApproved = contestStatus == 'approved';
                  final bool isRejected = contestStatus == 'rejected' ||
                      contestStatus == 'declined' ||
                      contestStatus == 'invalid';
                  final bool isPending = contestStatus == 'pending' ||
                      (answerStatus == 'contested' &&
                          !isApproved &&
                          !isRejected);

                  if (isPending) {
                    pendingContestCount++;
                  }

                  if (isApproved ||
                      answerStatus == 'correct' ||
                      rawCorrect == true) {
                    correctCount++;
                  } else if (isRejected ||
                      answerStatus == 'wrong' ||
                      isPending ||
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

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      _showContestantAnswersDialog(
                        context: context,
                        uid: contestantDoc.id,
                        name: name,
                        isTeam: isTeam,
                        teamMembers: teamMembers,
                        responseDocs: responseDocs,
                      );
                    },
                    child: Container(
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
                              Icon(
                                isTeam
                                    ? Icons.groups_rounded
                                    : Icons.person_rounded,
                                color: primaryBlue,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        color: darkBlue,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (isTeam && teamMembers.isNotEmpty)
                                      Text(
                                        'Members: ${teamMembers.join(', ')}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFF5B7A9C),
                                          fontSize: 10.5,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              if (contestant['eliminated'] == true ||
                                  contestant['isEliminated'] == true ||
                                  (contestant['status'] ?? '')
                                          .toString()
                                          .trim()
                                          .toLowerCase() ==
                                      'eliminated' ||
                                  contestant['eliminationConfirmed'] ==
                                      true) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF2F2),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: const Color(0xFFFCA5A5),
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.cancel_rounded,
                                        size: 11,
                                        color: Color(0xFFDC2626),
                                      ),
                                      SizedBox(width: 3),
                                      Text(
                                        'ELIMINATED',
                                        style: TextStyle(
                                          color: Color(0xFFDC2626),
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                              ],
                              if (isTeam)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: primaryBlue.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color:
                                          primaryBlue.withValues(alpha: 0.25),
                                    ),
                                  ),
                                  child: const Text(
                                    'TEAM',
                                    style: TextStyle(
                                      color: primaryBlue,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(
                                      alpha: 0.10,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: const Color(0xFF10B981).withValues(
                                        alpha: 0.25,
                                      ),
                                    ),
                                  ),
                                  child: const Text(
                                    'SOLO',
                                    style: TextStyle(
                                      color: Color(0xFF059669),
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.open_in_new_rounded,
                                size: 14,
                                color: Color(0xFF94A3B8),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (isLoading)
                            const LinearProgressIndicator(minHeight: 2)
                          else ...[
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
                            if (pendingContestCount > 0) ...[
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: Colors.amber.shade300,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.hourglass_top_rounded,
                                      size: 12,
                                      color: Colors.amber.shade900,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      '$pendingContestCount contest pending review',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: Colors.amber.shade900,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          }).toList(),
        );
      },
    );
  }

  void _showContestantAnswersDialog({
    required BuildContext context,
    required String uid,
    required String name,
    required bool isTeam,
    required List<String> teamMembers,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> responseDocs,
  }) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        String filter = 'all';

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final List<Map<String, dynamic>> items = [];

            for (final doc in responseDocs) {
              final data = doc.data();
              final rawIdx = doc.id.replaceAll('question_', '');
              final int qIdx = int.tryParse(rawIdx) ??
                  ((data['questionNumber'] as num?)?.toInt() ?? 1) - 1;
              final qNum = qIdx + 1;

              final answerStatus = (data['answerStatus'] ?? '')
                  .toString()
                  .toLowerCase();
              final rawCorrect = data['isCorrect'];
              final contestStatus = (data['contestStatus'] ?? '')
                  .toString()
                  .toLowerCase();

              final bool isApproved = contestStatus == 'approved';
              final bool isRejected = contestStatus == 'rejected' ||
                  contestStatus == 'declined' ||
                  contestStatus == 'invalid';
              final bool isPendingContest = contestStatus == 'pending' ||
                  (answerStatus == 'contested' && !isApproved && !isRejected);

              final bool isCheck = isApproved ||
                  answerStatus == 'correct' ||
                  rawCorrect == true;
              final bool isUnanswered = answerStatus == 'unanswered';
              final bool isWrong = !isCheck && !isUnanswered;

              String questionText = (data['questionText'] ??
                      data['question'] ??
                      '')
                  .toString();
              String expectedAnswer = (data['expectedAnswer'] ??
                      data['correctAnswer'] ??
                      data['answer'] ??
                      '')
                  .toString();

              if (qIdx >= 0 && qIdx < _questions.length) {
                final qDocData =
                    _questions[qIdx].data() as Map<String, dynamic>;
                if (questionText.isEmpty) {
                  questionText = (qDocData['questionText'] ??
                          qDocData['question'] ??
                          qDocData['text'] ??
                          '')
                      .toString();
                }
                if (expectedAnswer.isEmpty) {
                  expectedAnswer = (qDocData['correctAnswer'] ??
                          qDocData['answer'] ??
                          '')
                      .toString();
                }
              }

              final contestantAnswer = (data['selectedAnswer'] ??
                      data['contestantAnswer'] ??
                      data['answer'] ??
                      (isUnanswered ? 'No answer' : ''))
                  .toString();

              items.add({
                'qIndex': qIdx,
                'qNumber': qNum,
                'questionText': questionText,
                'contestantAnswer': contestantAnswer,
                'expectedAnswer': expectedAnswer,
                'isCheck': isCheck,
                'isWrong': isWrong,
                'isUnanswered': isUnanswered,
                'isApproved': isApproved,
                'isRejected': isRejected,
                'isPendingContest': isPendingContest,
                'contestStatus': contestStatus,
                'contestComment': (data['contestComment'] ??
                        data['quizmasterComment'] ??
                        data['rejectionReason'] ??
                        '')
                    .toString(),
              });
            }

            items.sort((a, b) =>
                (a['qIndex'] as int).compareTo(b['qIndex'] as int));

            final filteredItems = items.where((item) {
              if (filter == 'correct') return item['isCheck'] == true;
              if (filter == 'wrong') return item['isWrong'] == true;
              if (filter == 'unanswered') return item['isUnanswered'] == true;
              if (filter == 'contested') {
                return item['isApproved'] == true ||
                    item['isRejected'] == true ||
                    item['isPendingContest'] == true;
              }
              return true;
            }).toList();

            final int correctTotal =
                items.where((i) => i['isCheck'] == true).length;
            final int wrongTotal =
                items.where((i) => i['isWrong'] == true).length;
            final int unansweredTotal =
                items.where((i) => i['isUnanswered'] == true).length;
            final int contestedTotal = items.where((i) =>
                i['isApproved'] == true ||
                i['isRejected'] == true ||
                i['isPendingContest'] == true).length;

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 580,
                  maxHeight: 680,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: primaryBlue.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              isTeam
                                  ? Icons.groups_rounded
                                  : Icons.person_rounded,
                              color: primaryBlue,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: darkBlue,
                                  ),
                                ),
                                if (isTeam && teamMembers.isNotEmpty)
                                  Text(
                                    'Members: ${teamMembers.join(', ')}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.pop(dialogCtx),
                            tooltip: 'Close',
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Filter chips row
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildDialogFilterChip(
                              label: 'ALL (${items.length})',
                              isSelected: filter == 'all',
                              color: primaryBlue,
                              onTap: () =>
                                  setDialogState(() => filter = 'all'),
                            ),
                            const SizedBox(width: 6),
                            _buildDialogFilterChip(
                              label: '✔ CHECK ($correctTotal)',
                              isSelected: filter == 'correct',
                              color: Colors.green,
                              onTap: () =>
                                  setDialogState(() => filter = 'correct'),
                            ),
                            const SizedBox(width: 6),
                            _buildDialogFilterChip(
                              label: '✖ WRONG ($wrongTotal)',
                              isSelected: filter == 'wrong',
                              color: Colors.red,
                              onTap: () =>
                                  setDialogState(() => filter = 'wrong'),
                            ),
                            const SizedBox(width: 6),
                            if (unansweredTotal > 0) ...[
                              _buildDialogFilterChip(
                                label: '? UNANSWERED ($unansweredTotal)',
                                isSelected: filter == 'unanswered',
                                color: Colors.orange,
                                onTap: () => setDialogState(
                                    () => filter = 'unanswered'),
                              ),
                              const SizedBox(width: 6),
                            ],
                            if (contestedTotal > 0) ...[
                              _buildDialogFilterChip(
                                label: '⚡ CONTESTS ($contestedTotal)',
                                isSelected: filter == 'contested',
                                color: Colors.purple,
                                onTap: () => setDialogState(
                                    () => filter = 'contested'),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 10),

                      // Answer items list
                      Expanded(
                        child: filteredItems.isEmpty
                            ? Center(
                                child: Text(
                                  'No answers found for filter "$filter".',
                                  style: const TextStyle(
                                    color: Colors.black54,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: filteredItems.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, idx) {
                                  final item = filteredItems[idx];
                                  final qNum = item['qNumber'];
                                  final isCheck = item['isCheck'] == true;
                                  final isApproved = item['isApproved'] == true;
                                  final isRejected = item['isRejected'] == true;
                                  final isPending =
                                      item['isPendingContest'] == true;
                                  final isUnanswered =
                                      item['isUnanswered'] == true;
                                  final qText = item['questionText'] as String;
                                  final userAns =
                                      item['contestantAnswer'] as String;
                                  final correctAns =
                                      item['expectedAnswer'] as String;
                                  final comment =
                                      item['contestComment'] as String;

                                  final Color statusColor = isCheck
                                      ? Colors.green
                                      : (isPending
                                          ? Colors.orange
                                          : (isUnanswered
                                              ? Colors.grey
                                              : Colors.red));

                                  final String badgeLabel = isApproved
                                      ? '✔ CHECK (CONTEST APPROVED)'
                                      : (isRejected
                                          ? '✖ WRONG (CONTEST REJECTED)'
                                          : (isPending
                                              ? '⚡ CONTEST PENDING'
                                              : (isCheck
                                                  ? '✔ CORRECT'
                                                  : (isUnanswered
                                                      ? '? UNANSWERED'
                                                      : '✖ WRONG'))));

                                  return Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color:
                                          statusColor.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color:
                                            statusColor.withValues(alpha: 0.25),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 7,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: primaryBlue
                                                    .withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                'Q$qNum',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: primaryBlue,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 7,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: statusColor
                                                    .withValues(alpha: 0.12),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                badgeLabel,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  color: statusColor,
                                                  fontSize: 10,
                                                  letterSpacing: 0.3,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (qText.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            qText,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12.5,
                                              color: darkBlue,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 6),
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Answer: ',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: Colors.black54,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                userAns.isNotEmpty
                                                    ? userAns
                                                    : '(No answer)',
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: isCheck
                                                      ? Colors.green.shade800
                                                      : Colors.red.shade800,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (correctAns.isNotEmpty &&
                                            !isCheck) ...[
                                          const SizedBox(height: 2),
                                          Row(
                                            crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Correct: ',
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  color: Colors.black54,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Expanded(
                                                child: Text(
                                                  correctAns,
                                                  style: const TextStyle(
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.bold,
                                                    color: Color(0xFF15803D),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                        if (isRejected &&
                                            comment.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.red.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: Colors.red.shade200,
                                              ),
                                            ),
                                            child: Text(
                                              'Rejection Reason: $comment',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.red.shade900,
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                },
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
    );
  }

  Widget _buildDialogFilterChip({
    required String label,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.3),
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: isSelected ? Colors.white : color,
          ),
        ),
      ),
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
      stream: quizRef.collection('join_requests').snapshots(),
      builder: (context, requestsSnapshot) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: quizRef.collection('scores').snapshots(),
          builder: (context, scoresSnapshot) {
            if (scoresSnapshot.hasError || requestsSnapshot.hasError) {
              return const Text('Unable to load current standings.');
            }
            if ((scoresSnapshot.connectionState == ConnectionState.waiting &&
                    !scoresSnapshot.hasData) &&
                (requestsSnapshot.connectionState == ConnectionState.waiting &&
                    !requestsSnapshot.hasData)) {
              return const Center(child: CircularProgressIndicator());
            }

            final requestDocs = requestsSnapshot.data?.docs ?? [];
            final scoreDocs = scoresSnapshot.data?.docs ?? [];

            _syncOrFetchLevelScores(
              widget.quizCode,
              scoreDocs,
              quizData: _quizData,
            );

            final Map<String, Map<String, dynamic>> joinByUid = {};
            final Map<String, Map<String, dynamic>> joinByName = {};

            for (final doc in requestDocs) {
              final d = doc.data();
              joinByUid[doc.id] = d;
              final dName = (d['displayName'] ??
                      d['name'] ??
                      d['teamName'] ??
                      d['realName'] ??
                      d['fullName'] ??
                      '')
                  .toString()
                  .trim()
                  .toLowerCase();
              if (dName.isNotEmpty) {
                joinByName[dName] = d;
              }
            }

            final Map<String, Map<String, dynamic>> participants = {};

            // 1. Process join requests (approved or participating)
            for (final doc in requestDocs) {
              final d = doc.data();
              final status =
                  (d['status'] ?? '').toString().trim().toLowerCase();
              if (status == 'rejected' || status == 'pending') continue;
              participants[doc.id] = {
                'id': doc.id,
                'jData': d,
                'sData': <String, dynamic>{},
              };
            }

            // 2. Process score docs
            for (final doc in scoreDocs) {
              final s = doc.data();
              if (participants.containsKey(doc.id)) {
                participants[doc.id]!['sData'] = s;
              } else {
                final sName = (s['name'] ??
                        s['displayName'] ??
                        s['contestantName'] ??
                        '')
                    .toString()
                    .trim()
                    .toLowerCase();
                final matchedJoin =
                    sName.isNotEmpty ? joinByName[sName] : null;
                participants[doc.id] = {
                  'id': doc.id,
                  'jData': matchedJoin ?? <String, dynamic>{},
                  'sData': s,
                };
              }
            }

            final rows = <Map<String, dynamic>>[];

            for (final entry in participants.values) {
              final id = entry['id'] as String;
              final jData = (entry['jData'] as Map<String, dynamic>?) ?? {};
              final sData = (entry['sData'] as Map<String, dynamic>?) ?? {};

              final rawTeam =
                  (sData['teamName'] ?? jData['teamName'] ?? '')
                      .toString()
                      .trim();
              final contestantType =
                  (sData['contestantType'] ?? jData['contestantType'] ?? '')
                      .toString()
                      .trim()
                      .toLowerCase();
              final bool isTeam =
                  sData['isTeam'] == true ||
                  contestantType == 'team' ||
                  jData['isTeam'] == true ||
                  rawTeam.isNotEmpty;

              final String personalFullName = (jData['realName'] ??
                      jData['fullName'] ??
                      jData['displayName'] ??
                      jData['name'] ??
                      sData['realName'] ??
                      sData['fullName'] ??
                      sData['displayName'] ??
                      sData['name'] ??
                      sData['contestantName'] ??
                      id)
                  .toString()
                  .trim();

              final String finalTeamName =
                  rawTeam.isNotEmpty
                      ? rawTeam
                      : (isTeam ? personalFullName : '');

              final String displayName =
                  isTeam
                      ? (finalTeamName.isNotEmpty
                          ? finalTeamName
                          : personalFullName)
                      : (personalFullName.isNotEmpty
                          ? personalFullName
                          : 'Contestant');

              final rawMembers =
                  sData['teamMembers'] ??
                  sData['members'] ??
                  jData['teamMembers'] ??
                  jData['members'];
              final List<String> teamMembers = [];
              if (rawMembers is List) {
                for (final m in rawMembers) {
                  final s =
                      m is Map
                          ? (m['name'] ?? m['displayName'] ?? '')
                              .toString()
                              .trim()
                          : m.toString().trim();
                  if (s.isNotEmpty && !teamMembers.contains(s)) {
                    teamMembers.add(s);
                  }
                }
              }

              final score = _getContestantEffectiveScore(
                sData,
                jData: jData,
                uid: id,
              );

              // Auto-heal inflated or outdated score in Firestore score document
              final storedScore = _asInt(sData['score']);
              if (storedScore != null && storedScore != score) {
                quizRef.collection('scores').doc(id).set({
                  'score': score,
                  'totalScore': score,
                }, SetOptions(merge: true)).catchError((_) {});
              }

              final bool isEliminated =
                  sData['eliminated'] == true ||
                  sData['isEliminated'] == true ||
                  (sData['status'] ?? '').toString().trim().toLowerCase() == 'eliminated' ||
                  sData['eliminationConfirmed'] == true ||
                  jData['eliminated'] == true ||
                  jData['isEliminated'] == true ||
                  (jData['status'] ?? '').toString().trim().toLowerCase() == 'eliminated' ||
                  jData['eliminationConfirmed'] == true;

              rows.add({
                'id': id,
                'name': displayName,
                'isTeam': isTeam,
                'teamName': finalTeamName,
                'personalFullName': personalFullName,
                'teamMembers': teamMembers,
                'score': score,
                'isEliminated': isEliminated,
              });
            }

            rows.sort((a, b) {
              final scoreComp = (b['score'] as int).compareTo(
                a['score'] as int,
              );
              if (scoreComp != 0) return scoreComp;
              return (a['name'] as String).toLowerCase().compareTo(
                (b['name'] as String).toLowerCase(),
              );
            });

            if (rows.isEmpty) {
              return const Text(
                'Standings will appear when contestant scores are recorded.',
              );
            }

            // Assign ranks (equal score = equal rank)
            for (int i = 0; i < rows.length; i++) {
              if (i > 0 && rows[i]['score'] == rows[i - 1]['score']) {
                rows[i]['rank'] = rows[i - 1]['rank'];
              } else {
                rows[i]['rank'] = i + 1;
              }
            }

            // Check if Question 2 has submissions/answers or if past Question 1:
            // Rank numbers only appear after Question 2 submissions and score updates.
            bool hasQuestion2Submission = false;
            for (final doc in scoreDocs) {
              final sData = doc.data();
              final lq = _asInt(sData['lastQuestion']) ?? 0;
              if (lq >= 2) {
                hasQuestion2Submission = true;
                break;
              }
            }

            final bool hasAnyScore = rows.any((r) => (r['score'] as int) > 0);
            bool showRankNumbers = false;

            if (hasAnyScore) {
              if (_currentLevel > 1 || _currentQuestion >= 2) {
                showRankNumbers = true;
              } else if (hasQuestion2Submission) {
                showRankNumbers = true;
              } else if (_currentQuestion >= 1 &&
                  (_status == 'contest_review' ||
                      _status == 'level_pause' ||
                      _status == 'review' ||
                      _isFinished)) {
                showRankNumbers = true;
              }
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!showRankNumbers)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 15,
                          color: Color(0xFF64748B),
                        ),
                        SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            'Rankings will be declared after Question 2 submissions.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                for (int i = 0; i < rows.length; i++)
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    leading: CircleAvatar(
                      radius: 15,
                      backgroundColor: rows[i]['isEliminated'] == true
                          ? const Color(0xFFFEE2E2)
                          : (showRankNumbers
                              ? Colors.blue.shade50
                              : const Color(0xFFF1F5F9)),
                      child: Text(
                        showRankNumbers ? '${rows[i]['rank']}' : '-',
                        style: TextStyle(
                          color: rows[i]['isEliminated'] == true
                              ? const Color(0xFFDC2626)
                              : (showRankNumbers
                                  ? primaryBlue
                                  : const Color(0xFF94A3B8)),
                          fontWeight: FontWeight.bold,
                          fontSize: showRankNumbers ? 12 : 14,
                        ),
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            rows[i]['name'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: rows[i]['isEliminated'] == true
                                  ? const Color(0xFF991B1B)
                                  : darkBlue,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (rows[i]['isEliminated'] == true) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFFFCA5A5),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.cancel_rounded,
                                  size: 11,
                                  color: Color(0xFFDC2626),
                                ),
                                SizedBox(width: 3),
                                Text(
                                  'ELIMINATED',
                                  style: TextStyle(
                                    color: Color(0xFFDC2626),
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        if (rows[i]['isTeam'] == true)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: primaryBlue.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: primaryBlue.withValues(alpha: 0.25),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.groups_rounded,
                                  size: 11,
                                  color: primaryBlue,
                                ),
                                SizedBox(width: 3),
                                Text(
                                  'TEAM',
                                  style: TextStyle(
                                    color: primaryBlue,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(
                                alpha: 0.10,
                              ),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFF10B981).withValues(
                                  alpha: 0.25,
                                ),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.person_rounded,
                                  size: 11,
                                  color: Color(0xFF059669),
                                ),
                                SizedBox(width: 3),
                                Text(
                                  'SOLO',
                                  style: TextStyle(
                                    color: Color(0xFF059669),
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if ((rows[i]['teamMembers'] as List<String>?)?.isNotEmpty ?? false)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Members: ${(rows[i]['teamMembers'] as List<String>).join(', ')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: Color(0xFF5B7A9C),
                              ),
                            ),
                          ),
                        if (rows[i]['isEliminated'] == true)
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Text(
                              'Eliminated from quiz',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFFDC2626),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    trailing: Builder(
                      builder: (context) {
                        final int sc = (rows[i]['score'] as int?) ?? 0;
                        final String label = sc == 0
                            ? '0'
                            : (sc == 1 ? '1 pt' : '$sc pts');
                        return Text(
                          label,
                          style: TextStyle(
                            color: rows[i]['isEliminated'] == true
                                ? const Color(0xFFDC2626)
                                : darkBlue,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
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
    final bool isWaiting = _status == 'waiting' ||
        _status == 'tie_breaker_preparation' ||
        _status == 'tie_breaker_invite';
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
                        if (_isTieBreakerActive) ...[
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF9A3412), Color(0xFFEA580C)],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.orange.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.bolt_rounded,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '⚡ TIE BREAKER SHOWDOWN ACTIVE',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _tieBreakerBroken &&
                                                _tieBreakerLeadingName != null
                                            ? 'Leader: $_tieBreakerLeadingName ($_tieBreakerLeadingScore PTS) • Tie broken!'
                                            : 'Sudden-Death Round: ${(_quizData?['tieBreakerContestantNames'] as List?)?.join(' vs ') ?? 'Tied Contestants'}',
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.9,
                                          ),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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

                        if (isPaused && !_isFinished)
                          const SizedBox(height: 20),

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
                                        ? (_countdown > 0
                                              ? '$_countdown'
                                              : 'GO!')
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
                            final currentLevel = _getLevel(_currentQuestion);
                            final lastQuestionOfCurrentLevel =
                                _getLastQuestionIndexForLevel(currentLevel) ==
                                _currentQuestion;
                            final isLastQuestionOrLevelDone =
                                lastQuestionOfCurrentLevel ||
                                (_totalQuestions > 0 &&
                                    _currentQuestion >= _totalQuestions - 1);

                            // When tie breaker is active and tie is broken (or questions done),
                            // do not show the green END QUESTION button.
                            // The red END TIE BREAKER button is the only action needed to finalize.
                            final bool hideTieBreakerMainButton =
                                _isTieBreakerActive &&
                                    (_tieBreakerBroken || isLastQuestionOrLevelDone);

                            final compact = constraints.maxWidth < 560;
                            final columns = compact ? 2 : (hideTieBreakerMainButton ? 3 : 4);
                            const gap = 8.0;
                            final buttonWidth =
                                (constraints.maxWidth - gap * (columns - 1)) /
                                columns;

                            return Wrap(
                              spacing: gap,
                              runSpacing: gap,
                              children: [
                                if (!hideTieBreakerMainButton)
                                  SizedBox(
                                    width: buttonWidth,
                                    child: _compactControlButton(
                                      icon: _isTieBreakerActive
                                          ? (_currentQuestion == 0 &&
                                                  (isWaiting ||
                                                      _status ==
                                                          'tie_breaker_invite' ||
                                                      _status ==
                                                          'tie_breaker_preparation')
                                              ? Icons.play_arrow_rounded
                                              : Icons.skip_next_rounded)
                                          : (_currentQuestion == 0 &&
                                                  isWaiting &&
                                                  _quizData?['startedAt'] == null)
                                              ? Icons.play_arrow_rounded
                                              : Icons.skip_next_rounded,
                                      label: _isTieBreakerActive
                                          ? (_currentQuestion == 0 &&
                                                  (isWaiting ||
                                                      _status ==
                                                          'tie_breaker_invite' ||
                                                      _status ==
                                                          'tie_breaker_preparation')
                                              ? 'START QUESTION'
                                              : 'NEXT QUESTION')
                                          : _levelPreparedForStart
                                              ? 'START LEVEL $_currentLevel'
                                              : (_currentQuestion == 0 &&
                                                      isWaiting &&
                                                      _quizData?['startedAt'] ==
                                                          null)
                                                  ? 'START'
                                                  : 'NEXT QUESTION',
                                      color: _isTieBreakerActive
                                          ? (_currentQuestion == 0 &&
                                                  (isWaiting ||
                                                      _status ==
                                                          'tie_breaker_invite' ||
                                                      _status ==
                                                          'tie_breaker_preparation')
                                              ? Colors.green
                                              : primaryBlue)
                                          : _levelPreparedForStart ||
                                                  (_currentQuestion == 0 &&
                                                      isWaiting &&
                                                      _quizData?['startedAt'] ==
                                                          null)
                                              ? Colors.green
                                              : isLastQuestionOrLevelDone
                                                  ? Colors.grey
                                                  : primaryBlue,
                                      enabled: !_isFinished &&
                                          !_isAdvancingQuestion &&
                                          !_startingFromMainButton &&
                                          (_isTieBreakerActive
                                              ? ((_currentQuestion == 0 &&
                                                      (isWaiting ||
                                                          _status ==
                                                              'tie_breaker_invite' ||
                                                          _status ==
                                                              'tie_breaker_preparation'))
                                                  ? true
                                                  : (!isWaiting &&
                                                      !isCountdown &&
                                                      !_contestReviewActive &&
                                                      !_isManuallyPaused))
                                              : (_levelPreparedForStart ||
                                                  ((_currentQuestion == 0 &&
                                                          isWaiting &&
                                                          _quizData?['startedAt'] ==
                                                              null)
                                                      ? isWaiting
                                                      : (!isLastQuestionOrLevelDone &&
                                                          !isWaiting &&
                                                          !isCountdown &&
                                                          !_contestReviewActive &&
                                                          !_isManuallyPaused)))),
                                      // One primary control starts the next question or level.
                                      onTap: _isTieBreakerActive
                                          ? ((_currentQuestion == 0 &&
                                                  (isWaiting ||
                                                      _status ==
                                                          'tie_breaker_invite' ||
                                                      _status ==
                                                          'tie_breaker_preparation'))
                                              ? _startInitialCountdownFromButton
                                              : _confirmNextQuestion)
                                          : _levelPreparedForStart
                                              ? () async {
                                                  final targetQuestion =
                                                      _pendingQuestionIndex ??
                                                          _currentQuestion;
                                                  final targetLevel =
                                                      _pendingLevel ??
                                                          _currentLevel;
                                                  setState(
                                                    () => _levelPreparedForStart =
                                                        false,
                                                  );
                                                  await _startQuestionCountdown(
                                                    questionIndex: targetQuestion,
                                                    level: targetLevel,
                                                  );
                                                }
                                              : (_currentQuestion == 0 &&
                                                      isWaiting &&
                                                      _quizData?['startedAt'] ==
                                                          null)
                                                  ? _startInitialCountdownFromButton
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
                                  width: (compact && hideTieBreakerMainButton)
                                      ? constraints.maxWidth
                                      : buttonWidth,
                                  child: _compactControlButton(
                                    icon: Icons.flag_rounded,
                                    label: _isTieBreakerActive
                                        ? 'END TIE BREAKER'
                                        : 'END LEVEL',
                                    color: Colors.red,
                                    enabled: !_isFinished && !_isFinishingQuiz,
                                    onTap: _isTieBreakerActive
                                        ? _endTieBreakerAndOpenFinalTally
                                        : _confirmFinishQuiz,
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
                                      await QuizMasterNavPersistence.savePage('dashboard');
                                      if (!context.mounted) return;
                                      Navigator.of(context).pushAndRemoveUntil(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const QuizMasterDashboard(
                                            restoreLastPage: false,
                                          ),
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
