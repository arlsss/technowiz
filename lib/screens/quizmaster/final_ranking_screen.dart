import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'quizmaster_dashboard.dart';
import 'quizmaster_theme.dart';

class FinalRankingScreen extends StatefulWidget {
  final String quizCode;
  final int level;
  final bool isFinal;
  final Future<void> Function()? onStartNextLevel;

  const FinalRankingScreen({
    super.key,
    required this.quizCode,
    this.level = 1,
    this.isFinal = false,
    this.onStartNextLevel,
  });

  @override
  State<FinalRankingScreen> createState() => _FinalRankingScreenState();
}

class _FinalRankingScreenState extends State<FinalRankingScreen> {
  String get quizCode => widget.quizCode;
  int get level => widget.level;
  bool get isFinal => widget.isFinal;
  Future<void> Function()? get onStartNextLevel => widget.onStartNextLevel;

  late final DocumentReference<Map<String, dynamic>> _sessionRef;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _sessionStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _scoresStream;

  final Map<String, int> _userResponseTimes = {};
  final Map<String, int> _lockedRankOrder = {};
  bool _isLoadingResponseTimes = false;

  bool _isSyncingRanks = false;
  bool _pendingSync = false;
  final Map<String, int> _lastSyncedRanks = {};
  int? _lastSyncedLevel;

  void _fetchResponseTimesIfNeeded(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final missingUids = docs
        .map((d) => d.id)
        .where((uid) => !_userResponseTimes.containsKey(uid))
        .toList();

    if (missingUids.isEmpty || _isLoadingResponseTimes) return;

    _isLoadingResponseTimes = true;
    Future.microtask(() async {
      try {
        final Map<String, int> fetchedTimes = {};
        for (final uid in missingUids) {
          try {
            final snap = await _sessionRef
                .collection('answers')
                .doc(uid)
                .collection('responses')
                .get();

            int latestMs = 0;

            for (final r in snap.docs) {
              final rData = r.data();
              final rawLevel = rData['level'];
              final int? rLevel = rawLevel is num
                  ? rawLevel.toInt()
                  : int.tryParse(rawLevel?.toString() ?? '');
              if (rLevel != null && rLevel != widget.level) continue;

              final answeredAt = rData['answeredAt'];
              if (answeredAt is Timestamp) {
                final ms = answeredAt.millisecondsSinceEpoch;
                if (ms > latestMs) latestMs = ms;
              }
            }

            if (latestMs > 0) {
              fetchedTimes[uid] = latestMs;
            }
          } catch (_) {}
        }

        if (mounted && fetchedTimes.isNotEmpty) {
          setState(() {
            _userResponseTimes.addAll(fetchedTimes);
          });
        }
      } finally {
        _isLoadingResponseTimes = false;
      }
    });
  }

