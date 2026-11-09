import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'manage_quiz_sessions_screen.dart';
import 'admin_theme.dart';
import '../../navigation_persistence.dart';

class CreateQuizScreen extends StatefulWidget {
  final String? editQuizCode;

  const CreateQuizScreen({
    super.key,
    this.editQuizCode,
  });

  @override
  State<CreateQuizScreen> createState() => _CreateQuizScreenState();
}

class _CreateQuizScreenState extends State<CreateQuizScreen> {
  static const String _templateDialogOpenKey =
      'technowiz_create_quiz_template_dialog_open';
  static const String _templateDialogEditModeKey =
      'technowiz_create_quiz_template_dialog_edit_mode';

  @override
  void initState() {
    super.initState();
    AdminNavPersistence.savePage('create_quiz');
    if (widget.editQuizCode != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadQuizByCode(widget.editQuizCode!);
      });
    } else {
      _restoreTemplateDialogIfNeeded();
    }
  }

  Future<void> _loadQuizByCode(String code) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('quiz_sessions')
          .doc(code)
          .get();
      if (doc.exists && mounted) {
        _loadExistingQuiz(doc, editMode: true);
      }
    } catch (e) {
      if (mounted) showError('Could not load quiz $code: $e');
    }
  }

  Future<void> _restoreTemplateDialogIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final shouldRestore = prefs.getBool(_templateDialogOpenKey) ?? false;
    if (!shouldRestore) return;

    final editMode = prefs.getBool(_templateDialogEditModeKey) ?? false;

    // Wait until CreateQuizScreen is mounted before showing the dialog.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        chooseExistingQuiz(editMode: editMode);
      }
    });
  }

  Future<void> _saveTemplateDialogState({required bool editMode}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_templateDialogOpenKey, true);
    await prefs.setBool(_templateDialogEditModeKey, editMode);
  }

  Future<void> _clearTemplateDialogState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_templateDialogOpenKey);
    await prefs.remove(_templateDialogEditModeKey);
  }

  void _handleBackNavigation() {
    // If currently using a previous quiz template, back arrow returns to blank Create Quiz mode
    if (duplicateSourceQuizCode != null || editingQuizCode != null) {
      setState(() {
        duplicateSourceQuizCode = null;
        duplicateSourceTitle = null;
        editingQuizCode = null;
        titleController.clear();
        descriptionController.clear();
        locationController.clear();
        selectedDate = null;
        selectedStartTime = null;
        selectedEndTime = null;
      });
      return;
    }

    final navigator = Navigator.of(context);

    if (navigator.canPop()) {
      navigator.pop();
      return;
    }

    // Return to Quiz Sessions / Admin Dashboard safely
    AdminNavPersistence.savePage('quiz_sessions');
    navigator.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => const ManageQuizSessionsScreen(),
      ),
    );
  }

  // =========================================================

  // COLORS

  // =========================================================

  static const Color primaryPurple = AdminThemeColors.primary;

  static const Color lightPurple = AdminThemeColors.pillBg;

  static const Color backgroundColor = AdminThemeColors.background;

  static const Color textDark = AdminThemeColors.textPrimary;

  static const Color textMuted = AdminThemeColors.textMuted;

  static const Color borderColor = AdminThemeColors.border;

  static const Color green = Color(0xFF16A875);

  static const Color lightGreen = Color(0xFFEAF9F3);

  static const Color red = Color(0xFFEF4444);

  // =========================================================

  // CONTROLLERS

  // =========================================================

  final TextEditingController titleController = TextEditingController();

  final TextEditingController descriptionController = TextEditingController();

  final TextEditingController locationController = TextEditingController();

  // =========================================================

  // DATE / TIME

  // =========================================================

  DateTime? selectedDate;

  TimeOfDay? selectedStartTime;

  TimeOfDay? selectedEndTime;

  bool isLoading = false;
  String? editingQuizCode;
  String? duplicateSourceQuizCode;
  String? duplicateSourceTitle;

  // =========================================================

  // GENERATE QUIZ CODE

  // =========================================================

  String generateQuizCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ123456789';

    final random = Random();

    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }

  // =========================================================

  // PICK DATE

  // =========================================================

  Future<void> pickQuizDate() async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,

      initialDate: selectedDate ?? now,

      firstDate: DateTime(2020),

      lastDate: DateTime(now.year + 10),

      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: primaryPurple),
          ),

          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  // =========================================================

  // PICK START TIME

  // =========================================================

  Future<void> pickStartTime() async {
    final picked = await showTimePicker(
      context: context,

      initialTime: selectedStartTime ?? TimeOfDay.now(),

      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: primaryPurple),
          ),

          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        selectedStartTime = picked;

        if (selectedEndTime == null) {
          final startMinutes = picked.hour * 60 + picked.minute;

          final endMinutes = startMinutes + 60;

          selectedEndTime = TimeOfDay(
            hour: (endMinutes ~/ 60) % 24,

            minute: endMinutes % 60,
          );
        }
      });
    }
  }

  // =========================================================

  // PICK END TIME

  // =========================================================

  Future<void> pickEndTime() async {
    final picked = await showTimePicker(
      context: context,

      initialTime:
          selectedEndTime ??
          TimeOfDay(
            hour: ((selectedStartTime?.hour ?? 0) + 1) % 24,

            minute: selectedStartTime?.minute ?? 0,
          ),

      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: primaryPurple),
          ),

          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        selectedEndTime = picked;
      });
    }
  }

  // =========================================================

  // FORMAT DATE

  // =========================================================

  String formatDate(DateTime? date) {
    if (date == null) return "Select date";

    const months = [
      "January",

      "February",

      "March",

      "April",

      "May",

      "June",

      "July",

      "August",

      "September",

      "October",

      "November",

      "December",
    ];

    return "${months[date.month - 1]} ${date.day}, ${date.year}";
  }

  // =========================================================

  // FORMAT TIME

  // =========================================================

  String formatTime(TimeOfDay? time) {
    if (time == null) return "Select time";

    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;

    final minute = time.minute.toString().padLeft(2, '0');

    final period = time.period == DayPeriod.am ? "AM" : "PM";

    return "$hour:$minute $period";
  }

  // =========================================================

  // DATE TIME

  // =========================================================

  DateTime dateTimeFrom(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  // =========================================================

  // ERROR

  // =========================================================

  void _showTopNotification(String message) {
    AdminNotification.success(context, message);
  }

  void showError(String message) {
    AdminNotification.error(context, message);
  }

  // =========================================================
  // SELECT A PREVIOUS QUIZ AS A TEMPLATE
  // =========================================================

  Future<bool> _confirmAndDeleteQuiz(
    QueryDocumentSnapshot<Map<String, dynamic>> quiz,
  ) async {
    final title = (quiz.data()['title'] ?? 'Untitled Quiz').toString();
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Quiz Event?'),
        content: Text(
          'Are you sure you want to delete "$title"? '
          'Its assigned questions will also be deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext, rootNavigator: true).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext, rootNavigator: true).pop(true),
            style: TextButton.styleFrom(foregroundColor: red),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;

    try {
      final questions = await quiz.reference.collection('questions').get();
      final firestore = FirebaseFirestore.instance;
      for (var start = 0; start < questions.docs.length; start += 450) {
        final batch = firestore.batch();
        final end = (start + 450 < questions.docs.length)
            ? start + 450
            : questions.docs.length;
        for (var i = start; i < end; i++) {
          batch.delete(questions.docs[i].reference);
        }
        await batch.commit();
      }
      await quiz.reference.delete();
      if (mounted) {
        _showTopNotification('Deleted "$title".');
      }
      return true;
    } catch (e) {
      if (mounted) showError('Could not delete quiz event: $e');
      return false;
    }
  }

  Future<void> chooseExistingQuiz({required bool editMode}) async {
    try {
      // Persist the dialog state before loading Firestore so a browser refresh
      // can reopen this list when CreateQuizScreen is restored.
      await _saveTemplateDialogState(editMode: editMode);

      final snapshot = await FirebaseFirestore.instance
          .collection('quiz_sessions')
          .get();

      if (!mounted) return;

      var quizzes = snapshot.docs.toList();

      quizzes.sort((a, b) {
        final aTitle = (a.data()['title'] ?? '').toString().toLowerCase();
        final bTitle = (b.data()['title'] ?? '').toString().toLowerCase();
        return aTitle.compareTo(bTitle);
      });

      if (quizzes.isEmpty) {
        await _clearTemplateDialogState();
        if (!mounted) return;
        showError(
          editMode
              ? 'No quiz events are available to edit.'
              : 'No quiz events are available to use as a template.',
        );
        return;
      }

      final selected = await showDialog<QueryDocumentSnapshot<Map<String, dynamic>>>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) {
          var visibleQuizzes =
              List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(quizzes);
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text(
                editMode
                    ? 'Select Quiz Event to Edit'
                    : 'Use Previous Quiz as Template',
              ),
              content: SizedBox(
                width: 480,
                height: MediaQuery.of(context).size.height * 0.62,
                child: visibleQuizzes.isEmpty
                    ? const Center(
                        child: Text('No quiz events available.'),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: visibleQuizzes.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final doc = visibleQuizzes[index];
                          final data = doc.data();
                          return ListTile(
                            leading: Icon(
                              editMode
                                  ? Icons.edit_outlined
                                  : Icons.copy_outlined,
                              color: primaryPurple,
                            ),
                            title: Text(
                              (data['title'] ?? 'Untitled Quiz').toString(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              'Code: ${(data['quizCode'] ?? doc.id).toString()} • '
                              'Status: ${(data['status'] ?? 'unknown').toString()}',
                            ),
                            trailing: IconButton(
                              tooltip: 'Delete quiz event',
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                color: red,
                              ),
                              onPressed: () async {
                                final deleted = await _confirmAndDeleteQuiz(
                                  doc,
                                );
                                if (deleted && context.mounted) {
                                  setDialogState(() {
                                    visibleQuizzes.removeWhere(
                                      (item) => item.id == doc.id,
                                    );
                                  });
                                }
                              },
                            ),
                            onTap: () => Navigator.of(
                              dialogContext,
                              rootNavigator: true,
                            ).pop(doc),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.of(dialogContext, rootNavigator: true).pop(),
                  child: const Text('CANCEL'),
                ),
              ],
            ),
          );
        },
      );

      // Once the dialog closes (CANCEL, outside tap, or selection), do not
      // reopen it on a later refresh.
      await _clearTemplateDialogState();

      if (selected == null || !mounted) return;
      _loadExistingQuiz(selected, editMode: editMode);
    } catch (e) {
      await _clearTemplateDialogState();
      if (mounted) showError('Could not load quiz events: $e');
    }
  }

  DateTime? _dateFromFirestore(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  void _loadExistingQuiz(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required bool editMode,
  }) {
    final data = doc.data() ?? {};

    DateTime? date = _dateFromFirestore(data['date']);
    DateTime? start = _dateFromFirestore(data['startTime']);
    DateTime? end = _dateFromFirestore(data['endTime']);

    setState(() {
      titleController.text = (data['title'] ?? '').toString();
      descriptionController.text = (data['description'] ?? '').toString();
      locationController.text = (data['location'] ?? '').toString();

      selectedDate = date;
      selectedStartTime = start == null
          ? null
          : TimeOfDay(hour: start.hour, minute: start.minute);
      selectedEndTime = end == null
          ? null
          : TimeOfDay(hour: end.hour, minute: end.minute);

      editingQuizCode = null;
      duplicateSourceQuizCode = doc.id;
      duplicateSourceTitle = (data['title'] ?? doc.id).toString();
    });
  }

  // =========================================================
  // COPY A PREVIOUS QUIZ TEMPLATE INTO A NEW EVENT
  // =========================================================

  Future<void> _copyQuizConfiguration({
    required FirebaseFirestore firestore,
    required String sourceQuizCode,
    required DocumentReference<Map<String, dynamic>> destinationRef,
  }) async {
    // Locate the original event by document ID first, then by its quizCode
    // field for compatibility with older records.
    DocumentSnapshot<Map<String, dynamic>> source = await firestore
        .collection('quiz_sessions')
        .doc(sourceQuizCode)
        .get();

    if (!source.exists) {
      final matches = await firestore
          .collection('quiz_sessions')
          .where('quizCode', isEqualTo: sourceQuizCode)
          .limit(1)
          .get();
      if (matches.docs.isEmpty) {
        throw StateError('The previous quiz event could not be found.');
      }
      source = matches.docs.first;
    }

    final sourceData = source.data() ?? <String, dynamic>{};

    // Copy event configuration but never copy runtime state, scores, requests,
    // or the original event identity.
    final copiedData = Map<String, dynamic>.from(sourceData);
    for (final key in <String>[
      'quizCode',
      'status',
      'eventStatus',
      'published',
      'isPublished',
      'isFinished',
      'isCompleted',
      'finished',
      'completed',
      'currentQuestion',
      'currentLevel',
      'level',
      'preparedLevel',
      'timer',
      'countdown',
      'countdownActive',
      'readyCheckId',
      'readyCheckActive',
      'readyCheckType',
      'readyCheckDeadline',
      'readyCheckStartedAt',
      'readyCheckCompleted',
      'initialReadyCheckTriggered',
      'createdAt',
      'updatedAt',
      'startedAt',
      'endedAt',
      'finishedAt',
      'completedAt',
      'winner',
      'winnerId',
      'participants',
      'participantCount',
      'scores',
      'ranking',
      'results',
      'summary',
      'finalScores',
      'submittedAnswers',
    ]) {
      copiedData.remove(key);
    }

    copiedData.addAll({
      'title': titleController.text.trim(),
      'description': descriptionController.text.trim(),
      'date': Timestamp.fromDate(
        DateTime(selectedDate!.year, selectedDate!.month, selectedDate!.day),
      ),
      'startTime': Timestamp.fromDate(
        dateTimeFrom(selectedDate!, selectedStartTime!),
      ),
      'endTime': Timestamp.fromDate(
        dateTimeFrom(selectedDate!, selectedEndTime!),
      ),
      'location': locationController.text.trim(),
      'quizCode': destinationRef.id,
      'status': 'waiting',
      'eventStatus': 'waiting',
      'published': false,
      'isPublished': false,
      'isFinished': false,
      'isCompleted': false,
      'completed': false,
      'finished': false,
      'currentLevel': 1,
      'level': 1,
      'preparedLevel': 1,
      'currentQuestion': 0,
      'timer': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await destinationRef.set(copiedData);

    // Copy question documents only. Join requests and scores belong to the
    // original event and must not be copied into the new one.
    final questionSnapshot = await source.reference
        .collection('questions')
        .get();
    for (var start = 0; start < questionSnapshot.docs.length; start += 450) {
      final batch = firestore.batch();
      final end = (start + 450 < questionSnapshot.docs.length)
          ? start + 450
          : questionSnapshot.docs.length;
      for (var i = start; i < end; i++) {
        final question = questionSnapshot.docs[i];
        batch.set(
          destinationRef.collection('questions').doc(question.id),
          question.data(),
        );
      }
      await batch.commit();
    }
  }

  // =========================================================

  // CREATE QUIZ

  // =========================================================

  Future<void> createQuiz() async {
    final title = titleController.text.trim();

    final description = descriptionController.text.trim();

    final location = locationController.text.trim();

    if (title.isEmpty) {
      showError("Please enter a quiz title.");

      return;
    }

    if (description.isEmpty) {
      showError("Please enter a quiz description.");

      return;
    }

    if (selectedDate == null) {
      showError("Please select a quiz date.");

      return;
    }

    if (location.isEmpty) {
      showError("Please enter the quiz location.");

      return;
    }

    if (selectedStartTime == null) {
      showError("Please select a start time.");

      return;
    }

    if (selectedEndTime == null) {
      showError("Please select an end time.");

      return;
    }

    final startDateTime = dateTimeFrom(selectedDate!, selectedStartTime!);

    final endDateTime = dateTimeFrom(selectedDate!, selectedEndTime!);

    if (!endDateTime.isAfter(startDateTime)) {
      showError("End time must be later than start time.");

      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final dateValue = Timestamp.fromDate(
        DateTime(selectedDate!.year, selectedDate!.month, selectedDate!.day),
      );
      final startValue = Timestamp.fromDate(startDateTime);
      final endValue = Timestamp.fromDate(endDateTime);

      if (editingQuizCode != null) {
        // Update only event details; preserve quiz code, status, scores and history.
        await firestore
            .collection('quiz_sessions')
            .doc(editingQuizCode)
            .update({
              "title": title,
              "description": description,
              "date": dateValue,
              "startTime": startValue,
              "endTime": endValue,
              "location": location,
              "updatedAt": FieldValue.serverTimestamp(),
            });

        final code = editingQuizCode!;
        if (!mounted) return;
        setState(() {
          isLoading = false;
          editingQuizCode = null;
        });
        await _showQuizSavedDialog(code, edited: true);
      } else {
        // Avoid accidental quiz-code collisions.
        String code;
        DocumentReference<Map<String, dynamic>> quizRef;
        do {
          code = generateQuizCode();
          quizRef = firestore.collection('quiz_sessions').doc(code);
        } while ((await quizRef.get()).exists);

        if (duplicateSourceQuizCode != null) {
          // Duplicate the configuration and question bank into a NEW event.
          // The original event, its scores, join requests, and history remain
          // untouched.
          await _copyQuizConfiguration(
            firestore: firestore,
            sourceQuizCode: duplicateSourceQuizCode!,
            destinationRef: quizRef,
          );
        } else {
          await quizRef.set({
            "title": title,
            "description": description,
            "date": dateValue,
            "startTime": startValue,
            "endTime": endValue,
            "location": location,
            "quizCode": code,
            "status": "waiting",
            "eventStatus": "waiting",
            "published": false,
            "isPublished": false,
            "isFinished": false,
            "isCompleted": false,
            "completed": false,
            "finished": false,
            "currentQuestion": 0,
            "currentLevel": 1,
            "level": 1,
            "preparedLevel": 1,
            "timer": 0,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
          });
        }

        final notificationRef = firestore.collection('notifications').doc();
        await notificationRef.set({
          "type": "quiz_created",
          "title": "New Quiz Created",
          "message": duplicateSourceQuizCode != null
              ? 'Admin duplicated quiz event "$title" into a new event.'
              : 'Admin created a new quiz session: "$title".',
          "quizCode": code,
          "quizTitle": title,
          "createdAt": FieldValue.serverTimestamp(),
          "isRead": false,
        });

        if (!mounted) return;
        setState(() {
          isLoading = false;
          duplicateSourceQuizCode = null;
        });
        await _showQuizCreatedDialog(code);
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      showError(
        editingQuizCode != null
            ? "Failed to update quiz event: $e"
            : "Failed to create quiz: $e",
      );
    }
  }

  Future<void> _showQuizSavedDialog(String code, {required bool edited}) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(edited ? 'Quiz Event Updated' : 'Quiz Event Saved'),
        content: Text(
          edited
              ? 'The quiz event "$code" details have been updated. Its existing quiz code and history were preserved.'
              : 'The quiz event has been saved.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext, rootNavigator: true).pop();
              if (mounted) {
                final navigator = Navigator.of(context);
                if (navigator.canPop()) {
                  navigator.pop();
                } else {
                  AdminNavPersistence.savePage('quiz_sessions');
                  navigator.pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) => const ManageQuizSessionsScreen(),
                    ),
                  );
                }
              }
            },
            child: const Text('DONE'),
          ),
        ],
      ),
    );
  }

  // =========================================================

  // CREATED DIALOG

  // =========================================================

  Future<void> _showQuizCreatedDialog(String code) async {
    await showDialog(
      context: context,

      barrierDismissible: false,

      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,

          elevation: 12,

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),

          contentPadding: const EdgeInsets.fromLTRB(24, 26, 24, 18),

          content: Column(
            mainAxisSize: MainAxisSize.min,

            children: [
              Container(
                width: 58,

                height: 58,

                decoration: BoxDecoration(
                  color: lightGreen,

                  borderRadius: BorderRadius.circular(16),
                ),

                child: const Icon(Icons.check_rounded, color: green, size: 30),
              ),

              const SizedBox(height: 16),

              const Text(
                "Quiz Created",

                style: TextStyle(
                  color: textDark,

                  fontSize: 20,

                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                "Your quiz session has been created successfully.",

                textAlign: TextAlign.center,

                style: TextStyle(color: textMuted, fontSize: 12, height: 1.5),
              ),

              const SizedBox(height: 18),

              Container(
                width: double.infinity,

                padding: const EdgeInsets.symmetric(
                  horizontal: 18,

                  vertical: 15,
                ),

                decoration: BoxDecoration(
                  color: lightPurple,

                  borderRadius: BorderRadius.circular(12),

                  border: Border.all(color: primaryPurple.withAlpha(30)),
                ),

                child: Column(
                  children: [
                    const Text(
                      "QUIZ CODE",

                      style: TextStyle(
                        color: textMuted,

                        fontSize: 9,

                        fontWeight: FontWeight.w800,

                        letterSpacing: 1,
                      ),
                    ),

                    const SizedBox(height: 7),

                    Text(
                      code,

                      style: const TextStyle(
                        color: primaryPurple,

                        fontSize: 25,

                        fontWeight: FontWeight.w900,

                        letterSpacing: 4,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,

                height: 45,

                child: ElevatedButton(
                  onPressed: () {
                    // Close the success dialog, then replace Create Quiz Event
                    // with the Admin Quiz Sessions page instead of returning to
                    // the Admin Dashboard.
                    Navigator.of(dialogContext, rootNavigator: true).pop();
                    if (!mounted) return;
                    Navigator.of(context, rootNavigator: true).pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (_) => const ManageQuizSessionsScreen(),
                      ),
                    );
                  },

                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryPurple,

                    foregroundColor: Colors.white,

                    elevation: 0,

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),

                  child: const Text(
                    "DONE",

                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // =========================================================

  // INPUT FIELD

  // =========================================================

  Widget inputField({
    required TextEditingController controller,

    required String label,

    required String hint,

    required IconData icon,

    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        Text(
          label,

          style: const TextStyle(
            color: textDark,

            fontSize: 11,

            fontWeight: FontWeight.w700,
          ),
        ),

        const SizedBox(height: 7),

        TextField(
          controller: controller,

          maxLines: maxLines,

          style: const TextStyle(
            color: textDark,

            fontSize: 12,

            fontWeight: FontWeight.w500,
          ),

          decoration: InputDecoration(
            hintText: hint,

            hintStyle: const TextStyle(color: textMuted, fontSize: 11),

            prefixIcon: Padding(
              padding: EdgeInsets.only(
                left: 13,

                right: maxLines > 1 ? 5 : 7,

                top: maxLines > 1 ? 12 : 0,
              ),

              child: Icon(icon, color: primaryPurple, size: 18),
            ),

            prefixIconConstraints: const BoxConstraints(minWidth: 42),

            filled: true,

            fillColor: const Color(0xFFFBFBFD),

            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,

              vertical: 13,
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

              borderSide: const BorderSide(color: primaryPurple, width: 1.4),
            ),
          ),
        ),
      ],
    );
  }

  // =========================================================

  // PICKER FIELD

  // =========================================================

  Widget pickerField({
    required String label,

    required String value,

    required IconData icon,

    required VoidCallback onTap,

    bool selected = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        Text(
          label,

          style: const TextStyle(
            color: textDark,

            fontSize: 11,

            fontWeight: FontWeight.w700,
          ),
        ),

        const SizedBox(height: 7),

        InkWell(
          onTap: onTap,

          borderRadius: BorderRadius.circular(11),

          child: Container(
            width: double.infinity,

            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),

            decoration: BoxDecoration(
              color: const Color(0xFFFBFBFD),

              borderRadius: BorderRadius.circular(11),

              border: Border.all(
                color: selected ? primaryPurple.withAlpha(90) : borderColor,
              ),
            ),

            child: Row(
              children: [
                Container(
                  width: 34,

                  height: 34,

                  decoration: BoxDecoration(
                    color: lightPurple,

                    borderRadius: BorderRadius.circular(9),
                  ),

                  child: Icon(icon, color: primaryPurple, size: 16),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: Text(
                    value,

                    maxLines: 1,

                    overflow: TextOverflow.ellipsis,

                    style: TextStyle(
                      color: selected ? textDark : textMuted,

                      fontSize: 11,

                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),

                const Icon(
                  Icons.keyboard_arrow_down_rounded,

                  color: textMuted,

                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // =========================================================

  // STEP ITEM

  // =========================================================

  Widget stepItem({
    required int number,

    required String title,

    required bool active,

    required bool completed,
  }) {
    return Expanded(
      child: Row(
        children: [
          Container(
            width: 31,

            height: 31,

            decoration: BoxDecoration(
              color: active || completed
                  ? primaryPurple
                  : const Color(0xFFF0F1F5),

              shape: BoxShape.circle,
            ),

            child: Center(
              child: completed
                  ? const Icon(
                      Icons.check_rounded,

                      color: Colors.white,

                      size: 16,
                    )
                  : Text(
                      "$number",

                      style: TextStyle(
                        color: active ? Colors.white : textMuted,

                        fontSize: 11,

                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),

          const SizedBox(width: 9),

          Flexible(
            child: Text(
              title,

              overflow: TextOverflow.ellipsis,

              style: TextStyle(
                color: active ? textDark : textMuted,

                fontSize: 10,

                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),

          if (number != 3)
            Expanded(
              child: Container(
                height: 1,

                margin: const EdgeInsets.symmetric(horizontal: 12),

                color: borderColor,
              ),
            ),
        ],
      ),
    );
  }

  // =========================================================

  Widget sectionTitle({
    required IconData icon,

    required String title,

    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        Container(
          width: 38,

          height: 38,

          decoration: BoxDecoration(
            color: lightPurple,

            borderRadius: BorderRadius.circular(10),
          ),

          child: Icon(icon, color: primaryPurple, size: 19),
        ),

        const SizedBox(width: 11),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              Text(
                title,

                style: const TextStyle(
                  color: textDark,

                  fontSize: 16,

                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 3),

              Text(
                subtitle,

                style: const TextStyle(
                  color: textMuted,

                  fontSize: 10,

                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =========================================================

  // INFO ROW

  // =========================================================

  Widget infoRow() {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(13),

      decoration: BoxDecoration(
        color: const Color(0xFFFBF9FF),

        borderRadius: BorderRadius.circular(11),

        border: Border.all(color: primaryPurple.withAlpha(25)),
      ),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Container(
            width: 34,

            height: 34,

            decoration: BoxDecoration(
              color: lightPurple,

              borderRadius: BorderRadius.circular(9),
            ),

            child: Icon(
              duplicateSourceQuizCode != null
                  ? Icons.copy_rounded
                  : Icons.auto_awesome_outlined,

              color: primaryPurple,

              size: 17,
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  duplicateSourceQuizCode != null
                      ? "Using Previous Quiz: ${duplicateSourceTitle ?? duplicateSourceQuizCode}"
                      : "Automatic Quiz Code",

                  style: const TextStyle(
                    color: textDark,

                    fontSize: 11,

                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  duplicateSourceQuizCode != null
                      ? "A new 6-character quiz code will be generated for this event. All questions from '$duplicateSourceTitle' will be copied over. You can edit the date, times, title, and location above before creating."
                      : "A new 6-character quiz code is generated for every new event. You can load a previous quiz as a template to reuse its settings and questions without changing the original event.",

                  style: const TextStyle(color: textMuted, fontSize: 10, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================

  // BUILD

  // =========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,

      // =======================================================

      // APP BAR

      // =======================================================
      appBar: AppBar(
        backgroundColor: Colors.white,

        surfaceTintColor: Colors.white,

        elevation: 0,

        scrolledUnderElevation: 0,

        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: textDark, size: 21),

          tooltip: duplicateSourceQuizCode != null
              ? 'Clear and back to blank Create Quiz'
              : 'Back',

          onPressed: _handleBackNavigation,
        ),

        titleSpacing: 0,

        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Create Quiz Event",
              style: TextStyle(
                color: textDark,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (duplicateSourceQuizCode != null)
              Text(
                "Using previous quiz: ${duplicateSourceTitle ?? duplicateSourceQuizCode}",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: primaryPurple,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),

        actions: [
          TextButton.icon(
            onPressed: isLoading
                ? null
                : () => chooseExistingQuiz(editMode: true),
            icon: Icon(
              duplicateSourceQuizCode != null
                  ? Icons.swap_horiz_rounded
                  : Icons.edit_note_rounded,
              size: 17,
            ),
            label: Text(
              duplicateSourceQuizCode != null
                  ? 'Switch Previous Quiz'
                  : 'Edit Previous Event',
            ),
            style: TextButton.styleFrom(
              foregroundColor: primaryPurple,
              textStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],

        toolbarHeight: 62,

        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),

          child: Divider(height: 1, thickness: 1, color: borderColor),
        ),
      ),

      // =======================================================

      // BODY

      // =======================================================
      body: SafeArea(
        top: false,

        child: AdminCircuitBackground(
          child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;

            final isMobile = width < 700;

            final horizontalPadding = isMobile ? 14.0 : 24.0;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,

                22,

                horizontalPadding,

                35,
              ),

              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      // =================================================

                      // BASIC INFORMATION

                      // =================================================
                      Container(
                        width: double.infinity,

                        padding: EdgeInsets.all(isMobile ? 17 : 22),

                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFE9E4F8)),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF34216B).withAlpha(8),
                              blurRadius: 16,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            sectionTitle(
                              icon: Icons.description_outlined,

                              title: "Quiz Information",

                              subtitle:
                                  "Enter the basic details for your quiz.",
                            ),

                            const SizedBox(height: 20),

                            inputField(
                              controller: titleController,

                              label: "Quiz Title",

                              hint: "Enter quiz title",

                              icon: Icons.title_rounded,
                            ),

                            const SizedBox(height: 16),

                            inputField(
                              controller: descriptionController,

                              label: "Description",

                              hint: "Enter quiz description",

                              icon: Icons.notes_outlined,

                              maxLines: 4,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // =================================================

                      // SCHEDULE & LOCATION

                      // =================================================
                      Container(
                        width: double.infinity,

                        padding: EdgeInsets.all(isMobile ? 17 : 22),

                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFE9E4F8)),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF34216B).withAlpha(8),
                              blurRadius: 16,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            sectionTitle(
                              icon: Icons.calendar_month_outlined,

                              title: "Schedule & Location",

                              subtitle:
                                  "Set when and where the quiz session will take place.",
                            ),

                            const SizedBox(height: 20),

                            if (isMobile) ...[
                              pickerField(
                                label: "Quiz Date",

                                value: formatDate(selectedDate),

                                icon: Icons.calendar_today_outlined,

                                selected: selectedDate != null,

                                onTap: pickQuizDate,
                              ),

                              const SizedBox(height: 14),

                              inputField(
                                controller: locationController,

                                label: "Location",

                                hint: "Enter quiz location",

                                icon: Icons.location_on_outlined,
                              ),

                              const SizedBox(height: 14),

                              Row(
                                children: [
                                  Expanded(
                                    child: pickerField(
                                      label: "Start Time",

                                      value: formatTime(selectedStartTime),

                                      icon: Icons.schedule_outlined,

                                      selected: selectedStartTime != null,

                                      onTap: pickStartTime,
                                    ),
                                  ),

                                  const SizedBox(width: 10),

                                  Expanded(
                                    child: pickerField(
                                      label: "End Time",

                                      value: formatTime(selectedEndTime),

                                      icon: Icons.schedule_outlined,

                                      selected: selectedEndTime != null,

                                      onTap: pickEndTime,
                                    ),
                                  ),
                                ],
                              ),
                            ] else ...[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,

                                children: [
                                  Expanded(
                                    child: pickerField(
                                      label: "Quiz Date",

                                      value: formatDate(selectedDate),

                                      icon: Icons.calendar_today_outlined,

                                      selected: selectedDate != null,

                                      onTap: pickQuizDate,
                                    ),
                                  ),

                                  const SizedBox(width: 14),

                                  Expanded(
                                    child: inputField(
                                      controller: locationController,

                                      label: "Location",

                                      hint: "Enter quiz location",

                                      icon: Icons.location_on_outlined,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 15),

                              Row(
                                children: [
                                  Expanded(
                                    child: pickerField(
                                      label: "Start Time",

                                      value: formatTime(selectedStartTime),

                                      icon: Icons.schedule_outlined,

                                      selected: selectedStartTime != null,

                                      onTap: pickStartTime,
                                    ),
                                  ),

                                  const SizedBox(width: 14),

                                  Expanded(
                                    child: pickerField(
                                      label: "End Time",

                                      value: formatTime(selectedEndTime),

                                      icon: Icons.schedule_outlined,

                                      selected: selectedEndTime != null,

                                      onTap: pickEndTime,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // =================================================

                      // AUTOMATIC CODE INFO

                      // =================================================
                      infoRow(),

                      const SizedBox(height: 16),

                      // =================================================

                      // CREATE ACTION

                      // =================================================
                      Container(
                        width: double.infinity,

                        padding: EdgeInsets.all(isMobile ? 15 : 17),

                        decoration: BoxDecoration(
                          color: Colors.white,

                          borderRadius: BorderRadius.circular(15),

                          border: Border.all(color: borderColor),
                        ),

                        child: isMobile
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,

                                children: [
                                  Text(
                                    editingQuizCode != null
                                        ? "Ready to update?"
                                        : "Ready to create?",

                                    style: TextStyle(
                                      color: textDark,

                                      fontSize: 12,

                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),

                                  const SizedBox(height: 3),

                                  Text(
                                    editingQuizCode != null
                                        ? "Review the changes before saving this quiz event."
                                        : "Review the information before creating your quiz event.",

                                    style: TextStyle(
                                      color: textMuted,

                                      fontSize: 10,
                                    ),
                                  ),

                                  const SizedBox(height: 13),

                                  SizedBox(
                                    width: double.infinity,

                                    height: 46,

                                    child: ElevatedButton.icon(
                                      onPressed: isLoading ? null : createQuiz,

                                      icon: isLoading
                                          ? const SizedBox(
                                              width: 17,

                                              height: 17,

                                              child: CircularProgressIndicator(
                                                color: Colors.white,

                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.add_circle_outline_rounded,

                                              size: 18,
                                            ),

                                      label: Text(
                                        isLoading
                                            ? (editingQuizCode != null
                                                  ? "Saving..."
                                                  : "Creating...")
                                            : (editingQuizCode != null
                                                  ? "Save Changes"
                                                  : "Create Quiz Event"),

                                        style: const TextStyle(
                                          fontSize: 12,

                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),

                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: primaryPurple,

                                        foregroundColor: Colors.white,

                                        disabledBackgroundColor: primaryPurple
                                            .withAlpha(130),

                                        elevation: 0,

                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            11,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,

                                      children: [
                                        Text(
                                          (editingQuizCode != null
                                              ? "Ready to update?"
                                              : "Ready to create?"),

                                          style: TextStyle(
                                            color: textDark,

                                            fontSize: 12,

                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),

                                        SizedBox(height: 3),

                                        Text(
                                          (editingQuizCode != null
                                              ? "Review the changes before saving this quiz event."
                                              : "Review the information before creating your quiz event."),

                                          style: TextStyle(
                                            color: textMuted,

                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(width: 15),

                                  SizedBox(
                                    height: 46,

                                    width: 180,

                                    child: ElevatedButton.icon(
                                      onPressed: isLoading ? null : createQuiz,

                                      icon: isLoading
                                          ? const SizedBox(
                                              width: 17,

                                              height: 17,

                                              child: CircularProgressIndicator(
                                                color: Colors.white,

                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.add_circle_outline_rounded,

                                              size: 18,
                                            ),

                                      label: Text(
                                        isLoading
                                            ? (editingQuizCode != null
                                                  ? "Saving..."
                                                  : "Creating...")
                                            : (editingQuizCode != null
                                                  ? "Save Changes"
                                                  : "Create Quiz Event"),

                                        style: const TextStyle(
                                          fontSize: 12,

                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),

                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: primaryPurple,

                                        foregroundColor: Colors.white,

                                        disabledBackgroundColor: primaryPurple
                                            .withAlpha(130),

                                        elevation: 0,

                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            11,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),

                      const SizedBox(height: 24),

                      // =================================================

                      // FOOTER

                      // =================================================
                      const Center(
                        child: Text(
                          "TechNoWiz Quiz System • Admin Panel",

                          style: TextStyle(
                            color: textMuted,

                            fontSize: 9,

                            fontWeight: FontWeight.w500,
                          ),
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
  );
  }

  // =========================================================

  // DISPOSE

  // =========================================================

  @override
  void dispose() {
    titleController.dispose();

    descriptionController.dispose();

    locationController.dispose();

    super.dispose();
  }
}
