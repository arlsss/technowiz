import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'admin_dashboard.dart';
import 'manage_users_screen.dart';
import 'question_list_screen.dart';
import 'manage_quiz_sessions_screen.dart';
import 'admin_leaderboard_screen.dart';
import 'admin_report_screen.dart';
import 'admin_sidebar.dart';
import 'admin_theme.dart';
import '../login_screen.dart';
import '../../navigation_persistence.dart';

class AddQuestionScreen extends StatefulWidget {
  const AddQuestionScreen({super.key});

  @override
  State<AddQuestionScreen> createState() => _AddQuestionScreenState();
}

class _AddQuestionScreenState extends State<AddQuestionScreen> {
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

  static const Color successColor = Color(0xFF16A34A);

  static const Color successBackground = Color(0xFFECFDF3);

  static const Color redColor = Color(0xFFEF4444);

  // ============================================================

  // CONTROLLERS

  // ============================================================

  final TextEditingController questionController = TextEditingController();

  final TextEditingController optionAController = TextEditingController();

  final TextEditingController optionBController = TextEditingController();

  final TextEditingController optionCController = TextEditingController();

  final TextEditingController optionDController = TextEditingController();

  final List<TextEditingController> identificationControllers = [
    TextEditingController(),

    TextEditingController(),
  ];

  final List<TextEditingController> enumerationControllers = [
    TextEditingController(),

    TextEditingController(),

    TextEditingController(),
  ];

  // ============================================================

  // VARIABLES

  // ============================================================

  String questionType = "Multiple Choice";

  String correctAnswer = "A";

  final List<Map<String, dynamic>> levels = [
    {'level': 1, 'name': 'Easy'},

    {'level': 2, 'name': 'Hard'},

    {'level': 3, 'name': 'Hardest'},
  ];

  int selectedLevel = 1;

  bool isSaving = false;

  bool isLoadingLevels = false;

  // ============================================================

  // INIT

  // ============================================================

  @override
  void initState() {
    super.initState();
    AdminNavPersistence.savePage('add_question');

    _loadLevels();
  }

  // ============================================================

  // LEVEL HELPERS

  // ============================================================

  Map<String, dynamic> get selectedLevelData {
    return levels.firstWhere(
      (item) => item['level'] == selectedLevel,

      orElse: () => levels.first,
    );
  }

  String get levelName {
    return selectedLevelData['name'].toString();
  }

  String levelDisplayName(int level) {
    final data = levels.firstWhere(
      (item) => item['level'] == level,

      orElse: () => {'level': level, 'name': 'Level $level'},
    );

    return data['name'].toString();
  }

  int get nextLevelNumber {
    if (levels.isEmpty) return 1;

    int maxLevel = 0;

    for (final item in levels) {
      final value = item['level'];

      int? number;

      if (value is int) {
        number = value;
      } else {
        number = int.tryParse(value.toString());
      }

      if (number != null && number > maxLevel) {
        maxLevel = number;
      }
    }

    return maxLevel + 1;
  }

  // ============================================================

  // LOAD LEVELS

  // ============================================================

  Future<void> _loadLevels() async {
    if (mounted) {
      setState(() {
        isLoadingLevels = true;
      });
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('quiz_levels')
          .orderBy('level')
          .get();

      final loadedLevels = <Map<String, dynamic>>[];

      for (final doc in snapshot.docs) {
        final data = doc.data();

        final rawLevel = data['level'];

        int? level;

        if (rawLevel is int) {
          level = rawLevel;
        } else if (rawLevel is double) {
          level = rawLevel.toInt();
        } else {
          level = int.tryParse(rawLevel.toString());
        }

        if (level != null) {
          loadedLevels.add({
            'level': level,

            'name': data['name']?.toString() ?? 'Level $level',
          });
        }
      }

      if (loadedLevels.isNotEmpty) {
        final existingNumbers = loadedLevels
            .map((e) => e['level'] as int)
            .toSet();

        for (final defaultLevel in [
          {'level': 1, 'name': 'Easy'},

          {'level': 2, 'name': 'Hard'},

          {'level': 3, 'name': 'Hardest'},
        ]) {
          if (!existingNumbers.contains(defaultLevel['level'])) {
            loadedLevels.add(defaultLevel);
          }
        }

        loadedLevels.sort(
          (a, b) => (a['level'] as int).compareTo(b['level'] as int),
        );

        if (mounted) {
          setState(() {
            levels
              ..clear()
              ..addAll(loadedLevels);

            if (!levels.any((item) => item['level'] == selectedLevel)) {
              selectedLevel = levels.first['level'] as int;
            }
          });
        }
      }
    } catch (e) {
      // Keep default levels.
    } finally {
      if (mounted) {
        setState(() {
          isLoadingLevels = false;
        });
      }
    }
  }

