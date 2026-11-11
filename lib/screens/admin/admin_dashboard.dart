import 'dart:ui';
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:firebase_auth/firebase_auth.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'add_question_screen.dart';

import 'question_list_screen.dart';

import 'manage_users_screen.dart';

import 'admin_report_screen.dart';

import 'admin_leaderboard_screen.dart';

import 'manage_quiz_sessions_screen.dart';
import '../../navigation_persistence.dart';

import 'admin_sidebar.dart';
import 'admin_theme.dart';

import '../login_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key, this.restoreLastPage = false});

  /// Retained for backwards compatibility across existing navigation calls.
  final bool restoreLastPage;

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  // =========================================================

  // COLORS - UNIFIED LIGHT PURPLE THEME

  // =========================================================

  static const Color primaryPurple = AdminThemeColors.primary;

  static const Color lightPurple = AdminThemeColors.pillBg;

  static const Color backgroundColor = AdminThemeColors.background;

  static const Color surfaceColor = AdminThemeColors.surface;

  static const Color textDark = AdminThemeColors.textPrimary;

  static const Color textMuted = AdminThemeColors.textMuted;

  static const Color borderColor = AdminThemeColors.border;

  // =========================================================

  // NOTIFICATIONS

  // =========================================================

  static const List<String> adminNotificationTypes = [
    "new_user",

    "user_login",

    "quiz_ended",
  ];

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> notifications = [];

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  notificationSubscription;

  @override
  void initState() {
    super.initState();

    startNotificationListener();
    AdminNavPersistence.savePage('dashboard');
  }

  void startNotificationListener() {
    notificationSubscription = FirebaseFirestore.instance
        .collection("notifications")
        .where("type", whereIn: adminNotificationTypes)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;

            final docs = [...snapshot.docs];

            docs.sort((a, b) {
              final aTimestamp = a.data()["createdAt"];

              final bTimestamp = b.data()["createdAt"];

              if (aTimestamp is Timestamp && bTimestamp is Timestamp) {
                return bTimestamp.compareTo(aTimestamp);
              }

              if (aTimestamp is Timestamp) return -1;

              if (bTimestamp is Timestamp) return 1;

              return 0;
            });

            setState(() {
              notifications
                ..clear()
                ..addAll(docs);
            });
          },

          onError: (error) {
            debugPrint("Notification listener error: $error");
          },
        );
  }

  int get unreadNotificationCount {
    return notifications.where((doc) {
      return doc.data()["isRead"] != true;
    }).length;
  }

  Future<void> markAllNotificationsAsRead() async {
    final unreadNotifications = notifications.where((doc) {
      return doc.data()["isRead"] != true;
    }).toList();

    if (unreadNotifications.isEmpty) return;

    final firestore = FirebaseFirestore.instance;

    const int batchLimit = 400;

    try {
      for (int i = 0; i < unreadNotifications.length; i += batchLimit) {
        final end = (i + batchLimit < unreadNotifications.length)
            ? i + batchLimit
            : unreadNotifications.length;

        final batch = firestore.batch();

        for (int j = i; j < end; j++) {
          batch.update(unreadNotifications[j].reference, {"isRead": true});
        }

        await batch.commit();
      }
    } catch (e) {
      debugPrint("Error marking notifications as read: $e");
    }
  }

  Future<void> markNotificationAsRead(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    if (doc.data()["isRead"] == true) return;

    try {
      await doc.reference.update({"isRead": true});
    } catch (e) {
      debugPrint("Error marking notification as read: $e");
    }
  }

  Future<void> clearAllNotifications(BuildContext sheetContext) async {
    if (notifications.isEmpty) return;

    final bool? confirmed = await showDialog<bool>(
      context: sheetContext,

      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),

          title: const Text(
            "Clear All Notifications?",

            style: TextStyle(color: textDark, fontWeight: FontWeight.bold),
          ),

          content: Text(
            "This will permanently remove all "
            "${notifications.length} Admin notifications.",

            style: const TextStyle(color: textMuted, height: 1.4),
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },

              child: const Text(
                "Cancel",

                style: TextStyle(color: textMuted, fontWeight: FontWeight.w600),
              ),
            ),

            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },

              style: ElevatedButton.styleFrom(
                backgroundColor: primaryPurple,

                foregroundColor: Colors.white,

                elevation: 0,

                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              child: const Text(
                "Clear All",

                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      final firestore = FirebaseFirestore.instance;

      const int batchLimit = 400;

      for (int i = 0; i < notifications.length; i += batchLimit) {
        final end = (i + batchLimit < notifications.length)
            ? i + batchLimit
            : notifications.length;

        final batch = firestore.batch();

        for (int j = i; j < end; j++) {
          batch.delete(notifications[j].reference);
        }

        await batch.commit();
      }

      if (!mounted || !sheetContext.mounted) return;

      Navigator.pop(sheetContext);

      AdminNotification.success(
        context,
        "All Admin notifications have been cleared.",
      );
    } catch (e) {
      debugPrint("Error clearing notifications: $e");

      if (!sheetContext.mounted) return;

      AdminNotification.error(
        sheetContext,
        "Failed to clear notifications. Please try again.",
      );
    }
  }

  @override
  void dispose() {
    notificationSubscription?.cancel();

    super.dispose();
  }

  // =========================================================

  // NAVIGATION

  // =========================================================

  // =========================================================

  // NAVIGATION PERSISTENCE

  // =========================================================

  Future<void> _saveLastAdminPage(String page) async {
    await AdminNavPersistence.savePage(page);
  }

  Future<void> _clearLastAdminPage() async {
    await AdminNavPersistence.clear();
  }

  Future<void> logout(BuildContext context) async {
    await AdminNavPersistence.clear();
    await _clearLastAdminPage();
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

  void openPage(
    BuildContext context,
    Widget page,
    String pageKey,
  ) {
    unawaited(_saveLastAdminPage(pageKey));
    if (!context.mounted) return;

    debugPrint('TECHNOWIZ ADMIN NAVIGATING TO: $pageKey');
    Navigator.of(context).pushReplacement(adminPageRoute(page));
  }

  // =========================================================

  // NOTIFICATIONS DROPDOWN

  // =========================================================

  void showNotifications(BuildContext context) {
    markAllNotificationsAsRead();

    final mediaQuery = MediaQuery.of(context);

    final double panelWidth = mediaQuery.size.width < 430
        ? mediaQuery.size.width - 28
        : 380;

    showDialog(
      context: context,

      barrierDismissible: true,

      barrierColor: Colors.transparent,

      useSafeArea: false,

      builder: (popupContext) {
        return Stack(
          children: [
            Positioned(
              top: mediaQuery.padding.top + 72,

              right: 14,

              child: Material(
                color: Colors.transparent,

                child: Container(
                  width: panelWidth,

                  constraints: const BoxConstraints(maxHeight: 520),

                  decoration: BoxDecoration(
                    color: Colors.white,

                    borderRadius: BorderRadius.circular(24),

                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x26000000),

                        blurRadius: 24,

                        spreadRadius: 1,

                        offset: Offset(0, 10),
                      ),
                    ],
                  ),

                  clipBehavior: Clip.antiAlias,

                  child: Column(
                    mainAxisSize: MainAxisSize.min,

                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 20, 18, 16),

                        child: Row(
                          children: [
                            Container(
                              width: 48,

                              height: 48,

                              decoration: BoxDecoration(
                                color: lightPurple,

                                borderRadius: BorderRadius.circular(14),
                              ),

                              child: const Icon(
                                Icons.notifications_none_rounded,

                                color: primaryPurple,

                                size: 27,
                              ),
                            ),

                            const SizedBox(width: 14),

                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,

                                children: [
                                  const Text(
                                    "Notifications",

                                    style: TextStyle(
                                      fontSize: 22,

                                      fontWeight: FontWeight.bold,

                                      color: textDark,
                                    ),
                                  ),

                                  const SizedBox(height: 3),

                                  Text(
                                    notifications.isEmpty
                                        ? "You're all caught up"
                                        : "${notifications.length} notification"
                                              "${notifications.length == 1 ? '' : 's'}",

                                    style: const TextStyle(
                                      fontSize: 12,

                                      color: textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            if (notifications.isNotEmpty)
                              TextButton(
                                onPressed: () {
                                  clearAllNotifications(popupContext);
                                },

                                child: const Text(
                                  "Clear All",

                                  style: TextStyle(
                                    color: primaryPurple,

                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      const Divider(height: 1, color: borderColor),

                      Flexible(
                        child: notifications.isEmpty
                            ? _emptyNotificationState()
                            : ListView.builder(
                                shrinkWrap: true,

                                padding: const EdgeInsets.all(16),

                                itemCount: notifications.length,

                                itemBuilder: (context, index) {
                                  final doc = notifications[index];

                                  final data = doc.data();

                                  final String type = (data["type"] ?? "")
                                      .toString();

                                  final String title =
                                      (data["title"] ?? "Notification")
                                          .toString();

                                  final String message =
                                      (data["message"] ??
                                              data["description"] ??
                                              "")
                                          .toString();

                                  final bool isRead = data["isRead"] == true;

                                  final Timestamp? timestamp =
                                      data["createdAt"] is Timestamp
                                      ? data["createdAt"] as Timestamp
                                      : null;

                                  final DateTime time =
                                      timestamp?.toDate() ?? DateTime.now();

                                  return GestureDetector(
                                    onTap: () {
                                      markNotificationAsRead(doc);
                                    },

                                    child: notificationCard(
                                      icon: getNotificationIcon(type),

                                      title: title,

                                      message: message,

                                      time: formatNotificationTime(time),

                                      isNew: !isRead,
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _emptyNotificationState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            Container(
              width: 76,

              height: 76,

              decoration: BoxDecoration(
                color: lightPurple,

                borderRadius: BorderRadius.circular(20),
              ),

              child: const Icon(
                Icons.notifications_none_rounded,

                color: primaryPurple,

                size: 40,
              ),
            ),

            const SizedBox(height: 18),

            const Text(
              "No notifications yet",

              style: TextStyle(
                fontSize: 18,

                fontWeight: FontWeight.bold,

                color: textDark,
              ),
            ),

            const SizedBox(height: 7),

            const Text(
              "New registrations, logins,\n"
              "and ended quizzes will appear here.",

              textAlign: TextAlign.center,

              style: TextStyle(color: textMuted, fontSize: 13, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }

  IconData getNotificationIcon(String type) {
    switch (type) {
      case "new_user":
        return Icons.person_add_alt_1_rounded;

      case "user_login":
        return Icons.login_rounded;

      case "quiz_ended":
        return Icons.emoji_events_rounded;

      default:
        return Icons.notifications_rounded;
    }
  }

  Widget notificationCard({
    required IconData icon,

    required String title,

    required String message,

    required String time,

    required bool isNew,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),

      padding: const EdgeInsets.all(14),

      decoration: BoxDecoration(
        color: isNew ? const Color(0xFFF4F0FF) : const Color(0xFFFBFCFC),

        borderRadius: BorderRadius.circular(16),

        border: Border.all(
          color: isNew ? const Color(0xFFD8CCF7) : borderColor,
        ),
      ),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Container(
            width: 46,

            height: 46,

            decoration: BoxDecoration(
              color: lightPurple,

              borderRadius: BorderRadius.circular(13),
            ),

            child: Icon(icon, color: primaryPurple, size: 23),
          ),

          const SizedBox(width: 13),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  title,

                  maxLines: 1,

                  overflow: TextOverflow.ellipsis,

                  style: TextStyle(
                    fontSize: 14,

                    fontWeight: isNew ? FontWeight.bold : FontWeight.w600,

                    color: textDark,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  message,

                  maxLines: 3,

                  overflow: TextOverflow.ellipsis,

                  style: const TextStyle(
                    fontSize: 12.5,

                    color: textMuted,

                    height: 1.35,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  time,

                  style: const TextStyle(
                    fontSize: 11,

                    color: primaryPurple,

                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          if (isNew)
            Container(
              width: 8,

              height: 8,

              margin: const EdgeInsets.only(top: 5, left: 8),

              decoration: const BoxDecoration(
                shape: BoxShape.circle,

                color: primaryPurple,
              ),
            ),
        ],
      ),
    );
  }

  String formatNotificationTime(DateTime time) {
    final Duration difference = DateTime.now().difference(time);

    if (difference.isNegative || difference.inSeconds < 10) {
      return "Just now";
    }

    if (difference.inMinutes < 1) {
      return "${difference.inSeconds}s ago";
    }

    if (difference.inHours < 1) {
      return "${difference.inMinutes}m ago";
    }

    if (difference.inDays < 1) {
      return "${difference.inHours}h ago";
    }

    if (difference.inDays < 7) {
      return "${difference.inDays}d ago";
    }

    return "${time.day}/${time.month}/${time.year}";
  }

  // =========================================================

  // PROFILE

  // =========================================================

  void showProfileMenu(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;

    showModalBottomSheet(
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
                  width: 76,

                  height: 76,

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

                    size: 40,
                  ),
                ),

                const SizedBox(height: 14),

                const Text(
                  "Admin",

                  style: TextStyle(
                    fontSize: 21,

                    fontWeight: FontWeight.bold,

                    color: textDark,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  user?.email ?? "admin@example.com",

                  textAlign: TextAlign.center,

                  style: const TextStyle(fontSize: 13, color: textMuted),
                ),

                const SizedBox(height: 20),

                const Divider(color: borderColor),

                const SizedBox(height: 10),

                SizedBox(
                  width: double.infinity,

                  height: 50,

                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);

                      logout(context);
                    },

                    icon: const Icon(Icons.logout_rounded, size: 20),

                    label: const Text(
                      "Logout",

                      style: TextStyle(
                        fontSize: 15,

                        fontWeight: FontWeight.bold,
                      ),
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

  // =========================================================

  // FIRESTORE COUNT

  // =========================================================

  Widget firestoreCount({
    required String collectionName,

    required IconData icon,

    required String title,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection(collectionName).snapshots(),

      builder: (context, snapshot) {
        String count = "0";

        if (snapshot.hasData) {
          count = snapshot.data!.docs.length.toString();
        }

        return overviewCard(icon: icon, number: count, title: title);
      },
    );
  }

  Widget overviewCard({
    required IconData icon,

    required String number,

    required String title,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(
        color: surfaceColor,

        borderRadius: BorderRadius.circular(18),

        border: Border.all(color: const Color(0xFFE9E1FA)),

        boxShadow: const [
          BoxShadow(
            color: Color(0x0D5424B8),

            blurRadius: 16,

            offset: Offset(0, 5),
          ),
        ],
      ),

      child: Row(
        children: [
          Container(
            width: 46,

            height: 46,

            decoration: BoxDecoration(
              color: lightPurple,

              borderRadius: BorderRadius.circular(12),
            ),

            child: Icon(icon, color: primaryPurple, size: 23),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              mainAxisAlignment: MainAxisAlignment.center,

              children: [
                Text(
                  number,

                  maxLines: 1,

                  overflow: TextOverflow.ellipsis,

                  style: const TextStyle(
                    fontSize: 24,

                    fontWeight: FontWeight.w800,

                    color: textDark,

                    height: 1,
                  ),
                ),

                const SizedBox(height: 7),

                Text(
                  title,

                  maxLines: 2,

                  overflow: TextOverflow.ellipsis,

                  style: const TextStyle(
                    fontSize: 11.5,

                    color: textMuted,

                    height: 1.2,
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

  // RECENT ACTIVITIES

  // =========================================================

  Widget recentActivities() {
    if (notifications.isEmpty) {
      return Container(
        width: double.infinity,

        padding: const EdgeInsets.all(22),

        decoration: BoxDecoration(
          color: Colors.white,

          borderRadius: BorderRadius.circular(18),

          border: Border.all(color: const Color(0xFFE9E1FA)),

          boxShadow: const [
            BoxShadow(
              color: Color(0x0A5424B8),

              blurRadius: 14,

              offset: Offset(0, 4),
            ),
          ],
        ),

        child: const Row(
          children: [
            Icon(Icons.history_rounded, color: primaryPurple, size: 24),

            SizedBox(width: 12),

            Expanded(
              child: Text(
                "No recent activities yet.",

                style: TextStyle(color: textMuted, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    final recent = notifications.take(5).toList();

    return Container(
      width: double.infinity,

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(18),

        border: Border.all(color: const Color(0xFFE9E1FA)),

        boxShadow: const [
          BoxShadow(
            color: Color(0x0A5424B8),

            blurRadius: 14,

            offset: Offset(0, 4),
          ),
        ],
      ),

      child: ListView.separated(
        shrinkWrap: true,

        physics: const NeverScrollableScrollPhysics(),

        itemCount: recent.length,

        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: borderColor),

        itemBuilder: (context, index) {
          final data = recent[index].data();

          final type = (data["type"] ?? "").toString();

          final title = (data["title"] ?? "Activity").toString();

          final message = (data["message"] ?? data["description"] ?? "")
              .toString();

          final timestamp = data["createdAt"];

          final time = timestamp is Timestamp
              ? formatNotificationTime(timestamp.toDate())
              : "Recently";

          return Padding(
            padding: const EdgeInsets.all(15),

            child: Row(
              children: [
                Container(
                  width: 42,

                  height: 42,

                  decoration: BoxDecoration(
                    color: lightPurple,

                    borderRadius: BorderRadius.circular(11),
                  ),

                  child: Icon(
                    getNotificationIcon(type),

                    color: primaryPurple,

                    size: 21,
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      Text(
                        title,

                        maxLines: 1,

                        overflow: TextOverflow.ellipsis,

                        style: const TextStyle(
                          color: textDark,

                          fontWeight: FontWeight.bold,

                          fontSize: 13,
                        ),
                      ),

                      const SizedBox(height: 3),

                      Text(
                        message.isEmpty ? "No description available." : message,

                        maxLines: 1,

                        overflow: TextOverflow.ellipsis,

                        style: const TextStyle(
                          color: textMuted,

                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 10),

                Text(
                  time,

                  style: const TextStyle(color: textMuted, fontSize: 10.5),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // =========================================================

  // SIDEBAR

  // =========================================================

  // Shared Admin sidebar UI is provided by AdminSidebar.

  // =========================================================

  // TOP BAR

  // =========================================================

  Widget topBar(BuildContext context, bool isMobile) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: borderColor, width: 1)),
      ),
      child: SafeArea(
        top: isMobile,
        bottom: false,
        child: SizedBox(
          height: isMobile ? 68 : 72,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 15 : 28),
            child: Row(
              children: [
                // Purple TechNoWiz Brand Icon Badge (Shield)
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AdminThemeColors.primary, AdminThemeColors.primaryDark],
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
                    size: 21,
                  ),
                ),
                const SizedBox(width: 10),

                // TechNoWiz Brand Name
                const Text(
                  'TechNoWiz',
                  style: TextStyle(
                    color: AdminThemeColors.primaryDark,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                  ),
                ),
                if (!isMobile) ...[
                  const SizedBox(width: 14),
                  Container(
                    height: 18,
                    width: 1,
                    color: AdminThemeColors.border,
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    "Admin Command Center",
                    style: TextStyle(
                      color: AdminThemeColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const Spacer(),
                Builder(
                  builder: (scaffoldContext) => IconButton(
                    tooltip: "Open navigation menu",
                    padding: EdgeInsets.zero,
                    icon: const Icon(
                      Icons.menu_rounded,
                      color: textDark,
                      size: 24,
                    ),
                    onPressed: () {
                      Scaffold.of(scaffoldContext).openEndDrawer();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================

  // DASHBOARD CONTENT

  // =========================================================

  Widget dashboardContent(BuildContext context, double width) {
    final bool isMobile = width < 650;
    final double horizontalPadding = width < 360
        ? 8
        : width < 650
        ? 12
        : width < 1000
        ? 20
        : 26;

    return SingleChildScrollView(
      padding: EdgeInsets.all(horizontalPadding),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1250),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Purple welcome banner, matching the supplied reference UI.
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(isMobile ? 18 : 24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AdminThemeColors.primaryDark, AdminThemeColors.primary],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AdminThemeColors.primary.withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.35),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.shield_rounded,
                                  color: Colors.white,
                                  size: 13,
                                ),
                                SizedBox(width: 5),
                                Text(
                                  "TECHNOWIZ COMMAND CENTER",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Text(
                            "Welcome, Admin! 👋",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            "Here's what's happening with your quiz system.",
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Technology/education illustration: brain + graduation cap.
                    // This replaces the question-mark head icon in the banner.
                    SizedBox(
                      width: isMobile ? 58 : 78,
                      height: isMobile ? 44 : 58,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Icon(
                              Icons.psychology_rounded,
                              color: Colors.white.withValues(alpha: 0.95),
                              size: isMobile ? 34 : 44,
                            ),
                          ),
                          Align(
                            alignment: Alignment.topRight,
                            child: Transform.rotate(
                              angle: -0.12,
                              child: Icon(
                                Icons.school_rounded,
                                color: Colors.white.withValues(alpha: 0.95),
                                size: isMobile ? 31 : 40,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Dashboard summary cards (navigation actions are already in the sidebar).
              GridView.count(
                crossAxisCount: width < 360 ? 1 : (width >= 1100 ? 4 : 2),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: width < 360
                    ? 2.8
                    : width >= 1100
                    ? 1.95
                    : width < 650
                    ? 2.05
                    : 2.3,
                children: [
                  _dashboardMetricCard(
                    icon: Icons.people_alt_rounded,
                    title: "Total Users",
                    collection: "users",
                    color: AdminThemeColors.primary,
                    background: AdminThemeColors.pillBg,
                  ),
                  _dashboardMetricCard(
                    icon: Icons.menu_book_rounded,
                    title: "Total Questions",
                    collection: "questions",
                    color: const Color(0xFF1683D8),
                    background: const Color(0xFFE5F3FF),
                  ),
                  _dashboardMetricCard(
                    icon: Icons.emoji_events_rounded,
                    title: "Total Quiz Sessions",
                    collection: "quiz_sessions",
                    onlyLastWeek: true,
                    color: const Color(0xFF10A86B),
                    background: const Color(0xFFE2F9ED),
                  ),
                  _dashboardMetricCard(
                    icon: Icons.play_circle_fill_rounded,
                    title: "Ongoing Quizzes",
                    collection: "quiz_sessions",
                    onlyOngoing: true,
                    color: const Color(0xFFD97706),
                    background: const Color(0xFFFFF0DD),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Recent quiz sessions are read from the same Firestore collection
              // already used by the existing quiz-session screen.
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      "Recent Quiz Sessions",
                      style: TextStyle(
                        color: textDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      openPage(
                        context,
                        const AdminQuizHistoryScreen(),
                        'quiz_history',
                      );
                    },
                    icon: const Icon(Icons.history_rounded, size: 17),
                    label: const Text('History'),
                    style: TextButton.styleFrom(
                      foregroundColor: primaryPurple,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AdminThemeColors.border, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: AdminThemeColors.primary.withValues(alpha: 0.05),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection("quiz_sessions")
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          "Unable to load quiz sessions.",
                          style: TextStyle(color: textMuted, fontSize: 12),
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: primaryPurple,
                            ),
                          ),
                        ),
                      );
                    }

                    DateTime? sessionDateOf(
                      QueryDocumentSnapshot<Map<String, dynamic>> doc,
                    ) {
                      final data = doc.data();
                      final dynamic raw =
                          data['createdAt'] ??
                          data['startTime'] ??
                          data['scheduledAt'] ??
                          data['date'] ??
                          data['timestamp'] ??
                          data['updatedAt'];
                      if (raw is Timestamp) return raw.toDate();
                      if (raw is DateTime) return raw;
                      if (raw is String) return DateTime.tryParse(raw);
                      if (raw is int) {
                        return DateTime.fromMillisecondsSinceEpoch(raw);
                      }
                      return null;
                    }

                    bool isValidRecentQuiz(
                      QueryDocumentSnapshot<Map<String, dynamic>> doc,
                    ) {
                      final data = doc.data();
                      // Filter out empty or "Untitled Quiz"
                      final rawTitle = (data['title'] ??
                              data['quizTitle'] ??
                              data['quizName'] ??
                              data['name'] ??
                              '')
                          .toString()
                          .trim();
                      if (rawTitle.isEmpty) return false;
                      final lowerTitle = rawTitle.toLowerCase();
                      if (lowerTitle == 'untitled quiz' ||
                          lowerTitle == 'untitled' ||
                          lowerTitle == 'no title' ||
                          lowerTitle == 'untitled_quiz') {
                        return false;
                      }

                      // Only show finished, waiting, pause, and ongoing
                      final rawStatus = (data['status'] ?? data['state'] ?? '')
                          .toString()
                          .trim()
                          .toLowerCase()
                          .replaceAll(' ', '_');
                      if (rawStatus.isEmpty) return false;

                      final isFinished = rawStatus == 'finished' ||
                          rawStatus == 'ended' ||
                          rawStatus == 'completed' ||
                          rawStatus == 'complete' ||
                          rawStatus == 'done';
                      final isWaiting = rawStatus == 'waiting' ||
                          rawStatus == 'pending' ||
                          rawStatus == 'ready' ||
                          rawStatus == 'waiting_for_readiness' ||
                          rawStatus == 'preparing_to_begin' ||
                          rawStatus == 'countdown';
                      final isPaused = rawStatus == 'paused' ||
                          rawStatus == 'pause' ||
                          rawStatus == 'level_pause' ||
                          rawStatus == 'break';
                      final isOngoing = rawStatus == 'ongoing' ||
                          rawStatus == 'active' ||
                          rawStatus == 'live' ||
                          rawStatus == 'in_progress' ||
                          rawStatus == 'running' ||
                          rawStatus == 'contest_review';

                      return isFinished || isWaiting || isPaused || isOngoing;
                    }

                    final sessions = snapshot.data!.docs
                        .where(isValidRecentQuiz)
                        .toList();

                    sessions.sort((a, b) {
                      final aDate =
                          sessionDateOf(a) ??
                          DateTime.fromMillisecondsSinceEpoch(0);
                      final bDate =
                          sessionDateOf(b) ??
                          DateTime.fromMillisecondsSinceEpoch(0);
                      return bDate.compareTo(aDate);
                    });

                    if (sessions.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 18, vertical: 24),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.quiz_outlined,
                                size: 30,
                                color: AdminThemeColors.textMuted,
                              ),
                              SizedBox(height: 7),
                              Text(
                                "No recent quiz sessions yet.",
                                style: TextStyle(
                                  color: AdminThemeColors.textMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return Column(
                      children: [
                        for (int i = 0; i < sessions.length && i < 4; i++) ...[
                          if (i > 0)
                            const Divider(
                              height: 1,
                              thickness: 1,
                              color: AdminThemeColors.border,
                            ),
                          _recentSessionTile(sessions[i]),
                        ],
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  const Expanded(
                    child: Text(
                      "User Roles Overview",
                      style: TextStyle(
                        color: textDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: _userCountCard(
                      collection: "users",
                      role: "admin",
                      label: "Admins",
                      color: AdminThemeColors.primary,
                      background: AdminThemeColors.pillBg,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: _userCountCard(
                      collection: "users",
                      role: "quizmaster",
                      label: "Quiz Masters",
                      color: const Color(0xFF1683D8),
                      background: const Color(0xFFE5F3FF),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: _userCountCard(
                      collection: "users",
                      role: "contestant",
                      label: "Contestants",
                      color: const Color(0xFF10A86B),
                      background: const Color(0xFFE2F9ED),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Center(
                child: Text(
                  "TechNoWiz • Admin Panel • v1.0.0",
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dashboardMetricCard({
    required IconData icon,
    required String title,
    required String collection,
    required Color color,
    required Color background,
    bool onlyOngoing = false,
    bool onlyLastWeek = false,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection(collection).snapshots(),
      builder: (context, snapshot) {
        int count = 0;
        if (snapshot.hasData) {
          if (onlyOngoing) {
            count = snapshot.data!.docs.where((doc) {
              final data = doc.data();
              final status = (data['status'] ?? data['state'] ?? '')
                  .toString()
                  .toLowerCase();
              // Count only quizzes that are still waiting to start or are
              // currently in progress. Finished/completed quizzes are excluded.
              return status == 'waiting' ||
                  status == 'pending' ||
                  status == 'ongoing' ||
                  status == 'active' ||
                  status == 'live' ||
                  status == 'in_progress' ||
                  status == 'in progress' ||
                  status == 'paused' ||
                  status == 'level_pause';
            }).length;
          } else if (onlyLastWeek) {
            final now = DateTime.now();
            final cutoff = now.subtract(const Duration(days: 7));
            count = snapshot.data!.docs.where((doc) {
              final data = doc.data();
              final dynamic raw =
                  data['createdAt'] ??
                  data['startTime'] ??
                  data['scheduledAt'] ??
                  data['date'];
              DateTime? sessionDate;
              if (raw is Timestamp) {
                sessionDate = raw.toDate();
              } else if (raw is DateTime) {
                sessionDate = raw;
              } else if (raw is String) {
                sessionDate = DateTime.tryParse(raw);
              }
              // Count only sessions with a recognizable date in the last 7 days.
              return sessionDate != null &&
                  !sessionDate.isBefore(cutoff) &&
                  !sessionDate.isAfter(now);
            }).length;
          } else {
            count = snapshot.data!.docs.length;
          }
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AdminThemeColors.border, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: AdminThemeColors.primary.withValues(alpha: 0.06),
                blurRadius: 14,
                offset: const Offset(0, 3),
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
                    colors: [
                      background,
                      color.withValues(alpha: 0.16),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: color.withValues(alpha: 0.25),
                    width: 1.2,
                  ),
                ),
                child: Icon(icon, color: color, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      snapshot.hasError
                          ? '—'
                          : (snapshot.hasData ? count.toString() : '…'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AdminThemeColors.textPrimary,
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AdminThemeColors.textMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _recentSessionTile(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final String quizCode =
        (data['quizCode'] ?? data['code'] ?? doc.id).toString();
    final String title = (data['title'] ??
            data['quizTitle'] ??
            data['quizName'] ??
            data['name'] ??
            'Quiz')
        .toString()
        .trim();
    final dynamic rawDate =
        data['createdAt'] ??
        data['startTime'] ??
        data['scheduledAt'] ??
        data['date'] ??
        data['timestamp'] ??
        data['updatedAt'];
    DateTime? date;
    if (rawDate is Timestamp) date = rawDate.toDate();
    if (rawDate is DateTime) date = rawDate;
    if (rawDate is String) date = DateTime.tryParse(rawDate);
    if (rawDate is int) date = DateTime.fromMillisecondsSinceEpoch(rawDate);

    final String dateText = date == null
        ? 'Recent'
        : '${date.day} ${_monthName(date.month)}, ${date.year}  '
              '${date.hour.toString().padLeft(2, '0')}:'
              '${date.minute.toString().padLeft(2, '0')}';

    final String rawStatus = (data['status'] ?? data['state'] ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll(' ', '_');

    String statusText;
    Color statusColor;
    IconData icon;
    final bool isFinished = rawStatus == 'finished' ||
        rawStatus == 'ended' ||
        rawStatus == 'completed' ||
        rawStatus == 'complete' ||
        rawStatus == 'done';

    if (isFinished) {
      statusText = 'Finished';
      statusColor = AdminThemeColors.primary;
      icon = Icons.task_alt_rounded;
    } else if (rawStatus == 'ongoing' ||
        rawStatus == 'active' ||
        rawStatus == 'live' ||
        rawStatus == 'in_progress' ||
        rawStatus == 'running' ||
        rawStatus == 'contest_review') {
      statusText = 'Ongoing';
      statusColor = const Color(0xFF0E9F6E);
      icon = Icons.play_arrow_rounded;
    } else if (rawStatus == 'paused' ||
        rawStatus == 'pause' ||
        rawStatus == 'level_pause' ||
        rawStatus == 'break') {
      statusText = 'Paused';
      statusColor = const Color(0xFFD97706);
      icon = Icons.pause_rounded;
    } else {
      statusText = 'Waiting';
      statusColor = const Color(0xFF2563EB);
      icon = Icons.hourglass_top_rounded;
    }

    final Color statusBackground = statusColor.withValues(alpha: 0.10);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          if (isFinished) {
            AdminNavPersistence.savePage(
              'quiz_history_results',
              historyQuizCode: quizCode,
              historyQuizTitle: title,
              historyQuizDate: dateText,
              historyDocId: doc.id,
            );
            await Navigator.push(
              context,
              adminPageRoute(
                AdminFinishedQuizResultsScreen(
                  quizCode: quizCode,
                  quizTitle: title,
                  quizDate: dateText,
                  docId: doc.id,
                ),
              ),
            );
            if (mounted) {
              AdminNavPersistence.savePage('dashboard');
            }
          } else {
            openPage(
              context,
              const ManageQuizSessionsScreen(),
              'quiz_sessions',
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: statusBackground,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.25),
                    width: 1.2,
                  ),
                ),
                child: Icon(
                  icon,
                  color: statusColor,
                  size: 20,
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
                        color: AdminThemeColors.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.schedule_rounded,
                          size: 11,
                          color: AdminThemeColors.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            dateText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AdminThemeColors.textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusBackground,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    statusText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: Color(0xFFC4B5FD),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _monthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  Widget _userCountCard({
    required String collection,
    required String role,
    required String label,
    required Color color,
    required Color background,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection(collection).snapshots(),
      builder: (context, snapshot) {
        int count = 0;
        if (snapshot.hasData) {
          String normalizeRole(dynamic value) {
            return (value ?? '').toString().trim().toLowerCase().replaceAll(
              RegExp(r'[\s_\-]+'),
              '',
            );
          }

          String canonicalRole(dynamic value) {
            final normalized = normalizeRole(value);
            if (normalized == 'admin' || normalized == 'administrator') {
              return 'admin';
            }
            if (normalized == 'quizmaster' ||
                normalized == 'quizmasters' ||
                normalized == 'master') {
              return 'quizmaster';
            }
            if (normalized == 'contestant' ||
                normalized == 'contestants' ||
                normalized == 'competitor' ||
                normalized == 'competitors') {
              return 'contestant';
            }
            return normalized;
          }

          count = snapshot.data!.docs.where((doc) {
            final data = doc.data();
            final actualRole = canonicalRole(data['role'] ?? data['userRole']);
            return actualRole == canonicalRole(role);
          }).length;
        }
        final IconData roleIcon = role == 'admin'
            ? Icons.admin_panel_settings_rounded
            : role == 'quizmaster'
            ? Icons.school_rounded
            : Icons.sports_esports_rounded;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AdminThemeColors.border, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: AdminThemeColors.primary.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: background,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color.withValues(alpha: 0.25),
                    width: 1.2,
                  ),
                ),
                child: Icon(roleIcon, color: color, size: 21),
              ),
              const SizedBox(height: 8),
              Text(
                snapshot.hasError ? '—' : count.toString(),
                style: const TextStyle(
                  color: AdminThemeColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget sectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 4,

          height: 21,

          decoration: BoxDecoration(
            color: primaryPurple,

            borderRadius: BorderRadius.circular(5),
          ),
        ),

        const SizedBox(width: 9),

        Text(
          title,

          style: const TextStyle(
            fontSize: 21,

            fontWeight: FontWeight.w800,

            color: textDark,
          ),
        ),
      ],
    );
  }

  // =========================================================

  // BUILD

  // =========================================================

  @override
  Widget build(BuildContext context) {
    final sidebar = AdminSidebar(
      currentPage: 'dashboard',
      onProfileTap: () => showProfileMenu(context),
      onDestinationSelected: (destination) {
        switch (destination) {
          case 'manage_users':
            openPage(context, const ManageUsersScreen(), 'manage_users');
            break;
          case 'add_question':
            openPage(context, const AddQuestionScreen(), 'add_question');
            break;
          case 'question_list':
            openPage(context, const QuestionListScreen(), 'question_list');
            break;
          case 'quiz_sessions':
            openPage(
              context,
              const ManageQuizSessionsScreen(),
              'quiz_sessions',
            );
            break;
          case 'leaderboard':
            openPage(context, const AdminLeaderboardScreen(), 'leaderboard');
            break;
          case 'reports':
            openPage(context, const AdminReportScreen(), 'reports');
            break;
          case 'dashboard':
            _saveLastAdminPage('dashboard');
            break;
        }
      },
    );

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: backgroundColor,
      appBar: buildAdminStandardAppBar(
        context: context,
        badgeText: 'Dashboard',
        subtitle: 'Admin Command Center',
        onMenuPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
      ),
      endDrawer: sidebar,
      endDrawerEnableOpenDragGesture: true,
      body: AdminCircuitBackground(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double width = constraints.maxWidth;
            return dashboardContent(context, width);
          },
        ),
      ),
    );
  }
}

/// Results viewer opened when an Admin taps a finished quiz in History.
/// Shows the complete quiz history: description, venue, schedule, the timer
/// used for each level, who was eliminated in each level, and every
/// contestant's correct / wrong answers per level. Read-only except for the
/// explicit delete action in the app bar.
class AdminFinishedQuizResultsScreen extends StatefulWidget {
  const AdminFinishedQuizResultsScreen({
    super.key,
    required this.quizCode,
    required this.quizTitle,
    required this.quizDate,
    this.docId,
  });

  final String quizCode;
  final String quizTitle;
  final String quizDate;
  final String? docId;

  @override
  State<AdminFinishedQuizResultsScreen> createState() =>
      _AdminFinishedQuizResultsScreenState();
}

class _AdminFinishedQuizResultsScreenState
    extends State<AdminFinishedQuizResultsScreen> {
  final ScrollController _tabsScrollController = ScrollController();

  void _scrollToSelectedTab() {
    if (!_tabsScrollController.hasClients) return;
    final allTabs = <int?>[null, ..._levels.map((l) => l.number)];
    final idx = allTabs.indexOf(_selectedLevel);
    if (idx >= 0) {
      final targetOffset = (idx * 135.0) - 20.0;
      final max = _tabsScrollController.position.maxScrollExtent;
      final clamped = targetOffset.clamp(0.0, max);
      _tabsScrollController.animateTo(
        clamped,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _selectNextTab() {
    final allTabs = <int?>[null, ..._levels.map((l) => l.number)];
    final idx = allTabs.indexOf(_selectedLevel);
    if (idx < allTabs.length - 1) {
      setState(() => _selectedLevel = allTabs[idx + 1]);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelectedTab());
    }
  }

  void _selectPrevTab() {
    final allTabs = <int?>[null, ..._levels.map((l) => l.number)];
    final idx = allTabs.indexOf(_selectedLevel);
    if (idx > 0) {
      setState(() => _selectedLevel = allTabs[idx - 1]);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelectedTab());
    }
  }

  @override
  void dispose() {
    _tabsScrollController.dispose();
    super.dispose();
  }
  static const Color _purple = AdminThemeColors.primary;
  static const Color _dark = AdminThemeColors.textPrimary;
  static const Color _muted = AdminThemeColors.textMuted;
  static const Color _pill = AdminThemeColors.pillBg;
  static const Color _border = AdminThemeColors.border;
  static const Color _green = Color(0xFF16A34A);
  static const Color _red = Color(0xFFDC2626);

  /// Same fallback Quiz Control uses when a level has no configured timer.
  static const int _defaultTimerSeconds = 30;

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _session = {};
  List<_HistoryLevel> _levels = [];
  List<_HistoryContestant> _contestants = [];
  int _questionCount = 0;

  /// null = all levels, otherwise the selected level number.
  int? _selectedLevel;
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    AdminNavPersistence.savePage(
      'quiz_history_results',
      historyQuizCode: widget.quizCode,
      historyQuizTitle: widget.quizTitle,
      historyQuizDate: widget.quizDate,
      historyDocId: widget.docId,
    );
    _load();
  }

  // ==========================================================
  // PARSING HELPERS
  // ==========================================================

  static int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    final digits = value.toString().replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits);
  }

  static num? _asNum(dynamic value) {
    if (value == null) return null;
    if (value is num) return value;
    return num.tryParse(value.toString().trim());
  }

  static String _text(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    return '';
  }

  static String _pick(List<String> values) {
    for (final value in values) {
      if (value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  static dynamic _raw(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value != null && value.toString().trim().isNotEmpty) return value;
    }
    return null;
  }

  static int _levelOfQuestion(Map<String, dynamic> question) {
    return _asInt(question['sessionLevel'] ?? question['level']) ?? 1;
  }

  static bool _isEliminatedFlag(Map<String, dynamic> data) {
    return data['eliminated'] == true ||
        data['isEliminated'] == true ||
        (data['status'] ?? '').toString().trim().toLowerCase() == 'eliminated';
  }

  static int _scoreOf(Map<String, dynamic> data) {
    for (final key in const ['score', 'totalScore', 'finalScore', 'points']) {
      final value = _asNum(data[key]);
      if (value != null) return value.toInt();
    }
    return 0;
  }

  /// Sorts session questions exactly like the contestant history screen so
  /// response ids (question_0, question_1, ...) map to the right question.
  List<Map<String, dynamic>> _sortQuestions(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sorted = [...docs];
    sorted.sort((a, b) {
      final ad = a.data();
      final bd = b.data();
      final levelCompare = _levelOfQuestion(ad).compareTo(_levelOfQuestion(bd));
      if (levelCompare != 0) return levelCompare;

      final aOrder = _asNum(ad['order']);
      final bOrder = _asNum(bd['order']);
      if (aOrder != null && bOrder != null && aOrder != bOrder) {
        return aOrder.compareTo(bOrder);
      }
      if (aOrder != null && bOrder == null) return -1;
      if (aOrder == null && bOrder != null) return 1;

      final aCreated = ad['createdAt'];
      final bCreated = bd['createdAt'];
      if (aCreated is Timestamp && bCreated is Timestamp) {
        final dateCompare = aCreated.compareTo(bCreated);
        if (dateCompare != 0) return dateCompare;
      } else if (aCreated is Timestamp) {
        return -1;
      } else if (bCreated is Timestamp) {
        return 1;
      }
      return a.id.compareTo(b.id);
    });
    return sorted.map((doc) => doc.data()).toList();
  }

  // ==========================================================
  // LOAD
  // ==========================================================

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      var ref = firestore
          .collection('quiz_sessions')
          .doc(widget.docId ?? widget.quizCode);
      var sessionDoc = await ref.get();
      if (!sessionDoc.exists &&
          widget.docId != null &&
          widget.docId != widget.quizCode) {
        ref = firestore.collection('quiz_sessions').doc(widget.quizCode);
        sessionDoc = await ref.get();
      }
      final session = sessionDoc.data() ?? <String, dynamic>{};

      final snapshots = await Future.wait([
        ref.collection('questions').get(),
        ref.collection('scores').get(),
        ref.collection('join_requests').get(),
      ]);
      final questions = _sortQuestions(snapshots[0].docs);
      final scoreDocs = snapshots[1].docs;
      final joinDocs = snapshots[2].docs;

      final scoreById = {for (final d in scoreDocs) d.id: d.data()};
      final joinById = {for (final d in joinDocs) d.id: d.data()};

      // Contestants = everyone with a score record, plus approved contestants
      // that never scored (so 0-point contestants are not hidden).
      final ids = <String>{...scoreById.keys};
      for (final doc in joinDocs) {
        final status = (doc.data()['status'] ?? '').toString().toLowerCase();
        if (const {
          'approved',
          'accepted',
          'eliminated',
          'proceeding',
        }.contains(status)) {
          ids.add(doc.id);
        }
      }
      final idList = ids.toList();

      final responseSnaps = await Future.wait(
        idList.map(
          (id) => ref.collection('answers').doc(id).collection('responses').get(),
        ),
      );

      final levelNumbers = <int>{};
      final contestants = <_HistoryContestant>[];

      for (int i = 0; i < idList.length; i++) {
        final uid = idList[i];
        final score = scoreById[uid] ?? <String, dynamic>{};
        final join = joinById[uid] ?? <String, dynamic>{};

        final name = _pick([
          _text(score, const [
            'name',
            'displayName',
            'contestantName',
            'userName',
          ]),
          _text(join, const [
            'name',
            'displayName',
            'contestantName',
            'userName',
          ]),
          _text(score, const ['email']),
          _text(join, const ['email']),
          uid,
        ]);

        final tallies = <int, _LevelTally>{};
        final answers = <_HistoryAnswer>[];

        for (final responseDoc in responseSnaps[i].docs) {
          final rd = responseDoc.data();

          int? qIndex;
          final match = RegExp(r'^question_(\d+)$').firstMatch(responseDoc.id);
          if (match != null) qIndex = int.tryParse(match.group(1)!);
          qIndex ??= _asInt(rd['questionIndex']);
          final qNumberRaw = _asInt(rd['questionNumber']);
          if (qIndex == null && qNumberRaw != null) qIndex = qNumberRaw - 1;
          final qNumber = qNumberRaw ?? (qIndex != null ? qIndex + 1 : null);

          final question =
              (qIndex != null && qIndex >= 0 && qIndex < questions.length)
              ? questions[qIndex]
              : const <String, dynamic>{};

          final level =
              _asInt(rd['level'] ?? rd['sessionLevel']) ??
              (question.isNotEmpty ? _levelOfQuestion(question) : 1);

          final isCorrect =
              rd['isCorrect'] == true ||
              rd['answerStatus']?.toString().toLowerCase() == 'correct';
          final points = isCorrect
              ? (_asNum(rd['points'])?.toInt() ?? 1)
              : 0;

          final tally = tallies.putIfAbsent(level, () => _LevelTally());
          if (isCorrect) {
            tally.correct++;
            tally.points += points;
          } else {
            tally.wrong++;
          }
          levelNumbers.add(level);

          answers.add(
            _HistoryAnswer(
              number: qNumber ?? answers.length + 1,
              level: level,
              question: _pick([
                _text(question, const ['question', 'questionText', 'title']),
                _text(rd, const ['question', 'questionText']),
              ]),
              selected: _text(rd, const ['selectedAnswer', 'answer']),
              correctAnswer: _pick([
                _text(rd, const ['correctAnswer']),
                _text(question, const ['correctAnswer', 'answer']),
              ]),
              isCorrect: isCorrect,
              timedOut: rd['timedOut'] == true,
            ),
          );
        }
        answers.sort((a, b) => a.number.compareTo(b.number));

        final eliminated = _isEliminatedFlag(score) || _isEliminatedFlag(join);
        int? eliminatedLevel;
        if (eliminated) {
          eliminatedLevel = _asInt(
            _raw(score, const [
                  'eliminatedLevel',
                  'eliminatedAfterLevel',
                  'decisionLevel',
                ]) ??
                _raw(join, const [
                  'eliminatedLevel',
                  'eliminatedAfterLevel',
                  'decisionLevel',
                ]),
          );
          // Older records may not store the level: use the last level the
          // contestant answered in.
          if (eliminatedLevel == null && tallies.isNotEmpty) {
            eliminatedLevel = tallies.keys.reduce((a, b) => a > b ? a : b);
          }
          if (eliminatedLevel != null) levelNumbers.add(eliminatedLevel);
        }

        contestants.add(
          _HistoryContestant(
            uid: uid,
            name: name,
            score: _scoreOf(score),
            isEliminated: eliminated,
            eliminatedLevel: eliminatedLevel,
            tallies: tallies,
            answers: answers,
          ),
        );
      }

      // Finalists first, then contestants who lasted longer, then by score.
      contestants.sort((a, b) {
        if (a.isEliminated != b.isEliminated) return a.isEliminated ? 1 : -1;
        if (a.isEliminated && b.isEliminated) {
          final levelCompare = (b.eliminatedLevel ?? 0).compareTo(
            a.eliminatedLevel ?? 0,
          );
          if (levelCompare != 0) return levelCompare;
        }
        final scoreCompare = b.score.compareTo(a.score);
        if (scoreCompare != 0) return scoreCompare;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      // Levels configured on the session + levels seen in questions/answers.
      final settings = session['levelSettings'] is Map
          ? Map<String, dynamic>.from(session['levelSettings'] as Map)
          : <String, dynamic>{};
      final rawLevels = session['levels'];
      if (rawLevels is List) {
        for (final level in rawLevels) {
          final n = _asInt(level);
          if (n != null) levelNumbers.add(n);
        }
      }
      final settingsByLevel = <int, Map<String, dynamic>>{};
      settings.forEach((key, value) {
        final n = _asInt(key);
        if (n != null) {
          levelNumbers.add(n);
          if (value is Map) {
            settingsByLevel[n] = Map<String, dynamic>.from(value);
          }
        }
      });
      for (final q in questions) {
        levelNumbers.add(_levelOfQuestion(q));
      }

      final sortedLevels = levelNumbers.toList()..sort();
      final levels = sortedLevels.map((n) {
        final cfg = settingsByLevel[n] ?? const <String, dynamic>{};
        final configuredTimer = _asInt(cfg['timerSeconds']);
        final hasTimer = configuredTimer != null && configuredTimer > 0;
        return _HistoryLevel(
          number: n,
          timerSeconds: hasTimer ? configuredTimer : _defaultTimerSeconds,
          timerIsDefault: !hasTimer,
          eliminateCount: _asInt(cfg['eliminateCount']),
          pointsPerCorrect: _asInt(cfg['pointsPerCorrectAnswer']),
          difficulty: _text(cfg, const ['difficulty']),
          questionCount: questions.where((q) => _levelOfQuestion(q) == n).length,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _session = session;
        _levels = levels;
        _contestants = contestants;
        _questionCount = questions.length;
        if (_selectedLevel != null &&
            !levels.any((l) => l.number == _selectedLevel)) {
          _selectedLevel = null;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ==========================================================
  // FORMATTING
  // ==========================================================

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  DateTime? _toDate(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    return null;
  }

  String _formatDate(dynamic raw) {
    final date = _toDate(raw);
    if (date != null) {
      return '${date.day} ${_months[date.month - 1]} ${date.year}';
    }
    return raw?.toString().trim() ?? '';
  }

  String _formatTime(dynamic raw) {
    final date = _toDate(raw);
    if (date != null) {
      final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
      final period = date.hour < 12 ? 'AM' : 'PM';
      return '$hour:${date.minute.toString().padLeft(2, '0')} $period';
    }
    return raw?.toString().trim() ?? '';
  }

  String _orNotSet(String value) => value.isEmpty ? 'Not set' : value;

  // ==========================================================
  // DERIVED DATA
  // ==========================================================

  List<_HistoryContestant> _eliminatedIn(int level) => _contestants
      .where((c) => c.isEliminated && c.eliminatedLevel == level)
      .toList();

  /// Contestants who were still in the game when [level] was played.
  List<_HistoryContestant> _playedLevel(int level) => _contestants
      .where(
        (c) =>
            !c.isEliminated ||
            c.eliminatedLevel == null ||
            c.eliminatedLevel! >= level,
      )
      .toList();

  List<_HistoryContestant> get _finalists =>
      _contestants.where((c) => !c.isEliminated).toList();

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final title = _pick([
      widget.quizTitle,
      _text(_session, const ['title', 'quizTitle', 'name']),
      'Quiz Results',
    ]);

    return Scaffold(
      backgroundColor: AdminThemeColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: kAdminAppBarHeight,
        foregroundColor: _dark,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            final navigator = Navigator.of(context);
            if (navigator.canPop()) {
              navigator.pop();
            } else {
              AdminNavPersistence.savePage('quiz_history');
              navigator.pushAndRemoveUntil<void>(
                adminPageRoute<void>(
                  const AdminQuizHistoryScreen(),
                ),
                (route) => false,
              );
            }
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const Text(
              'Quiz History Details',
              style: TextStyle(
                fontSize: 11,
                color: _muted,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded, color: _purple),
            onPressed: _loading ? null : _load,
          ),
          IconButton(
            tooltip: 'Delete Quiz Session',
            icon: const Icon(Icons.delete_outline_rounded, color: _red),
            onPressed: () async {
              final deleted = await AdminQuizHistoryScreen._deleteQuizSession(
                context,
                widget.docId ?? widget.quizCode,
                title,
                quizCode: widget.quizCode,
              );
              if (deleted && context.mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AdminCircuitBackground(child: _buildBody(title)),
    );
  }

  Widget _buildBody(String title) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _purple));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 44, color: _red),
              const SizedBox(height: 12),
              Text(
                'Unable to load quiz history.\n$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _dark, fontSize: 12.5),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _purple,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const maxContentWidth = 1000.0;
        final sidePadding = constraints.maxWidth > maxContentWidth + 32
            ? (constraints.maxWidth - maxContentWidth) / 2
            : 14.0;
        return RefreshIndicator(
          color: _purple,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(sidePadding, 14, sidePadding, 28),
            children: [
              _buildOverviewCard(title),
              const SizedBox(height: 12),
              _buildStatsRow(),
              const SizedBox(height: 18),
              _sectionTitle(
                Icons.timer_rounded,
                'LEVEL TIMERS & RULES',
                '${_levels.length} level${_levels.length == 1 ? '' : 's'}',
              ),
              const SizedBox(height: 8),
              _buildLevelCards(),
              const SizedBox(height: 18),
              _sectionTitle(
                Icons.person_off_rounded,
                'ELIMINATED PER LEVEL',
                '${_contestants.where((c) => c.isEliminated).length} eliminated',
              ),
              const SizedBox(height: 8),
              _buildEliminationTimeline(),
              const SizedBox(height: 18),
              _sectionTitle(
                Icons.fact_check_rounded,
                'CORRECT & WRONG PER LEVEL',
                '${_contestants.length} contestant${_contestants.length == 1 ? '' : 's'}',
              ),
              const SizedBox(height: 8),
              _buildLevelTabs(),
              const SizedBox(height: 10),
              _buildContestantCardsSection(),
            ],
          ),
        );
      },
    );
  }

  // ==========================================================
  // SECTIONS
  // ==========================================================

  BoxDecoration _cardDecoration({Color color = Colors.white, Color? border}) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: border ?? _border, width: 1.2),
      boxShadow: [
        BoxShadow(
          color: _purple.withValues(alpha: 0.05),
          blurRadius: 14,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }

  Widget _sectionTitle(IconData icon, String title, String trailing) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _purple),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: _dark,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(trailing, style: const TextStyle(fontSize: 11, color: _muted)),
      ],
    );
  }

  Widget _buildOverviewCard(String title) {
    final description = _text(_session, const [
      'description',
      'quizDescription',
      'details',
    ]);
    final venue = _text(_session, const ['venue', 'location', 'where', 'place']);
    final date = _formatDate(
      _raw(_session, const ['date', 'quizDate', 'startDate', 'scheduledDate']),
    );
    final startTime = _formatTime(
      _raw(_session, const [
        'time',
        'quizTime',
        'startTime',
        'scheduledTime',
        'startedAt',
      ]),
    );
    final endTime = _formatTime(
      _raw(_session, const [
        'endTime',
        'quizEndTime',
        'finishTime',
        'scheduledEndTime',
        'finishedAt',
        'endedAt',
        'completedAt',
      ]),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _chip(
                icon: Icons.qr_code_rounded,
                label: 'CODE: ${widget.quizCode}',
                color: _purple,
                background: _pill,
              ),
              _chip(
                icon: Icons.check_circle_rounded,
                label: 'FINISHED',
                color: const Color(0xFF059669),
                background: const Color(0xFFECFDF5),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              color: _dark,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'DESCRIPTION',
            style: TextStyle(
              fontSize: 10,
              color: _muted,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            description.isEmpty ? 'No description provided.' : description,
            style: TextStyle(
              fontSize: 12.5,
              color: description.isEmpty ? _muted : _dark,
              height: 1.4,
              fontStyle: description.isEmpty
                  ? FontStyle.italic
                  : FontStyle.normal,
            ),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: _border),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 640
                  ? 4
                  : (constraints.maxWidth >= 340 ? 2 : 1);
              const spacing = 12.0;
              final itemWidth =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              final items = [
                _metaItem(
                  Icons.location_on_rounded,
                  'VENUE',
                  _orNotSet(venue),
                  const Color(0xFFEA580C),
                  const Color(0xFFFFF7ED),
                ),
                _metaItem(
                  Icons.calendar_today_rounded,
                  'DATE',
                  _orNotSet(date),
                  const Color(0xFF2563EB),
                  const Color(0xFFEFF6FF),
                ),
                _metaItem(
                  Icons.schedule_rounded,
                  'START TIME',
                  _orNotSet(startTime),
                  _purple,
                  _pill,
                ),
                _metaItem(
                  Icons.timer_off_outlined,
                  'END TIME',
                  _orNotSet(endTime),
                  const Color(0xFF0891B2),
                  const Color(0xFFECFEFF),
                ),
              ];
              return Wrap(
                spacing: spacing,
                runSpacing: 12,
                children: [
                  for (final item in items)
                    SizedBox(width: itemWidth, child: item),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required IconData icon,
    required String label,
    required Color color,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaItem(
    IconData icon,
    String label,
    String value,
    Color iconColor,
    Color background,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: iconColor, size: 17),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: _muted,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: value == 'Not set' ? _muted : _dark,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow() {
    final eliminated = _contestants.where((c) => c.isEliminated).length;
    final stats = [
      ('Contestants', '${_contestants.length}', Icons.people_alt_rounded, _purple),
      ('Levels', '${_levels.length}', Icons.layers_rounded, const Color(0xFF2563EB)),
      ('Questions', '$_questionCount', Icons.quiz_rounded, const Color(0xFF0891B2)),
      ('Eliminated', '$eliminated', Icons.person_off_rounded, _red),
      ('Finalists', '${_finalists.length}', Icons.emoji_events_rounded, const Color(0xFFD97706)),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 700
            ? 5
            : (constraints.maxWidth >= 420 ? 3 : 2);
        const spacing = 8.0;
        final itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final s in stats)
              Container(
                width: itemWidth,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: _cardDecoration(),
                child: Row(
                  children: [
                    Icon(s.$3, size: 18, color: s.$4),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.$2,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: _dark,
                            ),
                          ),
                          Text(
                            s.$1,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: _muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildLevelCards() {
    if (_levels.isEmpty) {
      return _emptyBox('No level settings were saved for this quiz.');
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 860
            ? 3
            : (constraints.maxWidth >= 520 ? 2 : 1);
        const spacing = 8.0;
        final itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final level in _levels)
              SizedBox(width: itemWidth, child: _levelCard(level)),
          ],
        );
      },
    );
  }

  Widget _levelCard(_HistoryLevel level) {
    final eliminatedCount = _eliminatedIn(level.number).length;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _pill,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: _purple.withValues(alpha: 0.25)),
            ),
            child: Text(
              'L${level.number}',
              style: const TextStyle(
                color: _purple,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Level ${level.number}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _dark,
                      ),
                    ),
                    if (level.difficulty.isNotEmpty)
                      _miniTag(level.difficulty, const Color(0xFF4B5563),
                          const Color(0xFFF3F4F6)),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_rounded,
                          size: 13, color: Color(0xFFB45309)),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '${level.timerSeconds} seconds per question'
                          '${level.timerIsDefault ? ' (default)' : ''}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 3,
                  children: [
                    _levelFact(Icons.quiz_outlined, '${level.questionCount} questions'),
                    if (level.pointsPerCorrect != null)
                      _levelFact(Icons.star_outline_rounded,
                          '+${level.pointsPerCorrect} pt / correct'),
                    if (level.eliminateCount != null)
                      _levelFact(Icons.content_cut_rounded,
                          'Eliminate ${level.eliminateCount}'),
                    _levelFact(Icons.person_off_outlined,
                        '$eliminatedCount eliminated'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _levelFact(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: _muted),
        const SizedBox(width: 3),
        Text(
          text,
          style: const TextStyle(
            fontSize: 10.5,
            color: _muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _miniTag(String text, Color color, Color background) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9.5,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildEliminationTimeline() {
    final unknownLevel = _contestants
        .where((c) => c.isEliminated && c.eliminatedLevel == null)
        .toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final level in _levels) ...[
            _eliminationRow(
              label: 'Level ${level.number}',
              people: _eliminatedIn(level.number),
              level: level.number,
            ),
            const SizedBox(height: 10),
          ],
          if (unknownLevel.isNotEmpty) ...[
            _eliminationRow(
              label: 'Level not recorded',
              people: unknownLevel,
              level: null,
            ),
            const SizedBox(height: 10),
          ],
          const Divider(height: 1, color: _border),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.emoji_events_rounded,
                  size: 16, color: Color(0xFFD97706)),
              const SizedBox(width: 6),
              Text(
                'FINALISTS (${_finalists.length})',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFB45309),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_finalists.isEmpty)
            const Text(
              'No finalist recorded.',
              style: TextStyle(fontSize: 11.5, color: _muted),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in _finalists)
                  _personPill(
                    c.name,
                    '${c.score} pts',
                    const Color(0xFF166534),
                    const Color(0xFFF0FDF4),
                    const Color(0xFF86EFAC),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _eliminationRow({
    required String label,
    required List<_HistoryContestant> people,
    required int? level,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _purple,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                people.isEmpty
                    ? 'No one eliminated'
                    : '${people.length} eliminated',
                style: TextStyle(
                  fontSize: 11,
                  color: people.isEmpty ? _muted : _red,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        if (people.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in people)
                _personPill(
                  c.name,
                  level == null
                      ? '${c.score} pts'
                      : '${c.tallies[level]?.correct ?? 0}✓ '
                            '${c.tallies[level]?.wrong ?? 0}✗',
                  const Color(0xFF991B1B),
                  const Color(0xFFFEF2F2),
                  const Color(0xFFFCA5A5),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _personPill(
    String name,
    String detail,
    Color color,
    Color background,
    Color border,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: name,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            TextSpan(
              text: '  $detail',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLevelTabs() {
    Widget tab(String label, int? level) {
      final selected = _selectedLevel == level;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          onSelected: (_) {
            setState(() => _selectedLevel = level);
            WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelectedTab());
          },
          selectedColor: _purple,
          backgroundColor: Colors.white,
          labelStyle: TextStyle(
            color: selected ? Colors.white : _dark,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: selected ? _purple : _border, width: 1.1),
          ),
        ),
      );
    }

    return ScrollConfiguration(
      behavior: const _SwipeableScrollBehavior(),
      child: SingleChildScrollView(
        controller: _tabsScrollController,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          children: [
            tab('All Levels', null),
            for (final level in _levels)
              tab('Level ${level.number} • ${level.timerSeconds}s', level.number),
          ],
        ),
      ),
    );
  }

  Widget _buildContestantCardsSection() {
    final level = _selectedLevel;
    final list = level == null ? _contestants : _playedLevel(level);

    if (list.isEmpty) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity < -220) {
            _selectNextTab();
          } else if (velocity > 220) {
            _selectPrevTab();
          }
        },
        child: _emptyBox(
          level == null
              ? 'No contestant records found for this quiz.'
              : 'No contestant played Level $level.',
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -220) {
          _selectNextTab();
        } else if (velocity > 220) {
          _selectPrevTab();
        }
      },
      child: Column(
        children: [
          for (int i = 0; i < list.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _contestantCard(i + 1, list[i], level),
            ),
        ],
      ),
    );
  }

  Widget _contestantCard(int rank, _HistoryContestant c, int? level) {
    final expanded = _expanded.contains(c.uid);
    final correct = level == null ? c.totalCorrect : (c.tallies[level]?.correct ?? 0);
    final wrong = level == null ? c.totalWrong : (c.tallies[level]?.wrong ?? 0);
    final points = level == null ? c.score : (c.tallies[level]?.points ?? 0);
    final answers = level == null
        ? c.answers
        : c.answers.where((a) => a.level == level).toList();
    final eliminatedHere = level != null && c.isEliminated && c.eliminatedLevel == level;

    return Container(
      decoration: _cardDecoration(
        border: eliminatedHere ? const Color(0xFFFCA5A5) : null,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                _rankBadge(rank),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _dark,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _statusBadge(c),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$points',
                      style: const TextStyle(
                        color: _purple,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      level == null ? 'TOTAL POINTS' : 'LEVEL $level POINTS',
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 9, 14, 10),
            decoration: const BoxDecoration(
              color: Color(0xFFFAF8FF),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
              border: Border(top: BorderSide(color: Color(0xFFF1EEFF))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _countPill('Correct', correct, _green, const Color(0xFFDCFCE7)),
                    const SizedBox(width: 6),
                    _countPill('Wrong', wrong, _red, const Color(0xFFFEE2E2)),
                    const Spacer(),
                    if (answers.isNotEmpty)
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => setState(() {
                          if (expanded) {
                            _expanded.remove(c.uid);
                          } else {
                            _expanded.add(c.uid);
                          }
                        }),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                expanded ? 'Hide answers' : 'View answers',
                                style: const TextStyle(
                                  color: _purple,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Icon(
                                expanded
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.keyboard_arrow_down_rounded,
                                size: 17,
                                color: _purple,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                if (level == null && _levels.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final l in _levels) _levelTallyChip(c, l.number),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (expanded && answers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                children: [for (final a in answers) _answerRow(a)],
              ),
            ),
        ],
      ),
    );
  }

  Widget _rankBadge(int rank) {
    final colors = switch (rank) {
      1 => (const Color(0xFFFEF3C7), const Color(0xFFF59E0B), const Color(0xFFB45309)),
      2 => (const Color(0xFFF3F4F6), const Color(0xFF9CA3AF), const Color(0xFF4B5563)),
      3 => (const Color(0xFFFFEDD5), const Color(0xFFF97316), const Color(0xFFC2410C)),
      _ => (_pill, _purple.withValues(alpha: 0.3), _purple),
    };
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.$1,
        shape: BoxShape.circle,
        border: Border.all(color: colors.$2, width: 1.2),
      ),
      child: Text(
        '$rank',
        style: TextStyle(
          color: colors.$3,
          fontWeight: FontWeight.w900,
          fontSize: 15,
        ),
      ),
    );
  }

  Widget _statusBadge(_HistoryContestant c) {
    if (c.isEliminated) {
      return _chip(
        icon: Icons.cancel_rounded,
        label: c.eliminatedLevel == null
            ? 'ELIMINATED'
            : 'ELIMINATED • LEVEL ${c.eliminatedLevel}',
        color: _red,
        background: const Color(0xFFFEF2F2),
      );
    }
    return _chip(
      icon: Icons.emoji_events_rounded,
      label: 'FINALIST',
      color: const Color(0xFF059669),
      background: const Color(0xFFECFDF5),
    );
  }

  Widget _countPill(String label, int count, Color color, Color background) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _levelTallyChip(_HistoryContestant c, int level) {
    final tally = c.tallies[level];
    final notReached = c.isEliminated &&
        c.eliminatedLevel != null &&
        level > c.eliminatedLevel!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: notReached
          ? Text(
              'L$level: not reached',
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF9CA3AF),
                fontWeight: FontWeight.w600,
              ),
            )
          : Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'L$level  ',
                    style: const TextStyle(
                      color: _muted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextSpan(
                    text: '${tally?.correct ?? 0}✓  ',
                    style: const TextStyle(
                      color: _green,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextSpan(
                    text: '${tally?.wrong ?? 0}✗',
                    style: const TextStyle(
                      color: _red,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 10.5),
            ),
    );
  }

  Widget _answerRow(_HistoryAnswer a) {
    final color = a.isCorrect ? _green : _red;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: a.isCorrect ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: a.isCorrect ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            a.isCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 17,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Q${a.number} • Level ${a.level}'
                  '${a.question.isEmpty ? '' : ' — ${a.question}'}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: _dark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Answer: ${a.selected.isEmpty ? (a.timedOut ? 'No answer (time ran out)' : 'No answer') : a.selected}',
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!a.isCorrect && a.correctAnswer.isNotEmpty)
                  Text(
                    'Correct answer: ${a.correctAnswer}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF374151),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyBox(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: _muted, fontSize: 12),
      ),
    );
  }
}

class _HistoryLevel {
  const _HistoryLevel({
    required this.number,
    required this.timerSeconds,
    required this.timerIsDefault,
    required this.eliminateCount,
    required this.pointsPerCorrect,
    required this.difficulty,
    required this.questionCount,
  });

  final int number;
  final int timerSeconds;
  final bool timerIsDefault;
  final int? eliminateCount;
  final int? pointsPerCorrect;
  final String difficulty;
  final int questionCount;
}

class _LevelTally {
  int correct = 0;
  int wrong = 0;
  int points = 0;
}

class _HistoryAnswer {
  const _HistoryAnswer({
    required this.number,
    required this.level,
    required this.question,
    required this.selected,
    required this.correctAnswer,
    required this.isCorrect,
    required this.timedOut,
  });

  final int number;
  final int level;
  final String question;
  final String selected;
  final String correctAnswer;
  final bool isCorrect;
  final bool timedOut;
}

class _HistoryContestant {
  _HistoryContestant({
    required this.uid,
    required this.name,
    required this.score,
    required this.isEliminated,
    required this.eliminatedLevel,
    required this.tallies,
    required this.answers,
  });

  final String uid;
  final String name;
  final int score;
  final bool isEliminated;
  final int? eliminatedLevel;
  final Map<int, _LevelTally> tallies;
  final List<_HistoryAnswer> answers;

  int get totalCorrect =>
      tallies.values.fold(0, (total, tally) => total + tally.correct);
  int get totalWrong =>
      tallies.values.fold(0, (total, tally) => total + tally.wrong);
}

/// Admin-only history of quiz sessions. This view does not delete or modify
/// quiz records; it filters the existing quiz_sessions collection for finished
/// sessions and displays them newest-first.
class AdminQuizHistoryScreen extends StatefulWidget {
  const AdminQuizHistoryScreen({super.key});

  @override
  State<AdminQuizHistoryScreen> createState() => _AdminQuizHistoryScreenState();

  /// Deletes a quiz session along with all associated subcollections.
  static Future<bool> _deleteQuizSession(
    BuildContext context,
    String docId,
    String quizTitle, {
    String quizCode = '',
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.delete_forever_rounded,
                  color: Color(0xFFDC2626),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Delete Quiz Record?',
                  style: TextStyle(
                    color: AdminThemeColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Sigurado ka ba nga gusto nimo i-delete ang session para sa "$quizTitle"?\n\n'
            'Mawala ang tanang scores, question history, ug answers niini gikan sa database. Dili na kini mabalik.',
            style: const TextStyle(
              color: AdminThemeColors.textPrimary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              style: TextButton.styleFrom(
                foregroundColor: AdminThemeColors.textMuted,
              ),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: const Text(
                'DELETE',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
    );

    if (confirm != true) return false;

    try {
      final firestore = FirebaseFirestore.instance;
      final quizRef = firestore.collection('quiz_sessions').doc(docId);

      final subcollections = [
        'scores',
        'questions',
        'join_requests',
        'participants',
        'submissions',
        'answers',
      ];

      for (final collectionName in subcollections) {
        final snapshot = await quizRef.collection(collectionName).get();
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

      if (quizCode.isNotEmpty && quizCode != docId) {
        final altRef = firestore.collection('quiz_sessions').doc(quizCode);
        final altDoc = await altRef.get();
        if (altDoc.exists) {
          await altRef.delete();
        }
      }

      if (context.mounted) {
        AdminNotification.success(
          context,
          'Quiz "$quizTitle" ($quizCode) deleted successfully.',
        );
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        AdminNotification.error(
          context,
          'Failed to delete quiz: $e',
        );
      }
      return false;
    }
  }

  /// Bulk deletes all completed quiz history entries.
  static Future<void> _deleteAllHistory(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> sessions,
  ) async {
    if (sessions.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.delete_sweep_rounded,
                  color: Color(0xFFDC2626),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Delete All History?',
                  style: TextStyle(
                    color: AdminThemeColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Sigurado ka ba nga gusto nimo i-delete ang tanang ${sessions.length} completed quiz session(s) sa history?\n\nDili na kini mabalik.',
            style: const TextStyle(
              color: AdminThemeColors.textPrimary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              style: TextButton.styleFrom(
                foregroundColor: AdminThemeColors.textMuted,
              ),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: const Text(
                'DELETE ALL',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      final firestore = FirebaseFirestore.instance;
      for (final doc in sessions) {
        final quizRef = doc.reference;
        final subcollections = [
          'scores',
          'questions',
          'join_requests',
          'participants',
          'submissions',
          'answers',
        ];
        for (final collectionName in subcollections) {
          final snapshot = await quizRef.collection(collectionName).get();
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
      }

      if (context.mounted) {
        AdminNotification.success(
          context,
          'Successfully deleted ${sessions.length} history session(s).',
        );
      }
    } catch (e) {
      if (context.mounted) {
        AdminNotification.error(
          context,
          'Failed to delete history: $e',
        );
      }
    }
  }
}

class _AdminQuizHistoryScreenState extends State<AdminQuizHistoryScreen> {
  static const Color _purple = AdminThemeColors.primary;
  static const Color _textDark = AdminThemeColors.textPrimary;
  static const Color _textMuted = AdminThemeColors.textMuted;

  @override
  void initState() {
    super.initState();
    AdminNavPersistence.savePage('quiz_history');
  }

  Future<bool> _deleteQuizSession(
    BuildContext context,
    String docId,
    String quizTitle, [
    String quizCode = '',
  ]) {
    return AdminQuizHistoryScreen._deleteQuizSession(
      context,
      docId,
      quizTitle,
      quizCode: quizCode,
    );
  }

  Future<void> _deleteAllHistory(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> sessions,
  ) {
    return AdminQuizHistoryScreen._deleteAllHistory(context, sessions);
  }

  DateTime _dateOf(Map<String, dynamic> data) {
    final raw =
        data['createdAt'] ??
        data['startTime'] ??
        data['scheduledAt'] ??
        data['date'] ??
        data['timestamp'] ??
        data['updatedAt'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw) ?? DateTime.fromMillisecondsSinceEpoch(0);
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  bool _isFinished(Map<String, dynamic> data) {
    final title = (data['title'] ??
            data['quizTitle'] ??
            data['quizName'] ??
            data['name'] ??
            '')
        .toString()
        .trim();
    if (title.isEmpty ||
        title.toLowerCase() == 'untitled quiz' ||
        title.toLowerCase() == 'untitled' ||
        title.toLowerCase() == 'no title') {
      return false;
    }
    final status = (data['status'] ?? data['state'] ?? '')
        .toString()
        .toLowerCase()
        .replaceAll(' ', '_');
    return status == 'finished' ||
        status == 'ended' ||
        status == 'completed' ||
        status == 'complete' ||
        status == 'done';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminThemeColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: kAdminAppBarHeight,
        foregroundColor: _textDark,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Back to Admin Dashboard',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            final navigator = Navigator.of(context);
            if (navigator.canPop()) {
              navigator.pop();
            } else {
              AdminNavPersistence.savePage('dashboard');
              navigator.pushAndRemoveUntil<void>(
                adminPageRoute<void>(
                  const AdminDashboard(restoreLastPage: false),
                ),
                (route) => false,
              );
            }
          },
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quiz History',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            Text(
              'View completed quiz sessions.',
              style: TextStyle(
                fontSize: 11,
                color: _textMuted,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
      body: AdminCircuitBackground(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('quiz_sessions')
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('Unable to load quiz history.'));
            }
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: _purple),
              );
            }
            final sessions =
                snapshot.data!.docs
                    .where((doc) => _isFinished(doc.data()))
                    .toList()
                  ..sort(
                    (a, b) => _dateOf(b.data()).compareTo(_dateOf(a.data())),
                  );
            if (sessions.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_rounded, size: 48, color: _purple),
                      SizedBox(height: 12),
                      Text(
                        'No quiz history yet',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _textDark,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Finished quiz sessions will appear here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _textMuted),
                      ),
                    ],
                  ),
                ),
              );
            }
            return Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: Colors.white.withValues(alpha: 0.7),
                  child: Row(
                    children: [
                      Text(
                        '${sessions.length} Completed Quiz${sessions.length == 1 ? '' : 'zes'}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _textMuted,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => _deleteAllHistory(context, sessions),
                        icon: const Icon(
                          Icons.delete_sweep_rounded,
                          size: 16,
                          color: Color(0xFFEF4444),
                        ),
                        label: const Text(
                          'Delete All',
                          style: TextStyle(
                            color: Color(0xFFEF4444),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: sessions.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 9),
                    itemBuilder: (context, index) {
                      final doc = sessions[index];
                      final data = doc.data();
                      final title =
                          (data['title'] ??
                                  data['quizTitle'] ??
                                  data['quizName'] ??
                                  data['name'] ??
                                  'Quiz')
                              .toString();
                      final code =
                          (data['quizCode'] ?? data['code'] ?? doc.id)
                              .toString();
                      final date = _dateOf(data);
                      final dateText = date.millisecondsSinceEpoch == 0
                          ? 'Date not set'
                          : '${date.day} ${_monthName(date.month)} ${date.year} • ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () async {
                            AdminNavPersistence.savePage(
                              'quiz_history_results',
                              historyQuizCode: code,
                              historyQuizTitle: title,
                              historyQuizDate: dateText,
                              historyDocId: doc.id,
                            );
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AdminFinishedQuizResultsScreen(
                                  quizCode: code,
                                  quizTitle: title,
                                  quizDate: dateText,
                                  docId: doc.id,
                                ),
                              ),
                            );
                            if (mounted) {
                              AdminNavPersistence.savePage('quiz_history');
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFE7E8EF)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AdminThemeColors.pillBg,
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child: const Icon(
                                    Icons.history_rounded,
                                    color: _purple,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: _textDark,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Code: $code',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: _textMuted,
                                          fontSize: 11,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        dateText,
                                        style: const TextStyle(
                                          color: _textMuted,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AdminThemeColors.pillBg,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: AdminThemeColors.primary.withValues(alpha: 0.25),
                                      width: 1,
                                    ),
                                  ),
                                  child: const Text(
                                    'FINISHED',
                                    style: TextStyle(
                                      color: AdminThemeColors.primary,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  tooltip: 'Delete Quiz Session',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 36,
                                    minHeight: 36,
                                  ),
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: Color(0xFFEF4444),
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    _deleteQuizSession(
                                      context,
                                      doc.id,
                                      title,
                                      code,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _monthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }
}

class _SwipeableScrollBehavior extends MaterialScrollBehavior {
  const _SwipeableScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}
