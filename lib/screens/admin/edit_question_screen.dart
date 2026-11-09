import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_theme.dart';
import 'question_list_screen.dart';
import '../../navigation_persistence.dart';

class EditQuestionScreen extends StatefulWidget {
  final String questionId;

  final Map<String, dynamic> questionData;

  const EditQuestionScreen({
    super.key,

    required this.questionId,

    required this.questionData,
  });

  @override
  State<EditQuestionScreen> createState() => _EditQuestionScreenState();
}

class _EditQuestionScreenState extends State<EditQuestionScreen> {
  static const Color primaryPurple = AdminThemeColors.primary;

  static const Color lightPurple = AdminThemeColors.pillBg;

  static const Color pageBackground = AdminThemeColors.background;

  static const Color textDark = AdminThemeColors.textPrimary;

  static const Color textMuted = AdminThemeColors.textMuted;

  static const Color borderColor = AdminThemeColors.border;

  static const Color successGreen = Color(0xFF16A765);

  late final TextEditingController questionController;

  late final TextEditingController optionAController;

  late final TextEditingController optionBController;

  late final TextEditingController optionCController;

  late final TextEditingController optionDController;

  String correctAnswer = 'A';

  bool isUpdating = false;

  void _handleBack(BuildContext context) {
    AdminNavPersistence.savePage('question_list');
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacement(
        MaterialPageRoute(builder: (_) => const QuestionListScreen()),
      );
    }
  }

  String get _questionType =>
      (widget.questionData['questionType'] ??
              widget.questionData['type'] ??
              'Multiple Choice')
          .toString()
          .trim()
          .toLowerCase();

  bool get _isTrueFalseType =>
      _questionType.contains('true') && _questionType.contains('false');

  bool get _isWrittenAnswerType =>
      _questionType.contains('identification') ||
      _questionType.contains('enumeration') ||
      _questionType.contains('fill in the blank') ||
      _questionType.contains('fill-in-the-blank') ||
      _questionType.contains('fill blank');

  @override
  void initState() {
    super.initState();
    AdminNavPersistence.savePage(
      'edit_question',
      editQuestionId: widget.questionId,
    );

    questionController = TextEditingController(
      text: widget.questionData['question']?.toString() ?? '',
    );

    optionAController = TextEditingController(
      text:
          (widget.questionData['answer'] ??
                  widget.questionData['acceptedAnswer'] ??
                  widget.questionData['optionA'] ??
                  '')
              .toString(),
    );

    optionBController = TextEditingController(
      text: widget.questionData['optionB']?.toString() ?? '',
    );

    optionCController = TextEditingController(
      text: widget.questionData['optionC']?.toString() ?? '',
    );

    optionDController = TextEditingController(
      text: widget.questionData['optionD']?.toString() ?? '',
    );

    final savedAnswer = (widget.questionData['correctAnswer'] ?? 'A')
        .toString()
        .trim();
    if (_isTrueFalseType) {
      correctAnswer = savedAnswer.toLowerCase() == 'false' || savedAnswer == 'B'
          ? 'B'
          : 'A';
      optionAController.text = 'True';
      optionBController.text = 'False';
      optionCController.clear();
      optionDController.clear();
    } else if (['A', 'B', 'C', 'D'].contains(savedAnswer)) {
      correctAnswer = savedAnswer;
    }

    questionController.addListener(_refreshPreview);

    optionAController.addListener(_refreshPreview);

    optionBController.addListener(_refreshPreview);

    optionCController.addListener(_refreshPreview);

    optionDController.addListener(_refreshPreview);
  }

  void _refreshPreview() {
    if (mounted) setState(() {});
  }

  Future<void> updateQuestion() async {
    final missingAnswer = _isWrittenAnswerType
        ? optionAController.text.trim().isEmpty
        : _isTrueFalseType
        ? !['A', 'B'].contains(correctAnswer)
        : optionAController.text.trim().isEmpty ||
              optionBController.text.trim().isEmpty ||
              optionCController.text.trim().isEmpty ||
              optionDController.text.trim().isEmpty;

    if (questionController.text.trim().isEmpty || missingAnswer) {
      AdminNotification.warning(context, 'Please complete all fields.');
      return;
    }

    setState(() => isUpdating = true);

    try {
      await FirebaseFirestore.instance
          .collection('questions')
          .doc(widget.questionId)
          .update({
            'question': questionController.text.trim(),

            'optionA': _isTrueFalseType
                ? 'True'
                : optionAController.text.trim(),

            'optionB': _isTrueFalseType
                ? 'False'
                : (_isWrittenAnswerType ? '' : optionBController.text.trim()),

            'optionC': _isWrittenAnswerType || _isTrueFalseType
                ? ''
                : optionCController.text.trim(),

            'optionD': _isWrittenAnswerType || _isTrueFalseType
                ? ''
                : optionDController.text.trim(),

            'correctAnswer': correctAnswer,
          });

      if (!mounted) return;

      AdminNotification.success(context, 'Question updated successfully!');

      _handleBack(context);
    } catch (e) {
      if (!mounted) return;

      AdminNotification.error(context, 'Failed to update question: $e');
    } finally {
      if (mounted) setState(() => isUpdating = false);
    }
  }

  Widget _sectionHeading(IconData icon, String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        Container(
          width: 46,

          height: 46,

          decoration: BoxDecoration(
            color: lightPurple,

            borderRadius: BorderRadius.circular(14),
          ),

          child: Icon(icon, color: primaryPurple, size: 25),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  title,

                  style: const TextStyle(
                    color: textDark,

                    fontSize: 17,

                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  subtitle,

                  style: const TextStyle(
                    color: textMuted,

                    fontSize: 12,

                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _panel({
    required Widget child,

    EdgeInsets padding = const EdgeInsets.all(20),
  }) {
    return Container(
      width: double.infinity,

      padding: padding,

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(18),

        border: Border.all(color: borderColor),

        boxShadow: const [
          BoxShadow(
            color: Color(0x0834216B),

            blurRadius: 16,

            offset: Offset(0, 5),
          ),
        ],
      ),

      child: child,
    );
  }

  Widget _textField({
    required TextEditingController controller,

    required String label,

    String? hint,

    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        Text(
          label,

          style: const TextStyle(
            color: textDark,

            fontSize: 13,

            fontWeight: FontWeight.w700,
          ),
        ),

        const SizedBox(height: 8),

        TextField(
          controller: controller,

          enabled: !isUpdating,

          maxLines: maxLines,

          minLines: maxLines == 1 ? 1 : (maxLines >= 3 ? 3 : maxLines),

          style: const TextStyle(
            color: textDark,

            fontSize: 14,

            fontWeight: FontWeight.w500,
          ),

          decoration: InputDecoration(
            hintText: hint,

            hintStyle: const TextStyle(color: Color(0xFF9AA4BD), fontSize: 13),

            filled: true,

            fillColor: const Color(0xFFFEFEFF),

            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,

              vertical: 14,
            ),

            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),

              borderSide: const BorderSide(color: borderColor),
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
      ],
    );
  }

  Widget _answerEditor({
    required String letter,

    required TextEditingController controller,
  }) {
    final selected = correctAnswer == letter;

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),

      child: Row(
        children: [
          Container(
            width: 38,

            height: 38,

            decoration: BoxDecoration(
              color: selected ? const Color(0xFFD8FBE8) : lightPurple,

              borderRadius: BorderRadius.circular(12),
            ),

            alignment: Alignment.center,

            child: Text(
              letter,

              style: TextStyle(
                color: selected ? successGreen : primaryPurple,

                fontWeight: FontWeight.w900,
              ),
            ),
          ),

          const SizedBox(width: 9),

          Expanded(
            child: TextField(
              controller: controller,

              enabled: !isUpdating,

              style: const TextStyle(color: textDark, fontSize: 13),

              decoration: InputDecoration(
                hintText: 'Enter option $letter',

                hintStyle: const TextStyle(
                  color: Color(0xFF9AA4BD),

                  fontSize: 12,
                ),

                isDense: true,

                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,

                  vertical: 13,
                ),

                filled: true,

                fillColor: Colors.white,

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),

                  borderSide: const BorderSide(color: borderColor),
                ),

                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),

                  borderSide: const BorderSide(color: borderColor),
                ),

                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),

                  borderSide: const BorderSide(
                    color: primaryPurple,

                    width: 1.4,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          IconButton(
            tooltip: selected ? 'Correct answer' : 'Set as correct answer',

            onPressed: isUpdating
                ? null
                : () => setState(() => correctAnswer = letter),

            icon: Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,

              color: selected ? successGreen : const Color(0xFF8B98B8),

              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _notesCard() {
    const notes = [
      'Make sure the question is clear and easy to understand.',

      'Review the answer choices for accuracy.',

      'Select the correct answer before saving.',

      'Your changes are saved when you select Update Question.',
    ];

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          _sectionHeading(
            Icons.info_outline_rounded,

            'Important Notes',

            'Keep these in mind when editing.',
          ),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(14),

            decoration: BoxDecoration(
              color: const Color(0xFFF6F1FF),

              borderRadius: BorderRadius.circular(12),
            ),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: notes
                  .map(
                    (note) => Padding(
                      padding: const EdgeInsets.only(bottom: 9),

                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 5),

                            child: Icon(
                              Icons.circle,

                              size: 6,

                              color: primaryPurple,
                            ),
                          ),

                          const SizedBox(width: 9),

                          Expanded(
                            child: Text(
                              note,

                              style: const TextStyle(
                                color: textMuted,

                                fontSize: 12,

                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),

          const SizedBox(height: 16),

          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 330;

              final cancel = OutlinedButton.icon(
                onPressed: isUpdating ? null : () => _handleBack(context),

                icon: const Icon(Icons.close_rounded, size: 18),

                label: const Text('Cancel'),

                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryPurple,

                  side: const BorderSide(color: primaryPurple),

                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,

                    vertical: 14,
                  ),

                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
              );

              final update = ElevatedButton.icon(
                onPressed: isUpdating ? null : updateQuestion,

                icon: isUpdating
                    ? const SizedBox(
                        width: 17,

                        height: 17,

                        child: CircularProgressIndicator(
                          strokeWidth: 2,

                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_rounded, size: 18),

                label: Text(isUpdating ? 'Updating...' : 'Update Question'),

                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryPurple,

                  foregroundColor: Colors.white,

                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,

                    vertical: 14,
                  ),

                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
              );

              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,

                  children: [cancel, const SizedBox(height: 9), update],
                );
              }

              return Wrap(
                alignment: WrapAlignment.end,

                spacing: 9,

                runSpacing: 9,

                children: [cancel, update],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _trueFalseChoice(String label, String value) {
    final selected = correctAnswer == value;
    return InkWell(
      onTap: isUpdating ? null : () => setState(() => correctAnswer = value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFDDFBEA) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFF77E7B0) : borderColor,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? successGreen : const Color(0xFF8B98B8),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: textDark, fontSize: 14),
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_circle_rounded,
                color: successGreen,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  Widget _questionForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        _panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              _sectionHeading(
                Icons.description_outlined,

                'Question Details',

                'Update the question information.',
              ),

              const SizedBox(height: 20),

              _textField(
                controller: questionController,

                label: 'Question Text *',

                hint: 'Enter your question here...',

                maxLines: 4,
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),

        const SizedBox(height: 16),

        _panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              _sectionHeading(
                Icons.format_list_bulleted_rounded,

                'Answer Choices',

                'Edit the answer choices for this question.',
              ),

              const SizedBox(height: 18),

              if (_isWrittenAnswerType) ...[
                _textField(
                  controller: optionAController,
                  label: _questionType.contains('enumeration')
                      ? 'Expected answers *'
                      : 'Accepted answer *',
                  hint: _questionType.contains('enumeration')
                      ? 'Example: Java, Python, C++, JavaScript'
                      : 'Enter the correct answer...',
                  maxLines: _questionType.contains('enumeration') ? 3 : 2,
                ),
                const SizedBox(height: 12),
              ] else if (_isTrueFalseType) ...[
                _trueFalseChoice('True', 'A'),
                _trueFalseChoice('False', 'B'),
                const SizedBox(height: 8),
                const Text(
                  'Select the correct answer above.',
                  style: TextStyle(color: textMuted, fontSize: 12),
                ),
              ] else ...[
                _answerEditor(letter: 'A', controller: optionAController),

                _answerEditor(letter: 'B', controller: optionBController),

                _answerEditor(letter: 'C', controller: optionCController),

                _answerEditor(letter: 'D', controller: optionDController),

                const SizedBox(height: 5),

                Container(
                  width: double.infinity,

                  padding: const EdgeInsets.symmetric(vertical: 12),

                  decoration: BoxDecoration(
                    color: const Color(0xFFFCFAFF),

                    borderRadius: BorderRadius.circular(11),

                    border: Border.all(
                      color: const Color(0xFFDCCBFF),

                      style: BorderStyle.solid,
                    ),
                  ),

                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,

                    children: [
                      Icon(
                        Icons.info_outline_rounded,

                        color: primaryPurple,

                        size: 17,
                      ),

                      SizedBox(width: 7),

                      Flexible(
                        child: Text(
                          'This question uses four answer choices.',

                          style: TextStyle(
                            color: primaryPurple,

                            fontSize: 12,

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
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageBackground,

      appBar: AppBar(
        backgroundColor: Colors.white,

        surfaceTintColor: Colors.transparent,

        elevation: 0,

        automaticallyImplyLeading: false,

        leading: IconButton(
          tooltip: 'Back',

          onPressed: isUpdating ? null : () => _handleBack(context),

          icon: const Icon(Icons.arrow_back_rounded, color: textDark),
        ),

        titleSpacing: 0,

        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            Text(
              'Edit Question',

              style: TextStyle(
                color: textDark,

                fontSize: 18,

                fontWeight: FontWeight.w900,
              ),
            ),

            SizedBox(height: 2),

            Text(
              'Update the details of the selected question.',

              style: TextStyle(color: textMuted, fontSize: 11),
            ),
          ],
        ),
        actions: const [],
      ),

      body: SafeArea(
        child: AdminCircuitBackground(
          child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 1000;

            final horizontalPadding = constraints.maxWidth < 600 ? 12.0 : 24.0;

            final form = _questionForm();

            final side = Column(children: [_notesCard()]);

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,

                18,

                horizontalPadding,

                30,
              ),

              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1450),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      if (isWide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            Expanded(flex: 6, child: form),

                            const SizedBox(width: 16),

                            Expanded(flex: 5, child: side),
                          ],
                        )
                      else ...[
                        form,

                        const SizedBox(height: 16),

                        side,
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  }

  @override
  void dispose() {
    questionController.dispose();

    optionAController.dispose();

    optionBController.dispose();

    optionCController.dispose();

    optionDController.dispose();

    super.dispose();
  }
}
