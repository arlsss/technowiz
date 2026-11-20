import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'quizmaster_dashboard.dart';
import 'quizmaster_theme.dart';
import '../../navigation_persistence.dart';

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

class _RankingEntry {
  final String id;
  final Map<String, dynamic> _data;

  _RankingEntry(this.id, this._data);

  Map<String, dynamic> data() => _data;
}

class _FinalRankingScreenState extends State<FinalRankingScreen> {
  String get quizCode => widget.quizCode;
  int get level => widget.level;
  bool get isFinal => widget.isFinal;
  Future<void> Function()? get onStartNextLevel => widget.onStartNextLevel;

  late final DocumentReference<Map<String, dynamic>> _sessionRef;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _sessionStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _scoresStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _requestsStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _participantsStream;

  final Map<String, int> _userResponseTimes = {};
  final Map<String, int> _lockedRankOrder = {};
  bool _isLoadingResponseTimes = false;

  bool _isSyncingRanks = false;
  bool _pendingSync = false;
  final Map<String, int> _lastSyncedRanks = {};
  int? _lastSyncedLevel;

  void _fetchResponseTimesIfNeeded(
    List<_RankingEntry> docs,
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
    _requestsStream = _sessionRef.collection('join_requests').snapshots();
    _participantsStream = _sessionRef.collection('participants').snapshots();
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
    await QuizMasterNavPersistence.savePage(
      'ranking',
      quizCode: widget.quizCode,
      rankingLevel: widget.level,
      rankingIsFinal: widget.isFinal,
    );
  }

  static const Color primaryBlue = Color(0xFF1565D8);
  static const Color darkBlue = Color(0xFF0B2E6B);
  static const Color lightBlue = Color(0xFFEAF3FF);

  // ============================================================
  // LABELS
  // ============================================================

  String get _stageLabel => isFinal ? 'the final round' : 'Level $level';

  String get _appBarTitle => isFinal ? 'Winners Result' : 'Level $level Result';

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
      data['isEliminated'] == true ||
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