  // ============================================================

  // ADD LEVEL

  // ============================================================

  Future<void> addLevelDialog() async {
    final TextEditingController levelNameController = TextEditingController();

    final newName = await showDialog<String>(
      context: context,

      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),

          title: const Text(
            'Add Quiz Level',

            style: TextStyle(color: textDark, fontWeight: FontWeight.w800),
          ),

          content: TextField(
            controller: levelNameController,

            textCapitalization: TextCapitalization.words,

            decoration: InputDecoration(
              hintText: 'Enter level name',

              hintStyle: const TextStyle(color: textGrey),

              filled: true,

              fillColor: backgroundColor,

              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),

                borderSide: BorderSide.none,
              ),

              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),

                borderSide: const BorderSide(color: borderColor),
              ),

              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),

                borderSide: const BorderSide(color: primaryPurple, width: 1.5),
              ),
            ),
          ),

          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },

              child: const Text(
                'Cancel',

                style: TextStyle(color: textGrey, fontWeight: FontWeight.w600),
              ),
            ),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryPurple,

                foregroundColor: Colors.white,

                elevation: 0,

                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),

              onPressed: () {
                final value = levelNameController.text.trim();

                if (value.isNotEmpty) {
                  Navigator.pop(dialogContext, value);
                }
              },

              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    levelNameController.dispose();

    if (newName == null || newName.trim().isEmpty) {
      return;
    }

    final newLevel = nextLevelNumber;

    try {
      await FirebaseFirestore.instance
          .collection('quiz_levels')
          .doc('level_$newLevel')
          .set({
            'level': newLevel,

            'name': newName.trim(),

            'createdAt': FieldValue.serverTimestamp(),

            'updatedAt': FieldValue.serverTimestamp(),
          });

      if (!mounted) return;

      setState(() {
        levels.add({'level': newLevel, 'name': newName.trim()});

        levels.sort((a, b) => (a['level'] as int).compareTo(b['level'] as int));

        selectedLevel = newLevel;
      });

      _showMessage('Level added successfully.');
    } catch (e) {
      _showMessage('Failed to add level: $e', isError: true);
    }
  }

  // ============================================================

  // REMOVE LEVEL

  // ============================================================

  Future<void> removeLevelDialog(Map<String, dynamic> level) async {
    final int levelNumber = level['level'] as int;

    final String name = level['name'].toString();

    if (levels.length <= 1) {
      _showMessage('You must keep at least one quiz level.', isError: true);

      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,

      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),

          title: Row(
            children: [
              Container(
                width: 42,

                height: 42,

                decoration: BoxDecoration(
                  color: const Color(0xFFFFEEEE),

                  borderRadius: BorderRadius.circular(11),
                ),

                child: const Icon(
                  Icons.delete_outline_rounded,

                  color: redColor,

                  size: 22,
                ),
              ),

              const SizedBox(width: 11),

              const Expanded(
                child: Text(
                  'Remove Quiz Level?',

                  style: TextStyle(
                    color: textDark,

                    fontSize: 17,

                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),

          content: Text(
            'Are you sure you want to remove '
            'Level $levelNumber - $name?\n\n'
            'This level will no longer be '
            'available when adding questions.',

            style: const TextStyle(color: textGrey, fontSize: 13, height: 1.5),
          ),

          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),

              child: const Text(
                'Cancel',

                style: TextStyle(color: textGrey, fontWeight: FontWeight.w700),
              ),
            ),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: redColor,

                foregroundColor: Colors.white,

                elevation: 0,

                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),

              onPressed: () => Navigator.pop(dialogContext, true),

              child: const Text(
                'Remove',

                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('quiz_levels')
          .doc('level_$levelNumber')
          .delete();

      if (!mounted) return;

      setState(() {
        levels.removeWhere((item) => item['level'] == levelNumber);

        if (selectedLevel == levelNumber) {
          selectedLevel = levels.first['level'] as int;
        }
      });

      _showMessage('Level $levelNumber removed successfully.');
    } catch (e) {
      if (!mounted) return;

      _showMessage('Failed to remove level: $e', isError: true);
    }
  }

  // ============================================================

  // ANSWER HELPERS

  // ============================================================

  String normalizeAnswer(String value) {
    return value.trim();
  }

  List<String> getIdentificationAnswers() {
    return identificationControllers
        .map((controller) => normalizeAnswer(controller.text))
        .where((answer) => answer.isNotEmpty)
        .toList();
  }

  List<String> getEnumerationAnswers() {
    return enumerationControllers
        .map((controller) => normalizeAnswer(controller.text))
        .where((answer) => answer.isNotEmpty)
        .toList();
  }

  // ============================================================

  // SAVE QUESTION

  // ============================================================

  Future<void> saveQuestion() async {
    final question = questionController.text.trim();

    if (question.isEmpty) {
      _showMessage('Please enter a question.', isError: true);

      return;
    }

    if (questionType == "Multiple Choice" ||
        questionType == "Fill in the Blank") {
      if (optionAController.text.trim().isEmpty ||
          optionBController.text.trim().isEmpty ||
          optionCController.text.trim().isEmpty ||
          optionDController.text.trim().isEmpty) {
        _showMessage('Please fill in all answer options.', isError: true);

        return;
      }
    }

    if (questionType == "Identification") {
      final answers = getIdentificationAnswers();

      if (answers.isEmpty) {
        _showMessage(
          'Please enter at least one accepted answer.',

          isError: true,
        );

        return;
      }
    }

    if (questionType == "Enumeration") {
      final answers = getEnumerationAnswers();

      if (answers.isEmpty) {
        _showMessage(
          'Please enter at least one correct answer.',

          isError: true,
        );

        return;
      }
    }

    if (questionType == "True/False") {
      if (correctAnswer != "True" && correctAnswer != "False") {
        _showMessage('Please select True or False.', isError: true);

        return;
      }
    }

    if (mounted) {
      setState(() {
        isSaving = true;
      });
    }

    try {
      final Map<String, dynamic> questionData = {
        'question': question,

        'questionType': questionType,

        'level': selectedLevel,

        'levelName': levelDisplayName(selectedLevel),

        'createdAt': FieldValue.serverTimestamp(),
      };

      if (questionType == "Multiple Choice" ||
          questionType == "Fill in the Blank") {
        String correctText = "";

        if (correctAnswer == "A") {
          correctText = optionAController.text.trim();
        } else if (correctAnswer == "B") {
          correctText = optionBController.text.trim();
        } else if (correctAnswer == "C") {
          correctText = optionCController.text.trim();
        } else if (correctAnswer == "D") {
          correctText = optionDController.text.trim();
        }

        questionData.addAll({
          'optionA': optionAController.text.trim(),

          'optionB': optionBController.text.trim(),

          'optionC': optionCController.text.trim(),

          'optionD': optionDController.text.trim(),

          'correctAnswer': correctAnswer,

          'correctAnswers': [correctText],
        });
      }

      if (questionType == "Identification") {
        final answers = getIdentificationAnswers();

        questionData.addAll({
          'correctAnswers': answers,

          'correctAnswer': answers.first,

          'answer': answers.first,
        });
      }

      if (questionType == "Enumeration") {
        final answers = getEnumerationAnswers();

        questionData.addAll({
          'correctAnswers': answers,

          'correctAnswer': answers.join(', '),
        });
      }

      if (questionType == "True/False") {
        questionData.addAll({
          'correctAnswer': correctAnswer,

          'correctAnswers': [correctAnswer],
        });
      }

      await FirebaseFirestore.instance
          .collection('questions')
          .add(questionData);

      if (!mounted) return;

      _showMessage('Question added successfully.');

      _clearFields();
    } catch (e) {
      if (!mounted) return;

      _showMessage('Failed to save question: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  // ============================================================

  // CLEAR

  // ============================================================

  void _clearFields() {
    questionController.clear();

    optionAController.clear();

    optionBController.clear();

    optionCController.clear();

    optionDController.clear();

    for (final controller in identificationControllers) {
      controller.clear();
    }

    for (final controller in enumerationControllers) {
      controller.clear();
    }

    setState(() {
      correctAnswer = questionType == "True/False" ? "True" : "A";
    });
  }

  // ============================================================

  // MESSAGE

  // ============================================================

  void _showMessage(String message, {bool isError = false}) {
    AdminNotification.show(context, message, isError: isError);
  }

  // ============================================================

  // SECTION TITLE

  // ============================================================

  Widget sectionTitle(String title, {String? subtitle, bool required = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        RichText(
          text: TextSpan(
            text: title,

            style: const TextStyle(
              color: textDark,

              fontSize: 15,

              fontWeight: FontWeight.w800,
            ),

            children: required
                ? const [
                    TextSpan(
                      text: ' *',

                      style: TextStyle(color: redColor),
                    ),
                  ]
                : null,
          ),
        ),

        if (subtitle != null) ...[
          const SizedBox(height: 4),

          Text(
            subtitle,

            style: const TextStyle(color: textGrey, fontSize: 10, height: 1.3),
          ),
        ],
      ],
    );
  }

  // ============================================================

  // PAGE HEADER

  // ============================================================

  Widget pageHeader() {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 24,
        vertical: compact ? 16 : 20,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Colors.white, Color(0xFFF3EEFF)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3DAFF)),
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 44 : 54,
            height: compact ? 44 : 54,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF8247FA), Color(0xFF5D2AE7)],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.note_add_rounded,
              color: Colors.white,
              size: compact ? 23 : 29,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add Question',
                  style: TextStyle(
                    color: textDark,
                    fontSize: compact ? 21 : 29,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  compact
                      ? 'Create a new question for your quiz.'
                      : 'Create a new question for the quiz. Fill out the details below.',
                  style: const TextStyle(
                    color: textGrey,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (!compact)
            const Icon(
              Icons.memory_rounded,
              color: Color(0xFFB9A1FF),
              size: 42,
            ),
        ],
      ),
    );
  }

  Widget questionField() {
    return Container(
      width: double.infinity,

      decoration: BoxDecoration(
        color: backgroundColor,

        borderRadius: BorderRadius.circular(11),

        border: Border.all(color: borderColor),
      ),

      child: TextField(
        controller: questionController,

        maxLines: 5,

        minLines: 5,

        maxLength: 500,

        textCapitalization: TextCapitalization.sentences,

        style: const TextStyle(
          color: textDark,

          fontSize: 13,

          fontWeight: FontWeight.w500,
        ),

        decoration: const InputDecoration(
          hintText: 'Enter your question here...',

          hintStyle: TextStyle(color: Color(0xFF9AA6C5), fontSize: 12),

          border: InputBorder.none,

          contentPadding: EdgeInsets.fromLTRB(13, 13, 13, 8),

          counterStyle: TextStyle(color: textGrey, fontSize: 9),
        ),
      ),
    );
  }

  // ============================================================

  // QUESTION TYPE

  // ============================================================

  Widget questionTypeSelector() {
    const questionTypes = [
      "Multiple Choice",

      "Fill in the Blank",

      "Identification",

      "True/False",
    ];

    return Container(
      height: 54,

      padding: const EdgeInsets.symmetric(horizontal: 12),

      decoration: BoxDecoration(
        color: backgroundColor,

        borderRadius: BorderRadius.circular(11),

        border: Border.all(color: borderColor),
      ),

      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: questionType,

          isExpanded: true,

          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,

            color: textGrey,

            size: 20,
          ),

          dropdownColor: Colors.white,

          borderRadius: BorderRadius.circular(12),

          style: const TextStyle(
            color: textDark,

            fontSize: 12,

            fontWeight: FontWeight.w700,
          ),

          items: questionTypes.map((type) {
            IconData icon;

            switch (type) {
              case "Fill in the Blank":
                icon = Icons.edit_note_rounded;

                break;

              case "Identification":
                icon = Icons.short_text_rounded;

                break;

              case "True/False":
                icon = Icons.check_circle_outline_rounded;

                break;

              default:
                icon = Icons.format_list_bulleted_rounded;
            }

            return DropdownMenuItem<String>(
              value: type,

              child: Row(
                children: [
                  Container(
                    width: 32,

                    height: 32,

                    decoration: BoxDecoration(
                      color: lightPurple,

                      borderRadius: BorderRadius.circular(8),
                    ),

                    child: Icon(icon, color: primaryPurple, size: 17),
                  ),

                  const SizedBox(width: 10),

                  Text(
                    type,

                    style: const TextStyle(
                      color: textDark,

                      fontSize: 12,

                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),

          onChanged: (value) {
            if (value == null) return;

            setState(() {
              questionType = value;

              correctAnswer = questionType == "True/False" ? "True" : "A";
            });
          },
        ),
      ),
    );
  }

  // ============================================================

  // ANSWER TEXT FIELD

  // ============================================================

  Widget answerTextField({
    required TextEditingController controller,

    required String hint,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,

        borderRadius: BorderRadius.circular(9),

        border: Border.all(color: borderColor),
      ),

      child: TextField(
        controller: controller,

        onChanged: (_) {
          // Refresh the Correct Answer dropdown so it shows the option text
          // while the admin types in A, B, C, or D.
          setState(() {});
        },

        style: const TextStyle(
          color: textDark,

          fontSize: 12,

          fontWeight: FontWeight.w500,
        ),

        decoration: InputDecoration(
          hintText: hint,

          hintStyle: const TextStyle(color: Color(0xFF9AA6C5), fontSize: 11),

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

  // OPTION CARD

  // ============================================================

  Widget optionCard({
    required String letter,
    required TextEditingController controller,
    bool showLetter = true,
  }) {
    final bool isCorrect = correctAnswer == letter;

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),

      child: Container(
        padding: const EdgeInsets.all(9),

        decoration: BoxDecoration(
          color: isCorrect ? successBackground : Colors.white,

          borderRadius: BorderRadius.circular(10),

          border: Border.all(
            color: isCorrect ? successColor.withValues(alpha: 0.30) : borderColor,
          ),
        ),

        child: Row(
          children: [
            if (showLetter) ...[
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isCorrect ? successColor : lightPurple,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  letter,
                  style: TextStyle(
                    color: isCorrect ? Colors.white : primaryPurple,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 9),
            ],

            Expanded(
              child: answerTextField(
                controller: controller,

                hint: 'Enter option $letter',
              ),
            ),

            const SizedBox(width: 7),

            InkWell(
              borderRadius: BorderRadius.circular(20),

              onTap: () {
                setState(() {
                  correctAnswer = letter;
                });
              },

              child: Icon(
                isCorrect ? Icons.check_circle : Icons.radio_button_unchecked,

                color: isCorrect ? successColor : textGrey,

                size: 21,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================

  // IDENTIFICATION

  // ============================================================

  Widget identificationAnswer(int index, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),

      child: Row(
        children: [
          Container(
            width: 34,

            height: 34,

            alignment: Alignment.center,

            decoration: const BoxDecoration(
              color: lightPurple,

              shape: BoxShape.circle,
            ),

            child: Text(
              '${index + 1}',

              style: const TextStyle(
                color: primaryPurple,

                fontSize: 11,

                fontWeight: FontWeight.w800,
              ),
            ),
          ),

          const SizedBox(width: 9),

          Expanded(
            child: answerTextField(
              controller: controller,

              hint: 'Enter accepted answer',
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================

  // ENUMERATION

  // ============================================================

  Widget enumerationAnswers() {
    return Column(
      children: List.generate(enumerationControllers.length, (index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 9),

          child: Row(
            children: [
              Container(
                width: 34,

                height: 34,

                alignment: Alignment.center,

                decoration: const BoxDecoration(
                  color: lightPurple,

                  shape: BoxShape.circle,
                ),

                child: Text(
                  '${index + 1}',

                  style: const TextStyle(
                    color: primaryPurple,

                    fontSize: 11,

                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),

              const SizedBox(width: 9),

              Expanded(
                child: answerTextField(
                  controller: enumerationControllers[index],

                  hint: 'Enter correct answer ${index + 1}',
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  // ============================================================

  // TRUE / FALSE

  // ============================================================

  Widget trueFalseSelector() {
    return Row(
      children: [
        Expanded(
          child: _trueFalseButton(
            value: 'True',

            icon: Icons.check_circle_outline_rounded,
          ),
        ),

        const SizedBox(width: 10),

        Expanded(
          child: _trueFalseButton(value: 'False', icon: Icons.cancel_outlined),
        ),
      ],
    );
  }

  Widget _trueFalseButton({required String value, required IconData icon}) {
    final bool selected = correctAnswer == value;

    return GestureDetector(
      onTap: () {
        setState(() {
          correctAnswer = value;
        });
      },

      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),

        height: 48,

        decoration: BoxDecoration(
          color: selected ? primaryPurple : Colors.white,

          borderRadius: BorderRadius.circular(9),

          border: Border.all(color: selected ? primaryPurple : borderColor),
        ),

        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            Icon(
              icon,

              color: selected ? Colors.white : primaryPurple,

              size: 18,
            ),

            const SizedBox(width: 7),

            Text(
              value,

              style: TextStyle(
                color: selected ? Colors.white : textDark,

                fontSize: 12,

                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================

  // CORRECT ANSWER LABEL

  // ============================================================

  Widget correctAnswerCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),

      decoration: BoxDecoration(
        color: successBackground,

        borderRadius: BorderRadius.circular(7),
      ),

      child: const Row(
        mainAxisSize: MainAxisSize.min,

        children: [
          Icon(Icons.check_circle, color: successColor, size: 14),

          SizedBox(width: 5),

          Text(
            'Select correct',

            style: TextStyle(
              color: successColor,

              fontSize: 8,

              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================

  // LEVEL SELECTOR

  // ============================================================

  Widget levelSelector() {
    return Container(
      padding: const EdgeInsets.all(12),

      decoration: BoxDecoration(
        color: backgroundColor,

        borderRadius: BorderRadius.circular(11),

        border: Border.all(color: borderColor),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Row(
            children: [
              const Icon(Icons.layers_outlined, color: primaryPurple, size: 18),

              const SizedBox(width: 7),

              Expanded(
                child: Text(
                  'Level $selectedLevel • $levelName',

                  style: const TextStyle(
                    color: textDark,

                    fontSize: 11,

                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              InkWell(
                borderRadius: BorderRadius.circular(7),

                onTap: addLevelDialog,

                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,

                    vertical: 6,
                  ),

                  decoration: BoxDecoration(
                    color: lightPurple,

                    borderRadius: BorderRadius.circular(7),
                  ),

                  child: const Row(
                    children: [
                      Icon(Icons.add_rounded, color: primaryPurple, size: 14),

                      SizedBox(width: 3),

                      Text(
                        'ADD LEVEL',

                        style: TextStyle(
                          color: primaryPurple,

                          fontSize: 8,

                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          SizedBox(
            height: 62,

            child: isLoadingLevels
                ? const Center(
                    child: SizedBox(
                      width: 18,

                      height: 18,

                      child: CircularProgressIndicator(
                        strokeWidth: 2,

                        color: primaryPurple,
                      ),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,

                    itemCount: levels.length,

                    separatorBuilder: (_, _) => const SizedBox(width: 7),

                    itemBuilder: (context, index) {
                      return levelButton(levels[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget levelButton(Map<String, dynamic> level) {
    final int levelNumber = level['level'] as int;

    final String name = level['name'].toString();

    final bool isSelected = selectedLevel == levelNumber;

    return GestureDetector(
      onTap: () {
        setState(() {
          selectedLevel = levelNumber;
        });
      },

      child: Container(
        width: 105,

        padding: const EdgeInsets.all(8),

        decoration: BoxDecoration(
          color: isSelected ? primaryPurple : Colors.white,

          borderRadius: BorderRadius.circular(9),

          border: Border.all(color: isSelected ? primaryPurple : borderColor),
        ),

        child: Row(
          children: [
            Container(
              width: 25,

              height: 25,

              alignment: Alignment.center,

              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.18)
                    : lightPurple,

                shape: BoxShape.circle,
              ),

              child: Text(
                '$levelNumber',

                style: TextStyle(
                  color: isSelected ? Colors.white : primaryPurple,

                  fontSize: 10,

                  fontWeight: FontWeight.w800,
                ),
              ),
            ),

            const SizedBox(width: 6),

            Expanded(
              child: Text(
                name,

                maxLines: 1,

                overflow: TextOverflow.ellipsis,

                style: TextStyle(
                  color: isSelected ? Colors.white : textDark,

                  fontSize: 9,

                  fontWeight: FontWeight.w700,
                ),
              ),
            ),

            GestureDetector(
              onTap: () => removeLevelDialog(level),

              child: Icon(
                Icons.close_rounded,

                size: 14,

                color: isSelected ? Colors.white70 : textGrey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================

  // FORM CARD

  // ============================================================

  Widget _refCard({
    required IconData icon,
    required String title,
    required Widget child,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F7FF),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: primaryPurple, size: 20),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  color: textDark,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: textGrey, fontSize: 11),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _refDesktopForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFE4E0F8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final type = _refCard(
                icon: Icons.description_outlined,
                title: 'Question Type',
                child: questionTypeSelector(),
              );
              return type;
            },
          ),
          const SizedBox(height: 12),
          _refCard(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Question',
            child: questionField(),
          ),
          if (questionType == 'Multiple Choice' ||
              questionType == 'Fill in the Blank') ...[
            const SizedBox(height: 12),
            _refCard(
              icon: Icons.format_list_bulleted_rounded,
              title: questionType == 'Fill in the Blank'
                  ? 'Blank Answer Choices'
                  : 'Answer Choices',
              subtitle: questionType == 'Fill in the Blank'
                  ? 'Enter choices for the blank and select the correct one.'
                  : 'Select the circle beside the correct answer.',
              child: Column(
                children: [
                  optionCard(
                    letter: 'A',
                    controller: optionAController,
                    showLetter: questionType != 'Fill in the Blank',
                  ),
                  optionCard(
                    letter: 'B',
                    controller: optionBController,
                    showLetter: questionType != 'Fill in the Blank',
                  ),
                  optionCard(
                    letter: 'C',
                    controller: optionCController,
                    showLetter: questionType != 'Fill in the Blank',
                  ),
                  optionCard(
                    letter: 'D',
                    controller: optionDController,
                    showLetter: questionType != 'Fill in the Blank',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _refCard(
              icon: Icons.check_box_rounded,
              title: 'Correct Answer',
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: const Color(0xFFCFC6F5)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: ['A', 'B', 'C', 'D'].contains(correctAnswer)
                        ? correctAnswer
                        : 'A',
                    isExpanded: true,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    style: const TextStyle(color: textDark, fontSize: 12),
                    items: ['A', 'B', 'C', 'D'].map((letter) {
                      final controller = {
                        'A': optionAController,
                        'B': optionBController,
                        'C': optionCController,
                        'D': optionDController,
                      }[letter]!;
                      final text = controller.text.trim();
                      return DropdownMenuItem<String>(
                        value: letter,
                        child: Text(
                          questionType == 'Fill in the Blank'
                              ? (text.isEmpty ? 'Enter choice' : text)
                              : (text.isEmpty
                                    ? '$letter — Enter option $letter'
                                    : '$letter — $text'),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => correctAnswer = value);
                    },
                  ),
                ),
              ),
            ),
          ],
          if (questionType == 'Identification') ...[
            const SizedBox(height: 12),
            _refCard(
              icon: Icons.short_text_rounded,
              title: 'Accepted Answers',
              child: Column(
                children: [
                  identificationAnswer(0, identificationControllers[0]),
                  identificationAnswer(1, identificationControllers[1]),
                ],
              ),
            ),
          ],
          if (questionType == 'Enumeration') ...[
            const SizedBox(height: 12),
            _refCard(
              icon: Icons.format_list_numbered_rounded,
              title: 'Correct Answers',
              child: enumerationAnswers(),
            ),
          ],
          if (questionType == 'True/False') ...[
            const SizedBox(height: 12),
            _refCard(
              icon: Icons.check_box_rounded,
              title: 'Correct Answer',
              child: trueFalseSelector(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _refGuides() {
    Widget bullet(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: primaryPurple,
            size: 18,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: textDark,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );

    Widget panel({
      required IconData icon,
      required String title,
      required Widget child,
    }) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE4E0F8)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: primaryPurple, size: 21),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: textDark,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            child,
          ],
        ),
      );
    }

    Widget typeInfo(String title, String description) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: primaryPurple,
            size: 19,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(
                    color: textGrey,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        panel(
          icon: Icons.lightbulb_outline_rounded,
          title: 'Question Guidelines',
          child: Column(
            children: [
              bullet('Write a clear and concise question.'),
              bullet('Provide 2–4 answer choices.'),
              bullet('Select the correct answer.'),
              bullet('Choose the appropriate level.'),
              bullet(
                'Make sure the question is accurate and relevant to the topic.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        panel(
          icon: Icons.description_outlined,
          title: 'Question Types',
          child: Column(
            children: [
              typeInfo(
                'Multiple Choice',
                'One correct answer from given choices.',
              ),
              const Divider(height: 20, color: borderColor),
              typeInfo(
                'Fill in the Blank',
                'Supply the missing word or phrase to complete the statement.',
              ),
              const Divider(height: 20, color: borderColor),
              typeInfo('Identification', 'Type an accepted answer.'),
              const Divider(height: 20, color: borderColor),
              typeInfo('True or False', 'Choose between True or False.'),
            ],
          ),
        ),
      ],
    );
  }

  Widget buildActionBar() {
    final compact = MediaQuery.sizeOf(context).width < 500;
    Widget clearButton() => SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: isSaving ? null : _clearFields,
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryPurple,
          side: const BorderSide(color: primaryPurple, width: 1.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.close_rounded, size: 18),
            SizedBox(width: 7),
            Text(
              'Clear',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
    Widget saveButton() => SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: isSaving ? null : saveQuestion,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryPurple,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFB8A9EF),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
        ),
        child: isSaving
            ? const SizedBox(
                width: 19,
                height: 19,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.send_rounded, size: 17),
                  SizedBox(width: 7),
                  Text(
                    'Save Question',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
      ),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: borderColor),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                saveButton(),
                const SizedBox(height: 9),
                clearButton(),
              ],
            )
          : Row(
              children: [
                Expanded(child: clearButton()),
                const SizedBox(width: 12),
                Expanded(child: saveButton()),
              ],
            ),
    );
  }

  Future<void> _showGuidesPanel() async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close question guidelines',
      barrierColor: Colors.black.withValues(alpha: 0.28),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final screenWidth = MediaQuery.sizeOf(dialogContext).width;
        final panelWidth = screenWidth < 480 ? screenWidth * 0.92 : 390.0;
        return SafeArea(
          child: Align(
            alignment: Alignment.centerRight,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: panelWidth,
                height: double.infinity,
                margin: const EdgeInsets.only(
                  left: 10,
                  top: 8,
                  bottom: 8,
                  right: 8,
                ),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE4E0F8)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 28,
                      offset: Offset(-8, 0),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: lightPurple,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.tips_and_updates_rounded,
                              color: primaryPurple,
                            ),
                          ),
                          const SizedBox(width: 11),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Question Help',
                                  style: TextStyle(
                                    color: textDark,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'Guidelines, point levels and question types',
                                  style: TextStyle(
                                    color: textGrey,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: textGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: borderColor),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: _refGuides(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final slide =
            Tween<Offset>(
              begin: const Offset(0.12, 0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
        return SlideTransition(position: slide, child: child);
      },
    );
  }

  Future<void> _navigateFromDrawer(String destinationKey) async {
    // Preserve the existing page-restoration key and destination behavior.
    const pageKeys = <String, String>{
      'dashboard': 'dashboard',
      'manage_users': 'manage_users',
      'add_question': 'add_question',
      'question_list': 'question_list',
      'quiz_sessions': 'quiz_sessions',
      'leaderboard': 'leaderboard',
      'reports': 'reports',
    };

    final pageKey = pageKeys[destinationKey];
    if (pageKey != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('technowiz_admin_last_page', pageKey);
    }

    if (!mounted) return;

    // The shared sidebar closes the drawer before invoking this callback.
    // Do not push another copy of the current Add Question screen.
    if (destinationKey == 'add_question') return;

    Widget? destination;
    switch (destinationKey) {
      case 'dashboard':
        destination = const AdminDashboard(restoreLastPage: false);
        break;
      case 'manage_users':
        destination = const ManageUsersScreen();
        break;
      case 'question_list':
        destination = const QuestionListScreen();
        break;
      case 'quiz_sessions':
        destination = const ManageQuizSessionsScreen();
        break;
      case 'leaderboard':
        destination = const AdminLeaderboardScreen();
        break;
      case 'reports':
        destination = const AdminReportScreen();
        break;
    }

    if (destination == null || !mounted) return;

    Navigator.of(
      context,
    ).pushReplacement(adminPageRoute<void>(destination));
  }

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

  Widget _buildAdminDrawer() {
    return AdminSidebar(
      currentPage: 'add_question',
      onDestinationSelected: _navigateFromDrawer,
      onProfileTap: () => _showProfileMenu(context),
    );
  }

  // ============================================================

  // DISPOSE

  // ============================================================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          AdminNavPersistence.savePage('question_list');
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
      drawer: _buildAdminDrawer(),
      backgroundColor: backgroundColor,

      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: kAdminAppBarHeight,
        leading: IconButton(
          tooltip: 'Back to Question Bank',
          onPressed: () {
            AdminNavPersistence.savePage('question_list');
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              Navigator.of(context).pushReplacement(
                adminPageRoute<void>(
                  const QuestionListScreen(),
                ),
              );
            }
          },
          icon: const Icon(Icons.arrow_back_rounded, color: textDark, size: 24),
        ),

        titleSpacing: 0,

        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            Text(
              'Add Question',

              style: TextStyle(
                color: textDark,

                fontSize: 18,

                fontWeight: FontWeight.w800,
              ),
            ),

            SizedBox(height: 2),

            Text(
              'Create a new quiz question',

              style: TextStyle(color: textGrey, fontSize: 9),
            ),
          ],
        ),

        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: IconButton(
              tooltip: 'Question Guidelines',
              onPressed: _showGuidesPanel,
              style: IconButton.styleFrom(
                backgroundColor: lightPurple,
                foregroundColor: primaryPurple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                fixedSize: const Size(40, 40),
              ),
              icon: const Icon(Icons.tips_and_updates_rounded, size: 20),
            ),
          ),
        ],
      ),

      body: SafeArea(
        top: false,

        child: AdminCircuitBackground(
          child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),

              padding: const EdgeInsets.fromLTRB(14, 16, 14, 30),

              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      // CONTENT
                      _refDesktopForm(),

                      const SizedBox(height: 16),

                      // ACTIONS
                      buildActionBar(),

                      const SizedBox(height: 16),

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
        ),
      ),
    ),
  ),
  );
  }

  // ============================================================

  // DISPOSE

  // ============================================================

  @override
  void dispose() {
    questionController.dispose();

    optionAController.dispose();

    optionBController.dispose();

    optionCController.dispose();

    optionDController.dispose();

    for (final controller in identificationControllers) {
      controller.dispose();
    }

    for (final controller in enumerationControllers) {
      controller.dispose();
    }

    super.dispose();
  }
}
