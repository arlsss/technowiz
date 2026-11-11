import 'package:flutter/material.dart';
import 'profile_screen.dart';
import 'quizmaster_theme.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:firebase_auth/firebase_auth.dart';

import 'quiz_sessions_screen.dart';

import 'leaderboard_screen.dart';

import 'manage_participants_screen.dart';

import '../login_screen.dart';
import '../../navigation_persistence.dart';

class QuizMasterDashboard extends StatefulWidget {
  const QuizMasterDashboard({super.key});

  @override
  State<QuizMasterDashboard> createState() => _QuizMasterDashboardState();
}

class _QuizMasterDashboardState extends State<QuizMasterDashboard> {
  // ============================================================

  // COLORS

  // ============================================================

  static const Color primaryBlue = Color(0xFF168BEB);

  static const Color darkBlue = Color(0xFF07549A);

  static const Color lightBlue = Color(0xFFE5F4FF);

  static const Color borderColor = Color(0xFFD8EAF8);

  static const Color textMuted = Color(0xFF718096);

  int selectedMenu = 0;
  final Set<int> _hoveredMenuItems = <int>{};
  bool _navigationInProgress = false;

  @override
  void initState() {
    super.initState();
    _saveLastPage('dashboard');
  }

  // ============================================================

  // USER

  // ============================================================

  User? get currentUser => FirebaseAuth.instance.currentUser;

  String get userEmail {
    return currentUser?.email ?? "quizmaster@email.com";
  }

  String get userName {
    final email = currentUser?.email;

    if (email == null || email.isEmpty) {
      return "Quiz Master";
    }

    final name = email.split('@').first;

    if (name.isEmpty) {
      return "Quiz Master";
    }

    return name
        .split(RegExp(r'[._-]'))
        .map(
          (word) => word.isEmpty
              ? ''
              : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }

  // ============================================================

  // LOGOUT

  // ============================================================

  Future<void> _saveLastPage(String page, {String? resultMode}) async {
    await QuizMasterNavPersistence.savePage(page, resultMode: resultMode);
  }

  Future<void> _clearLastPage() async {
    await QuizMasterNavPersistence.clearAll();
  }

  Future<void> logout(BuildContext context) async {
    await _clearLastPage();
    await LoginScreen.clearSavedCredentials();
    await FirebaseAuth.instance.signOut();

    if (!context.mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const LoginScreen(clearCredentials: true),
      ),
      (route) => false,
    );
  }

  // ============================================================

  // NOTIFICATION STREAM

  // ============================================================

  Stream<QuerySnapshot> get notificationStream {
    return FirebaseFirestore.instance
        .collection('notifications')
        .where('type', isEqualTo: 'quiz_created')
        .snapshots();
  }

  // ============================================================

  // MARK NOTIFICATION READ

  // ============================================================

  Future<void> markNotificationAsRead(
    QueryDocumentSnapshot notification,
  ) async {
    try {
      final data = notification.data() as Map<String, dynamic>;

      if (data['isRead'] == true) return;

      await notification.reference.update({'isRead': true});
    } catch (e) {
      debugPrint("Notification error: $e");
    }
  }

  // ============================================================

  // CLEAR NOTIFICATIONS

  // ============================================================

