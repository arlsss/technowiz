import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Model representing a single competitor badge
class BadgeItem {
  final String id;
  final String title;
  final String subtitle;
  final String description;
  final String requirement;
  final String category; // 'Rankings', 'Mastery', 'Milestones'
  final Color color;
  final IconData icon;
  final String? trophyAsset;
  final bool isUnlocked;
  final int currentProgress;
  final int maxProgress;
  final DateTime? unlockedAt;
  final String? earnedDetails;

  const BadgeItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.requirement,
    required this.category,
    required this.color,
    required this.icon,
    this.trophyAsset,
    required this.isUnlocked,
    required this.currentProgress,
    required this.maxProgress,
    this.unlockedAt,
    this.earnedDetails,
  });

  double get progressRatio => maxProgress > 0
      ? (currentProgress / maxProgress).clamp(0.0, 1.0)
      : (isUnlocked ? 1.0 : 0.0);
}

/// Standalone Badges View embedded inside CompetitorDashboard
class ContestantBadgesView extends StatefulWidget {
  final bool mobile;
  final Widget? mobileHeader;

  const ContestantBadgesView({
    super.key,
    required this.mobile,
    this.mobileHeader,
  });

  @override
  State<ContestantBadgesView> createState() => _ContestantBadgesViewState();
}

class _ContestantBadgesViewState extends State<ContestantBadgesView> {
  static const Color primaryGreen = Color(0xFF16A34A);
  static const Color softBorder = Color(0xFFDCEFE1);
  static const Color textDark = Color(0xFF172033);

  bool _loading = true;
  String? _error;
  String _selectedCategory = 'All'; // 'All', 'Rankings', 'Mastery', 'Milestones', 'Unlocked'

  List<BadgeItem> _badges = [];
  int _totalCompletedQuizzes = 0;
  int _totalPoints = 0;
  int _goldCount = 0;
  int _silverCount = 0;
  int _bronzeCount = 0;
  int _top10Count = 0;

  @override
  void initState() {
    super.initState();
    _loadUserBadges();
  }