  // Tagsa-tagsa ka rank (1, 2, 3...) base sa fixed sorted order.
  // Walay mag-share og parehas nga rank ug dili mag-ilis-ilis og ranking.
  List<int> _computeRanks(
    List<_RankingEntry> rankingsDocs,
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
    List<_RankingEntry> rankings,
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
      final sessionDoc = await sessionRef.get();
      final sessionData = sessionDoc.data() ?? {};
      final rawLevelSettings =
          (sessionData['levelSettings'] as Map?)?['Level $level'];
      final int? configuredProceedCount = rawLevelSettings is Map
          ? (int.tryParse(rawLevelSettings['proceedCount']?.toString() ?? '') ??
              int.tryParse(
                  rawLevelSettings['participantsToProceed']?.toString() ?? '') ??
              int.tryParse(rawLevelSettings['eliminateCount']?.toString() ?? ''))
          : null;

      final scores = await sessionRef.collection('scores').get();
      final requests = await sessionRef.collection('join_requests').get();
      final eliminatedIds = <String>{
        for (final d in scores.docs)
          if (_isEliminated(d.data())) d.id,
        for (final r in requests.docs)
          if (_isEliminated(r.data())) r.id,
      };
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
        final bool isExplicitlyEliminated = eliminatedIds.contains(r.id);
        final bool isExplicitlyProceeded = _isProceededForCurrentLevel(r.data());

        final bool shouldProceed = isExplicitlyProceeded
            ? true
            : isExplicitlyEliminated
                ? false
                : (configuredProceedCount != null &&
                        configuredProceedCount > 0 &&
                        assignedRank != null)
                    ? assignedRank <= configuredProceedCount
                    : !eliminatedIds.contains(r.id);

        if (shouldProceed) {
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
    if (!mounted || !context.mounted) return;
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
  // REJOIN ONE CONTESTANT
  // ============================================================

  Future<void> _rejoinContestant({
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
          'Rejoin Contestant?',
          style: TextStyle(color: darkBlue, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Allow "$contestantName" to rejoin and proceed to Level ${level + 1}?\n\n'
          'Current Score: $score points\n'
          'Current Rank: #$rank',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('REJOIN'),
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
        'status': 'proceeding',
        'proceeded': true,
        'eliminated': false,
        'isEliminated': false,
        'eliminatedLevel': FieldValue.delete(),
        'eliminatedAt': FieldValue.delete(),
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
          'proceeded': true,
          'proceededFromLevel': level,
          'eliminated': false,
          'isEliminated': false,
          'eliminatedAfterLevel': FieldValue.delete(),
          'eliminatedScore': FieldValue.delete(),
          'eliminationReason': FieldValue.delete(),
          'eliminatedAt': FieldValue.delete(),
          'eliminatedLevel': FieldValue.delete(),
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
          'status': 'proceeding',
          'eliminated': false,
          'isEliminated': false,
          'eliminatedLevel': FieldValue.delete(),
          'eliminatedAt': FieldValue.delete(),
          'proceededAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await batch.commit();

      if (!context.mounted) return;

      showQuizMasterTopNotification(
        context,
        '$contestantName has rejoined and will proceed to Level ${level + 1}.',
        isSuccess: true,
      );
    } catch (e) {
      if (!context.mounted) return;

      showQuizMasterTopNotification(
        context,
        'Failed to rejoin contestant: $e',
        isError: true,
      );
    }
  }

  // ============================================================
  // CONFIRM ELIMINATION FOR ONE CONTESTANT
  // ============================================================

  Future<void> _confirmElimination({
    required BuildContext context,
    required String contestantId,
    required String contestantName,
    required int score,
    required int rank,
    required bool isAlreadyConfirmed,
  }) async {
    if (isAlreadyConfirmed) {
      showQuizMasterTopNotification(
        context,
        'Elimination is already confirmed for $contestantName.',
        isSuccess: true,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Confirm Elimination?',
          style: TextStyle(color: darkBlue, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to confirm the elimination of "$contestantName" '
          'from $_stageLabel?\n\n'
          'Current Score: $score points\n'
          'Current Rank: #$rank\n\n'
          'The contestant will see the elimination result.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('CONFIRM'),
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
        'isEliminated': true,
        'proceeded': false,
        'proceededFromLevel': FieldValue.delete(),
        'proceededAt': FieldValue.delete(),
        'eliminatedLevel': level,
        'eliminatedAt': FieldValue.serverTimestamp(),
        'rankAtElimination': rank,
        'rank': rank,
        'levelRank': rank,
        'currentRank': rank,
        'rankLevel': level,
      }, SetOptions(merge: true));

      batch.set(
        sessionRef.collection('join_requests').doc(contestantId),
        {
          'status': 'eliminated',
          'eliminationConfirmed': true,
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
        'Elimination confirmed for $contestantName.',
        isWarning: true,
      );
    } catch (e) {
      if (!context.mounted) return;

      showQuizMasterTopNotification(
        context,
        'Failed to confirm elimination: $e',
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

      await QuizMasterNavPersistence.savePage('dashboard');
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
        final rawLevelSettings =
            (sessionData?['levelSettings'] as Map?)?['Level $level'];
        final int? configuredProceedCount = rawLevelSettings is Map
            ? (int.tryParse(rawLevelSettings['proceedCount']?.toString() ?? '') ??
                int.tryParse(
                    rawLevelSettings['participantsToProceed']?.toString() ?? '') ??
                int.tryParse(rawLevelSettings['eliminateCount']?.toString() ?? ''))
            : null;
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
            badgeText: 'TECHNOWIZ • RESULT COMMAND',
            badgeIcon: Icons.emoji_events_rounded,
            showBackButton: false,
          ),
          body: QuizMasterCircuitBackground(
            child: SafeArea(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _scoresStream,
                builder: (context, scoreSnapshot) {
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _requestsStream,
                    builder: (context, requestSnapshot) {
                      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _participantsStream,
                        builder: (context, participantsSnapshot) {
                          if ((scoreSnapshot.connectionState ==
                                      ConnectionState.waiting &&
                                  !scoreSnapshot.hasData) ||
                              (requestSnapshot.connectionState ==
                                      ConnectionState.waiting &&
                                  !requestSnapshot.hasData)) {
                            return const Center(
                              child: CircularProgressIndicator(color: primaryBlue),
                            );
                          }

                          if (scoreSnapshot.hasError || requestSnapshot.hasError) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(25),
                                child: Text(
                                  'Unable to Load Ranking\n\n${scoreSnapshot.error ?? requestSnapshot.error}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: darkBlue),
                                ),
                              ),
                            );
                          }

                          final scoreDocs = scoreSnapshot.data?.docs ?? [];
                          final requestDocs = requestSnapshot.data?.docs ?? [];
                          final participantDocs =
                              participantsSnapshot.data?.docs ?? [];

                          final Map<String, Map<String, dynamic>> mergedMap = {};

                          // 1. Process join_requests (all approved/joined contestants)
                          for (final doc in requestDocs) {
                            final data = doc.data();
                            final status =
                                (data['status'] ?? '').toString().trim().toLowerCase();
                            if (status == 'left' ||
                                status == 'rejected' ||
                                status == 'declined' ||
                                data['leftQuiz'] == true) {
                              continue;
                            }
                            final id = (data['uid'] ?? doc.id).toString().trim();
                            if (id.isEmpty) continue;
                            mergedMap[id] = Map<String, dynamic>.from(data);
                            mergedMap[id]!['uid'] = id;
                          }

                          // 2. Process participants (supplemental)
                          for (final doc in participantDocs) {
                            final data = doc.data();
                            final status =
                                (data['status'] ?? '').toString().trim().toLowerCase();
                            if (status == 'left' ||
                                status == 'rejected' ||
                                status == 'declined' ||
                                data['leftQuiz'] == true) {
                              continue;
                            }
                            final id = (data['uid'] ?? doc.id).toString().trim();
                            if (id.isEmpty) continue;
                            if (!mergedMap.containsKey(id)) {
                              mergedMap[id] = Map<String, dynamic>.from(data);
                              mergedMap[id]!['uid'] = id;
                            } else {
                              final current = mergedMap[id]!;
                              if ((current['teamName'] == null ||
                                      current['teamName']
                                          .toString()
                                          .trim()
                                          .isEmpty) &&
                                  data['teamName'] != null) {
                                current['teamName'] = data['teamName'];
                              }
                              if (current['teamMembers'] == null &&
                                  data['teamMembers'] != null) {
                                current['teamMembers'] = data['teamMembers'];
                              }
                            }
                          }

                          // 3. Process scores (overlay scores and points)
                          for (final doc in scoreDocs) {
                            final data = doc.data();
                            final id = (data['uid'] ?? doc.id).toString().trim();
                            if (id.isEmpty) continue;
                            if (mergedMap.containsKey(id)) {
                              final existing = mergedMap[id]!;
                              final oldName =
                                  existing['name'] ?? existing['displayName'];
                              final oldTeamName = existing['teamName'];
                              final oldMembers = existing['teamMembers'] ??
                                  existing['members'];
                              existing.addAll(data);
                              if ((existing['name'] == null ||
                                      existing['name'].toString().trim().isEmpty) &&
                                  oldName != null) {
                                existing['name'] = oldName;
                              }
                              if ((existing['teamName'] == null ||
                                      existing['teamName']
                                          .toString()
                                          .trim()
                                          .isEmpty) &&
                                  oldTeamName != null) {
                                existing['teamName'] = oldTeamName;
                              }
                              if (existing['teamMembers'] == null &&
                                  oldMembers != null) {
                                existing['teamMembers'] = oldMembers;
                              }
                            } else {
                              mergedMap[id] = Map<String, dynamic>.from(data);
                              mergedMap[id]!['uid'] = id;
                            }
                          }

                          final allContestants = mergedMap.entries
                              .map(
                                (e) => _RankingEntry(e.key, e.value),
                              )
                              .toList();

                          if (allContestants.isEmpty) {
                            return _emptyRanking(
                              context,
                              isFinalView: effectiveIsFinal,
                            );
                          }

                          // Ipakita ang tanang contestant nga naka-apil, apil ang mga na-eliminate
                          final activeDocs = allContestants.toList();

                          if (activeDocs.isEmpty) {
                            return _emptyRanking(
                              context,
                              isFinalView: effectiveIsFinal,
                            );
                          }

                          _fetchResponseTimesIfNeeded(activeDocs);

                // Sort sa client:
                // 1. Elimination state (ang active una, ang eliminated sa ubos)
                // 2. Score (descending - highest score first)
                // 3. Speed / Submission time (earlier timestamp = faster = higher rank)
                // 4. Locked order if already locked and times equal
                // 5. Stable deterministic fallback (by ID)
                final rankings = [...activeDocs]
                  ..sort((a, b) {
                    final aElim = _isEliminated(a.data());
                    final bElim = _isEliminated(b.data());
                    if (aElim != bElim) return aElim ? 1 : -1;

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
                              if (!effectiveIsFinal &&
                                  configuredProceedCount != null &&
                                  configuredProceedCount > 0) ...[
                                Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.green.shade200,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.how_to_reg_rounded,
                                        color: Colors.green.shade700,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Advancement Rule: Top $configuredProceedCount participant(s) will proceed to Level ${level + 1}.',
                                          style: TextStyle(
                                            color: Colors.green.shade800,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              // Split rankings into qualified and eliminated
                              () {
                                final List<int> qualifiedIndices = [];
                                final List<int> eliminatedIndices = [];
                                for (int i = 0; i < rankings.length; i++) {
                                  final pData = rankings[i].data();
                                  final pRank = ranks[i];
                                  final bool pExplicitElim = _isEliminated(pData);
                                  final bool pExplicitProceed =
                                      _isProceededForCurrentLevel(pData);
                                  final bool pWithinCutoff =
                                      (configuredProceedCount != null &&
                                              configuredProceedCount > 0)
                                          ? pRank <= configuredProceedCount
                                          : true;
                                  final bool pIsQualified = pExplicitProceed
                                      ? true
                                      : pExplicitElim
                                          ? false
                                          : pWithinCutoff;

                                  if (pIsQualified) {
                                    qualifiedIndices.add(i);
                                  } else {
                                    eliminatedIndices.add(i);
                                  }
                                }

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // 1. QUALIFIED CONTESTANTS CARD (BABAW)
                                    Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.only(bottom: 16),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(
                                          color: const Color(0xFFBBF7D0),
                                          width: 1.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.04),
                                            blurRadius: 10,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Header for Qualified
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 12,
                                            ),
                                            decoration: const BoxDecoration(
                                              color: Color(0xFFF0FDF4),
                                              borderRadius: BorderRadius.only(
                                                topLeft: Radius.circular(17),
                                                topRight: Radius.circular(17),
                                              ),
                                              border: Border(
                                                bottom: BorderSide(
                                                  color: Color(0xFFBBF7D0),
                                                ),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(6),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFDCFCE7),
                                                    borderRadius:
                                                        BorderRadius.circular(8),
                                                  ),
                                                  child: const Icon(
                                                    Icons.check_circle_rounded,
                                                    color: Color(0xFF15803D),
                                                    size: 18,
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                    children: [
                                                      const Text(
                                                        'QUALIFIED CONTESTANTS',
                                                        style: TextStyle(
                                                          color: Color(0xFF14532D),
                                                          fontWeight: FontWeight.w800,
                                                          fontSize: 13.5,
                                                          letterSpacing: 0.5,
                                                        ),
                                                      ),
                                                      Text(
                                                        configuredProceedCount != null &&
                                                                configuredProceedCount > 0
                                                            ? 'Top $configuredProceedCount will advance to Level ${level + 1} (Auto-proceed)'
                                                            : 'Proceeding to Level ${level + 1} (Auto-proceed)',
                                                        style: TextStyle(
                                                          color: Colors.green.shade700,
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF16A34A),
                                                    borderRadius:
                                                        BorderRadius.circular(12),
                                                  ),
                                                  child: Text(
                                                    '${qualifiedIndices.length}',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (qualifiedIndices.isEmpty)
                                            Padding(
                                              padding: const EdgeInsets.all(22),
                                              child: Center(
                                                child: Text(
                                                  'No qualified contestants yet.',
                                                  style: TextStyle(
                                                    color: Colors.grey.shade600,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            )
                                          else
                                            ListView.separated(
                                              shrinkWrap: true,
                                              physics:
                                                  const NeverScrollableScrollPhysics(),
                                              padding: const EdgeInsets.all(12),
                                              itemCount: qualifiedIndices.length,
                                              separatorBuilder: (_, __) =>
                                                  const SizedBox(height: 8),
                                              itemBuilder: (context, qIndex) {
                                                final index = qualifiedIndices[qIndex];
                                                final player = rankings[index];
                                                final data = player.data();
                                                final rawMembers =
                                                    data['teamMembers'] ??
                                                        data['members'];
                                                final List<String> members = [];
                                                if (rawMembers is List) {
                                                  for (final m in rawMembers) {
                                                    final s = m is Map
                                                        ? (m['name'] ?? '')
                                                            .toString()
                                                            .trim()
                                                        : m.toString().trim();
                                                    if (s.isNotEmpty &&
                                                        !members.contains(s)) {
                                                      members.add(s);
                                                    }
                                                  }
                                                }

                                                return _buildQualifiedCard(
                                                  context: context,
                                                  rank: ranks[index],
                                                  playerId: player.id,
                                                  playerName: (data['displayName'] ??
                                                          data['name'] ??
                                                          player.id)
                                                      .toString()
                                                      .trim(),
                                                  team: data['teamName']
                                                          ?.toString()
                                                          .trim() ??
                                                      '',
                                                  members: members,
                                                  score: _scoreOf(data),
                                                  configuredProceedCount:
                                                      configuredProceedCount,
                                                );
                                              },
                                            ),
                                        ],
                                      ),
                                    ),

                                    // 2. ELIMINATED CONTESTANTS CARD (UBOS)
                                    Container(
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(
                                          color: const Color(0xFFFECACA),
                                          width: 1.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.04),
                                            blurRadius: 10,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Header for Eliminated
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 12,
                                            ),
                                            decoration: const BoxDecoration(
                                              color: Color(0xFFFEF2F2),
                                              borderRadius: BorderRadius.only(
                                                topLeft: Radius.circular(17),
                                                topRight: Radius.circular(17),
                                              ),
                                              border: Border(
                                                bottom: BorderSide(
                                                  color: Color(0xFFFECACA),
                                                ),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(6),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFFEE2E2),
                                                    borderRadius:
                                                        BorderRadius.circular(8),
                                                  ),
                                                  child: const Icon(
                                                    Icons.cancel_rounded,
                                                    color: Color(0xFFDC2626),
                                                    size: 18,
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                const Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        'ELIMINATED CONTESTANTS',
                                                        style: TextStyle(
                                                          color: Color(0xFF991B1B),
                                                          fontWeight: FontWeight.w800,
                                                          fontSize: 13.5,
                                                          letterSpacing: 0.5,
                                                        ),
                                                      ),
                                                      Text(
                                                        'Below advancement cutoff or confirmed eliminated',
                                                        style: TextStyle(
                                                          color: Color(0xFFB91C1C),
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFDC2626),
                                                    borderRadius:
                                                        BorderRadius.circular(12),
                                                  ),
                                                  child: Text(
                                                    '${eliminatedIndices.length}',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (eliminatedIndices.isEmpty)
                                            Padding(
                                              padding: const EdgeInsets.all(22),
                                              child: Center(
                                                child: Text(
                                                  'No eliminated contestants in this level.',
                                                  style: TextStyle(
                                                    color: Colors.grey.shade600,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            )
                                          else
                                            ListView.separated(
                                              shrinkWrap: true,
                                              physics:
                                                  const NeverScrollableScrollPhysics(),
                                              padding: const EdgeInsets.all(12),
                                              itemCount: eliminatedIndices.length,
                                              separatorBuilder: (_, __) =>
                                                  const SizedBox(height: 8),
                                              itemBuilder: (context, eIndex) {
                                                final index = eliminatedIndices[eIndex];
                                                final player = rankings[index];
                                                final data = player.data();
                                                final rawMembers =
                                                    data['teamMembers'] ??
                                                        data['members'];
                                                final List<String> members = [];
                                                if (rawMembers is List) {
                                                  for (final m in rawMembers) {
                                                    final s = m is Map
                                                        ? (m['name'] ?? '')
                                                            .toString()
                                                            .trim()
                                                        : m.toString().trim();
                                                    if (s.isNotEmpty &&
                                                        !members.contains(s)) {
                                                      members.add(s);
                                                    }
                                                  }
                                                }

                                                final bool isConfirmed =
                                                    data['eliminationConfirmed'] ==
                                                        true;

                                                return _buildEliminatedCard(
                                                  context: context,
                                                  rank: ranks[index],
                                                  playerId: player.id,
                                                  playerName: (data['displayName'] ??
                                                          data['name'] ??
                                                          player.id)
                                                      .toString()
                                                      .trim(),
                                                  team: data['teamName']
                                                          ?.toString()
                                                          .trim() ??
                                                      '',
                                                  members: members,
                                                  score: _scoreOf(data),
                                                  isConfirmed: isConfirmed,
                                                  configuredProceedCount:
                                                      configuredProceedCount,
                                                );
                                              },
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }(),
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
                        );
                      },
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
    required List<_RankingEntry> rankings,
    required List<int> ranks,
  }) {
    if (rankings.isEmpty) {
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
          Row(
            children: [
              const Icon(Icons.emoji_events_rounded, color: Colors.amber, size: 26),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'TOTAL RANKINGS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white30),
                ),
                child: Text(
                  '${rankings.length} Contestants',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...List.generate(rankings.length, (i) {
            final player = rankings[i];
            final data = player.data();
            final rank = ranks[i];
            final bool isEliminated = _isEliminated(data);
            final int score = _scoreOf(data);
            final String name = (data['displayName'] ??
                    data['name'] ??
                    player.id)
                .toString()
                .trim();
            final String team = data['teamName']?.toString().trim() ?? '';
            final rawMembers = data['teamMembers'] ?? data['members'];
            final List<String> members = [];
            if (rawMembers is List) {
              for (final m in rawMembers) {
                final s = m is Map
                    ? (m['name'] ?? '').toString().trim()
                    : m.toString().trim();
                if (s.isNotEmpty && !members.contains(s)) {
                  members.add(s);
                }
              }
            }

            // Subtitle label and accent colors based on rank & elimination
            String titleLabel;
            Color accentColor;
            if (isEliminated) {
              titleLabel = 'ELIMINATED • RANK #$rank';
              accentColor = const Color(0xFFFF8A80);
            } else if (rank == 1) {
              titleLabel = 'CHAMPION • RANK 1';
              accentColor = Colors.amber.shade300;
            } else if (rank == 2) {
              titleLabel = '1ST RUNNER-UP • RANK 2';
              accentColor = Colors.blueGrey.shade200;
            } else if (rank == 3) {
              titleLabel = '2ND RUNNER-UP • RANK 3';
              accentColor = Colors.orange.shade300;
            } else if (rank <= 10) {
              titleLabel = 'TOP 10 • RANK #$rank';
              accentColor = const Color(0xFF86EFAC);
            } else {
              titleLabel = 'RANK #$rank';
              accentColor = Colors.white70;
            }

            final cardBg = isEliminated
                ? Colors.red.withValues(alpha: 0.14)
                : Colors.white.withValues(
                    alpha: rank == 1
                        ? 0.20
                        : rank == 2
                        ? 0.15
                        : rank == 3
                        ? 0.13
                        : rank <= 10
                        ? 0.10
                        : 0.08,
                  );

            final cardBorder = isEliminated
                ? Colors.redAccent.withValues(alpha: 0.45)
                : rank == 1
                ? Colors.amber.shade300
                : rank == 2
                ? Colors.blueGrey.shade200
                : rank == 3
                ? Colors.orange.shade300
                : rank <= 10
                ? const Color(0xFF86EFAC).withValues(alpha: 0.60)
                : Colors.white24;

            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 9),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: cardBorder,
                  width: (!isEliminated && rank <= 2) ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                children: [
                  _buildRankLeadingWidget(rank, isEliminated),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titleLabel,
                          style: TextStyle(
                            color: accentColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (team.isNotEmpty && team != name)
                          Text(
                            team,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        if (members.isNotEmpty)
                          Text(
                            'Members: ${members.join(', ')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.65),
                              fontSize: 10,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$score pts',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (isEliminated) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFFFF8A80),
                              width: 0.8,
                            ),
                          ),
                          child: const Text(
                            'ELIMINATED',
                            style: TextStyle(
                              color: Color(0xFFFF8A80),
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildRankLeadingWidget(int rank, bool isEliminated) {
    if (rank <= 3) {
      final trophyAsset = rank == 1
          ? 'assets/trophies/gold_trophy_3d.jpg'
          : (rank == 2
              ? 'assets/trophies/silver_trophy_3d.jpg'
              : 'assets/trophies/bronze_trophy_3d.jpg');

      final rankColor = rank == 1
          ? const Color(0xFFF59E0B)
          : (rank == 2 ? const Color(0xFFCBD5E1) : const Color(0xFFD97706));

      return Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: rankColor, width: 2),
              boxShadow: [
                BoxShadow(
                  color: rankColor.withValues(alpha: 0.35),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                trophyAsset,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(
                  Icons.emoji_events_rounded,
                  size: 20,
                  color: rankColor,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -2,
            right: -3,
            child: Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                color: rankColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.2),
              ),
              alignment: Alignment.center,
              child: Text(
                '$rank',
                style: const TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (rank >= 4 && rank <= 10) {
      const badgeAsset = 'assets/trophies/top10_badge_3d.jpg';
      const rankColor = Color(0xFF22C55E);

      return Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: rankColor, width: 2),
              boxShadow: [
                BoxShadow(
                  color: rankColor.withValues(alpha: 0.35),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                badgeAsset,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.workspace_premium_rounded,
                  size: 20,
                  color: rankColor,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -2,
            right: -3,
            child: Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                color: rankColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.2),
              ),
              alignment: Alignment.center,
              child: Text(
                '$rank',
                style: const TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Rank 11+ : Numbers only
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.16),
        border: Border.all(
          color: isEliminated
              ? Colors.redAccent.withValues(alpha: 0.5)
              : Colors.white38,
          width: 1.3,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        '#$rank',
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w900,
          color: isEliminated ? const Color(0xFFFF8A80) : Colors.white,
        ),
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

  Widget _buildQualifiedCard({
    required BuildContext context,
    required int rank,
    required String playerId,
    required String playerName,
    required String team,
    required List<String> members,
    required int score,
    int? configuredProceedCount,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFBBF7D0),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Color(0xFF16A34A),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$rank',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5,
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
                  style: const TextStyle(
                    color: darkBlue,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (members.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Members: ${members.join(', ')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF5B7A9C),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 3),
                Text(
                  configuredProceedCount != null && configuredProceedCount > 0
                      ? 'TOP $configuredProceedCount • QUALIFIED TO PROCEED'
                      : 'QUALIFIED TO PROCEED',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF15803D),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$score pts',
                style: const TextStyle(
                  color: darkBlue,
                  fontWeight: FontWeight.bold,
                  fontSize: 14.5,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 2.5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF86EFAC),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_rounded,
                      size: 11,
                      color: Color(0xFF15803D),
                    ),
                    SizedBox(width: 2),
                    Text(
                      'QUALIFIED',
                      style: TextStyle(
                        color: Color(0xFF15803D),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEliminatedCard({
    required BuildContext context,
    required int rank,
    required String playerId,
    required String playerName,
    required String team,
    required List<String> members,
    required int score,
    required bool isConfirmed,
    int? configuredProceedCount,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFECACA),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isConfirmed ? Colors.grey.shade600 : const Color(0xFFEF4444),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$rank',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5,
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
                    color: Colors.red.shade900,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (members.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Members: ${members.join(', ')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF5B7A9C),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 3),
                Text(
                  isConfirmed
                      ? 'ELIMINATION CONFIRMED'
                      : (configuredProceedCount != null &&
                              configuredProceedCount > 0 &&
                              rank > configuredProceedCount)
                          ? 'BELOW TOP $configuredProceedCount CUTOFF'
                          : 'ELIMINATED',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isConfirmed
                        ? Colors.grey.shade700
                        : Colors.red.shade700,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$score pts',
                style: const TextStyle(
                  color: darkBlue,
                  fontWeight: FontWeight.bold,
                  fontSize: 14.5,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => _rejoinContestant(
                      context: context,
                      contestantId: playerId,
                      contestantName: playerName,
                      score: score,
                      rank: rank,
                    ),
                    child: const Text(
                      'REJOIN',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isConfirmed
                          ? Colors.grey.shade600
                          : Colors.red.shade600,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => _confirmElimination(
                      context: context,
                      contestantId: playerId,
                      contestantName: playerName,
                      score: score,
                      rank: rank,
                      isAlreadyConfirmed: isConfirmed,
                    ),
                    child: Text(
                      isConfirmed ? 'CONFIRMED' : 'CONFIRM',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
