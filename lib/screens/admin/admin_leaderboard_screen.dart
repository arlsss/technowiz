import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'admin_dashboard.dart';
import 'manage_users_screen.dart';
import 'add_question_screen.dart';
import 'question_list_screen.dart';
import 'manage_quiz_sessions_screen.dart';
import 'admin_report_screen.dart';
import 'admin_sidebar.dart';
import 'admin_theme.dart';
import '../login_screen.dart';
import '../../navigation_persistence.dart';

// ============================================================================
// ADMIN LEADERBOARD SCREEN - MATCHES QUIZMASTER REAL-TIME DASHBOARD & HERO CARD
// ============================================================================

class AdminLeaderboardScreen extends StatefulWidget {
  const AdminLeaderboardScreen({super.key});

  @override
  State<AdminLeaderboardScreen> createState() => _AdminLeaderboardScreenState();
}

class _AdminLeaderboardScreenState extends State<AdminLeaderboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  bool showHistory = false;
  String? _selectedQuizCode;
  bool _isViewingFromHistory = false;
  String selectedLevel = 'Level 1';

  @override
  void initState() {
    super.initState();
    AdminNavPersistence.savePage('leaderboard');
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('technowiz_admin_last_page', pageKey);
      await prefs.remove('technowiz_admin_detail_quiz_code');
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

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => page!,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  void _showProfileMenu(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 25, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0EBFF),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFD8CCF7),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.admin_panel_settings_rounded,
                    color: AdminThemeColors.primary,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Admin',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AdminThemeColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  user?.email ?? 'No email available',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AdminThemeColors.textMuted),
                ),
                const SizedBox(height: 18),
                const Divider(color: AdminThemeColors.border),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      try {
                        final prefs = await SharedPreferences.getInstance();
                        await AdminNavPersistence.clear();
                        await prefs.remove('technowiz_admin_last_page');
                        await prefs.remove('technowiz_admin_detail_quiz_code');
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
                      backgroundColor: const Color(0xFFF0EBFF),
                      foregroundColor: AdminThemeColors.primary,
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
        );
      },
    );
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
      endDrawer: _adminNavigationDrawer(context),

      // App Bar
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.white,
        automaticallyImplyLeading: false,
        titleSpacing: showHistory ? 0 : 16,
        toolbarHeight: 62,
        leading: showHistory
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: AdminThemeColors.textPrimary),
                tooltip: 'Back',
                onPressed: () {
                  setState(() => showHistory = false);
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
                                    color: AdminThemeColors.primary
                                        .withValues(alpha: 0.22),
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
        actions: [
          // 3 Lines Navigation Menu on the RIGHT side
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Builder(
                builder: (drawerContext) => IconButton(
                  icon: const Icon(Icons.menu_rounded, color: AdminThemeColors.textPrimary, size: 24),
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
          child: Divider(height: 1, thickness: 1, color: AdminThemeColors.border),
        ),
      ),

      body: AdminCircuitBackground(
        child: showHistory
            ? AdminLeaderboardHistoryView(
                onBack: () {
                  if (mounted) setState(() => showHistory = false);
                },
                onOverview: (quizCode) {
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
                            final entries = _buildLeaderboard(
                              requests: requests,
                              scores: scores,
                              selectedLevel: selectedLevel,
                            );

                            return SingleChildScrollView(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 14, 16, 30),
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
  }) {
    final isLive = status == 'live' ||
        status == 'started' ||
        status == 'ongoing' ||
        status == 'in progress' ||
        status == 'inprogress';

    final topLeader = entries.isNotEmpty ? entries.first : null;
    final topLeaderName =
        topLeader != null ? topLeader.name : 'Waiting for contestants...';
    final topScore = topLeader != null ? '${topLeader.score} pts' : '0 pts';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            AdminThemeColors.primaryDark,
            AdminThemeColors.primary,
          ],
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
            // Top Row: LIVE RANKING Pill + Status + History Button (Responsive Wrap)
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
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
                  ],
                ),
                // History button inside hero card to switch to history
                InkWell(
                  onTap: () {
                    setState(() => showHistory = true);
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AdminThemeColors.border),
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
              color: Color(0xFFF0EBFF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.hourglass_empty_rounded,
              size: 30,
              color: AdminThemeColors.primary,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Waiting for Quiz Submissions',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AdminThemeColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Scores and rankings will update here live in real-time as contestants answer questions.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: AdminThemeColors.textMuted,
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
        border: Border.all(color: AdminThemeColors.border),
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
              color: Color(0xFFF0EBFF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.leaderboard_outlined,
              size: 32,
              color: AdminThemeColors.primary,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'No Active Quiz',
            style: TextStyle(
              color: AdminThemeColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Live rankings and standings will appear here once an active quiz begins.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AdminThemeColors.textMuted,
              fontSize: 13,
            ),
          ),
        ],
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
        final normalizedLabel =
            numericLevel != null ? 'Level $numericLevel' : rawLabel;
        if (!configuredLevels.contains(normalizedLabel)) {
          configuredLevels.add(normalizedLabel);
        }
      }
    }

    if (configuredLevels.isEmpty) {
      final int highestAvailableLevel =
          completedLevel > currentLevel ? completedLevel : currentLevel;
      final int levelCount =
          highestAvailableLevel > 1 ? highestAvailableLevel : 1;
      for (var number = 1; number <= levelCount; number++) {
        configuredLevels.add('Level $number');
      }
    }

    if (!configuredLevels.contains('Level 1')) {
      configuredLevels.insert(0, 'Level 1');
    }

    // Siguradoha nga numerically ascending ang levels: Level 1, Level 2, Level 3...
    configuredLevels.sort((a, b) {
      final matchA = RegExp(r'\d+').firstMatch(a);
      final matchB = RegExp(r'\d+').firstMatch(b);
      final numA = matchA != null ? int.tryParse(matchA.group(0)!) ?? 0 : 0;
      final numB = matchB != null ? int.tryParse(matchB.group(0)!) ?? 0 : 0;
      if (numA != numB) return numA.compareTo(numB);
      return a.compareTo(b);
    });

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
            border: Border.all(color: AdminThemeColors.border),
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

  Widget _podium(List<_LeaderboardEntry> entries) {
    final first = entries.isNotEmpty ? entries[0] : null;
    final second = entries.length > 1 ? entries[1] : null;
    final third = entries.length > 2 ? entries[2] : null;

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
                  color: const Color(0xFFF0EBFF),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Text(
                  'TOP 3',
                  style: TextStyle(
                    color: AdminThemeColors.primary,
                    fontSize: 8,
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
              Expanded(
                child: _podiumPerson(entry: third, rank: 3, height: 90),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _podiumPerson({
    required _LeaderboardEntry? entry,
    required int rank,
    required double height,
  }) {
    final bool isFirst = rank == 1;

    return Column(
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

        // Name
        Text(
          entry?.name ?? '---',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AdminThemeColors.textPrimary,
          ),
        ),

        const SizedBox(height: 3),

        // Score
        Text(
          '${entry?.score ?? 0} pts',
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: AdminThemeColors.primary,
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

  Widget _rankingList(List<_LeaderboardEntry> entries) {
    if (entries.isEmpty) {
      return const SizedBox.shrink();
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
      child: Column(
        children: [
          for (int i = 0; i < entries.length; i++)
            _rankingItem(entries[i], i + 1),
        ],
      ),
    );
  }

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
      badgeBg = const Color(0xFFF3E8FF);
      badgeBorder = const Color(0xFFDDD6FE);
      badgeTextColor = AdminThemeColors.primary;
    } else {
      badgeBg = AdminThemeColors.pillBg;
      badgeBorder = AdminThemeColors.border;
      badgeTextColor = AdminThemeColors.primary;
    }

    return Container(
      key: ValueKey('rank_item_${entry.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isFirst
            ? const Color(0xFFFFFDF5)
            : (isTop3 ? const Color(0xFFFAF7FF) : Colors.white),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isFirst
              ? const Color(0xFFFDE68A)
              : (isTop3 ? const Color(0xFFDDD6FE) : AdminThemeColors.border),
          width: isTop3 ? 1.4 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isFirst
                ? const Color(0x12F59E0B)
                : const Color(0x0517245A),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Rank Badge
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: badgeBorder, width: isTop3 ? 1.4 : 1),
            ),
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: badgeTextColor,
              ),
            ),
          ),
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
                        ),
                        child: const Text(
                          'ELIMINATED',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (entry.teamName.isNotEmpty && entry.teamName != entry.name) ...[
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
                  : const Color(0xFFF0EBFF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isFirst
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFFDDD6FE),
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
                    : AdminThemeColors.primary,
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
  // LEADERBOARD COMPUTATION ENGINE WITH SPEED TIEBREAKER
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
      final school =
          (data['school'] ?? data['schoolName'] ?? '').toString().trim();
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
      final school =
          (data['school'] ?? data['schoolName'] ?? '').toString().trim();
      final members = teamName.isNotEmpty
          ? _teamMembers(data['teamMembers'] ?? data['members'])
          : <String>[];
      final isEliminated = data['eliminated'] == true ||
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
      if (selectedLevel == 'Overall') {
        contestantScore =
            _toInt(data['score'] ?? data['totalScore'] ?? data['points'] ?? 0);
      } else {
        final levelMatch = RegExp(r'\d+').firstMatch(selectedLevel);
        final levelNum =
            levelMatch != null ? int.tryParse(levelMatch.group(0)!) ?? 1 : 1;
        final levelKey = 'level${levelNum}Score';
        final altKey = 'level_$levelNum';
        if (data.containsKey(levelKey)) {
          contestantScore = _toInt(data[levelKey]);
        } else if (data.containsKey(altKey)) {
          contestantScore = _toInt(data[altKey]);
        } else {
          final currentLevel =
              _toInt(data['currentLevel'] ?? data['level'] ?? 1);
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
          score: teamName.isNotEmpty
              ? current.score + contestantScore
              : contestantScore,
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
        final timeCompare =
            a.lastSubmissionTime!.compareTo(b.lastSubmissionTime!);
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
                final code = (data['quizCode'] ?? doc.id).toString().toLowerCase();
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
                  final quizCode =
                      (data['quizCode'] ?? quiz.id).toString().trim();
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
    return const AdminLeaderboardScreen();
  }
}
