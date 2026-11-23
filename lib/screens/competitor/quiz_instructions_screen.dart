import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'technowiz_theme.dart';

/// Reusable Level Instructions UI for WaitingRoomScreen & QuizScreen.
/// Displays the exact standard Level 1 card layout uniformly across ALL levels
/// (Level 1, Level 2, Level 3, Level 4 and above) with TechCircuitBackground.
class QuizInstructionsScreen extends StatefulWidget {
  final Map<String, dynamic> quizData;
  final int level;
  final String? quizCode;

  const QuizInstructionsScreen({
    super.key,
    required this.quizData,
    required this.level,
    this.quizCode,
  });

  @override
  State<QuizInstructionsScreen> createState() => _QuizInstructionsScreenState();
}

class _QuizInstructionsScreenState extends State<QuizInstructionsScreen> {
  static const Color _background = Color(0xFFF2FBF5);
  static const Color _primaryGreen = Color(0xFF16A34A);
  static const Color _darkGreen = Color(0xFF14532D);
  static const Color _lightGreen = Color(0xFFECFDF3);
  static const Color _textDark = Color(0xFF1F2937);

  int? _proceedCount;
  int? _points;
  String? _questionTypes;

  @override
  void initState() {
    super.initState();
    _computeInitialValues();
    _loadAsyncOverrides();
  }

