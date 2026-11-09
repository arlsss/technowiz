import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'technowiz_theme.dart';

/// Reusable Level Instructions UI for WaitingRoomScreen & QuizScreen.
/// Displays the exact standard Level 1 card layout uniformly across ALL levels
/// (Level 1, Level 2, Level 3, Level 4 and above) with TechCircuitBackground.
class QuizInstructionsScreen extends StatelessWidget {
  final Map<String, dynamic> quizData;
  final int level;
  final String? quizCode;

  const QuizInstructionsScreen({
    super.key,
    required this.quizData,
    required this.level,
    this.quizCode,
  });

  static const Color _background = Color(0xFFF2FBF5);
  static const Color _primaryGreen = Color(0xFF16A34A);
  static const Color _darkGreen = Color(0xFF14532D);
  static const Color _lightGreen = Color(0xFFECFDF3);
  static const Color _textDark = Color(0xFF1F2937);

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
      if (_normalizeLevelKey(entry.key) == target && entry.value is Map) {
        return Map<String, dynamic>.from(entry.value as Map);
      }
    }
    return null;
  }

  Future<int> _loadPointsForLevel(
    Map<String, dynamic> fallbackSettings,
    int instructionLevel,
  ) async {
    final code =
        (quizCode ??
                quizData['quizCode'] ??
                quizData['code'] ??
                quizData['sessionCode'] ??
                quizData['quizEventCode'] ??
                '')
            .toString()
            .trim();

    if (code.isNotEmpty) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('quiz_sessions')
            .doc(code)
            .get();

        final sessionData = snapshot.data() ?? <String, dynamic>{};
        final rawAllSettings =
            sessionData['levelSettings'] ?? sessionData['levels'];

        final savedSettings = _findLevelSettings(
          rawAllSettings,
          instructionLevel,
        );

        if (savedSettings != null) {
          final savedPoints = _configuredPoints(savedSettings);
          if (savedPoints != null) return savedPoints;

          for (final nestedKey in [
            'settings',
            'levelSettings',
            'configuration',
            'config',
          ]) {
            final nested = savedSettings[nestedKey];
            if (nested is Map) {
              final nestedPoints = _configuredPoints(
                Map<String, dynamic>.from(nested),
              );
              if (nestedPoints != null) return nestedPoints;
            }
          }
        }

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
            if (parsed != null) return parsed;
          }
        }
      } catch (error) {
        debugPrint(
          'Unable to load Admin points for Level $instructionLevel: $error',
        );
      }
    }

    final suppliedPoints = _configuredPoints(fallbackSettings);
    if (suppliedPoints != null) return suppliedPoints;

    final rawQuizSettings = quizData['levelSettings'] ?? quizData['levels'];
    final quizLevelSettings = _findLevelSettings(
      rawQuizSettings,
      instructionLevel,
    );
    if (quizLevelSettings != null) {
      final points = _configuredPoints(quizLevelSettings);
      if (points != null) return points;
    }

    final rawQuizPoints =
        quizData['level${instructionLevel}Points'] ??
        quizData['level${instructionLevel}PointsPerQuestion'] ??
        quizData['level${instructionLevel}PointValue'];
    if (rawQuizPoints != null) {
      final parsed = rawQuizPoints is num
          ? rawQuizPoints.toInt()
          : int.tryParse(rawQuizPoints.toString().trim());
      if (parsed != null) return parsed;
    }

    return instructionLevel.clamp(1, 3).toInt();
  }

  String? _normalizeType(dynamic raw) {
    if (raw == null) return null;
    final original = raw.toString().trim();
    if (original.isEmpty) return null;

    final normalized = original.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (normalized.contains('multiplechoice') || normalized == 'mcq') {
      return 'Multiple Choice';
    }
    if (normalized.contains('truefalse') || normalized == 'tf') {
      return 'True/False';
    }
    if (normalized.contains('identification')) return 'Identification';
    if (normalized.contains('enumeration')) return 'Enumeration';
    return null;
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

  Future<String> _loadQuestionTypes(Map<String, dynamic> settings) async {
    final code =
        (quizCode ??
                quizData['quizCode'] ??
                quizData['code'] ??
                quizData['sessionCode'] ??
                '')
            .toString()
            .trim();

    if (code.isNotEmpty) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('quiz_sessions')
            .doc(code)
            .collection('questions')
            .get();

        final types = <String>{};
        for (final doc in snapshot.docs) {
          final question = doc.data();
          final assignedLevel = _questionLevel(question);
          if (assignedLevel != level) continue;

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

          if (type != null) types.add(type);
        }

        const order = [
          'Multiple Choice',
          'True/False',
          'Identification',
          'Enumeration',
        ];
        final found = order.where(types.contains).toList();
        if (found.isNotEmpty) return found.join(', ');
      } catch (error) {
        debugPrint('Unable to load selected question types: $error');
      }
    }

    final raw =
        settings['questionTypes'] ??
        settings['questionType'] ??
        settings['question_types'] ??
        settings['types'] ??
        settings['allowedQuestionTypes'];

    final values = <String>[];
    if (raw is List) {
      for (final item in raw) {
        final type = _normalizeType(item);
        if (type != null && !values.contains(type)) values.add(type);
      }
    } else if (raw is String) {
      for (final item in raw.split(',')) {
        final type = _normalizeType(item);
        if (type != null && !values.contains(type)) values.add(type);
      }
    }

    const order = [
      'Multiple Choice',
      'True/False',
      'Identification',
      'Enumeration',
    ];
    final found = order.where(values.contains).toList();
    return found.isEmpty ? 'Multiple Choice' : found.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final instructionLevel = level.clamp(1, 99).toInt();

    final dynamic allLevelSettings =
        quizData['levelSettings'] ?? quizData['levels'];

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
          quizData['timerSeconds'] ??
          quizData['questionTime'],
      fallback: 30,
    );

    final eliminations = _readInt(
      settings['eliminateCount'] ??
          settings['eliminationCount'] ??
          settings['eliminations'] ??
          quizData['level${instructionLevel}EliminateCount'],
      fallback: 0,
    );

    final points =
        _configuredPoints(settings) ??
        _configuredPoints(quizData) ??
        _readInt(
          quizData['level${instructionLevel}Points'] ??
              quizData['level${instructionLevel}PointsPerQuestion'] ??
              quizData['level${instructionLevel}PointValue'],
          fallback: instructionLevel.clamp(1, 3),
        );

    final difficulty =
        (settings['difficulty'] ??
                settings['levelName'] ??
                settings['name'] ??
                quizData['level${instructionLevel}Difficulty'] ??
                (instructionLevel == 1
                    ? 'Easy'
                    : instructionLevel == 2
                    ? 'Medium'
                    : 'Hard'))
            .toString()
            .trim();
    final shownDifficulty = difficulty.isEmpty ? 'Easy' : difficulty;

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
                      Icons.block_rounded,
                      const Color(0xFFEF4444),
                      eliminations == 0
                          ? "Elimination: None."
                          : "Elimination: $eliminations participant(s).",
                    ),
                    _instructionItem(
                      Icons.check_box_rounded,
                      _primaryGreen,
                      "Answers cannot be changed after submission.",
                    ),
                    FutureBuilder<String>(
                      future: _loadQuestionTypes(settings),
                      builder: (context, snapshot) {
                        final types = snapshot.data;
                        return _instructionItem(
                          Icons.edit_note_rounded,
                          const Color(0xFF0EA5E9),
                          types == null
                              ? "Question types: Loading..."
                              : "Question types: $types.",
                        );
                      },
                    ),
                    FutureBuilder<int>(
                      future: _loadPointsForLevel(settings, instructionLevel),
                      builder: (context, pointsSnapshot) {
                        final displayedPoints = pointsSnapshot.data ?? points;
                        return _instructionItem(
                          Icons.star_rounded,
                          const Color(0xFFF59E0B),
                          pointsSnapshot.connectionState ==
                                  ConnectionState.waiting
                              ? "Loading points for Level $instructionLevel..."
                              : "$displayedPoints point(s) per question.",
                        );
                      },
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
