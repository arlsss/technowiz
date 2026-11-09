import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'edit_question_screen.dart';

import 'admin_dashboard.dart';

import 'add_question_screen.dart';

import 'manage_users_screen.dart';

import 'manage_quiz_sessions_screen.dart';

import 'admin_leaderboard_screen.dart';

import 'admin_report_screen.dart';
import 'admin_sidebar.dart';
import 'admin_theme.dart';
import '../login_screen.dart';
import '../../navigation_persistence.dart';

class QuestionListScreen extends StatefulWidget {
  const QuestionListScreen({super.key});

  @override
  State<QuestionListScreen> createState() => _QuestionListScreenState();
}

class _QuestionListScreenState extends State<QuestionListScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // ============================================================

  // COLORS

  // ============================================================

  static const Color primaryPurple = AdminThemeColors.primary;

  static const Color lightPurple = AdminThemeColors.pillBg;

  static const Color backgroundColor = AdminThemeColors.background;

  static const Color textDark = AdminThemeColors.textPrimary;

  static const Color textGrey = AdminThemeColors.textMuted;

  static const Color borderColor = AdminThemeColors.border;

  static const Color redColor = Color(0xFFEF4444);

  static const Color lightRed = Color(0xFFFFEEEE);

  // ============================================================

  // STATE

  // ============================================================

  final TextEditingController searchController = TextEditingController();

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _questionsStream;

  String selectedFilter = 'All';

  final ScrollController _filterScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    AdminNavPersistence.savePage('question_list');

    _questionsStream = FirebaseFirestore.instance
        .collection('questions')
        .snapshots();

    searchController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    searchController.dispose();

    _filterScrollController.dispose();

    super.dispose();
  }

  // ============================================================

  // DELETE QUESTION

  // ============================================================

  Future<void> deleteQuestion(String id) async {
    await FirebaseFirestore.instance.collection('questions').doc(id).delete();
  }

  // ============================================================

  // CLEAR ALL QUESTIONS

  // ============================================================

  Future<void> clearAllQuestions(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,

      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),

          title: const Row(
            children: [
              Icon(Icons.delete_sweep_outlined, color: redColor, size: 25),

              SizedBox(width: 10),

              Expanded(
                child: Text(
                  'Clear All Questions?',

                  style: TextStyle(
                    color: textDark,

                    fontSize: 18,

                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),

          content: const Text(
            'This will permanently delete all questions from your question bank.\n\n'
            'This action cannot be undone.',

            style: TextStyle(color: textGrey, fontSize: 13, height: 1.5),
          ),

          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },

              child: const Text(
                'Cancel',

                style: TextStyle(color: textGrey, fontWeight: FontWeight.w700),
              ),
            ),

            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },

              style: ElevatedButton.styleFrom(
                backgroundColor: redColor,

                foregroundColor: Colors.white,

                elevation: 0,

                padding: const EdgeInsets.symmetric(
                  horizontal: 18,

                  vertical: 11,
                ),

                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              child: const Text(
                'Clear All',

                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      final collection = FirebaseFirestore.instance.collection('questions');

      final snapshot = await collection.get();

      if (snapshot.docs.isEmpty) {
        if (!context.mounted) return;

        _showMessage('There are no questions to delete.', isError: true);

        return;
      }

      for (var i = 0; i < snapshot.docs.length; i += 500) {
        final batch = FirebaseFirestore.instance.batch();

        final end = (i + 500 < snapshot.docs.length)
            ? i + 500
            : snapshot.docs.length;

        for (var j = i; j < end; j++) {
          batch.delete(snapshot.docs[j].reference);
        }

        await batch.commit();
      }

      if (!mounted) return;

      _showMessage('${snapshot.docs.length} questions deleted successfully.');
    } catch (e) {
      if (!mounted) return;

      _showMessage('Failed to clear questions: $e', isError: true);
    }
  }

  // ============================================================

  // DELETE CONFIRMATION

  // ============================================================

  Future<void> confirmDelete(
    BuildContext context,

    String id,

    String questionText,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,

      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),

          title: const Row(
            children: [
              Icon(Icons.delete_outline_rounded, color: redColor, size: 25),

              SizedBox(width: 10),

              Expanded(
                child: Text(
                  'Delete Question?',

                  style: TextStyle(
                    color: textDark,

                    fontSize: 18,

                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),

          content: Text(
            'Are you sure you want to delete this question?\n\n'
            '"$questionText"',

            style: const TextStyle(color: textGrey, fontSize: 13, height: 1.5),
          ),

          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },

              child: const Text(
                'Cancel',

                style: TextStyle(color: textGrey, fontWeight: FontWeight.w700),
              ),
            ),

            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },

              style: ElevatedButton.styleFrom(
                backgroundColor: redColor,

                foregroundColor: Colors.white,

                elevation: 0,

                padding: const EdgeInsets.symmetric(
                  horizontal: 18,

                  vertical: 11,
                ),

                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              child: const Text(
                'Delete',

                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await deleteQuestion(id);

      if (!mounted) return;

      _showMessage('Question deleted successfully.');
    } catch (e) {
      if (!mounted) return;

      _showMessage('Failed to delete question: $e', isError: true);
    }
  }

  // ============================================================

  // MESSAGE

  // ============================================================

  void _showMessage(String message, {bool isError = false}) {
    AdminNotification.show(context, message, isError: isError);
  }

  // ============================================================

  // FILTER

  // ============================================================

  bool matchesFilter(Map<String, dynamic> data) {
    if (selectedFilter == 'All') {
      return true;
    }

    final type = (data['questionType']?.toString() ?? '').trim().toLowerCase();

    final filter = selectedFilter.trim().toLowerCase();

    if (filter == 'fill in the blank') {
      return type == 'fill in the blank' ||
          type == 'fill-in-the-blank' ||
          type == 'fill_in_the_blank' ||
          type == 'fill in blank';
    }

    if (filter == 'true/false' || filter == 'true or false') {
      return type == 'true/false' ||
          type == 'true or false' ||
          type == 'truefalse' ||
          type == 'true / false';
    }

    return type == filter;
  }

  bool matchesSearch(Map<String, dynamic> data) {
    final search = searchController.text.trim().toLowerCase();

    if (search.isEmpty) {
      return true;
    }

    final question = data['question']?.toString().toLowerCase() ?? '';

    final type = data['questionType']?.toString().toLowerCase() ?? '';

    final answer = data['correctAnswer']?.toString().toLowerCase() ?? '';

    return question.contains(search) ||
        type.contains(search) ||
        answer.contains(search);
  }

  // ============================================================

  // SEARCH BAR

  // ============================================================

  Widget searchBar() {
    return Container(
      height: 45,

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(11),

        border: Border.all(color: borderColor),
      ),

      child: TextField(
        controller: searchController,

        style: const TextStyle(color: textDark, fontSize: 12),

        decoration: InputDecoration(
          hintText: 'Search questions...',

          hintStyle: const TextStyle(color: textGrey, fontSize: 11),

          prefixIcon: const Icon(
            Icons.search_rounded,

            color: textGrey,

            size: 19,
          ),

          suffixIcon: searchController.text.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    searchController.clear();
                  },

                  icon: const Icon(
                    Icons.close_rounded,

                    color: textGrey,

                    size: 17,
                  ),
                )
              : null,

          border: InputBorder.none,

          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,

            vertical: 12,
          ),
        ),
      ),
    );
  }

  // ============================================================

  // FILTER BUTTON

  // ============================================================

  Widget filterButton(String title) {
    final bool selected = selectedFilter == title;

    return InkWell(
      onTap: () {
        setState(() {
          selectedFilter = title;
        });
      },

      borderRadius: BorderRadius.circular(9),

      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),

        decoration: BoxDecoration(
          color: selected ? primaryPurple : Colors.white,

          borderRadius: BorderRadius.circular(9),

          border: Border.all(color: selected ? primaryPurple : borderColor),
        ),

        child: Text(
          title,

          style: TextStyle(
            color: selected ? Colors.white : textGrey,

            fontSize: 10,

            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  void _openAddQuestion(BuildContext context) {
    AdminNavPersistence.savePage('add_question');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AddQuestionScreen(),
      ),
    );
  }

  // ============================================================

  // QUESTION TYPES CARD (UNIFIED SUMMARY CARD)

  // ============================================================

  Widget _buildTypeItem({
    required String title,
    required int count,
    required IconData icon,
    required Color color,
    required String filterKey,
  }) {
    final bool isSelected = selectedFilter.toLowerCase() == filterKey.toLowerCase();
    return InkWell(
      onTap: () {
        setState(() {
          selectedFilter = isSelected ? 'All' : filterKey;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.12)
              : const Color(0xFFF9F8FD),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : borderColor,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color, color.withValues(alpha: 0.82)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.28),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 17),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$count',
                    style: const TextStyle(
                      color: textDark,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected ? color : const Color(0xFF64748B),
                      fontSize: 10,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionTypesCard({
    required bool isMobile,
    required int multipleChoiceCount,
    required int identificationCount,
    required int trueFalseCount,
    required int fillBlankCount,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: primaryPurple.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: lightPurple,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.category_rounded,
                  color: primaryPurple,
                  size: 16,
                ),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Question Types',
                      style: TextStyle(
                        color: textDark,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Distribution and count by question format',
                      style: TextStyle(
                        color: textGrey,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (isMobile)
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildTypeItem(
                        title: 'Multiple Choice',
                        count: multipleChoiceCount,
                        icon: Icons.list_alt_rounded,
                        color: const Color(0xFF3578E5),
                        filterKey: 'Multiple Choice',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildTypeItem(
                        title: 'Identification',
                        count: identificationCount,
                        icon: Icons.badge_outlined,
                        color: const Color(0xFF16A34A),
                        filterKey: 'Identification',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildTypeItem(
                        title: 'True/False',
                        count: trueFalseCount,
                        icon: Icons.check_circle_outline_rounded,
                        color: const Color(0xFF8B5CF6),
                        filterKey: 'True/False',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildTypeItem(
                        title: 'Fill in the Blank',
                        count: fillBlankCount,
                        icon: Icons.edit_note_rounded,
                        color: const Color(0xFFE67E22),
                        filterKey: 'Fill in the Blank',
                      ),
                    ),
                  ],
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: _buildTypeItem(
                    title: 'Multiple Choice',
                    count: multipleChoiceCount,
                    icon: Icons.list_alt_rounded,
                    color: const Color(0xFF3578E5),
                    filterKey: 'Multiple Choice',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildTypeItem(
                    title: 'Identification',
                    count: identificationCount,
                    icon: Icons.badge_outlined,
                    color: const Color(0xFF16A34A),
                    filterKey: 'Identification',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildTypeItem(
                    title: 'True/False',
                    count: trueFalseCount,
                    icon: Icons.check_circle_outline_rounded,
                    color: const Color(0xFF8B5CF6),
                    filterKey: 'True/False',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildTypeItem(
                    title: 'Fill in the Blank',
                    count: fillBlankCount,
                    icon: Icons.edit_note_rounded,
                    color: const Color(0xFFE67E22),
                    filterKey: 'Fill in the Blank',
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ============================================================

  // QUESTION TYPE BADGE

  // ============================================================

  Widget questionTypeBadge(String type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),

      decoration: BoxDecoration(
        color: lightPurple,

        borderRadius: BorderRadius.circular(20),

        border: Border.all(
          color: primaryPurple.withValues(alpha: 0.22),
          width: 1,
        ),
      ),

      child: Text(
        type,

        style: const TextStyle(
          color: primaryPurple,

          fontSize: 10.5,

          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  // ============================================================

  // OPTION TILE

  // ============================================================

  Widget optionTile({
    required String label,

    required String text,

    required bool isCorrect,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),

      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),

      decoration: BoxDecoration(
        color: isCorrect ? const Color(0xFFDCFCE7) : Colors.white,

        borderRadius: BorderRadius.circular(12),

        border: Border.all(
          color: isCorrect
              ? const Color(0xFF86EFAC)
              : AdminThemeColors.primary.withValues(alpha: 0.12),
          width: 1.2,
        ),

        boxShadow: [
          BoxShadow(
            color: (isCorrect ? const Color(0xFF22C55E) : Colors.black)
                .withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),

      child: Row(
        children: [
          Container(
            width: 28,

            height: 28,

            alignment: Alignment.center,

            decoration: BoxDecoration(
              gradient: isCorrect
                  ? const LinearGradient(
                      colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,

              color: isCorrect ? null : lightPurple,

              shape: BoxShape.circle,
            ),

            child: Text(
              label,

              style: TextStyle(
                color: isCorrect ? Colors.white : primaryPurple,

                fontSize: 11,

                fontWeight: FontWeight.w900,
              ),
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Text(
              text.isEmpty ? '-' : text,

              style: TextStyle(
                color: isCorrect ? const Color(0xFF15803D) : textDark,

                fontSize: 12,

                fontWeight: isCorrect ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),

          if (isCorrect)
            const Icon(
              Icons.check_circle_rounded,

              color: Color(0xFF16A34A),

              size: 18,
            ),
        ],
      ),
    );
  }

  // ============================================================

  // QUESTION CARD

  // ============================================================

  Widget questionCard(
    BuildContext context,

    QueryDocumentSnapshot doc,

    bool isMobile,
  ) {
    final data = doc.data() as Map<String, dynamic>;

    final String question = data['question']?.toString() ?? 'No question';

    final String correctAnswer = data['correctAnswer']?.toString() ?? '';

    final String optionA = data['optionA']?.toString() ?? '';

    final String optionB = data['optionB']?.toString() ?? '';

    final String optionC = data['optionC']?.toString() ?? '';

    final String optionD = data['optionD']?.toString() ?? '';

    final String questionType =
        data['questionType']?.toString() ?? 'Multiple Choice';

    final bool isMultipleChoice =
        questionType.toLowerCase() == 'multiple choice';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),

      padding: EdgeInsets.all(isMobile ? 15 : 18),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(16),

        border: Border.all(
          color: AdminThemeColors.primary.withValues(alpha: 0.12),
          width: 1.2,
        ),

        boxShadow: [
          BoxShadow(
            color: AdminThemeColors.primary.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          // --------------------------------------------------------

          // TOP
          // --------------------------------------------------------
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Text(
                      question,

                      maxLines: 3,

                      overflow: TextOverflow.ellipsis,

                      style: TextStyle(
                        color: textDark,

                        fontSize: isMobile ? 13.5 : 14.5,

                        height: 1.4,

                        fontWeight: FontWeight.w800,

                        letterSpacing: -0.2,
                      ),
                    ),

                    const SizedBox(height: 8),

                    questionTypeBadge(questionType),
                  ],
                ),
              ),

              const SizedBox(width: 4),

              PopupMenuButton<String>(
                tooltip: 'Question actions',

                padding: EdgeInsets.zero,

                icon: const Icon(
                  Icons.more_vert_rounded,

                  color: textGrey,

                  size: 21,
                ),

                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),

                onSelected: (value) async {
                  if (value == 'edit') {
                    AdminNavPersistence.savePage('edit_question', editQuestionId: doc.id);
                    Navigator.push(
                      context,

                      MaterialPageRoute(
                        builder: (_) => EditQuestionScreen(
                          questionId: doc.id,

                          questionData: data,
                        ),
                      ),
                    );
                  }

                  if (value == 'delete') {
                    confirmDelete(context, doc.id, question);
                  }
                },

                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',

                    child: Row(
                      children: [
                        Icon(
                          Icons.edit_outlined,

                          size: 18,

                          color: primaryPurple,
                        ),

                        SizedBox(width: 9),

                        Text('Edit Question'),
                      ],
                    ),
                  ),

                  const PopupMenuItem(
                    value: 'delete',

                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 18, color: redColor),

                        SizedBox(width: 9),

                        Text('Delete Question'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 13),

          // --------------------------------------------------------

          // ANSWERS
          // --------------------------------------------------------
          if (isMultipleChoice) ...[
            optionTile(
              label: 'A',

              text: optionA,

              isCorrect: correctAnswer == 'A' || correctAnswer == optionA,
            ),

            optionTile(
              label: 'B',

              text: optionB,

              isCorrect: correctAnswer == 'B' || correctAnswer == optionB,
            ),

            optionTile(
              label: 'C',

              text: optionC,

              isCorrect: correctAnswer == 'C' || correctAnswer == optionC,
            ),

            optionTile(
              label: 'D',

              text: optionD,

              isCorrect: correctAnswer == 'D' || correctAnswer == optionD,
            ),
          ] else
            Container(
              width: double.infinity,

              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),

              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),

                borderRadius: BorderRadius.circular(12),

                border: Border.all(
                  color: const Color(0xFF86EFAC),
                  width: 1.2,
                ),
              ),

              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,

                    color: Color(0xFF16A34A),

                    size: 19,
                  ),

                  const SizedBox(width: 9),

                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        children: [
                          const TextSpan(
                            text: 'Correct Answer: ',

                            style: TextStyle(
                              color: Color(0xFF15803D),

                              fontSize: 12,

                              fontWeight: FontWeight.w800,
                            ),
                          ),

                          TextSpan(
                            text: correctAnswer.isEmpty ? '-' : correctAnswer,

                            style: const TextStyle(
                              color: Color(0xFF166534),

                              fontSize: 12,

                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

          if (isMultipleChoice) ...[
            const SizedBox(height: 12),

            // --------------------------------------------------------
            // BOTTOM ACTION (Correct Answer for Multiple Choice)
            // --------------------------------------------------------
            Container(
              padding: const EdgeInsets.only(top: 11),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: AdminThemeColors.primary.withValues(alpha: 0.08),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF16A34A),
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Correct: ${correctAnswer.isEmpty ? '-' : correctAnswer}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: textGrey,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
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

  // EMPTY STATE

  // ============================================================

  Widget emptyState() {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 55),

      child: Column(
        children: [
          Container(
            width: 65,

            height: 65,

            decoration: const BoxDecoration(
              color: lightPurple,

              shape: BoxShape.circle,
            ),

            child: const Icon(
              Icons.quiz_outlined,

              color: primaryPurple,

              size: 30,
            ),
          ),

          const SizedBox(height: 15),

          const Text(
            'No Questions Found',

            style: TextStyle(
              color: textDark,

              fontSize: 17,

              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 6),

          const Text(
            'Your question bank is currently empty.',

            textAlign: TextAlign.center,

            style: TextStyle(color: textGrey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ============================================================

  // ERROR

  // ============================================================

  Widget errorView(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(25),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            Container(
              width: 65,

              height: 65,

              decoration: BoxDecoration(
                color: lightRed,

                borderRadius: BorderRadius.circular(16),
              ),

              child: const Icon(
                Icons.error_outline_rounded,

                color: redColor,

                size: 34,
              ),
            ),

            const SizedBox(height: 14),

            const Text(
              'Unable to Load Questions',

              style: TextStyle(
                color: textDark,

                fontSize: 18,

                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(height: 7),

            Text(
              '$error',

              textAlign: TextAlign.center,

              style: const TextStyle(color: textGrey, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================

  // APP BAR

  // ============================================================

  Future<void> _showProfileMenu(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: lightPurple,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFD8CCF7), width: 2),
                ),
                child: const Icon(
                  Icons.admin_panel_settings_rounded,
                  color: primaryPurple,
                  size: 36,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Admin',
                style: TextStyle(
                  color: textDark,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                user?.email ?? 'No email available',
                textAlign: TextAlign.center,
                style: const TextStyle(color: textGrey, fontSize: 12),
              ),
              const SizedBox(height: 20),
              const Divider(color: borderColor),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    // Close the profile sheet, sign out, and clear protected pages.
                    Navigator.pop(sheetContext);
                    try {
                      await AdminNavPersistence.clear();
                      await LoginScreen.clearSavedCredentials();
                      await FirebaseAuth.instance.signOut();
                      if (!context.mounted) return;
                      Navigator.of(
                        context,
                        rootNavigator: true,
                      ).pushAndRemoveUntil<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => const LoginScreen(clearCredentials: true),
                        ),
                        (route) => false,
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      AdminNotification.error(context, 'Logout failed: $e');
                    }
                  },
                  icon: const Icon(Icons.logout_rounded, size: 19),
                  label: const Text(
                    'Logout',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: lightPurple,
                    foregroundColor: primaryPurple,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _navigateFromAdminSidebar(
    BuildContext context,
    String destination,
  ) async {
    const pageKeys = <String, String>{
      'dashboard': 'dashboard',
      'manage_users': 'manage_users',
      'add_question': 'add_question',
      'question_list': 'question_list',
      'quiz_sessions': 'quiz_sessions',
      'leaderboard': 'leaderboard',
      'reports': 'reports',
    };

    final pageKey = pageKeys[destination];
    if (pageKey != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('technowiz_admin_last_page', pageKey);
    }

    if (!context.mounted) return;

    // Avoid pushing another copy of the currently open Question Bank page.
    if (destination == 'question_list') return;

    final Widget? page;
    switch (destination) {
      case 'dashboard':
        page = const AdminDashboard(restoreLastPage: false);
        break;
      case 'manage_users':
        page = const ManageUsersScreen();
        break;
      case 'add_question':
        page = const AddQuestionScreen();
        break;
      case 'quiz_sessions':
        page = const ManageQuizSessionsScreen();
        break;
      case 'leaderboard':
        page = const AdminLeaderboardScreen();
        break;
      case 'reports':
        page = const AdminReportScreen();
        break;
      default:
        page = null;
    }

    if (page == null || !context.mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) => page!,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  Widget _buildAdminNavigationDrawer(BuildContext context) {
    return AdminSidebar(
      currentPage: 'question_list',
      onDestinationSelected: (destination) {
        _navigateFromAdminSidebar(context, destination);
      },
      onProfileTap: () => _showProfileMenu(context),
    );
  }

  PreferredSizeWidget buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,

      elevation: 0,

      scrolledUnderElevation: 0,

      surfaceTintColor: Colors.transparent,

      automaticallyImplyLeading: false,

      titleSpacing: 16,

      title: Row(
        children: [
          // Purple TechNoWiz Brand Icon Badge (Shield)
          Container(
            width: 38,

            height: 38,

            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  AdminThemeColors.primary,
                  AdminThemeColors.primaryDark,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(11),
              boxShadow: [
                BoxShadow(
                  color: AdminThemeColors.primary.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.admin_panel_settings_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),

          const SizedBox(width: 11),

          // TechNoWiz Brand & Screen Subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      'TechNoWiz',
                      style: TextStyle(
                        color: AdminThemeColors.primaryDark,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                    ),

                    const SizedBox(width: 8),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AdminThemeColors.pillBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AdminThemeColors.primary.withValues(alpha: 0.22),
                          width: 1,
                        ),
                      ),
                      child: const Text(
                        'Question Bank',
                        style: TextStyle(
                          color: AdminThemeColors.primary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 2),

                const Text(
                  'Your quiz question bank',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textGrey,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),

      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: SizedBox(
            width: 40,
            height: 40,
            child: IconButton(
              tooltip: 'Open navigation menu',
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.menu_rounded, color: textDark, size: 24),
              onPressed: () {
                FocusScope.of(context).unfocus();
                _scaffoldKey.currentState?.openEndDrawer();
              },
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================

  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,

      backgroundColor: backgroundColor,

      drawer: _buildAdminNavigationDrawer(context),

      endDrawer: _buildAdminNavigationDrawer(context),

      appBar: buildAppBar(context),

      body: SafeArea(
        top: false,

        child: AdminCircuitBackground(
          child: StreamBuilder<QuerySnapshot>(
          stream: _questionsStream,

          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                  color: primaryPurple,

                  strokeWidth: 2.5,
                ),
              );
            }

            if (snapshot.hasError) {
              return errorView(snapshot.error!);
            }

            final allQuestions = List<QueryDocumentSnapshot>.from(
              snapshot.data?.docs ?? [],
            );

            // ------------------------------------------------------

            // SORT

            // ------------------------------------------------------

            allQuestions.sort((a, b) {
              final aData = a.data() as Map<String, dynamic>;

              final bData = b.data() as Map<String, dynamic>;

              final aCreated = aData['createdAt'];

              final bCreated = bData['createdAt'];

              if (aCreated is Timestamp && bCreated is Timestamp) {
                return bCreated.compareTo(aCreated);
              }

              return 0;
            });

            // ------------------------------------------------------

            // FILTER

            // ------------------------------------------------------

            final filteredQuestions = allQuestions.where((doc) {
              final data = doc.data() as Map<String, dynamic>;

              return matchesFilter(data) && matchesSearch(data);
            }).toList();

            int multipleChoiceCount = 0;
            int identificationCount = 0;
            int trueFalseCount = 0;
            int fillBlankCount = 0;

            for (final doc in allQuestions) {
              final data = doc.data() as Map<String, dynamic>;
              final type = (data['questionType'] ?? '').toString().toLowerCase();
              if (type == 'multiple choice') {
                multipleChoiceCount++;
              } else if (type == 'identification') {
                identificationCount++;
              } else if (type.contains('true') || type.contains('false')) {
                trueFalseCount++;
              } else if (type.contains('fill')) {
                fillBlankCount++;
              }
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                final bool isMobile = constraints.maxWidth < 700;

                final double horizontalPadding = isMobile ? 14 : 24;

                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),

                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,

                    16,

                    horizontalPadding,

                    30,
                  ),

                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),

                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          // ==================================================
                          // QUESTION TYPES CARD (UNIFIED)
                          // ==================================================
                          _buildQuestionTypesCard(
                            isMobile: isMobile,
                            multipleChoiceCount: multipleChoiceCount,
                            identificationCount: identificationCount,
                            trueFalseCount: trueFalseCount,
                            fillBlankCount: fillBlankCount,
                          ),

                          const SizedBox(height: 16),

                          // ==================================================

                          // SEARCH

                          // ==================================================
                          searchBar(),

                          const SizedBox(height: 10),

                          // ==================================================

                          // FILTERS

                          // ==================================================
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,

                            children: [
                              SizedBox(
                                height: 38,
                                width: double.infinity,
                                child: ScrollConfiguration(
                                  behavior: ScrollConfiguration.of(context).copyWith(
                                    dragDevices: {
                                      PointerDeviceKind.touch,
                                      PointerDeviceKind.mouse,
                                      PointerDeviceKind.trackpad,
                                      PointerDeviceKind.stylus,
                                    },
                                    scrollbars: false,
                                  ),
                                  child: SingleChildScrollView(
                                    controller: _filterScrollController,
                                    scrollDirection: Axis.horizontal,
                                    physics: const BouncingScrollPhysics(
                                      parent: AlwaysScrollableScrollPhysics(),
                                    ),
                                    child: Row(
                                      children: [
                                        filterButton('All'),
                                        const SizedBox(width: 7),
                                        filterButton('Multiple Choice'),
                                        const SizedBox(width: 7),
                                        filterButton('Identification'),
                                        const SizedBox(width: 7),
                                        filterButton('True/False'),
                                        const SizedBox(width: 7),
                                        filterButton('Fill in the Blank'),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 18),

                          // ==================================================

                          // QUESTIONS CONTAINER

                          // ==================================================
                          Container(
                            width: double.infinity,

                            decoration: BoxDecoration(
                              color: Colors.white,

                              borderRadius: BorderRadius.circular(16),

                              border: Border.all(
                                color: AdminThemeColors.primary.withValues(alpha: 0.12),
                                width: 1,
                              ),

                              boxShadow: [
                                BoxShadow(
                                  color: AdminThemeColors.primary.withValues(alpha: 0.05),

                                  blurRadius: 12,

                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),

                            child: Column(
                              children: [
                                // ------------------------------------------

                                // SECTION HEADER

                                // ------------------------------------------
                                Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    isMobile ? 14 : 18,

                                    15,

                                    isMobile ? 14 : 18,

                                    13,
                                  ),

                                  child: Row(
                                    children: [
                                      Container(
                                        width: 4,

                                        height: 24,

                                        decoration: BoxDecoration(
                                          color: primaryPurple,

                                          borderRadius: BorderRadius.circular(
                                            5,
                                          ),
                                        ),
                                      ),

                                      const SizedBox(width: 9),

                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,

                                          children: [
                                            const Text(
                                              'All Questions',

                                              style: TextStyle(
                                                color: textDark,

                                                fontSize: 16,

                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),

                                            const SizedBox(height: 2),

                                            Text(
                                              '${filteredQuestions.length} question${filteredQuestions.length == 1 ? '' : 's'} found',

                                              style: const TextStyle(
                                                color: textGrey,

                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      InkWell(
                                        onTap: () => _openAddQuestion(context),
                                        borderRadius: BorderRadius.circular(20),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 11,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [
                                                AdminThemeColors.primary,
                                                AdminThemeColors.primaryDark,
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            borderRadius: BorderRadius.circular(20),
                                            boxShadow: [
                                              BoxShadow(
                                                color: AdminThemeColors.primary.withValues(alpha: 0.35),
                                                blurRadius: 6,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.add_rounded,
                                                color: Colors.white,
                                                size: 15,
                                              ),
                                              SizedBox(width: 4),
                                              Text(
                                                'Add Question',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: 0.2,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const Divider(height: 1, color: borderColor),

                                // ------------------------------------------

                                // LIST

                                // ------------------------------------------
                                Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    isMobile ? 12 : 15,

                                    14,

                                    isMobile ? 12 : 15,

                                    5,
                                  ),

                                  child: filteredQuestions.isEmpty
                                      ? emptyState()
                                      : ListView.builder(
                                          shrinkWrap: true,

                                          physics:
                                              const NeverScrollableScrollPhysics(),

                                          itemCount: filteredQuestions.length,

                                          itemBuilder: (context, index) {
                                            return questionCard(
                                              context,

                                              filteredQuestions[index],

                                              isMobile,
                                            );
                                          },
                                        ),
                                ),

                                // ------------------------------------------

                                // FOOTER

                                // ------------------------------------------
                                Container(
                                  width: double.infinity,

                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 17,

                                    vertical: 11,
                                  ),

                                  decoration: const BoxDecoration(
                                    color: Color(0xFFFAFBFE),

                                    border: Border(
                                      top: BorderSide(color: borderColor),
                                    ),
                                  ),

                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Showing ${filteredQuestions.length} of ${allQuestions.length} questions',

                                          style: const TextStyle(
                                            color: textGrey,

                                            fontSize: 10,
                                          ),
                                        ),
                                      ),

                                      const Text(
                                        'TechNoWiz',

                                        style: TextStyle(
                                          color: textGrey,

                                          fontSize: 10,

                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 18),

                          const Center(
                            child: Text(
                              'TechNoWiz Quiz System',

                              style: TextStyle(color: textGrey, fontSize: 9),
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
  );
  }
}
