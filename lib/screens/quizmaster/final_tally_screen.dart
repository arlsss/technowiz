import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'quizmaster_theme.dart';
import 'final_ranking_screen.dart';
import 'quiz_control_screen.dart';
import '../../navigation_persistence.dart';

/// Contestant Tally Model
class ContestantTally {
  final String uid;
  final String displayName;
  final String teamName;
  final bool isTeam;
  final List<String> teamMembers;
  final int score;
  final int rank;
  final int correctCount;
  final int wrongCount;
  final int unansweredCount;
  final int contestedCount;
  final int submissionTimeMs;
  final bool isEliminated;
  final bool isTied;

  const ContestantTally({
    required this.uid,
    required this.displayName,
    required this.teamName,
    required this.isTeam,
    required this.teamMembers,
    required this.score,
    required this.rank,
    required this.correctCount,
    required this.wrongCount,
    required this.unansweredCount,
    required this.contestedCount,
    required this.submissionTimeMs,
    required this.isEliminated,
    required this.isTied,
  });

  String get effectiveName {
    if (isTeam && teamName.trim().isNotEmpty) {
      return teamName.trim();
    }
    return displayName.trim().isNotEmpty ? displayName.trim() : 'Contestant';
  }

  ContestantTally copyWith({
    int? rank,
    bool? isTied,
  }) {
    return ContestantTally(
      uid: uid,
      displayName: displayName,
      teamName: teamName,
      isTeam: isTeam,
      teamMembers: teamMembers,
      score: score,
      rank: rank ?? this.rank,
      correctCount: correctCount,
      wrongCount: wrongCount,
      unansweredCount: unansweredCount,
      contestedCount: contestedCount,
      submissionTimeMs: submissionTimeMs,
      isEliminated: isEliminated,
      isTied: isTied ?? this.isTied,
    );
  }
}

/// Final Tally Screen
/// Displays a comprehensive table form showing all contestants, their:
/// - Correct answers (Check / ✔️)
/// - Wrong answers (❌)
/// - Unanswered questions (❓)
/// - Contested answers (⚖️)
/// - Total Score & Rank
/// With bottom actions: "TIE BREAKER" and "FINISH QUIZ" (or "NEXT LEVEL").
class FinalTallyScreen extends StatefulWidget {
  final String quizCode;
  final int level;
  final bool isFinal;
  final Future<void> Function()? onFinishQuiz;
  final Future<void> Function()? onProceedToNextLevel;

  const FinalTallyScreen({
    super.key,
    required this.quizCode,
    this.level = 1,
    this.isFinal = true,
    this.onFinishQuiz,
    this.onProceedToNextLevel,
  });

  @override
  State<FinalTallyScreen> createState() => _FinalTallyScreenState();
}

class _FinalTallyScreenState extends State<FinalTallyScreen> {
  String get quizCode => widget.quizCode;
  int get level => widget.level;
  bool get isFinal => widget.isFinal;

  late final DocumentReference<Map<String, dynamic>> _sessionRef;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _sessionStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _requestsStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _scoresStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _contestsStream;

  final Map<String, Map<String, dynamic>> _contestantResponsesCache = {};
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
      _responseSubs = {};

  bool _isFinishing = false;
  final Set<String> _tieResolvedUids = {};

  @override
  void initState() {
    super.initState();
    _saveCurrentPage();

    _sessionRef = FirebaseFirestore.instance
        .collection('quiz_sessions')
        .doc(widget.quizCode);
    _sessionStream = _sessionRef.snapshots();
    _requestsStream = _sessionRef.collection('join_requests').snapshots();
    _scoresStream = _sessionRef.collection('scores').snapshots();
    _contestsStream = _sessionRef.collection('contest_requests').snapshots();
  }

  Future<void> _saveCurrentPage() async {
    await QuizMasterNavPersistence.savePage(
      'tally',
      quizCode: widget.quizCode,
      rankingLevel: widget.level,
      rankingIsFinal: widget.isFinal,
    );
  }

  @override
  void dispose() {
    for (final sub in _responseSubs.values) {
      sub.cancel();
    }
    _responseSubs.clear();
    super.dispose();
  }

