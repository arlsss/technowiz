import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'technowiz_theme.dart';

class ContestantOverallTallyScreen extends StatefulWidget {
  final String quizCode;
  final int? currentLevel;

  const ContestantOverallTallyScreen({
    super.key,
    required this.quizCode,
    this.currentLevel,
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
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: primaryGreen),
            tooltip: 'Back to Quiz',
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.analytics_rounded, color: primaryGreen, size: 22),
              SizedBox(width: 8),
              Text(
                'OVERALL TALLY',
                style: TextStyle(
                  color: textDark,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 14),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF86EFAC), width: 1.2),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 8, color: primaryGreen),
                  SizedBox(width: 5),
                  Text(
                    'LIVE',
                    style: TextStyle(
                      color: darkGreen,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: sessionRef.snapshots(),
            builder: (context, sessionSnap) {
              final sessionData = sessionSnap.data?.data() ?? {};

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

                        final tiePts = _extractNumber(sData['tieBreakerScore']);
                        int totalScore = levelSum + tiePts;
                        final storedScore = _extractNumber(sData['score'] ?? sData['totalScore']);
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
                                if (myParticipant != null) ...[
                                  _buildMyTallyCard(
                                    myParticipant,
                                    sortedLevels,
                                  ),
                                  const SizedBox(height: 22),
                                ],

                                // ==========================================
                                // ALL CONTESTANTS STANDINGS SECTION
                                // ==========================================
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFDCFCE7),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.leaderboard_rounded,
                                        color: primaryGreen,
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      "ALL CONTESTANTS TALLY",
                                      style: TextStyle(
                                        color: darkGreen,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      "${participants.length} Joined",
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                if (participants.isEmpty)
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
                                  )
                                else
                                  ListView.separated(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: participants.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 10),
                                    itemBuilder: (context, index) {
                                      final item = participants[index];
                                      return _buildParticipantCard(
                                        item,
                                        sortedLevels,
                                      );
                                    },
                                  ),

                                const SizedBox(height: 30),
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
    );
  }

  // ==========================================================
  // MY OVERALL TALLY CARD (Hero Card)
  // ==========================================================
  Widget _buildMyTallyCard(
    _TallyParticipant me,
    List<int> sortedLevels,
  ) {
    final rankStyle = TechRankStyle.forRank(me.rank);

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
          // Top Row: Avatar/Trophy + Name + Rank Badge
          Row(
            children: [
              Tech3DTrophyWidget(
                rank: me.rank,
                size: 50,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            me.name,
                            style: const TextStyle(
                              color: textDark,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            "YOU",
                            style: TextStyle(
                              color: primaryGreen,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (me.isTeam) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEDE9FE),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              "TEAM",
                              style: TextStyle(
                                color: Color(0xFF6D28D9),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (me.isTeam && me.teamMembers.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        "Members: ${me.teamMembers.join(', ')}",
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              // Rank Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: rankStyle.bgColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: rankStyle.borderColor, width: 1.2),
                ),
                child: Text(
                  rankStyle.label,
                  style: TextStyle(
                    color: rankStyle.primaryColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
          const SizedBox(height: 16),

          // Total Score Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                  "${me.totalScore} ${me.totalScore == 1 ? 'PT' : 'PTS'}",
                  style: const TextStyle(
                    color: primaryGreen,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

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
          const SizedBox(height: 10),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final lvl in sortedLevels) ...[
                _buildLevelScoreChip(
                  label: "Level $lvl",
                  points: me.levelPoints[lvl] ?? 0,
                  isHighlighted: true,
                ),
              ],
              if (me.tieBreakerPoints > 0)
                _buildLevelScoreChip(
                  label: "Tie Breaker",
                  points: me.tieBreakerPoints,
                  isTieBreaker: true,
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // LEVEL SCORE CHIP
  // ==========================================================
  Widget _buildLevelScoreChip({
    required String label,
    required int points,
    bool isHighlighted = false,
    bool isTieBreaker = false,
  }) {
    final Color bgColor = isTieBreaker
        ? const Color(0xFFFEF3C7)
        : (isHighlighted ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC));
    final Color borderColor = isTieBreaker
        ? const Color(0xFFFDE68A)
        : (isHighlighted ? const Color(0xFFA7F3D0) : const Color(0xFFE2E8F0));
    final Color textColor = isTieBreaker
        ? const Color(0xFFB45309)
        : (isHighlighted ? const Color(0xFF065F46) : const Color(0xFF334155));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "$label: ",
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            "$points ${points == 1 ? 'pt' : 'pts'}",
            style: TextStyle(
              color: textColor,
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // ALL PARTICIPANTS CARD
  // ==========================================================
  Widget _buildParticipantCard(
    _TallyParticipant item,
    List<int> sortedLevels,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: item.isMe ? const Color(0xFFF0FDF4) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: item.isMe ? primaryGreen : const Color(0xFFE2E8F0),
          width: item.isMe ? 1.8 : 1.0,
        ),
        boxShadow: item.isMe
            ? [
                BoxShadow(
                  color: primaryGreen.withValues(alpha: 0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Rank Badge with 3D Trophy
          Tech3DTrophyWidget(
            rank: item.rank,
            size: 40,
          ),
          const SizedBox(width: 12),

          // Name, Team, and Level Chips
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      item.isTeam
                          ? Icons.groups_rounded
                          : Icons.person_rounded,
                      size: 14,
                      color:
                          item.isMe ? primaryGreen : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        item.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: item.isMe
                              ? primaryGreen
                              : const Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (item.isMe) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Text(
                          "YOU",
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: primaryGreen,
                          ),
                        ),
                      ),
                    ],
                    if (item.isTeam) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEDE9FE),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Text(
                          "TEAM",
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF6D28D9),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),

                if (item.isTeam && item.teamMembers.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    "Members: ${item.teamMembers.join(', ')}",
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                const SizedBox(height: 6),

                // Level points breakdown chips
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final lvl in sortedLevels) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: item.isMe
                              ? const Color(0xFFDCFCE7)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: item.isMe
                                ? const Color(0xFF86EFAC)
                                : const Color(0xFFCBD5E1),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          (item.levelPoints[lvl] ?? 0) == 0
                              ? "L$lvl: 0"
                              : "L$lvl: ${item.levelPoints[lvl] ?? 0} ${(item.levelPoints[lvl] ?? 0) == 1 ? 'pt' : 'pts'}",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: item.isMe
                                ? const Color(0xFF14532D)
                                : const Color(0xFF334155),
                          ),
                        ),
                      ),
                    ],
                    if (item.tieBreakerPoints > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFFFDE68A),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          "TB: +${item.tieBreakerPoints} ${item.tieBreakerPoints == 1 ? 'pt' : 'pts'}",
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Total Score Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: item.isMe ? primaryGreen : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
              boxShadow: item.isMe
                  ? [
                      BoxShadow(
                        color: primaryGreen.withValues(alpha: 0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "${item.totalScore}",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: item.isMe
                        ? Colors.white
                        : const Color(0xFF0F172A),
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.totalScore == 1 ? "PT" : "PTS",
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: item.isMe
                        ? Colors.white70
                        : const Color(0xFF64748B),
                    height: 1.0,
                  ),
                ),
              ],
            ),
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
