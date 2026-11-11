import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'competitor_dashboard.dart';
import 'technowiz_theme.dart';

class QuizHistoryScoreScreen extends StatefulWidget {
  final String quizCode;
  final String? quizTitle;

  const QuizHistoryScoreScreen({
    super.key,
    required this.quizCode,
    this.quizTitle,
  });

  @override
  State<QuizHistoryScoreScreen> createState() => _QuizHistoryScoreScreenState();
}

class _QuizHistoryScoreScreenState extends State<QuizHistoryScoreScreen> {
  static const Color primaryGreen = Color(0xFF16A34A);
  static const Color lightGreen = Color(0xFFF0FDF4);
  static const Color borderGreen = Color(0xFFDCEFE1);
  static const Color textDark = Color(0xFF172033);

  bool _loading = true;
  String? _error;
  String _filter = 'all'; // 'all', 'correct', 'wrong'
  int? _selectedLevel; // null means 'All Levels', otherwise 1, 2, 3...

  Map<String, dynamic> _sessionData = {};
  List<Map<String, dynamic>> _reviewedQuestions = [];
  int _totalScore = 0;

  @override
  void initState() {
    super.initState();
    _saveCurrentState();
    _loadQuizHistory();
  }

  Future<void> _saveCurrentState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('contestant_last_page', 'quiz_history_score');
    await prefs.setString('contestant_current_quiz_code', widget.quizCode);
  }

  Future<void> _onExitScreen() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getString('contestant_last_page');
    if (current == 'quiz_history_score') {
      await prefs.setString('contestant_last_page', 'my_score');
    }
  }

  int _parseLevel(dynamic value, {int fallback = 1}) {
    if (value is int && value > 0) return value;
    if (value is num && value > 0) return value.toInt();
    if (value != null) {
      final text = value.toString().trim();
      final match = RegExp(r'\d+').firstMatch(text);
      if (match != null) {
        final parsed = int.tryParse(match.group(0)!);
        if (parsed != null && parsed > 0) return parsed;
      }
      final lower = text.toLowerCase();
      if (lower.contains('easy')) return 1;
      if (lower.contains('moderate') || lower.contains('medium')) return 2;
      if (lower.contains('difficult') || lower.contains('hard')) return 3;
      if (lower.contains('clincher')) return 4;
    }
    return fallback;
  }

  String _getLevelTitle(int level) {
    switch (level) {
      case 1:
        return 'Level 1 (Easy)';
      case 2:
        return 'Level 2 (Moderate)';
      case 3:
        return 'Level 3 (Difficult)';
      case 4:
        return 'Level 4 (Clincher)';
      default:
        return 'Level $level';
    }
  }

  Color _getLevelColor(int level) {
    switch (level) {
      case 1:
        return const Color(0xFF16A34A); // Green
      case 2:
        return const Color(0xFFD97706); // Amber
      case 3:
        return const Color(0xFFDC2626); // Red
      case 4:
        return const Color(0xFF7C3AED); // Purple
      default:
        return primaryGreen;
    }
  }

  List<String> _getQuestionOptions(Map<String, dynamic> question) {
    final rawOptions = question['options'];
    if (rawOptions is List) {
      return rawOptions
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return [
      question['optionA']?.toString().trim() ?? '',
      question['optionB']?.toString().trim() ?? '',
      question['optionC']?.toString().trim() ?? '',
      question['optionD']?.toString().trim() ?? '',
    ].where((e) => e.isNotEmpty).toList();
  }

  String _getCorrectAnswer(Map<String, dynamic> question) {
    final rawValue = question['correctAnswer'];
    if (rawValue is List) {
      return rawValue
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .join(', ');
    }
    final rawCorrect = rawValue?.toString().trim() ?? '';
    final options = _getQuestionOptions(question);

    switch (rawCorrect.toUpperCase()) {
      case 'A':
        return options.isNotEmpty ? options[0] : rawCorrect;
      case 'B':
        return options.length > 1 ? options[1] : rawCorrect;
      case 'C':
        return options.length > 2 ? options[2] : rawCorrect;
      case 'D':
        return options.length > 3 ? options[3] : rawCorrect;
    }

    for (final option in options) {
      if (rawCorrect.toLowerCase() == option.toLowerCase()) {
        return option;
      }
    }
    return rawCorrect;
  }

  String _getQuestionType(Map<String, dynamic> question) {
    final type = question['questionType']?.toString().trim();
    if (type != null && type.isNotEmpty) {
      if (type.toLowerCase() == 'true/false' ||
          type.toLowerCase() == 'true or false') {
        return "True or False";
      }
      return type;
    }
    final rawType = question['type']?.toString().trim();
    if (rawType != null && rawType.isNotEmpty) return rawType;
    return "Multiple Choice";
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortSessionQuestions(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sorted = [...docs];

    int getLevel(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
      final data = doc.data();
      final raw = data['sessionLevel'] ?? data['level'];
      return _parseLevel(raw);
    }

    int? getOrder(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
      final raw = doc.data()['order'];
      if (raw is num) return raw.toInt();
      return int.tryParse(raw?.toString() ?? '');
    }

    DateTime? getCreatedAt(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
      final raw = doc.data()['createdAt'];
      if (raw is Timestamp) return raw.toDate();
      return null;
    }

    sorted.sort((a, b) {
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

    return sorted;
  }

  Future<void> _loadQuizHistory() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Please log in to view quiz score history.';
        });
      }
      return;
    }

    try {
      final sessionRef = FirebaseFirestore.instance
          .collection('quiz_sessions')
          .doc(widget.quizCode);

      final sessionDoc = await sessionRef.get();
      if (!sessionDoc.exists) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'Quiz session not found (${widget.quizCode}).';
          });
        }
        return;
      }

      _sessionData = sessionDoc.data() ?? {};

      // 1. Fetch questions
      final questionsSnap = await sessionRef.collection('questions').get();
      final sortedQuestions = _sortSessionQuestions(questionsSnap.docs);

      // 2. Fetch contestant responses
      final responsesSnap = await sessionRef
          .collection('answers')
          .doc(currentUser.uid)
          .collection('responses')
          .get();

      final responsesByDocId = <String, Map<String, dynamic>>{};
      final responsesByNumber = <int, Map<String, dynamic>>{};

      for (final doc in responsesSnap.docs) {
        final data = doc.data();
        responsesByDocId[doc.id] = data;
        final qNum = int.tryParse(data['questionNumber']?.toString() ?? '');
        if (qNum != null) {
          responsesByNumber[qNum] = data;
        }
      }

      // 3. Fetch score doc
      final scoreDoc =
          await sessionRef.collection('scores').doc(currentUser.uid).get();
      if (scoreDoc.exists) {
        _totalScore =
            int.tryParse(scoreDoc.data()?['score']?.toString() ?? '') ?? 0;
      }

      // 4. Build combined review list
      final reviewList = <Map<String, dynamic>>[];
      int calculatedScore = 0;

      for (int i = 0; i < sortedQuestions.length; i++) {
        final qDoc = sortedQuestions[i];
        final qData = qDoc.data();
        final qNumber = i + 1;

        final response =
            responsesByDocId['question_$i'] ?? responsesByNumber[qNumber];

        final questionText = qData['question']?.toString().trim().isNotEmpty ==
                true
            ? qData['question'].toString().trim()
            : (qData['questionText']?.toString().trim().isNotEmpty == true
                ? qData['questionText'].toString().trim()
                : (qData['title']?.toString().trim().isNotEmpty == true
                    ? qData['title'].toString().trim()
                    : 'Question $qNumber'));

        final questionType = response?['questionType']?.toString().trim() ??
            _getQuestionType(qData);

        final expectedCorrect =
            response?['correctAnswer']?.toString().trim().isNotEmpty == true
                ? response!['correctAnswer'].toString().trim()
                : _getCorrectAnswer(qData);

        final alternateAnswers = response?['correctAnswers'] ?? qData['correctAnswers'];

        final selectedAnswer =
            response?['selectedAnswer']?.toString().trim() ?? '';
        final hasAnswer = selectedAnswer.isNotEmpty;
        final isCorrect = response?['isCorrect'] == true ||
            response?['answerStatus'] == 'correct';
        final isTimedOut = response?['timedOut'] == true;
        final points = int.tryParse(response?['points']?.toString() ?? '') ??
            (isCorrect ? 1 : 0);

        final level = _parseLevel(
          response?['level'] ?? qData['level'] ?? qData['sessionLevel'],
        );

        if (isCorrect) {
          calculatedScore += points;
        }

        reviewList.add({
          'questionIndex': i,
          'questionNumber': qNumber,
          'level': level,
          'questionText': questionText,
          'questionType': questionType,
          'options': _getQuestionOptions(qData),
          'selectedAnswer': selectedAnswer,
          'correctAnswer': expectedCorrect,
          'alternateAnswers': alternateAnswers,
          'isCorrect': isCorrect,
          'hasAnswer': hasAnswer,
          'isTimedOut': isTimedOut,
          'points': points,
        });
      }

      if (_totalScore == 0 && calculatedScore > 0) {
        _totalScore = calculatedScore;
      }

      if (mounted) {
        setState(() {
          _reviewedQuestions = reviewList;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Error loading quiz history: $e';
        });
      }
    }
  }

  List<int> _getUniqueLevels() {
    final set = <int>{};
    for (final q in _reviewedQuestions) {
      final lvl = q['level'] as int? ?? 1;
      set.add(lvl);
    }
    final list = set.toList()..sort();
    return list;
  }

  Map<String, dynamic> _getLevelStats(int? level) {
    final questions = level == null
        ? _reviewedQuestions
        : _reviewedQuestions.where((q) => q['level'] == level).toList();

    final total = questions.length;
    final correct = questions.where((q) => q['isCorrect'] == true).length;
    final wrong = questions
        .where((q) => q['isCorrect'] != true && q['hasAnswer'] == true)
        .length;
    final unanswered = questions.where((q) => q['hasAnswer'] != true).length;
    final score =
        questions.fold<int>(0, (totalPoints, q) => totalPoints + (q['points'] as int));
    final accuracy = total > 0 ? ((correct / total) * 100).toStringAsFixed(0) : '0';

    return {
      'total': total,
      'correct': correct,
      'wrong': wrong,
      'unanswered': unanswered,
      'score': score,
      'accuracy': accuracy,
      'questions': questions,
    };
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.quizTitle?.isNotEmpty == true
        ? widget.quizTitle!
        : (_sessionData['title']?.toString() ?? 'Quiz Score History');

    final uniqueLevels = _getUniqueLevels();

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
            "Quiz History Score",
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
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: primaryGreen),
                )
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    )
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 920),
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                          children: [
                            // LEVEL SELECTOR PILLS
                            if (uniqueLevels.length > 1) ...[
                              _buildLevelSelectorBar(uniqueLevels),
                              const SizedBox(height: 12),
                            ],

                            // SUMMARY HERO CARD (Separated per Level or Overall)
                            _buildSummaryCard(title, uniqueLevels),

                            const SizedBox(height: 14),

                            // STATUS FILTER CHIPS (All, Correct, Wrong)
                            _buildFilterChips(),

                            const SizedBox(height: 16),

                            // QUESTIONS CONTENT (Separated by Level Sections or Selected Level)
                            _buildQuestionsContent(uniqueLevels),
                          ],
                        ),
                      ),
                    ),
        ),
      ),
    );
  }

  /// Horizontal Level Selector Pills (Smoothly swipeable with touch & mouse drag)
  Widget _buildLevelSelectorBar(List<int> uniqueLevels) {
    return ScrollConfiguration(
      behavior: const _HistorySwipeableScrollBehavior(),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(right: 20, top: 2, bottom: 4),
        child: Row(
          children: [
            // All Levels Pill
            _buildLevelPill(
              level: null,
              label: 'All Levels (${_reviewedQuestions.length})',
              color: primaryGreen,
            ),
            const SizedBox(width: 8),

            // Each Level Pill
            ...uniqueLevels.map((lvl) {
              final stats = _getLevelStats(lvl);
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _buildLevelPill(
                  level: lvl,
                  label: 'Level $lvl • ${stats['score']} pts',
                  color: _getLevelColor(lvl),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildLevelPill({
    required int? level,
    required String label,
    required Color color,
  }) {
    final isSelected = _selectedLevel == level;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedLevel = level;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : borderGreen,
            width: 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.check_circle_rounded, color: Colors.white, size: 14),
              ),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : textDark,
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Summary Hero Card (Shows Level Stats if level selected, or overall stats + per-level pills)
  Widget _buildSummaryCard(String title, List<int> uniqueLevels) {
    final isSingleLevel = _selectedLevel != null;
    final currentStats = _getLevelStats(_selectedLevel);
    final cardColor = isSingleLevel ? _getLevelColor(_selectedLevel!) : primaryGreen;

    final cardTitle = isSingleLevel
        ? _getLevelTitle(_selectedLevel!)
        : title;

    final cardSubtitle = isSingleLevel
        ? 'Quiz: $title • Code: ${widget.quizCode} • Accuracy: ${currentStats['accuracy']}%'
        : 'Code: ${widget.quizCode} • Accuracy: ${currentStats['accuracy']}%';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isSingleLevel
              ? [
                  cardColor.withValues(alpha: 0.9),
                  cardColor,
                ]
              : [
                  const Color(0xFF064E25),
                  const Color(0xFF07883D),
                ],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: cardColor.withValues(alpha: 0.24),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HEADER ROW
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isSingleLevel
                      ? Icons.flag_rounded
                      : Icons.assignment_turned_in_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cardSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSingleLevel) ...[
                const SizedBox(width: 8),
                Flexible(
                  flex: 0,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedLevel = null;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white30),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.close_rounded, color: Colors.white, size: 14),
                          SizedBox(width: 4),
                          Text(
                            'View All',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 18),

          // STATS ROW: CORRECT • WRONG • SCORE
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _buildSummaryStat(
                        icon: Icons.check_circle_rounded,
                        iconColor: Colors.greenAccent.shade400,
                        value: '${currentStats['correct']}',
                        label: isSingleLevel ? 'Level Correct' : 'Total Correct',
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: 34,
                  color: Colors.white24,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _buildSummaryStat(
                        icon: Icons.cancel_rounded,
                        iconColor: Colors.redAccent.shade100,
                        value: '${currentStats['wrong']}',
                        label: isSingleLevel ? 'Level Wrong' : 'Total Wrong',
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: 34,
                  color: Colors.white24,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _buildSummaryStat(
                        icon: Icons.stars_rounded,
                        iconColor: Colors.amberAccent.shade400,
                        value: '${currentStats['score']} pts',
                        label: isSingleLevel ? 'Level Score' : 'Final Score',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // PER-LEVEL BREAKDOWN ROW (Shown when viewing all levels)
          if (!isSingleLevel && uniqueLevels.length > 1) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SCORE BY LEVEL (Tap to filter):',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ScrollConfiguration(
                    behavior: const _HistorySwipeableScrollBehavior(),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.only(right: 12),
                      child: Row(
                        children: uniqueLevels.map((lvl) {
                        final st = _getLevelStats(lvl);
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedLevel = lvl;
                            });
                          },
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white30),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Level $lvl: ',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '${st['score']} pts',
                                  style: const TextStyle(
                                    color: Colors.amberAccent,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  ' (${st['correct']}✓ ${st['wrong']}✗)',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
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

  Widget _buildSummaryStat({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
  }) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 16),
            const SizedBox(width: 5),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  /// Status Filter Chips (All, Correct, Wrong)
  Widget _buildFilterChips() {
    final currentStats = _getLevelStats(_selectedLevel);
    final total = currentStats['total'] as int;
    final correct = currentStats['correct'] as int;
    final wrong = currentStats['wrong'] as int;

    return Row(
      children: [
        _buildFilterChip(
          id: 'all',
          label: 'All ($total)',
        ),
        const SizedBox(width: 8),
        _buildFilterChip(
          id: 'correct',
          label: 'Correct ($correct)',
          activeColor: primaryGreen,
        ),
        const SizedBox(width: 8),
        _buildFilterChip(
          id: 'wrong',
          label: 'Wrong ($wrong)',
          activeColor: Colors.red.shade600,
        ),
      ],
    );
  }

  Widget _buildFilterChip({
    required String id,
    required String label,
    Color activeColor = primaryGreen,
  }) {
    final isSelected = _filter == id;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _filter = id;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? activeColor : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? activeColor : borderGreen,
              width: 1.4,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected ? Colors.white : textDark,
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Questions Content: Grouped by level if 'All Levels', or showing only selected level
  Widget _buildQuestionsContent(List<int> uniqueLevels) {
    if (_selectedLevel != null) {
      // SINGLE LEVEL VIEW
      final questions = _reviewedQuestions.where((q) {
        if (q['level'] != _selectedLevel) return false;
        if (_filter == 'correct') return q['isCorrect'] == true;
        if (_filter == 'wrong') return q['isCorrect'] != true;
        return true;
      }).toList();

      if (questions.isEmpty) {
        return _buildEmptyState();
      }

      return Column(
        children: questions.map(_buildQuestionCard).toList(),
      );
    }

    // ALL LEVELS VIEW: Grouped by Level Sections
    final sections = <Widget>[];

    for (final lvl in uniqueLevels) {
      final levelQuestions = _reviewedQuestions.where((q) {
        if (q['level'] != lvl) return false;
        if (_filter == 'correct') return q['isCorrect'] == true;
        if (_filter == 'wrong') return q['isCorrect'] != true;
        return true;
      }).toList();

      if (levelQuestions.isEmpty) continue;

      final stats = _getLevelStats(lvl);

      sections.add(
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 12),
          child: _buildLevelSectionHeader(lvl, stats),
        ),
      );

      for (final q in levelQuestions) {
        sections.add(_buildQuestionCard(q));
      }
    }

    if (sections.isEmpty) {
      return _buildEmptyState();
    }

    return Column(children: sections);
  }

  /// Level Section Header Banner (Clearly separating each level)
  Widget _buildLevelSectionHeader(int level, Map<String, dynamic> stats) {
    final color = _getLevelColor(level);
    final title = _getLevelTitle(level);
    final score = stats['score'];
    final correct = stats['correct'];
    final wrong = stats['wrong'];
    final total = stats['total'];
    final accuracy = stats['accuracy'];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.28), width: 1.4),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.flag_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$total Questions • $correct Correct • $wrong Wrong ($accuracy%)',
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                '$score pts',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderGreen),
      ),
      child: Center(
        child: Text(
          _filter == 'correct'
              ? 'No correct answers in this section.'
              : _filter == 'wrong'
                  ? 'No incorrect answers in this section! Perfect score!'
                  : 'No questions found.',
          style: const TextStyle(
            color: Colors.black54,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionCard(Map<String, dynamic> item) {
    final bool isCorrect = item['isCorrect'] == true;
    final bool hasAnswer = item['hasAnswer'] == true;
    final String selectedAnswer = item['selectedAnswer'] as String;
    final String correctAnswer = item['correctAnswer'] as String;
    final alternateAnswers = item['alternateAnswers'];
    final String questionText = item['questionText'] as String;
    final int questionNumber = item['questionNumber'] as int;
    final int level = item['level'] as int;
    final int points = item['points'] as int;
    final String questionType = item['questionType'] as String;

    final Color statusColor = isCorrect
        ? primaryGreen
        : (!hasAnswer ? Colors.orange.shade700 : Colors.red.shade600);

    final Color statusBg = isCorrect
        ? const Color(0xFFE8F8EE)
        : (!hasAnswer ? const Color(0xFFFFF7ED) : const Color(0xFFFEE2E2));

    final String statusLabel = isCorrect
        ? '✓ CORRECT (+$points pt${points != 1 ? 's' : ''})'
        : (!hasAnswer
            ? '⏱ UNANSWERED (0 pts)'
            : '✗ INCORRECT (0 pts)');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isCorrect
              ? borderGreen
              : (hasAnswer ? Colors.red.shade200 : Colors.orange.shade200),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: (isCorrect ? primaryGreen : Colors.black).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // CARD HEADER: NUMBER + LEVEL + STATUS PILL
          LayoutBuilder(
            builder: (context, constraints) {
              final qPill = Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: _getLevelColor(level).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _getLevelColor(level).withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  'Q#$questionNumber • Level $level',
                  style: TextStyle(
                    color: _getLevelColor(level),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              );

              final typeText = Text(
                questionType,
                style: const TextStyle(
                  color: Colors.black45,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              );

              final statusBadge = Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4.5,
                ),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    statusLabel,
                    maxLines: 1,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              );

              if (constraints.maxWidth < 250) {
                return SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [qPill, typeText],
                      ),
                      statusBadge,
                    ],
                  ),
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [qPill, typeText],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(flex: 0, child: statusBadge),
                ],
              );
            },
          ),

          const SizedBox(height: 12),

          // QUESTION TEXT
          Text(
            questionText,
            style: const TextStyle(
              color: textDark,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),

          const SizedBox(height: 14),

          // CONTESTANT ANSWER BOX
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isCorrect
                  ? const Color(0xFFF0FDF4)
                  : (!hasAnswer ? const Color(0xFFFFFBEB) : const Color(0xFFFFF1F2)),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isCorrect
                    ? Colors.green.shade200
                    : (!hasAnswer ? Colors.orange.shade200 : Colors.red.shade200),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isCorrect
                      ? Icons.check_circle_rounded
                      : (!hasAnswer ? Icons.hourglass_empty_rounded : Icons.cancel_rounded),
                  color: statusColor,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 13, height: 1.3),
                      children: [
                        const TextSpan(
                          text: 'Your Answer: ',
                          style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(
                          text: hasAnswer
                              ? selectedAnswer
                              : '(No Answer / Timed Out)',
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // CORRECT ANSWER BOX (Shown if wrong or unanswered)
          if (!isCorrect) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.verified_rounded,
                    color: primaryGreen,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 13, height: 1.3),
                            children: [
                              const TextSpan(
                                text: 'Correct Answer: ',
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              TextSpan(
                                text: correctAnswer,
                                style: const TextStyle(
                                  color: primaryGreen,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (alternateAnswers is List && alternateAnswers.length > 1) ...[
                          const SizedBox(height: 3),
                          Text(
                            'Accepted: ${alternateAnswers.join(", ")}',
                            style: TextStyle(
                              color: Colors.green.shade800,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
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
}

class _HistorySwipeableScrollBehavior extends MaterialScrollBehavior {
  const _HistorySwipeableScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}