  Future<void> clearAllNotifications(
    BuildContext context,

    List<QueryDocumentSnapshot> notifications,
  ) async {
    if (notifications.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,

      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            "Clear Notifications?",

            style: TextStyle(fontWeight: FontWeight.bold, color: darkBlue),
          ),

          content: const Text(
            "This will permanently remove all quiz notifications.",
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },

              child: const Text("CANCEL"),
            ),

            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },

              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,

                foregroundColor: Colors.white,
              ),

              child: const Text("CLEAR ALL"),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      final batch = FirebaseFirestore.instance.batch();

      for (final doc in notifications) {
        batch.delete(doc.reference);
      }

      await batch.commit();

      if (!context.mounted) return;

      showQuizMasterTopNotification(
        context,
        "All notifications cleared.",
        isSuccess: true,
      );
    } catch (e) {
      debugPrint("Clear notification error: $e");

      if (!context.mounted) return;

      showQuizMasterTopNotification(
        context,
        "Unable to clear notifications.",
        isError: true,
      );
    }
  }

  // ============================================================

  // PROFILE

  // ============================================================

  void showProfileMenu(BuildContext context) {
    showQuizMasterProfileSideSheet(context);
  }

  // ============================================================

  // NOTIFICATIONS

  // ============================================================

  void showNotifications(BuildContext context) {
    showGeneralDialog(
      context: context,

      barrierDismissible: true,

      barrierLabel: "Notifications",

      barrierColor: Colors.black54,

      transitionDuration: const Duration(milliseconds: 250),

      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final width = MediaQuery.of(dialogContext).size.width;

        final height = MediaQuery.of(dialogContext).size.height;

        final panelWidth = width < 600 ? width * .88 : 420.0;

        return Align(
          alignment: Alignment.topRight,

          child: Padding(
            padding: const EdgeInsets.only(top: 70, right: 16),

            child: Material(
              color: Colors.white,

              elevation: 18,

              borderRadius: BorderRadius.circular(18),

              clipBehavior: Clip.antiAlias,

              child: SizedBox(
                width: panelWidth,

                height: height < 700 ? height * .72 : 520,

                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 10, 14),

                      child: Row(
                        children: [
                          const Icon(
                            Icons.notifications_active,

                            color: primaryBlue,
                          ),

                          const SizedBox(width: 10),

                          const Expanded(
                            child: Text(
                              "Notifications",

                              style: TextStyle(
                                fontSize: 20,

                                fontWeight: FontWeight.bold,

                                color: darkBlue,
                              ),
                            ),
                          ),

                          StreamBuilder<QuerySnapshot>(
                            stream: notificationStream,

                            builder: (context, snapshot) {
                              final docs = snapshot.hasData
                                  ? snapshot.data!.docs
                                  : <QueryDocumentSnapshot>[];

                              if (docs.isEmpty) {
                                return const SizedBox.shrink();
                              }

                              return TextButton(
                                onPressed: () {
                                  clearAllNotifications(dialogContext, docs);
                                },

                                child: const Text(
                                  "Clear All",

                                  style: TextStyle(color: Colors.red),
                                ),
                              );
                            },
                          ),

                          IconButton(
                            onPressed: () {
                              Navigator.pop(dialogContext);
                            },

                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),

                    const Divider(height: 1),

                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: notificationStream,

                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(
                                color: primaryBlue,
                              ),
                            );
                          }

                          if (snapshot.hasError) {
                            return const Center(
                              child: Text("Unable to load notifications."),
                            );
                          }

                          if (!snapshot.hasData ||
                              snapshot.data!.docs.isEmpty) {
                            return const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,

                                children: [
                                  Icon(
                                    Icons.notifications_none,

                                    size: 60,

                                    color: Colors.black26,
                                  ),

                                  SizedBox(height: 10),

                                  Text(
                                    "No quiz notifications yet.",

                                    style: TextStyle(color: Colors.black54),
                                  ),
                                ],
                              ),
                            );
                          }

                          final notifications = snapshot.data!.docs.toList();

                          notifications.sort((a, b) {
                            final aData = a.data() as Map<String, dynamic>;

                            final bData = b.data() as Map<String, dynamic>;

                            final aTime = aData['createdAt'];

                            final bTime = bData['createdAt'];

                            if (aTime is Timestamp && bTime is Timestamp) {
                              return bTime.compareTo(aTime);
                            }

                            return 0;
                          });

                          return ListView.separated(
                            padding: const EdgeInsets.all(15),

                            itemCount: notifications.length,

                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),

                            itemBuilder: (context, index) {
                              final notification = notifications[index];

                              final data =
                                  notification.data() as Map<String, dynamic>;

                              final title =
                                  data['title']?.toString() ??
                                  "New Quiz Created";

                              final message =
                                  data['message']?.toString() ??
                                  "A new quiz session has been created.";

                              final quizCode =
                                  data['quizCode']?.toString() ?? "";

                              final isRead = data['isRead'] == true;

                              return InkWell(
                                onTap: () async {
                                  await markNotificationAsRead(notification);

                                  if (!dialogContext.mounted) {
                                    return;
                                  }

                                  Navigator.pop(dialogContext);

                                  openQuizSessions(context);
                                },

                                borderRadius: BorderRadius.circular(15),

                                child: Container(
                                  padding: const EdgeInsets.all(14),

                                  decoration: BoxDecoration(
                                    color: isRead ? Colors.white : lightBlue,

                                    borderRadius: BorderRadius.circular(15),

                                    border: Border.all(
                                      color: isRead ? borderColor : primaryBlue,
                                    ),
                                  ),

                                  child: Row(
                                    children: [
                                      Container(
                                        width: 42,

                                        height: 42,

                                        decoration: BoxDecoration(
                                          color: lightBlue,

                                          borderRadius: BorderRadius.circular(
                                            11,
                                          ),
                                        ),

                                        child: const Icon(
                                          Icons.quiz_rounded,

                                          color: primaryBlue,
                                        ),
                                      ),

                                      const SizedBox(width: 12),

                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,

                                          children: [
                                            Text(
                                              title,

                                              style: const TextStyle(
                                                color: primaryBlue,

                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),

                                            const SizedBox(height: 5),

                                            Text(
                                              message,

                                              maxLines: 2,

                                              overflow: TextOverflow.ellipsis,

                                              style: const TextStyle(
                                                color: darkBlue,

                                                fontSize: 12,
                                              ),
                                            ),

                                            if (quizCode.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 6,
                                                ),

                                                child: Text(
                                                  "Quiz Code: $quizCode",

                                                  style: const TextStyle(
                                                    color: primaryBlue,

                                                    fontWeight: FontWeight.bold,

                                                    fontSize: 9.5,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),

                                      if (!isRead)
                                        Container(
                                          width: 8,

                                          height: 8,

                                          decoration: const BoxDecoration(
                                            color: primaryBlue,

                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
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
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
              .animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),

          child: child,
        );
      },
    );
  }

  // ============================================================

  // NAVIGATION

  // ============================================================

  Future<void> handleMenuTap(int index) async {
    if (!mounted || _navigationInProgress) return;

    if (index == 4) {
      showQuizMasterProfileSideSheet(context);
      return;
    }

    setState(() {
      selectedMenu = index;
    });

    switch (index) {
      case 0:
        // Dashboard is already the current page. Save it without popping
        // the dashboard route, which could otherwise leave the screen.
        await _saveLastPage('dashboard');
        break;

      case 1:
        await _saveLastPage('quiz_sessions');
        if (!mounted) return;
        openQuizSessions(context);
        break;

      case 2:
        await _openLeaderboard(context);
        break;

      case 3:
        await _openManageParticipants(context);
        break;
    }
  }

  Future<void> _openLeaderboard(BuildContext context) async {
    if (_navigationInProgress) return;
    setState(() => _navigationInProgress = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('quiz_sessions')
          .orderBy('createdAt', descending: true)
          .get();

      String? quizCode;

      for (final doc in snapshot.docs) {
        final data = doc.data();

        final status = data['status']?.toString().trim().toLowerCase() ?? '';

        final isFinished = data['isFinished'] == true ||
            data['isCompleted'] == true ||
            data['completed'] == true ||
            data['finished'] == true ||
            status == 'finished' ||
            status == 'completed' ||
            status == 'closed' ||
            status == 'archived';

        if (isFinished) continue;

        final isPub = data['published'] == true ||
            data['isPublished'] == true ||
            data['is_published'] == true ||
            data['published'] == 1 ||
            data['isPublished'] == 1 ||
            data['published']?.toString().toLowerCase() == 'true' ||
            data['isPublished']?.toString().toLowerCase() == 'true' ||
            status == 'published';

        if (!isPub) continue;

        if (status == 'active' ||
            status == 'live' ||
            status == 'started' ||
            status == 'ongoing' ||
            status == 'waiting' ||
            status == 'countdown' ||
            status == 'level_pause' ||
            status == 'paused') {
          final code = data['quizCode']?.toString().trim() ?? '';

          if (code.isNotEmpty) {
            quizCode = code;

            break;
          }
        }
      }

      // If no active quiz, do NOT fall back to finished quizzes
      quizCode ??= '';

      if (!context.mounted) return;

      await _saveLastPage('leaderboard');
      if (!mounted || !context.mounted) return;

      await Navigator.push(
        context,
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => LeaderboardScreen(quizCode: quizCode!),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, animation, secondaryAnimation, child) =>
              child,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;

      showQuizMasterTopNotification(
        context,
        'Unable to open the leaderboard.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _navigationInProgress = false);
    }
  }

  Future<void> openQuizSessions(BuildContext context) async {
    if (!mounted || _navigationInProgress) return;
    setState(() => _navigationInProgress = true);
    await _saveLastPage('quiz_sessions');
    if (!mounted || !context.mounted) return;

    // Replace the current route to prevent duplicate Quiz Sessions pages.
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,

        reverseTransitionDuration: Duration.zero,

        pageBuilder: (context, animation, secondaryAnimation) =>
            const QuizSessionsScreen(),

        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            child,
      ),
    );
  }

  Future<void> _openManageParticipants(BuildContext context) async {
    if (_navigationInProgress) return;
    setState(() => _navigationInProgress = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('quiz_sessions')
          .get();

      const activeStatuses = <String>{
        'active',
        'live',
        'started',
        'ongoing',
        'waiting',
        'countdown',
        'level_pause',
        'paused',
        'in_progress',
        'inprogress',
        'published',
        'scheduled',
        'ready',
        'standby',
        'open',
        'pending',
      };

      String? activeQuizCode;

      final sortedDocs = snapshot.docs.toList()
        ..sort((a, b) {
          final aDate = _dateValue(a.data()['updatedAt'] ?? a.data()['createdAt']);
          final bDate = _dateValue(b.data()['updatedAt'] ?? b.data()['createdAt']);
          return bDate.compareTo(aDate);
        });

      for (final doc in sortedDocs) {
        final data = doc.data();
        final status = data['status']?.toString().trim().toLowerCase() ?? '';
        final isFinished = data['isFinished'] == true ||
            data['isCompleted'] == true ||
            data['completed'] == true ||
            data['finished'] == true ||
            status == 'finished' ||
            status == 'completed' ||
            status == 'closed' ||
            status == 'archived';

        if (isFinished) continue;

        final isPub = data['published'] == true ||
            data['isPublished'] == true ||
            data['is_published'] == true ||
            data['published'] == 1 ||
            data['isPublished'] == 1 ||
            data['published']?.toString().toLowerCase() == 'true' ||
            data['isPublished']?.toString().toLowerCase() == 'true' ||
            status == 'published';

        if (!isPub) continue;
        if (!activeStatuses.contains(status)) continue;

        final code = doc.id.trim();
        if (code.isNotEmpty) {
          activeQuizCode = code.toUpperCase();
          break;
        }
      }

      // If no active quiz, do NOT fall back to finished quizzes
      activeQuizCode ??= '';

      if (!context.mounted) return;

      await _saveLastPage('participants');
      if (!mounted || !context.mounted) return;

      await Navigator.push(
        context,
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) =>
              ManageParticipantsScreen(quizCode: activeQuizCode!),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, animation, secondaryAnimation, child) =>
              child,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;

      showQuizMasterTopNotification(
        context,
        'Unable to open participants: $e',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _navigationInProgress = false);
    }
  }

  void openResult(BuildContext context, String type) {
    _saveLastPage('result', resultMode: type);

    Navigator.push(
      context,

      MaterialPageRoute(builder: (_) => QuizSessionsScreen(resultMode: type)),
    );
  }

  // // BUILD

  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: QuizMasterCircuitBackground(
        child: _buildMainContent(),
      ),
      bottomNavigationBar: _buildBottomNavigation(),
    );
  }

  // ============================================================

  // BOTTOM NAVIGATION

  // ============================================================

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
          child: Row(
            children: items.map((item) {
              final selected = selectedMenu == item.index;
              final hovered = _hoveredMenuItems.contains(item.index);
              return Expanded(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) {
                    setState(() => _hoveredMenuItems.add(item.index));
                  },
                  onExit: (_) {
                    setState(() => _hoveredMenuItems.remove(item.index));
                  },
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => handleMenuTap(item.index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: selected || hovered ? lightBlue : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            item.icon,
                            size: 20,
                            color: selected || hovered
                                ? primaryBlue
                                : textMuted,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected || hovered
                                  ? primaryBlue
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
          ),
        ),
      ),
    );
  }

  // ============================================================

  // Sidebar removed: this dashboard now uses bottom navigation.

  // MAIN CONTENT

  // ============================================================

  Widget _buildMainContent() {
    return SafeArea(
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('quiz_sessions')
            .snapshots(),

        builder: (context, snapshot) {
          final docs = snapshot.hasData
              ? snapshot.data!.docs
              : <QueryDocumentSnapshot>[];

          int totalParticipants = 0;

          int liveQuizzes = 0;

          int totalQuestions = 0;

          // Count every quiz that has not been finished, regardless of
          // its creation date or whether createdAt is present.
          // The Firestore stream updates these totals in real time.
          int recentUnfinishedQuizzes = 0;

          const finishedStatuses = <String>{
            'finished',
            'finish',
            'completed',
            'complete',
            'ended',
            'end',
          };

          for (final doc in docs) {
            final data = doc.data() as Map<String, dynamic>;

            final isPublished = data['published'] == true ||
                data['isPublished'] == true ||
                data['is_published'] == true ||
                data['published'] == 1 ||
                data['isPublished'] == 1 ||
                data['published']?.toString().trim().toLowerCase() == 'true' ||
                data['isPublished']?.toString().trim().toLowerCase() == 'true' ||
                (data['status'] ?? '').toString().toLowerCase() == 'published';

            if (!isPublished) continue;

            final status = (data['status']?.toString() ?? '')
                .trim()
                .toLowerCase()
                .replaceAll('-', '_')
                .replaceAll(' ', '_');

            final isFinished = finishedStatuses.contains(status) ||
                data['isFinished'] == true ||
                data['isCompleted'] == true ||
                data['completed'] == true ||
                data['finished'] == true;

            if (!isFinished) {
              recentUnfinishedQuizzes++;

              totalParticipants +=
                  _toInt(data['participants']) ??
                  _toInt(data['participantCount']) ??
                  0;
            }

            if (status == 'active' ||
                status == 'live' ||
                status == 'started' ||
                status == 'ongoing' ||
                status == 'in_progress' ||
                status == 'inprogress') {
              liveQuizzes++;
            }

            totalQuestions +=
                _toInt(data['questions']) ?? _toInt(data['questionCount']) ?? 0;
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth > 1200
                  ? 1150.0
                  : double.infinity;

              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: constraints.maxWidth < 600 ? 16 : 28,

                  vertical: 20,
                ),

                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),

                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [
                        _buildTopBar(),

                        const SizedBox(height: 28),

                        _buildWelcome(),

                        const SizedBox(height: 20),

                        _buildStats(
                          totalQuizzes: recentUnfinishedQuizzes,

                          totalParticipants: totalParticipants,

                          liveQuizzes: liveQuizzes,

                          totalQuestions: totalQuestions,
                        ),

                        const SizedBox(height: 25),

                        _buildLiveLeaderboardCard(docs),

                        const SizedBox(height: 20),

                        _buildRecentQuizzes(docs),

                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ============================================================

  // TOP BAR

  // ============================================================

  Widget _buildTopBar() {
    return Row(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(
                width: 42,
                height: 42,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: lightBlue,
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  child: Icon(
                    Icons.school_rounded,
                    color: primaryBlue,
                    size: 25,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "TechNoWiz",
                      style: TextStyle(
                        color: darkBlue,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('quiz_sessions')
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const SizedBox.shrink();
                        }

                        const activeStatuses = <String>{
                          'active',
                          'live',
                          'started',
                          'ongoing',
                          'in_progress',
                          'inprogress',
                          'waiting',
                          'countdown',
                          'paused',
                          'level_pause',
                          'published',
                          'scheduled',
                          'ready',
                          'standby',
                          'open',
                          'pending',
                        };

                        QueryDocumentSnapshot? activeQuiz;
                        final sortedDocs = snapshot.data!.docs.toList()
                          ..sort((a, b) {
                            final aData = a.data() as Map<String, dynamic>;
                            final bData = b.data() as Map<String, dynamic>;
                            final aDate = _dateValue(aData['updatedAt'] ?? aData['createdAt']);
                            final bDate = _dateValue(bData['updatedAt'] ?? bData['createdAt']);
                            return bDate.compareTo(aDate);
                          });

                        for (final doc in sortedDocs) {
                          final data = doc.data() as Map<String, dynamic>;
                          final status = (data['status']?.toString() ?? '')
                              .trim()
                              .toLowerCase()
                              .replaceAll('-', '_')
                              .replaceAll(' ', '_');
                          final isPublished = data['published'] == true ||
                              data['isPublished'] == true ||
                              data['is_published'] == true ||
                              data['published']?.toString().toLowerCase() == 'true' ||
                              data['isPublished']?.toString().toLowerCase() == 'true' ||
                              status == 'published';
                          final isFinished = data['isFinished'] == true ||
                              data['isCompleted'] == true ||
                              data['completed'] == true ||
                              data['finished'] == true ||
                              status == 'finished' ||
                              status == 'completed' ||
                              status == 'closed' ||
                              status == 'archived';

                          if (isFinished || !isPublished) continue;
                          if (!activeStatuses.contains(status)) continue;

                          final candidateName =
                              (data['title'] ??
                                      data['quizTitle'] ??
                                      data['name'] ??
                                      '')
                                  .toString()
                                  .trim();
                          // Use only an actual title saved with the Admin-created event.
                          if (candidateName.isEmpty) continue;
                          activeQuiz = doc;
                          break;
                        }

                        if (activeQuiz == null) {
                          return const SizedBox.shrink();
                        }

                        final data = activeQuiz.data() as Map<String, dynamic>;
                        final quizName =
                            (data['title'] ??
                                    data['quizTitle'] ??
                                    data['name'] ??
                                    '')
                                .toString()
                                .trim();
                        final description =
                            (data['description'] ??
                                    data['quizDescription'] ??
                                    '')
                                .toString()
                                .trim();

                        return Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                quizName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: primaryBlue,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (description.isNotEmpty)
                                Text(
                                  description,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: textMuted,
                                    fontSize: 9,
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================

  // WELCOME

  // ============================================================

  Widget _buildWelcome() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E88E5), Color(0xFF0D47A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.25),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: primaryBlue.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const QuizMasterBadge(
                  label: 'TECHNOWIZ • COMMAND CENTER',
                  icon: Icons.terminal_rounded,
                  darkTheme: true,
                ),
                const SizedBox(height: 10),
                const Text(
                  "Welcome, Quiz Master! 👋",
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Here's what's happening with your quiz system.",
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFFEAF6FF),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          const Icon(
            Icons.settings_suggest_rounded,

            color: Colors.white,

            size: 29,
          ),

          const SizedBox(width: 7),

          const Icon(Icons.school_rounded, color: Colors.white, size: 32),
        ],
      ),
    );
  }

  // ============================================================

  // STATS

  // ============================================================

  Widget _buildStats({
    required int totalQuizzes,

    required int totalParticipants,

    required int liveQuizzes,

    required int totalQuestions,
  }) {
    final width = MediaQuery.of(context).size.width;

    final cards = [
      _StatData(
        title: "Total Quizzes",

        value: "$totalQuizzes",

        icon: Icons.quiz_outlined,

        percentage: "+12.3%",
      ),

      _StatData(
        title: "Total Participants",

        value: _formatNumber(totalParticipants),

        icon: Icons.people_outline,

        percentage: "+10.1%",
      ),
    ];

    final columns = 2;

    return GridView.builder(
      shrinkWrap: true,

      physics: const NeverScrollableScrollPhysics(),

      itemCount: cards.length,

      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,

        crossAxisSpacing: 12,

        mainAxisSpacing: 12,

        childAspectRatio: width < 600 ? 1.9 : 2.5,
      ),

      itemBuilder: (context, index) {
        return _statCard(cards[index]);
      },
    );
  }

  // ============================================================

  // STAT CARD

  // ============================================================

  Widget _statCard(_StatData stat) {
    final width = MediaQuery.of(context).size.width;

    final mobile = width < 600;

    return Container(
      padding: EdgeInsets.all(mobile ? 12 : 16),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(14),

        border: Border.all(color: borderColor),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),

            blurRadius: 8,

            offset: const Offset(0, 3),
          ),
        ],
      ),

      child: Row(
        children: [
          Container(
            width: mobile ? 32 : 36,

            height: mobile ? 32 : 36,

            decoration: BoxDecoration(
              color: lightBlue,

              borderRadius: BorderRadius.circular(11),
            ),

            child: Icon(stat.icon, color: primaryBlue, size: mobile ? 16 : 18),
          ),

          SizedBox(width: mobile ? 8 : 12),

          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  stat.title,

                  maxLines: 2,

                  overflow: TextOverflow.ellipsis,

                  style: TextStyle(
                    color: textMuted,

                    fontSize: mobile ? 8.5 : 10,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  stat.value,

                  style: TextStyle(
                    color: darkBlue,

                    fontSize: mobile ? 19 : 22,

                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // LIVE LEADERBOARD CARD
  // ============================================================

  Widget _buildLiveLeaderboardCard(List<QueryDocumentSnapshot> docs) {
    if (docs.isEmpty) return const SizedBox.shrink();

    const activeStatuses = <String>{
      'active',
      'ongoing',
      'running',
      'in_progress',
      'inprogress',
      'waiting',
      'countdown',
      'live',
      'started',
      'paused',
      'level_pause',
      'contest_review',
    };

    QueryDocumentSnapshot? targetDoc;
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final isPub = data['published'] == true ||
          data['isPublished'] == true ||
          data['is_published'] == true ||
          data['published'] == 1 ||
          data['isPublished'] == 1 ||
          data['published']?.toString().toLowerCase() == 'true' ||
          data['isPublished']?.toString().toLowerCase() == 'true' ||
          (data['status'] ?? '').toString().toLowerCase() == 'published';
      if (!isPub) continue;

      final st = (data['status']?.toString() ?? '')
          .trim()
          .toLowerCase()
          .replaceAll('-', '_')
          .replaceAll(' ', '_');
      if (activeStatuses.contains(st)) {
        targetDoc = doc;
        break;
      }
    }
    // Only show live card if there is an actual active quiz session
    if (targetDoc == null) return const SizedBox.shrink();

    final data = targetDoc.data() as Map<String, dynamic>;
    final quizCode = (data['quizCode'] ?? targetDoc.id).toString().trim();
    final quizTitle =
        (data['title'] ?? data['quizTitle'] ?? quizCode).toString();
    final status = (data['status'] ?? 'waiting').toString().toLowerCase();
    final isLive = status == 'active' ||
        status == 'ongoing' ||
        status == 'running' ||
        status == 'in_progress';

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('quiz_sessions')
          .doc(quizCode)
          .collection('scores')
          .snapshots(),
      builder: (context, scoreSnap) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('quiz_sessions')
              .doc(quizCode)
              .collection('join_requests')
              .snapshots(),
          builder: (context, joinSnap) {
            final scoreDocs = scoreSnap.data?.docs ?? [];
            final joinDocs = joinSnap.data?.docs ?? [];

            final Map<String, Map<String, dynamic>> contestantMap = {};
            for (final j in joinDocs) {
              final d = j.data();
              contestantMap[j.id] = {
                'id': j.id,
                'name': d['name'] ??
                    d['displayName'] ??
                    d['contestantName'] ??
                    'Contestant',
                'teamName': d['teamName'] ?? '',
                'score': 0,
              };
            }
            for (final s in scoreDocs) {
              final d = s.data();
              final rawScore = d['score'] ?? d['totalScore'] ?? 0;
              final numScore = rawScore is num
                  ? rawScore.toInt()
                  : (int.tryParse(rawScore.toString()) ?? 0);
              if (contestantMap.containsKey(s.id)) {
                contestantMap[s.id]!['score'] = numScore;
              } else {
                contestantMap[s.id] = {
                  'id': s.id,
                  'name': d['name'] ?? d['displayName'] ?? 'Contestant',
                  'teamName': d['teamName'] ?? '',
                  'score': numScore,
                };
              }
            }

            final list = contestantMap.values.toList()
              ..sort(
                (a, b) => (b['score'] as int).compareTo(a['score'] as int),
              );

            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F4C81), Color(0xFF1689E8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x331689E8),
                    blurRadius: 18,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.leaderboard_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Live Ranking & Leaderboard',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              quizTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
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
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white30),
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
                                    : Colors.amberAccent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isLive ? 'LIVE' : 'ACTIVE',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (list.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(
                        child: Text(
                          'Waiting for contestants to join and submit scores...',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    )
                  else ...[
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 12,
                      ),
                      child: Column(
                        children: [
                          for (int i = 0;
                              i < (list.length > 3 ? 3 : list.length);
                              i++) ...[
                            if (i > 0)
                              const Divider(color: Colors.white12, height: 12),
                            Row(
                              children: [
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: i == 0
                                        ? const Color(0xFFFFD700)
                                        : i == 1
                                            ? const Color(0xFFC0C0C0)
                                            : const Color(0xFFCD7F32),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${i + 1}',
                                      style: const TextStyle(
                                        color: Colors.black87,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    list[i]['name'].toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${list[i]['score']} pts',
                                    style: const TextStyle(
                                      color: Color(0xFF93C5FD),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0F4C81),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => _openLeaderboard(context),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                      label: const Text(
                        'Open Full Live Leaderboard',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ============================================================
  // RECENT QUIZZES
  // ============================================================

  Widget _buildRecentQuizzes(List<QueryDocumentSnapshot> docs) {
    final recentDocs = docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;

      final status =
          data['status']
              ?.toString()
              .trim()
              .toLowerCase()
              .replaceAll('-', '_')
              .replaceAll(' ', '_') ??
          '';

      final isFinished = {
        'finished',

        'finish',

        'completed',

        'complete',

        'ended',

        'end',
      }.contains(status);

      // Finished quizzes belong in Quiz History, not Recent Quizzes.
      // Keep unfinished quizzes visible regardless of creation date.
      if (isFinished) return false;

      return true;
    }).toList();

    return Container(
      width: double.infinity,

      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(15),

        border: Border.all(color: borderColor),
      ),

      child: Column(
        children: [
          const Row(
            children: [
              Text(
                "Recent Quizzes",
                style: TextStyle(
                  color: darkBlue,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          if (recentDocs.isEmpty)
            _emptyQuizState()
          else
            Column(
              children: [...recentDocs.take(5).map((doc) => _quizRow(doc))],
            ),
        ],
      ),
    );
  }

  // ============================================================

  // QUIZ ROW

  // ============================================================

  Widget _quizRow(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    final title =
        data['title']?.toString() ??
        data['quizTitle']?.toString() ??
        "Untitled Quiz";

    final status = data['status']?.toString() ?? "upcoming";

    final participants =
        _toInt(data['participants']) ?? _toInt(data['participantCount']) ?? 0;

    final createdAt = data['createdAt'];

    String dateText = "";

    if (createdAt is Timestamp) {
      final date = createdAt.toDate();

      dateText = "${_monthName(date.month)} ${date.day}, ${date.year}";
    }

    final normalized = status
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');

    String badgeText;

    if ({
      "finished",

      "finish",

      "completed",

      "complete",

      "ended",

      "end",
    }.contains(normalized)) {
      badgeText = "Finished";
    } else if ({
      "active",

      "live",

      "started",

      "ongoing",

      "in_progress",

      "inprogress",
    }.contains(normalized)) {
      badgeText = "Ongoing";
    } else if ({"waiting", "countdown"}.contains(normalized)) {
      badgeText = "Waiting";
    } else if ({
      "paused",

      "pause",

      "level_pause",

      "on_hold",
    }.contains(normalized)) {
      badgeText = "Paused";
    } else if (normalized == "draft") {
      badgeText = "Draft";
    } else {
      badgeText = "Upcoming";
    }

    return InkWell(
      onTap: () {
        openQuizSessions(context);
      },

      borderRadius: BorderRadius.circular(10),

      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),

        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: borderColor)),
        ),

        child: Row(
          children: [
            Container(
              width: 38,

              height: 38,

              decoration: BoxDecoration(
                color: normalized == "active" || normalized == "live"
                    ? const Color(0xFFE8F7EF)
                    : lightBlue,

                borderRadius: BorderRadius.circular(10),
              ),

              child: Icon(
                Icons.quiz_rounded,

                size: 18,

                color: normalized == "active" || normalized == "live"
                    ? Colors.green
                    : primaryBlue,
              ),
            ),

            const SizedBox(width: 11),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Text(
                    title,

                    maxLines: 1,

                    overflow: TextOverflow.ellipsis,

                    style: const TextStyle(
                      color: darkBlue,

                      fontSize: 12,

                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    dateText.isEmpty
                        ? "$participants participants"
                        : "$dateText • $participants participants",

                    style: const TextStyle(color: textMuted, fontSize: 9),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            _statusBadge(badgeText, normalized),
          ],
        ),
      ),
    );
  }

  // ============================================================

  // STATUS

  // ============================================================

  Widget _statusBadge(String text, String status) {
    Color bg = lightBlue;

    Color fg = primaryBlue;

    if ({
      "active",

      "live",

      "started",

      "ongoing",

      "in_progress",

      "inprogress",
    }.contains(status)) {
      bg = const Color(0xFFE8F7EF);

      fg = Colors.green.shade800;
    } else if ({
      "finished",

      "finish",

      "completed",

      "complete",

      "ended",

      "end",
    }.contains(status)) {
      bg = const Color(0xFFF0F1F4);

      fg = textMuted;
    } else if ({"paused", "pause", "level_pause", "on_hold"}.contains(status)) {
      bg = const Color(0xFFFFF3E0);

      fg = Colors.orange.shade800;
    } else if (status == "draft") {
      bg = const Color(0xFFFFF3E0);

      fg = Colors.orange.shade800;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),

      decoration: BoxDecoration(
        color: bg,

        borderRadius: BorderRadius.circular(7),
      ),

      child: Text(
        text,

        style: TextStyle(color: fg, fontSize: 9, fontWeight: FontWeight.bold),
      ),
    );
  }

  // ============================================================

  // EMPTY

  // ============================================================

  Widget _emptyQuizState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 35),

      child: Column(
        children: [
          Container(
            width: 60,

            height: 60,

            decoration: const BoxDecoration(
              color: lightBlue,

              shape: BoxShape.circle,
            ),

            child: const Icon(
              Icons.quiz_outlined,

              color: primaryBlue,

              size: 28,
            ),
          ),

          const SizedBox(height: 12),

          const Text(
            "No quizzes yet",

            style: TextStyle(color: darkBlue, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 4),

          const Text(
            "Your recent quizzes will appear here.",

            style: TextStyle(color: textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  // ============================================================

  // HELPERS

  // ============================================================

  DateTime _dateValue(dynamic val) {
    if (val is Timestamp) return val.toDate();
    if (val is DateTime) return val;
    if (val is String) {
      final parsed = DateTime.tryParse(val);
      if (parsed != null) return parsed;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  int? _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is double) {
      return value.toInt();
    }

    if (value is String) {
      return int.tryParse(value);
    }

    return null;
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return "${(number / 1000000).toStringAsFixed(1)}M";
    }

    if (number >= 1000) {
      return "${(number / 1000).toStringAsFixed(1)}K";
    }

    return number.toString();
  }

  String _monthName(int month) {
    const months = [
      "Jan",

      "Feb",

      "Mar",

      "Apr",

      "May",

      "Jun",

      "Jul",

      "Aug",

      "Sep",

      "Oct",

      "Nov",

      "Dec",
    ];

    if (month < 1 || month > 12) {
      return "";
    }

    return months[month - 1];
  }
}

// ============================================================
// STAT DATA
// ============================================================
class _StatData {
  final String title;
  final String value;
  final IconData icon;
  final String percentage;

  const _StatData({
    required this.title,
    required this.value,
    required this.icon,
    required this.percentage,
  });
}