  @override
  void didUpdateWidget(covariant QuizInstructionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.level != widget.level ||
        oldWidget.quizCode != widget.quizCode ||
        oldWidget.quizData != widget.quizData) {
      _computeInitialValues();
      _loadAsyncOverrides();
    }
  }

  int _readInt(dynamic value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  int? _configuredPoints(Map<String, dynamic> source) {
    const keys = [
      'pointsPerQuestion',
      'points_per_question',
      'pointValue',
      'point_value',
      'points',
      'point',
      'pointsPerCorrectAnswer',
      'points_per_correct_answer',
      'pointsPerCorrect',
      'correctAnswerPoints',
      'scorePerQuestion',
      'scoreValue',
      'questionPoints',
    ];

    for (final key in keys) {
      final value = source[key];
      if (value != null) {
        final parsed = value is num
            ? value.toInt()
            : int.tryParse(value.toString().trim());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  String _normalizeLevelKey(dynamic key) {
    return key.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  Map<String, dynamic>? _findLevelSettings(
    dynamic rawAllSettings,
    int instructionLevel,
  ) {
    if (rawAllSettings is! Map) return null;

    final target = 'level$instructionLevel';
    for (final entry in rawAllSettings.entries) {
      final key = _normalizeLevelKey(entry.key);
      if ((key == target || key == '$instructionLevel') && entry.value is Map) {
        return Map<String, dynamic>.from(entry.value as Map);
      }
    }
    return null;
  }

  int? _extractProceedCount(
    Map<String, dynamic> source, [
    int? instructionLevel,
  ]) {
    final directKeys = [
      'proceedCount',
      'participantsToProceed',
      'proceed_count',
      'participants_to_proceed',
      'eliminateCount',
      'eliminationCount',
      'eliminations',
      'eliminate_count',
    ];
    for (final k in directKeys) {
      if (source.containsKey(k) && source[k] != null) {
        final v = _readInt(source[k], fallback: -1);
        if (v >= 0) return v;
      }
    }
    if (instructionLevel != null) {
      final levelKeys = [
        'level${instructionLevel}ProceedCount',
        'level${instructionLevel}ParticipantsToProceed',
        'level${instructionLevel}EliminateCount',
        'proceedCountLevel$instructionLevel',
      ];
      for (final k in levelKeys) {
        if (source.containsKey(k) && source[k] != null) {
          final v = _readInt(source[k], fallback: -1);
          if (v >= 0) return v;
        }
      }
    }
    return null;
  }

  String? _normalizeType(dynamic raw) {
    if (raw == null) return null;
    final original = raw.toString().trim();
    if (original.isEmpty) return null;

    final normalized =
        original.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

    if (normalized.contains('multiplechoice') ||
        normalized == 'mcq' ||
        normalized == 'multiple' ||
        normalized == 'choice') {
      return 'Multiple Choice';
    }
    if (normalized.contains('truefalse') ||
        normalized.contains('trueorfalse') ||
        normalized == 'tf' ||
        normalized == 'boolean') {
      return 'True/False';
    }
    if ((normalized.contains('fill') && normalized.contains('blank')) ||
        normalized.contains('fillintheblank') ||
        normalized.contains('fillinblank') ||
        normalized == 'fillblank' ||
        normalized == 'fitb' ||
        normalized == 'blank') {
      return 'Fill in the Blank';
    }
    if (normalized.contains('identification') || normalized == 'ident') {
      return 'Identification';
    }
    if (normalized.contains('enumeration') || normalized == 'enum') {
      return 'Enumeration';
    }
    if (normalized.contains('mixed') || normalized == 'all') {
      return 'Mixed';
    }
    return original;
  }

  int? _questionLevel(Map<String, dynamic> question) {
    final raw =
        question['sessionLevel'] ??
        question['level'] ??
        question['levelName'] ??
        question['quizLevel'] ??
        question['levelNumber'] ??
        question['levelNo'] ??
        question['assignedLevel'];

    if (raw is num) return raw.toInt();
    final text = raw?.toString().trim() ?? '';
    final match = RegExp(r'(\d+)').firstMatch(text);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  String _extractInitialQuestionTypes(
    Map<String, dynamic> settings,
    int instructionLevel,
  ) {
    final rawAdminType =
        settings['questionType'] ??
        settings['questionTypes'] ??
        settings['question_type'] ??
        settings['question_types'] ??
        settings['type'] ??
        settings['types'] ??
        settings['allowedQuestionTypes'] ??
        widget.quizData['level${instructionLevel}QuestionType'] ??
        widget.quizData['level${instructionLevel}QuestionTypes'] ??
        widget.quizData['questionType'] ??
        widget.quizData['type'];

    if (rawAdminType is List && rawAdminType.isNotEmpty) {
      final types = <String>[];
      for (final item in rawAdminType) {
        final t = _normalizeType(item);
        if (t != null && !types.contains(t)) types.add(t);
      }
      if (types.isNotEmpty) return types.join(', ');
    } else if (rawAdminType is String && rawAdminType.trim().isNotEmpty) {
      final types = <String>[];
      for (final item in rawAdminType.split(',')) {
        final t = _normalizeType(item);
        if (t != null && !types.contains(t)) types.add(t);
      }
      if (types.isNotEmpty) return types.join(', ');
    }

    return 'Identification';
  }

  void _computeInitialValues() {
    final instructionLevel = widget.level.clamp(1, 99).toInt();
    final dynamic allLevelSettings =
        widget.quizData['levelSettings'] ?? widget.quizData['levels'];

    Map<String, dynamic> settings = <String, dynamic>{};
    if (allLevelSettings is Map) {
      final normalizedTarget = 'level$instructionLevel';
      for (final entry in allLevelSettings.entries) {
        final normalizedKey = entry.key.toString().toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]'),
          '',
        );
        if (normalizedKey == normalizedTarget && entry.value is Map) {
          settings = Map<String, dynamic>.from(entry.value as Map);
          break;
        }
      }
    }

    _proceedCount = _extractProceedCount(settings, instructionLevel) ??
        _readInt(
          settings['proceedCount'] ??
              settings['participantsToProceed'] ??
              settings['eliminateCount'] ??
              settings['eliminationCount'] ??
              settings['eliminations'] ??
              widget.quizData['level${instructionLevel}ProceedCount'] ??
              widget.quizData['level${instructionLevel}EliminateCount'],
          fallback: 0,
        );

    _points = _configuredPoints(settings) ??
        _configuredPoints(widget.quizData) ??
        _readInt(
          widget.quizData['level${instructionLevel}Points'] ??
              widget.quizData['level${instructionLevel}PointsPerQuestion'] ??
              widget.quizData['level${instructionLevel}PointValue'],
          fallback: instructionLevel.clamp(1, 3),
        );

    _questionTypes = _extractInitialQuestionTypes(settings, instructionLevel);
  }

  Future<void> _loadAsyncOverrides() async {
    final code =
        (widget.quizCode ??
                widget.quizData['quizCode'] ??
                widget.quizData['code'] ??
                widget.quizData['sessionCode'] ??
                widget.quizData['quizEventCode'] ??
                '')
            .toString()
            .trim();

    if (code.isEmpty) return;

    try {
      final instructionLevel = widget.level.clamp(1, 99).toInt();
      final sessionDoc = await FirebaseFirestore.instance
          .collection('quiz_sessions')
          .doc(code)
          .get();

      if (!sessionDoc.exists || sessionDoc.data() == null) return;
      final sessionData = sessionDoc.data()!;

      final rawAllSettings =
          sessionData['levelSettings'] ?? sessionData['levels'];
      final savedSettings = _findLevelSettings(
        rawAllSettings,
        instructionLevel,
      );

      int? newProceed;
      int? newPoints;
      String? newTypes;

      if (savedSettings != null) {
        newProceed = _extractProceedCount(savedSettings, instructionLevel);
        newPoints = _configuredPoints(savedSettings);
      }

      newProceed ??= _extractProceedCount(sessionData, instructionLevel);
      if (newPoints == null) {
        final topLevelKeys = [
          'level${instructionLevel}Points',
          'level${instructionLevel}PointsPerQuestion',
          'level${instructionLevel}PointValue',
          'pointsLevel$instructionLevel',
          'pointsPerQuestionLevel$instructionLevel',
        ];
        for (final key in topLevelKeys) {
          final value = sessionData[key];
          if (value != null) {
            final parsed = value is num
                ? value.toInt()
                : int.tryParse(value.toString().trim());
            if (parsed != null) {
              newPoints = parsed;
              break;
            }
          }
        }
      }

      // Load question types from questions collection
      final questionsSnap = await FirebaseFirestore.instance
          .collection('quiz_sessions')
          .doc(code)
          .collection('questions')
          .get();

      final questionTypesSet = <String>{};
      for (final doc in questionsSnap.docs) {
        final question = doc.data();
        final assignedLevel = _questionLevel(question);
        if (assignedLevel != instructionLevel) continue;

        var type = _normalizeType(
          question['questionType'] ??
              question['type'] ??
              question['question_type'],
        );

        if (type == null) {
          final options = question['options'];
          final answer = question['correctAnswer'] ?? question['answer'];
          if (options is List && options.isNotEmpty) {
            type = 'Multiple Choice';
          } else if (answer is List) {
            type = 'Enumeration';
          }
        }

        if (type != null) {
          questionTypesSet.add(type);
        }
      }

      const order = [
        'Multiple Choice',
        'True/False',
        'Identification',
        'Fill in the Blank',
        'Enumeration',
      ];

      if (questionTypesSet.isNotEmpty) {
        final ordered = <String>[];
        for (final t in order) {
          if (questionTypesSet.contains(t)) ordered.add(t);
        }
        for (final t in questionTypesSet) {
          if (!ordered.contains(t)) ordered.add(t);
        }
        newTypes = ordered.join(', ');
      }

      if (!mounted) return;

      setState(() {
        if (newProceed != null) _proceedCount = newProceed;
        if (newPoints != null) _points = newPoints;
        if (newTypes != null && newTypes.isNotEmpty) _questionTypes = newTypes;
      });
    } catch (e) {
      debugPrint('Error loading instructions overrides: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final instructionLevel = widget.level.clamp(1, 99).toInt();

    final dynamic allLevelSettings =
        widget.quizData['levelSettings'] ?? widget.quizData['levels'];

    Map<String, dynamic> settings = <String, dynamic>{};
    if (allLevelSettings is Map) {
      final normalizedTarget = 'level$instructionLevel';
      for (final entry in allLevelSettings.entries) {
        final normalizedKey = entry.key.toString().toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]'),
          '',
        );
        if (normalizedKey == normalizedTarget && entry.value is Map) {
          settings = Map<String, dynamic>.from(entry.value as Map);
          break;
        }
      }
    }

    final seconds = _readInt(
      settings['timerSeconds'] ??
          settings['timeSeconds'] ??
          settings['timer'] ??
          widget.quizData['timerSeconds'] ??
          widget.quizData['questionTime'],
      fallback: 30,
    );

    final proceedCount = _proceedCount ??
        _extractProceedCount(settings, instructionLevel) ??
        _readInt(
          settings['proceedCount'] ??
              settings['participantsToProceed'] ??
              settings['eliminateCount'] ??
              settings['eliminationCount'] ??
              settings['eliminations'] ??
              widget.quizData['level${instructionLevel}ProceedCount'] ??
              widget.quizData['level${instructionLevel}EliminateCount'],
          fallback: 0,
        );

    final points = _points ??
        _configuredPoints(settings) ??
        _configuredPoints(widget.quizData) ??
        _readInt(
          widget.quizData['level${instructionLevel}Points'] ??
              widget.quizData['level${instructionLevel}PointsPerQuestion'] ??
              widget.quizData['level${instructionLevel}PointValue'],
          fallback: instructionLevel.clamp(1, 3),
        );

    final difficulty =
        (settings['difficulty'] ??
                settings['levelName'] ??
                settings['name'] ??
                widget.quizData['level${instructionLevel}Difficulty'] ??
                (instructionLevel == 1
                    ? 'Easy'
                    : instructionLevel == 2
                    ? 'Medium'
                    : 'Hard'))
            .toString()
            .trim();
    final shownDifficulty = difficulty.isEmpty ? 'Easy' : difficulty;

    final String proceedText;
    if (proceedCount <= 0) {
      proceedText = "Contestants to proceed: All eligible contestants.";
    } else if (proceedCount == 1) {
      proceedText = "Contestant to proceed: 1 contestant.";
    } else {
      proceedText = "Contestants to proceed: $proceedCount contestant(s).";
    }

    final displayedTypes =
        _questionTypes ?? _extractInitialQuestionTypes(settings, instructionLevel);

    return TechCircuitBackground(
      baseColor: _background,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 26),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x12000000),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(
                      child: Icon(
                        Icons.menu_book_rounded,
                        color: _primaryGreen,
                        size: 52,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        "LEVEL $instructionLevel INSTRUCTIONS",
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _textDark,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text(
                        "Please read the rules while waiting for the Quiz Master to start.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    _instructionItem(
                      Icons.menu_book_rounded,
                      const Color(0xFF2563EB),
                      "Level $instructionLevel difficulty: $shownDifficulty.",
                    ),
                    _instructionItem(
                      Icons.timer_outlined,
                      const Color(0xFF64748B),
                      "$seconds sec per question.",
                    ),
                    _instructionItem(
                      Icons.how_to_reg_rounded,
                      const Color(0xFF10B981),
                      proceedText,
                    ),
                    _instructionItem(
                      Icons.check_box_rounded,
                      _primaryGreen,
                      "Answers cannot be changed after submission.",
                    ),
                    _instructionItem(
                      Icons.edit_note_rounded,
                      const Color(0xFF0EA5E9),
                      "Question types: $displayedTypes.",
                    ),
                    _instructionItem(
                      Icons.star_rounded,
                      const Color(0xFFF59E0B),
                      "$points point(s) per question.",
                    ),
                    _instructionItem(
                      Icons.balance_rounded,
                      const Color(0xFF64748B),
                      "Contest Answer: Challenge an incorrect mark on any question type with a valid explanation.",
                    ),
                    _instructionItem(
                      Icons.cast_for_education_rounded,
                      const Color(0xFF0F766E),
                      "Before each question, confirm that you are ready when the Ready Check appears.",
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 18,
                      ),
                      decoration: BoxDecoration(
                        color: _lightGreen,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.hourglass_top_rounded,
                            color: _primaryGreen,
                            size: 26,
                          ),
                          SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              "Please wait here. The Quiz Master will start the quiz when everyone is ready.",
                              style: TextStyle(
                                color: _darkGreen,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _instructionItem(IconData icon, Color iconColor, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 26,
            child: Icon(icon, size: 21, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: _textDark,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
