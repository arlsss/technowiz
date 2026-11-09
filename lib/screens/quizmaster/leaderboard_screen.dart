import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'quizmaster_dashboard.dart';
import 'quiz_sessions_screen.dart';
import 'manage_participants_screen.dart';
import 'profile_screen.dart';
import 'quizmaster_theme.dart';

class LeaderboardScreen extends StatefulWidget {
  final String quizCode;
  final bool initialShowHistory;
  final String initialLevel;

  const LeaderboardScreen({
    super.key,
    required this.quizCode,
    this.initialShowHistory = false,
    this.initialLevel = 'Level 1',
  });

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // ================================================================

  // COLORS

  // ================================================================

  static const Color primaryPurple = Color(0xFF1689E8);

  static const Color darkPurple = Color(0xFF0868B8);

  static const Color backgroundColor = Color(0xFFF2F8FD);

  static const Color surfaceColor = Colors.white;

  static const Color textDark = Color(0xFF17245A);

  static const Color textMuted = Color(0xFF71849E);

  static const Color borderColor = Color(0xFFDCEAF5);

  static const Color lightPurple = Color(0xFFE5F4FF);

  // ================================================================

  // STATE

  // ================================================================

  late String selectedLevel = widget.initialLevel;
  late bool showHistory = widget.initialShowHistory;
  bool _isViewingFromHistory = false;
  final Set<int> _hoveredMenuItems = <int>{};
  static const int _selectedNavigationIndex = 2;

  static const String _lastPageKey = 'technowiz_quizmaster_last_page';
  static const String _quizCodeKey = 'technowiz_quizmaster_current_quiz_code';
  static const String _leaderboardLevelKey =
      'technowiz_quizmaster_leaderboard_level';