  int _getSubmissionTime(String uid, Map<String, dynamic> data) {
    if (_userResponseTimes.containsKey(uid) && _userResponseTimes[uid]! > 0) {
      return _userResponseTimes[uid]!;
    }
    final raw =
        data['updatedAt'] ?? data['answeredAt'] ?? data['lastAnsweredAt'];
    if (raw is Timestamp) return raw.millisecondsSinceEpoch;
    if (raw is num) return raw.toInt();
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed.millisecondsSinceEpoch;
      return int.tryParse(raw) ?? 0;
    }
    return 0;
  }

  @override
  void initState() {
    super.initState();
    _saveCurrentPage();
    _sessionRef = FirebaseFirestore.instance
        .collection('quiz_sessions')
        .doc(widget.quizCode);
    _sessionStream = _sessionRef.snapshots();
    _scoresStream = _sessionRef.collection('scores').snapshots();
  }

  @override
  void didUpdateWidget(covariant FinalRankingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.level != widget.level || oldWidget.quizCode != widget.quizCode) {
      _lockedRankOrder.clear();
      _userResponseTimes.clear();
    }
  }

  Future<void> _saveCurrentPage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('technowiz_quizmaster_last_page', 'ranking');
      await prefs.setString(
        'technowiz_quizmaster_current_quiz_code',
        widget.quizCode,
      );
      await prefs.setInt('technowiz_quizmaster_ranking_level', widget.level);
      await prefs.setBool(
        'technowiz_quizmaster_ranking_is_final',
        widget.isFinal,
      );
    } catch (_) {}
  }

  static const Color primaryBlue = Color(0xFF1565D8);
  static const Color darkBlue = Color(0xFF0B2E6B);
  static const Color lightBlue = Color(0xFFEAF3FF);

  // ============================================================
  // LABELS
  // ============================================================

  String get _stageLabel => isFinal ? 'the final round' : 'Level $level';

  String get _appBarTitle => isFinal ? 'Winners Result' : 'Level $level Result';

  String get _listTitle => isFinal ? 'FINAL RANKING' : 'RANKING';

  String get _footerText => isFinal
      ? 'Quiz Master • Final Results'
      : 'Quiz Master • Level $level Result';

  // ============================================================
  // HELPERS
  // ============================================================

  int _scoreOf(Map<String, dynamic> data) =>
      int.tryParse(data['score']?.toString() ?? '') ?? 0;

  bool _isEliminated(Map<String, dynamic> data) =>
      data['eliminated'] == true ||
      data['status']?.toString().toLowerCase() == 'eliminated';

  bool _isProceededForCurrentLevel(Map<String, dynamic> data) {
    final isProceeding =
        data['proceeded'] == true ||
        data['status']?.toString().toLowerCase() == 'proceeding';
    if (!isProceeding) return false;

    final rawFromLevel = data['proceededFromLevel'];
    final fromLevel = rawFromLevel is num
        ? rawFromLevel.toInt()
        : int.tryParse(rawFromLevel?.toString() ?? '');

    return fromLevel == level;
  }

  // Kung ang contestant na-eliminate sa una nga level (e.g. Level 1),
  // dili na dapat makita ilang ngalan sa sunod nga level (e.g. Level 2, 3...)
  bool _wasEliminatedInPreviousLevel(Map<String, dynamic> data) {
    if (widget.level <= 1) return false;

    final isElim = _isEliminated(data);
    if (!isElim) return false;

    // 1. Tan-awa ang explicit elimination level markers
    final rawLevel = data['eliminatedLevel'] ??
        data['eliminatedAfterLevel'] ??
        data['decisionLevel'];
    final int? elimLevel = rawLevel is num
        ? rawLevel.toInt()
        : int.tryParse(rawLevel?.toString() ?? '');

    if (elimLevel != null) {
      // Na-eliminate sa mas sayo nga level: ayaw na i-apil sa sunod nga level
      return elimLevel < widget.level;
    }

    // 2. Kon walay elimLevel, tan-awa kon nakapadayon ba sa karon nga level
    final rawProceededFrom = data['proceededFromLevel'];
    final int? proceededFrom = rawProceededFrom is num
        ? rawProceededFrom.toInt()
        : int.tryParse(rawProceededFrom?.toString() ?? '');

    final rawNext = data['nextLevel'];
    final int? next = rawNext is num
        ? rawNext.toInt()
        : int.tryParse(rawNext?.toString() ?? '');

    if (proceededFrom != (widget.level - 1) && (next == null || next < widget.level)) {
      return true;
    }

    return false;
  }

  // Tagsa-tagsa ka rank (1, 2, 3...) base sa fixed sorted order.
  // Walay mag-share og parehas nga rank ug dili mag-ilis-ilis og ranking.
  List<int> _computeRanks(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> rankingsDocs,
  ) {
    final ranks = <int>[];
    for (int i = 0; i < rankingsDocs.length; i++) {
      ranks.add(i + 1);
    }
    return ranks;
  }

  // Awtomatikong i-sync ang accurate ranking sa Firestore aron parehas
  // gyud ang rank nga makita sa quizmaster ug sa contestant side.
  void _syncRankingsToFirestore(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> rankings,
    List<int> ranks,
  ) {
    if (rankings.isEmpty || ranks.isEmpty) return;

    bool hasChanges = _lastSyncedLevel != level;
    for (int i = 0; i < rankings.length; i++) {
      if (_lastSyncedRanks[rankings[i].id] != ranks[i]) {
        hasChanges = true;
        break;
      }
    }

    if (!hasChanges) return;

    if (_isSyncingRanks) {
      _pendingSync = true;
      return;
    }

    _isSyncingRanks = true;
    _lastSyncedLevel = level;

    Future.microtask(() async {
      try {
        final db = FirebaseFirestore.instance;
        final sessionRef = db.collection('quiz_sessions').doc(quizCode);
        final batch = db.batch();

        final officialRanksMap = <String, int>{};

        for (int i = 0; i < rankings.length; i++) {
          final contestantId = rankings[i].id;
          final int rank = ranks[i];
          _lastSyncedRanks[contestantId] = rank;
          officialRanksMap[contestantId] = rank;

          batch.set(
            sessionRef.collection('scores').doc(contestantId),
            {
              'rank': rank,
              'levelRank': rank,
              'currentRank': rank,
              'rankLevel': level,
              'rankUpdatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );

          batch.set(
            sessionRef.collection('join_requests').doc(contestantId),
            {
              'rank': rank,
              'levelRank': rank,
              'currentRank': rank,
              'rankLevel': level,
            },
            SetOptions(merge: true),
          );
        }

        batch.set(
          sessionRef,
          {
            'officialRanks': officialRanksMap,
            'rankingUpdatedLevel': level,
            'rankingUpdatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        await batch.commit();
      } catch (e) {
        debugPrint('SYNC RANKINGS ERROR: $e');
      } finally {
        _isSyncingRanks = false;
        if (_pendingSync) {
          _pendingSync = false;
          _syncRankingsToFirestore(rankings, ranks);
        }
      }
    });
  }

  // ============================================================
  // START NEXT LEVEL -> OPEN CONTESTANT READINESS DIRECTLY
  // ============================================================

  Future<void> _startNextLevel(BuildContext context) async {
    if (isFinal) return;

    // Siguradoha nga ang tanang contestant nga gitugotan nga maka-proceed
    // ma-sync sa Firestore isip approved ug dili eliminated sa join_requests,
    // ug i-publish ang elimination aron makapadayon ang tanang qualified contestants
    try {
      final db = FirebaseFirestore.instance;
      final sessionRef = db.collection('quiz_sessions').doc(quizCode);
      final scores = await sessionRef.collection('scores').get();
      final eliminatedIds = <String>{
        for (final d in scores.docs)
          if (_isEliminated(d.data())) d.id,
      };

      final requests = await sessionRef.collection('join_requests').get();
      final batch = db.batch();
      bool hasUpdates = false;

      for (final r in requests.docs) {
        final rStatus =
            (r.data()['status'] ?? '').toString().trim().toLowerCase();
        if (rStatus == 'left' ||
            rStatus == 'rejected' ||
            rStatus == 'declined' ||
            r.data()['leftQuiz'] == true) {
          continue;
        }

        final assignedRank = _lockedRankOrder[r.id];

        if (!eliminatedIds.contains(r.id)) {
          hasUpdates = true;
          final rData = r.data();
          final rawReadyForLevel = rData['readyForLevel'];
          final readyForLevel = rawReadyForLevel is num
              ? rawReadyForLevel.toInt()
              : int.tryParse(rawReadyForLevel?.toString() ?? '');
          final bool alreadyProceeded =
              readyForLevel != null && readyForLevel >= level + 1;

          final updateData = <String, dynamic>{
            'status': 'approved',
            'eliminated': false,
            'isEliminated': false,
            'eliminationConfirmed': false,
          };

          if (assignedRank != null) {
            updateData['rank'] = assignedRank;
            updateData['levelRank'] = assignedRank;
            updateData['currentRank'] = assignedRank;
            updateData['rankLevel'] = level;
          }

          // Kung ang contestant WALA pa naka-click og PROCEED, i-publish ang decision
          // aron makita nila ang decision screen. Kung NAKA-CLICK na og PROCEED,
          // AYAW na i-overwrite og 'contestantDecision' aron dili sila mobalik sa proceed screen.
          if (!alreadyProceeded) {
            updateData['contestantDecision'] = 'proceeding';
            updateData['decisionLevel'] = level;
            updateData['nextLevel'] = level + 1;
            updateData['decisionMessage'] =
                'Congratulations! You will be proceeding to Level ${level + 1}!';
            updateData['decisionAt'] = FieldValue.serverTimestamp();
          }

          batch.set(r.reference, updateData, SetOptions(merge: true));

          final scoreUpdate = <String, dynamic>{
            'status': 'proceeding',
            'proceeded': true,
            'eliminated': false,
            'isEliminated': false,
            'proceededFromLevel': level,
            'nextLevel': level + 1,
            'proceededAt': FieldValue.serverTimestamp(),
          };
          if (assignedRank != null) {
            scoreUpdate['rank'] = assignedRank;
            scoreUpdate['levelRank'] = assignedRank;
            scoreUpdate['currentRank'] = assignedRank;
            scoreUpdate['rankLevel'] = level;
          }
          batch.set(sessionRef.collection('scores').doc(r.id), scoreUpdate, SetOptions(merge: true));
        } else {
          hasUpdates = true;
          final elimData = <String, dynamic>{
            'status': 'eliminated',
            'eliminated': true,
            'isEliminated': true,
            'eliminatedLevel': level,
            'decisionLevel': level,
          };
          if (assignedRank != null) {
            elimData['rank'] = assignedRank;
            elimData['levelRank'] = assignedRank;
            elimData['currentRank'] = assignedRank;
            elimData['rankLevel'] = level;
          }
          batch.set(r.reference, elimData, SetOptions(merge: true));

          final scoreElimUpdate = <String, dynamic>{
            'status': 'eliminated',
            'eliminated': true,
            'isEliminated': true,
            'eliminatedLevel': level,
            'eliminatedAt': FieldValue.serverTimestamp(),
          };
          if (assignedRank != null) {
            scoreElimUpdate['rank'] = assignedRank;
            scoreElimUpdate['levelRank'] = assignedRank;
            scoreElimUpdate['currentRank'] = assignedRank;
            scoreElimUpdate['rankLevel'] = level;
          }
          batch.set(sessionRef.collection('scores').doc(r.id), scoreElimUpdate, SetOptions(merge: true));
        }
      }

      final nextLevel = level + 1;
      final officialRanksMap = <String, int>{
        for (final entry in _lockedRankOrder.entries) entry.key: entry.value,
      };
      batch.set(sessionRef, {
        if (officialRanksMap.isNotEmpty) 'officialRanks': officialRanksMap,
        'eliminationPublished': true,
        'eliminationPublishedLevel': level,
        'eliminationPublishedAt': FieldValue.serverTimestamp(),
        'currentLevel': nextLevel,
        'level': nextLevel,
        'preparedLevel': nextLevel,
        'status': 'waiting',
        'eventStatus': 'waiting_for_readiness',
        'readyCheckActive': false,
        'readyCheckType': 'level',
        'readyCheckTitle': 'Level $nextLevel is about to begin',
        'readyCheckMessage':
            'Please review Level $nextLevel instructions and get ready.',
      }, SetOptions(merge: true));
      hasUpdates = true;

      if (hasUpdates) {
        await batch.commit();
      }
    } catch (e) {
      debugPrint("SYNC PROCEEDING ON START NEXT LEVEL ERROR: $e");
    }

    // QuizControl owns the synchronized readiness/countdown flow. Return to it
    // and let its existing _startNextLevel method open Contestant Readiness.
    if (!mounted) return;
    final startNextLevel = onStartNextLevel;
    if (startNextLevel == null) {
      showQuizMasterTopNotification(
        context,
        'Unable to open the next-level readiness flow.',
        isError: true,
      );
      return;
    }

    await startNextLevel();
  }

  // ============================================================
  // ELIMINATE ONE CONTESTANT
  //
  // Makita dayon sa contestant: "Thank you for participating".
  // ============================================================

  Future<void> _eliminateContestant({
    required BuildContext context,
    required String contestantId,
    required String contestantName,
    required int score,
    required int rank,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Eliminate Contestant?',
          style: TextStyle(color: darkBlue, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to eliminate "$contestantName" '
          'from $_stageLabel?\n\n'
          'Current Score: $score points\n'
          'Current Rank: #$rank\n\n'
          'The contestant will see the result right away.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('ELIMINATE'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final db = FirebaseFirestore.instance;
      final sessionRef = db.collection('quiz_sessions').doc(quizCode);

      final batch = db.batch();

      batch.set(sessionRef.collection('scores').doc(contestantId), {
        'status': 'eliminated',
        'eliminated': true,
        'eliminatedLevel': level,
        'eliminatedAt': FieldValue.serverTimestamp(),
        'rankAtElimination': rank,
        'rank': rank,
        'levelRank': rank,
        'currentRank': rank,
        'rankLevel': level,
      }, SetOptions(merge: true));

      // Para mo-reset ang confirmation sa contestant ug i-mark isip eliminated
      batch.set(
        sessionRef.collection('join_requests').doc(contestantId),
        {
          'status': 'eliminated',
          'eliminationConfirmed': false,
          'eliminated': true,
          'isEliminated': true,
          'ready': false,
          'readyResponded': false,
          'contestantDecision': 'eliminated',
          'decisionLevel': level,
          'rank': rank,
          'levelRank': rank,
          'currentRank': rank,
          'rankLevel': level,
          'decisionMessage': 'Thank you for participating!',
          'decisionAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      batch.set(
        db
            .collection('quiz_reports')
            .doc(quizCode)
            .collection('levels')
            .doc('level_$level')
            .collection('contestants')
            .doc(contestantId),
        {
          'contestantId': contestantId,
          'name': contestantName,
          'score': score,
          'rank': rank,
          'level': level,
          'quizCode': quizCode,
          'status': 'eliminated',
          'eliminatedLevel': level,
          'eliminatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await batch.commit();

      if (!context.mounted) return;

      showQuizMasterTopNotification(
        context,
        '$contestantName has been eliminated from $_stageLabel.',
        isWarning: true,
      );
    } catch (e) {
      if (!context.mounted) return;

      showQuizMasterTopNotification(
        context,
        'Failed to eliminate contestant: $e',
        isError: true,
      );
    }
  }

  // ============================================================
  // MARK ONE CONTESTANT AS PROCEEDING
  // ============================================================

  Future<void> _proceedContestant({
    required BuildContext context,
    required String contestantId,
    required String contestantName,
    required int score,
    required int rank,
  }) async {
    try {
      final db = FirebaseFirestore.instance;
      final sessionRef = db.collection('quiz_sessions').doc(quizCode);
      final batch = db.batch();

      batch.set(sessionRef.collection('scores').doc(contestantId), {
        'status': 'proceeding',
        'proceeded': true,
        'eliminated': false,
        'isEliminated': false,
        'proceededFromLevel': level,
        'nextLevel': level + 1,
        'proceededAt': FieldValue.serverTimestamp(),
        'rankAtProceed': rank,
        'rank': rank,
        'levelRank': rank,
        'currentRank': rank,
        'rankLevel': level,
      }, SetOptions(merge: true));

      batch.set(
        sessionRef.collection('join_requests').doc(contestantId),
        {
          'status': 'approved',
          'eliminated': false,
          'isEliminated': false,
          'ready': false,
          'readyResponded': false,
          'contestantDecision': 'proceeding',
          'decisionLevel': level,
          'nextLevel': level + 1,
          'rank': rank,
          'levelRank': rank,
          'currentRank': rank,
          'rankLevel': level,
          'decisionMessage':
              'Congratulations! You will be proceeding to Level ${level + 1}!',
          'decisionAt': FieldValue.serverTimestamp(),
          'eliminationConfirmed': false,
        },
        SetOptions(merge: true),
      );

      await batch.commit();

      if (!context.mounted) return;

      showQuizMasterTopNotification(
        context,
        '$contestantName marked to proceed to Level ${level + 1}.',
        isSuccess: true,
      );
    } catch (e) {
      if (!context.mounted) return;

      showQuizMasterTopNotification(
        context,
        'Failed to mark contestant to proceed: $e',
        isError: true,
      );
    }
  }

  Future<void> _goBackToDashboard(BuildContext context) async {
    try {
      final db = FirebaseFirestore.instance;
      await db.collection('quiz_sessions').doc(quizCode).set({
        'status': 'finished',
        'isFinished': true,
        'timer': 0,
        'countdownActive': false,
        'readyCheckActive': false,
        'finishedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('technowiz_quizmaster_last_page', 'dashboard');
      await prefs.remove('technowiz_quizmaster_current_quiz_code');
      await prefs.remove('technowiz_quizmaster_result_mode');
    } catch (e) {
      debugPrint('Error saving dashboard state: $e');
    }
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const QuizMasterDashboard(),
      ),
      (route) => false,
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _sessionStream,
      builder: (context, sessionSnap) {
        final sessionData = sessionSnap.data?.data();
        final String sessionStatus =
            sessionData?['status']?.toString().trim().toLowerCase() ?? '';
        final bool effectiveIsFinal =
            isFinal ||
            sessionStatus == 'finished' ||
            sessionStatus == 'ended' ||
            sessionStatus == 'completed';

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: QuizMasterAppBar(
            title: effectiveIsFinal ? 'Winners Result' : _appBarTitle,
            subtitle: 'Code: $quizCode',
            badgeText: 'TECHNOWIZ • RANKING COMMAND',
            badgeIcon: Icons.emoji_events_rounded,
            showBackButton: false,
          ),
          body: QuizMasterCircuitBackground(
            child: SafeArea(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _scoresStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: primaryBlue),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(25),
                      child: Text(
                        'Unable to Load Ranking\n\n${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: darkBlue),
                      ),
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _emptyRanking(context, isFinalView: effectiveIsFinal);
                }

                // Dili i-apil sa sunod nga level ang mga contestant nga na-eliminate sa miaging mga level
                final activeDocs = snapshot.data!.docs.where((doc) {
                  if (effectiveIsFinal) return true;
                  return !_wasEliminatedInPreviousLevel(doc.data());
                }).toList();

                if (activeDocs.isEmpty) {
                  return _emptyRanking(context, isFinalView: effectiveIsFinal);
                }

                _fetchResponseTimesIfNeeded(activeDocs);

                // Sort sa client:
                // 1. Elimination state (kon final round)
                // 2. Score (descending - highest score first)
                // 3. Speed / Submission time (earlier timestamp = faster = higher rank)
                // 4. Locked order if already locked and times equal
                // 5. Stable deterministic fallback (by ID)
                final rankings = [...activeDocs]
                  ..sort((a, b) {
                    if (effectiveIsFinal) {
                      final aElim = _isEliminated(a.data());
                      final bElim = _isEliminated(b.data());
                      if (aElim != bElim) return aElim ? 1 : -1;
                    }
                    final scoreA = _scoreOf(a.data());
                    final scoreB = _scoreOf(b.data());
                    final byScore = scoreB.compareTo(scoreA);
                    if (byScore != 0) return byScore;

                    // Tie-breaker para sa parehas og score:
                    // Kinsay mas paspas ni-submit sa answer ang mas una / mas taas og rank
                    final timeA = _getSubmissionTime(a.id, a.data());
                    final timeB = _getSubmissionTime(b.id, b.data());
                    if (timeA > 0 && timeB > 0 && timeA != timeB) {
                      return timeA.compareTo(timeB); // Mas sayo ni-submit = mas paspas = una
                    } else if (timeA > 0 && timeB == 0) {
                      return -1;
                    } else if (timeB > 0 && timeA == 0) {
                      return 1;
                    }

                    // Siguradoha nga dili mag-ilis-ilis ang rank kung parehas og time o wala pay time:
                    final lockedA = _lockedRankOrder[a.id];
                    final lockedB = _lockedRankOrder[b.id];
                    if (lockedA != null && lockedB != null && lockedA != lockedB) {
                      return lockedA.compareTo(lockedB);
                    }

                    return a.id.compareTo(b.id);
                  });

                // I-lock ug i-update ang ranking order aron bisan pa'g ma-rebuild o mo-refresh ang stream,
                // magpabilin ang mao nga rank sa matag contestant
                for (int i = 0; i < rankings.length; i++) {
                  _lockedRankOrder[rankings[i].id] = i + 1;
                }

                final ranks = _computeRanks(rankings);
                _syncRankingsToFirestore(rankings, ranks);

                bool hasTopTie = false;
                if (effectiveIsFinal) {
                  final activeRanks = <int>[];
                  for (int i = 0; i < rankings.length; i++) {
                    if (!_isEliminated(rankings[i].data()) && ranks[i] <= 3) {
                      activeRanks.add(ranks[i]);
                    }
                  }
                  hasTopTie = activeRanks.length != activeRanks.toSet().length;
                }

                return Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(15, 18, 15, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (effectiveIsFinal) ...[
                              _buildTopWinnersShowcase(
                                rankings: rankings,
                                ranks: ranks,
                              ),
                              if (hasTopTie) ...[
                                const SizedBox(height: 10),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 11,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade50,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: Colors.amber.shade300,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.balance_rounded,
                                        color: Colors.amber.shade900,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Tie detected in the top rankings! Contestants with equal scores share the same rank.',
                                          style: TextStyle(
                                            color: Colors.amber.shade900,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ] else ...[
                              Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: lightBlue,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.leaderboard_rounded,
                                      color: primaryBlue,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _listTitle,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: darkBlue,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${rankings.length}',
                                    style: const TextStyle(
                                      color: primaryBlue,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: rankings.length,
                                itemBuilder: (context, index) {
                                  final player = rankings[index];
                                  final data = player.data();
                                  final rawMembers = data['teamMembers'] ?? data['members'];
                                  final List<String> members = [];
                                  if (rawMembers is List) {
                                    for (final m in rawMembers) {
                                      final s = m is Map ? (m['name'] ?? '').toString().trim() : m.toString().trim();
                                      if (s.isNotEmpty && !members.contains(s)) members.add(s);
                                    }
                                  }

                                  return _rankingCard(
                                    context: context,
                                    rank: ranks[index],
                                    playerId: player.id,
                                    playerName:
                                        data['name']?.toString() ?? player.id,
                                    team:
                                        data['teamName']?.toString().trim() ??
                                        '',
                                    members: members,
                                    score: _scoreOf(data),
                                    eliminated: _isEliminated(data),
                                    proceeded: _isProceededForCurrentLevel(
                                      data,
                                    ),
                                    isFinalView: false,
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(15, 10, 15, 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 10,
                            offset: const Offset(0, -3),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (effectiveIsFinal)
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton.icon(
                                onPressed: () => _goBackToDashboard(context),
                                icon: const Icon(Icons.dashboard_rounded),
                                label: const Text(
                                  'BACK TO DASHBOARD',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryBlue,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            )
                          else ...[
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton.icon(
                                onPressed: () => _startNextLevel(context),
                                icon: const Icon(Icons.skip_next_rounded),
                                label: const Text(
                                  'START NEXT LEVEL',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryBlue,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: primaryBlue,
                                  disabledForegroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Center(
                              child: Text(
                                _footerText,
                                style: TextStyle(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ],
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

  Widget _buildTopWinnersShowcase({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> rankings,
    required List<int> ranks,
  }) {
    final topEntries = <({int rank, String name, String team, int score})>[];
    for (int i = 0; i < rankings.length; i++) {
      final data = rankings[i].data();
      if (_isEliminated(data)) continue;
      if (ranks[i] <= 3) {
        topEntries.add((
          rank: ranks[i],
          name: data['name']?.toString() ?? rankings[i].id,
          team: data['teamName']?.toString().trim() ?? '',
          score: _scoreOf(data),
        ));
      }
    }

    if (topEntries.isEmpty) {
      for (int i = 0; i < rankings.length; i++) {
        final data = rankings[i].data();
        if (ranks[i] <= 3) {
          topEntries.add((
            rank: ranks[i],
            name: data['name']?.toString() ?? rankings[i].id,
            team: data['teamName']?.toString().trim() ?? '',
            score: _scoreOf(data),
          ));
        }
      }
    }

    if (topEntries.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B2E6B), Color(0xFF1565D8)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: primaryBlue.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.emoji_events_rounded, color: Colors.amber, size: 26),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'OFFICIAL WINNERS PODIUM',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...topEntries.map((winner) {
            final String titleLabel = winner.rank == 1
                ? 'CHAMPION • RANK 1'
                : winner.rank == 2
                ? '1ST RUNNER-UP • RANK 2'
                : '2ND RUNNER-UP • RANK 3';
            final Color badgeColor = winner.rank == 1
                ? Colors.amber.shade600
                : winner.rank == 2
                ? Colors.blueGrey.shade300
                : Colors.orange.shade400;

            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: winner.rank == 1 ? 0.18 : 0.11),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: winner.rank == 1
                      ? Colors.amber.shade300
                      : Colors.white24,
                  width: winner.rank == 1 ? 1.4 : 1.0,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: badgeColor,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '#${winner.rank}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titleLabel,
                          style: TextStyle(
                            color: winner.rank == 1
                                ? Colors.amber.shade300
                                : Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          winner.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (winner.team.isNotEmpty)
                          Text(
                            winner.team,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    '${winner.score} pts',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _emptyRanking(BuildContext context, {bool isFinalView = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              (isFinal || isFinalView)
                  ? 'Final Ranking Not Available\n\nQuiz Code: $quizCode'
                  : 'Level $level Ranking Not Available\n\nQuiz Code: $quizCode',
              textAlign: TextAlign.center,
              style: const TextStyle(color: darkBlue, fontSize: 18),
            ),
            if (isFinal || isFinalView) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () => _goBackToDashboard(context),
                  icon: const Icon(Icons.dashboard_rounded),
                  label: const Text(
                    'BACK TO DASHBOARD',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _rankingCard({
    required BuildContext context,
    required int rank,
    required String playerId,
    required String playerName,
    required String team,
    required int score,
    required bool eliminated,
    required bool proceeded,
    bool isFinalView = false,
    List<String> members = const [],
  }) {
    final iconColor = rank == 1
        ? Colors.amber.shade700
        : rank == 2
        ? Colors.blueGrey.shade500
        : rank == 3
        ? Colors.brown.shade500
        : primaryBlue;

    final bool showProceededState = !isFinalView && proceeded && !eliminated;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: eliminated
            ? const Color(0xFFE5E7EB)
            : isFinalView && rank == 1
            ? const Color(0xFFFFFBEB)
            : showProceededState
            ? const Color(0xFFF0FFF4)
            : Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: eliminated
              ? Colors.grey.shade400
              : isFinalView && rank == 1
              ? Colors.amber.shade400
              : showProceededState
              ? Colors.green.shade200
              : Colors.blue.shade100,
          width: isFinalView && !eliminated && rank <= 2 ? 1.6 : 1.0,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: eliminated
                  ? Colors.grey.shade600
                  : showProceededState
                  ? Colors.green.shade600
                  : iconColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$rank',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  playerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: eliminated ? Colors.red.shade800 : darkBlue,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (members.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Members: ' + members.join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF5B7A9C),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  eliminated
                      ? 'ELIMINATED'
                      : isFinalView
                      ? (team.isEmpty || team == playerName ? 'RANK $rank' : '$team - RANK $rank')
                      : showProceededState
                      ? 'PROCEEDING TO LEVEL ${level + 1}'
                      : (team.isEmpty || team == playerName ? 'Rank #$rank' : '$team - Rank #$rank'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: eliminated
                        ? Colors.grey.shade700
                        : isFinalView
                        ? iconColor
                        : showProceededState
                        ? Colors.green.shade700
                        : Colors.black54,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$score pts',
                style: const TextStyle(
                  color: darkBlue,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 7),
              if (isFinalView)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: eliminated
                        ? Colors.grey.shade300
                        : iconColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: eliminated
                          ? Colors.grey.shade400
                          : iconColor.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!eliminated && rank <= 3) ...[
                        Icon(
                          Icons.emoji_events_rounded,
                          size: 14,
                          color: iconColor,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        eliminated ? 'ELIMINATED' : 'RANK $rank',
                        style: TextStyle(
                          color: eliminated ? Colors.grey.shade700 : iconColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                )
              else if (proceeded && !eliminated)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'PROCEED',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.check_circle_rounded,
                      color: Colors.green.shade700,
                      size: 24,
                    ),
                  ],
                )
              else if (!eliminated)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                      onPressed: () => _proceedContestant(
                        context: context,
                        contestantId: playerId,
                        contestantName: playerName,
                        score: score,
                        rank: rank,
                      ),
                      child: const Text(
                        'PROCEED',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                      onPressed: () => _eliminateContestant(
                        context: context,
                        contestantId: playerId,
                        contestantName: playerName,
                        score: score,
                        rank: rank,
                      ),
                      child: const Text(
                        'ELIMINATE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                )
              else
                Text(
                  'ELIMINATED',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
