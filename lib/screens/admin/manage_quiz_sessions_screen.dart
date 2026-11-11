import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_dashboard.dart';
import 'create_quiz_screen.dart';
import 'manage_users_screen.dart';
import 'add_question_screen.dart';
import 'question_list_screen.dart';
import 'admin_leaderboard_screen.dart';
import 'admin_report_screen.dart';
import 'admin_sidebar.dart';
import 'admin_theme.dart';
import '../login_screen.dart';
import '../../navigation_persistence.dart';

// ============================================================================
// RESPONSIVE UI HELPERS
// ============================================================================
// Keeps the same UI design while adapting spacing, sizing, and dialog widths
// for phones, tablets, and browser/desktop screens.
class _ResponsiveUI {
  static double width(BuildContext context) => MediaQuery.sizeOf(context).width;

  static double dialogWidth(BuildContext context, double desktopWidth) {
    final w = width(context);
    if (w < 600) return w - 28;
    return desktopWidth.clamp(420.0, w - 48);
  }
}

String _resolveQuestionAnswer(Map<String, dynamic> data) {
  final raw = (data['correctAnswer'] ??
          data['answer'] ??
          data['correctOption'] ??
          data['correct_option'] ??
          '')
      .toString()
      .trim();

  if (raw.isNotEmpty) {
    final upper = raw.toUpperCase();
    if (['A', 'B', 'C', 'D'].contains(upper)) {
      final opt = (data['option$upper'] ?? data['option_${upper.toLowerCase()}'])
          ?.toString()
          .trim();
      if (opt != null && opt.isNotEmpty) {
        return '$upper. $opt';
      }
      final options = data['options'];
      if (options is List) {
        final idx = upper.codeUnitAt(0) - 65;
        if (idx >= 0 && idx < options.length) {
          final text = options[idx]?.toString().trim() ?? '';
          if (text.isNotEmpty) return '$upper. $text';
        }
      } else if (options is Map && options[upper] != null) {
        return '$upper. ${options[upper]}';
      }
    }
    return raw;
  }

  final answers = data['correctAnswers'];
  if (answers is List && answers.isNotEmpty) {
    return answers.join(', ');
  }

  return 'No answer set';
}

class ManageQuizSessionsScreen extends StatefulWidget {
  const ManageQuizSessionsScreen({super.key});

  @override
  State<ManageQuizSessionsScreen> createState() =>
      _ManageQuizSessionsScreenState();
}

class _ManageQuizSessionsScreenState extends State<ManageQuizSessionsScreen> {
  @override
  void initState() {
    super.initState();
    AdminNavPersistence.savePage('quiz_sessions');
  }
  static const Color primaryPurple = AdminThemeColors.primary;
  static const Color backgroundColor = AdminThemeColors.background;
  static const Color textDark = AdminThemeColors.textPrimary;

  String _sessionStatusFilter = 'All';

  // =========================================================
  // STAT CARDS
  // =========================================================

