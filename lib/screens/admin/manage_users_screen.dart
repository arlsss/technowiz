import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../login_screen.dart';

import 'admin_dashboard.dart';

import 'add_question_screen.dart';

import 'question_list_screen.dart';

import 'manage_quiz_sessions_screen.dart';

import 'admin_leaderboard_screen.dart';

import 'admin_report_screen.dart';

import 'admin_sidebar.dart';
import 'admin_theme.dart';

import '../../navigation_persistence.dart';

class ManageUsersScreen extends StatefulWidget {
  const ManageUsersScreen({super.key});

  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen> {
  @override
  void initState() {
    super.initState();
    AdminNavPersistence.savePage('manage_users');
  }

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // =========================================================

  // COLORS

  // =========================================================

  static const Color primaryPurple = AdminThemeColors.primary;

  static const Color lightPurple = AdminThemeColors.pillBg;

  static const Color background = AdminThemeColors.background;

  static const Color textDark = AdminThemeColors.textPrimary;

  static const Color textGrey = AdminThemeColors.textMuted;

  static const Color border = AdminThemeColors.border;

  static const Color green = Color(0xFF16A875);

  static const Color red = Color(0xFFEF4444);

  static const Color lightRed = Color(0xFFFFEEEE);

  static const Color blue = Color(0xFF3578E5);

  // =========================================================

  // DELETE USER

  // =========================================================

  Future<void> deleteUser(String uid) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).delete();
  }

  // =========================================================

  // DELETE CONFIRMATION

  // =========================================================

  Future<void> confirmDelete(
    BuildContext context,

    String uid,

    String name,
  ) async {
    final bool confirm =
        await showDialog<bool>(
          context: context,

          builder: (dialogContext) {
            return AlertDialog(
              backgroundColor: Colors.white,

              elevation: 10,

              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),

              title: const Row(
                children: [
                  Icon(Icons.delete_outline_rounded, color: red, size: 24),

                  SizedBox(width: 10),

                  Text(
                    "Delete User",

                    style: TextStyle(
                      color: textDark,

                      fontSize: 18,

                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              content: Text(
                "Are you sure you want to delete $name?",

                style: const TextStyle(
                  color: textGrey,

                  fontSize: 13,

                  height: 1.5,
                ),
              ),

              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),

              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext, false);
                  },

                  child: const Text(
                    "Cancel",

                    style: TextStyle(
                      color: textGrey,

                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogContext, true);
                  },

                  style: ElevatedButton.styleFrom(
                    backgroundColor: red,

                    foregroundColor: Colors.white,

                    elevation: 0,

                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,

                      vertical: 11,
                    ),

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),

                  child: const Text(
                    "Delete",

                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirm) return;

    try {
      await deleteUser(uid);

      if (!context.mounted) return;

      AdminNotification.success(context, "$name deleted successfully.");
    } catch (e) {
      if (!context.mounted) return;

      AdminNotification.error(context, "Failed to delete user: $e");
    }
  }

  // =========================================================

  // ACCOUNT TYPE

  // =========================================================

  String getAccountType(Map<String, dynamic> data) {
    final role = (data['role'] ?? '').toString().trim().toLowerCase();

    final contestantType = (data['contestantType'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    if (role == 'admin') {
      return "ADMIN";
    }

    if (role == 'quiz master') {
      return "QUIZ MASTER";
    }

    if (role == 'contestant' || role == 'competitor') {
      if (contestantType == 'team') {
        return "TEAM";
      }

      return "SOLO";
    }

    return role.isEmpty ? "UNKNOWN" : role.toUpperCase();
  }

  // =========================================================

  // ROLE COLOR

  // =========================================================

  Color getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case "admin":
        return blue;

      case "quiz master":
        return primaryPurple;

      case "competitor":
      case "contestant":
        return green;

      default:
        return textGrey;
    }
  }

  // =========================================================

  // ACCOUNT TYPE COLOR

  // =========================================================

  Color getAccountTypeColor(String accountType) {
    switch (accountType.toUpperCase()) {
      case "ADMIN":
        return blue;

      case "QUIZ MASTER":
        return primaryPurple;

      case "TEAM":
        return const Color(0xFFE67E22);

      case "SOLO":
        return green;

      default:
        return textGrey;
    }
  }

  // =========================================================

  // ACCOUNT TYPE ICON

  // =========================================================

  IconData getAccountTypeIcon(String accountType) {
    switch (accountType.toUpperCase()) {
      case "ADMIN":
        return Icons.admin_panel_settings_outlined;

      case "QUIZ MASTER":
        return Icons.school_outlined;

      case "TEAM":
        return Icons.groups_outlined;

      case "SOLO":
        return Icons.person_outline_rounded;

      default:
        return Icons.person_outline_rounded;
    }
  }

  // =========================================================

  // AVATAR

  // =========================================================

  Widget userAvatar({
    required String name,

    required String role,

    double size = 40,
  }) {
    final Color roleColor = getRoleColor(role);

    String initial = "?";

    if (name.trim().isNotEmpty) {
      initial = name.trim()[0].toUpperCase();
    }

    return Container(
      width: size,

      height: size,

      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            roleColor.withValues(alpha: 0.18),
            roleColor.withValues(alpha: 0.07),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),

        shape: BoxShape.circle,

        border: Border.all(
          color: roleColor.withValues(alpha: 0.35),
          width: 1.5,
        ),

        boxShadow: [
          BoxShadow(
            color: roleColor.withValues(alpha: 0.12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),

      child: Center(
        child: Text(
          initial,

          style: TextStyle(
            color: roleColor,

            fontSize: size * .38,

            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  // =========================================================

  // ACCOUNT TYPE BADGE

  // =========================================================

  Widget accountTypeBadge(String accountType) {
    final Color color = getAccountTypeColor(accountType);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),

      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),

        borderRadius: BorderRadius.circular(20),

        border: Border.all(color: color.withValues(alpha: 0.22), width: 1),
      ),

      child: Row(
        mainAxisSize: MainAxisSize.min,

        children: [
          Icon(getAccountTypeIcon(accountType), color: color, size: 13),

          const SizedBox(width: 5),

          Flexible(
            child: Text(
              accountType,

              overflow: TextOverflow.ellipsis,

              style: TextStyle(
                color: color,

                fontSize: 10.5,

                fontWeight: FontWeight.w800,

                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================

  // STATUS

  // =========================================================

  Widget statusBadge(bool isOnline) {
    final Color color = isOnline
        ? const Color(0xFF15803D)
        : const Color(0xFF64748B);
    final Color bgColor = isOnline
        ? const Color(0xFFDCFCE7)
        : const Color(0xFFF1F5F9);
    final Color borderColor = isOnline
        ? const Color(0xFF86EFAC)
        : const Color(0xFFCBD5E1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),

      decoration: BoxDecoration(
        color: bgColor,

        borderRadius: BorderRadius.circular(20),

        border: Border.all(color: borderColor, width: 1),
      ),

      child: Row(
        mainAxisSize: MainAxisSize.min,

        children: [
          Container(
            width: 7,

            height: 7,

            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: isOnline
                  ? [
                      BoxShadow(
                        color: const Color(0xFF22C55E).withValues(alpha: 0.6),
                        blurRadius: 4,
                        offset: const Offset(0, 0),
                      ),
                    ]
                  : null,
            ),
          ),

          const SizedBox(width: 6),

          Text(
            isOnline ? "Active" : "Inactive",

            style: TextStyle(
              color: color,

              fontSize: 10.5,

              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================

  // ACTION BUTTON

  // =========================================================

  Widget actionButton({
    required IconData icon,

    required Color color,

    required VoidCallback onPressed,

    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? "",

      child: InkWell(
        borderRadius: BorderRadius.circular(10),

        onTap: onPressed,

        child: Container(
          width: 36,

          height: 36,

          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),

            borderRadius: BorderRadius.circular(10),

            border: Border.all(
              color: const Color(0xFFFCA5A5).withValues(alpha: 0.5),
              width: 1,
            ),
          ),

          child: const Icon(
            Icons.delete_outline_rounded,
            color: Color(0xFFEF4444),
            size: 18,
          ),
        ),
      ),
    );
  }

  // =========================================================

  // STAT CARD

  // =========================================================

  Widget statCard({
    required IconData icon,

    required int value,

    required String label,

    required Color color,
  }) {
    return Expanded(
      child: Container(
        height: 86,

        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),

        decoration: BoxDecoration(
          color: Colors.white,

          borderRadius: BorderRadius.circular(16),

          border: Border.all(color: color.withValues(alpha: 0.22), width: 1.2),

          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 10,
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

                    style: const TextStyle(
                      color: Color(0xFF64748B),

                      fontSize: 11,

                      fontWeight: FontWeight.w600,

                      letterSpacing: 0.1,
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

  // =========================================================

  // TEAM INFO

  // =========================================================

  Widget teamInfo({
    required String teamName,

    required List<String> teamMembers,

    bool compact = false,
  }) {
    if (teamName.trim().isEmpty && teamMembers.isEmpty) {
      return const SizedBox.shrink();
    }

    final String displayTeamName = teamName.trim().isEmpty
        ? "Unnamed Team"
        : teamName.trim();

    return Container(
      margin: EdgeInsets.only(top: compact ? 5 : 7),

      padding: EdgeInsets.all(compact ? 7 : 9),

      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F0),

        borderRadius: BorderRadius.circular(8),

        border: Border.all(color: const Color(0xFFF2D7B7)),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Row(
            children: [
              const Icon(
                Icons.groups_outlined,

                color: Color(0xFFE67E22),

                size: 14,
              ),

              const SizedBox(width: 5),

              Expanded(
                child: Text(
                  displayTeamName,

                  maxLines: 1,

                  overflow: TextOverflow.ellipsis,

                  style: const TextStyle(
                    color: Color(0xFF9A5515),

                    fontSize: 10,

                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),

              if (teamMembers.isNotEmpty)
                Text(
                  "${teamMembers.length} member${teamMembers.length == 1 ? '' : 's'}",

                  style: const TextStyle(
                    color: textGrey,

                    fontSize: 9,

                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),

          if (teamMembers.isNotEmpty) ...[
            const SizedBox(height: 5),

            ...teamMembers.map(
              (member) => Padding(
                padding: const EdgeInsets.only(top: 2),

                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    const Text(
                      "• ",

                      style: TextStyle(
                        color: Color(0xFFE67E22),

                        fontSize: 10,

                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    Expanded(
                      child: Text(
                        member,

                        style: const TextStyle(color: textGrey, fontSize: 9),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // =========================================================

  // GET TEAM MEMBERS

  // =========================================================

  List<String> getTeamMembers(Map<String, dynamic> data) {
    final rawMembers = data['teamMembers'];

    if (rawMembers is! List) {
      return [];
    }

    return rawMembers
        .map((member) => member.toString().trim())
        .where((member) => member.isNotEmpty)
        .toList();
  }

  // =========================================================

  // DESKTOP USER ROW

  // =========================================================

  Widget desktopUserRow({
    required BuildContext context,

    required String uid,

    required String name,

    required String email,

    required String role,

    required String accountType,

    required bool isOnline,

    required String teamName,

    required List<String> teamMembers,
  }) {
    final bool isTeam = accountType == "TEAM";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),

      decoration: const BoxDecoration(
        color: Colors.white,

        border: Border(bottom: BorderSide(color: border, width: 1)),
      ),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          // USER
          Expanded(
            flex: 4,

            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                userAvatar(name: name, role: role, size: 40),

                const SizedBox(width: 11),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      Text(
                        name,

                        maxLines: 1,

                        overflow: TextOverflow.ellipsis,

                        style: const TextStyle(
                          color: textDark,

                          fontSize: 12,

                          fontWeight: FontWeight.w700,
                        ),
                      ),

                      const SizedBox(height: 3),

                      Text(
                        email,

                        maxLines: 1,

                        overflow: TextOverflow.ellipsis,

                        style: const TextStyle(color: textGrey, fontSize: 10),
                      ),

                      if (isTeam)
                        teamInfo(
                          teamName: teamName,

                          teamMembers: teamMembers,

                          compact: true,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ACCOUNT TYPE
          Expanded(
            flex: 2,

            child: Padding(
              padding: const EdgeInsets.only(top: 2),

              child: Align(
                alignment: Alignment.topLeft,

                child: accountTypeBadge(accountType),
              ),
            ),
          ),

          // STATUS
          Expanded(
            flex: 2,

            child: Padding(
              padding: const EdgeInsets.only(top: 2),

              child: Align(
                alignment: Alignment.topLeft,

                child: statusBadge(isOnline),
              ),
            ),
          ),

          // JOINED
          const Expanded(
            flex: 2,

            child: Padding(
              padding: EdgeInsets.only(top: 7),

              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,

                    color: textGrey,

                    size: 14,
                  ),

                  SizedBox(width: 7),

                  Text(
                    "Registered",

                    style: TextStyle(color: textGrey, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),

          // ACTIONS
          SizedBox(
            width: 82,

            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,

              children: [
                actionButton(
                  icon: Icons.edit_outlined,

                  color: primaryPurple,

                  tooltip: "Edit User",

                  onPressed: () {},
                ),

                const SizedBox(width: 6),

                actionButton(
                  icon: Icons.delete_outline_rounded,

                  color: red,

                  tooltip: "Delete User",

                  onPressed: () {
                    confirmDelete(context, uid, name);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================

  // MOBILE USER CARD

  // =========================================================

  Widget mobileUserCard({
    required BuildContext context,

    required String uid,

    required String name,

    required String email,

    required String role,

    required String accountType,

    required bool isOnline,

    required String teamName,

    required List<String> teamMembers,
  }) {
    final bool isTeam = accountType == "TEAM";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),

      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(16),

        border: Border.all(
          color: AdminThemeColors.primary.withValues(alpha: 0.12),
          width: 1,
        ),

        boxShadow: [
          BoxShadow(
            color: AdminThemeColors.primary.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),

      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,

            children: [
              userAvatar(name: name, role: role, size: 46),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Text(
                      name,

                      maxLines: 1,

                      overflow: TextOverflow.ellipsis,

                      style: const TextStyle(
                        color: textDark,

                        fontSize: 14,

                        fontWeight: FontWeight.w800,

                        letterSpacing: -0.2,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      email,

                      maxLines: 1,

                      overflow: TextOverflow.ellipsis,

                      style: const TextStyle(
                        color: Color(0xFF64748B),

                        fontSize: 11,

                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              actionButton(
                icon: Icons.delete_outline_rounded,

                color: red,

                tooltip: "Delete User",

                onPressed: () {
                  confirmDelete(context, uid, name);
                },
              ),
            ],
          ),

          if (isTeam) teamInfo(teamName: teamName, teamMembers: teamMembers),

          const SizedBox(height: 12),

          Container(
            height: 1,
            color: AdminThemeColors.primary.withValues(alpha: 0.08),
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(child: accountTypeBadge(accountType)),

              const SizedBox(width: 8),

              statusBadge(isOnline),
            ],
          ),
        ],
      ),
    );
  }

  // =========================================================

  // EMPTY

  // =========================================================

  Widget emptyUsers() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(35),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            Container(
              width: 70,

              height: 70,

              decoration: BoxDecoration(
                color: lightPurple,

                borderRadius: BorderRadius.circular(18),
              ),

              child: const Icon(
                Icons.people_outline_rounded,

                color: primaryPurple,

                size: 34,
              ),
            ),

            const SizedBox(height: 15),

            const Text(
              "No Users Found",

              style: TextStyle(
                color: textDark,

                fontSize: 18,

                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 5),

            const Text(
              "Registered users will appear here.",

              style: TextStyle(color: textGrey, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================

  // ERROR

  // =========================================================

  Widget errorView(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(25),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            Container(
              width: 65,

              height: 65,

              decoration: BoxDecoration(
                color: lightRed,

                borderRadius: BorderRadius.circular(16),
              ),

              child: const Icon(
                Icons.error_outline_rounded,

                color: red,

                size: 34,
              ),
            ),

            const SizedBox(height: 14),

            const Text(
              "Unable to Load Users",

              style: TextStyle(
                color: textDark,

                fontSize: 18,

                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 7),

            Text(
              "$error",

              textAlign: TextAlign.center,

              style: const TextStyle(color: textGrey, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSidebarDestination(
    BuildContext context,
    String destination,
  ) async {
    // Keep the same saved-page keys used by the existing navigation.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('technowiz_admin_last_page', destination);

    if (!context.mounted) return;

    final Widget page;
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
      case 'leaderboard':
        page = const AdminLeaderboardScreen();
        break;
      case 'reports':
        page = const AdminReportScreen();
        break;
      default:
        return;
    }

    Navigator.of(
      context,
    ).pushReplacement(adminPageRoute<void>(page));
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
                      // Close the profile sheet first, then sign out and clear
                      // the protected admin pages from the navigation stack.
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

  Widget _buildNavigationDrawer(BuildContext context) {
    return AdminSidebar(
      currentPage: 'manage_users',
      onDestinationSelected: (destination) {
        _handleSidebarDestination(context, destination);
      },
      onProfileTap: () => _showProfileMenu(context),
    );
  }

  // BUILD

  // =========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: background,
      appBar: buildAdminStandardAppBar(
        context: context,
        badgeText: 'Manage Users',
        subtitle: 'View and manage registered users and their account types.',
        onMenuPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
      ),
      endDrawer: _buildNavigationDrawer(context),
      endDrawerEnableOpenDragGesture: true,
      body: AdminCircuitBackground(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double width = constraints.maxWidth;

              final bool isMobile = width < 900;

              final double horizontalPadding = width < 360
                  ? 8
                  : width < 600
                  ? 12
                  : width < 900
                  ? 16
                  : width < 1200
                  ? 22
                  : 28;

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .snapshots(),

                builder: (context, snapshot) {
                  // =================================================

                  // LOADING

                  // =================================================

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: primaryPurple,

                        strokeWidth: 2.5,
                      ),
                    );
                  }

                  // =================================================

                  // ERROR

                  // =================================================

                  if (snapshot.hasError) {
                    return errorView(snapshot.error!);
                  }

                  final users = snapshot.data?.docs ?? [];

                  // =================================================

                  // EMPTY

                  // =================================================

                  if (users.isEmpty) {
                    return emptyUsers();
                  }

                  // =================================================

                  // USER COUNTS

                  // =================================================

                  int soloUsers = 0;

                  int teamUsers = 0;

                  int quizMasters = 0;

                  int admins = 0;

                  for (final user in users) {
                    final data = user.data();

                    final accountType = getAccountType(data);

                    if (accountType == "SOLO") {
                      soloUsers++;
                    } else if (accountType == "TEAM") {
                      teamUsers++;
                    } else if (accountType == "QUIZ MASTER") {
                      quizMasters++;
                    } else if (accountType == "ADMIN") {
                      admins++;
                    }
                  }

                  // =================================================

                  // MAIN

                  // =================================================

                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,

                      isMobile ? 10 : 14,

                      horizontalPadding,

                      30,
                    ),

                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1200),

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            // =================================================

                            // STATISTICS

                            // =================================================
                            if (isMobile)
                              Column(
                                children: [
                                  Row(
                                    children: [
                                      statCard(
                                        icon: Icons.person_outline,

                                        value: soloUsers,

                                        label: "Solo",

                                        color: green,
                                      ),

                                      const SizedBox(width: 9),

                                      statCard(
                                        icon: Icons.groups_outlined,

                                        value: teamUsers,

                                        label: "Teams",

                                        color: const Color(0xFFE67E22),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 9),

                                  Row(
                                    children: [
                                      statCard(
                                        icon: Icons.school_outlined,

                                        value: quizMasters,

                                        label: "Quiz Masters",

                                        color: primaryPurple,
                                      ),

                                      const SizedBox(width: 9),

                                      statCard(
                                        icon:
                                            Icons.admin_panel_settings_outlined,

                                        value: admins,

                                        label: "Admins",

                                        color: blue,
                                      ),
                                    ],
                                  ),
                                ],
                              )
                            else
                              Row(
                                children: [
                                  statCard(
                                    icon: Icons.person_outline,

                                    value: soloUsers,

                                    label: "Solo",

                                    color: green,
                                  ),

                                  const SizedBox(width: 12),

                                  statCard(
                                    icon: Icons.groups_outlined,

                                    value: teamUsers,

                                    label: "Teams",

                                    color: const Color(0xFFE67E22),
                                  ),

                                  const SizedBox(width: 12),

                                  statCard(
                                    icon: Icons.school_outlined,

                                    value: quizMasters,

                                    label: "Quiz Masters",

                                    color: primaryPurple,
                                  ),

                                  const SizedBox(width: 12),

                                  statCard(
                                    icon: Icons.admin_panel_settings_outlined,

                                    value: admins,

                                    label: "Admins",

                                    color: blue,
                                  ),
                                ],
                              ),

                            const SizedBox(height: 18),

                            // =================================================

                            // USERS CARD

                            // =================================================
                            Container(
                              width: double.infinity,

                              decoration: BoxDecoration(
                                color: Colors.white,

                                borderRadius: BorderRadius.circular(16),

                                border: Border.all(
                                  color: AdminThemeColors.primary.withValues(
                                    alpha: 0.12,
                                  ),
                                  width: 1,
                                ),

                                boxShadow: [
                                  BoxShadow(
                                    color: AdminThemeColors.primary.withValues(
                                      alpha: 0.05,
                                    ),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),

                              child: Column(
                                children: [
                                  // USERS HEADER
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      17,

                                      15,

                                      17,

                                      13,
                                    ),

                                    child: Row(
                                      children: [
                                        Container(
                                          width: 4,

                                          height: 23,

                                          decoration: BoxDecoration(
                                            color: primaryPurple,

                                            borderRadius: BorderRadius.circular(
                                              5,
                                            ),
                                          ),
                                        ),

                                        const SizedBox(width: 9),

                                        const Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,

                                            children: [
                                              Text(
                                                "Users",

                                                style: TextStyle(
                                                  color: textDark,

                                                  fontSize: 16,

                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),

                                              SizedBox(height: 2),

                                              Text(
                                                "Manage registered users and account types",

                                                style: TextStyle(
                                                  color: textGrey,

                                                  fontSize: 10,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,

                                            vertical: 6,
                                          ),

                                          decoration: BoxDecoration(
                                            color: lightPurple,

                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),

                                            border: Border.all(
                                              color: primaryPurple.withValues(
                                                alpha: 0.22,
                                              ),
                                              width: 1,
                                            ),
                                          ),

                                          child: Text(
                                            "${users.length} Users",

                                            style: const TextStyle(
                                              color: primaryPurple,

                                              fontSize: 10.5,

                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // =================================================

                                  // DESKTOP TABLE HEADER

                                  // =================================================
                                  if (!isMobile)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,

                                        vertical: 10,
                                      ),

                                      color: const Color(0xFFF8F9FC),

                                      child: const Row(
                                        children: [
                                          Expanded(
                                            flex: 4,

                                            child: Text(
                                              "USER / TEAM",

                                              style: TextStyle(
                                                color: textGrey,

                                                fontSize: 9,

                                                fontWeight: FontWeight.bold,

                                                letterSpacing: .7,
                                              ),
                                            ),
                                          ),

                                          Expanded(
                                            flex: 2,

                                            child: Text(
                                              "ACCOUNT TYPE",

                                              style: TextStyle(
                                                color: textGrey,

                                                fontSize: 9,

                                                fontWeight: FontWeight.bold,

                                                letterSpacing: .7,
                                              ),
                                            ),
                                          ),

                                          Expanded(
                                            flex: 2,

                                            child: Text(
                                              "STATUS",

                                              style: TextStyle(
                                                color: textGrey,

                                                fontSize: 9,

                                                fontWeight: FontWeight.bold,

                                                letterSpacing: .7,
                                              ),
                                            ),
                                          ),

                                          Expanded(
                                            flex: 2,

                                            child: Text(
                                              "JOINED",

                                              style: TextStyle(
                                                color: textGrey,

                                                fontSize: 9,

                                                fontWeight: FontWeight.bold,

                                                letterSpacing: .7,
                                              ),
                                            ),
                                          ),

                                          SizedBox(
                                            width: 82,

                                            child: Text(
                                              "ACTION",

                                              textAlign: TextAlign.end,

                                              style: TextStyle(
                                                color: textGrey,

                                                fontSize: 9,

                                                fontWeight: FontWeight.bold,

                                                letterSpacing: .7,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                  // =================================================

                                  // MOBILE USERS

                                  // =================================================
                                  if (isMobile)
                                    Padding(
                                      padding: const EdgeInsets.all(12),

                                      child: Column(
                                        children: users.map((user) {
                                          final data = user.data();

                                          final name =
                                              (data['name'] ?? 'No Name')
                                                  .toString();

                                          final email =
                                              (data['email'] ?? 'No Email')
                                                  .toString();

                                          final role =
                                              (data['role'] ?? 'No Role')
                                                  .toString();

                                          final accountType = getAccountType(
                                            data,
                                          );

                                          final isOnline =
                                              data['isOnline'] == true;

                                          final teamName =
                                              (data['teamName'] ?? '')
                                                  .toString();

                                          final teamMembers = getTeamMembers(
                                            data,
                                          );

                                          return mobileUserCard(
                                            context: context,

                                            uid: user.id,

                                            name: name,

                                            email: email,

                                            role: role,

                                            accountType: accountType,

                                            isOnline: isOnline,

                                            teamName: teamName,

                                            teamMembers: teamMembers,
                                          );
                                        }).toList(),
                                      ),
                                    )
                                  // =================================================
                                  // DESKTOP USERS
                                  // =================================================
                                  else
                                    Column(
                                      children: users.map((user) {
                                        final data = user.data();

                                        final name = (data['name'] ?? 'No Name')
                                            .toString();

                                        final email =
                                            (data['email'] ?? 'No Email')
                                                .toString();

                                        final role = (data['role'] ?? 'No Role')
                                            .toString();

                                        final accountType = getAccountType(
                                          data,
                                        );

                                        final isOnline =
                                            data['isOnline'] == true;

                                        final teamName =
                                            (data['teamName'] ?? '').toString();

                                        final teamMembers = getTeamMembers(
                                          data,
                                        );

                                        return desktopUserRow(
                                          context: context,

                                          uid: user.id,

                                          name: name,

                                          email: email,

                                          role: role,

                                          accountType: accountType,

                                          isOnline: isOnline,

                                          teamName: teamName,

                                          teamMembers: teamMembers,
                                        );
                                      }).toList(),
                                    ),

                                  // =================================================

                                  // FOOTER

                                  // =================================================
                                  Container(
                                    width: double.infinity,

                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 17,

                                      vertical: 11,
                                    ),

                                    decoration: const BoxDecoration(
                                      color: Color(0xFFFAFBFE),

                                      border: Border(
                                        top: BorderSide(color: border),
                                      ),
                                    ),

                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            "Showing ${users.length} registered user${users.length == 1 ? '' : 's'}",

                                            style: const TextStyle(
                                              color: textGrey,

                                              fontSize: 10,
                                            ),
                                          ),
                                        ),

                                        const Text(
                                          "TechNoWiz",

                                          style: TextStyle(
                                            color: textGrey,

                                            fontSize: 10,

                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 18),

                            const Center(
                              child: Text(
                                "TechNoWiz Quiz System",

                                style: TextStyle(color: textGrey, fontSize: 9),
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
          ),
        ),
    );
  }
}
