import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'quizmaster_theme.dart';

class SubmittedAnswersScreen extends StatefulWidget {
  final String quizCode;

  // Optional para compatible gihapon sa existing QuizControlScreen.
  final int? questionIndex;

  const SubmittedAnswersScreen({
    super.key,
    required this.quizCode,
    this.questionIndex,
  });

  @override
  State<SubmittedAnswersScreen> createState() => _SubmittedAnswersScreenState();
}

class _SubmittedAnswersScreenState extends State<SubmittedAnswersScreen> {
  String get quizCode => widget.quizCode;
  int? get questionIndex => widget.questionIndex;

  @override
  void initState() {
    super.initState();
    _saveCurrentPage();
  }

  Future<void> _saveCurrentPage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'technowiz_quizmaster_last_page',
        'submitted_answers',
      );
      await prefs.setString(
        'technowiz_quizmaster_current_quiz_code',
        widget.quizCode,
      );
      if (widget.questionIndex != null) {
        await prefs.setInt(
          'technowiz_quizmaster_submitted_question_index',
          widget.questionIndex!,
        );
      } else {
        await prefs.remove('technowiz_quizmaster_submitted_question_index');
      }
    } catch (_) {}
  }

  // ============================================================
  // NORMALIZE & MATCH HELPERS
  // ============================================================

  String normalizeAnswer(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\u2010-\u2015]'), '-')
        .replaceAll(RegExp(r'[\u2018\u2019]'), "'")
        .replaceAll(RegExp(r'[\u201C\u201D]'), '"')
        .replaceAll(RegExp(r'\[|\{'), '(')
        .replaceAll(RegExp(r'\]|\}'), ')')
        .replaceAll(RegExp(r'\s*\(\s*'), ' ( ')
        .replaceAll(RegExp(r'\s*\)\s*'), ' ) ')
        .replaceAll(RegExp(r'\s*:\s*'), ' : ')
        .replaceAll(RegExp(r'\s*-\s*'), ' - ')
        .replaceAll(RegExp(r'\s*/\s*'), ' / ')
        .replaceAll(RegExp(r'\s*,\s*'), ' , ')
        .replaceAll(RegExp(r'(?<=\w)\.(?=\s|$)'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _stripPunctuation(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[\u2010-\u2015]'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _sortTokens(String value) {
    final tokens =
        _stripPunctuation(value).split(' ').where((t) => t.isNotEmpty).toList();
    tokens.sort();
    return tokens.join(' ');
  }

  List<String> getExpandedAnswerVariants(String rawAnswer) {
    final variants = <String>{};
    final trimmed = rawAnswer.trim();
    if (trimmed.isEmpty) return [];

    variants.add(trimmed);

    // 1. Parentheses/brackets: e.g. "DNS (Domain Name System)" or "DNS(Domain Name System)"
    final parenMatch =
        RegExp(r'^(.*?)\s*[\(\[\{](.*?)[\)\]\}]\s*$').firstMatch(trimmed);
    if (parenMatch != null) {
      final part1 = parenMatch.group(1)?.trim() ?? '';
      final part2 = parenMatch.group(2)?.trim() ?? '';
      if (part1.isNotEmpty && part2.isNotEmpty) {
        variants.add('$part1 ($part2)');
        variants.add('$part2 ($part1)');
        variants.add('$part1 - $part2');
        variants.add('$part2 - $part1');
        variants.add('$part1 $part2');
        variants.add('$part2 $part1');
      }
    }

    // 2. Dash, colon, or slash: e.g. "DNS - Domain Name System"
    final delimMatch = RegExp(r'^(.*?)\s*[:\-\/]\s*(.*?)$').firstMatch(trimmed);
    if (delimMatch != null) {
      final part1 = delimMatch.group(1)?.trim() ?? '';
      final part2 = delimMatch.group(2)?.trim() ?? '';
      if (part1.isNotEmpty && part2.isNotEmpty) {
        variants.add('$part1 ($part2)');
        variants.add('$part2 ($part1)');
        variants.add('$part1 - $part2');
        variants.add('$part2 - $part1');
        variants.add('$part1 $part2');
        variants.add('$part2 $part1');
      }
    }

    return variants.toList();
  }

  bool _isAnswerMatch(String submitted, String accepted) {
    final subTrim = submitted.trim();
    final accTrim = accepted.trim();
    if (subTrim.isEmpty || accTrim.isEmpty) return false;

    // 1. Exact case-insensitive match
    if (subTrim.toLowerCase() == accTrim.toLowerCase()) {
      return true;
    }

    // 2. Spacing around delimiters normalized match
    final normSub = normalizeAnswer(subTrim);
    final normAcc = normalizeAnswer(accTrim);
    if (normSub == normAcc) {
      return true;
    }

    // 3. Punctuation stripped match
    final stripSub = _stripPunctuation(subTrim);
    final stripAcc = _stripPunctuation(accTrim);
    if (stripSub.isNotEmpty && stripSub == stripAcc) {
      return true;
    }

    // 4. Token-sorted match (handles "Domain Name System (DNS)" vs "DNS (Domain Name System)")
    final sortSub = _sortTokens(subTrim);
    final sortAcc = _sortTokens(accTrim);
    if (sortSub.isNotEmpty && sortSub == sortAcc) {
      return true;
    }

    return false;
  }

  // ============================================================
  // GET ACCEPTED ANSWERS
  // ============================================================

  List<String> getAcceptedAnswers(Map<String, dynamic> question) {
    final List<String> accepted = [];

    void addVariants(dynamic value) {
      if (value == null) return;
      if (value is List) {
        for (final item in value) {
          addVariants(item);
        }
        return;
      }
      final raw = value.toString().trim();
      if (raw.isEmpty) return;

      final variants = getExpandedAnswerVariants(raw);
      for (final v in variants) {
        final normalized = normalizeAnswer(v);
        if (normalized.isNotEmpty && !accepted.contains(normalized)) {
          accepted.add(normalized);
        }
      }
    }

    // 1. correctAnswer
    addVariants(question['correctAnswer']);

    // 2. correctAnswers list
    addVariants(question['correctAnswers']);
    addVariants(question['answer']);
    addVariants(question['acceptedAnswers']);
    addVariants(question['alternateAnswers']);

    return accepted;
  }

  // ============================================================
  // CHECK ANSWER
  // ============================================================

  bool isAnswerCorrect(Map<String, dynamic> question, String submittedAnswer) {
    final sub = submittedAnswer.trim();
    if (sub.isEmpty) {
      return false;
    }

    // Check direct match with correctAnswer
    final rawCorrect = question['correctAnswer']?.toString().trim() ?? '';
    if (rawCorrect.isNotEmpty && _isAnswerMatch(sub, rawCorrect)) {
      return true;
    }

    // Check all accepted answers and their variations
    final acceptedAnswers = getAcceptedAnswers(question);
    for (final accepted in acceptedAnswers) {
      if (_isAnswerMatch(sub, accepted)) {
        return true;
      }
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: QuizMasterAppBar(
        title: "Submitted Answers",
        subtitle: "Code: $quizCode",
        badgeText: "TECHNOWIZ • ANSWER AUDIT",
        badgeIcon: Icons.fact_check_rounded,
      ),
      body: QuizMasterCircuitBackground(
        child: FutureBuilder<QuerySnapshot>(
          future: FirebaseFirestore.instance.collection('questions').get(),
          builder: (context, questionSnapshot) {
            // =====================================================
            // LOADING QUESTIONS
            // =====================================================

            if (questionSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: QuizMasterColors.primaryBlue),
              );
            }

          // =====================================================
          // ERROR
          // =====================================================

          if (questionSnapshot.hasError) {
            return const Center(
              child: Text(
                "Error loading questions",
                style: TextStyle(fontSize: 18),
              ),
            );
          }

          if (!questionSnapshot.hasData) {
            return const Center(child: Text("No question data found"));
          }

          final questions = questionSnapshot.data!.docs;

          if (questions.isEmpty) {
            return const Center(
              child: Text("No Questions Found", style: TextStyle(fontSize: 20)),
            );
          }

          // =====================================================
          // LOAD CONTESTANTS
          // =====================================================

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('quiz_sessions')
                .doc(quizCode)
                .collection('answers')
                .snapshots(),

            builder: (context, answerSnapshot) {
              // =================================================
              // LOADING ANSWERS
              // =================================================

              if (answerSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.deepPurple),
                );
              }

              // =================================================
              // ERROR
              // =================================================

              if (answerSnapshot.hasError) {
                return const Center(
                  child: Text(
                    "Error loading submitted answers",
                    style: TextStyle(fontSize: 18),
                  ),
                );
              }

              if (!answerSnapshot.hasData) {
                return const Center(child: Text("No answer data found"));
              }

              final contestants = answerSnapshot.data!.docs;

              // =================================================
              // NO CONTESTANTS
              // =================================================

              if (contestants.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.assignment_outlined,
                        size: 80,
                        color: Colors.grey,
                      ),

                      SizedBox(height: 20),

                      Text(
                        "No Answers Yet",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      SizedBox(height: 8),

                      Text(
                        "No contestant has submitted answers yet.",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              // =================================================
              // CONTESTANT LIST
              // =================================================

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: contestants.length,

                itemBuilder: (context, contestantIndex) {
                  final contestant = contestants[contestantIndex];

                  return FutureBuilder<Map<String, dynamic>>(
                    future: _loadContestantData(
                      contestant.id,
                      quizCode,
                      questions,
                    ),

                    builder: (context, resultSnapshot) {
                      // =========================================
                      // LOADING CONTESTANT
                      // =========================================

                      if (resultSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),

                          child: const Padding(
                            padding: EdgeInsets.all(20),

                            child: Center(
                              child: CircularProgressIndicator(
                                color: Colors.deepPurple,
                              ),
                            ),
                          ),
                        );
                      }

                      // =========================================
                      // ERROR
                      // =========================================

                      if (resultSnapshot.hasError || !resultSnapshot.hasData) {
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),

                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.person),
                            ),

                            title: Text(contestant.id),

                            subtitle: const Text("Unable to load answers"),
                          ),
                        );
                      }

                      final data = resultSnapshot.data!;

                      final String name =
                          data['name']?.toString() ?? contestant.id;

                      final List<Map<String, dynamic>> answers =
                          List<Map<String, dynamic>>.from(
                            data['answers'] ?? [],
                          );

                      final int totalQuestions = questions.length;

                      final int answered = answers.length;

                      final int correct = answers
                          .where((answer) => answer['correct'] == true)
                          .length;

                      final int wrong = answers
                          .where((answer) => answer['correct'] == false)
                          .length;

                      final double accuracy = answered == 0
                          ? 0
                          : (correct / answered) * 100;

                      // =========================================
                      // CONTESTANT CARD
                      // =========================================

                      return Card(
                        elevation: 4,
                        margin: const EdgeInsets.only(bottom: 15),

                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),

                        child: ExpansionTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.deepPurple,

                            child: Text(
                              "${contestantIndex + 1}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),

                          title: Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),

                          subtitle: Text(
                            "$answered / $totalQuestions answered • "
                            "$correct correct • $wrong wrong",
                          ),

                          children: [
                            // =================================
                            // CONTESTANT SUMMARY
                            // =================================
                            Container(
                              width: double.infinity,

                              margin: const EdgeInsets.symmetric(
                                horizontal: 15,
                                vertical: 8,
                              ),

                              padding: const EdgeInsets.all(15),

                              decoration: BoxDecoration(
                                color: Colors.deepPurple,
                                borderRadius: BorderRadius.circular(15),
                              ),

                              child: Column(
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),

                                  const SizedBox(height: 10),

                                  Text(
                                    "Answered: "
                                    "$answered / "
                                    "$totalQuestions",

                                    style: const TextStyle(color: Colors.white),
                                  ),

                                  Text(
                                    "Correct: $correct",

                                    style: const TextStyle(
                                      color: Colors.greenAccent,
                                    ),
                                  ),

                                  Text(
                                    "Wrong: $wrong",

                                    style: const TextStyle(
                                      color: Colors.redAccent,
                                    ),
                                  ),

                                  Text(
                                    "Accuracy: "
                                    "${accuracy.toStringAsFixed(1)}%",

                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ],
                              ),
                            ),

                            // =================================
                            // ALL QUESTIONS
                            // =================================
                            ...List.generate(questions.length, (
                              questionNumber,
                            ) {
                              final question = questions[questionNumber];

                              final questionData =
                                  question.data() as Map<String, dynamic>;

                              final String questionText =
                                  questionData['question']?.toString() ?? '';

                              // =================================
                              // FIND SUBMITTED ANSWER
                              // =================================

                              final matchingAnswers = answers.where(
                                (answer) =>
                                    answer['questionIndex'] == questionNumber,
                              );

                              Map<String, dynamic>? submittedData;

                              if (matchingAnswers.isNotEmpty) {
                                submittedData = matchingAnswers.first;
                              }

                              final bool hasAnswer = submittedData != null;

                              final String selectedAnswer =
                                  submittedData?['answer']?.toString() ??
                                  "No Answer";

                              // =================================
                              // IMPORTANT:
                              // RECALCULATE CORRECT ANSWER
                              // USING ACCEPTED ANSWERS
                              // =================================

                              final bool isCorrect =
                                  hasAnswer &&
                                  isAnswerCorrect(questionData, selectedAnswer);

                              // =================================
                              // DISPLAY CORRECT ANSWER
                              // =================================

                              final String correctAnswer =
                                  questionData['correctAnswer']?.toString() ??
                                  '';

                              // =================================
                              // QUESTION CARD
                              // =================================

                              return Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),

                                padding: const EdgeInsets.all(15),

                                decoration: BoxDecoration(
                                  color: !hasAnswer
                                      ? Colors.grey.shade100
                                      : isCorrect
                                      ? Colors.green.shade50
                                      : Colors.red.shade50,

                                  borderRadius: BorderRadius.circular(14),

                                  border: Border.all(
                                    color: !hasAnswer
                                        ? Colors.grey
                                        : isCorrect
                                        ? Colors.green
                                        : Colors.red,

                                    width: 1.2,
                                  ),
                                ),

                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,

                                  children: [
                                    // =========================
                                    // QUESTION NUMBER
                                    // =========================
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 18,

                                          backgroundColor: !hasAnswer
                                              ? Colors.grey
                                              : isCorrect
                                              ? Colors.green
                                              : Colors.red,

                                          child: Text(
                                            "${questionNumber + 1}",

                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),

                                        const SizedBox(width: 10),

                                        Expanded(
                                          child: Text(
                                            "Question "
                                            "${questionNumber + 1}",

                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 17,
                                            ),
                                          ),
                                        ),

                                        if (hasAnswer)
                                          Icon(
                                            isCorrect
                                                ? Icons.check_circle
                                                : Icons.cancel,

                                            color: isCorrect
                                                ? Colors.green
                                                : Colors.red,
                                          ),
                                      ],
                                    ),

                                    const SizedBox(height: 12),

                                    // =========================
                                    // QUESTION
                                    // =========================
                                    Text(
                                      questionText,

                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),

                                    const SizedBox(height: 12),

                                    // =========================
                                    // SUBMITTED ANSWER
                                    // =========================
                                    Container(
                                      width: double.infinity,

                                      padding: const EdgeInsets.all(10),

                                      decoration: BoxDecoration(
                                        color: Colors.white,

                                        borderRadius: BorderRadius.circular(8),
                                      ),

                                      child: Text(
                                        "Submitted Answer: "
                                        "$selectedAnswer",

                                        style: const TextStyle(fontSize: 15),
                                      ),
                                    ),

                                    const SizedBox(height: 8),

                                    // =========================
                                    // CORRECT ANSWER
                                    // =========================
                                    Container(
                                      width: double.infinity,

                                      padding: const EdgeInsets.all(10),

                                      decoration: BoxDecoration(
                                        color: Colors.white,

                                        borderRadius: BorderRadius.circular(8),
                                      ),

                                      child: Text(
                                        "Correct Answer: "
                                        "$correctAnswer",

                                        style: const TextStyle(fontSize: 15),
                                      ),
                                    ),

                                    const SizedBox(height: 8),

                                    // =========================
                                    // RESULT
                                    // =========================
                                    Text(
                                      !hasAnswer
                                          ? "⚪ No Answer"
                                          : isCorrect
                                          ? "✅ Correct"
                                          : "❌ Wrong",

                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,

                                        fontSize: 16,

                                        color: !hasAnswer
                                            ? Colors.grey
                                            : isCorrect
                                            ? Colors.green
                                            : Colors.red,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),

                            const SizedBox(height: 10),
                          ],
                        ),
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
  );
}

  // ============================================================
  // LOAD ONE CONTESTANT'S WHOLE QUIZ ANSWERS
  // ============================================================

  Future<Map<String, dynamic>> _loadContestantData(
    String uid,
    String quizCode,
    List<QueryDocumentSnapshot> questions,
  ) async {
    // ==========================================================
    // GET USER NAME
    // ==========================================================

    String name = uid;

    final user = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    if (user.exists) {
      final userData = user.data();

      if (userData != null && userData['name'] != null) {
        name = userData['name'].toString();
      }
    }

    // ==========================================================
    // GET ALL RESPONSES
    // ==========================================================

    final List<Map<String, dynamic>> allAnswers = [];

    for (int i = 0; i < questions.length; i++) {
      final question = questions[i].data() as Map<String, dynamic>;

      final answer = await FirebaseFirestore.instance
          .collection('quiz_sessions')
          .doc(quizCode)
          .collection('answers')
          .doc(uid)
          .collection('responses')
          .doc('question_$i')
          .get();

      if (!answer.exists) {
        continue;
      }

      final String selected = answer['selectedAnswer']?.toString() ?? '';

      // ========================================================
      // IMPORTANT:
      // DON'T JUST USE:
      //
      // selected == correctAnswer
      //
      // Instead, use the accepted-answer checker.
      // ========================================================

      final bool isCorrect = isAnswerCorrect(question, selected);

      final String correctAnswer = question['correctAnswer']?.toString() ?? '';

      allAnswers.add({
        'questionIndex': i,
        'answer': selected,
        'correctAnswer': correctAnswer,
        'correct': isCorrect,
      });
    }

    return {'name': name, 'answers': allAnswers};
  }
}