  Widget _buildStatCard({
    required IconData icon,
    required int value,
    required String label,
    required Color color,
    required String filterKey,
  }) {
    final bool isSelected =
        _sessionStatusFilter.toLowerCase() == filterKey.toLowerCase();
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _sessionStatusFilter = isSelected ? 'All' : filterKey;
          });
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 86,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? color : color.withValues(alpha: 0.22),
              width: isSelected ? 1.6 : 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? color.withValues(alpha: 0.16)
                    : color.withValues(alpha: 0.08),
                blurRadius: isSelected ? 12 : 10,
                offset: const Offset(0, 3),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.82)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.32),
                      blurRadius: 7,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "$value",
                      style: const TextStyle(
                        color: textDark,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isSelected ? color : const Color(0xFF64748B),
                        fontSize: 11,
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w600,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCards({
    required bool isMobile,
    required int waitingCount,
    required int ongoingCount,
    required int publishedCount,
    required int unpublishedCount,
  }) {
    if (isMobile) {
      return Column(
        children: [
          Row(
            children: [
              _buildStatCard(
                icon: Icons.hourglass_top_rounded,
                value: waitingCount,
                label: "Waiting",
                color: const Color(0xFFE67E22),
                filterKey: "waiting",
              ),
              const SizedBox(width: 9),
              _buildStatCard(
                icon: Icons.play_circle_fill_rounded,
                value: ongoingCount,
                label: "Ongoing",
                color: const Color(0xFF16A34A),
                filterKey: "ongoing",
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              _buildStatCard(
                icon: Icons.public_rounded,
                value: publishedCount,
                label: "Published",
                color: const Color(0xFF3578E5),
                filterKey: "Published",
              ),
              const SizedBox(width: 9),
              _buildStatCard(
                icon: Icons.visibility_off_rounded,
                value: unpublishedCount,
                label: "Unpublished",
                color: primaryPurple,
                filterKey: "Unpublished",
              ),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        _buildStatCard(
          icon: Icons.hourglass_top_rounded,
          value: waitingCount,
          label: "Waiting",
          color: const Color(0xFFE67E22),
          filterKey: "waiting",
        ),
        const SizedBox(width: 12),
        _buildStatCard(
          icon: Icons.play_circle_fill_rounded,
          value: ongoingCount,
          label: "Ongoing",
          color: const Color(0xFF16A34A),
          filterKey: "ongoing",
        ),
        const SizedBox(width: 12),
        _buildStatCard(
          icon: Icons.public_rounded,
          value: publishedCount,
          label: "Published",
          color: const Color(0xFF3578E5),
          filterKey: "Published",
        ),
        const SizedBox(width: 12),
        _buildStatCard(
          icon: Icons.visibility_off_rounded,
          value: unpublishedCount,
          label: "Unpublished",
          color: primaryPurple,
          filterKey: "Unpublished",
        ),
      ],
    );
  }

  String textValue(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    return value.toString();
  }

  String getQuestionText(Map<String, dynamic> data) {
    return textValue(
      data['questionText'] ??
          data['question'] ??
          data['text'] ??
          data['question_title'],
      'Untitled Question',
    );
  }

  String getLevel(Map<String, dynamic> data) {
    final dynamic value =
        data['level'] ?? data['difficultyLevel'] ?? data['quizLevel'];

    if (value == null) {
      return 'Uncategorized';
    }

    return value.toString();
  }

  List<String> getOptions(Map<String, dynamic> data) {
    final dynamic options = data['options'];

    if (options is List) {
      return options.map((e) => e.toString()).toList();
    }

    final List<String> result = [];

    for (final key in ['optionA', 'optionB', 'optionC', 'optionD']) {
      if (data[key] != null && data[key].toString().trim().isNotEmpty) {
        result.add(data[key].toString());
      }
    }

    return result;
  }

  String getCorrectAnswer(Map<String, dynamic> data) {
    return textValue(
      data['correctAnswer'] ??
          data['answer'] ??
          data['correct_option'] ??
          data['correctOption'],
      '',
    );
  }

  int getOrder(Map<String, dynamic> data, int fallback) {
    final dynamic value = data['order'];

    if (value is int) return value;

    if (value is num) return value.toInt();

    return fallback;
  }

  // =========================================================
  // TOP NOTIFICATION
  // =========================================================

  void showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    AdminNotification.show(context, message, isError: error);
  }

  // =========================================================
  // DELETE QUIZ
  // =========================================================

  Future<bool> deleteQuiz(BuildContext context, String quizCode) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Delete Quiz?',
                  style: TextStyle(
                    color: textDark,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Delete quiz session "$quizCode"?\n\n'
            'This will also remove its assigned questions, '
            'join requests, and scores.',
            style: const TextStyle(color: Colors.grey, height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('DELETE'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return false;

    try {
      final firestore = FirebaseFirestore.instance;

      final quizRef = firestore.collection('quiz_sessions').doc(quizCode);

      final subcollections = ['questions', 'join_requests', 'scores'];

      for (final collectionName in subcollections) {
        final snapshot = await quizRef.collection(collectionName).get();

        // Firestore batch limit safety
        for (int i = 0; i < snapshot.docs.length; i += 450) {
          final batch = firestore.batch();

          final end = (i + 450 < snapshot.docs.length)
              ? i + 450
              : snapshot.docs.length;

          for (int j = i; j < end; j++) {
            batch.delete(snapshot.docs[j].reference);
          }

          await batch.commit();
        }
      }

      await quizRef.delete();

      showMessage('Quiz $quizCode deleted successfully.');
      return true;
    } catch (e) {
      showMessage('Failed to delete quiz: $e', error: true);
      return false;
    }
  }

  // =========================================================
  // OPEN QUIZ DETAIL
  // =========================================================

  Future<void> openQuizDetail(
    QueryDocumentSnapshot<Map<String, dynamic>> quiz,
  ) async {
    await AdminNavPersistence.savePage('quiz_session_detail', detailQuizCode: quiz.id);

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            QuizSessionDetailScreen(quizCode: quiz.id, quizData: quiz.data()),
      ),
    );
    if (mounted) {
      AdminNavPersistence.savePage('quiz_sessions');
    }
  }

  // =========================================================
  // QUIZ CARD
  // =========================================================

  Widget quizCard(QueryDocumentSnapshot<Map<String, dynamic>> quiz) {
    final data = quiz.data();
    final String quizCode = quiz.id;
    final String title = textValue(data['title'], 'Untitled Quiz');
    final String status = textValue(data['status'], 'waiting');
    final bool published = data['published'] == true;

    final dynamic createdAt = data['createdAt'];
    String dateText = '';

    if (createdAt is Timestamp) {
      final date = createdAt.toDate();
      dateText = '${date.month}/${date.day}/${date.year}';
    }

    return Material(
      key: ValueKey('admin_quiz_card_${quiz.id}'),
      color: Colors.transparent,
      child: InkWell(
        onTap: () => openQuizDetail(quiz),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE7EAF2)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              Widget quizIcon() {
                return Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0E9FF),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.emoji_events_rounded,
                    color: primaryPurple,
                    size: 21,
                  ),
                );
              }

              Widget quizInfo() {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: textDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.qr_code_rounded,
                          size: 13,
                          color: primaryPurple,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            quizCode,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: primaryPurple,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        if (dateText.isNotEmpty) ...[
                          const SizedBox(width: 7),
                          const Text(
                            '•',
                            style: TextStyle(color: Color(0xFFB2B6C3)),
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              dateText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF7B8198),
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                );
              }

              final statusWidgets = Wrap(
                spacing: 7,
                runSpacing: 6,
                children: [
                  _statusChip(
                    published ? 'Published' : 'Unpublished',
                    published
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFF59E0B),
                  ),
                  _statusChip(
                    status.isEmpty ? 'Waiting' : status,
                    primaryPurple,
                  ),
                ],
              );

              final actions = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Delete',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 38,
                      minHeight: 38,
                    ),
                    onPressed: () => deleteQuiz(context, quizCode),
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: Color(0xFFEF4444),
                      size: 19,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF9AA1B2),
                    size: 21,
                  ),
                ],
              );

              // Keep the session information and status chips inside the
              // flexible middle area. This prevents the status chips from
              // pushing the delete/arrow actions outside the card on narrow
              // screens.
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  quizIcon(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        quizInfo(),
                        const SizedBox(height: 8),
                        statusWidgets,
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  actions,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _statusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  // =========================================================
  // BUILD
  // =========================================================

  Future<void> _saveAdminPage(String pageKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('technowiz_admin_last_page', pageKey);

    // Leaving the quiz detail screen should not restore an old quiz detail.
    if (pageKey != 'quiz_session_detail') {
      await prefs.remove('technowiz_admin_detail_quiz_code');
    }
  }

  void _navigateFromAdminSidebar(String destination) {
    // Preserve the existing saved-page key and clear stale detail restoration.
    unawaited(_saveAdminPage(destination));
    if (!mounted) return;

    // Do not navigate to another copy of the page already open.
    if (destination == 'quiz_sessions') return;

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
      case 'leaderboard':
        page = const AdminLeaderboardScreen();
        break;
      case 'reports':
        page = const AdminReportScreen();
        break;
      default:
        page = null;
    }

    if (page == null || !mounted) return;

    Navigator.of(context).pushReplacement(
      adminPageRoute(page),
    );
  }

  void _showProfileMenu(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    const lightPurple = Color(0xFFF0E9FF);
    const textGrey = Color(0xFF7B8198);
    const border = Color(0xFFE7EAF2);

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
                    color: lightPurple,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFD8CCF7),
                      width: 2,
                    ),
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
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: textDark,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  user?.email ?? 'No email available',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: textGrey),
                ),
                const SizedBox(height: 18),
                const Divider(color: border),
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
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      drawer: AdminSidebar(
        currentPage: 'quiz_sessions',
        onDestinationSelected: _navigateFromAdminSidebar,
        onProfileTap: () => _showProfileMenu(context),
      ),
      endDrawer: AdminSidebar(
        currentPage: 'quiz_sessions',
        onDestinationSelected: _navigateFromAdminSidebar,
        onProfileTap: () => _showProfileMenu(context),
      ),
      appBar: buildAdminStandardAppBar(
        context: context,
        badgeText: 'Quiz Sessions',
        subtitle: 'Manage and monitor all quiz sessions',
      ),
      body: SafeArea(
        top: false,
        child: AdminCircuitBackground(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('quiz_sessions')
              .orderBy('createdAt', descending: true)
              .snapshots()
              .distinct((prev, next) {
                if (prev.docs.length != next.docs.length) return false;
                for (int i = 0; i < prev.docs.length; i++) {
                  final pDoc = prev.docs[i];
                  final nDoc = next.docs[i];
                  if (pDoc.id != nDoc.id) return false;
                  final p = pDoc.data();
                  final n = nDoc.data();
                  if (p['title'] != n['title'] ||
                      p['status'] != n['status'] ||
                      p['published'] != n['published'] ||
                      p['createdAt'] != n['createdAt']) {
                    return false;
                  }
                }
                // Suppress timer/countdown gameplay ticks so session list stays steady
                return true;
              }),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: primaryPurple),
              );
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Error loading quiz sessions:\n\n${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              );
            }

            final allQuizzes = snapshot.data?.docs ?? [];
            final activeQuizzes = allQuizzes.where((quiz) {
              final status = textValue(
                quiz.data()['status'],
                'waiting',
              ).trim().toLowerCase();
              return status != 'finished';
            }).toList();

            int waitingCount = 0;
            int ongoingCount = 0;
            int publishedCount = 0;
            int unpublishedCount = 0;

            for (final quiz in activeQuizzes) {
              final data = quiz.data();
              final status =
                  textValue(data['status'], 'waiting').trim().toLowerCase();
              final isPublished = data['published'] == true;

              if (status == 'waiting') {
                waitingCount++;
              } else if (status == 'ongoing' ||
                  status == 'active' ||
                  status == 'in_progress') {
                ongoingCount++;
              }

              if (isPublished) {
                publishedCount++;
              } else {
                unpublishedCount++;
              }
            }

            final filteredQuizzes = activeQuizzes.where((quiz) {
              final data = quiz.data();
              final status = textValue(data['status'], 'waiting').toLowerCase();
              final published = data['published'] == true;
              final matchesStatus =
                  _sessionStatusFilter == 'All' ||
                  (_sessionStatusFilter == 'Published' && published) ||
                  (_sessionStatusFilter == 'Unpublished' && !published) ||
                  status == _sessionStatusFilter.toLowerCase();
              return matchesStatus;
            }).toList();

            return LayoutBuilder(
              builder: (context, constraints) {
                final isPhone = constraints.maxWidth < 600;
                final horizontal = constraints.maxWidth >= 1100
                    ? 34.0
                    : (isPhone ? 14.0 : 24.0);
                return ListView(
                  padding: EdgeInsets.fromLTRB(horizontal, 6, horizontal, 30),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            _buildStatCards(
                              isMobile: isPhone,
                              waitingCount: waitingCount,
                              ongoingCount: ongoingCount,
                              publishedCount: publishedCount,
                              unpublishedCount: unpublishedCount,
                            ),
                            const SizedBox(height: 16),
                            if (filteredQuizzes.isEmpty)
                              _emptyState()
                            else ...[
                              _buildAboveCardsActionRow(
                                context,
                                filteredQuizzes.length,
                              ),
                              ...filteredQuizzes.map((quiz) => quizCard(quiz)),
                            ],
                            const SizedBox(height: 24),
                            const Center(
                              child: Text(
                                'TechNoWiz • v1.0.0',
                                style: TextStyle(
                                  color: Color(0xFF9AA1B2),
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    ),
  );
  }

  Widget _buildAboveCardsActionRow(BuildContext context, int count) {
    final bool isPhone = MediaQuery.sizeOf(context).width < 500;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                _sessionStatusFilter == 'All'
                    ? 'Quiz Sessions'
                    : '$_sessionStatusFilter Sessions',
                style: const TextStyle(
                  color: textDark,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AdminThemeColors.pillBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AdminThemeColors.primary.withValues(alpha: 0.22),
                  ),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: AdminThemeColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          ElevatedButton.icon(
            onPressed: _openCreateQuiz,
            icon: const Icon(Icons.add_rounded, size: 17),
            label: Text(isPhone ? 'Create Event' : 'Create Quiz Event'),
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: primaryPurple,
              elevation: 1.5,
              shadowColor: primaryPurple.withValues(alpha: 0.35),
              padding: EdgeInsets.symmetric(
                horizontal: isPhone ? 12 : 16,
                vertical: 10,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openCreateQuiz() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'technowiz_admin_last_page',
      'create_quiz',
    );
    await prefs.remove('technowiz_admin_detail_quiz_code');

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreateQuizScreen()),
    );
  }

  Widget _emptyState() {
    final bool isFiltered = _sessionStatusFilter != 'All';
    final String title = isFiltered
        ? 'No ${_sessionStatusFilter.toUpperCase()} Sessions'
        : 'No Quiz Sessions Yet';
    final String subtitle = isFiltered
        ? 'There are currently no quiz sessions matching the "$_sessionStatusFilter" status.'
        : 'Get started by creating your first interactive quiz event for competitors and quiz masters.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AdminThemeColors.primary.withValues(alpha: 0.14),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AdminThemeColors.primary.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Command Center Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AdminThemeColors.pillBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AdminThemeColors.primary.withValues(alpha: 0.18),
              ),
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
                const SizedBox(width: 6),
                const Text(
                  'QUIZ COMMAND CENTER',
                  style: TextStyle(
                    color: AdminThemeColors.primary,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Layered glowing icon halo
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: AdminThemeColors.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    AdminThemeColors.primary,
                    AdminThemeColors.primaryDark,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AdminThemeColors.primary.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.emoji_events_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Title
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: textDark,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),

          // Subtitle
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 22),

          // Action Button
          if (isFiltered)
            OutlinedButton.icon(
              onPressed: () => setState(() => _sessionStatusFilter = 'All'),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Show All Sessions'),
              style: OutlinedButton.styleFrom(
                foregroundColor: primaryPurple,
                side: BorderSide(
                  color: primaryPurple.withValues(alpha: 0.35),
                  width: 1.2,
                ),
                backgroundColor: AdminThemeColors.pillBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: _openCreateQuiz,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Create Quiz Event'),
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: primaryPurple,
                elevation: 2,
                shadowColor: primaryPurple.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                textStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// QUIZ SESSION DETAIL SCREEN
// ============================================================================

class QuizSessionDetailScreen extends StatefulWidget {
  final String quizCode;
  final Map<String, dynamic> quizData;

  const QuizSessionDetailScreen({
    super.key,
    required this.quizCode,
    required this.quizData,
  });

  @override
  State<QuizSessionDetailScreen> createState() =>
      _QuizSessionDetailScreenState();
}

class _QuizSessionDetailScreenState extends State<QuizSessionDetailScreen> {
  static const Color primaryPurple = Color(0xFF7C3AED);

  // =========================================================
  // ADMIN PAGE PERSISTENCE
  // =========================================================
  static const String _lastAdminPageKey = 'technowiz_admin_last_page';
  static const String _adminDetailQuizCodeKey =
      'technowiz_admin_detail_quiz_code';

  Future<void> _rememberDetailPage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastAdminPageKey, 'quiz_session_detail');
    await prefs.setString(_adminDetailQuizCodeKey, widget.quizCode);
  }

  Future<void> _rememberQuizSessionsPage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastAdminPageKey, 'quiz_sessions');
    await prefs.remove(_adminDetailQuizCodeKey);
  }

  Future<void> _handleDetailBack() async {
    await _rememberQuizSessionsPage();
    if (!mounted) return;

    final navigator = Navigator.of(context);

    // A restored screen after browser refresh may be the first route,
    // so do not pop when there is no previous route in the Navigator.
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }

    // Safe fallback when this detail page is the root route.
    navigator.pushAndRemoveUntil<void>(
      adminPageRoute<void>(
        const ManageQuizSessionsScreen(),
      ),
      (route) => false,
    );
  }

  static const Color textDark = Color(0xFF29213D);
  static const Color textGrey = Color(0xFF7B8198);

  final TextEditingController questionSearchController =
      TextEditingController();

  String questionSearch = '';

  String selectedLevel = 'Level 1';

  // Inline Add Level editor. This intentionally avoids showDialog() so the
  // level editor cannot trigger the Flutter '_dependents.isEmpty' assertion.
  final TextEditingController addLevelController = TextEditingController();
  final TextEditingController levelTimerController = TextEditingController();
  final TextEditingController levelEliminateController =
      TextEditingController();
  final TextEditingController levelPointsController = TextEditingController();

  // Difficulty/description for each level.
  // Admin can type the difficulty directly (e.g. Easy, Medium, Hard).
  // This is saved inside levelSettings["Level X"].difficulty.
  String levelDifficulty = '';
  final TextEditingController levelDifficultyController = TextEditingController(
    text: 'Easy',
  );
  String levelQuestionType = 'Multiple Choice';

  bool isAddingLevel = false;
  String? editingLevelName;

  @override
  void initState() {
    super.initState();

    _rememberDetailPage();

    questionSearchController.addListener(() {
      setState(() {
        questionSearch = questionSearchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    questionSearchController.dispose();
    addLevelController.dispose();
    levelTimerController.dispose();
    levelEliminateController.dispose();
    levelPointsController.dispose();
    levelDifficultyController.dispose();
    super.dispose();
  }

  DocumentReference<Map<String, dynamic>> get quizRef {
    return FirebaseFirestore.instance
        .collection('quiz_sessions')
        .doc(widget.quizCode);
  }

  String questionText(Map<String, dynamic> data) {
    return (data['questionText'] ??
            data['question'] ??
            data['text'] ??
            'Untitled Question')
        .toString();
  }

  // Helper for searching/displaying questions in this screen.
  String getQuestionText(Map<String, dynamic> data) {
    return (data['questionText'] ??
            data['question'] ??
            data['text'] ??
            data['question_title'] ??
            'Untitled Question')
        .toString();
  }

  void _showTopNotification(String message, {bool error = false}) {
    if (!mounted) return;
    AdminNotification.show(context, message, isError: error);
  }

  // Keep existing calls throughout QuizSessionDetailScreen working, but show
  // their notifications at the top instead of using bottom SnackBars.
  void showMessage(String message, {bool error = false}) {
    _showTopNotification(message, error: error);
  }

  String levelText(Map<String, dynamic> data) {
    return (data['level'] ??
            data['difficultyLevel'] ??
            data['quizLevel'] ??
            'Uncategorized')
        .toString();
  }

  List<String> options(Map<String, dynamic> data) {
    if (data['options'] is List) {
      return (data['options'] as List).map((e) => e.toString()).toList();
    }

    final List<String> result = [];

    for (final key in ['optionA', 'optionB', 'optionC', 'optionD']) {
      if (data[key] != null) {
        result.add(data[key].toString());
      }
    }

    return result;
  }

  String correctAnswer(Map<String, dynamic> data) {
    return (data['correctAnswer'] ??
            data['answer'] ??
            data['correctOption'] ??
            '')
        .toString();
  }

  dynamic _firstRawValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value == null) continue;

      if (value is String && value.trim().isEmpty) continue;

      return value;
    }

    return null;
  }

  String _firstValue(Map<String, dynamic> data, List<String> keys) {
    final value = _firstRawValue(data, keys);
    if (value == null) return 'Not set';
    return value.toString().trim().isEmpty ? 'Not set' : value.toString();
  }

  String _formatQuizDate(dynamic value) {
    if (value == null) return 'Not set';

    DateTime? date;

    if (value is Timestamp) {
      date = value.toDate();
    } else if (value is DateTime) {
      date = value;
    }

    if (date == null) {
      return value.toString();
    }

    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatQuizTime(dynamic value) {
    if (value == null) return 'Not set';

    DateTime? date;

    if (value is Timestamp) {
      date = value.toDate();
    } else if (value is DateTime) {
      date = value;
    }

    if (date == null) {
      return value.toString();
    }

    final hour = date.hour;
    final minute = date.minute;

    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;

    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
  }





  // =========================================================
  // TOGGLE PUBLISHED
  // =========================================================

  Future<void> togglePublished(bool value) async {
    final action = value ? 'publish' : 'unpublish';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            value ? 'Publish Quiz?' : 'Unpublish Quiz?',
            style: const TextStyle(
              color: textDark,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            value
                ? 'Are you sure you want to publish this quiz?\n\n'
                      'Contestants will be able to access the published quiz.'
                : 'Are you sure you want to unpublish this quiz?\n\n'
                      'Contestants will no longer see this quiz as published.',
            style: const TextStyle(color: Colors.grey, height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: value ? Colors.green : Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: Text(value ? 'PUBLISH' : 'UNPUBLISH'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      if (value) {
        await quizRef.update({
          'published': true,
          'isPublished': true,
          'status': 'waiting',
          'isFinished': false,
          'isCompleted': false,
          'completed': false,
          'finished': false,
          'currentQuestion': 0,
          'preparedLevel': 1,
          'eventStatus': 'waiting',
          'readyCheckActive': false,
          'countdownActive': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await quizRef.update({
          'published': false,
          'isPublished': false,
          'isFinished': false,
          'isCompleted': false,
          'completed': false,
          'finished': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      if (!mounted) return;

      AdminNotification.success(
        context,
        value
            ? 'Quiz published successfully.'
            : 'Quiz unpublished successfully.',
      );
    } catch (e) {
      if (!mounted) return;

      AdminNotification.error(context, 'Failed to $action quiz: $e');
    }
  }

  // =========================================================
  // ADD QUESTIONS
  // =========================================================

  Future<void> openAddQuestions(String level) async {
    final result = await showDialog<Set<String>>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AddQuestionsDialog(quizCode: widget.quizCode, level: level);
      },
    );

    if (result == null) return;

    try {
      final firestore = FirebaseFirestore.instance;
      final questionsRef = quizRef.collection('questions');
      final quizSnapshot = await quizRef.get();
      final liveData = quizSnapshot.data() ?? widget.quizData;

      final Map<String, List<String>> levelQuestions = {};

      final rawLevels = liveData['levelQuestions'];
      if (rawLevels is Map) {
        rawLevels.forEach((key, value) {
          if (value is List) {
            levelQuestions[key.toString()] = value
                .map((e) => e.toString())
                .toSet()
                .toList();
          }
        });
      }

      // Keep existing assigned questions compatible with older sessions.
      if (levelQuestions.isEmpty) {
        final existing = await questionsRef.get();
        for (final doc in existing.docs) {
          final data = doc.data();
          final oldLevel = (data['sessionLevel'] ?? data['level'] ?? 'Level 1')
              .toString();
          final normalized = oldLevel.toLowerCase().startsWith('level ')
              ? oldLevel
              : 'Level $oldLevel';
          levelQuestions.putIfAbsent(normalized, () => []);
          levelQuestions[normalized]!.add(doc.id);
        }
      }

      // A question belongs to one quiz level. If it is selected for this
      // level, remove it from any other level first.
      for (final ids in levelQuestions.values) {
        ids.removeWhere((id) => result.contains(id));
      }

      levelQuestions[level] = result.toList();

      final allAssignedIds = <String>{
        for (final ids in levelQuestions.values) ...ids,
      };

      final existingSnapshot = await questionsRef.get();
      final batch = firestore.batch();

      // Remove questions that are no longer assigned to any level.
      for (final doc in existingSnapshot.docs) {
        if (!allAssignedIds.contains(doc.id)) {
          batch.delete(doc.reference);
        }
      }

      int nextOrder = 0;

      for (final currentLevel in levelQuestions.keys) {
        for (final questionId in levelQuestions[currentLevel] ?? <String>[]) {
          final questionDoc = await firestore
              .collection('questions')
              .doc(questionId)
              .get();

          if (!questionDoc.exists) continue;

          final data = questionDoc.data() ?? {};
          final target = questionsRef.doc(questionId);

          batch.set(target, {
            'questionId': questionId,
            'questionText':
                data['questionText'] ?? data['question'] ?? data['text'] ?? '',
            'question':
                data['question'] ?? data['questionText'] ?? data['text'] ?? '',

            // Preserve the question type chosen in Admin's Question Bank.
            // Without this field, QuizScreen may incorrectly infer the type
            // (for example, Enumeration may be displayed as Multiple Choice).
            'questionType':
                data['questionType'] ??
                data['type'] ??
                data['question_type'] ??
                '',

            'options':
                data['options'] ??
                [
                  if (data['optionA'] != null) data['optionA'],
                  if (data['optionB'] != null) data['optionB'],
                  if (data['optionC'] != null) data['optionC'],
                  if (data['optionD'] != null) data['optionD'],
                ],

            // Keep accepted answers and legacy answer fields too, especially
            // for Enumeration and Identification questions.
            'correctAnswers':
                data['correctAnswers'] ??
                (data['correctAnswer'] is List
                    ? data['correctAnswer']
                    : data['correctAnswer'] != null
                    ? [data['correctAnswer']]
                    : data['answer'] is List
                    ? data['answer']
                    : data['answer'] != null
                    ? [data['answer']]
                    : []),

            'correctAnswer':
                data['correctAnswer'] ??
                data['answer'] ??
                data['correctOption'] ??
                '',

            'answer': data['answer'] ?? data['correctAnswer'] ?? '',

            'level':
                data['level'] ??
                data['difficultyLevel'] ??
                data['quizLevel'] ??
                'Uncategorized',
            'sessionLevel': currentLevel,
            'order': nextOrder,
            'addedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          nextOrder++;
        }
      }

      batch.set(quizRef, {
        'levels': levelQuestions.keys.toList(),
        'levelQuestions': levelQuestions,
        'questionIds': allAssignedIds.toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();

      if (!mounted) return;

      AdminNotification.success(
        context,
        '${result.length} question(s) assigned to $level.',
      );
    } catch (e) {
      if (!mounted) return;

      AdminNotification.error(context, 'Failed to assign questions: $e');
    }
  }

  // =========================================================
  // ADD LEVEL
  // =========================================================

  void addLevel() {
    if (!mounted) return;

    setState(() {
      editingLevelName = null;
      isAddingLevel = true;
      addLevelController.clear();
      levelTimerController.clear();
      levelEliminateController.clear();
      levelPointsController.clear();
      levelDifficulty = '';
      levelDifficultyController.clear();
    });
  }

  Future<void> chooseLevelToEdit() async {
    try {
      final snapshot = await quizRef.get();
      if (!mounted) return;
      final data = snapshot.data() ?? <String, dynamic>{};
      final rawLevels = data['levels'];
      final levels = rawLevels is List
          ? rawLevels
                .map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .toList()
          : <String>[];
      if (levels.isEmpty) {
        showMessage('Please add a level first.', error: true);
        return;
      }
      final chosen = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Edit Level'),
          content: SizedBox(
            width: 340,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: levels.length,
              itemBuilder: (_, index) => ListTile(
                leading: const Icon(Icons.edit_outlined, color: primaryPurple),
                title: Text(levels[index]),
                onTap: () => Navigator.pop(dialogContext, levels[index]),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCEL'),
            ),
          ],
        ),
      );
      if (chosen != null && mounted) await editLevel(chosen);
    } catch (e) {
      showMessage('Failed to load levels: $e', error: true);
    }
  }

  Future<void> editLevel(String level) async {
    if (!mounted) return;

    final latestSnapshot = await quizRef.get();
    if (!mounted) return;
    final latestData = latestSnapshot.data() ?? widget.quizData;
    final rawSettings = (latestData['levelSettings'] is Map)
        ? Map<String, dynamic>.from(latestData['levelSettings'] as Map)
        : <String, dynamic>{};
    final rawLevel = rawSettings[level];
    final settings = rawLevel is Map
        ? Map<String, dynamic>.from(rawLevel)
        : <String, dynamic>{};
    final number = int.tryParse(level.replaceFirst(RegExp(r'^Level\s*'), ''));

    setState(() {
      editingLevelName = level;
      isAddingLevel = true;
      addLevelController.text = number?.toString() ?? '';
      levelTimerController.text = (settings['timerSeconds'] ?? '').toString();
      levelEliminateController.text = (settings['eliminateCount'] ?? '')
          .toString();
      levelPointsController.text = (settings['pointsPerCorrectAnswer'] ?? '1')
          .toString();
      levelDifficulty = (settings['difficulty'] ?? 'Easy').toString();
      levelDifficultyController.text = levelDifficulty;
      levelQuestionType = (settings['questionType'] ??
              settings['type'] ??
              'Multiple Choice')
          .toString();
    });
  }

  Future<void> confirmCancelLevel() async {
    final isEditing = editingLevelName != null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isEditing ? 'Cancel Level Editing?' : 'Cancel Add Level?'),
        content: Text(
          isEditing
              ? 'Discard the changes made to $editingLevelName?'
              : 'Discard the level information you entered?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('KEEP EDITING'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('DISCARD'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      cancelAddLevel();
    }
  }

  Future<void> confirmSaveLevel() async {
    final isEditing = editingLevelName != null;
    final levelLabel =
        editingLevelName ??
        'Level ${addLevelController.text.trim().isEmpty ? '?' : addLevelController.text.trim()}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isEditing ? 'Update Level Settings?' : 'Save New Level?'),
        content: Text(
          isEditing
              ? 'Save the updated settings for $levelLabel?'
              : 'Create $levelLabel with the settings you entered?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('REVIEW'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryPurple,
              foregroundColor: Colors.white,
            ),
            child: Text(isEditing ? 'UPDATE LEVEL' : 'SAVE LEVEL'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await saveLevel();
    }
  }

  void cancelAddLevel() {
    if (!mounted) return;

    setState(() {
      editingLevelName = null;
      isAddingLevel = false;
      addLevelController.clear();
      levelTimerController.clear();
      levelEliminateController.clear();
      levelPointsController.clear();
      levelDifficulty = '';
      levelDifficultyController.clear();
      levelQuestionType = 'Multiple Choice';
    });
  }

  Future<void> saveLevel() async {
    final number = int.tryParse(addLevelController.text.trim());
    final timerSeconds = int.tryParse(levelTimerController.text.trim());
    final eliminateCount = int.tryParse(levelEliminateController.text.trim());
    final pointsPerCorrectAnswer = int.tryParse(
      levelPointsController.text.trim().isEmpty
          ? '1'
          : levelPointsController.text.trim(),
    );

    if (number == null || number <= 0) {
      showMessage('Please enter a valid level number.', error: true);
      return;
    }

    if (timerSeconds == null || timerSeconds <= 0) {
      showMessage('Please enter a valid timer.', error: true);
      return;
    }

    if (eliminateCount == null || eliminateCount < 0) {
      showMessage('Please enter a valid elimination count.', error: true);
      return;
    }

    if (pointsPerCorrectAnswer == null || pointsPerCorrectAnswer <= 0) {
      showMessage('Please enter valid points per correct answer.', error: true);
      return;
    }

    final level = editingLevelName ?? 'Level $number';

    try {
      final snapshot = await quizRef.get();
      final data = snapshot.data() ?? {};
      final levels = <String>[];

      final rawLevels = data['levels'];
      if (rawLevels is List) {
        levels.addAll(rawLevels.map((e) => e.toString()));
      }

      if (!levels.contains(level)) {
        levels.add(level);
      }

      levels.sort((a, b) {
        final aNum = int.tryParse(a.replaceFirst(RegExp(r'^Level\s*'), ''));
        final bNum = int.tryParse(b.replaceFirst(RegExp(r'^Level\s*'), ''));

        if (aNum != null && bNum != null) {
          return aNum.compareTo(bNum);
        }
        if (aNum != null) return -1;
        if (bNum != null) return 1;

        return a.compareTo(b);
      });

      final Map<String, dynamic> levelQuestions = {};
      final rawMap = data['levelQuestions'];

      if (rawMap is Map) {
        rawMap.forEach((key, value) {
          levelQuestions[key.toString()] = value is List ? value : <String>[];
        });
      }

      levelQuestions.putIfAbsent(level, () => <String>[]);

      // Keep existing settings for other levels.
      final Map<String, dynamic> levelSettings = {};
      final rawSettings = data['levelSettings'];

      if (rawSettings is Map) {
        rawSettings.forEach((key, value) {
          if (value is Map) {
            levelSettings[key.toString()] = Map<String, dynamic>.from(value);
          }
        });
      }

      // Save the settings for this level.
      levelSettings[level] = {
        'timerSeconds': timerSeconds,
        'eliminateCount': eliminateCount,
        'pointsPerCorrectAnswer': pointsPerCorrectAnswer,
        'difficulty': levelDifficulty,
        'questionType': levelQuestionType,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await quizRef.set({
        'levels': levels,
        'levelQuestions': levelQuestions,
        'levelSettings': levelSettings,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      setState(() {
        selectedLevel = level;
        editingLevelName = null;
        isAddingLevel = false;
        addLevelController.clear();
        levelTimerController.clear();
        levelEliminateController.clear();
        levelPointsController.clear();
        levelDifficulty = '';
        levelDifficultyController.clear();
        levelQuestionType = 'Multiple Choice';
      });

      showMessage('$level saved successfully.');
    } catch (e) {
      showMessage('Failed to add level: $e', error: true);
    }
  }

  // =========================================================
  // REMOVE LEVEL
  // =========================================================

  Future<void> removeLevel(String level) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Remove Level?'),
          content: Text(
            'Are you sure you want to remove $level?\n\n'
            'Questions assigned to this level will also be removed from this quiz session.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('REMOVE'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      final firestore = FirebaseFirestore.instance;
      final target = level.trim().toLowerCase();

      // Use a Firestore transaction so the level cannot be restored from
      // an old snapshot while this delete is happening.
      final removedQuestionIds = <String>{};
      List<String> remainingLevels = [];

      await firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(quizRef);
        final data = snapshot.data() ?? <String, dynamic>{};

        final rawLevels = data['levels'];
        remainingLevels = [];

        if (rawLevels is List) {
          for (final value in rawLevels) {
            final valueString = value.toString().trim();
            if (valueString.isEmpty) continue;

            if (valueString.toLowerCase() == target) {
              continue;
            }

            if (!remainingLevels.contains(valueString)) {
              remainingLevels.add(valueString);
            }
          }
        }

        final remainingLevelQuestions = <String, List<String>>{};
        final rawMap = data['levelQuestions'];

        if (rawMap is Map) {
          rawMap.forEach((key, value) {
            final keyString = key.toString().trim();
            if (keyString.isEmpty) return;

            final ids = value is List
                ? value.map((e) => e.toString()).toSet().toList()
                : <String>[];

            if (keyString.toLowerCase() == target) {
              removedQuestionIds.addAll(ids);
              return;
            }

            remainingLevelQuestions[keyString] = ids;
          });
        }

        final remainingQuestionIds = <String>{
          for (final ids in remainingLevelQuestions.values) ...ids,
        };

        transaction.update(quizRef, {
          'levels': remainingLevels,
          'levelQuestions': remainingLevelQuestions,
          'questionIds': remainingQuestionIds.toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      // Remove the question documents belonging to the deleted level.
      // These are session copies only; the global question bank is untouched.
      final questionSnapshot = await quizRef.collection('questions').get();

      for (final doc in questionSnapshot.docs) {
        final questionData = doc.data();
        final sessionLevel = (questionData['sessionLevel'] ?? '')
            .toString()
            .trim()
            .toLowerCase();

        if (sessionLevel == target || removedQuestionIds.contains(doc.id)) {
          removedQuestionIds.add(doc.id);
        }
      }

      // Firestore batches have a 500-operation limit, so delete in chunks.
      final ids = removedQuestionIds.toList();
      for (int i = 0; i < ids.length; i += 450) {
        final end = (i + 450 < ids.length) ? i + 450 : ids.length;
        final batch = firestore.batch();

        for (int j = i; j < end; j++) {
          batch.delete(quizRef.collection('questions').doc(ids[j]));
        }

        if (end > i) {
          await batch.commit();
        }
      }

      // Final cleanup: remove any old/case-variant occurrence that may have
      // been stored by an older version of the screen.
      final latestSnapshot = await quizRef.get();
      final latestData = latestSnapshot.data() ?? <String, dynamic>{};
      final latestLevels = <String>[];
      final latestRawLevels = latestData['levels'];

      if (latestRawLevels is List) {
        for (final value in latestRawLevels) {
          final valueString = value.toString().trim();
          if (valueString.isEmpty) continue;
          if (valueString.toLowerCase() == target) continue;
          if (!latestLevels.contains(valueString)) {
            latestLevels.add(valueString);
          }
        }
      }

      final latestMap = <String, dynamic>{};
      final latestRawMap = latestData['levelQuestions'];

      if (latestRawMap is Map) {
        latestRawMap.forEach((key, value) {
          final keyString = key.toString().trim();
          if (keyString.isEmpty) return;
          if (keyString.toLowerCase() == target) return;

          latestMap[keyString] = value is List
              ? List<dynamic>.from(value)
              : <String>[];
        });
      }

      final latestQuestionIds = <String>{
        for (final value in latestMap.values)
          if (value is List) ...value.map((e) => e.toString()),
      };

      await quizRef.update({
        'levels': latestLevels,
        'levelQuestions': latestMap,
        'questionIds': latestQuestionIds.toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      setState(() {
        selectedLevel = latestLevels.isNotEmpty ? latestLevels.first : '';
      });

      showMessage('$level removed successfully.');
    } catch (e) {
      showMessage('Failed to remove level: $e', error: true);
    }
  }

  // =========================================================
  // REMOVE QUESTION
  // =========================================================

  Future<void> removeQuestion(String questionId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Remove Question?'),
          content: const Text(
            'This question will be removed from this '
            'quiz session but will remain in the global '
            'question bank.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('REMOVE'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      await quizRef.collection('questions').doc(questionId).delete();

      final quizSnapshot = await quizRef.get();
      final data = quizSnapshot.data() ?? {};
      final Map<String, List<String>> levelQuestions = {};
      final rawLevels = data['levelQuestions'];

      if (rawLevels is Map) {
        rawLevels.forEach((key, value) {
          if (value is List) {
            levelQuestions[key.toString()] = value
                .map((e) => e.toString())
                .where((id) => id != questionId)
                .toList();
          }
        });
      }

      final allAssignedIds = <String>{
        for (final ids in levelQuestions.values) ...ids,
      };

      await quizRef.set({
        'levelQuestions': levelQuestions,
        'questionIds': allAssignedIds.toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _reorderQuestions();

      if (!mounted) return;

      showMessage('Question removed from this quiz.');
    } catch (e) {
      if (!mounted) return;

      showMessage('Failed: $e', error: true);
    }
  }

  // =========================================================
  // REORDER QUESTIONS
  // =========================================================

  Future<void> _reorderQuestions() async {
    final snapshot = await quizRef
        .collection('questions')
        .orderBy('order')
        .get();

    final batch = FirebaseFirestore.instance.batch();

    for (int i = 0; i < snapshot.docs.length; i++) {
      batch.update(snapshot.docs[i].reference, {
        'order': i,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  // =========================================================
  // MOVE QUESTION
  // =========================================================

  Future<void> moveQuestion(
    String questionId,
    int oldIndex,
    int newIndex,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (newIndex < 0 || newIndex >= docs.length) {
      return;
    }

    final reordered = [...docs];

    final item = reordered.removeAt(oldIndex);

    reordered.insert(newIndex, item);

    final batch = FirebaseFirestore.instance.batch();

    for (int i = 0; i < reordered.length; i++) {
      batch.update(reordered[i].reference, {
        'order': i,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  // =========================================================
  // JOIN REQUEST ACTION
  // =========================================================

  Future<void> updateJoinRequest(String uid, String status) async {
    try {
      await quizRef.collection('join_requests').doc(uid).update({
        'status': status,
        'respondedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      _showTopNotification(
        status == 'approved' ? 'Contestant approved.' : 'Contestant declined.',
      );
    } catch (e) {
      if (!mounted) return;

      AdminNotification.error(context, 'Failed: $e');
    }
  }

  // Remove a contestant from this quiz event without deleting their account.
  // Delete all event-specific records so the Waiting Room can detect removal
  // immediately through its Firestore listeners.
  Future<void> removeJoinRequest(String uid) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch();

      batch.delete(quizRef.collection('join_requests').doc(uid));
      batch.delete(quizRef.collection('participants').doc(uid));
      batch.delete(quizRef.collection('scores').doc(uid));

      await batch.commit();

      if (!mounted) return;
      _showTopNotification('Contestant removed from this quiz event.');
    } catch (e) {
      if (!mounted) return;
      _showTopNotification('Failed to remove contestant: $e', error: true);
    }
  }

  // =========================================================
  // LEVEL HELPERS
  // =========================================================

  List<String> getLevels(Map<String, dynamic> data) {
    final result = <String>[];

    final rawLevels = data['levels'];
    if (rawLevels is List) {
      for (final value in rawLevels) {
        final level = value.toString().trim();
        if (level.isNotEmpty && !result.contains(level)) {
          result.add(level);
        }
      }
    }

    final rawMap = data['levelQuestions'];
    if (rawMap is Map) {
      for (final key in rawMap.keys) {
        final level = key.toString().trim();
        if (level.isNotEmpty && !result.contains(level)) {
          result.add(level);
        }
      }
    }

    // IMPORTANT: Do not recreate "Level 1" when all levels were removed.
    // An empty list means the quiz currently has no levels.
    result.sort((a, b) {
      final aNum = int.tryParse(a.replaceFirst(RegExp(r'^Level\s*'), ''));
      final bNum = int.tryParse(b.replaceFirst(RegExp(r'^Level\s*'), ''));
      if (aNum != null && bNum != null) return aNum.compareTo(bNum);
      if (aNum != null) return -1;
      if (bNum != null) return 1;
      return a.compareTo(b);
    });

    return result;
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminThemeColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: kAdminAppBarHeight,
        leading: IconButton(
          onPressed: _handleDetailBack,
          icon: const Icon(Icons.arrow_back_rounded, color: textDark),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'QUIZ EVENT',
              style: TextStyle(
                color: primaryPurple,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
            Text(
              liveTitle(widget.quizData),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: textDark,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
      body: AdminCircuitBackground(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: quizRef.snapshots().distinct((prev, next) {
          final p = prev.data();
          final n = next.data();
          if (p == null || n == null) return false;
          final pLevels = (p['levels'] is List) ? (p['levels'] as List).join(',') : '';
          final nLevels = (n['levels'] is List) ? (n['levels'] as List).join(',') : '';
          // Ignore runtime gameplay ticks (countdown, timers, current question)
          // to keep the admin quiz session screen completely steady and stable.
          return p['title'] == n['title'] &&
              p['description'] == n['description'] &&
              p['published'] == n['published'] &&
              p['status'] == n['status'] &&
              pLevels == nLevels;
        }),
        builder: (context, quizSnapshot) {
          final liveData = quizSnapshot.data?.data() ?? widget.quizData;
          final published = liveData['published'] == true;
          final liveStatus = (liveData['status'] ?? '').toString().toLowerCase().trim();
          final isWaiting = liveStatus == 'waiting' || liveStatus.isEmpty;
          final isFinished = !isWaiting &&
              (liveData['isFinished'] == true ||
                  liveData['isCompleted'] == true ||
                  liveStatus == 'finished' ||
                  liveStatus == 'completed');
          final levels = getLevels(liveData);
          final effectiveSelectedLevel = levels.isEmpty
              ? ''
              : (levels.contains(selectedLevel) ? selectedLevel : levels.first);

          final width = MediaQuery.sizeOf(context).width;
          final wide = width >= 900;
          final phone = width < 600;
          final smallPhone = width < 380;

          Widget publishedBadge() => Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: published
                  ? const Color(0xFFEAF8EF)
                  : const Color(0xFFFFF5DF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              published ? 'PUBLISHED' : 'DRAFT',
              style: TextStyle(
                color: published
                    ? const Color(0xFF16803A)
                    : const Color(0xFFB66A00),
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          );

          String levelDifficultyFor(String level) {
            final rawSettings = liveData['levelSettings'];

            if (rawSettings is Map) {
              final rawLevelSettings = rawSettings[level];

              if (rawLevelSettings is Map) {
                final value = rawLevelSettings['difficulty'];

                if (value != null && value.toString().trim().isNotEmpty) {
                  return value.toString().trim();
                }
              }
            }

            return 'Easy';
          }

          Color difficultyColor(String difficulty) {
            switch (difficulty.toLowerCase()) {
              case 'hard':
                return const Color(0xFFDC2626);
              case 'medium':
                return const Color(0xFFD97706);
              default:
                return const Color(0xFF16A34A);
            }
          }

          Widget levelChip(String level) {
            final selected = level == effectiveSelectedLevel;
            final difficulty = levelDifficultyFor(level);
            final difficultyColorValue = difficultyColor(difficulty);
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: () {
                    setState(() {
                      selectedLevel = level;
                      questionSearchController.clear();
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? primaryPurple : const Color(0xFFF7F5FA),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: selected
                            ? primaryPurple
                            : const Color(0xFFE7E1F2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (selected)
                          const Padding(
                            padding: EdgeInsets.only(right: 5),
                            child: Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 13,
                            ),
                          ),
                        Text(
                          level,
                          style: TextStyle(
                            color: selected ? Colors.white : textDark,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? Colors.white.withValues(alpha: 0.18)
                                : difficultyColorValue.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            difficulty.toUpperCase(),
                            style: TextStyle(
                              color: selected
                                  ? Colors.white
                                  : difficultyColorValue,
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove $level',
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: Color(0xFFEF4444),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 26,
                    minHeight: 26,
                  ),
                  onPressed: () => removeLevel(level),
                ),
              ],
            );
          }

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              wide ? 28 : 14,
              20,
              wide ? 28 : 14,
              40,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // QUIZ SUMMARY
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(
                        wide ? 22 : (smallPhone ? 12 : 16),
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE7E1F2)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.035),
                            blurRadius: 18,
                            offset: const Offset(0, 7),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 54,
                                height: 54,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF8B5CF6),
                                      Color(0xFF6D28D9),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                child: const Icon(
                                  Icons.emoji_events_rounded,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            liveTitle(liveData),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: textDark,
                                              fontSize: wide ? 21 : 18,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        publishedBadge(),
                                      ],
                                    ),
                                    const SizedBox(height: 5),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.qr_code_rounded,
                                          size: 14,
                                          color: primaryPurple,
                                        ),
                                        const SizedBox(width: 5),
                                        Flexible(
                                          child: Text(
                                            widget.quizCode,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: primaryPurple,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 1.2,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F6FC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFECE7F5),
                              ),
                            ),
                            child: Wrap(
                              spacing: wide ? 24 : 18,
                              runSpacing: 16,
                              children: [
                                _detailInfo(
                                  Icons.description_outlined,
                                  'DESCRIPTION',
                                  _firstValue(liveData, [
                                    'description',
                                    'details',
                                    'quizDescription',
                                  ]),
                                  wide ? 205 : 160,
                                ),
                                _detailInfo(
                                  Icons.calendar_today_outlined,
                                  'DATE',
                                  _formatQuizDate(
                                    _firstRawValue(liveData, [
                                      'date',
                                      'quizDate',
                                      'startDate',
                                      'scheduledDate',
                                    ]),
                                  ),
                                  150,
                                ),
                                _detailInfo(
                                  Icons.location_on_outlined,
                                  'VENUE',
                                  _firstValue(liveData, [
                                    'location',
                                    'venue',
                                    'where',
                                  ]),
                                  wide ? 205 : 160,
                                ),
                                _detailInfo(
                                  Icons.access_time_rounded,
                                  'START TIME',
                                  _formatQuizTime(
                                    _firstRawValue(liveData, [
                                      'time',
                                      'quizTime',
                                      'startTime',
                                      'scheduledTime',
                                    ]),
                                  ),
                                  125,
                                ),
                                _detailInfo(
                                  Icons.timer_outlined,
                                  'END TIME',
                                  _formatQuizTime(
                                    _firstRawValue(liveData, [
                                      'endTime',
                                      'quizEndTime',
                                      'finishTime',
                                      'scheduledEndTime',
                                    ]),
                                  ),
                                  125,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ACTIONS
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE7E1F2)),
                      ),
                      child: LayoutBuilder(
                        builder: (context, actionConstraints) {
                          final compact = actionConstraints.maxWidth < 390;
                          final buttonPadding = EdgeInsets.symmetric(
                            horizontal: compact ? 4 : 8,
                            vertical: 9,
                          );
                          final labelStyle = TextStyle(
                            fontSize: compact ? 9 : 10,
                            fontWeight: FontWeight.w700,
                          );

                          // Keep all three actions aligned in one row when
                          // there is enough room; stack safely on very narrow
                          // layouts instead of letting individual buttons wrap.
                          if (actionConstraints.maxWidth >= 340) {
                            return Row(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: OutlinedButton.icon(
                                    onPressed: () => openAddQuestions(
                                      effectiveSelectedLevel,
                                    ),
                                    icon: const Icon(
                                      Icons.add_rounded,
                                      size: 15,
                                    ),
                                    label: const FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text('ADD QUESTIONS'),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      padding: buttonPadding,
                                      textStyle: labelStyle,
                                      minimumSize: const Size(0, 38),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  flex: 3,
                                  child: FilledButton.icon(
                                    onPressed: (published && !isFinished)
                                        ? null
                                        : () => togglePublished(true),
                                    icon: const Icon(
                                      Icons.publish_rounded,
                                      size: 14,
                                    ),
                                    label: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(isFinished ? 'RE-PUBLISH' : 'PUBLISH'),
                                    ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF16A34A),
                                      padding: buttonPadding,
                                      textStyle: labelStyle,
                                      minimumSize: const Size(0, 38),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  flex: 4,
                                  child: OutlinedButton.icon(
                                    onPressed: published
                                        ? () => togglePublished(false)
                                        : null,
                                    icon: const Icon(
                                      Icons.visibility_off_outlined,
                                      size: 14,
                                    ),
                                    label: const FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text('UNPUBLISH'),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      padding: buttonPadding,
                                      textStyle: labelStyle,
                                      minimumSize: const Size(0, 38),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }

                          return Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () =>
                                    openAddQuestions(effectiveSelectedLevel),
                                icon: const Icon(Icons.add_rounded, size: 16),
                                label: const Text('ADD QUESTIONS'),
                                style: OutlinedButton.styleFrom(
                                  padding: buttonPadding,
                                  textStyle: labelStyle,
                                ),
                              ),
                              FilledButton.icon(
                                onPressed: (published && !isFinished)
                                    ? null
                                    : () => togglePublished(true),
                                icon: const Icon(
                                  Icons.publish_rounded,
                                  size: 15,
                                ),
                                label: Text(isFinished ? 'RE-PUBLISH' : 'PUBLISH'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF16A34A),
                                  padding: buttonPadding,
                                  textStyle: labelStyle,
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: published
                                    ? () => togglePublished(false)
                                    : null,
                                icon: const Icon(
                                  Icons.visibility_off_outlined,
                                  size: 15,
                                ),
                                label: const Text('UNPUBLISH'),
                                style: OutlinedButton.styleFrom(
                                  padding: buttonPadding,
                                  textStyle: labelStyle,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ASSIGNED QUESTIONS
                    phone
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Assigned Questions',
                                style: TextStyle(
                                  color: textDark,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Manage the questions included in this quiz event.',
                                style: TextStyle(color: textGrey, fontSize: 11),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: isAddingLevel
                                          ? null
                                          : addLevel,
                                      icon: const Icon(
                                        Icons.add_rounded,
                                        size: 17,
                                      ),
                                      label: const Text('ADD LEVEL'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: primaryPurple,
                                        side: const BorderSide(
                                          color: primaryPurple,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        textStyle: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: isAddingLevel
                                          ? null
                                          : chooseLevelToEdit,
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 17,
                                      ),
                                      label: const Text('EDIT LEVEL'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: primaryPurple,
                                        side: const BorderSide(
                                          color: primaryPurple,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        textStyle: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Assigned Questions',
                                      style: TextStyle(
                                        color: textDark,
                                        fontSize: 21,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Manage the questions included in this quiz event.',
                                      style: TextStyle(
                                        color: textGrey,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton.icon(
                                onPressed: isAddingLevel ? null : addLevel,
                                icon: const Icon(Icons.add_rounded, size: 17),
                                label: const Text('ADD LEVEL'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: primaryPurple,
                                  side: const BorderSide(color: primaryPurple),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: isAddingLevel
                                    ? null
                                    : chooseLevelToEdit,
                                icon: const Icon(Icons.edit_outlined, size: 17),
                                label: const Text('EDIT LEVEL'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: primaryPurple,
                                  side: const BorderSide(color: primaryPurple),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                    const SizedBox(height: 10),

                    if (isAddingLevel)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE7E1F2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.tune_rounded,
                                  color: primaryPurple,
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  editingLevelName == null
                                      ? 'Level Settings'
                                      : 'Edit $editingLevelName',
                                  style: TextStyle(
                                    color: textDark,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // LEVEL NUMBER
                            TextField(
                              controller: addLevelController,
                              autofocus: editingLevelName == null,
                              readOnly: editingLevelName != null,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: InputDecoration(
                                labelText: 'Level Number',
                                hintText: 'Example: 1',
                                prefixIcon: const Icon(
                                  Icons.layers_outlined,
                                  color: primaryPurple,
                                ),
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),

                            const SizedBox(height: 10),

                            // TIMER PER QUESTION
                            TextField(
                              controller: levelTimerController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: InputDecoration(
                                labelText: 'Time per Question (seconds)',
                                hintText: 'Enter time per question',
                                prefixIcon: const Icon(
                                  Icons.timer_outlined,
                                  color: primaryPurple,
                                ),
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),

                            const SizedBox(height: 10),

                            // CONTESTANT ELIMINATION
                            TextField(
                              controller: levelEliminateController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: InputDecoration(
                                labelText: 'Participants to Eliminate',
                                hintText: 'Enter number of participants',
                                prefixIcon: const Icon(
                                  Icons.person_remove_outlined,
                                  color: Colors.redAccent,
                                ),
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),

                            const SizedBox(height: 10),

                            // LEVEL DIFFICULTY / DESCRIPTION
                            TextField(
                              controller: levelDifficultyController,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: InputDecoration(
                                labelText: 'Level Difficulty',
                                hintText: 'Enter difficulty level',
                                prefixIcon: const Icon(
                                  Icons.signal_cellular_alt_rounded,
                                  color: primaryPurple,
                                ),
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onChanged: (value) {
                                levelDifficulty = value.trim();
                              },
                            ),

                            const SizedBox(height: 10),

                            // POINTS PER CORRECT ANSWER
                            TextField(
                              controller: levelPointsController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: InputDecoration(
                                labelText: 'Points per Correct Answer',
                                floatingLabelBehavior:
                                    FloatingLabelBehavior.auto,
                                prefixIcon: const Icon(
                                  Icons.stars_rounded,
                                  color: primaryPurple,
                                ),
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),

                            const SizedBox(height: 10),

                            // QUESTION TYPE
                            DropdownButtonFormField<String>(
                              initialValue: const [
                                'Multiple Choice',
                                'Identification',
                                'True/False',
                                'Enumeration',
                                'Fill in the Blank',
                                'Mixed',
                              ].contains(levelQuestionType)
                                  ? levelQuestionType
                                  : 'Multiple Choice',
                              decoration: InputDecoration(
                                labelText: 'Question Type',
                                prefixIcon: const Icon(
                                  Icons.account_tree_outlined,
                                  color: primaryPurple,
                                ),
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'Multiple Choice',
                                  child: Text('Multiple Choice'),
                                ),
                                DropdownMenuItem(
                                  value: 'Identification',
                                  child: Text('Identification'),
                                ),
                                DropdownMenuItem(
                                  value: 'True/False',
                                  child: Text('True / False'),
                                ),
                                DropdownMenuItem(
                                  value: 'Enumeration',
                                  child: Text('Enumeration'),
                                ),
                                DropdownMenuItem(
                                  value: 'Fill in the Blank',
                                  child: Text('Fill in the Blank'),
                                ),
                                DropdownMenuItem(
                                  value: 'Mixed',
                                  child: Text('Mixed / All'),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => levelQuestionType = val);
                                }
                              },
                            ),

                            const SizedBox(height: 12),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton(
                                  onPressed: confirmCancelLevel,
                                  child: const Text('CANCEL'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton.icon(
                                  onPressed: confirmSaveLevel,
                                  icon: const Icon(
                                    Icons.save_rounded,
                                    size: 17,
                                  ),
                                  label: Text(
                                    editingLevelName == null
                                        ? 'SAVE LEVEL'
                                        : 'UPDATE LEVEL',
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: primaryPurple,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                    if (levels.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: levels.map(levelChip).toList(),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE7E1F2)),
                        ),
                        child: const Column(
                          children: [
                            Icon(
                              Icons.layers_clear_outlined,
                              color: textGrey,
                              size: 34,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'No quiz levels',
                              style: TextStyle(
                                color: textDark,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Click Add Level to create one.',
                              style: TextStyle(color: textGrey, fontSize: 11),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 12),

                    if (levels.isNotEmpty)
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: quizRef
                            .collection('questions')
                            .orderBy('order')
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.all(30),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: primaryPurple,
                                ),
                              ),
                            );
                          }
                          if (snapshot.hasError) {
                            return _errorBox(snapshot.error.toString());
                          }

                          final allDocs = snapshot.data?.docs ?? [];
                          final docs = allDocs.where((doc) {
                            final data = doc.data();
                            final level = (data['sessionLevel'] ?? '')
                                .toString();
                            if (level != effectiveSelectedLevel) return false;
                            if (questionSearch.isEmpty) return true;
                            return getQuestionText(
                              data,
                            ).toLowerCase().contains(questionSearch);
                          }).toList();

                          if (docs.isEmpty) return _emptyQuestions();
                          return _buildQuestionList(docs);
                        },
                      ),

                    const SizedBox(height: 30),

                    // JOIN REQUESTS
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Contestant Join Requests',
                          style: TextStyle(
                            color: textDark,
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Review contestants who want to join this quiz event.',
                          style: TextStyle(color: textGrey, fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: JoinRequestsWidget(
                        quizRef: quizRef,
                        onUpdate: updateJoinRequest,
                        onRemove: removeJoinRequest,
                      ),
                    ),
                    const SizedBox(height: 30),
                    const Center(
                      child: Text(
                        'TechNoWiz • v1.0.0',
                        style: TextStyle(
                          color: Color(0xFF9AA1B2),
                          fontSize: 10,
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
  );
  }

  String liveTitle(Map<String, dynamic> data) {
    return (data['title'] ?? 'Quiz Session').toString();
  }

  Widget _detailInfo(IconData icon, String label, String value, double width) {
    return SizedBox(
      width: width,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 29,
            height: 29,
            decoration: BoxDecoration(
              color: const Color(0xFFF0E9FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: primaryPurple, size: 15),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: textGrey,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // GROUP QUESTIONS BY LEVEL
  // =========================================================

  Widget _buildQuestionList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return Column(
      children: docs.map((doc) => _assignedQuestionTile(doc)).toList(),
    );
  }

  // =========================================================
  // QUESTION TILE
  // =========================================================

  Widget _assignedQuestionTile(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();

    final String question =
        (data['questionText'] ??
                data['question'] ??
                data['text'] ??
                'Untitled Question')
            .toString();

    final String answer = _resolveQuestionAnswer(data);

    return Container(
      key: ValueKey('assigned_q_${doc.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFE7E1F2)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        question,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: textDark,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 13,
                            color: Color(0xFF16A34A),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Answer: $answer',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF15803D),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Question options',
                  onSelected: (value) {
                    if (value == 'remove') {
                      removeQuestion(doc.id);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'remove',
                      child: Row(
                        children: [
                          Icon(
                            Icons.remove_circle_outline,
                            color: Colors.red,
                            size: 19,
                          ),
                          SizedBox(width: 8),
                          Text('Remove'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyQuestions() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8DFFF)),
      ),
      child: Column(
        children: [
          const Icon(Icons.assignment_outlined, size: 50, color: primaryPurple),
          const SizedBox(height: 10),
          const Text(
            'No Questions Assigned',
            style: TextStyle(
              color: textDark,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Use "ADD QUESTIONS" above to '
            'choose questions for this level.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _errorBox(String error) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Text(error, style: const TextStyle(color: Colors.red)),
    );
  }
}

// ============================================================================
// ADD QUESTIONS DIALOG
// ============================================================================

// ============================================================================
// CREATE QUESTION DIALOG
// ============================================================================

class CreateQuestionDialog extends StatefulWidget {
  final String level;

  const CreateQuestionDialog({super.key, required this.level});

  @override
  State<CreateQuestionDialog> createState() => _CreateQuestionDialogState();
}

class _CreateQuestionDialogState extends State<CreateQuestionDialog> {
  static const Color primaryPurple = Color(0xFF7C3AED);
  static const Color textDark = Color(0xFF29213D);

  final TextEditingController questionController = TextEditingController();
  final TextEditingController optionAController = TextEditingController();
  final TextEditingController optionBController = TextEditingController();
  final TextEditingController optionCController = TextEditingController();
  final TextEditingController optionDController = TextEditingController();
  final TextEditingController answerController = TextEditingController();

  final List<TextEditingController> enumerationControllers = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];

  String questionType = 'multipleChoice';
  String correctAnswer = 'A';
  String trueFalseAnswer = 'True';
  bool saving = false;

  @override
  void dispose() {
    questionController.dispose();
    optionAController.dispose();
    optionBController.dispose();
    optionCController.dispose();
    optionDController.dispose();
    answerController.dispose();
    for (final controller in enumerationControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  String get typeLabel {
    switch (questionType) {
      case 'identification':
        return 'Identification';
      case 'fillBlank':
        return 'Fill in the Blank';
      case 'trueFalse':
        return 'True or False';
      default:
        return 'Multiple Choice';
    }
  }

  Future<void> createQuestion() async {
    final question = questionController.text.trim();

    if (question.isEmpty) {
      _showError('Please enter the question.');
      return;
    }

    final String savedType = questionType == 'fillBlank'
        ? 'Fill in the Blank'
        : (questionType == 'multipleChoice'
            ? 'Multiple Choice'
            : (questionType == 'identification'
                ? 'Identification'
                : (questionType == 'trueFalse'
                    ? 'True/False'
                    : questionType)));

    final Map<String, dynamic> data = {
      'questionText': question,
      'question': question,
      'text': question,
      'questionType': savedType,
      'type': savedType,
      'level': widget.level.replaceFirst(RegExp(r'^Level\\s*'), ''),
      'difficultyLevel': widget.level.replaceFirst(RegExp(r'^Level\\s*'), ''),
      'quizLevel': widget.level.replaceFirst(RegExp(r'^Level\\s*'), ''),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (questionType == 'multipleChoice' || questionType == 'fillBlank') {
      final a = optionAController.text.trim();
      final b = optionBController.text.trim();
      final c = optionCController.text.trim();
      final d = optionDController.text.trim();

      if (a.isEmpty || b.isEmpty || c.isEmpty || d.isEmpty) {
        _showError('Please complete all four choices.');
        return;
      }

      data.addAll({
        'options': [a, b, c, d],
        'optionA': a,
        'optionB': b,
        'optionC': c,
        'optionD': d,
        'correctAnswer': correctAnswer,
        'correctOption': correctAnswer,
        'answer': correctAnswer,
      });
    } else if (questionType == 'identification') {
      final answer = answerController.text.trim();

      if (answer.isEmpty) {
        _showError('Please enter the correct answer.');
        return;
      }

      data.addAll({
        'correctAnswer': answer,
        'answer': answer,
        'correctOption': answer,
      });
    } else if (questionType == 'enumeration') {
      final answers = enumerationControllers
          .map((controller) => controller.text.trim())
          .where((value) => value.isNotEmpty)
          .toList();

      if (answers.isEmpty) {
        _showError('Please enter at least one correct answer.');
        return;
      }

      data.addAll({
        'answers': answers,
        'correctAnswers': answers,
        'correctAnswer': answers.join(', '),
        'answer': answers.join(', '),
      });
    } else {
      data.addAll({
        'options': ['True', 'False'],
        'optionA': 'True',
        'optionB': 'False',
        'correctAnswer': trueFalseAnswer,
        'correctOption': trueFalseAnswer,
        'answer': trueFalseAnswer,
      });
    }

    setState(() => saving = true);

    try {
      final ref = await FirebaseFirestore.instance
          .collection('questions')
          .add(data);

      if (!mounted) return;
      Navigator.pop(context, ref.id);
    } catch (e) {
      if (!mounted) return;

      setState(() => saving = false);
      _showError('Failed to create question: $e');
    }
  }

  void _showError(String message) {
    AdminNotification.error(context, message);
  }

  InputDecoration inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFFAF9FE),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE8DFFF)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE8DFFF)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryPurple, width: 1.5),
      ),
    );
  }

  Widget _typeSelector() {
    return DropdownButtonFormField<String>(
      initialValue: questionType,
      decoration: inputDecoration('Select question type'),
      items: const [
        DropdownMenuItem(
          value: 'multipleChoice',
          child: Text('Multiple Choice'),
        ),
        DropdownMenuItem(
          value: 'identification',
          child: Text('Identification'),
        ),
        DropdownMenuItem(
          value: 'trueFalse',
          child: Text('True or False'),
        ),
        DropdownMenuItem(
          value: 'fillBlank',
          child: Text('Fill in the Blank'),
        ),
      ],
      onChanged: saving
          ? null
          : (value) {
              if (value != null) {
                setState(() => questionType = value);
              }
            },
    );
  }

  Widget _multipleChoiceFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Choices',
          style: TextStyle(color: textDark, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: optionAController,
          decoration: inputDecoration('Option A'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: optionBController,
          decoration: inputDecoration('Option B'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: optionCController,
          decoration: inputDecoration('Option C'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: optionDController,
          decoration: inputDecoration('Option D'),
        ),
        const SizedBox(height: 14),
        const Text(
          'Correct Answer',
          style: TextStyle(color: textDark, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 7),
        DropdownButtonFormField<String>(
          initialValue: correctAnswer,
          decoration: inputDecoration('Select correct answer'),
          items: const [
            DropdownMenuItem(value: 'A', child: Text('A')),
            DropdownMenuItem(value: 'B', child: Text('B')),
            DropdownMenuItem(value: 'C', child: Text('C')),
            DropdownMenuItem(value: 'D', child: Text('D')),
          ],
          onChanged: saving
              ? null
              : (value) {
                  if (value != null) {
                    setState(() => correctAnswer = value);
                  }
                },
        ),
      ],
    );
  }

  Widget _identificationFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Correct Answer',
          style: TextStyle(color: textDark, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: answerController,
          decoration: inputDecoration('Enter the correct answer...'),
        ),
      ],
    );
  }

  Widget _enumerationFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Correct Answers',
          style: TextStyle(color: textDark, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 5),
        const Text(
          'Add the answers in order. Empty fields will be ignored.',
          style: TextStyle(color: Colors.grey, fontSize: 11),
        ),
        const SizedBox(height: 8),
        ...List.generate(enumerationControllers.length, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              controller: enumerationControllers[index],
              decoration: inputDecoration('Answer ${index + 1}'),
            ),
          );
        }),
      ],
    );
  }

  Widget _trueFalseFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Correct Answer',
          style: TextStyle(color: textDark, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 7),
        DropdownButtonFormField<String>(
          initialValue: trueFalseAnswer,
          decoration: inputDecoration('Select correct answer'),
          items: const [
            DropdownMenuItem(value: 'True', child: Text('True')),
            DropdownMenuItem(value: 'False', child: Text('False')),
          ],
          onChanged: saving
              ? null
              : (value) {
                  if (value != null) {
                    setState(() => trueFalseAnswer = value);
                  }
                },
        ),
      ],
    );
  }

  Widget _typeFields() {
    switch (questionType) {
      case 'identification':
        return _identificationFields();
      case 'enumeration':
        return _enumerationFields();
      case 'trueFalse':
        return _trueFalseFields();
      case 'fillBlank':
      default:
        return _multipleChoiceFields();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Row(
        children: [
          const Icon(Icons.add_circle_rounded, color: primaryPurple),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Create $typeLabel Question',
              style: const TextStyle(
                color: textDark,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            onPressed: saving ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      content: SizedBox(
        width: _ResponsiveUI.dialogWidth(context, 620),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3E9FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.layers_rounded,
                      color: primaryPurple,
                      size: 19,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This question will be added to ${widget.level}',
                        style: const TextStyle(
                          color: textDark,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Question Type',
                style: TextStyle(color: textDark, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 7),
              _typeSelector(),
              const SizedBox(height: 14),
              const Text(
                'Question',
                style: TextStyle(color: textDark, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 7),
              TextField(
                controller: questionController,
                maxLines: 3,
                decoration: inputDecoration('Enter your question...'),
              ),
              const SizedBox(height: 14),
              _typeFields(),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        ElevatedButton.icon(
          onPressed: saving ? null : createQuestion,
          icon: saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_rounded),
          label: Text(saving ? 'CREATING...' : 'CREATE QUESTION'),
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryPurple,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }
}

class AddQuestionsDialog extends StatefulWidget {
  final String quizCode;
  final String level;

  const AddQuestionsDialog({
    super.key,
    required this.quizCode,
    required this.level,
  });

  @override
  State<AddQuestionsDialog> createState() => _AddQuestionsDialogState();
}

class _AddQuestionsDialogState extends State<AddQuestionsDialog> {
  static const Color primaryPurple = Color(0xFF7C3AED);
  static const Color textDark = Color(0xFF29213D);

  final TextEditingController searchController = TextEditingController();
  final ScrollController questionsScrollController = ScrollController();

  String search = '';
  String selectedType = 'all';

  final Set<String> selectedIds = {};
  final ValueNotifier<Set<String>> selectedIdsNotifier =
      ValueNotifier<Set<String>>(<String>{});

  // Questions already assigned to another level of the same quiz session.
  // These questions must not appear in this level's picker.
  final Set<String> assignedToOtherLevels = {};

  bool loadingExisting = true;

  @override
  void initState() {
    super.initState();

    _loadExisting();

    searchController.addListener(() {
      setState(() {
        search = searchController.text.trim().toLowerCase();
      });
    });
  }

  Future<void> _loadExisting() async {
    final session = await FirebaseFirestore.instance
        .collection('quiz_sessions')
        .doc(widget.quizCode)
        .get();

    if (!mounted) return;

    final data = session.data() ?? {};
    final raw = data['levelQuestions'];

    if (raw is Map) {
      final currentLevelKey = widget.level.trim().toLowerCase();

      final currentIds = <String>{};
      final otherLevelIds = <String>{};

      raw.forEach((key, value) {
        if (value is! List) return;

        final levelKey = key.toString().trim().toLowerCase();
        final ids = value.map((e) => e.toString()).toSet();

        if (levelKey == currentLevelKey) {
          currentIds.addAll(ids);
        } else {
          otherLevelIds.addAll(ids);
        }
      });

      if (!mounted) return;

      setState(() {
        selectedIds.addAll(currentIds);
        assignedToOtherLevels.addAll(otherLevelIds);
        loadingExisting = false;
      });

      return;
    }

    // Backward compatibility for older quiz sessions.
    final snapshot = await FirebaseFirestore.instance
        .collection('quiz_sessions')
        .doc(widget.quizCode)
        .collection('questions')
        .get();

    if (!mounted) return;

    final currentLevel = widget.level.trim().toLowerCase();

    setState(() {
      for (final doc in snapshot.docs) {
        final docData = doc.data();
        final docLevel =
            (docData['sessionLevel'] ?? docData['level'] ?? 'Level 1')
                .toString();
        final normalized = docLevel.toLowerCase().startsWith('level ')
            ? docLevel
            : 'Level $docLevel';

        if (normalized.trim().toLowerCase() == currentLevel) {
          selectedIds.add(doc.id);
        } else {
          assignedToOtherLevels.add(doc.id);
        }
      }

      loadingExisting = false;
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    questionsScrollController.dispose();
    selectedIdsNotifier.dispose();
    super.dispose();
  }

  String questionText(Map<String, dynamic> data) {
    return (data['questionText'] ??
            data['question'] ??
            data['text'] ??
            'Untitled Question')
        .toString();
  }

  String levelText(Map<String, dynamic> data) {
    return (data['level'] ??
            data['difficultyLevel'] ??
            data['quizLevel'] ??
            'Uncategorized')
        .toString();
  }

  String questionType(Map<String, dynamic> data) {
    final raw =
        (data['questionType'] ??
                data['type'] ??
                data['question_type'] ??
                'multipleChoice')
            .toString()
            .trim()
            .toLowerCase();

    if (raw == 'multiple choice' ||
        raw == 'multiple_choice' ||
        raw == 'multiplechoice') {
      return 'multipleChoice';
    }
    if (raw == 'true/false' ||
        raw == 'true false' ||
        raw == 'true_false' ||
        raw == 'true or false' ||
        raw == 'truefalse') {
      return 'trueFalse';
    }
    if (raw == 'fill in the blank' ||
        raw == 'fill-in-the-blank' ||
        raw == 'fill_in_the_blank' ||
        raw == 'fill in blank' ||
        raw == 'fillintheblank' ||
        raw == 'fillblank' ||
        raw == 'blank') {
      return 'fillBlank';
    }
    if (raw == 'identification') {
      return 'identification';
    }
    if (raw == 'enumerate' || raw == 'enumeration') return 'enumeration';
    return raw;
  }

  Widget _questionTypeChip(String value, String label, IconData icon) {
    final selected = selectedType == value;

    return FilterChip(
      selected: selected,
      showCheckmark: false,
      avatar: Icon(
        icon,
        size: 15,
        color: selected ? Colors.white : primaryPurple,
      ),
      label: Text(label),
      selectedColor: primaryPurple,
      backgroundColor: const Color(0xFFF8F5FF),
      side: BorderSide(
        color: selected ? primaryPurple : const Color(0xFFE4D7FF),
      ),
      labelStyle: TextStyle(
        color: selected ? Colors.white : textDark,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      onSelected: (_) {
        if (selectedType == value) return;

        final offset = questionsScrollController.hasClients
            ? questionsScrollController.offset
            : 0.0;

        setState(() {
          selectedType = value;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !questionsScrollController.hasClients) return;

          final max = questionsScrollController.position.maxScrollExtent;
          questionsScrollController.jumpTo(offset.clamp(0.0, max));
        });
      },
    );
  }

  @override
  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: LayoutBuilder(
        builder: (context, dialogConstraints) {
          final screenWidth = MediaQuery.of(context).size.width;
          final screenHeight = MediaQuery.of(context).size.height;
          final isMobile = screenWidth < 600;

          return SizedBox(
            width: isMobile ? screenWidth - 32 : 900,
            height: screenHeight * 0.88,
            child: Column(
              children: [
                // ===================================================
                // HEADER
                // ===================================================
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    isMobile ? 14 : 20,
                    isMobile ? 14 : 20,
                    isMobile ? 8 : 12,
                    isMobile ? 10 : 12,
                  ),
                  child: isMobile
                      ? Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF3E9FF),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.library_add_rounded,
                                    color: primaryPurple,
                                    size: 21,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Add Questions - ${widget.level}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: textDark,
                                          fontSize: 17,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      const Text(
                                        'Choose questions for this quiz session',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final createdId = await showDialog<String>(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (_) => CreateQuestionDialog(
                                      level: widget.level,
                                    ),
                                  );

                                  if (!mounted || createdId == null) return;

                                  selectedIds.add(createdId);
                                  selectedIdsNotifier.value = Set<String>.from(
                                    selectedIds,
                                  );

                                  searchController.clear();
                                },
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: const Text('CREATE QUESTION'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: primaryPurple,
                                  side: const BorderSide(color: primaryPurple),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3E9FF),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.library_add_rounded,
                                color: primaryPurple,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Add Questions - ${widget.level}',
                                    style: const TextStyle(
                                      color: textDark,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  const Text(
                                    'Choose questions for this quiz session',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final createdId = await showDialog<String>(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (_) =>
                                      CreateQuestionDialog(level: widget.level),
                                );

                                if (!mounted || createdId == null) return;

                                setState(() {
                                  selectedIds.add(createdId);
                                });

                                searchController.clear();
                              },
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('CREATE QUESTION'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: primaryPurple,
                                side: const BorderSide(color: primaryPurple),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                ),

                const Divider(height: 1),

                // ===================================================
                // SEARCH
                // ===================================================
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ScrollConfiguration(
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
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          ),
                          child: Row(
                            children: [
                              _questionTypeChip('all', 'All', Icons.apps_rounded),
                              const SizedBox(width: 7),
                              _questionTypeChip(
                                'multipleChoice',
                                'Multiple Choice',
                                Icons.radio_button_checked_rounded,
                              ),
                              const SizedBox(width: 7),
                              _questionTypeChip(
                                'identification',
                                'Identification',
                                Icons.badge_outlined,
                              ),
                              const SizedBox(width: 7),
                              _questionTypeChip(
                                'trueFalse',
                                'True / False',
                                Icons.check_circle_outline_rounded,
                              ),
                              const SizedBox(width: 7),
                              _questionTypeChip(
                                'fillBlank',
                                'Fill in the Blank',
                                Icons.edit_note_rounded,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: searchController,
                        decoration: InputDecoration(
                          hintText: 'Search questions...',
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: primaryPurple,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFFAF9FE),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ===================================================
                // ALL QUESTIONS
                // ===================================================
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('questions')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: primaryPurple,
                          ),
                        );
                      }

                      if (snapshot.hasError) {
                        return Center(child: Text('Error:\n${snapshot.error}'));
                      }

                      if (loadingExisting) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: primaryPurple,
                          ),
                        );
                      }

                      final docs = snapshot.data?.docs ?? [];

                      // Show available questions in one list.
                      // The question bank's own level/difficulty is not used
                      // to categorize the questions in this dialog.
                      final filtered = docs.where((doc) {
                        // A question already assigned to another level in this
                        // same quiz session must not be available here.
                        if (assignedToOtherLevels.contains(doc.id)) {
                          return false;
                        }

                        final data = doc.data();
                        final question = questionText(data).toLowerCase();

                        final matchesSearch =
                            search.isEmpty || question.contains(search);
                        final matchesType =
                            selectedType == 'all' ||
                            questionType(data) == selectedType;

                        return matchesSearch && matchesType;
                      }).toList();

                      if (filtered.isEmpty) {
                        return const Center(
                          child: Text(
                            'No questions found.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        );
                      }

                      return ListView.separated(
                        controller: questionsScrollController,
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final doc = filtered[index];
                          final data = doc.data();

                          return ValueListenableBuilder<Set<String>>(
                            valueListenable: selectedIdsNotifier,
                            builder: (context, selectedSet, child) {
                              final selected = selectedSet.contains(doc.id);

                              return Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: selected
                                        ? primaryPurple.withAlpha(100)
                                        : const Color(0xFFE8DFFF),
                                  ),
                                ),
                                child: CheckboxListTile(
                                  value: selected,
                                  activeColor: primaryPurple,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  onChanged: (value) {
                                    if (value == true) {
                                      selectedIds.add(doc.id);
                                    } else {
                                      selectedIds.remove(doc.id);
                                    }

                                    // Only the selected question and the count
                                    // are refreshed. The ListView itself is not
                                    // rebuilt, so the scroll position stays put.
                                    selectedIdsNotifier.value =
                                        Set<String>.from(selectedIds);
                                  },
                                  title: Text(
                                    questionText(data),
                                    style: const TextStyle(
                                      color: textDark,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.check_circle_rounded,
                                          size: 11,
                                          color: Color(0xFF16A34A),
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            'Answer: ${_resolveQuestionAnswer(data)}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFF15803D),
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                            ),
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
                      );
                    },
                  ),
                ),

                // ===================================================
                // BOTTOM ACTIONS
                // ===================================================
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFEDE8F5))),
                  ),
                  child: ValueListenableBuilder<Set<String>>(
                    valueListenable: selectedIdsNotifier,
                    builder: (context, selectedSet, child) {
                      return isMobile
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  '${selectedSet.length} selected',
                                  style: const TextStyle(
                                    color: textDark,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 9),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('CANCEL'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () {
                                          Navigator.pop(context, selectedIds);
                                        },
                                        icon: const Icon(
                                          Icons.check_rounded,
                                          size: 18,
                                        ),
                                        label: const Text('ADD SELECTED'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: primaryPurple,
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                Text(
                                  '${selectedSet.length} selected',
                                  style: const TextStyle(
                                    color: textDark,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Spacer(),
                                OutlinedButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('CANCEL'),
                                ),
                                const SizedBox(width: 10),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(context, selectedIds);
                                  },
                                  icon: const Icon(Icons.check_rounded),
                                  label: const Text('ADD SELECTED'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primaryPurple,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ============================================================================
// JOIN REQUESTS
// ============================================================================

class JoinRequestsWidget extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> quizRef;

  final Future<void> Function(String uid, String status) onUpdate;
  final Future<void> Function(String uid) onRemove;

  const JoinRequestsWidget({
    super.key,
    required this.quizRef,
    required this.onUpdate,
    required this.onRemove,
  });

  @override
  State<JoinRequestsWidget> createState() => _JoinRequestsWidgetState();
}

class _JoinRequestsWidgetState extends State<JoinRequestsWidget> {
  String selectedStatus = 'pending';
  final Map<String, Map<String, dynamic>> _userCache = {};

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.quizRef
          .collection('join_requests')
          .orderBy('requestedAt', descending: true)
          .snapshots()
          .distinct((prev, next) {
            if (prev.docs.length != next.docs.length) return false;
            for (int i = 0; i < prev.docs.length; i++) {
              final pDoc = prev.docs[i];
              final nDoc = next.docs[i];
              if (pDoc.id != nDoc.id) return false;
              final p = pDoc.data();
              final n = nDoc.data();
              if (p['status'] != n['status'] ||
                  p['name'] != n['name'] ||
                  p['displayName'] != n['displayName'] ||
                  p['teamName'] != n['teamName'] ||
                  p['email'] != n['email']) {
                return false;
              }
            }
            // Suppress contestant gameplay answer/readiness pings
            return true;
          }),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF7C3AED)),
          );
        }

        if (snapshot.hasError) {
          return Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Text(
              'Join request error:\n${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        final filtered = docs.where((doc) {
          final status = (doc.data()['status'] ?? 'pending')
              .toString()
              .toLowerCase();

          return status == selectedStatus;
        }).toList();

        final pendingCount = docs.where((doc) {
          return (doc.data()['status'] ?? 'pending').toString().toLowerCase() ==
              'pending';
        }).length;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE8DFFF)),
          ),
          child: Column(
            children: [
              // =================================================
              // FILTER
              // =================================================
              ScrollConfiguration(
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
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  child: Row(
                    children: [
                      _filterButton('pending', pendingCount),
                      const SizedBox(width: 8),
                      _filterButton('approved', 0),
                      const SizedBox(width: 8),
                      _filterButton('declined', 0),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 15),

              if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(25),
                  child: Column(
                    children: [
                      Icon(
                        Icons.people_outline_rounded,
                        size: 42,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'No requests here.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              else
                ...filtered.map((doc) => _requestCard(doc)),
            ],
          ),
        );
      },
    );
  }

  Widget _filterButton(String status, int count) {
    final bool selected = selectedStatus == status;

    return OutlinedButton(
      onPressed: () {
        setState(() {
          selectedStatus = status;
        });
      },
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? const Color(0xFFF3E9FF) : Colors.white,
        foregroundColor: selected
            ? const Color(0xFF7C3AED)
            : Colors.grey.shade700,
        side: BorderSide(
          color: selected ? const Color(0xFF7C3AED) : const Color(0xFFE8DFFF),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        '${status[0].toUpperCase()}'
        '${status.substring(1)}'
        '${status == 'pending' ? ' ($count)' : ''}',
      ),
    );
  }

  Future<void> _confirmJoinRequestAction({
    required String uid,
    required String name,
    required String status,
  }) async {
    final bool approving = status == 'approved';

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            approving ? 'Approve Contestant?' : 'Decline Contestant?',
          ),
          content: Text(
            approving
                ? 'Are you sure you want to approve $name to join this quiz?'
                : 'Are you sure you want to decline $name from joining this quiz?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: approving ? Colors.green : Colors.red,
                foregroundColor: Colors.white,
              ),
              child: Text(approving ? 'APPROVE' : 'DECLINE'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await widget.onUpdate(uid, status);
    }
  }

  Future<void> _confirmRemoveContestant({
    required String uid,
    required String name,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Contestant?'),
        content: Text(
          'Remove $name from this quiz event? This will remove the contestant '
          'from the Approved/Declined list for this event, but will not delete '
          'their account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('REMOVE'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.onRemove(uid);
    }
  }

  Widget _requestCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final docData = doc.data();
    final String uid = doc.id;

    final String rawTeam =
        (docData['teamName'] ?? docData['team'] ?? '').toString().trim();
    final String contestantType =
        (docData['contestantType'] ?? '').toString().trim().toLowerCase();
    final dynamic rawMembers = docData['teamMembers'] ?? docData['members'];

    if (rawTeam.isNotEmpty || rawMembers != null || contestantType == 'team') {
      return _buildCardUI(docData, uid);
    }

    if (_userCache.containsKey(uid)) {
      final merged = Map<String, dynamic>.from(docData)..addAll(_userCache[uid]!);
      return _buildCardUI(merged, uid);
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data?.data() != null) {
          final userData = snapshot.data!.data()!;
          _userCache[uid] = userData;
          final merged = Map<String, dynamic>.from(docData)..addAll(userData);
          return _buildCardUI(merged, uid);
        }
        return _buildCardUI(docData, uid);
      },
    );
  }

  Widget _buildCardUI(Map<String, dynamic> data, String uid) {
    final String rawTeam =
        (data['teamName'] ?? data['team'] ?? '').toString().trim();
    final String contestantType =
        (data['contestantType'] ?? '').toString().trim().toLowerCase();
    final bool isTeam = contestantType == 'team' || rawTeam.isNotEmpty;

    final String personalName = (data['name'] ??
            data['displayName'] ??
            data['username'] ??
            data['realName'] ??
            'Unknown Contestant')
        .toString()
        .trim();

    final String teamName =
        rawTeam.isNotEmpty ? rawTeam : (isTeam ? personalName : '');
    final String displayName =
        isTeam ? (teamName.isNotEmpty ? teamName : personalName) : personalName;

    final List<String> teamMembers = [];
    final rawMembers = data['teamMembers'] ?? data['members'];
    if (rawMembers is List) {
      for (final m in rawMembers) {
        final s = m is Map
            ? (m['name'] ?? '').toString().trim()
            : m.toString().trim();
        if (s.isNotEmpty && !teamMembers.contains(s)) teamMembers.add(s);
      }
    } else if (rawMembers is String && rawMembers.trim().isNotEmpty) {
      teamMembers.addAll(
        rawMembers.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty),
      );
    }

    final String status = (data['status'] ?? 'pending').toString();
    final bool pending = status.toLowerCase() == 'pending';

    return Container(
      key: ValueKey('join_req_$uid'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFAFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isTeam ? const Color(0xFFDDD6FE) : const Color(0xFFEDE5FF),
          width: isTeam ? 1.4 : 1.0,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 360;

          final actionWidgets = pending
              ? [
                  IconButton(
                    tooltip: 'Decline',
                    onPressed: () {
                      _confirmJoinRequestAction(
                        uid: uid,
                        name: displayName,
                        status: 'declined',
                      );
                    },
                    icon: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.red,
                        size: 20,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Approve',
                    onPressed: () {
                      _confirmJoinRequestAction(
                        uid: uid,
                        name: displayName,
                        status: 'approved',
                      );
                    },
                    icon: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.green,
                        size: 20,
                      ),
                    ),
                  ),
                ]
              : [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: status.toLowerCase() == 'approved'
                          ? Colors.green.shade50
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        color: status.toLowerCase() == 'approved'
                            ? Colors.green
                            : Colors.orange,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove contestant',
                    onPressed: () =>
                        _confirmRemoveContestant(uid: uid, name: displayName),
                    icon: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.person_remove_outlined,
                        color: Colors.red,
                        size: 19,
                      ),
                    ),
                  ),
                ];

          final avatar = Container(
            width: compact ? 42 : 45,
            height: compact ? 42 : 45,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isTeam
                    ? const [Color(0xFF8B5CF6), Color(0xFF6D28D9)]
                    : const [Color(0xFF9B5CFF), Color(0xFF6D28D9)],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isTeam ? Icons.groups_rounded : Icons.person,
              color: Colors.white,
              size: compact ? 22 : 24,
            ),
          );

          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF29213D),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (isTeam) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3E8FF),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFDDD6FE)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 9,
                            color: Color(0xFF7C3AED),
                          ),
                          SizedBox(width: 3),
                          Text(
                            'TEAM',
                            style: TextStyle(
                              color: Color(0xFF7C3AED),
                              fontSize: 8.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              if (isTeam && teamMembers.isNotEmpty) ...[
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBF8FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFEDE5FF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.people_outline_rounded,
                            size: 13,
                            color: Color(0xFF7C3AED),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Members (${teamMembers.length}):',
                            style: const TextStyle(
                              color: Color(0xFF7C3AED),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        teamMembers.join(' • '),
                        style: const TextStyle(
                          color: Color(0xFF4C1D95),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (isTeam &&
                  personalName.isNotEmpty &&
                  personalName != teamName) ...[
                const SizedBox(height: 3),
                Text(
                  'Account: $personalName',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          );

          return compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        avatar,
                        const SizedBox(width: 10),
                        Expanded(child: details),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: actionWidgets,
                    ),
                  ],
                )
              : Row(
                  children: [
                    avatar,
                    const SizedBox(width: 11),
                    Expanded(child: details),
                    ...actionWidgets,
                  ],
                );
        },
      ),
    );
  }
}