  Future<void> _loadUserBadges() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _badges = _buildDefaultBadges();
        });
      }
      return;
    }

    if (mounted && _badges.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final uid = user.uid;

      // 1. Fetch user's manually unlocked badges if stored
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final userData = userDoc.data() ?? {};
      final rawUnlocked = userData['unlockedBadges'];
      final storedBadgeIds = <String>{};
      if (rawUnlocked is List) {
        for (final item in rawUnlocked) {
          final s = item?.toString().trim();
          if (s != null && s.isNotEmpty) storedBadgeIds.add(s);
        }
      }

      // 2. Fetch past quiz sessions to evaluate achievements dynamically
      final quizSessionsSnap = await FirebaseFirestore.instance
          .collection('quiz_sessions')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      int completedQuizzes = 0;
      int totalCumulativeScore = 0;
      int goldTrophies = 0;
      int silverTrophies = 0;
      int bronzeTrophies = 0;
      int top10Finishes = 0;

      bool hasPerfectQuiz = false;
      bool level1Mastered = false;
      bool level2Mastered = false;
      bool level3Mastered = false;
      bool clincherMastered = false;
      int maxStreak = 0;

      for (final sessionDoc in quizSessionsSnap.docs) {
        final scoreDoc =
            await sessionDoc.reference.collection('scores').doc(uid).get();

        if (!scoreDoc.exists) continue;
        final scoreData = scoreDoc.data() ?? {};
        if (scoreData['hiddenFromHistory'] == true) continue;

        completedQuizzes++;
        final score = int.tryParse(scoreData['score']?.toString() ?? '') ?? 0;
        totalCumulativeScore += score;

        final rankRaw = scoreData['rank'];
        final rank = rankRaw is int
            ? rankRaw
            : int.tryParse(rankRaw?.toString() ?? '');

        if (rank == 1) {
          goldTrophies++;
        } else if (rank == 2) {
          silverTrophies++;
        } else if (rank == 3) {
          bronzeTrophies++;
        } else if (rank != null && rank >= 4 && rank <= 10) {
          top10Finishes++;
        }

        // Fetch user responses for mastery & streak checks (limit checking to active sessions)
        try {
          final responsesSnap = await sessionDoc.reference
              .collection('answers')
              .doc(uid)
              .collection('responses')
              .get();

          if (responsesSnap.docs.isNotEmpty) {
            int qTotal = responsesSnap.docs.length;
            int qCorrect = 0;
            int currentStreak = 0;

            final lvl1Total = <bool>[];
            final lvl2Total = <bool>[];
            final lvl3Total = <bool>[];

            for (final rDoc in responsesSnap.docs) {
              final rData = rDoc.data();
              final isCorrect = rData['isCorrect'] == true ||
                  rData['answerStatus'] == 'correct';

              if (isCorrect) {
                qCorrect++;
                currentStreak++;
                if (currentStreak > maxStreak) {
                  maxStreak = currentStreak;
                }
              } else {
                currentStreak = 0;
              }

              final levelVal = rData['level']?.toString().toLowerCase() ?? '';
              if (levelVal.contains('1') || levelVal.contains('easy')) {
                lvl1Total.add(isCorrect);
              } else if (levelVal.contains('2') || levelVal.contains('moderate')) {
                lvl2Total.add(isCorrect);
              } else if (levelVal.contains('3') || levelVal.contains('difficult')) {
                lvl3Total.add(isCorrect);
              } else if (levelVal.contains('4') || levelVal.contains('clincher')) {
                if (isCorrect) clincherMastered = true;
              }
            }

            if (qTotal >= 3 && qCorrect == qTotal) {
              hasPerfectQuiz = true;
            }

            if (lvl1Total.isNotEmpty && lvl1Total.every((c) => c)) {
              level1Mastered = true;
            }
            if (lvl2Total.isNotEmpty && lvl2Total.every((c) => c)) {
              level2Mastered = true;
            }
            if (lvl3Total.isNotEmpty && lvl3Total.every((c) => c)) {
              level3Mastered = true;
            }
          }
        } catch (_) {}
      }

      final podiumTotal = goldTrophies + silverTrophies + bronzeTrophies;

      // 3. Assemble all 14 badges with real-time unlock status
      final computedBadges = <BadgeItem>[
        // --- RANKINGS & TROPHIES ---
        BadgeItem(
          id: 'champion_gold',
          title: 'Champion',
          subtitle: 'Gold Trophy Winner',
          category: 'Rankings',
          description:
              'Finished Rank #1 as the official Champion in a TechNoWiz competition.',
          requirement: 'Win 1st place in any official quiz tournament.',
          color: const Color(0xFFEAB308),
          icon: Icons.emoji_events_rounded,
          trophyAsset: 'assets/trophies/gold_trophy_3d.jpg',
          isUnlocked: goldTrophies > 0 || storedBadgeIds.contains('champion_gold'),
          currentProgress: goldTrophies > 0 ? 1 : 0,
          maxProgress: 1,
          earnedDetails: goldTrophies > 0 ? '$goldTrophies Gold Won' : null,
        ),
        BadgeItem(
          id: 'runner_up_silver',
          title: '1st Runner-Up',
          subtitle: 'Silver Trophy Winner',
          category: 'Rankings',
          description:
              'Finished Rank #2 as the 1st Runner-Up in an official quiz session.',
          requirement: 'Win 2nd place in any official quiz tournament.',
          color: const Color(0xFF94A3B8),
          icon: Icons.emoji_events_rounded,
          trophyAsset: 'assets/trophies/silver_trophy_3d.jpg',
          isUnlocked: silverTrophies > 0 || storedBadgeIds.contains('runner_up_silver'),
          currentProgress: silverTrophies > 0 ? 1 : 0,
          maxProgress: 1,
          earnedDetails: silverTrophies > 0 ? '$silverTrophies Silver Won' : null,
        ),
        BadgeItem(
          id: 'bronze_finisher',
          title: '2nd Runner-Up',
          subtitle: 'Bronze Trophy Winner',
          category: 'Rankings',
          description:
              'Finished Rank #3 as the 2nd Runner-Up on the official podium.',
          requirement: 'Win 3rd place in any official quiz tournament.',
          color: const Color(0xFFD97706),
          icon: Icons.emoji_events_rounded,
          trophyAsset: 'assets/trophies/bronze_trophy_3d.jpg',
          isUnlocked: bronzeTrophies > 0 || storedBadgeIds.contains('bronze_finisher'),
          currentProgress: bronzeTrophies > 0 ? 1 : 0,
          maxProgress: 1,
          earnedDetails: bronzeTrophies > 0 ? '$bronzeTrophies Bronze Won' : null,
        ),
        BadgeItem(
          id: 'top10_elite',
          title: 'Top 10 Finisher',
          subtitle: 'Official Top 10 Medal',
          category: 'Rankings',
          description:
              'Secured a spot among the elite Top 10 finalists of a quiz tournament.',
          requirement: 'Finish within Rank 4 to 10 in any official quiz competition.',
          color: const Color(0xFF16A34A),
          icon: Icons.workspace_premium_rounded,
          trophyAsset: 'assets/trophies/top10_badge_3d.jpg',
          isUnlocked: (podiumTotal + top10Finishes) > 0 ||
              storedBadgeIds.contains('top10_elite'),
          currentProgress: (podiumTotal + top10Finishes) > 0 ? 1 : 0,
          maxProgress: 1,
          earnedDetails: (podiumTotal + top10Finishes) > 0
              ? '${podiumTotal + top10Finishes} Top 10 Finishes'
              : null,
        ),
        BadgeItem(
          id: 'podium_regular',
          title: 'Podium Regular',
          subtitle: 'Double Podium Finish',
          category: 'Rankings',
          description:
              'Proven consistency by reaching the Top 3 podium across 2 different quizzes.',
          requirement: 'Reach Rank 1, 2, or 3 in at least 2 quizzes.',
          color: const Color(0xFF7C3AED),
          icon: Icons.military_tech_rounded,
          isUnlocked: podiumTotal >= 2 || storedBadgeIds.contains('podium_regular'),
          currentProgress: podiumTotal.clamp(0, 2),
          maxProgress: 2,
          earnedDetails: podiumTotal >= 2 ? '$podiumTotal Podiums' : null,
        ),

        // --- ACCURACY & MASTERY ---
        BadgeItem(
          id: 'flawless_victory',
          title: 'Flawless Score',
          subtitle: '100% Quiz Accuracy',
          category: 'Mastery',
          description:
              'Completed a quiz with a perfect score and zero incorrect answers.',
          requirement: 'Score 100% correct in any full quiz tournament.',
          color: const Color(0xFF0284C7),
          icon: Icons.verified_rounded,
          isUnlocked: hasPerfectQuiz || storedBadgeIds.contains('flawless_victory'),
          currentProgress: hasPerfectQuiz ? 1 : 0,
          maxProgress: 1,
          earnedDetails: hasPerfectQuiz ? 'Perfect Accuracy' : null,
        ),
        BadgeItem(
          id: 'easy_breezy',
          title: 'Easy Breezy',
          subtitle: 'Level 1 Specialist',
          category: 'Mastery',
          description:
              'Mastered all Easy (Level 1) questions without a single mistake.',
          requirement: 'Score 100% on all Level 1 questions in a quiz.',
          color: const Color(0xFF16A34A),
          icon: Icons.bolt_rounded,
          isUnlocked: level1Mastered || storedBadgeIds.contains('easy_breezy'),
          currentProgress: level1Mastered ? 1 : 0,
          maxProgress: 1,
          earnedDetails: level1Mastered ? 'Level 1 Perfect' : null,
        ),
        BadgeItem(
          id: 'moderate_master',
          title: 'Moderate Master',
          subtitle: 'Level 2 Specialist',
          category: 'Mastery',
          description:
              'Conquered all Moderate (Level 2) questions with flawless precision.',
          requirement: 'Score 100% on all Level 2 questions in a quiz.',
          color: const Color(0xFFD97706),
          icon: Icons.psychology_rounded,
          isUnlocked: level2Mastered || storedBadgeIds.contains('moderate_master'),
          currentProgress: level2Mastered ? 1 : 0,
          maxProgress: 1,
          earnedDetails: level2Mastered ? 'Level 2 Perfect' : null,
        ),
        BadgeItem(
          id: 'difficult_conqueror',
          title: 'Difficult Conqueror',
          subtitle: 'Level 3 Specialist',
          category: 'Mastery',
          description:
              'Triumphed over the hardest Level 3 questions in TechNoWiz.',
          requirement: 'Score 100% on all Level 3 questions in a quiz.',
          color: const Color(0xFFDC2626),
          icon: Icons.stars_rounded,
          isUnlocked: level3Mastered || storedBadgeIds.contains('difficult_conqueror'),
          currentProgress: level3Mastered ? 1 : 0,
          maxProgress: 1,
          earnedDetails: level3Mastered ? 'Level 3 Perfect' : null,
        ),
        BadgeItem(
          id: 'clincher_survivor',
          title: 'Clincher Clutch',
          subtitle: 'Tie-Breaker Survivor',
          category: 'Mastery',
          description:
              'Held nerve under extreme pressure and answered a Clincher question correctly.',
          requirement: 'Correctly answer a Clincher / Tie-breaker round question.',
          color: const Color(0xFF9333EA),
          icon: Icons.flash_on_rounded,
          isUnlocked: clincherMastered || storedBadgeIds.contains('clincher_survivor'),
          currentProgress: clincherMastered ? 1 : 0,
          maxProgress: 1,
          earnedDetails: clincherMastered ? 'Clutch Win' : null,
        ),

        // --- MILESTONES & PARTICIPATION ---
        BadgeItem(
          id: 'tech_novice',
          title: 'First Blood',
          subtitle: 'Quiz Competitor Debut',
          category: 'Milestones',
          description:
              'Completed your very first official TechNoWiz quiz competition.',
          requirement: 'Participate and complete 1 official quiz.',
          color: const Color(0xFF059669),
          icon: Icons.flag_rounded,
          isUnlocked: completedQuizzes >= 1 || storedBadgeIds.contains('tech_novice'),
          currentProgress: completedQuizzes.clamp(0, 1),
          maxProgress: 1,
          earnedDetails: completedQuizzes >= 1 ? 'Debut Completed' : null,
        ),
        BadgeItem(
          id: 'streak_master',
          title: 'On Fire',
          subtitle: '5-Answer Win Streak',
          category: 'Milestones',
          description:
              'Answered 5 questions in a row correctly without making any mistakes.',
          requirement: 'Achieve a continuous streak of 5 correct answers.',
          color: const Color(0xFFEA580C),
          icon: Icons.local_fire_department_rounded,
          isUnlocked: maxStreak >= 5 || storedBadgeIds.contains('streak_master'),
          currentProgress: maxStreak.clamp(0, 5),
          maxProgress: 5,
          earnedDetails: maxStreak >= 5 ? '$maxStreak Streak' : null,
        ),
        BadgeItem(
          id: 'quiz_veteran',
          title: 'Quiz Veteran',
          subtitle: '3 Competitions Completed',
          category: 'Milestones',
          description:
              'Demonstrated commitment by participating in 3 full quiz sessions.',
          requirement: 'Complete at least 3 quiz competitions.',
          color: const Color(0xFF2563EB),
          icon: Icons.shield_rounded,
          isUnlocked: completedQuizzes >= 3 || storedBadgeIds.contains('quiz_veteran'),
          currentProgress: completedQuizzes.clamp(0, 3),
          maxProgress: 3,
          earnedDetails: completedQuizzes >= 3 ? '$completedQuizzes Quizzes' : null,
        ),
        BadgeItem(
          id: 'point_collector',
          title: 'Point Collector',
          subtitle: '25+ Career Points',
          category: 'Milestones',
          description:
              'Accumulated an impressive total of 25 or more points in your career.',
          requirement: 'Earn 25 total cumulative points across all quizzes.',
          color: const Color(0xFFCA8A04),
          icon: Icons.monetization_on_rounded,
          isUnlocked:
              totalCumulativeScore >= 25 || storedBadgeIds.contains('point_collector'),
          currentProgress: totalCumulativeScore.clamp(0, 25),
          maxProgress: 25,
          earnedDetails: totalCumulativeScore >= 25 ? '$totalCumulativeScore pts' : null,
        ),
      ];

      // Automatically sync newly earned badges to user's profile doc in background
      final newlyUnlockedIds = computedBadges
          .where((b) => b.isUnlocked && !storedBadgeIds.contains(b.id))
          .map((b) => b.id)
          .toList();

      if (newlyUnlockedIds.isNotEmpty) {
        try {
          await FirebaseFirestore.instance.collection('users').doc(uid).set({
            'unlockedBadges': FieldValue.arrayUnion(newlyUnlockedIds),
          }, SetOptions(merge: true));
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _badges = computedBadges;
          _totalCompletedQuizzes = completedQuizzes;
          _totalPoints = totalCumulativeScore;
          _goldCount = goldTrophies;
          _silverCount = silverTrophies;
          _bronzeCount = bronzeTrophies;
          _top10Count = top10Finishes;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error loading badges: $e';
          _badges = _buildDefaultBadges();
          _loading = false;
        });
      }
    }
  }

  List<BadgeItem> _buildDefaultBadges() {
    return [
      const BadgeItem(
        id: 'champion_gold',
        title: 'Champion',
        subtitle: 'Gold Trophy Winner',
        category: 'Rankings',
        description: 'Finish Rank #1 as the Champion in a competition.',
        requirement: 'Win 1st place in any official quiz.',
        color: Color(0xFFEAB308),
        icon: Icons.emoji_events_rounded,
        trophyAsset: 'assets/trophies/gold_trophy_3d.jpg',
        isUnlocked: false,
        currentProgress: 0,
        maxProgress: 1,
      ),
      const BadgeItem(
        id: 'runner_up_silver',
        title: '1st Runner-Up',
        subtitle: 'Silver Trophy Winner',
        category: 'Rankings',
        description: 'Finish Rank #2 in an official quiz session.',
        requirement: 'Win 2nd place in any official quiz.',
        color: Color(0xFF94A3B8),
        icon: Icons.emoji_events_rounded,
        trophyAsset: 'assets/trophies/silver_trophy_3d.jpg',
        isUnlocked: false,
        currentProgress: 0,
        maxProgress: 1,
      ),
      const BadgeItem(
        id: 'bronze_finisher',
        title: '2nd Runner-Up',
        subtitle: 'Bronze Trophy Winner',
        category: 'Rankings',
        description: 'Finish Rank #3 on the official podium.',
        requirement: 'Win 3rd place in any official quiz.',
        color: Color(0xFFD97706),
        icon: Icons.emoji_events_rounded,
        trophyAsset: 'assets/trophies/bronze_trophy_3d.jpg',
        isUnlocked: false,
        currentProgress: 0,
        maxProgress: 1,
      ),
      const BadgeItem(
        id: 'top10_elite',
        title: 'Top 10 Finisher',
        subtitle: 'Official Top 10 Medal',
        category: 'Rankings',
        description: 'Finish within Rank 4 to 10 in any competition.',
        requirement: 'Finish in the Top 10 of any quiz.',
        color: Color(0xFF16A34A),
        icon: Icons.workspace_premium_rounded,
        trophyAsset: 'assets/trophies/top10_badge_3d.jpg',
        isUnlocked: false,
        currentProgress: 0,
        maxProgress: 1,
      ),
      const BadgeItem(
        id: 'tech_novice',
        title: 'First Blood',
        subtitle: 'Debut Competitor',
        category: 'Milestones',
        description: 'Complete your first official TechNoWiz quiz.',
        requirement: 'Complete 1 official quiz.',
        color: Color(0xFF059669),
        icon: Icons.flag_rounded,
        isUnlocked: false,
        currentProgress: 0,
        maxProgress: 1,
      ),
      const BadgeItem(
        id: 'flawless_victory',
        title: 'Flawless Score',
        subtitle: '100% Accuracy',
        category: 'Mastery',
        description: 'Complete a quiz with 100% accuracy.',
        requirement: 'Get zero wrong answers in a full quiz.',
        color: Color(0xFF0284C7),
        icon: Icons.verified_rounded,
        isUnlocked: false,
        currentProgress: 0,
        maxProgress: 1,
      ),
    ];
  }

  void _showBadgeDetailsModal(BadgeItem badge) {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: badge.color.withValues(alpha: 0.22),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
              border: Border.all(
                color: badge.isUnlocked
                    ? badge.color.withValues(alpha: 0.35)
                    : softBorder,
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Trophy or Big Badge Icon Showcase
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: badge.isUnlocked
                          ? [
                              badge.color.withValues(alpha: 0.18),
                              badge.color.withValues(alpha: 0.05),
                            ]
                          : [const Color(0xFFF1F5F9), const Color(0xFFE2E8F0)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: badge.isUnlocked
                          ? badge.color.withValues(alpha: 0.5)
                          : const Color(0xFFCBD5E1),
                      width: 2.5,
                    ),
                  ),
                  child: Center(
                    child: badge.trophyAsset != null
                        ? ClipOval(
                            child: Image.asset(
                              badge.trophyAsset!,
                              width: 95,
                              height: 95,
                              fit: BoxFit.cover,
                              color: badge.isUnlocked
                                  ? null
                                  : const Color(0x9971717A),
                              colorBlendMode: badge.isUnlocked
                                  ? null
                                  : BlendMode.saturation,
                            ),
                          )
                        : Icon(
                            badge.icon,
                            size: 52,
                            color: badge.isUnlocked
                                ? badge.color
                                : const Color(0xFF94A3B8),
                          ),
                  ),
                ),
                const SizedBox(height: 18),

                // Status pill
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: badge.isUnlocked
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: badge.isUnlocked
                          ? const Color(0xFF86EFAC)
                          : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        badge.isUnlocked
                            ? Icons.check_circle_rounded
                            : Icons.lock_outline_rounded,
                        size: 15,
                        color: badge.isUnlocked
                            ? primaryGreen
                            : const Color(0xFF64748B),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        badge.isUnlocked ? 'UNLOCKED' : 'LOCKED',
                        style: TextStyle(
                          color: badge.isUnlocked
                              ? const Color(0xFF15803D)
                              : const Color(0xFF64748B),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Title & Subtitle
                Text(
                  badge.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  badge.subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: badge.color,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),

                // Description Box
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ABOUT THIS BADGE',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        badge.description,
                        style: const TextStyle(
                          color: textDark,
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'HOW TO UNLOCK',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        badge.requirement,
                        style: TextStyle(
                          color: badge.isUnlocked
                              ? const Color(0xFF15803D)
                              : textDark,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Progress Bar
                if (!badge.isUnlocked && badge.maxProgress > 1) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Progress',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${badge.currentProgress} / ${badge.maxProgress}',
                        style: TextStyle(
                          fontSize: 12,
                          color: badge.color,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: badge.progressRatio,
                      backgroundColor: const Color(0xFFE2E8F0),
                      valueColor: AlwaysStoppedAnimation<Color>(badge.color),
                      minHeight: 7,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Close Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Awesome',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final unlockedCount = _badges.where((b) => b.isUnlocked).length;
    final totalCount = _badges.length;
    final rankingsCount = _badges.where((b) => b.category == 'Rankings').length;
    final masteryCount = _badges.where((b) => b.category == 'Mastery').length;
    final milestonesCount = _badges.where((b) => b.category == 'Milestones').length;
    final unlockedRatio =
        totalCount > 0 ? (unlockedCount / totalCount).clamp(0.0, 1.0) : 0.0;

    final filteredBadges = _badges.where((b) {
      if (_selectedCategory == 'All') return true;
      if (_selectedCategory == 'Unlocked') return b.isUnlocked;
      return b.category == _selectedCategory;
    }).toList();

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        widget.mobile ? 18 : 30,
        widget.mobile ? 20 : 28,
        widget.mobile ? 18 : 30,
        35,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.mobile && widget.mobileHeader != null) ...[
                widget.mobileHeader!,
                const SizedBox(height: 20),
              ],

              // Badges Hero Header Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF14532D), Color(0xFF16A34A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: primaryGreen.withValues(alpha: 0.28),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.workspace_premium_rounded,
                                  color: Colors.white,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Competitor Badges',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Unlock trophies and achievements',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
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
                        ),
                        const SizedBox(width: 6),
                        // Refresh Button
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                          tooltip: 'Refresh Badges',
                          onPressed: _loadUserBadges,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Progress Overview
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$unlockedCount of $totalCount Badges Unlocked',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${(unlockedRatio * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                            color: Color(0xFFFDE047), // Gold
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: unlockedRatio,
                        backgroundColor: Colors.white.withValues(alpha: 0.22),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFFFDE047),
                        ),
                        minHeight: 9,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Mini Stats Strip
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildMiniStat(
                            '🏆 Trophies',
                            _top10Count > 0
                                ? '$_goldCount G • $_silverCount S • $_bronzeCount B • $_top10Count Top 10'
                                : '$_goldCount G • $_silverCount S • $_bronzeCount B',
                          ),
                          Container(width: 1, height: 24, color: Colors.white24),
                          _buildMiniStat('🎯 Quizzes', '$_totalCompletedQuizzes Done'),
                          Container(width: 1, height: 24, color: Colors.white24),
                          _buildMiniStat('⭐ Career', '$_totalPoints pts'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Category Filter Tabs (Straight single line, smoothly swipeable)
              ScrollConfiguration(
                behavior: const _SwipeableScrollBehavior(),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(right: 20, top: 2, bottom: 4),
                  child: Row(
                    children: [
                      _buildCategoryFilterChip('All', Icons.grid_view_rounded, totalCount),
                      const SizedBox(width: 8),
                      _buildCategoryFilterChip('Rankings', Icons.emoji_events_rounded, rankingsCount),
                      const SizedBox(width: 8),
                      _buildCategoryFilterChip('Mastery', Icons.psychology_rounded, masteryCount),
                      const SizedBox(width: 8),
                      _buildCategoryFilterChip('Milestones', Icons.military_tech_rounded, milestonesCount),
                      const SizedBox(width: 8),
                      _buildCategoryFilterChip('Unlocked', Icons.check_circle_outline_rounded, unlockedCount),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Loading or Error State
              if (_loading) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: CircularProgressIndicator(color: primaryGreen),
                  ),
                ),
              ] else if (_error != null && _badges.isEmpty) ...[
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                ),
              ] else ...[
                // Badges Grid
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final crossAxisCount = width > 900
                        ? 4
                        : (width > 600 ? 3 : 2);
                    final childAspectRatio = width < 360
                        ? 0.68
                        : (width < 600 ? 0.73 : 0.85);

                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: childAspectRatio,
                      ),
                      itemCount: filteredBadges.length,
                      itemBuilder: (context, index) {
                        final badge = filteredBadges[index];
                        return _buildBadgeCard(badge);
                      },
                    );
                  },
                ),
              ],

              const SizedBox(height: 30),
              const Center(
                child: Text(
                  'TechNoWiz • Badges & Achievements',
                  style: TextStyle(color: Colors.black26, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilterChip(String category, IconData icon, [int? count]) {
    final active = _selectedCategory == category;
    final compact = widget.mobile;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        setState(() {
          _selectedCategory = category;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 13,
          vertical: compact ? 6 : 7.5,
        ),
        decoration: BoxDecoration(
          color: active ? primaryGreen : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? primaryGreen : softBorder,
            width: 1.5,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: primaryGreen.withValues(alpha: 0.22),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: compact ? 13 : 14.5,
              color: active ? Colors.white : const Color(0xFF64748B),
            ),
            const SizedBox(width: 4.5),
            Text(
              count != null ? '$category ($count)' : category,
              style: TextStyle(
                color: active ? Colors.white : textDark,
                fontSize: compact ? 11.5 : 12.5,
                fontWeight: active ? FontWeight.bold : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadgeCard(BadgeItem badge) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _showBadgeDetailsModal(badge),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: badge.isUnlocked
                ? badge.color.withValues(alpha: 0.5)
                : softBorder,
            width: badge.isUnlocked ? 1.8 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: badge.isUnlocked
                  ? badge.color.withValues(alpha: 0.14)
                  : Colors.black.withValues(alpha: 0.03),
              blurRadius: badge.isUnlocked ? 12 : 6,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Badge / Trophy Icon with Unlocked Glow or Locked Dim
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: badge.isUnlocked
                          ? [
                              badge.color.withValues(alpha: 0.2),
                              badge.color.withValues(alpha: 0.05),
                            ]
                          : [const Color(0xFFF1F5F9), const Color(0xFFE2E8F0)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Center(
                    child: badge.trophyAsset != null
                        ? ClipOval(
                            child: Image.asset(
                              badge.trophyAsset!,
                              width: 64,
                              height: 64,
                              fit: BoxFit.cover,
                              color: badge.isUnlocked
                                  ? null
                                  : const Color(0x9964748B),
                              colorBlendMode: badge.isUnlocked
                                  ? null
                                  : BlendMode.saturation,
                            ),
                          )
                        : Icon(
                            badge.icon,
                            size: 36,
                            color: badge.isUnlocked
                                ? badge.color
                                : const Color(0xFF94A3B8),
                          ),
                  ),
                ),
                // Lock overlay if locked
                if (!badge.isUnlocked)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF64748B),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.lock_rounded,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // Badge Title
            Text(
              badge.title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: badge.isUnlocked ? textDark : const Color(0xFF64748B),
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),

            // Badge Subtitle
            Text(
              badge.subtitle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: badge.isUnlocked
                    ? badge.color
                    : const Color(0xFF94A3B8),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),

            // Unlock Tag or Progress Bar
            if (badge.isUnlocked) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_rounded,
                      size: 11,
                      color: Color(0xFF15803D),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      badge.earnedDetails ?? 'Earned',
                      maxLines: 1,
                      style: const TextStyle(
                        color: Color(0xFF15803D),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: badge.progressRatio,
                    backgroundColor: const Color(0xFFE2E8F0),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      badge.color.withValues(alpha: 0.6),
                    ),
                    minHeight: 4,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SwipeableScrollBehavior extends MaterialScrollBehavior {
  const _SwipeableScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}
