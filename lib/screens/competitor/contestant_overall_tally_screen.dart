import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'technowiz_theme.dart';

class ContestantOverallTallyScreen extends StatefulWidget {
  final String quizCode;
  final int? currentLevel;
  final bool fromTieBreakerEnd;
  final bool showBackButton;

  const ContestantOverallTallyScreen({
    super.key,
    required this.quizCode,
    this.currentLevel,
    this.fromTieBreakerEnd = false,
    this.showBackButton = false,
  });

  @override
  State<ContestantOverallTallyScreen> createState() =>
      _ContestantOverallTallyScreenState();
}

class _ContestantOverallTallyScreenState
    extends State<ContestantOverallTallyScreen> {
  static const Color primaryGreen = Color(0xFF16A34A);
  static const Color darkGreen = Color(0xFF14532D);
  static const Color lightGreen = Color(0xFFF0FDF4);
  static const Color textDark = Color(0xFF172033);

  String get _currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  int _extractNumber(dynamic val) {
    if (val is num) return val.toInt();
    if (val != null) {
      final p = int.tryParse(val.toString().trim());
      if (p != null) return p;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final sessionRef = FirebaseFirestore.instance
        .collection('quiz_sessions')
        .doc(widget.quizCode);

    return TechCircuitBackground(
      baseColor: lightGreen,
      child: PopScope(
        canPop: widget.showBackButton,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            centerTitle: true,
            automaticallyImplyLeading: false,
            leading: widget.showBackButton
                ? IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: primaryGreen),
                    tooltip: 'Back to Quiz',
                    onPressed: () => Navigator.of(context).pop(),
                  )
                : null,
            title: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.analytics_rounded, color: primaryGreen, size: 22),
                SizedBox(width: 8),
                Text(
                  'FINAL TALLY',
                  style: TextStyle(
                    color: textDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
        ),
        body: SafeArea(
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: sessionRef.snapshots(),
            builder: (context, sessionSnap) {
              final sessionData = sessionSnap.data?.data() ?? {};

              // If Quiz Master starts a Tie Breaker for this contestant, immediately return to Quiz Screen
              final isTieBreakerActive =
                  sessionData['tieBreakerActive'] == true;
              final isTieBreakerEnded =
                  sessionData['tieBreakerEnded'] == true;
              final rawTieUids = sessionData['tieBreakerContestantUids'];
              final List<String> tieBreakerContestantUids = rawTieUids is List
                  ? rawTieUids.map((e) => e.toString()).toList()
                  : <String>[];
              final bool isTiedContestant =
                  tieBreakerContestantUids.contains(_currentUid);

              if (!widget.fromTieBreakerEnd &&
                  isTieBreakerActive &&
                  !isTieBreakerEnded &&
                  isTiedContestant) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                });
              }

              // Determine active levels configured in session
              final Set<int> allLevels = {};
              final rawLevelQuestions = sessionData['levelQuestions'];
              if (rawLevelQuestions is Map) {
                for (final key in rawLevelQuestions.keys) {
                  final m = RegExp(r'(\d+)').firstMatch(key.toString());
                  if (m != null) {
                    final l = int.tryParse(m.group(1)!);
                    if (l != null && l > 0) allLevels.add(l);
                  }
                }
              }
              final rawLevels = sessionData['levels'];
              if (rawLevels is List) {
                for (final lvl in rawLevels) {
                  final m = RegExp(r'(\d+)').firstMatch(lvl.toString());
                  if (m != null) {
                    final l = int.tryParse(m.group(1)!);
                    if (l != null && l > 0) allLevels.add(l);
                  }
                }
              }
              if (allLevels.isEmpty) {
                allLevels.addAll([1, 2, 3]);
              }
              final sortedLevels = allLevels.toList()..sort();

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: sessionRef.collection('join_requests').snapshots(),
                builder: (context, joinSnap) {
                  final joinDocs = joinSnap.data?.docs ?? [];
                  final Map<String, Map<String, dynamic>> joinById = {
                    for (final doc in joinDocs) doc.id: doc.data(),
                  };

                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: sessionRef.collection('scores').snapshots(),
                    builder: (context, scoresSnap) {
                      final scoreDocs = scoresSnap.data?.docs ?? [];
                      final Map<String, Map<String, dynamic>> scoreById = {
                        for (final doc in scoreDocs) doc.id: doc.data(),
                      };

                      final Set<String> allUids = {
                        ...joinById.keys,
                        ...scoreById.keys,
                      };

                      final List<_TallyParticipant> participants = [];

                      for (final uid in allUids) {
                        final jData = joinById[uid] ?? const {};
                        final sData = scoreById[uid] ?? const {};

                        final status = (jData['status'] ?? sData['status'] ?? '')
                            .toString()
                            .trim()
                            .toLowerCase();
                        if (status == 'pending' ||
                            status == 'rejected' ||
                            status == 'declined' ||
                            status == 'left' ||
                            jData['leftQuiz'] == true ||
                            sData['leftQuiz'] == true) {
                          continue;
                        }

                        final rawTeam = (jData['teamName'] ??
                                sData['teamName'] ??
                                '')
                            .toString()
                            .trim();
                        final rawMembers =
                            jData['teamMembers'] ?? sData['teamMembers'] ?? jData['members'];
                        final List<String> teamMembers = [];
                        if (rawMembers is List) {
                          for (final m in rawMembers) {
                            final s = m is Map
                                ? (m['name'] ?? m['displayName'] ?? '').toString().trim()
                                : m.toString().trim();
                            if (s.isNotEmpty && !teamMembers.contains(s)) {
                              teamMembers.add(s);
                            }
                          }
                        }

                        final bool isTeam = jData['isTeam'] == true ||
                            sData['isTeam'] == true ||
                            jData['contestantType'] == 'team' ||
                            rawTeam.isNotEmpty ||
                            teamMembers.isNotEmpty;

                        final personalName = (jData['realName'] ??
                                jData['fullName'] ??
                                jData['displayName'] ??
                                jData['name'] ??
                                sData['name'] ??
                                uid)
                            .toString()
                            .trim();

                        final displayName = isTeam
                            ? (rawTeam.isNotEmpty ? rawTeam : personalName)
                            : personalName;

                        // Extract score breakdown for each level
                        final Map<int, int> levelPoints = {};
                        int levelSum = 0;
                        for (int l = 1; l <= 20; l++) {
                          final dynamic v = sData['level${l}Score'] ??
                              sData['level_$l'] ??
                              (sData['levelScores'] is Map
                                  ? (sData['levelScores']['Level $l'] ??
                                      sData['levelScores']['$l'])
                                  : null);
                          final pts = _extractNumber(v);
                          levelPoints[l] = pts;
                          levelSum += pts;
                        }

                        int tiePts = _extractNumber(sData['tieBreakerScore'] ??
                            sData['tie_breaker_score'] ??
                            sData['tbScore'] ??
                            sData['tieScore'] ??
                            jData['tieBreakerScore'] ??
                            jData['tie_breaker_score']);
                        final storedScore = _extractNumber(sData['score'] ?? sData['totalScore']);
                        if (tiePts == 0 && storedScore > levelSum) {
                          tiePts = storedScore - levelSum;
                        }
                        int totalScore = levelSum + tiePts;
                        if (totalScore == 0 && storedScore > 0) {
                          totalScore = storedScore;
                        }

                        participants.add(_TallyParticipant(
                          uid: uid,
                          name: displayName,
                          isTeam: isTeam,
                          teamName: rawTeam,
                          teamMembers: teamMembers,
                          levelPoints: levelPoints,
                          tieBreakerPoints: tiePts,
                          totalScore: totalScore,
                          isMe: uid == _currentUid,
                        ));
                      }

                      // Sort participants: totalScore desc, tieBreaker desc, name asc
                      participants.sort((a, b) {
                        final s = b.totalScore.compareTo(a.totalScore);
                        if (s != 0) return s;
                        final tb = b.tieBreakerPoints.compareTo(a.tieBreakerPoints);
                        if (tb != 0) return tb;
                        return a.name.compareTo(b.name);
                      });

                      // Assign competition ranks
                      for (int i = 0; i < participants.length; i++) {
                        if (i > 0 &&
                            participants[i].totalScore ==
                                participants[i - 1].totalScore &&
                            participants[i].tieBreakerPoints ==
                                participants[i - 1].tieBreakerPoints) {
                          participants[i].rank = participants[i - 1].rank;
                        } else {
                          participants[i].rank = i + 1;
                        }
                      }

                      // Locate current user
                      _TallyParticipant? myParticipant;
                      for (final p in participants) {
                        if (p.isMe) {
                          myParticipant = p;
                          break;
                        }
                      }

                      return SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 18,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 540),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // ==========================================
                                // CURRENT CONTESTANT HIGHLIGHT CARD
                                // ==========================================
                                if (myParticipant != null)
                                  StreamBuilder<
                                      QuerySnapshot<Map<String, dynamic>>>(
                                    stream: _currentUid.isNotEmpty
                                        ? sessionRef
                                            .collection('answers')
                                            .doc(_currentUid)
                                            .collection('responses')
                                            .snapshots()
                                        : null,
                                    builder: (context, responsesSnap) {
                                      final responseDocs =
                                          responsesSnap.data?.docs ?? [];
                                      final Map<int, int> correctByLevel = {};
                                      final Map<int, int> wrongByLevel = {};
                                      final Map<int, int> contestByLevel = {};
                                      int tbCorrect = 0;
                                      int tbWrong = 0;
                                      int tbContest = 0;
                                      int tbPointsFromResponses = 0;

                                      for (final doc in responseDocs) {
                                        final data = doc.data();
                                        final bool isTb =
                                            data['isTieBreaker'] == true ||
                                                (data['level']
                                                        ?.toString()
                                                        .toLowerCase()
                                                        .contains('tie') ??
                                                    false);

                                        final bool isCorrect =
                                            data['isCorrect'] == true ||
                                                data['answerStatus'] ==
                                                    'correct' ||
                                                data['contestStatus'] ==
                                                    'approved';

                                        final bool isWrong = !isCorrect;

                                        final bool isContest =
                                            (data['contestStatus'] != null &&
                                                    data['contestStatus'] !=
                                                        'none') ||
                                                data['isContested'] == true ||
                                                data['contested'] == true;

                                        if (isTb) {
                                          if (isCorrect) {
                                            tbCorrect++;
                                            final int p = _extractNumber(data['points']);
                                            tbPointsFromResponses += (p > 0 ? p : 1);
                                          }
                                          if (isWrong) tbWrong++;
                                          if (isContest) tbContest++;
                                          continue;
                                        }

                                        int level = 1;
                                        final rawLvl = data['level'] ??
                                            data['sessionLevel'];
                                        if (rawLvl is num) {
                                          level = rawLvl.toInt();
                                        } else if (rawLvl != null) {
                                          final m = RegExp(r'(\d+)')
                                              .firstMatch(rawLvl.toString());
                                          if (m != null) {
                                            final p = int.tryParse(m.group(1)!);
                                            if (p != null) level = p;
                                          }
                                        }

                                        if (isCorrect) {
                                          correctByLevel[level] =
                                              (correctByLevel[level] ?? 0) + 1;
                                        }
                                        if (isWrong) {
                                          wrongByLevel[level] =
                                              (wrongByLevel[level] ?? 0) + 1;
                                        }
                                        if (isContest) {
                                          contestByLevel[level] =
                                              (contestByLevel[level] ?? 0) + 1;
                                        }
                                      }

                                      final int effectiveTbPoints = myParticipant!.tieBreakerPoints > 0
                                          ? myParticipant.tieBreakerPoints
                                          : (tbPointsFromResponses > 0
                                              ? tbPointsFromResponses
                                              : tbCorrect);

                                      return _buildMyTallyCard(
                                        me: myParticipant,
                                        sortedLevels: sortedLevels,
                                        correctByLevel: correctByLevel,
                                        wrongByLevel: wrongByLevel,
                                        contestByLevel: contestByLevel,
                                        tbCorrect: tbCorrect,
                                        tbWrong: tbWrong,
                                        tbContest: tbContest,
                                        effectiveTbPoints: effectiveTbPoints,
                                      );
                                    },
                                  )
                                else
                                  Container(
                                    padding: const EdgeInsets.all(24),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                          color: const Color(0xFFE2E8F0)),
                                    ),
                                    alignment: Alignment.center,
                                    child: const Text(
                                      "No score records yet.",
                                      style: TextStyle(
                                        color: Colors.black54,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),

                                const SizedBox(height: 20),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // MY OVERALL TALLY CARD (Hero Card)
  // ==========================================================
  Widget _buildMyTallyCard({
    required _TallyParticipant me,
    required List<int> sortedLevels,
    required Map<int, int> correctByLevel,
    required Map<int, int> wrongByLevel,
    required Map<int, int> contestByLevel,
    required int tbCorrect,
    required int tbWrong,
    required int tbContest,
    int effectiveTbPoints = 0,
  }) {
    int levelPointsSum = 0;
    for (final pts in me.levelPoints.values) {
      levelPointsSum += pts;
    }
    final int displayedTotal = (me.totalScore < levelPointsSum + effectiveTbPoints)
        ? (levelPointsSum + effectiveTbPoints)
        : me.totalScore;
    final displayName = me.isTeam
        ? (me.teamName.isNotEmpty ? me.teamName : me.name)
        : me.name;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFBBF7D0), width: 1.8),
        boxShadow: [
          BoxShadow(
            color: primaryGreen.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Row: Avatar + Name (with Members if Team)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFDCFCE7), Color(0xFFBBF7D0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF86EFAC),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: primaryGreen.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    me.isTeam ? Icons.groups_rounded : Icons.person_rounded,
                    color: primaryGreen,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(
                            color: textDark,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.2,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFF86EFAC),
                              width: 0.8,
                            ),
                          ),
                          child: const Text(
                            "YOU",
                            style: TextStyle(
                              color: primaryGreen,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        if (me.isTeam)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEDE9FE),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFFDDD6FE),
                                width: 0.8,
                              ),
                            ),
                            child: const Text(
                              "TEAM",
                              style: TextStyle(
                                color: Color(0xFF6D28D9),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (me.isTeam && me.teamMembers.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        "Members: ${me.teamMembers.join(', ')}",
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
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
          const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
          const SizedBox(height: 18),

          // Total Score Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF0FDF4), Color(0xFFDCFCE7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF86EFAC), width: 1.2),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.stars_rounded, color: primaryGreen, size: 24),
                    SizedBox(width: 8),
                    Text(
                      "TOTAL TALLY SCORE",
                      style: TextStyle(
                        color: darkGreen,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
                Text(
                  "$displayedTotal ${displayedTotal == 1 ? 'PT' : 'PTS'}",
                  style: const TextStyle(
                    color: primaryGreen,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Points Breakdown by Level
          Row(
            children: [
              const Icon(Icons.analytics_outlined,
                  size: 16, color: Color(0xFF047857)),
              const SizedBox(width: 6),
              Text(
                "EACH LEVEL POINTS BREAKDOWN",
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          for (final lvl in sortedLevels) ...[
            _buildLevelBreakdownCard(
              title: "Level $lvl",
              points: me.levelPoints[lvl] ?? 0,
              correct: correctByLevel[lvl] ?? 0,
              wrong: wrongByLevel[lvl] ?? 0,
              contest: contestByLevel[lvl] ?? 0,
            ),
            const SizedBox(height: 10),
          ],
          if (effectiveTbPoints > 0 ||
              tbCorrect > 0 ||
              tbWrong > 0 ||
              tbContest > 0) ...[
            _buildLevelBreakdownCard(
              title: "Tie Breaker",
              points: effectiveTbPoints,
              correct: tbCorrect,
              wrong: tbWrong,
              contest: tbContest,
              isTieBreaker: true,
            ),
          ],
        ],
      ),
    );
  }

  // ==========================================================
  // LEVEL BREAKDOWN CARD (Level, Points, Correct, Wrong, Contest)
  // ==========================================================
  Widget _buildLevelBreakdownCard({
    required String title,
    required int points,
    required int correct,
    required int wrong,
    required int contest,
    bool isTieBreaker = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isTieBreaker ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              isTieBreaker ? const Color(0xFFFDE68A) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isTieBreaker
                      ? const Color(0xFFFEF3C7)
                      : const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isTieBreaker
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFF86EFAC),
                    width: 1,
                  ),
                ),
                child: Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    color: isTieBreaker
                        ? const Color(0xFF92400E)
                        : const Color(0xFF14532D),
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Text(
                "$points ${points == 1 ? 'pt' : 'pts'}",
                style: TextStyle(
                  color:
                      isTieBreaker ? const Color(0xFFD97706) : primaryGreen,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // CORRECT
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF86EFAC), width: 1),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          size: 14, color: Color(0xFF16A34A)),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          "$correct Correct",
                          style: const TextStyle(
                            color: Color(0xFF15803D),
                            fontWeight: FontWeight.w800,
                            fontSize: 11.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // WRONG
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFFFCA5A5), width: 1),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.cancel_rounded,
                          size: 14, color: Color(0xFFDC2626)),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          "$wrong Wrong",
                          style: const TextStyle(
                            color: Color(0xFFB91C1C),
                            fontWeight: FontWeight.w800,
                            fontSize: 11.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // CONTEST
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFFFDE68A), width: 1),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.balance_rounded,
                          size: 14, color: Color(0xFFD97706)),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          "$contest Contest",
                          style: const TextStyle(
                            color: Color(0xFFB45309),
                            fontWeight: FontWeight.w800,
                            fontSize: 11.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TallyParticipant {
  final String uid;
  final String name;
  final bool isTeam;
  final String teamName;
  final List<String> teamMembers;
  final Map<int, int> levelPoints;
  final int tieBreakerPoints;
  final int totalScore;
  final bool isMe;
  int rank = 1;

  _TallyParticipant({
    required this.uid,
    required this.name,
    required this.isTeam,
    required this.teamName,
    required this.teamMembers,
    required this.levelPoints,
    required this.tieBreakerPoints,
    required this.totalScore,
    required this.isMe,
  });
}