  void _ensureResponseSubscription(String uid) {
    if (_responseSubs.containsKey(uid)) return;

    final sub = _sessionRef
        .collection('answers')
        .doc(uid)
        .collection('responses')
        .snapshots()
        .listen(
      (snapshot) {
        int correct = 0;
        int wrong = 0;
        int unanswered = 0;
        int contested = 0;
        int latestTimeMs = 0;

        for (final doc in snapshot.docs) {
          final data = doc.data();
          final answerStatus =
              (data['answerStatus'] ?? '').toString().toLowerCase();
          final rawCorrect = data['isCorrect'];

          if (answerStatus == 'correct' || rawCorrect == true) {
            correct++;
          } else if (answerStatus == 'wrong' ||
              (answerStatus.isEmpty && rawCorrect == false)) {
            wrong++;
          } else if (answerStatus == 'unanswered') {
            unanswered++;
          }

          final contestStatus =
              (data['contestStatus'] ?? '').toString().toLowerCase();
          if (contestStatus.isNotEmpty && contestStatus != 'none') {
            contested++;
          }

          final answeredAt = data['answeredAt'];
          if (answeredAt is Timestamp) {
            final ms = answeredAt.millisecondsSinceEpoch;
            if (ms > latestTimeMs) latestTimeMs = ms;
          }
        }

        if (mounted) {
          setState(() {
            _contestantResponsesCache[uid] = {
              'correct': correct,
              'wrong': wrong,
              'unanswered': unanswered,
              'contested': contested,
              'latestTimeMs': latestTimeMs,
            };
          });
        }
      },
      onError: (_) {},
    );

    _responseSubs[uid] = sub;
  }

  // ============================================================
  // TIE BREAKER ACTION
  // ============================================================

