import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'admin_dashboard.dart';
import 'manage_users_screen.dart';
import 'add_question_screen.dart';
import 'question_list_screen.dart';
import 'manage_quiz_sessions_screen.dart';
import 'admin_report_screen.dart';
import 'admin_sidebar.dart';
import 'admin_theme.dart';
import '../../navigation_persistence.dart';

// ============================================================================
// ADMIN LEADERBOARD SCREEN - MATCHES QUIZMASTER REAL-TIME DASHBOARD & HERO CARD
// ============================================================================

class AdminLeaderboardScreen extends StatefulWidget {
  final bool initialShowHistory;
  final String? initialQuizCode;
  final String? initialLevel;

  const AdminLeaderboardScreen({
    super.key,
    this.initialShowHistory = false,
    this.initialQuizCode,
    this.initialLevel,
  });

  @override
  State<AdminLeaderboardScreen> createState() => _AdminLeaderboardScreenState();
}

class _AdminLeaderboardScreenState extends State<AdminLeaderboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  bool showHistory = false;
  String? _selectedQuizCode;
  bool _isViewingFromHistory = false;
  String selectedLevel = 'Overall';

  final Map<String, Map<int, int>> _levelScoresCache = {};
  final Map<String, StreamSubscription> _responseSubs = {};
  final Set<String> _syncingUids = {};
  final Set<String> _checkedUids = {};
  String? _lastSyncedQuizCode;

  @override
  void dispose() {
    for (final sub in _responseSubs.values) {
      sub.cancel();
    }
    _responseSubs.clear();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    showHistory = widget.initialShowHistory;
    _selectedQuizCode = widget.initialQuizCode;
    selectedLevel = widget.initialLevel ?? 'Overall';
    _restorePreferencesAndSave();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  Future<void> _restorePreferencesAndSave() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      if (!widget.initialShowHistory &&
          prefs.containsKey(AdminNavPersistence.leaderboardShowHistoryKey)) {
        showHistory =
            prefs.getBool(AdminNavPersistence.leaderboardShowHistoryKey) ??
                false;
      }
      if (widget.initialLevel == null &&
          prefs.containsKey(AdminNavPersistence.leaderboardLevelKey)) {
        selectedLevel =
            prefs.getString(AdminNavPersistence.leaderboardLevelKey) ??
                'Overall';
      }
      if (widget.initialQuizCode == null &&
          prefs.containsKey(AdminNavPersistence.leaderboardQuizCodeKey)) {
        final savedCode =
            prefs.getString(AdminNavPersistence.leaderboardQuizCodeKey);
        if (savedCode != null && savedCode.isNotEmpty) {
          _selectedQuizCode = savedCode;
          _isViewingFromHistory = true;
        }
      }
    } catch (_) {}
    if (mounted) setState(() {});
    await _savePage();
  }

  Future<void> _savePage() async {
    await AdminNavPersistence.savePage(
      showHistory ? 'admin_leaderboard_history' : 'leaderboard',
      leaderboardQuizCode: _selectedQuizCode,
      leaderboardLevel: selectedLevel,
      leaderboardShowHistory: showHistory,
    );
  }

  // =========================================================
  // NAVIGATION & DRAWER
  // =========================================================

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
      await AdminNavPersistence.savePage(pageKey);
    }

    if (!context.mounted || destination == 'leaderboard') return;

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
      case 'question_list':
        page = const QuestionListScreen();
        break;
      case 'quiz_sessions':
        page = const ManageQuizSessionsScreen();
        break;
      case 'reports':
        page = const AdminReportScreen();
        break;
      default:
        page = null;
    }

    if (page == null || !context.mounted) return;

    Navigator.of(context).pushReplacement(adminPageRoute(page));
  }

  void _showProfileMenu(BuildContext context) {
    showAdminProfileSidePopup(context);
  }

  Widget _adminNavigationDrawer(BuildContext context) {
    return AdminSidebar(
      currentPage: 'leaderboard',
      onDestinationSelected: (destination) {
        _navigateFromAdminSidebar(context, destination);
      },
      onProfileTap: () => _showProfileMenu(context),
    );
  }

  // =========================================================
  // BUILD MAIN LEADERBOARD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AdminThemeColors.background,
      endDrawer: showHistory ? null : _adminNavigationDrawer(context),

      // App Bar
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        titleSpacing: showHistory ? 0 : 16,
        toolbarHeight: kAdminAppBarHeight,
        leading: showHistory
            ? IconButton(
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: AdminThemeColors.textPrimary,
                ),
                tooltip: 'Back',
                onPressed: () {
                  setState(() => showHistory = false);
                  _savePage();
                },
              )
            : null,
        title: showHistory
            ? const Text(
                'History',
                style: TextStyle(
                  color: AdminThemeColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              )
            : Row(
                children: [
                  // Admin Shield Badge Icon
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
                          color: AdminThemeColors.primary.withValues(
                            alpha: 0.35,
                          ),
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
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
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
                                    color: AdminThemeColors.primary.withValues(
                                      alpha: 0.22,
                                    ),
                                    width: 1,
                                  ),
                                ),
                                child: const Text(
                                  'Leaderboard',
                                  style: TextStyle(
                                    color: AdminThemeColors.primary,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'View live rankings for each quiz competition.',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AdminThemeColors.textMuted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        actions: showHistory
            ? const []
            : [
                // 3 Lines Navigation Menu on the RIGHT side
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Builder(
                      builder: (drawerContext) => IconButton(
                        icon: const Icon(
                          Icons.menu_rounded,
                          color: AdminThemeColors.textPrimary,
                          size: 24,
                        ),
                        tooltip: 'Open navigation menu',
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          FocusScope.of(context).unfocus();
                          Scaffold.of(drawerContext).openEndDrawer();
                        },
                      ),
                    ),
                  ),
                ),
              ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: AdminThemeColors.border,
          ),
        ),
      ),

      body: AdminCircuitBackground(
        child: showHistory
            ? AdminLeaderboardHistoryView(
                onBack: () {
                  if (mounted) {
                    setState(() => showHistory = false);
                    _savePage();
                  }
                },
                onOverview: (quizCode) {
                  if (!mounted) return;
                  setState(() {
                    _selectedQuizCode = quizCode;
                    _isViewingFromHistory = true;
                    selectedLevel = 'Overall';
                    showHistory = false;
                  });
                  _savePage();
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
                          color: AdminThemeColors.primary,
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
                      'tie_breaker_invite',
                      'tie_breaker_preparation',
                      'tie_breaker',
                      'tie_breaker_ended',
                      'tiebreaker',
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
                      final data = doc.data();
                      if (data['deleted'] == true ||
                          data['isDeleted'] == true ||
                          data['status'] == 'deleted') {
                        return false;
                      }

                      final status = (data['status'] ?? '')
                          .toString()
                          .trim()
                          .toLowerCase()
                          .replaceAll('-', '_')
                          .replaceAll(' ', '_');

                      final isTieBreakerActive = data['tieBreakerActive'] == true ||
                          status.contains('tie_breaker') ||
                          status.contains('tiebreaker') ||
                          status.contains('tie');

                      final isFinished = data['isFinished'] == true ||
                          data['isCompleted'] == true ||
                          data['completed'] == true ||
                          data['finished'] == true ||
                          finishedStatuses.contains(status);

                      if (!isTieBreakerActive && isFinished) {
                        return false;
                      }

                      // If tie breaker is active, it MUST be in live ranking
                      if (isTieBreakerActive) {
                        return true;
                      }

                      return activeStatuses.contains(status) ||
                          !finishedStatuses.contains(status);
                    }).toList();

                    bool isViewingHistoryQuiz = false;
                    QueryDocumentSnapshot<Map<String, dynamic>>? chosenDoc;

                    if (_isViewingFromHistory &&
                        _selectedQuizCode != null &&
                        _selectedQuizCode!.trim().isNotEmpty) {
                      final target = _selectedQuizCode!.trim();
                      for (final d in allSessions) {
                        final code = (d.data()['quizCode'] ?? d.id)
                            .toString()
                            .trim();
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
                                'levels': ['Level 1', 'Level 2', 'Level 3'],
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
                          final code = (d.data()['quizCode'] ?? d.id)
                              .toString()
                              .trim();
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
                              'levels': ['Level 1', 'Level 2', 'Level 3'],
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
                    final quizTitle =
                        (quizData['title'] ??
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
                        return StreamBuilder<
                          QuerySnapshot<Map<String, dynamic>>
                        >(
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
                                  color: AdminThemeColors.primary,
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
                            _syncOrFetchLevelScores(
                              effectiveCode,
                              scores,
                              quizData: quizData,
                            );
                            final configuredLevels =
                                _extractConfiguredLevels(quizData);
                            final entries = _buildLeaderboard(
                              requests: requests,
                              scores: scores,
                              selectedLevel: selectedLevel,
                              configuredLevels: configuredLevels,
                            );

                            final rankingsDeclared = _canDeclareRankings(
                              quizData: quizData,
                              scores: scores,
                              entries: entries,
                              isViewingHistory: isViewingHistoryQuiz,
                            );

                            final rankTiers = _buildRankTiers(entries);

                            return SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                14,
                                16,
                                30,
                              ),
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
                                          IconButton(
                                            tooltip: 'Close history view',
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            icon: const Icon(
                                              Icons.close_rounded,
                                              size: 18,
                                              color: Color(0xFFC2410C),
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                _isViewingFromHistory = false;
                                                _selectedQuizCode = null;
                                              });
                                            },
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
                                    rankingsDeclared: rankingsDeclared,
                                    topTier: rankTiers.isNotEmpty
                                        ? rankTiers.first
                                        : null,
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
                                    _podium(
                                      tiers: rankTiers,
                                      rankingsDeclared: rankingsDeclared,
                                    ),
                                    const SizedBox(height: 20),
                                    _sectionHeader(
                                      'Contestant Standings',
                                      'Scores and ranking of all contestants.',
                                      Icons.format_list_numbered_rounded,
                                    ),
                                    const SizedBox(height: 10),
                                    _rankingList(
                                      entries: entries,
                                      tiers: rankTiers,
                                      rankingsDeclared: rankingsDeclared,
                                    ),
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

  // ================================================================
  // HERO CARD: EXACT DESIGN WITH BLUE GRADIENT & METRICS SUMMARY
  // ================================================================

  Widget _buildLiveRankingHeroCard({
    required BuildContext context,
    required String quizTitle,
    required String quizCode,
    required String status,
    required List<_LeaderboardEntry> entries,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> allSessions,
    bool rankingsDeclared = true,
    _RankTier? topTier,
  }) {
    final isLive =
        status == 'live' ||
        status == 'started' ||
        status == 'ongoing' ||
        status == 'in progress' ||
        status == 'inprogress';

    final String topLeaderName;
    final String topScore;

    if (!rankingsDeclared) {
      topLeaderName = 'Pending Question 2...';
      topScore = '-- pts';
    } else if (topTier != null && topTier.entries.isNotEmpty) {
      if (topTier.entries.length == 1) {
        topLeaderName = topTier.entries.first.name;
      } else {
        topLeaderName =
            '${topTier.entries.first.name} +${topTier.entries.length - 1} tied';
      }
      topScore = '${topTier.score} pts';
    } else {
      final topLeader = entries.isNotEmpty ? entries.first : null;
      topLeaderName = topLeader != null
          ? topLeader.name
          : 'Waiting for contestants...';
      topScore = topLeader != null ? '${topLeader.score} pts' : '0 pts';
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AdminThemeColors.primaryDark, AdminThemeColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AdminThemeColors.primary.withValues(alpha: 0.35),
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
            // Top Row: LIVE RANKING Pill + Status on Left, History Button on Right
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
                      Icon(
                        Icons.sensors_rounded,
                        color: Colors.white,
                        size: 13,
                      ),
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
                // History button inside hero card pushed to the right side
                InkWell(
                  onTap: () {
                    setState(() => showHistory = true);
                    _savePage();
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
                    dropdownColor: AdminThemeColors.primaryDark,
                    icon: const Icon(
                      Icons.arrow_drop_down_rounded,
                      color: Colors.white,
                    ),
                    value:
                        allSessions.any(
                          (d) =>
                              (d.data()['quizCode'] ?? d.id)
                                  .toString()
                                  .trim() ==
                              quizCode,
                        )
                        ? quizCode
                        : (allSessions.first.data()['quizCode'] ??
                                  allSessions.first.id)
                              .toString()
                              .trim(),
                    items: allSessions.map((doc) {
                      final code = (doc.data()['quizCode'] ?? doc.id)
                          .toString()
                          .trim();
                      final title =
                          (doc.data()['title'] ??
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
                          'WINNER',
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AdminThemeColors.border, width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C5424B8),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
          BoxShadow(
            color: Color(0x05000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(
          children: [
            Container(
              height: 3.5,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AdminThemeColors.primary, Color(0xFF4C1D95)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3E8FF),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AdminThemeColors.primary.withValues(alpha: 0.18),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AdminThemeColors.primary, Color(0xFF4C1D95)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.hourglass_top_rounded,
                          size: 26,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF59E0B),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'AWAITING SUBMISSIONS',
                          style: TextStyle(
                            color: Color(0xFFB45309),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Waiting for Contestant Answers',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AdminThemeColors.textPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: const Text(
                      'Scores and rank positions will dynamically stream and update here in real-time as contestants submit their answers.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AdminThemeColors.textMuted,
                        height: 1.45,
                      ),
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

  Widget _noActiveQuizCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AdminThemeColors.border, width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C5424B8),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
          BoxShadow(
            color: Color(0x05000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(
          children: [
            Container(
              height: 3.5,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AdminThemeColors.primary, Color(0xFF4C1D95)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 38, horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3E8FF),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AdminThemeColors.primary.withValues(alpha: 0.20),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AdminThemeColors.primary, Color(0xFF4C1D95)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.leaderboard_rounded,
                          size: 28,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3E8FF),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFD8B4FE)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AdminThemeColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'LEADERBOARD STANDBY',
                          style: TextStyle(
                            color: AdminThemeColors.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No Active Quiz Right Now',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AdminThemeColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: const Text(
                      'Live rankings and contestant standings will automatically appear and stream here in real-time once an active quiz begins.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AdminThemeColors.textMuted,
                        fontSize: 12.5,
                        height: 1.45,
                      ),
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

  // ================================================================
  // LEVEL SELECTOR TABS
  // ================================================================

  Widget _levelSelector({Map<String, dynamic>? quizData}) {
    if (quizData != null) {
      return _buildLevelSelectorTabs(quizData);
    }
    return const SizedBox.shrink();
  }

  List<String> _extractConfiguredLevels(Map<String, dynamic>? data) {
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
        final normalizedLabel = numericLevel != null
            ? 'Level $numericLevel'
            : rawLabel;
        if (!configuredLevels.contains(normalizedLabel)) {
          configuredLevels.add(normalizedLabel);
        }
      }
    }

    if (configuredLevels.isEmpty) {
      final int highestAvailableLevel = completedLevel > currentLevel
          ? completedLevel
          : currentLevel;
      final int levelCount = highestAvailableLevel > 1
          ? highestAvailableLevel
          : 1;
      for (var number = 1; number <= levelCount; number++) {
        configuredLevels.add('Level $number');
      }
    }

    final bool hasTieBreaker = data?['tieBreakerActive'] == true ||
        (data?['status'] ?? '').toString().toLowerCase().contains('tie') ||
        data?['tieBreakerRank'] != null;
    if (hasTieBreaker && !configuredLevels.contains('Tie Breaker')) {
      configuredLevels.add('Tie Breaker');
    }

    return configuredLevels;
  }

  Widget _buildLevelSelectorTabs(Map<String, dynamic>? data) {
    final configuredLevels = _extractConfiguredLevels(data);
    return _levelTabs(configuredLevels);
  }

  Widget _levelTabs(List<String> configuredLevels) {
    final cleanLevels = configuredLevels
        .where((l) => l.trim().toLowerCase() != 'overall')
        .toList();

    final bool hasTieTab = cleanLevels.remove('Tie Breaker');

    if (!cleanLevels.contains('Level 1')) {
      cleanLevels.insert(0, 'Level 1');
    }

    // Siguradoha nga numerically ascending ang levels: Level 1, Level 2, Level 3...
    cleanLevels.sort((a, b) {
      final matchA = RegExp(r'\d+').firstMatch(a);
      final matchB = RegExp(r'\d+').firstMatch(b);
      final numA = matchA != null ? int.tryParse(matchA.group(0)!) ?? 0 : 0;
      final numB = matchB != null ? int.tryParse(matchB.group(0)!) ?? 0 : 0;
      if (numA != numB) return numA.compareTo(numB);
      return a.compareTo(b);
    });

    if (hasTieTab) {
      cleanLevels.add('Tie Breaker');
    }

    final levels = <String>['Overall', ...cleanLevels];
    if (!levels.contains(selectedLevel)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !levels.contains(selectedLevel)) {
          setState(() {
            selectedLevel = 'Overall';
          });
        }
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool shouldScroll =
            levels.length > 4 && constraints.maxWidth < (levels.length * 75);
        final buttons = [
          for (final level in levels)
            shouldScroll
                ? SizedBox(
                    width: 78,
                    child: _levelButton(level),
                  )
                : Flexible(fit: FlexFit.tight, child: _levelButton(level)),
        ];

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: AdminThemeColors.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0617245A),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: shouldScroll
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: buttons,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.max,
                  children: buttons,
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
            _savePage();
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
                    colors: [
                      AdminThemeColors.primary,
                      AdminThemeColors.primaryDark,
                    ],
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
                color: selected ? Colors.white : AdminThemeColors.textMuted,
                fontSize: 10,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ================================================================
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
            color: AdminThemeColors.primary,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(width: 9),
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFFF0EBFF),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: AdminThemeColors.primary, size: 17),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AdminThemeColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AdminThemeColors.textMuted,
                  fontSize: 10,
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
  // PODIUM (TOP 3 PERFORMERS)
  // ================================================================

  Widget _podium({
    required List<_RankTier> tiers,
    required bool rankingsDeclared,
  }) {
    final tier1 = tiers.isNotEmpty ? tiers[0] : null;
    final tier2 = tiers.length > 1 ? tiers[1] : null;
    final tier3 = tiers.length > 2 ? tiers[2] : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AdminThemeColors.border),
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
                  color: AdminThemeColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Top Performers',
                  style: TextStyle(
                    color: AdminThemeColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: rankingsDeclared
                      ? const Color(0xFFF0EBFF)
                      : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  rankingsDeclared ? 'TOP 3' : 'PENDING Q2',
                  style: TextStyle(
                    color: rankingsDeclared
                        ? AdminThemeColors.primary
                        : const Color(0xFFB45309),
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          if (!rankingsDeclared) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: Color(0xFFD97706),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Rankings will be declared after Question 2 concludes once contestants earn points.',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: _podiumTier(
                  entries: tier2?.entries ?? const [],
                  score: tier2?.score ?? 0,
                  rank: 2,
                  height: 105,
                  rankingsDeclared: rankingsDeclared,
                ),
              ),
              Expanded(
                child: _podiumTier(
                  entries: tier1?.entries ?? const [],
                  score: tier1?.score ?? 0,
                  rank: 1,
                  height: 135,
                  rankingsDeclared: rankingsDeclared,
                ),
              ),
              Expanded(
                child: _podiumTier(
                  entries: tier3?.entries ?? const [],
                  score: tier3?.score ?? 0,
                  rank: 3,
                  height: 90,
                  rankingsDeclared: rankingsDeclared,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _podiumTier({
    required List<_LeaderboardEntry> entries,
    required int score,
    required int rank,
    required double height,
    required bool rankingsDeclared,
  }) {
    final bool isFirst = rank == 1;
    final bool hasEntries = rankingsDeclared && entries.isNotEmpty;
    final bool isTied = rankingsDeclared && entries.length > 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Rank Circle
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
            boxShadow: [
              BoxShadow(
                color: (rank == 1
                        ? const Color(0xFFF59E0B)
                        : rank == 2
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFFD97706))
                    .withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
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

        const SizedBox(height: 6),

        // Tied indicator badge if multiple contestants share this rank
        if (isTied) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFFDE68A),
                width: 0.8,
              ),
            ),
            child: Text(
              'TIED (${entries.length})',
              style: const TextStyle(
                fontSize: 7.5,
                fontWeight: FontWeight.w900,
                color: Color(0xFFB45309),
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(height: 2),
        ],

        // Contestant Name(s) / Placeholder
        ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: isTied ? 36 : 28,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!rankingsDeclared || !hasEntries)
                const Text(
                  '---',
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AdminThemeColors.textMuted,
                  ),
                )
              else ...[
                for (int i = 0; i < entries.length && i < 2; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text(
                      entries[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: AdminThemeColors.textPrimary,
                      ),
                    ),
                  ),
                if (entries.length > 2)
                  Text(
                    '+${entries.length - 2} more',
                    style: const TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: AdminThemeColors.primary,
                    ),
                  ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 3),

        // Score
        Text(
          rankingsDeclared
              ? (hasEntries ? '$score pts' : '0 pts')
              : '-- pts',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: rankingsDeclared && hasEntries
                ? AdminThemeColors.primary
                : AdminThemeColors.textMuted,
          ),
        ),

        const SizedBox(height: 8),

        // Podium Pedestal
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

  Widget _rankingList({
    required List<_LeaderboardEntry> entries,
    required List<_RankTier> tiers,
    required bool rankingsDeclared,
  }) {
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }

    if (!rankingsDeclared) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: AdminThemeColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0617245A),
              blurRadius: 9,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.hourglass_top_rounded,
                size: 28,
                color: AdminThemeColors.textMuted,
              ),
              SizedBox(height: 8),
              Text(
                'Rankings will be declared after Question 2 concludes.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AdminThemeColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Map each entry's ID to its rank
    final Map<String, int> rankMap = {};
    for (final tier in tiers) {
      for (final entry in tier.entries) {
        rankMap[entry.id] = tier.rank;
      }
    }

    // Top 3 tier UIDs are already displayed in the podium above
    final Set<String> top3Uids = {};
    for (int i = 0; i < tiers.length && i < 3; i++) {
      for (final e in tiers[i].entries) {
        top3Uids.add(e.id);
      }
    }

    // Contestants to show in standings list:
    // Rank 4+ or eliminated contestants
    final standingsEntries = <MapEntry<int, _LeaderboardEntry>>[];
    for (final entry in entries) {
      final rank = rankMap[entry.id] ?? (tiers.length + 1);
      if (!top3Uids.contains(entry.id) || entry.eliminated) {
        standingsEntries.add(MapEntry(rank, entry));
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AdminThemeColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0617245A),
            blurRadius: 9,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: standingsEntries.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 20, horizontal: 12),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.emoji_events_outlined,
                      size: 28,
                      color: AdminThemeColors.textMuted,
                    ),
                    SizedBox(height: 6),
                    Text(
                      'All current active contestants are in the Top 3 podium above.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AdminThemeColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                for (final item in standingsEntries)
                  _rankingItem(item.value, item.key),
              ],
            ),
    );
  }

  Widget _rankingItem(_LeaderboardEntry entry, int rank) {
    final bool isFirst = rank == 1;
    final bool isSecond = rank == 2;
    final bool isTop3 = rank <= 3;
    final bool isTop10 = rank >= 4 && rank <= 10;

    Widget leadingWidget;

    if (entry.eliminated) {
      // Eliminated contestant uses soft-red rank indicator
      leadingWidget = Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFFCA5A5), width: 1.2),
        ),
        alignment: Alignment.center,
        child: Text(
          '$rank',
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w900,
            color: Color(0xFFDC2626),
          ),
        ),
      );
    } else if (isTop3) {
      final trophyAsset = isFirst
          ? 'assets/trophies/gold_trophy_3d.jpg'
          : (isSecond
                ? 'assets/trophies/silver_trophy_3d.jpg'
                : 'assets/trophies/bronze_trophy_3d.jpg');
      final rankColor = isFirst
          ? const Color(0xFFF59E0B)
          : (isSecond ? const Color(0xFF94A3B8) : const Color(0xFFD97706));

      leadingWidget = Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: rankColor, width: 1.8),
              boxShadow: [
                BoxShadow(
                  color: rankColor.withValues(alpha: 0.28),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                trophyAsset,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(
                  Icons.emoji_events_rounded,
                  size: 20,
                  color: rankColor,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -2,
            right: -3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
              decoration: BoxDecoration(
                color: rankColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.2),
              ),
              alignment: Alignment.center,
              child: Text(
                '$rank',
                style: const TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      );
    } else if (isTop10) {
      const badgeAsset = 'assets/trophies/top10_badge_3d.jpg';
      const rankColor = Color(0xFF22C55E);

      leadingWidget = Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: rankColor, width: 1.8),
              boxShadow: [
                BoxShadow(
                  color: rankColor.withValues(alpha: 0.28),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                badgeAsset,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.workspace_premium_rounded,
                  size: 20,
                  color: rankColor,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -2,
            right: -3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
              decoration: BoxDecoration(
                color: rankColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.2),
              ),
              alignment: Alignment.center,
              child: Text(
                '$rank',
                style: const TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      leadingWidget = Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
        ),
        alignment: Alignment.center,
        child: Text(
          '$rank',
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w900,
            color: Color(0xFF475569),
          ),
        ),
      );
    }

    return Container(
      key: ValueKey('rank_item_${entry.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: entry.eliminated
            ? const Color(0xFFFFF7F7)
            : (isFirst
                ? const Color(0xFFFFFDF5)
                : (isTop3
                    ? const Color(0xFFFAF7FF)
                    : (isTop10 ? const Color(0xFFF0FDF4) : Colors.white))),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: entry.eliminated
              ? const Color(0xFFFECACA)
              : (isFirst
                  ? const Color(0xFFFDE68A)
                  : (isTop3
                      ? const Color(0xFFDDD6FE)
                      : (isTop10
                          ? const Color(0xFF86EFAC)
                          : AdminThemeColors.border))),
          width: (entry.eliminated || isTop3 || isTop10) ? 1.2 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: entry.eliminated
                ? const Color(0x10DC2626)
                : (isFirst
                    ? const Color(0x12F59E0B)
                    : const Color(0x0517245A)),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          leadingWidget,
          const SizedBox(width: 12),

          // Contestant Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AdminThemeColors.textPrimary,
                        ),
                      ),
                    ),
                    if (entry.eliminated) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFFFCA5A5),
                            width: 0.8,
                          ),
                        ),
                        child: const Text(
                          'ELIMINATED',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFDC2626),
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (entry.teamName.isNotEmpty &&
                    entry.teamName != entry.name) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.school.isNotEmpty
                        ? '${entry.teamName} • ${entry.school}'
                        : entry.teamName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: AdminThemeColors.textMuted,
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
                      fontWeight: FontWeight.w500,
                      color: AdminThemeColors.textMuted,
                    ),
                  ),
                ],
                if (entry.members.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Members: ${entry.members.join(', ')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 9.5,
                      color: AdminThemeColors.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),

          // Score Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isFirst
                  ? const Color(0xFFFEF3C7)
                  : (isTop10
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFF0EBFF)),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isFirst
                    ? const Color(0xFFF59E0B)
                    : (isTop10
                          ? const Color(0xFF4ADE80)
                          : const Color(0xFFDDD6FE)),
                width: 1,
              ),
            ),
            child: Text(
              '${entry.score} pts',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: isFirst
                    ? const Color(0xFFB45309)
                    : (isTop10
                          ? const Color(0xFF15803D)
                          : AdminThemeColors.primary),
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
            border: Border.all(color: AdminThemeColors.border),
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
                  color: AdminThemeColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AdminThemeColors.textMuted,
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
  // LEVEL SCORES SYNC & ENGINE
  // ================================================================

  int _getAdminPointsForLevel(int level, Map<String, dynamic>? quizData) {
    if (quizData == null) return level;
    final rawSettings = quizData['levelSettings'] ?? quizData['levels'];
    if (rawSettings is Map) {
      final target = 'level$level';
      for (final entry in rawSettings.entries) {
        final norm = entry.key
            .toString()
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '');
        if ((norm == target || norm == '$level') && entry.value is Map) {
          final val = entry.value['pointsPerCorrectAnswer'] ??
              entry.value['points_per_correct_answer'] ??
              entry.value['pointsPerQuestion'] ??
              entry.value['points'];
          if (val is num && val > 0) return val.toInt();
          if (val != null) {
            final p = int.tryParse(val.toString());
            if (p != null && p > 0) return p;
          }
        }
      }
    }
    for (final key in [
      'level${level}Points',
      'level${level}PointsPerCorrectAnswer',
      'level${level}PointsPerQuestion',
      'level_${level}_points',
    ]) {
      final val = quizData[key];
      if (val is num && val > 0) return val.toInt();
      if (val != null) {
        final p = int.tryParse(val.toString());
        if (p != null && p > 0) return p;
      }
    }
    return level;
  }

  int _resolveResponseQuestionLevel(
    String docId,
    Map<String, dynamic> rData,
    Map<String, dynamic>? quizData,
  ) {
    final rawLevelQuestions = quizData?['levelQuestions'] ??
        quizData?['level_questions'];

    // 1. Check by questionId in levelQuestions
    final qId = (rData['questionId'] ?? rData['id'] ?? '').toString().trim();
    if (qId.isNotEmpty && rawLevelQuestions is Map) {
      for (final entry in rawLevelQuestions.entries) {
        if (entry.value is List && (entry.value as List).contains(qId)) {
          final m = RegExp(r'(\d+)').firstMatch(entry.key.toString());
          if (m != null) {
            final p = int.tryParse(m.group(1)!);
            if (p != null && p > 0) return p;
          }
        }
      }
    }

    // 2. Check by question index from docId or questionNumber
    final matchQ = RegExp(r'question_(\d+)').firstMatch(docId);
    int qIndex = matchQ != null ? (int.tryParse(matchQ.group(1)!) ?? -1) : -1;
    if (qIndex < 0 && rData['questionNumber'] is num) {
      qIndex = (rData['questionNumber'] as num).toInt() - 1;
    }

    if (qIndex >= 0 && rawLevelQuestions is Map) {
      int accumulated = 0;
      for (int l = 1; l <= 20; l++) {
        final target = 'level$l';
        int count = 0;
        for (final entry in rawLevelQuestions.entries) {
          final norm = entry.key
              .toString()
              .toLowerCase()
              .replaceAll(RegExp(r'[^a-z0-9]'), '');
          if ((norm == target || norm == '$l') && entry.value is List) {
            count = (entry.value as List).length;
            break;
          }
        }
        if (count > 0) {
          if (qIndex < accumulated + count) {
            return l;
          }
          accumulated += count;
        }
      }
    }

    // 3. Fallback to sessionLevel or level in rData
    final rawLvl = rData['sessionLevel'] ?? rData['level'];
    if (rawLvl is num) {
      final v = rawLvl.toInt();
      if (v > 0) return v;
    } else if (rawLvl != null) {
      final m = RegExp(r'(\d+)').firstMatch(rawLvl.toString());
      if (m != null) {
        final v = int.tryParse(m.group(1)!);
        if (v != null && v > 0) return v;
      }
    }

    return 1;
  }

  void _syncOrFetchLevelScores(
    String quizCode,
    List<QueryDocumentSnapshot> scoreDocs, {
    Map<String, dynamic>? quizData,
  }) {
    if (quizCode.isEmpty) return;

    if (_lastSyncedQuizCode != quizCode) {
      _lastSyncedQuizCode = quizCode;
      _levelScoresCache.clear();
      for (final sub in _responseSubs.values) {
        sub.cancel();
      }
      _responseSubs.clear();
      _syncingUids.clear();
      _checkedUids.clear();
    }

    for (final doc in scoreDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final uid = (data['uid'] ?? doc.id).toString();

      if (!_responseSubs.containsKey(uid)) {
        final sub = FirebaseFirestore.instance
            .collection('quiz_sessions')
            .doc(quizCode)
            .collection('answers')
            .doc(uid)
            .collection('responses')
            .snapshots()
            .listen((responsesSnap) {
          if (!mounted) return;
          final Map<int, int> userLevelScores = {};
          int totalRespPoints = 0;
          for (final r in responsesSnap.docs) {
            final rData = r.data();
            final int lvl =
                _resolveResponseQuestionLevel(r.id, rData, quizData);

            final isCorrect = rData['isCorrect'] == true ||
                (rData['answerStatus'] ?? '').toString().toLowerCase() ==
                    'correct' ||
                (rData['contestStatus'] ?? '').toString().toLowerCase() ==
                    'approved';
            if (isCorrect) {
              final adminPts = _getAdminPointsForLevel(lvl, quizData);
              int pts = adminPts > 0 ? adminPts : 1;
              userLevelScores[lvl] = (userLevelScores[lvl] ?? 0) + pts;
              totalRespPoints += pts;
            }
          }

          if (userLevelScores.isNotEmpty) {
            setState(() {
              _levelScoresCache[uid] = userLevelScores;
            });

            final updateData = <String, dynamic>{};
            for (final entry in userLevelScores.entries) {
              updateData['level${entry.key}Score'] = entry.value;
              updateData['level_${entry.key}'] = entry.value;
            }
            updateData['levelScores'] = {
              for (final entry in userLevelScores.entries)
                'Level ${entry.key}': entry.value,
            };
            final int tiePts = _toInt(data['tieBreakerScore']);
            final int realTotal = totalRespPoints + tiePts;
            updateData['score'] = realTotal;
            updateData['totalScore'] = realTotal;
            doc.reference
                .set(updateData, SetOptions(merge: true))
                .catchError((_) {});
          }
        }, onError: (_) {});
        _responseSubs[uid] = sub;
      }
    }
  }

  // ================================================================
  // RANKING VALIDATION & TIER GROUPING
  // ================================================================

  bool _canDeclareRankings({
    required Map<String, dynamic> quizData,
    required List<QueryDocumentSnapshot> scores,
    required List<_LeaderboardEntry> entries,
    required bool isViewingHistory,
  }) {
    if (entries.isEmpty) return false;

    // Must have at least one contestant who has scored points > 0
    final bool hasScore = entries.any((e) => e.score > 0);
    if (!hasScore) return false;

    // Past quizzes from history with scores can show rankings
    if (isViewingHistory) return true;

    final status = (quizData['status'] ?? '').toString().toLowerCase().trim();
    final eventStatus =
        (quizData['eventStatus'] ?? '').toString().toLowerCase().trim();

    // If quiz is finished/completed, rankings are declared
    if (status == 'finished' || status == 'completed' || status == 'ended') {
      return true;
    }

    // Rankings are officially declared only after Question 2 concludes
    final int currentLevel = _toInt(quizData['currentLevel'] ?? 1);
    final int currentQuestion = _toInt(quizData['currentQuestion'] ?? 0);

    if (currentLevel > 1) return true;
    if (currentQuestion >= 2) return true;

    // When on Question 2 (index 1), check if Question 2 has concluded
    if (currentQuestion == 1 &&
        (status == 'contest_review' ||
            status == 'level_pause' ||
            status == 'review' ||
            eventStatus == 'contest_review' ||
            eventStatus == 'level_pause')) {
      return true;
    }

    // Check if any contestant score document indicates completion of Question 2 or higher
    for (final doc in scores) {
      final sData = doc.data() as Map<String, dynamic>;
      final lq = _toInt(sData['lastQuestion']);
      if (lq >= 2) return true;
    }

    return false;
  }

  List<_RankTier> _buildRankTiers(List<_LeaderboardEntry> entries) {
    // Only active contestants with score > 0 qualify for rank tiers
    final activeEntries =
        entries.where((e) => !e.eliminated && e.score > 0).toList();
    if (activeEntries.isEmpty) return [];

    final Map<int, List<_LeaderboardEntry>> scoreGroups = {};
    for (final entry in activeEntries) {
      scoreGroups.putIfAbsent(entry.score, () => []).add(entry);
    }

    final sortedScores =
        scoreGroups.keys.toList()..sort((a, b) => b.compareTo(a));

    final List<_RankTier> tiers = [];
    int rank = 1;
    for (final score in sortedScores) {
      tiers.add(_RankTier(
        rank: rank,
        score: score,
        entries: scoreGroups[score]!,
      ));
      rank++;
    }
    return tiers;
  }

  // ================================================================
  // LEADERBOARD COMPUTATION ENGINE WITH SPEED TIEBREAKER
  // ================================================================

  List<_LeaderboardEntry> _buildLeaderboard({
    required List<QueryDocumentSnapshot> requests,
    required List<QueryDocumentSnapshot> scores,
    required String selectedLevel,
    List<String> configuredLevels = const [],
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
      final school = (data['school'] ?? data['schoolName'] ?? '')
          .toString()
          .trim();
      final members = teamName.isNotEmpty
          ? _teamMembers(data['teamMembers'] ?? data['members'])
          : <String>[];
      final key = teamName.isNotEmpty ? 'team:$teamName' : 'user:$uid';
      final display = teamName.isNotEmpty ? teamName : name;

      final reqIsEliminated = status == 'eliminated' ||
          data['eliminated'] == true ||
          data['isEliminated'] == true;

      final current = grouped[key];
      if (current == null) {
        grouped[key] = _LeaderboardEntry(
          id: uid,
          name: display,
          teamName: teamName,
          members: members,
          school: school,
          score: 0,
          eliminated: reqIsEliminated,
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
          eliminated: current.eliminated || reqIsEliminated,
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
      final school = (data['school'] ?? data['schoolName'] ?? '')
          .toString()
          .trim();
      final members = teamName.isNotEmpty
          ? _teamMembers(data['teamMembers'] ?? data['members'])
          : <String>[];
      final isEliminated =
          data['eliminated'] == true ||
          data['isEliminated'] == true ||
          (data['status'] ?? '').toString().toLowerCase() == 'eliminated';
      final status = (data['status'] ?? '').toString();
      final lastSubTime = data['lastSubmissionTime'] is Timestamp
          ? data['lastSubmissionTime'] as Timestamp
          : (data['updatedAt'] is Timestamp
                ? data['updatedAt'] as Timestamp
                : null);

      // Score based on selected level
      int contestantScore = 0;
      final cached = _levelScoresCache[uid];

      // Robust accumulation across all level keys and levelScores map
      int sumOfAllLevels = 0;
      final Map<int, int> levelPointsMap = {};

      if (cached != null && cached.isNotEmpty) {
        levelPointsMap.addAll(cached);
        sumOfAllLevels = cached.values.fold<int>(0, (acc, val) => acc + val);
      } else {
        if (data['levelScores'] is Map) {
          (data['levelScores'] as Map).forEach((k, v) {
            final m = RegExp(r'\d+').firstMatch(k.toString());
            final lvlNum = m != null ? int.tryParse(m.group(0)!) ?? 0 : 0;
            final p = _toInt(v);
            if (lvlNum > 0 && p > 0) {
              levelPointsMap[lvlNum] = p;
            }
          });
        }
        for (int i = 1; i <= 20; i++) {
          final lKey = 'level${i}Score';
          final aKey = 'level_$i';
          final val = _toInt(data[lKey] ?? data[aKey]);
          if (val > 0 &&
              (!levelPointsMap.containsKey(i) || levelPointsMap[i]! < val)) {
            levelPointsMap[i] = val;
          }
        }
        sumOfAllLevels =
            levelPointsMap.values.fold<int>(0, (acc, val) => acc + val);
      }

      final tieBreakerExtra = _toInt(data['tieBreakerScore']);
      final storedTotal =
          _toInt(data['score'] ?? data['totalScore'] ?? data['points'] ?? 0);

      if (selectedLevel == 'Tie Breaker') {
        contestantScore = tieBreakerExtra;
      } else if (selectedLevel == 'Overall') {
        final totalWithTie = sumOfAllLevels + tieBreakerExtra;
        contestantScore = totalWithTie > storedTotal ? totalWithTie : storedTotal;
        if (contestantScore < storedTotal + tieBreakerExtra && tieBreakerExtra > 0 && storedTotal == sumOfAllLevels) {
          contestantScore = storedTotal + tieBreakerExtra;
        }
      } else {
        final levelMatch = RegExp(r'\d+').firstMatch(selectedLevel);
        final levelNum = levelMatch != null
            ? int.tryParse(levelMatch.group(0)!) ?? 1
            : 1;
        contestantScore = levelPointsMap[levelNum] ?? 0;
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
          score: teamName.isNotEmpty
              ? (contestantScore > current.score
                  ? contestantScore
                  : current.score)
              : contestantScore,
          eliminated: current.eliminated || isEliminated,
          status: status.isNotEmpty ? status : current.status,
          lastSubmissionTime: lastSubTime ?? current.lastSubmissionTime,
        );
      }
    }

    final result = grouped.values.toList();
    result.sort((a, b) {
      // Active contestants always rank above eliminated contestants
      if (a.eliminated != b.eliminated) {
        return a.eliminated ? 1 : -1;
      }
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;
      if (a.lastSubmissionTime != null && b.lastSubmissionTime != null) {
        final timeCompare = a.lastSubmissionTime!.compareTo(
          b.lastSubmissionTime!,
        );
        if (timeCompare != 0) return timeCompare;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return result;
  }

  List<String> _teamMembers(dynamic raw) {
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return raw
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return <String>[];
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

// ================================================================
// LEADERBOARD MODEL
// ================================================================

class _RankTier {
  final int rank;
  final int score;
  final List<_LeaderboardEntry> entries;

  const _RankTier({
    required this.rank,
    required this.score,
    required this.entries,
  });
}

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
// LEADERBOARD HISTORY VIEW
// ================================================================

class AdminLeaderboardHistoryView extends StatefulWidget {
  final VoidCallback? onBack;
  final ValueChanged<String> onOverview;

  const AdminLeaderboardHistoryView({
    super.key,
    this.onBack,
    required this.onOverview,
  });

  @override
  State<AdminLeaderboardHistoryView> createState() =>
      _AdminLeaderboardHistoryViewState();
}

class _AdminLeaderboardHistoryViewState
    extends State<AdminLeaderboardHistoryView> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _friendlyQuizStatus(dynamic rawStatus) {
    final status = (rawStatus?.toString() ?? 'unknown')
        .toLowerCase()
        .replaceAll(' ', '_');

    if (status.contains('tie_breaker') || status.contains('tiebreaker') || status.contains('tie')) {
      return 'TIE BREAKER';
    }

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
    return Column(
      children: [
        // Search Bar inside history
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          color: Colors.white,
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFF8F5FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdminThemeColors.border),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                hintText: 'Search quiz title or code...',
                hintStyle: const TextStyle(
                  fontSize: 12.5,
                  color: AdminThemeColors.textMuted,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 19,
                  color: AdminThemeColors.textMuted,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
              ),
              style: const TextStyle(
                fontSize: 13,
                color: AdminThemeColors.textPrimary,
              ),
            ),
          ),
        ),
        const Divider(height: 1, thickness: 1, color: AdminThemeColors.border),

        // List of history sessions
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('quiz_sessions')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(
                    color: AdminThemeColors.primary,
                  ),
                );
              }

              if (snapshot.hasError) {
                return Center(
                  child: Text('Error loading history: ${snapshot.error}'),
                );
              }

              final allDocs = snapshot.data?.docs ?? [];
              final filteredDocs = allDocs.where((doc) {
                final data = doc.data();
                final title = (data['title'] ?? data['quizName'] ?? '')
                    .toString()
                    .toLowerCase();
                final code = (data['quizCode'] ?? doc.id)
                    .toString()
                    .toLowerCase();
                if (_searchQuery.isEmpty) return true;
                final q = _searchQuery.toLowerCase();
                return title.contains(q) || code.contains(q);
              }).toList();

              if (filteredDocs.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF0EBFF),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.history_rounded,
                            size: 32,
                            color: AdminThemeColors.primary,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'No Quiz History Found',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AdminThemeColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Completed and past quiz competitions will appear here for standings inspection.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AdminThemeColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
                itemCount: filteredDocs.length,
                itemBuilder: (context, index) {
                  final quiz = filteredDocs[index];
                  final data = quiz.data();
                  final title =
                      (data['title'] ?? data['quizName'] ?? 'Untitled Quiz')
                          .toString()
                          .trim();
                  final quizCode = (data['quizCode'] ?? quiz.id)
                      .toString()
                      .trim();
                  final statusStr = _friendlyQuizStatus(data['status']);
                  final isFinished = statusStr == 'FINISHED';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AdminThemeColors.border),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0617245A),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isFinished
                              ? const Color(0xFFF0EBFF)
                              : const Color(0xFFFAF7FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isFinished
                                ? const Color(0xFFDDD6FE)
                                : AdminThemeColors.border,
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          isFinished
                              ? Icons.emoji_events_rounded
                              : Icons.sensors_rounded,
                          color: isFinished
                              ? AdminThemeColors.primary
                              : AdminThemeColors.primaryLight,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AdminThemeColors.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AdminThemeColors.pillBg,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Code: $quizCode',
                                style: const TextStyle(
                                  color: AdminThemeColors.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isFinished
                                    ? const Color(0xFFECFDF5)
                                    : const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                statusStr,
                                style: TextStyle(
                                  color: isFinished
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFFF59E0B),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0EBFF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Inspect',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: AdminThemeColors.primary,
                              ),
                            ),
                            SizedBox(width: 2),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 15,
                              color: AdminThemeColors.primary,
                            ),
                          ],
                        ),
                      ),
                      onTap: () => widget.onOverview(quizCode),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// ADMIN QUIZ LEADERBOARD COMPATIBILITY WRAPPER (Preserved for splash/external routing)
// ============================================================================

class AdminQuizLeaderboardScreen extends StatelessWidget {
  final String quizCode;

  const AdminQuizLeaderboardScreen({super.key, required this.quizCode});

  @override
  Widget build(BuildContext context) {
    return AdminLeaderboardScreen(initialQuizCode: quizCode);
  }
}