  Future<void> _savePage(String page, {String? quizCode}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastPageKey, page);
    if (quizCode != null && quizCode.trim().isNotEmpty) {
      await prefs.setString(_quizCodeKey, quizCode.trim());
    }
  }

  Future<void> _saveDashboardPage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastPageKey, 'dashboard');
    await prefs.remove(_quizCodeKey);
  }

  @override
  void initState() {
    super.initState();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    _savePage(
      showHistory ? 'leaderboard_history' : 'leaderboard',
      quizCode: widget.quizCode,
    );
    _resolveQuizCode();
  }

  Future<void> _resolveQuizCode() async {
    if (_activeQuizCode.isNotEmpty) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('quiz_sessions')
          .orderBy('createdAt', descending: true)
          .get();
      if (!mounted) return;
      if (snapshot.docs.isNotEmpty) {
        QueryDocumentSnapshot<Map<String, dynamic>>? activeDoc;
        const activeStatuses = {
          'waiting',
          'countdown',
          'active',
          'live',
          'started',
          'ongoing',
          'paused',
          'level_pause',
          'in_progress',
          'inprogress',
        };
        for (final doc in snapshot.docs) {
          final status = (doc.data()['status'] ?? '')
              .toString()
              .trim()
              .toLowerCase()
              .replaceAll('-', '_')
              .replaceAll(' ', '_');
          if (activeStatuses.contains(status)) {
            activeDoc = doc;
            break;
          }
        }
        if (activeDoc != null) {
          final code =
              (activeDoc.data()['quizCode'] ?? activeDoc.id).toString().trim();
          if (mounted && code.isNotEmpty) {
            setState(() {
              _selectedQuizCode = code;
            });
            _savePage(
              showHistory ? 'leaderboard_history' : 'leaderboard',
              quizCode: code,
            );
          }
        }
      }
    } catch (_) {}
  }

  String? _selectedQuizCode;

  String get _activeQuizCode => (_selectedQuizCode ?? widget.quizCode).trim();



  // ================================================================

  // BUILD

  // ================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,

      backgroundColor: Colors.transparent,

      // ============================================================

      // APP BAR

      // ============================================================
      appBar: showHistory
          ? null
          : AppBar(
              backgroundColor: Colors.white,

              elevation: 0,

              scrolledUnderElevation: 0,

              surfaceTintColor: Colors.white,

              automaticallyImplyLeading: false,

              leading: const SizedBox.shrink(),
              leadingWidth: 12,
              toolbarHeight: 62,
              titleSpacing: 0,
              title: const QuizMasterBrandTitle(subtitle: 'Leaderboard'),
              bottom: const PreferredSize(
                preferredSize: Size.fromHeight(1),
                child: Divider(height: 1, thickness: 1, color: borderColor),
              ),
            ),

      // ============================================================

      // BODY

      // ============================================================
      bottomNavigationBar: _buildBottomNavigation(),
      body: QuizMasterCircuitBackground(
        child: showHistory
            ? LeaderboardHistoryScreen(
              onBack: () async {
                await _savePage('leaderboard', quizCode: _activeQuizCode);
                if (mounted) setState(() => showHistory = false);
              },

              onOpenNavigation: () {
                if (mounted) setState(() => showHistory = false);
              },

              onOverview: (quizCode) async {
                await _savePage('leaderboard', quizCode: quizCode);
                if (!mounted) return;
                setState(() {
                  _selectedQuizCode = quizCode;
                  _isViewingFromHistory = true;
                  selectedLevel = 'Level 1';
                  showHistory = false;
                });
              },
            )
          : SafeArea(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('quiz_sessions')
                    .orderBy('createdAt', descending: true)
                    .limit(30)
                    .snapshots(),
                builder: (context, sessionListSnapshot) {
                  if (sessionListSnapshot.connectionState ==
                          ConnectionState.waiting &&
                      !sessionListSnapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: primaryPurple,
                      ),
                    );
                  }

                  if (sessionListSnapshot.hasError) {
                    return _errorState(sessionListSnapshot.error);
                  }

                  final allSessions = sessionListSnapshot.data?.docs ?? [];

                  const activeStatuses = {
                    'waiting',
                    'countdown',
                    'active',
                    'live',
                    'started',
                    'ongoing',
                    'paused',
                    'level_pause',
                    'contest_review',
                    'in_progress',
                    'inprogress',
                  };

                  const finishedStatuses = {
                    'finished',
                    'finish',
                    'completed',
                    'complete',
                    'ended',
                    'end',
                    'archived',
                    'cancelled',
                    'canceled',
                  };

                  final activeSessions = allSessions.where((doc) {
                    final status = (doc.data()['status'] ?? '')
                        .toString()
                        .trim()
                        .toLowerCase()
                        .replaceAll('-', '_')
                        .replaceAll(' ', '_');
                    return activeStatuses.contains(status) &&
                        !finishedStatuses.contains(status);
                  }).toList();

                  bool isViewingHistoryQuiz = false;
                  QueryDocumentSnapshot<Map<String, dynamic>>? chosenDoc;

                  if (_isViewingFromHistory &&
                      _selectedQuizCode != null &&
                      _selectedQuizCode!.trim().isNotEmpty) {
                    final target = _selectedQuizCode!.trim();
                    for (final d in allSessions) {
                      final code =
                          (d.data()['quizCode'] ?? d.id).toString().trim();
                      if (code == target || d.id.trim() == target) {
                        chosenDoc = d;
                        isViewingHistoryQuiz = true;
                        break;
                      }
                    }
                  }

                  if (!isViewingHistoryQuiz) {
                    if (activeSessions.isEmpty) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLiveRankingHeroCard(
                              context: context,
                              quizTitle: 'No Active Quiz',
                              quizCode: '------',
                              status: 'WAITING',
                              entries: const [],
                              allSessions: const [],
                            ),
                            const SizedBox(height: 16),
                            _buildLevelSelectorTabs(const {
                              'levels': ['Level 1', 'Level 2', 'Level 3']
                            }),
                            const SizedBox(height: 16),
                            _noActiveQuizCard(),
                          ],
                        ),
                      );
                    }

                    chosenDoc = activeSessions.first;

                    if (_selectedQuizCode != null &&
                        _selectedQuizCode!.trim().isNotEmpty) {
                      final target = _selectedQuizCode!.trim();
                      for (final d in activeSessions) {
                        final code =
                            (d.data()['quizCode'] ?? d.id).toString().trim();
                        if (code == target || d.id.trim() == target) {
                          chosenDoc = d;
                          break;
                        }
                      }
                    }
                  }

                  if (chosenDoc == null) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildLiveRankingHeroCard(
                            context: context,
                            quizTitle: 'No Active Quiz',
                            quizCode: '------',
                            status: 'WAITING',
                            entries: const [],
                            allSessions: const [],
                          ),
                          const SizedBox(height: 16),
                          _buildLevelSelectorTabs(const {
                            'levels': ['Level 1', 'Level 2', 'Level 3']
                          }),
                          const SizedBox(height: 16),
                          _noActiveQuizCard(),
                        ],
                      ),
                    );
                  }

                  final effectiveCode =
                      (chosenDoc.data()['quizCode'] ?? chosenDoc.id)
                          .toString()
                          .trim();
                  final quizData = chosenDoc.data();
                  final quizTitle = (quizData['title'] ??
                          quizData['quizName'] ??
                          quizData['name'] ??
                          'Untitled Quiz')
                      .toString()
                      .trim();
                  final rawStatus = (quizData['status'] ?? 'waiting')
                      .toString()
                      .trim()
                      .toLowerCase()
                      .replaceAll('_', ' ');

                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('quiz_sessions')
                        .doc(effectiveCode)
                        .collection('join_requests')
                        .snapshots(),
                    builder: (context, requestSnap) {
                      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('quiz_sessions')
                            .doc(effectiveCode)
                            .collection('scores')
                            .snapshots(),
                        builder: (context, scoreSnap) {
                          if ((requestSnap.connectionState ==
                                      ConnectionState.waiting &&
                                  !requestSnap.hasData) ||
                              (scoreSnap.connectionState ==
                                      ConnectionState.waiting &&
                                  !scoreSnap.hasData)) {
                            return const Center(
                              child: CircularProgressIndicator(
                                color: primaryPurple,
                              ),
                            );
                          }

                          if (requestSnap.hasError || scoreSnap.hasError) {
                            return _errorState(
                              requestSnap.error ?? scoreSnap.error,
                            );
                          }

                          final requests = requestSnap.data?.docs ?? [];
                          final scores = scoreSnap.data?.docs ?? [];
                          final entries = _buildLeaderboard(
                            requests: requests,
                            scores: scores,
                            selectedLevel: selectedLevel,
                          );

                          return SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (isViewingHistoryQuiz) ...[
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF7ED),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFFFED7AA),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.history_rounded,
                                          size: 18,
                                          color: Color(0xFFEA580C),
                                        ),
                                        const SizedBox(width: 8),
                                        const Expanded(
                                          child: Text(
                                            'Viewing History Results',
                                            style: TextStyle(
                                              color: Color(0xFFC2410C),
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        InkWell(
                                          onTap: () {
                                            setState(() {
                                              _isViewingFromHistory = false;
                                              _selectedQuizCode = null;
                                            });
                                          },
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 2,
                                            ),
                                            child: Text(
                                              'Back to Live',
                                              style: TextStyle(
                                                color: primaryPurple,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                _buildLiveRankingHeroCard(
                                  context: context,
                                  quizTitle: quizTitle,
                                  quizCode: effectiveCode,
                                  status: rawStatus,
                                  entries: entries,
                                  allSessions: isViewingHistoryQuiz
                                      ? [chosenDoc!]
                                      : activeSessions,
                                ),
                                const SizedBox(height: 16),
                                _levelSelector(quizData: quizData),
                                const SizedBox(height: 16),
                                if (entries.isEmpty)
                                  _waitingLiveStandingsCard()
                                else ...[
                                  _sectionHeader(
                                    'Top Performers',
                                    'Leading participants in this competition.',
                                    Icons.emoji_events_rounded,
                                  ),
                                  const SizedBox(height: 10),
                                  _podium(entries),
                                  const SizedBox(height: 20),
                                  _sectionHeader(
                                    'Contestant Standings',
                                    'Scores and ranking of all contestants.',
                                    Icons.format_list_numbered_rounded,
                                  ),
                                  const SizedBox(height: 10),
                                  _rankingList(entries),
                                ],
                              ],
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
      ),
    );
  }

  // Bottom navigation matches the Quiz Master Dashboard exactly.
  // Hover updates are isolated to this navigation bar so they do not rebuild
  // the full leaderboard page or its Firestore streams.
  Widget _buildBottomNavigation() {
    final items = <({IconData icon, String title, int index})>[
      (icon: Icons.dashboard_outlined, title: 'Dashboard', index: 0),
      (icon: Icons.assignment_outlined, title: 'Quizzes', index: 1),
      (icon: Icons.bar_chart_outlined, title: 'Leaderboard', index: 2),
      (icon: Icons.people_outline, title: 'Participants', index: 3),
      (icon: Icons.person_outline, title: 'Profile', index: 4),
    ];

    return SafeArea(
      top: false,
      child: Material(
        color: Colors.white,
        elevation: 12,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: borderColor)),
          ),
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 5),
          child: StatefulBuilder(
            builder: (context, setNavState) {
              return Row(
                children: items.map((item) {
                  final selected = _selectedNavigationIndex == item.index;
                  final hovered = _hoveredMenuItems.contains(item.index);
                  return Expanded(
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      onEnter: (_) {
                        setNavState(() => _hoveredMenuItems.add(item.index));
                      },
                      onExit: (_) {
                        setNavState(() => _hoveredMenuItems.remove(item.index));
                      },
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _handleBottomNavigationTap(item.index),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 3,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: selected || hovered
                                ? lightPurple
                                : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                item.icon,
                                size: 20,
                                color: selected || hovered
                                    ? primaryPurple
                                    : textMuted,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: selected || hovered
                                      ? primaryPurple
                                      : textMuted,
                                  fontSize: 10,
                                  fontWeight: selected || hovered
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _handleBottomNavigationTap(int index) async {
    if (index == 4) {
      showQuizMasterProfileSideSheet(context);
      return;
    }

    if (index == 2) return;

    if (index == 0) {
      await _saveDashboardPage();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => const QuizMasterDashboard(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, animation, secondaryAnimation, child) =>
              child,
        ),
      );
    } else if (index == 1) {
      await _savePage('quiz_sessions');
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => const QuizSessionsScreen(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, animation, secondaryAnimation, child) =>
              child,
        ),
      );
    } else if (index == 3) {
      await _savePage('participants', quizCode: _activeQuizCode);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) =>
              ManageParticipantsScreen(quizCode: _activeQuizCode),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, animation, secondaryAnimation, child) =>
              child,
        ),
      );
    }
  }

  // ================================================================
  // LIVE RANKING HERO CARD
  // ================================================================

  Widget _buildLiveRankingHeroCard({
    required BuildContext context,
    required String quizTitle,
    required String quizCode,
    required String status,
    required List<_LeaderboardEntry> entries,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> allSessions,
  }) {
    final isLive = status == 'active' ||
        status == 'live' ||
        status == 'started' ||
        status == 'waiting';

    final topLeaderName =
        entries.isNotEmpty ? entries.first.name : 'Waiting for contestants...';
    final topScore =
        entries.isNotEmpty ? '${entries.first.score} pts' : '0 pts';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F4C81), Color(0xFF1689E8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F4C81).withValues(alpha: 0.28),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: LIVE RANKING Pill + Status + History Button
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sensors_rounded, color: Colors.white, size: 13),
                      SizedBox(width: 5),
                      Text(
                        'LIVE RANKING',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.7,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: isLive
                              ? const Color(0xFF4ADE80)
                              : const Color(0xFFFBBF24),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        status.isEmpty ? 'WAITING' : status.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // History button inside hero card to select from history
                InkWell(
                  onTap: () {
                    setState(() => showHistory = true);
                    _savePage('leaderboard_history');
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.history_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                        SizedBox(width: 5),
                        Text(
                          'History',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Quiz Title
            Text(
              quizTitle.isEmpty ? 'Untitled Quiz' : quizTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 4),

            // Quiz Code
            Text(
              'Code: $quizCode',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.88),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),

            // Switch Quiz Dropdown if multiple quizzes
            if (allSessions.length > 1) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.20),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    dropdownColor: const Color(0xFF0F4C81),
                    icon: const Icon(
                      Icons.arrow_drop_down_rounded,
                      color: Colors.white,
                    ),
                    value: allSessions.any((d) =>
                            (d.data()['quizCode'] ?? d.id).toString().trim() ==
                            quizCode)
                        ? quizCode
                        : (allSessions.first.data()['quizCode'] ??
                                allSessions.first.id)
                            .toString()
                            .trim(),
                    items: allSessions.map((doc) {
                      final code =
                          (doc.data()['quizCode'] ?? doc.id).toString().trim();
                      final title = (doc.data()['title'] ??
                              doc.data()['quizName'] ??
                              'Quiz')
                          .toString()
                          .trim();
                      return DropdownMenuItem<String>(
                        value: code,
                        child: Text(
                          '$title ($code)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (newCode) {
                      if (newCode != null && newCode.isNotEmpty) {
                        setState(() {
                          _selectedQuizCode = newCode;
                        });
                        _savePage('leaderboard', quizCode: newCode);
                      }
                    },
                  ),
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Live Metrics Summary
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'RANK 1 LEADER',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          topLeaderName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TOP SCORE',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          topScore,
                          style: const TextStyle(
                            color: Color(0xFF4ADE80),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'TOTAL',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${entries.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ================================================================
  // WAITING & EMPTY STATES
  // ================================================================

  Widget _waitingLiveStandingsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0617245A),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              color: Color(0xFFEFF6FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.hourglass_empty_rounded,
              size: 30,
              color: primaryPurple,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Waiting for Quiz Submissions',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: textDark,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Scores and rankings will update here live in real-time as contestants answer questions.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: textMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _noActiveQuizCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Color(0xFFEAF5FD),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.leaderboard_outlined,
              size: 32,
              color: primaryPurple,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'No Active Quiz',
            style: TextStyle(
              color: textDark,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Live rankings and standings will appear here once an active quiz begins.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textMuted,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // LEVEL SELECTOR
  // ================================================================

  Widget _levelSelector({Map<String, dynamic>? quizData}) {
    if (quizData != null) {
      return _buildLevelSelectorTabs(quizData);
    }
    if (_activeQuizCode.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('quiz_sessions')
          .doc(_activeQuizCode)
          .snapshots(),
      builder: (context, sessionSnapshot) {
        final data = sessionSnapshot.data?.data() as Map<String, dynamic>?;
        return _buildLevelSelectorTabs(data);
      },
    );
  }

  Widget _buildLevelSelectorTabs(Map<String, dynamic>? data) {
    final int currentLevel = _toInt(data?['currentLevel'] ?? 1);
    final String status = data?['status']?.toString().toLowerCase() ?? '';
    final int completedLevel = (status == 'level_pause' || status == 'finished')
        ? currentLevel
        : (currentLevel > 1 ? currentLevel - 1 : 0);

    final configuredLevels = <String>[];
    final rawLevels = data?['levels'];
    if (rawLevels is List) {
      for (final value in rawLevels) {
        final rawLabel = value.toString().trim();
        if (rawLabel.isEmpty || rawLabel.toLowerCase() == 'overall') continue;
        final numericLevel = int.tryParse(
          rawLabel.replaceFirst(RegExp(r'^level\s*', caseSensitive: false), ''),
        );
        final normalizedLabel = numericLevel != null ? 'Level $numericLevel' : rawLabel;
        if (!configuredLevels.contains(normalizedLabel)) {
          configuredLevels.add(normalizedLabel);
        }
      }
    }

    if (configuredLevels.isEmpty) {
      final int highestAvailableLevel =
          completedLevel > currentLevel ? completedLevel : currentLevel;
      final int levelCount = highestAvailableLevel > 1 ? highestAvailableLevel : 1;
      for (var number = 1; number <= levelCount; number++) {
        configuredLevels.add('Level $number');
      }
    }

    if (!configuredLevels.contains('Level 1')) {
      configuredLevels.insert(0, 'Level 1');
    }

    final levels = <String>[...configuredLevels, 'Overall'];
    if (!levels.contains(selectedLevel)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !levels.contains(selectedLevel)) {
          setState(() {
            selectedLevel = configuredLevels.contains('Level 1')
                ? 'Level 1'
                : configuredLevels.first;
          });
        }
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: borderColor),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0617245A),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              for (final level in levels)
                Flexible(fit: FlexFit.tight, child: _levelButton(level)),
            ],
          ),
        );
      },
    );
  }

  Widget _levelButton(String level) {
    final bool selected = selectedLevel == level;

    return Material(
      color: Colors.transparent,

      borderRadius: BorderRadius.circular(11),

      child: InkWell(
        borderRadius: BorderRadius.circular(11),

        onTap: () {
          if (selectedLevel != level) {
            setState(() => selectedLevel = level);
            SharedPreferences.getInstance().then((prefs) {
              prefs.setString(_leaderboardLevelKey, level);
            });
          }
        },

        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),

          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),

          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    begin: Alignment.topLeft,

                    end: Alignment.bottomRight,

                    colors: [primaryPurple, darkPurple],
                  )
                : null,

            color: selected ? null : Colors.transparent,

            borderRadius: BorderRadius.circular(11),
          ),

          child: FittedBox(
            fit: BoxFit.scaleDown,

            child: Text(
              level,

              maxLines: 1,

              softWrap: false,

              textAlign: TextAlign.center,

              style: TextStyle(
                color: selected ? Colors.white : textMuted,

                fontSize: 10,

                fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // SECTION HEADER

  // ================================================================

  Widget _sectionHeader(String title, String subtitle, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,

      children: [
        Container(
          width: 4,

          height: 21,

          decoration: BoxDecoration(
            color: primaryPurple,

            borderRadius: BorderRadius.circular(8),
          ),
        ),

        const SizedBox(width: 9),

        Container(
          width: 32,

          height: 32,

          decoration: BoxDecoration(
            color: lightPurple,

            borderRadius: BorderRadius.circular(9),
          ),

          child: Icon(icon, color: primaryPurple, size: 17),
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

                  fontSize: 15,

                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 2),

              Text(
                subtitle,

                style: const TextStyle(
                  color: textMuted,

                  fontSize: 9,

                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ================================================================

  // PODIUM

  // ================================================================

  Widget _podium(List<_LeaderboardEntry> entries) {
    final first = entries.isNotEmpty ? entries[0] : null;

    final second = entries.length > 1 ? entries[1] : null;

    final third = entries.length > 2 ? entries[2] : null;

    return Container(
      width: double.infinity,

      padding: const EdgeInsets.fromLTRB(12, 20, 12, 18),

      decoration: BoxDecoration(
        color: surfaceColor,

        borderRadius: BorderRadius.circular(17),

        border: Border.all(color: borderColor),

        boxShadow: const [
          BoxShadow(
            color: Color(0x0717245A),

            blurRadius: 10,

            offset: Offset(0, 3),
          ),
        ],
      ),

      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 4,

                height: 18,

                decoration: BoxDecoration(
                  color: primaryPurple,

                  borderRadius: BorderRadius.circular(8),
                ),
              ),

              const SizedBox(width: 8),

              const Expanded(
                child: Text(
                  'Top Performers',

                  style: TextStyle(
                    color: textDark,

                    fontSize: 14,

                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),

                decoration: BoxDecoration(
                  color: lightPurple,

                  borderRadius: BorderRadius.circular(18),
                ),

                child: const Text(
                  'TOP 3',

                  style: TextStyle(
                    color: primaryPurple,

                    fontSize: 7,

                    fontWeight: FontWeight.w900,

                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          Row(
            crossAxisAlignment: CrossAxisAlignment.end,

            mainAxisAlignment: MainAxisAlignment.center,

            children: [
              Expanded(
                child: _podiumPerson(entry: second, rank: 2, height: 105),
              ),

              Expanded(
                child: _podiumPerson(entry: first, rank: 1, height: 135),
              ),

              Expanded(child: _podiumPerson(entry: third, rank: 3, height: 90)),
            ],
          ),
        ],
      ),
    );
  }

  // ================================================================

  // PODIUM PERSON

  // ================================================================

  Widget _podiumPerson({
    required _LeaderboardEntry? entry,

    required int rank,

    required double height,
  }) {
    final bool isFirst = rank == 1;

    return Column(
      children: [
        // ==========================================================

        // RANK CIRCLE

        // ==========================================================
        Container(
          width: isFirst ? 62 : 54,
          height: isFirst ? 62 : 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: rank == 1
                ? const LinearGradient(
                    colors: [Color(0xFFFFD76A), Color(0xFFF59E0B)],
                  )
                : rank == 2
                ? const LinearGradient(
                    colors: [Color(0xFFF8FAFC), Color(0xFFE2E8F0)],
                  )
                : const LinearGradient(
                    colors: [Color(0xFFFFF7ED), Color(0xFFFFEDD5)],
                  ),
            border: Border.all(
              color: rank == 1
                  ? const Color(0xFFD97706)
                  : rank == 2
                  ? const Color(0xFF94A3B8)
                  : const Color(0xFFD97706),
              width: 2,
            ),
          ),
          child: Center(
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: isFirst ? 25 : 20,
                fontWeight: FontWeight.w900,
                color: rank == 1
                    ? const Color(0xFF78350F)
                    : rank == 2
                    ? const Color(0xFF334155)
                    : const Color(0xFF7C2D12),
              ),
            ),
          ),
        ),

        const SizedBox(height: 8),

        // ==========================================================
        // NAME
        // ==========================================================
        Text(
          entry?.name ?? '---',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: textDark,
          ),
        ),

        const SizedBox(height: 3),

        // ==========================================================
        // SCORE
        // ==========================================================
        Text(
          '${entry?.score ?? 0} pts',
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: primaryPurple,
          ),
        ),

        const SizedBox(height: 8),

        // ==========================================================
        // PODIUM
        // ==========================================================
        Container(
          height: height,
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            gradient: rank == 1
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
                  )
                : rank == 2
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFF1F5F9), Color(0xFFE2E8F0)],
                  )
                : const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFFF7ED), Color(0xFFFED7AA)],
                  ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Center(
            child: Container(
              width: isFirst ? 50 : 42,
              height: isFirst ? 50 : 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(
                  color: rank == 1
                      ? const Color(0xFFFCD34D)
                      : rank == 2
                          ? const Color(0xFFCBD5E1)
                          : const Color(0xFFFDBA74),
                  width: 2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x18000000),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  rank == 1
                      ? 'assets/trophies/gold_trophy_3d.jpg'
                      : rank == 2
                          ? 'assets/trophies/silver_trophy_3d.jpg'
                          : 'assets/trophies/bronze_trophy_3d.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Icon(
                    Icons.emoji_events_rounded,
                    size: isFirst ? 32 : 26,
                    color: rank == 1
                        ? const Color(0xFFD97706)
                        : rank == 2
                            ? const Color(0xFF64748B)
                            : const Color(0xFFB45309),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ================================================================
  // RANKING LIST
  // ================================================================

  Widget _rankingList(List<_LeaderboardEntry> entries) {
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: borderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0617245A),
            blurRadius: 9,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          for (int i = 0; i < entries.length; i++)
            _rankingItem(entries[i], i + 1),
        ],
      ),
    );
  }

  // ================================================================
  // RANKING ITEM
  // ================================================================

  Widget _rankingItem(_LeaderboardEntry entry, int rank) {
    final bool isFirst = rank == 1;
    final bool isSecond = rank == 2;
    final bool isThird = rank == 3;
    final bool isTop3 = rank <= 3;
    final bool isTop10 = rank >= 4 && rank <= 10;

    Color badgeBg;
    Color badgeBorder;
    Color badgeTextColor;

    if (isFirst) {
      badgeBg = const Color(0xFFFEF3C7);
      badgeBorder = const Color(0xFFF59E0B);
      badgeTextColor = const Color(0xFFB45309);
    } else if (isSecond) {
      badgeBg = const Color(0xFFF1F5F9);
      badgeBorder = const Color(0xFF94A3B8);
      badgeTextColor = const Color(0xFF475569);
    } else if (isThird) {
      badgeBg = const Color(0xFFFFEDD5);
      badgeBorder = const Color(0xFFFB923C);
      badgeTextColor = const Color(0xFFC2410C);
    } else if (isTop10) {
      badgeBg = const Color(0xFFE0F2FE);
      badgeBorder = const Color(0xFF7DD3FC);
      badgeTextColor = const Color(0xFF0369A1);
    } else {
      badgeBg = lightPurple;
      badgeBorder = borderColor;
      badgeTextColor = primaryPurple;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isFirst
            ? const Color(0xFFFFFDF5)
            : (isTop3 ? const Color(0xFFFAFCFF) : backgroundColor),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: isFirst
              ? const Color(0xFFFDE68A)
              : (isTop3 ? const Color(0xFFBAE6FD) : borderColor),
          width: isTop3 ? 1.4 : 1,
        ),
      ),
      child: Row(
        children: [
          // Rank Badge
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: badgeBorder, width: 1.2),
            ),
            child: Center(
              child: isTop3
                  ? Icon(
                      Icons.emoji_events_rounded,
                      size: 17,
                      color: badgeTextColor,
                    )
                  : Text(
                      '$rank',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        color: badgeTextColor,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),

          // Name & Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: textDark,
                        ),
                      ),
                    ),
                    if (entry.eliminated) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Text(
                          'ELIMINATED',
                          style: TextStyle(
                            color: Color(0xFFDC2626),
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ] else if (entry.status == 'proceeding' || entry.status == 'approved') ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Text(
                          'ACTIVE',
                          style: TextStyle(
                            color: Color(0xFF16A34A),
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (entry.teamName.isNotEmpty && entry.teamName != entry.name) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Team: ${entry.teamName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ] else if (entry.school.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.school,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (entry.members.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    'Members: ${entry.members.join(', ')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9, color: textMuted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Score Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isFirst
                  ? const Color(0xFFFEF3C7)
                  : (isTop3 ? const Color(0xFFE0F2FE) : lightPurple),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isFirst
                    ? const Color(0xFFF59E0B)
                    : (isTop3 ? const Color(0xFF38BDF8) : const Color(0xFFBAE6FD)),
                width: 1,
              ),
            ),
            child: Text(
              '${entry.score} pts',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: isFirst ? const Color(0xFFB45309) : primaryPurple,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // ERROR STATE
  // ================================================================

  Widget _errorState(Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),

        child: Container(
          width: double.infinity,

          padding: const EdgeInsets.all(28),

          decoration: BoxDecoration(
            color: Colors.white,

            borderRadius: BorderRadius.circular(17),

            border: Border.all(color: borderColor),
          ),

          child: Column(
            mainAxisSize: MainAxisSize.min,

            children: [
              Container(
                width: 70,

                height: 70,

                decoration: BoxDecoration(
                  color: const Color(0xFFFFEEEE),

                  borderRadius: BorderRadius.circular(18),
                ),

                child: const Icon(
                  Icons.error_outline_rounded,

                  color: Colors.redAccent,

                  size: 36,
                ),
              ),

              const SizedBox(height: 15),

              const Text(
                'Unable to Load Leaderboard',

                textAlign: TextAlign.center,

                style: TextStyle(
                  color: textDark,

                  fontSize: 17,

                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 7),

              Text(
                '$error',

                textAlign: TextAlign.center,

                style: const TextStyle(
                  color: textMuted,

                  fontSize: 11,

                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================================================================
  // BUILD LEADERBOARD DATA
  // ================================================================

  List<_LeaderboardEntry> _buildLeaderboard({
    required List<QueryDocumentSnapshot> requests,
    required List<QueryDocumentSnapshot> scores,
    required String selectedLevel,
  }) {
    final Map<String, _LeaderboardEntry> grouped = {};

    // 1. Add all contestants from join_requests so even 0 points appear
    for (final doc in requests) {
      final data = doc.data() as Map<String, dynamic>;
      final status = (data['status'] ?? '').toString().trim().toLowerCase();
      if (status == 'rejected' || status == 'denied') continue;

      final uid = data['uid']?.toString() ?? doc.id;
      final teamName = data['teamName']?.toString().trim() ?? '';
      final name = data['displayName']?.toString().trim().isNotEmpty == true
          ? data['displayName'].toString().trim()
          : (data['name']?.toString().trim().isNotEmpty == true
              ? data['name'].toString().trim()
              : 'Contestant');
      final school = (data['school'] ?? data['schoolName'] ?? '').toString().trim();
      final members = teamName.isNotEmpty
          ? _teamMembers(data['teamMembers'] ?? data['members'])
          : <String>[];
      final key = teamName.isNotEmpty ? 'team:$teamName' : 'user:$uid';
      final display = teamName.isNotEmpty ? teamName : name;

      final current = grouped[key];
      if (current == null) {
        grouped[key] = _LeaderboardEntry(
          id: uid,
          name: display,
          teamName: teamName,
          members: members,
          school: school,
          score: 0,
          eliminated: status == 'eliminated',
          status: status,
        );
      } else {
        grouped[key] = _LeaderboardEntry(
          id: current.id,
          name: current.name,
          teamName: current.teamName,
          members: {...current.members, ...members}.toList(),
          school: current.school.isNotEmpty ? current.school : school,
          score: current.score,
          eliminated: current.eliminated || status == 'eliminated',
          status: current.status.isNotEmpty ? current.status : status,
        );
      }
    }

    // 2. Add real-time scores from scores collection
    for (final doc in scores) {
      final data = doc.data() as Map<String, dynamic>;
      final uid = data['uid']?.toString() ?? doc.id;
      final teamName = data['teamName']?.toString().trim() ?? '';
      final name = data['displayName']?.toString().trim().isNotEmpty == true
          ? data['displayName'].toString().trim()
          : (data['name']?.toString().trim().isNotEmpty == true
              ? data['name'].toString().trim()
              : 'Contestant');
      final school = (data['school'] ?? data['schoolName'] ?? '').toString().trim();
      final members = teamName.isNotEmpty
          ? _teamMembers(data['teamMembers'] ?? data['members'])
          : <String>[];
      final isEliminated = data['eliminated'] == true ||
          data['isEliminated'] == true ||
          (data['status'] ?? '').toString().toLowerCase() == 'eliminated';
      final status = (data['status'] ?? '').toString();
      final lastSubTime = data['lastSubmissionTime'] is Timestamp
          ? data['lastSubmissionTime'] as Timestamp
          : (data['updatedAt'] is Timestamp ? data['updatedAt'] as Timestamp : null);

      // Score based on selected level
      int contestantScore = 0;
      if (selectedLevel == 'Overall') {
        contestantScore = _toInt(data['score'] ?? data['totalScore'] ?? data['points'] ?? 0);
      } else {
        final levelMatch = RegExp(r'\d+').firstMatch(selectedLevel);
        final levelNum = levelMatch != null ? int.tryParse(levelMatch.group(0)!) ?? 1 : 1;
        final levelKey = 'level${levelNum}Score';
        final altKey = 'level_$levelNum';
        if (data.containsKey(levelKey)) {
          contestantScore = _toInt(data[levelKey]);
        } else if (data.containsKey(altKey)) {
          contestantScore = _toInt(data[altKey]);
        } else {
          final currentLevel = _toInt(data['currentLevel'] ?? data['level'] ?? 1);
          if (currentLevel == levelNum) {
            contestantScore = _toInt(data['score'] ?? data['points'] ?? 0);
          } else if (levelNum == 1) {
            contestantScore = _toInt(data['score'] ?? 0);
          }
        }
      }

      final key = teamName.isNotEmpty ? 'team:$teamName' : 'user:$uid';
      final display = teamName.isNotEmpty ? teamName : name;

      final current = grouped[key];
      if (current == null) {
        grouped[key] = _LeaderboardEntry(
          id: uid,
          name: display,
          teamName: teamName,
          members: members,
          school: school,
          score: contestantScore,
          eliminated: isEliminated,
          status: status,
          lastSubmissionTime: lastSubTime,
        );
      } else {
        grouped[key] = _LeaderboardEntry(
          id: current.id,
          name: current.name,
          teamName: current.teamName.isNotEmpty ? current.teamName : teamName,
          members: {...current.members, ...members}.toList(),
          school: current.school.isNotEmpty ? current.school : school,
          score: teamName.isNotEmpty ? current.score + contestantScore : contestantScore,
          eliminated: current.eliminated || isEliminated,
          status: status.isNotEmpty ? status : current.status,
          lastSubmissionTime: lastSubTime ?? current.lastSubmissionTime,
        );
      }
    }

    final result = grouped.values.toList();
    result.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;
      if (a.lastSubmissionTime != null && b.lastSubmissionTime != null) {
        final timeCompare = a.lastSubmissionTime!.compareTo(b.lastSubmissionTime!);
        if (timeCompare != 0) return timeCompare;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return result;
  }

  List<String> _teamMembers(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }
    return <String>[];
  }

  // ================================================================
  // CONVERT TO INT
  // ================================================================

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is double) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

// ================================================================
// LEADERBOARD MODEL
// ================================================================

class _LeaderboardEntry {
  final String id;
  final String name;
  final String teamName;
  final List<String> members;
  final String school;
  final int score;
  final bool eliminated;
  final String status;
  final Timestamp? lastSubmissionTime;

  const _LeaderboardEntry({
    this.id = '',
    required this.name,
    this.teamName = '',
    this.members = const [],
    this.school = '',
    required this.score,
    this.eliminated = false,
    this.status = '',
    this.lastSubmissionTime,
  });
}

// ================================================================

// LEADERBOARD HISTORY

// ================================================================

class LeaderboardHistoryScreen extends StatefulWidget {
  final VoidCallback? onBack;

  final VoidCallback? onOpenNavigation;

  final ValueChanged<String>? onOverview;

  const LeaderboardHistoryScreen({
    super.key,

    this.onBack,

    this.onOpenNavigation,

    this.onOverview,
  });

  @override
  State<LeaderboardHistoryScreen> createState() =>
      _LeaderboardHistoryScreenState();
}

class _LeaderboardHistoryScreenState extends State<LeaderboardHistoryScreen> {
  bool _selectionMode = false;

  final Set<String> _selectedQuizIds = <String>{};

  List<QueryDocumentSnapshot> _currentQuizzes = <QueryDocumentSnapshot>[];

  void _toggleSelected(String quizId) {
    setState(() {
      if (!_selectedQuizIds.add(quizId)) {
        _selectedQuizIds.remove(quizId);
      }
    });
  }

  Future<void> _deleteSelectedQuizzes() async {
    if (_selectedQuizIds.isEmpty) {
      if (!mounted) return;
      showQuizMasterTopNotification(
        context,
        'Select at least one quiz first.',
        isWarning: true,
      );

      return;
    }

    final count = _selectedQuizIds.length;

    final confirmed = await showDialog<bool>(
      context: context,

      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete selected quizzes?'),

        content: Text(
          'Are you sure you want to delete $count selected quiz session(s)?',
        ),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),

            child: const Text('Cancel'),
          ),

          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),

            onPressed: () => Navigator.pop(dialogContext, true),

            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final batch = FirebaseFirestore.instance.batch();

      for (final quiz in _currentQuizzes) {
        if (_selectedQuizIds.contains(quiz.id)) {
          batch.delete(
            FirebaseFirestore.instance.collection('quiz_sessions').doc(quiz.id),
          );
        }
      }

      await batch.commit();

      if (!mounted) return;

      setState(() {
        _selectedQuizIds.clear();

        _selectionMode = false;
      });

      showQuizMasterTopNotification(
        context,
        '$count quiz session(s) deleted.',
        isSuccess: true,
      );
    } catch (error) {
      if (!mounted) return;

      showQuizMasterTopNotification(
        context,
        'Unable to delete selected quizzes: $error',
        isError: true,
      );
    }
  }

  static const Color primaryPurple = Color(0xFF1689E8);

  static const Color textDark = Color(0xFF17245A);

  static const Color textMuted = Color(0xFF71849E);

  static const Color borderColor = Color(0xFFDCEAF5);

  String _friendlyQuizStatus(dynamic rawStatus) {
    final status = (rawStatus?.toString() ?? 'unknown')
        .toLowerCase()
        .replaceAll(' ', '_');

    if (status.contains('pause')) return 'PAUSED';

    if (status == 'finished' || status == 'completed' || status == 'complete') {
      return 'FINISHED';
    }

    if (status == 'ongoing' ||
        status == 'in_progress' ||
        status == 'started' ||
        status == 'active' ||
        status == 'running') {
      return 'ONGOING';
    }

    if (status == 'waiting' || status == 'pending' || status == 'ready') {
      return 'WAITING';
    }

    return status.replaceAll('_', ' ').toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,

      appBar: AppBar(
        backgroundColor: Colors.white,

        foregroundColor: textDark,

        elevation: 0,

        automaticallyImplyLeading: false,

        leading: IconButton(
          tooltip: 'Back',

          icon: const Icon(Icons.arrow_back_rounded, color: textDark),

          onPressed: () {
            if (_selectionMode) {
              setState(() {
                _selectionMode = false;
                _selectedQuizIds.clear();
              });
              return;
            }
            if (widget.onBack != null) {
              widget.onBack!();
            } else if (widget.onOpenNavigation != null) {
              widget.onOpenNavigation!();
            } else {
              Navigator.maybePop(context);
            }
          },
        ),

        titleSpacing: 0,

        title: Text(
          _selectionMode
              ? '${_selectedQuizIds.length} selected'
              : 'Leaderboard History',

          style: const TextStyle(
            color: textDark,

            fontSize: 18,

            fontWeight: FontWeight.w800,
          ),
        ),

        actions: [
          if (!_selectionMode)
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _selectionMode = true;

                  _selectedQuizIds.clear();
                });
              },

              icon: const Icon(Icons.delete_outline_rounded, size: 18),

              label: const Text('Delete'),

              style: TextButton.styleFrom(
                foregroundColor: Colors.redAccent,

                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            )
          else ...[
            TextButton(
              onPressed: () {
                setState(() {
                  _selectionMode = false;

                  _selectedQuizIds.clear();
                });
              },

              child: const Text('Cancel'),
            ),

            TextButton.icon(
              onPressed: _selectedQuizIds.isEmpty
                  ? null
                  : () => _deleteSelectedQuizzes(),

              icon: const Icon(Icons.delete_rounded, size: 18),

              label: Text('Delete (${_selectedQuizIds.length})'),

              style: TextButton.styleFrom(
                foregroundColor: Colors.redAccent,

                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
          ],
        ],

        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),

          child: Divider(height: 1, thickness: 1, color: borderColor),
        ),
      ),

      body: QuizMasterCircuitBackground(
        child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('quiz_sessions')
            .orderBy('createdAt', descending: true)
            .snapshots(),

        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: primaryPurple),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Unable to load leaderboard history.\n${snapshot.error}',

                textAlign: TextAlign.center,

                style: const TextStyle(color: textMuted, fontSize: 12),
              ),
            );
          }

          final quizzes = (snapshot.data?.docs ?? []).toList();

          _currentQuizzes = quizzes;

          if (quizzes.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(25),

                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,

                  children: [
                    Icon(Icons.history_rounded, size: 58, color: primaryPurple),

                    SizedBox(height: 14),

                    Text(
                      'No Leaderboard History',

                      style: TextStyle(
                        color: textDark,

                        fontSize: 18,

                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    SizedBox(height: 6),

                    Text(
                      'Ongoing, paused, and finished quizzes will appear here.',

                      textAlign: TextAlign.center,

                      style: TextStyle(color: textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),

            itemCount: quizzes.length,

            itemBuilder: (context, index) {
              final quiz = quizzes[index];

              final data = quiz.data() as Map<String, dynamic>;

              final title = data['title']?.toString().trim().isNotEmpty == true
                  ? data['title'].toString().trim()
                  : 'Untitled Quiz';

              final quizCode =
                  data['quizCode']?.toString().trim().isNotEmpty == true
                  ? data['quizCode'].toString().trim()
                  : quiz.id;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),

                decoration: BoxDecoration(
                  color: Colors.white,

                  borderRadius: BorderRadius.circular(16),

                  border: Border.all(color: borderColor),
                ),

                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 15,

                    vertical: 6,
                  ),

                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE5F4FF),

                    child: Icon(
                      Icons.emoji_events_rounded,

                      color: primaryPurple,
                    ),
                  ),

                  title: Text(
                    title,

                    style: const TextStyle(
                      color: textDark,

                      fontSize: 13,

                      fontWeight: FontWeight.w800,
                    ),
                  ),

                  subtitle: Text(
                    'Quiz Code: $quizCode  •  ${_friendlyQuizStatus(data['status'])}',

                    maxLines: 2,

                    overflow: TextOverflow.ellipsis,

                    style: const TextStyle(color: textMuted, fontSize: 10),
                  ),

                  trailing: _selectionMode
                      ? Checkbox(
                          value: _selectedQuizIds.contains(quiz.id),

                          activeColor: primaryPurple,

                          onChanged: (_) => _toggleSelected(quiz.id),
                        )
                      : const Icon(
                          Icons.chevron_right_rounded,

                          color: primaryPurple,
                        ),

                  onTap: () {
                    if (_selectionMode) {
                      _toggleSelected(quiz.id);
                    } else {
                      widget.onOverview?.call(quizCode);
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    ),
  );
}
}
