import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'competitor_dashboard.dart';
import 'technowiz_theme.dart';
import 'quiz_history_score_screen.dart';
import 'quiz_screen.dart';

class MyScoreScreen extends StatefulWidget {
  final String quizCode;

  const MyScoreScreen({super.key, required this.quizCode});

  @override
  State<MyScoreScreen> createState() => _MyScoreScreenState();
}

class _MyScoreScreenState extends State<MyScoreScreen> {
  static const Color primaryGreen = Color(0xFF16A34A);
  static const Color darkGreen = Color(0xFF14532D);
  static const Color lightGreen = Color(0xFFF0FDF4);
  static const Color borderGreen = Color(0xFFDCEFE1);
  static const Color textDark = Color(0xFF172033);

  @override
  void initState() {
    super.initState();
    _saveCurrentState();
  }

  Future<void> _saveCurrentState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('contestant_last_page', 'my_score');
    await prefs.setString('contestant_current_quiz_code', widget.quizCode);
  }

  Future<void> _onExitScreen() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getString('contestant_last_page');
    if (current == 'my_score') {
      await prefs.setString('contestant_last_page', 'history');
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
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
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: primaryGreen),
            onPressed: () async {
              await _onExitScreen();
              if (!context.mounted) return;
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              } else {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const CompetitorDashboard(initialPage: 'history')),
                );
              }
            },
          ),
          iconTheme: const IconThemeData(color: primaryGreen),
          title: const Text(
            "My Score",
            style: TextStyle(color: textDark, fontWeight: FontWeight.bold),
          ),
        ),
        body: PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) {
              await _onExitScreen();
            }
          },
          child: SafeArea(
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: sessionRef.snapshots(),
              builder: (context, sessionSnap) {
                final sessionData = sessionSnap.data?.data() ?? {};
                final status =
                    sessionData['status']?.toString().trim().toLowerCase() ?? '';
                final isFinished =
                    status == 'finished' ||
                    status == 'completed' ||
                    status == 'ended';
                final quizTitle =
                    sessionData['title']?.toString().trim().isNotEmpty == true
                    ? sessionData['title'].toString().trim()
                    : '';

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: sessionRef.collection('scores').snapshots(),
                  builder: (context, scoreSnap) {
                    if (!scoreSnap.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(color: primaryGreen),
                      );
                    }

                    int liveScore = 0;
                    int? liveRank;
                    final scores = scoreSnap.data!.docs;

                    final userScoreDoc = scores
                        .where((d) => d.id == uid)
                        .firstOrNull;

                    if (userScoreDoc != null) {
                      final data = userScoreDoc.data();
                      liveScore = data['score'] ?? 0;
                      liveRank = data['rank'];
                    }

                    final sortedScores = scores.toList()
                      ..sort(
                        (a, b) => ((b.data()['score'] ?? 0) as int).compareTo(
                          (a.data()['score'] ?? 0) as int,
                        ),
                      );

                    if (liveRank == null && uid != null) {
                      final index = sortedScores.indexWhere((d) => d.id == uid);
                      if (index != -1) liveRank = index + 1;
                    }

                    final rankStyle = TechRankStyle.forRank(liveRank);
                    final placementTitle = rankStyle.label;
                    final rankTitle = liveRank == 1
                        ? "CONGRATULATIONS!"
                        : liveRank == 2
                        ? "EXCELLENT EFFORT!"
                        : liveRank == 3
                        ? "GREAT ACHIEVEMENT!"
                        : (liveRank != null && liveRank <= 10)
                        ? "TOP 10 FINISHER!"
                        : (isFinished ? "QUIZ FINISHED!" : "MY SCORE");

                    final rankSubtitle = liveRank == 1
                        ? "You finished at Rank #1 (Champion - Gold Trophy)!"
                        : liveRank == 2
                        ? "You finished at Rank #2 (Silver Trophy)!"
                        : liveRank == 3
                        ? "You finished at Rank #3 (Bronze Trophy)!"
                        : (liveRank != null && liveRank <= 10)
                        ? "You earned the Top 10 Badge at Rank #$liveRank!"
                        : (quizTitle.isNotEmpty
                              ? "$quizTitle - Code: ${widget.quizCode}"
                              : "Score updates automatically");

                    return SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 24,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const TechArenaBadge(
                                label: 'TECHNOWIZ OFFICIAL SCORE RECORD',
                                icon: Icons.verified_rounded,
                              ),
                              const SizedBox(height: 18),
                              Tech3DTrophyWidget(
                                rank: liveRank ?? 1,
                                size: 130,
                              ),
                              const SizedBox(height: 18),
                              Text(
                                rankTitle,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: darkGreen,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                rankSubtitle,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 22),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: borderGreen,
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: primaryGreen.withValues(alpha: 0.08),
                                      blurRadius: 18,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    const Text(
                                      "YOUR FINAL SCORE",
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.4,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      "$liveScore",
                                      style: const TextStyle(
                                        color: primaryGreen,
                                        fontSize: 56,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 9,
                                      ),
                                      decoration: BoxDecoration(
                                        color: rankStyle.bgColor,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: rankStyle.borderColor,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Text(
                                        placementTitle,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: rankStyle.primaryColor,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      "Score updates automatically",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.black45,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 26),
                              if (isFinished) ...[
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
                                const SizedBox(height: 14),
                              ],
                              SizedBox(
                                width: double.infinity,
                                height: 58,
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.assignment_turned_in_rounded),
                                  onPressed: () async {
                                    final prefs = await SharedPreferences.getInstance();
                                    await prefs.setString('contestant_last_page', 'quiz_history_score');
                                    await prefs.setString('contestant_current_quiz_code', widget.quizCode);
                                    if (!context.mounted) return;
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => QuizHistoryScoreScreen(
                                          quizCode: widget.quizCode,
                                          quizTitle: quizTitle,
                                        ),
                                      ),
                                    );
                                    await _saveCurrentState();
                                  },
                                  label: const Text(
                                    "VIEW HISTORY SCORE",
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
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