  Future<void> _handleTieBreaker(List<ContestantTally> contestants) async {
    if (contestants.isEmpty) return;

    // Group contestants by score
    final Map<int, List<ContestantTally>> scoreGroups = {};
    for (final c in contestants) {
      if (!c.isEliminated) {
        scoreGroups.putIfAbsent(c.score, () => []).add(c);
      }
    }

    // Filter tied groups (more than 1 contestant with same score)
    final tiedEntries =
        scoreGroups.entries.where((e) => e.value.length > 1).toList();

    if (tiedEntries.isEmpty) {
      showDialog<void>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: Colors.green.shade700,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'No Ties Detected',
                    style: TextStyle(
                      color: QuizMasterColors.darkBlue,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
            content: const Text(
              'All contestants have distinct scores. No tie-breaker is required!\n\nYou can proceed directly to FINISH QUIZ.',
              style: TextStyle(
                color: QuizMasterColors.textDark,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: QuizMasterColors.primaryBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
      return;
    }

    // Fetch Admin's Tie Breaker Questions from Firestore
    List<QueryDocumentSnapshot<Map<String, dynamic>>> tieBreakerQuestions = [];
    try {
      final snap =
          await _sessionRef.collection('questions').orderBy('order').get();
      tieBreakerQuestions = snap.docs.where((doc) {
        final data = doc.data();
        final isTB = data['isTieBreaker'] == true;
        final sLvl =
            (data['sessionLevel'] ?? '').toString().trim().toLowerCase();
        return isTB || sLvl == 'tie breaker';
      }).toList();
    } catch (_) {}

    if (!mounted) return;

    // Ties detected! Show Tie-Breaker Dialog with questions set by Admin
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.balance_rounded,
                  color: Colors.amber.shade900,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Tie Breaker Review',
                  style: TextStyle(
                    color: QuizMasterColors.darkBlue,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tied scores detected among contestants:\n',
                  style: TextStyle(
                    fontSize: 13,
                    color: QuizMasterColors.textDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                ...tiedEntries.map((entry) {
                  final score = entry.key;
                  final group = entry.value;
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade800,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '$score PTS',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Rank ${group.first.rank} (${group.length} Contestants Tied)',
                              style: TextStyle(
                                color: Colors.amber.shade900,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...group.map((c) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  size: 16,
                                  color: Colors.amber,
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        c.effectiveName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: QuizMasterColors.darkBlue,
                                        ),
                                      ),
                                      if (c.submissionTimeMs > 0)
                                        Text(
                                          'Last submission: ${DateTime.fromMillisecondsSinceEpoch(c.submissionTimeMs).toLocal().toString().substring(14, 19)}',
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            color: Colors.black54,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: () => _awardTieBreakerPoint(ctx, c),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF16A34A),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      '+1 PT',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                }),

                // Admin-set Tie Breaker Questions section
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 8, bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.help_outline_rounded,
                            size: 16,
                            color: QuizMasterColors.primaryBlue,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Admin Tie Breaker Questions (${tieBreakerQuestions.length})',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                              color: QuizMasterColors.darkBlue,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (tieBreakerQuestions.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            'No tie-breaker questions configured by Admin yet.\nYou can use QUIZ AGAIN or award +1 PT manually.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.black54,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        )
                      else
                        ...tieBreakerQuestions.asMap().entries.map((entry) {
                          final idx = entry.key + 1;
                          final qData = entry.value.data();
                          final qText = (qData['questionText'] ??
                                  qData['question'] ??
                                  qData['text'] ??
                                  '')
                              .toString();
                          final qAns = (qData['correctAnswer'] ??
                                  qData['answer'] ??
                                  '')
                              .toString();

                          return Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: QuizMasterColors.primaryBlue
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'Q$idx',
                                        style: const TextStyle(
                                          color: QuizMasterColors.primaryBlue,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        qText,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                          color: QuizMasterColors.darkBlue,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      size: 14,
                                      color: Color(0xFF16A34A),
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        'Answer: $qAns',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF15803D),
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
                ),

                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(
                            Icons.assignment_outlined,
                            size: 15,
                            color: QuizMasterColors.primaryBlue,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Quiz Instructions for Tie-Breaker:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: QuizMasterColors.darkBlue,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '• Present the tie-breaker questions below to the tied contestants.\n'
                        '• QUIZ AGAIN: Starts or resumes the quiz round for tied contestants.\n'
                        '• +1 PT: Tap "+1 PT" beside the contestant who answers correctly to award a point.\n'
                        '• KEEP SHARED: Finalizes the standings with tied contestants sharing the same rank without further questions.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF475569),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('KEEP SHARED'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await _handleQuizAgain();
              },
              icon: const Icon(Icons.replay_rounded, size: 18),
              label: const Text('QUIZ AGAIN'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF15803D),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _awardTieBreakerPoint(
    BuildContext dialogCtx,
    ContestantTally contestant,
  ) async {
    try {
      final scoreRef = _sessionRef.collection('scores').doc(contestant.uid);
      await scoreRef.set({
        'score': FieldValue.increment(1),
        'totalScore': FieldValue.increment(1),
        'tieBreakerWon': true,
        'tieBreakerResolved': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _tieResolvedUids.add(contestant.uid);

      if (dialogCtx.mounted) {
        Navigator.pop(dialogCtx);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '+1 Point awarded to ${contestant.effectiveName}! Tie resolved.',
            ),
            backgroundColor: const Color(0xFF16A34A),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update score: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleQuizAgain() async {
    try {
      await _sessionRef.set({
        'tieBreakerActive': true,
        'status': 'waiting',
        'isFinished': false,
        'currentQuestion': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error activating tie breaker: $e');
    }

    if (!mounted) return;
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => QuizControlScreen(quizCode: widget.quizCode),
        ),
      );
    }
  }

  // ============================================================
  // FINISH QUIZ ACTION
  // ============================================================

  void _confirmFinishQuiz() {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.emoji_events_rounded,
                color: QuizMasterColors.primaryBlue,
                size: 26,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Finish Quiz Event?',
                  style: TextStyle(
                    color: QuizMasterColors.darkBlue,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          content: const Text(
            'This will finalize the competition results and open the Winners Podium.\n\nProceed to final results declaration?',
            style: TextStyle(
              color: QuizMasterColors.textDark,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CANCEL'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _executeFinishQuiz();
              },
              icon: const Icon(Icons.flag_rounded),
              label: const Text('FINISH QUIZ'),
              style: ElevatedButton.styleFrom(
                backgroundColor: QuizMasterColors.primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _executeFinishQuiz() async {
    if (_isFinishing) return;
    setState(() => _isFinishing = true);

    try {
      if (widget.onFinishQuiz != null) {
        await widget.onFinishQuiz!();
        return;
      }

      // Default finish quiz logic
      await _sessionRef.set(
        {
          'status': 'finished',
          'isFinished': true,
          'finishedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;

      // Navigate to Winners Result
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => FinalRankingScreen(
            quizCode: widget.quizCode,
            level: widget.level,
            isFinal: true,
          ),
        ),
      );
    } catch (e) {
      debugPrint('FINISH QUIZ ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to finish quiz: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isFinishing = false);
      }
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: QuizMasterAppBar(
        title: 'Final Tally',
        subtitle: 'Code: $quizCode',
        badgeText: 'TECHNOWIZ • SCOREBOARD',
        badgeIcon: Icons.table_chart_rounded,
        showBackButton: true,
        onBack: () => Navigator.of(context).pop(),
      ),
      body: QuizMasterCircuitBackground(
        child: SafeArea(
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _sessionStream,
            builder: (context, sessionSnap) {
              final sessionData = sessionSnap.data?.data() ?? {};
              final totalQuizQuestions =
                  (sessionData['questions'] as List?)?.length ?? 0;

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _requestsStream,
                builder: (context, requestsSnap) {
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _scoresStream,
                    builder: (context, scoresSnap) {
                      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _contestsStream,
                        builder: (context, contestsSnap) {
                          if ((requestsSnap.connectionState ==
                                      ConnectionState.waiting &&
                                  !requestsSnap.hasData) ||
                              (scoresSnap.connectionState ==
                                      ConnectionState.waiting &&
                                  !scoresSnap.hasData)) {
                            return const Center(
                              child: CircularProgressIndicator(
                                color: QuizMasterColors.primaryBlue,
                              ),
                            );
                          }

                          // 1. Map scores by uid
                          final scoreDocs = scoresSnap.data?.docs ?? [];
                          final Map<String, Map<String, dynamic>> scoreByUid = {};
                          for (final d in scoreDocs) {
                            scoreByUid[d.id] = d.data();
                          }

                          // 2. Map contests by uid
                          final contestDocs = contestsSnap.data?.docs ?? [];
                          final Map<String, int> contestCountByUid = {};
                          for (final d in contestDocs) {
                            final data = d.data();
                            final uid = (data['contestantUid'] ??
                                    d.id.split('_').first)
                                .toString()
                                .trim();
                            if (uid.isNotEmpty) {
                              contestCountByUid[uid] =
                                  (contestCountByUid[uid] ?? 0) + 1;
                            }
                          }

                          // 3. Process join_requests (all approved/joined contestants)
                          final requestDocs = requestsSnap.data?.docs ?? [];
                          final List<ContestantTally> tallyList = [];

                          for (final doc in requestDocs) {
                            final data = doc.data();
                            final status = (data['status'] ?? '')
                                .toString()
                                .trim()
                                .toLowerCase();

                            // Skip left or rejected
                            if (status == 'left' ||
                                status == 'rejected' ||
                                status == 'declined' ||
                                data['leftQuiz'] == true) {
                              continue;
                            }

                            final uid =
                                (data['uid'] ?? doc.id).toString().trim();
                            if (uid.isEmpty) continue;

                            // Ensure responses are subscribed to
                            _ensureResponseSubscription(uid);

                            final sData = scoreByUid[uid] ?? {};
                            final rawScore = sData['score'];
                            final int score = rawScore is num
                                ? rawScore.toInt()
                                : int.tryParse(rawScore?.toString() ?? '') ?? 0;

                            final isElim = sData['eliminated'] == true ||
                                sData['isEliminated'] == true ||
                                sData['status']?.toString().toLowerCase() ==
                                    'eliminated';

                            final rawTeam =
                                (data['teamName'] ?? '').toString().trim();
                            final contestantType = (data['contestantType'] ?? '')
                                .toString()
                                .trim()
                                .toLowerCase();
                            final bool isTeam = data['isTeam'] == true ||
                                contestantType == 'team' ||
                                rawTeam.isNotEmpty;

                            final displayName = (data['displayName'] ??
                                    data['realName'] ??
                                    data['fullName'] ??
                                    data['name'] ??
                                    data['email'] ??
                                    uid)
                                .toString()
                                .trim();

                            final rawMembers =
                                data['teamMembers'] ?? data['members'];
                            final List<String> members = [];
                            if (rawMembers is List) {
                              for (final m in rawMembers) {
                                final s = m is Map
                                    ? (m['name'] ?? m['displayName'] ?? '')
                                        .toString()
                                        .trim()
                                    : m.toString().trim();
                                if (s.isNotEmpty && !members.contains(s)) {
                                  members.add(s);
                                }
                              }
                            }

                            // Response counts
                            final respData = _contestantResponsesCache[uid] ?? {};
                            final int correct =
                                (respData['correct'] as num?)?.toInt() ?? 0;
                            final int wrong =
                                (respData['wrong'] as num?)?.toInt() ?? 0;
                            int unanswered =
                                (respData['unanswered'] as num?)?.toInt() ?? 0;
                            final int respContested =
                                (respData['contested'] as num?)?.toInt() ?? 0;
                            final int directContested =
                                contestCountByUid[uid] ?? 0;
                            final int contested = directContested > respContested
                                ? directContested
                                : respContested;

                            final int answeredTotal = correct + wrong + unanswered;
                            if (totalQuizQuestions > answeredTotal) {
                              unanswered +=
                                  (totalQuizQuestions - answeredTotal);
                            }

                            final int respTimeMs =
                                (respData['latestTimeMs'] as num?)?.toInt() ?? 0;

                            tallyList.add(
                              ContestantTally(
                                uid: uid,
                                displayName: displayName,
                                teamName: rawTeam,
                                isTeam: isTeam,
                                teamMembers: members,
                                score: score,
                                rank: 1, // Will be computed
                                correctCount: correct,
                                wrongCount: wrong,
                                unansweredCount: unanswered,
                                contestedCount: contested,
                                submissionTimeMs: respTimeMs,
                                isEliminated: isElim,
                                isTied: false,
                              ),
                            );
                          }

                          // 4. Sort and calculate accurate rankings & ties
                          tallyList.sort((a, b) {
                            final scoreDiff = b.score.compareTo(a.score);
                            if (scoreDiff != 0) return scoreDiff;

                            // If tie already resolved
                            if (_tieResolvedUids.contains(a.uid) &&
                                _tieResolvedUids.contains(b.uid)) {
                              if (a.submissionTimeMs > 0 &&
                                  b.submissionTimeMs > 0 &&
                                  a.submissionTimeMs != b.submissionTimeMs) {
                                return a.submissionTimeMs
                                    .compareTo(b.submissionTimeMs);
                              }
                            }

                            return a.effectiveName.compareTo(b.effectiveName);
                          });

                          // Group active contestants by score to identify tied groups
                          final Map<int, List<ContestantTally>> scoreGroups = {};
                          for (final c in tallyList) {
                            if (!c.isEliminated && !_tieResolvedUids.contains(c.uid)) {
                              scoreGroups.putIfAbsent(c.score, () => []).add(c);
                            }
                          }

                          // Assign ranks (same score = same rank unless tie resolved)
                          final List<ContestantTally> rankedList = [];
                          bool hasAnyTie = false;
                          int currentRank = 1;

                          for (int i = 0; i < tallyList.length; i++) {
                            final c = tallyList[i];
                            if (i > 0 && c.score != tallyList[i - 1].score) {
                              currentRank = i + 1;
                            }

                            final isTied = !c.isEliminated &&
                                !_tieResolvedUids.contains(c.uid) &&
                                (scoreGroups[c.score]?.length ?? 0) > 1;

                            if (isTied) {
                              hasAnyTie = true;
                            }

                            rankedList.add(
                              c.copyWith(
                                rank: currentRank,
                                isTied: isTied,
                              ),
                            );
                          }

                          return Column(
                            children: [
                              // Top Summary Banner
                              _buildSummaryBanner(
                                totalContestants: rankedList.length,
                                totalQuestions: totalQuizQuestions,
                                hasAnyTie: hasAnyTie,
                              ),

                              // Table Area (Scrollable)
                              Expanded(
                                child: rankedList.isEmpty
                                    ? const Center(
                                        child: Text(
                                          'No contestants joined yet.',
                                          style: TextStyle(
                                            color: QuizMasterColors.textMuted,
                                            fontSize: 15,
                                          ),
                                        ),
                                      )
                                    : SingleChildScrollView(
                                        padding: const EdgeInsets.fromLTRB(
                                          14,
                                          4,
                                          14,
                                          20,
                                        ),
                                        child: _buildTableCard(rankedList),
                                      ),
                              ),

                              // Bottom Action Bar ("TIE BREAKER" & "FINISH QUIZ")
                              _buildBottomActionBar(
                                rankedList,
                                hasAnyTie: hasAnyTie,
                              ),
                            ],
                          );
                        },
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
  }

  // ============================================================
  // SUMMARY BANNER
  // ============================================================

  Widget _buildSummaryBanner({
    required int totalContestants,
    required int totalQuestions,
    required bool hasAnyTie,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: QuizMasterColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: QuizMasterColors.primaryBlue.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: QuizMasterColors.primaryBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.assessment_rounded,
                  color: QuizMasterColors.primaryBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CONTESTANT FINAL TALLY',
                      style: TextStyle(
                        color: QuizMasterColors.darkBlue,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      '$totalContestants Contestant(s) • ${totalQuestions > 0 ? '$totalQuestions Questions' : 'All Levels'}',
                      style: const TextStyle(
                        color: QuizMasterColors.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Text(
                  widget.isFinal ? 'FINAL ROUND' : 'LEVEL ${widget.level}',
                  style: const TextStyle(
                    color: QuizMasterColors.primaryBlue,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (hasAnyTie) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.balance_rounded,
                    color: Colors.amber.shade900,
                    size: 17,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tie detected in scores! Tap "TIE BREAKER" below to review.',
                      style: TextStyle(
                        color: Colors.amber.shade900,
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // TABLE FORM CARD
  // ============================================================

  Widget _buildTableCard(List<ContestantTally> contestants) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: QuizMasterColors.cardBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: DataTable(
            horizontalMargin: 16,
            columnSpacing: 18,
            headingRowHeight: 46,
            dataRowMinHeight: 56,
            dataRowMaxHeight: 64,
            headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
            border: const TableBorder(
              horizontalInside: BorderSide(
                color: Color(0xFFE2E8F0),
                width: 1,
              ),
            ),
            columns: const [
              DataColumn(
                label: Text(
                  'RANK',
                  style: TextStyle(
                    color: QuizMasterColors.darkBlue,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),
              ),
              DataColumn(
                label: Text(
                  'CONTESTANT',
                  style: TextStyle(
                    color: QuizMasterColors.darkBlue,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),
              ),
              DataColumn(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF16A34A),
                      size: 15,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'CHECK',
                      style: TextStyle(
                        color: Color(0xFF16A34A),
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              DataColumn(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cancel_rounded,
                      color: Color(0xFFDC2626),
                      size: 15,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'WRONG',
                      style: TextStyle(
                        color: Color(0xFFDC2626),
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              DataColumn(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.help_rounded,
                      color: Color(0xFFD97706),
                      size: 15,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'UNANSWERED',
                      style: TextStyle(
                        color: Color(0xFFD97706),
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              DataColumn(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.balance_rounded,
                      color: Color(0xFF7C3AED),
                      size: 15,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'CONTEST',
                      style: TextStyle(
                        color: Color(0xFF7C3AED),
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              DataColumn(
                label: Text(
                  'SCORE',
                  style: TextStyle(
                    color: QuizMasterColors.darkBlue,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
            rows: contestants.map((c) {
              return DataRow(
                color: WidgetStateProperty.resolveWith<Color?>((states) {
                  if (c.rank % 2 == 0) {
                    return const Color(0xFFF8FAFC);
                  }
                  return Colors.white;
                }),
                cells: [
                  // Rank Cell
                  DataCell(_buildRankBadge(c.rank, c.isTied)),

                  // Contestant Cell
                  DataCell(_buildContestantCell(c)),

                  // Check (Correct) Cell
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                      ),
                      child: Text(
                        '✔ ${c.correctCount}',
                        style: const TextStyle(
                          color: Color(0xFF15803D),
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ),

                  // Wrong Cell
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Text(
                        '✖ ${c.wrongCount}',
                        style: const TextStyle(
                          color: Color(0xFFB91C1C),
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ),

                  // Unanswered Cell
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Text(
                        '? ${c.unansweredCount}',
                        style: const TextStyle(
                          color: Color(0xFFB45309),
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ),

                  // Contest Cell
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: c.contestedCount > 0
                            ? const Color(0xFFF3E8FF)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: c.contestedCount > 0
                              ? const Color(0xFFE9D5FF)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Text(
                        '⚖ ${c.contestedCount}',
                        style: TextStyle(
                          color: c.contestedCount > 0
                              ? const Color(0xFF7E22CE)
                              : Colors.black45,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ),

                  // Score Cell
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: QuizMasterColors.primaryBlue.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: QuizMasterColors.primaryBlue.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        '${c.score} pts',
                        style: const TextStyle(
                          color: QuizMasterColors.darkBlue,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildRankBadge(int rank, bool isTied) {
    Color badgeColor;
    Color textColor = Colors.white;
    IconData? trophyIcon;

    if (rank == 1) {
      badgeColor = const Color(0xFFEAB308);
      trophyIcon = Icons.emoji_events_rounded;
    } else if (rank == 2) {
      badgeColor = const Color(0xFF94A3B8);
      trophyIcon = Icons.military_tech_rounded;
    } else if (rank == 3) {
      badgeColor = const Color(0xFFD97706);
      trophyIcon = Icons.workspace_premium_rounded;
    } else {
      badgeColor = const Color(0xFFE2E8F0);
      textColor = QuizMasterColors.darkBlue;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: badgeColor,
            shape: BoxShape.circle,
            boxShadow: [
              if (rank <= 3)
                BoxShadow(
                  color: badgeColor.withValues(alpha: 0.35),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
            ],
          ),
          child: Center(
            child: trophyIcon != null
                ? Icon(trophyIcon, color: Colors.white, size: 16)
                : Text(
                    '$rank',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
          ),
        ),
        if (isTied) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.amber.shade100,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.amber.shade400, width: 0.8),
            ),
            child: Text(
              'TIE',
              style: TextStyle(
                color: Colors.amber.shade900,
                fontSize: 8.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildContestantCell(ContestantTally c) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  c.effectiveName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: QuizMasterColors.darkBlue,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: c.isTeam
                      ? const Color(0xFFEFF6FF)
                      : const Color(0xFFF3E8FF),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: c.isTeam
                        ? const Color(0xFFBFDBFE)
                        : const Color(0xFFE9D5FF),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  c.isTeam ? 'TEAM' : 'SOLO',
                  style: TextStyle(
                    color: c.isTeam
                        ? QuizMasterColors.primaryBlue
                        : const Color(0xFF7E22CE),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (c.isTied) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: const Color(0xFFF59E0B),
                      width: 0.8,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.balance_rounded,
                        size: 10,
                        color: Color(0xFFB45309),
                      ),
                      SizedBox(width: 2.5),
                      Text(
                        'TIE',
                        style: TextStyle(
                          color: Color(0xFFB45309),
                          fontSize: 8.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (c.isTeam && c.teamMembers.isNotEmpty)
            Text(
              'Members: ${c.teamMembers.join(', ')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: QuizMasterColors.textMuted,
                fontSize: 10.5,
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // BOTTOM ACTION BAR ("TIE BREAKER" & "FINISH QUIZ")
  // ============================================================

  Widget _buildBottomActionBar(
    List<ContestantTally> contestants, {
    required bool hasAnyTie,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          top: BorderSide(color: QuizMasterColors.cardBorder, width: 1.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          // TIE BREAKER BUTTON: Only shown if a tie is detected
          if (hasAnyTie) ...[
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () => _handleTieBreaker(contestants),
                  icon: Icon(
                    Icons.balance_rounded,
                    color: Colors.amber.shade900,
                    size: 20,
                  ),
                  label: Text(
                    'TIE BREAKER',
                    style: TextStyle(
                      color: Colors.amber.shade900,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFFBEB),
                    side: BorderSide(color: Colors.amber.shade400, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],

          // FINISH QUIZ BUTTON (or NEXT LEVEL if intermediate)
          Expanded(
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: widget.isFinal
                    ? _confirmFinishQuiz
                    : () {
                        if (widget.onProceedToNextLevel != null) {
                          widget.onProceedToNextLevel!();
                        } else {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute<void>(
                              builder: (_) => FinalRankingScreen(
                                quizCode: widget.quizCode,
                                level: widget.level,
                                isFinal: false,
                              ),
                            ),
                          );
                        }
                      },
                icon: Icon(
                  widget.isFinal
                      ? Icons.emoji_events_rounded
                      : Icons.skip_next_rounded,
                  size: 20,
                ),
                label: Text(
                  widget.isFinal ? 'FINISH QUIZ' : 'LEVEL RESULTS',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: QuizMasterColors.primaryBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
