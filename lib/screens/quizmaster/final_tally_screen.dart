import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'quizmaster_theme.dart';
import 'quizmaster_dashboard.dart';
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
  final Map<int, int> levelPoints;
  final int? eliminatedLevel;

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
    this.levelPoints = const {},
    this.eliminatedLevel,
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
    Map<int, int>? levelPoints,
    int? eliminatedLevel,
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
      levelPoints: levelPoints ?? this.levelPoints,
      eliminatedLevel: eliminatedLevel ?? this.eliminatedLevel,
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
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _sessionDeletionSubscription;
  bool _isExitingDueToDeletion = false;

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

    _sessionDeletionSubscription = _sessionStream.listen((snapshot) {
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
    _sessionDeletionSubscription?.cancel();
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
        final Map<int, int> levelPoints = {};

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

          // Accumulate points per level
          final rawLvl =
              data['sessionLevel'] ?? data['level'] ?? data['questionLevel'];
          int? lvl;
          if (rawLvl is num) {
            lvl = rawLvl.toInt();
          } else if (rawLvl != null) {
            final match = RegExp(r'(\d+)').firstMatch(rawLvl.toString());
            if (match != null) lvl = int.tryParse(match.group(1)!);
          }
          lvl ??= 1;

          final rawPts = data['points'] ?? data['score'];
          int pts = 0;
          if (rawPts is num) {
            pts = rawPts.toInt();
          } else if (rawPts != null) {
            pts = int.tryParse(rawPts.toString()) ?? 0;
          }
          if (pts == 0 && (answerStatus == 'correct' || rawCorrect == true)) {
            pts = 1;
          }

          if (pts > 0 && (rawCorrect == true || answerStatus == 'correct')) {
            levelPoints[lvl] = (levelPoints[lvl] ?? 0) + pts;
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
              'levelPoints': levelPoints,
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
              'All contestants have distinct scores. No tie-breaker is required!\n\nYou can proceed directly to PUBLISH WINNERS.',
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
                await _handleQuizAgain(tiedEntries);
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

  Future<void> _handleQuizAgain([
    List<MapEntry<int, List<ContestantTally>>>? tiedEntries,
  ]) async {
    final List<String> tiedUids = [];
    final List<String> tiedNames = [];

    if (tiedEntries != null && tiedEntries.isNotEmpty) {
      for (final entry in tiedEntries) {
        for (final c in entry.value) {
          if (!tiedUids.contains(c.uid)) {
            tiedUids.add(c.uid);
            tiedNames.add(c.effectiveName);
          }
        }
      }
    }

    try {
      final batch = FirebaseFirestore.instance.batch();
      final updateData = <String, dynamic>{
        'tieBreakerActive': true,
        'tieBreakerResolved': false,
        'status': 'tie_breaker_invite',
        'questionState': 'waiting',
        'isFinished': false,
        'finished': false,
        'currentQuestion': 0,
        'tieBreakerQuestionIndex': 0,
        'tieBreakerReadyUids': <String>[],
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (tiedUids.isNotEmpty) {
        updateData['tieBreakerContestantUids'] = tiedUids;
        updateData['tieBreakerContestantNames'] = tiedNames;
      }
      batch.set(_sessionRef, updateData, SetOptions(merge: true));

      for (final uid in tiedUids) {
        final reqRef = _sessionRef.collection('join_requests').doc(uid);
        batch.set(reqRef, {
          'tieBreakerReady': false,
          'ready': false,
          'nextQuestionReady': false,
        }, SetOptions(merge: true));
      }

      await batch.commit();
    } catch (e) {
      debugPrint('Error activating tie breaker: $e');
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => QuizControlScreen(
          quizCode: widget.quizCode,
          isTieBreaker: true,
        ),
      ),
    );
  }

  // ============================================================
  // PUBLISH WINNERS ACTION
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
                  'Publish Final Winners?',
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
            'This will finalize the competition results and open the Winners Podium & Final Results screen.\n\nProceed to publish the final winners?',
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
              icon: const Icon(Icons.emoji_events_rounded),
              label: const Text('PUBLISH WINNERS'),
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
      } else {
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
      }

      await QuizMasterNavPersistence.savePage(
        'ranking',
        quizCode: widget.quizCode,
        rankingLevel: widget.level,
        rankingIsFinal: true,
      );

      if (!mounted) return;

      // Navigate to Winners Result (Final Winners page)
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => FinalRankingScreen(
            quizCode: widget.quizCode,
            level: widget.level,
            isFinal: true,
          ),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
    } catch (e) {
      debugPrint('PUBLISH WINNERS ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to publish winners: $e'),
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
        showBackButton: false,
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
                          final Map<String, DocumentSnapshot<Map<String, dynamic>>> scoreDocByUid = {
                            for (final d in scoreDocs) d.id: d,
                          };
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
                            final Map<int, int> levelPoints = {};
                            for (int l = 1; l <= 20; l++) {
                              final v = sData['level${l}Score'] ??
                                  sData['level_$l'] ??
                                  data['level${l}Score'] ??
                                  data['level_$l'];
                              if (v is num && v > 0) {
                                levelPoints[l] = v.toInt();
                              } else if (v != null) {
                                final parsed = int.tryParse(v.toString());
                                if (parsed != null && parsed > 0) {
                                  levelPoints[l] = parsed;
                                }
                              }
                            }
                            if (sData['levelScores'] is Map) {
                              for (final entry in (sData['levelScores'] as Map).entries) {
                                final numStr = entry.key
                                    .toString()
                                    .replaceAll(RegExp(r'[^0-9]'), '');
                                final lvl = int.tryParse(numStr);
                                final val =
                                    int.tryParse(entry.value?.toString() ?? '') ??
                                        0;
                                if (lvl != null && val > 0) {
                                  if ((levelPoints[lvl] ?? 0) < val) {
                                    levelPoints[lvl] = val;
                                  }
                                }
                              }
                            }
                            if (data['levelScores'] is Map) {
                              for (final entry in (data['levelScores'] as Map).entries) {
                                final numStr = entry.key
                                    .toString()
                                    .replaceAll(RegExp(r'[^0-9]'), '');
                                final lvl = int.tryParse(numStr);
                                final val =
                                    int.tryParse(entry.value?.toString() ?? '') ??
                                        0;
                                if (lvl != null && val > 0) {
                                  if ((levelPoints[lvl] ?? 0) < val) {
                                    levelPoints[lvl] = val;
                                  }
                                }
                              }
                            }
                            final cachedResp = _contestantResponsesCache[uid];
                            if (cachedResp != null &&
                                cachedResp['levelPoints'] is Map) {
                              for (final entry
                                  in (cachedResp['levelPoints'] as Map).entries) {
                                final lvl = int.tryParse(entry.key.toString());
                                final val =
                                    int.tryParse(entry.value?.toString() ?? '') ??
                                        0;
                                if (lvl != null && val > 0) {
                                  if ((levelPoints[lvl] ?? 0) < val) {
                                    levelPoints[lvl] = val;
                                  }
                                }
                              }
                            }

                            int lvlSum = 0;
                            for (final pts in levelPoints.values) {
                              lvlSum += pts;
                            }

                            final tiePts = int.tryParse((sData['tieBreakerScore'] ??
                                        data['tieBreakerScore'])
                                    ?.toString() ??
                                '') ??
                                0;

                            final rawScore = sData['score'] ??
                                sData['totalScore'] ??
                                data['score'] ??
                                data['finalScore'];
                            final stored = rawScore is num
                                ? rawScore.toInt()
                                : int.tryParse(rawScore?.toString() ?? '') ?? 0;

                            int score = 0;
                            if (lvlSum > 0) {
                              score = lvlSum + tiePts;
                            } else {
                              score = stored > 0 ? (stored + tiePts) : 0;
                            }

                            // Auto-heal corrupt score in Firestore
                            if (scoreDocByUid[uid] != null &&
                                stored != score &&
                                score > 0) {
                              scoreDocByUid[uid]!.reference.update({
                                'score': score,
                                'totalScore': score,
                              }).catchError((_) {});
                            }

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

                            int? elimLevel;
                            final rawElim = sData['eliminatedLevel'] ??
                                sData['eliminatedAtLevel'] ??
                                sData['decisionLevel'] ??
                                data['eliminatedLevel'] ??
                                data['eliminatedAtLevel'] ??
                                data['decisionLevel'];
                            if (rawElim is num) {
                              elimLevel = rawElim.toInt();
                            } else if (rawElim != null) {
                              elimLevel = int.tryParse(rawElim.toString());
                            }
                            if (isElim && elimLevel == null) {
                              if (levelPoints.isNotEmpty) {
                                elimLevel = levelPoints.keys
                                    .reduce((a, b) => a > b ? a : b);
                              } else {
                                elimLevel = widget.level > 1
                                    ? widget.level - 1
                                    : 1;
                              }
                            }

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
                                levelPoints: levelPoints,
                                eliminatedLevel: elimLevel,
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

                          // Compute maxLevel across session configuration and contestant scores
                          int maxLevel = widget.level;
                          if (sessionData['levelSettings'] is Map) {
                            for (final k in (sessionData['levelSettings'] as Map).keys) {
                              final m = RegExp(r'(\d+)').firstMatch(k.toString());
                              if (m != null) {
                                final lvl = int.tryParse(m.group(1)!);
                                if (lvl != null && lvl > maxLevel) maxLevel = lvl;
                              }
                            }
                          }
                          if (sessionData['levels'] is List) {
                            for (final item in (sessionData['levels'] as List)) {
                              final m = RegExp(r'(\d+)').firstMatch(item.toString());
                              if (m != null) {
                                final lvl = int.tryParse(m.group(1)!);
                                if (lvl != null && lvl > maxLevel) maxLevel = lvl;
                              }
                            }
                          }
                          final rawTotalLevels = sessionData['totalLevels'] ??
                              sessionData['totalLevel'] ??
                              sessionData['currentLevel'];
                          if (rawTotalLevels is num && rawTotalLevels.toInt() > maxLevel) {
                            maxLevel = rawTotalLevels.toInt();
                          }
                          for (final c in rankedList) {
                            for (final lvl in c.levelPoints.keys) {
                              if (lvl > maxLevel) maxLevel = lvl;
                            }
                          }
                          if (maxLevel < 1) maxLevel = 1;

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
                                        child: _buildTableCard(
                                          rankedList,
                                          scoreByUid: scoreByUid,
                                          maxLevel: maxLevel,
                                        ),
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

  int _getContestantLevelScore(
    ContestantTally c,
    int lvl,
    Map<String, dynamic>? sData,
    int maxLevel,
  ) {
    int maxVal = 0;
    if (c.levelPoints.containsKey(lvl)) {
      final p = c.levelPoints[lvl] ?? 0;
      if (p > maxVal) maxVal = p;
    }
    if (sData != null) {
      final levelKey = 'level${lvl}Score';
      final altKey = 'level_$lvl';
      for (final key in [levelKey, altKey]) {
        if (sData.containsKey(key)) {
          final val = sData[key];
          final parsed =
              val is num ? val.toInt() : int.tryParse(val?.toString() ?? '');
          if (parsed != null && parsed > maxVal) maxVal = parsed;
        }
      }
      if (sData['levelScores'] is Map) {
        final map = sData['levelScores'] as Map;
        for (final entry in map.entries) {
          final numStr =
              entry.key.toString().replaceAll(RegExp(r'[^0-9]'), '');
          if (int.tryParse(numStr) == lvl) {
            final val = entry.value;
            final parsed = val is num
                ? val.toInt()
                : int.tryParse(val?.toString() ?? '');
            if (parsed != null && parsed > maxVal) maxVal = parsed;
          }
        }
      }
    }
    if (maxVal > 0) return maxVal;
    if (lvl == 1 && (maxLevel == 1 || c.eliminatedLevel == 1)) {
      return c.score;
    }
    return 0;
  }

  Widget _buildLevelScoreCell(
    ContestantTally c,
    int lvl,
    Map<String, dynamic>? sData,
    int maxLevel,
  ) {
    // Check if contestant was eliminated in an earlier level
    final bool isEliminatedBeforeThisLevel =
        c.isEliminated && c.eliminatedLevel != null && lvl > c.eliminatedLevel!;

    if (isEliminatedBeforeThisLevel) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        alignment: Alignment.center,
        child: const Text(
          '—',
          style: TextStyle(
            color: QuizMasterColors.textMuted,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
      );
    }

    final int pts = _getContestantLevelScore(c, lvl, sData, maxLevel);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: pts > 0 ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: pts > 0 ? const Color(0xFFBBF7D0) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Text(
        pts == 0 ? '0' : '$pts ${pts == 1 ? 'pt' : 'pts'}',
        style: TextStyle(
          color: pts > 0 ? const Color(0xFF15803D) : QuizMasterColors.textMuted,
          fontWeight: FontWeight.w800,
          fontSize: 12.5,
        ),
      ),
    );
  }

  Widget _buildTableCard(
    List<ContestantTally> contestants, {
    required Map<String, Map<String, dynamic>> scoreByUid,
    required int maxLevel,
  }) {
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
            columnSpacing: 20,
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
            columns: [
              const DataColumn(
                label: Text(
                  'RANK',
                  style: TextStyle(
                    color: QuizMasterColors.darkBlue,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),
              ),
              const DataColumn(
                label: Text(
                  'CONTESTANT',
                  style: TextStyle(
                    color: QuizMasterColors.darkBlue,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),
              ),
              for (int lvl = 1; lvl <= maxLevel; lvl++)
                DataColumn(
                  label: Text(
                    'LEVEL $lvl',
                    style: const TextStyle(
                      color: QuizMasterColors.darkBlue,
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              const DataColumn(
                label: Text(
                  'TOTAL SCORE',
                  style: TextStyle(
                    color: QuizMasterColors.darkBlue,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
            rows: contestants.map((c) {
              final sData = scoreByUid[c.uid];
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

                  // Level Score Cells
                  for (int lvl = 1; lvl <= maxLevel; lvl++)
                    DataCell(_buildLevelScoreCell(c, lvl, sData, maxLevel)),

                  // Total Score Cell (strictly accurate sum of displayed levels + tiebreaker)
                  DataCell(
                    Builder(
                      builder: (context) {
                        int rowSum = 0;
                        for (int lvl = 1; lvl <= maxLevel; lvl++) {
                          rowSum +=
                              _getContestantLevelScore(c, lvl, sData, maxLevel);
                        }
                        final tiePts = int.tryParse(
                                sData?['tieBreakerScore']?.toString() ?? '') ??
                            0;
                        final int displayTotal =
                            rowSum > 0 ? (rowSum + tiePts) : c.score;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: QuizMasterColors.primaryBlue
                                .withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: QuizMasterColors.primaryBlue
                                  .withValues(alpha: 0.25),
                            ),
                          ),
                          child: Text(
                            '$displayTotal ${displayTotal == 1 ? 'pt' : 'pts'}',
                            style: const TextStyle(
                              color: QuizMasterColors.darkBlue,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                        );
                      },
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
    Widget badgeWidget;

    if (rank <= 3) {
      final trophyAsset = rank == 1
          ? 'assets/trophies/gold_trophy_3d.jpg'
          : (rank == 2
              ? 'assets/trophies/silver_trophy_3d.jpg'
              : 'assets/trophies/bronze_trophy_3d.jpg');

      final rankColor = rank == 1
          ? const Color(0xFFF59E0B)
          : (rank == 2 ? const Color(0xFF94A3B8) : const Color(0xFFD97706));

      badgeWidget = Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
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
                  rank == 1
                      ? Icons.emoji_events_rounded
                      : (rank == 2
                          ? Icons.military_tech_rounded
                          : Icons.workspace_premium_rounded),
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
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: rankColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                '$rank',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      );
    } else if (rank >= 4 && rank <= 10) {
      const badgeAsset = 'assets/trophies/top10_badge_3d.jpg';
      const rankColor = Color(0xFF22C55E);

      badgeWidget = Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: rankColor, width: 1.8),
              boxShadow: [
                BoxShadow(
                  color: rankColor.withValues(alpha: 0.25),
                  blurRadius: 4,
                  offset: const Offset(0, 1.5),
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                badgeAsset,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.workspace_premium_rounded,
                  size: 18,
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
    } else {
      badgeWidget = Container(
        width: 28,
        height: 28,
        decoration: const BoxDecoration(
          color: Color(0xFFE2E8F0),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            '$rank',
            style: const TextStyle(
              color: QuizMasterColors.darkBlue,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        badgeWidget,
        if (isTied) ...[
          const SizedBox(width: 5),
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
              if (c.isEliminated) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFFFECACA),
                      width: 0.8,
                    ),
                  ),
                  child: const Text(
                    'ELIMINATED',
                    style: TextStyle(
                      color: Color(0xFFDC2626),
                      fontSize: 8.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
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

          // PUBLISH WINNERS BUTTON (or LEVEL RESULTS if intermediate)
          Expanded(
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: widget.isFinal
                    ? _confirmFinishQuiz
                    : () async {
                        if (widget.onProceedToNextLevel != null) {
                          await widget.onProceedToNextLevel!();
                        }
                        if (!mounted) return;
                        Navigator.of(context).pushReplacement(
                          PageRouteBuilder<void>(
                            pageBuilder: (_, _, _) => FinalRankingScreen(
                              quizCode: widget.quizCode,
                              level: widget.level,
                              isFinal: false,
                            ),
                            transitionDuration: Duration.zero,
                            reverseTransitionDuration: Duration.zero,
                          ),
                        );
                      },
                icon: Icon(
                  widget.isFinal
                      ? Icons.emoji_events_rounded
                      : Icons.skip_next_rounded,
                  size: 20,
                ),
                label: Text(
                  widget.isFinal ? 'PUBLISH WINNERS' : 'LEVEL RESULTS',
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
