import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'admin_dashboard.dart';

import 'add_question_screen.dart';

import 'question_list_screen.dart';

import 'manage_quiz_sessions_screen.dart';

import 'admin_leaderboard_screen.dart';

import 'admin_report_screen.dart';

import 'admin_sidebar.dart';
import 'admin_theme.dart';

import '../../navigation_persistence.dart';
import '../../services/user_presence_service.dart';

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

  /// Filter active on the user list: 'ALL', 'SOLO', 'TEAM', 'QUIZ MASTER', 'ADMIN'.
  String _selectedFilter = 'ALL';

  void _toggleFilter(String filterKey) {
    setState(() {
      if (_selectedFilter == filterKey) {
        _selectedFilter = 'ALL';
      } else {
        _selectedFilter = filterKey;
      }
    });
  }

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

  // USER BLOCKING & PROFILE HELPERS

  // =========================================================

  bool isUserBlocked(Map<String, dynamic> data) {
    if (data['isBlocked'] == true) return true;
    final status = (data['status'] ?? '').toString().trim().toLowerCase();
    return status == 'blocked';
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return "Unknown";
    DateTime? dt;
    if (raw is Timestamp) {
      dt = raw.toDate();
    } else if (raw is DateTime) {
      dt = raw;
    } else if (raw is String) {
      dt = DateTime.tryParse(raw);
    }
    if (dt == null) return "Unknown";

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
    final month = months[dt.month - 1];
    final day = dt.day;
    final year = dt.year;
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return "$month $day, $year • $hour:$minute $ampm";
  }

  Future<void> confirmToggleBlock(
    BuildContext context,
    String uid,
    String name,
    bool isCurrentlyBlocked, {
    String roleLabel = "User",
  }) async {
    final bool willBlock = !isCurrentlyBlocked;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          elevation: 10,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Row(
            children: [
              Icon(
                willBlock ? Icons.block_rounded : Icons.lock_open_rounded,
                color: willBlock ? red : green,
                size: 24,
              ),
              const SizedBox(width: 10),
              Text(
                willBlock ? "Block $roleLabel" : "Unblock $roleLabel",
                style: const TextStyle(
                  color: textDark,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Text(
            willBlock
                ? "Are you sure you want to block $name? This $roleLabel will be logged out and cannot access TechNoWiz until unblocked."
                : "Are you sure you want to unblock $name? This $roleLabel will be permitted to log in and use TechNoWiz again.",
            style: const TextStyle(
              color: textGrey,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text(
                "Cancel",
                style: TextStyle(color: textGrey, fontWeight: FontWeight.w600),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: willBlock ? red : green,
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
              child: Text(
                willBlock ? "Block User" : "Unblock User",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'isBlocked': willBlock,
        'status': willBlock ? 'blocked' : 'Offline',
        'blockedAt': willBlock ? FieldValue.serverTimestamp() : null,
      });

      if (!context.mounted) return;
      AdminNotification.success(
        context,
        willBlock
            ? "$name has been blocked."
            : "$name has been unblocked successfully.",
      );
    } catch (e) {
      if (!context.mounted) return;
      AdminNotification.error(
        context,
        "Failed to update user block status: $e",
      );
    }
  }

  Widget blockedBadge({bool compact = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFFCA5A5),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.block_rounded,
            color: const Color(0xFFDC2626),
            size: compact ? 10 : 12,
          ),
          SizedBox(width: compact ? 3 : 5),
          Text(
            "Blocked",
            style: TextStyle(
              color: const Color(0xFFDC2626),
              fontSize: compact ? 9.5 : 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileInfoTile({
    required IconData icon,
    required String title,
    required String value,
    Color? iconColor,
  }) {
    final effectiveColor = iconColor ?? primaryPurple;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: effectiveColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: effectiveColor.withValues(alpha: 0.22),
              ),
            ),
            child: Icon(icon, color: effectiveColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _teamMembersCard(List<String> members) {
    if (members.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F0),
        borderRadius: BorderRadius.circular(14),
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
                size: 16,
              ),
              const SizedBox(width: 6),
              const Text(
                "Team Members",
                style: TextStyle(
                  color: Color(0xFF9A5515),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE67E22).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "${members.length} members",
                  style: const TextStyle(
                    color: Color(0xFF9A5515),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...members.map(
            (m) => Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                children: [
                  const Text(
                    "• ",
                    style: TextStyle(
                      color: Color(0xFFE67E22),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      m,
                      style: const TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showUserDetailsDialog(
    BuildContext context,
    String uid,
    Map<String, dynamic> initialData,
  ) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (dialogCtx) {
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .snapshots(),
          builder: (context, snapshot) {
            final data = snapshot.hasData && snapshot.data!.exists
                ? (snapshot.data!.data() ?? initialData)
                : initialData;

            final String name = (data['name'] ?? 'User').toString().trim();
            final String email = (data['email'] ?? 'No email').toString().trim();
            final String role = (data['role'] ?? 'User').toString().trim();
            final String rawRole = role.toLowerCase();
            final String accountType = getAccountType(data);
            final bool isQuizMaster = accountType == 'QUIZ MASTER' ||
                rawRole == 'quizmaster' ||
                rawRole.contains('quiz');
            final bool isAdmin =
                accountType == 'ADMIN' || rawRole == 'admin';
            final bool isContestant = !isQuizMaster && !isAdmin;

            final String roleLabel = isQuizMaster
                ? "Quiz Master"
                : (isAdmin ? "Admin" : "Contestant");

            final String headerBadgeTitle = isQuizMaster
                ? "QUIZ MASTER PROFILE DETAILS"
                : (isAdmin
                    ? "ADMIN PROFILE DETAILS"
                    : "CONTESTANT PROFILE DETAILS");

            final String sectionTitle = isQuizMaster
                ? "Quiz Master Information"
                : (isAdmin
                    ? "Administrator Information"
                    : "Contestant Information");

            final bool isTeam = isContestant && accountType == 'TEAM';
            final String teamName = (data['teamName'] ?? '').toString().trim();
            final List<String> teamMembers = getTeamMembers(data);
            final bool isBlocked = isUserBlocked(data);
            final bool isOnline = UserPresenceService.isUserActive(
              data,
              docUid: uid,
            );

            final String schoolName = (data['schoolName'] ??
                    data['address'] ??
                    data['school'] ??
                    '')
                .toString()
                .trim();
            final String educationLevel =
                (data['educationLevel'] ?? '').toString().trim();
            final String gradeLevel =
                (data['gradeLevel'] ?? '').toString().trim();
            final String contactNumber = (data['contactNumber'] ??
                    data['phone'] ??
                    data['contact'] ??
                    '')
                .toString()
                .trim();
            final String createdAtStr = _formatDate(data['createdAt']);

            final Color roleColor = getRoleColor(role);

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 560,
                  maxHeight: 760,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 28,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // HEADER WITH GRADIENT
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(20, 18, 16, 20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isBlocked
                                  ? const [
                                      Color(0xFF7F1D1D),
                                      Color(0xFF991B1B),
                                      Color(0xFFDC2626),
                                    ]
                                  : [
                                      const Color(0xFF4C1D95),
                                      const Color(0xFF6D28D9),
                                      primaryPurple,
                                    ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.white
                                              .withValues(alpha: 0.2),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: const Icon(
                                          Icons.badge_outlined,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        headerBadgeTitle,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                    ],
                                  ),
                                  IconButton(
                                    tooltip: "Close",
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    icon: Container(
                                      padding: const EdgeInsets.all(5),
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.2),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close_rounded,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                    onPressed: () => Navigator.pop(dialogCtx),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  userAvatar(
                                    name: (isTeam && teamName.isNotEmpty)
                                        ? teamName
                                        : name,
                                    role: role,
                                    size: 64,
                                    photoUrl: data['photoUrl']?.toString(),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (isTeam && teamName.isNotEmpty)
                                              ? teamName
                                              : name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: -0.3,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          email,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFFE9D5FF),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: [
                                            accountTypeBadge(accountType),
                                            statusBadge(isOnline),
                                            if (isBlocked) blockedBadge(),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // BODY CONTENT (SCROLLABLE)
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // BLOCKED WARNING BANNER
                                if (isBlocked) ...[
                                  Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(bottom: 16),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEF2F2),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFFFCA5A5),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.block_rounded,
                                          color: Color(0xFFDC2626),
                                          size: 20,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            "This $roleLabel is BLOCKED. They cannot log in or access TechNoWiz until unblocked.",
                                            style: const TextStyle(
                                              color: Color(0xFF991B1B),
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],

                                // PROFILE INFORMATION CARDS
                                Text(
                                  sectionTitle,
                                  style: const TextStyle(
                                    color: textDark,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                                const SizedBox(height: 10),

                                if (isQuizMaster || isAdmin) ...[
                                  _profileInfoTile(
                                    icon: Icons.person_outline_rounded,
                                    title: "Full Name",
                                    value: name.isNotEmpty ? name : "Not set",
                                    iconColor: roleColor,
                                  ),

                                  _profileInfoTile(
                                    icon: Icons.mail_outline_rounded,
                                    title: "Email Address",
                                    value: email.isNotEmpty ? email : "No email",
                                    iconColor: blue,
                                  ),

                                  _profileInfoTile(
                                    icon: isQuizMaster
                                        ? Icons.school_outlined
                                        : Icons.admin_panel_settings_outlined,
                                    title: "Assigned Role",
                                    value: isQuizMaster
                                        ? "Official Quiz Master Host"
                                        : "System Administrator",
                                    iconColor: roleColor,
                                  ),

                                  if (schoolName.isNotEmpty &&
                                      schoolName != "Not yet set")
                                    _profileInfoTile(
                                      icon: Icons.business_outlined,
                                      title: "School / Institution",
                                      value: schoolName,
                                      iconColor: primaryPurple,
                                    ),

                                  if (contactNumber.isNotEmpty &&
                                      contactNumber != "Not yet set")
                                    _profileInfoTile(
                                      icon: Icons.phone_outlined,
                                      title: "Contact Number",
                                      value: contactNumber,
                                      iconColor: green,
                                    ),

                                  _profileInfoTile(
                                    icon: Icons.calendar_today_outlined,
                                    title: "Date Registered",
                                    value: createdAtStr,
                                    iconColor: textGrey,
                                  ),
                                ] else ...[
                                  if (!isTeam)
                                    _profileInfoTile(
                                      icon: Icons.person_outline_rounded,
                                      title: "Full Name",
                                      value: name.isNotEmpty ? name : "Not set",
                                      iconColor: roleColor,
                                    ),

                                  _profileInfoTile(
                                    icon: Icons.school_outlined,
                                    title: "School / Institution",
                                    value: schoolName.isNotEmpty
                                        ? schoolName
                                        : "Not yet set",
                                    iconColor: primaryPurple,
                                  ),

                                  _profileInfoTile(
                                    icon: Icons.groups_outlined,
                                    title: "Participation Type",
                                    value: accountType,
                                    iconColor: const Color(0xFFE67E22),
                                  ),

                                  if (isTeam) ...[
                                    _profileInfoTile(
                                      icon: Icons.badge_outlined,
                                      title: "Team Name",
                                      value: teamName.isNotEmpty
                                          ? teamName
                                          : "Not yet set",
                                      iconColor: const Color(0xFFE67E22),
                                    ),
                                    _teamMembersCard(teamMembers),
                                  ],

                                  _profileInfoTile(
                                    icon: Icons.menu_book_outlined,
                                    title: "Education Level",
                                    value: educationLevel.isNotEmpty
                                        ? educationLevel
                                        : "Not yet set",
                                    iconColor: blue,
                                  ),

                                  _profileInfoTile(
                                    icon: Icons.grade_outlined,
                                    title: "Grade / Year Level",
                                    value: gradeLevel.isNotEmpty
                                        ? gradeLevel
                                        : "Not yet set",
                                    iconColor: primaryPurple,
                                  ),

                                  if (contactNumber.isNotEmpty &&
                                      contactNumber != "Not yet set")
                                    _profileInfoTile(
                                      icon: Icons.phone_outlined,
                                      title: "Contact Number",
                                      value: contactNumber,
                                      iconColor: green,
                                    ),

                                  _profileInfoTile(
                                    icon: Icons.calendar_today_outlined,
                                    title: "Date Registered",
                                    value: createdAtStr,
                                    iconColor: textGrey,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),

                        // ACTIONS FOOTER
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF8FAFC),
                            border: Border(
                              top: BorderSide(color: border, width: 1),
                            ),
                          ),
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(dialogCtx);
                                  confirmDelete(context, uid, name);
                                },
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 16,
                                  color: red,
                                ),
                                label: const Text(
                                  "Delete User",
                                  style: TextStyle(
                                    color: red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: Color(0xFFFCA5A5),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(dialogCtx),
                                    child: const Text(
                                      "Close",
                                      style: TextStyle(
                                        color: textGrey,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: () async {
                                      await confirmToggleBlock(
                                        context,
                                        uid,
                                        name,
                                        isBlocked,
                                        roleLabel: roleLabel,
                                      );
                                    },
                                    icon: Icon(
                                      isBlocked
                                          ? Icons.lock_open_rounded
                                          : Icons.block_rounded,
                                      size: 16,
                                    ),
                                    label: Text(
                                      isBlocked
                                          ? "Unblock $roleLabel"
                                          : "Block $roleLabel",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isBlocked ? green : red,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 11,
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
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // =========================================================

  // ACCOUNT TYPE

  // =========================================================

  String getAccountType(Map<String, dynamic> data) {
    final rawRole = (data['role'] ?? '').toString().trim().toLowerCase();
    final cleanRole = rawRole.replaceAll(RegExp(r'[\s_-]+'), '');

    final contestantType = (data['contestantType'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    final isTeam = data['isTeam'] == true ||
        contestantType == 'team' ||
        (data['teamName'] != null &&
            data['teamName'].toString().trim().isNotEmpty);

    if (cleanRole == 'admin') {
      return "ADMIN";
    }

    if (cleanRole == 'quizmaster' ||
        cleanRole.contains('quizmaster') ||
        rawRole.contains('quiz')) {
      return "QUIZ MASTER";
    }

    if (cleanRole == 'contestant' ||
        cleanRole == 'competitor' ||
        cleanRole.isEmpty) {
      if (isTeam) {
        return "TEAM";
      }

      return "SOLO";
    }

    if (cleanRole == 'team' || isTeam) {
      return "TEAM";
    }

    if (cleanRole == 'solo') {
      return "SOLO";
    }

    return rawRole.isEmpty ? "UNKNOWN" : rawRole.toUpperCase();
  }

  // =========================================================

  // ROLE COLOR

  // =========================================================

  Color getRoleColor(String role) {
    final cleanRole = role.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
    if (cleanRole == 'admin') {
      return blue;
    }
    if (cleanRole == 'quizmaster' || cleanRole.contains('quiz')) {
      return primaryPurple;
    }
    if (cleanRole == 'competitor' || cleanRole == 'contestant') {
      return green;
    }
    return textGrey;
  }

  // =========================================================

  // ACCOUNT TYPE COLOR

  // =========================================================

  Color getAccountTypeColor(String accountType) {
    final cleanType = accountType.toUpperCase().replaceAll(RegExp(r'[\s_-]+'), '');
    if (cleanType == 'ADMIN') {
      return blue;
    }
    if (cleanType == 'QUIZMASTER' || cleanType.contains('QUIZ')) {
      return primaryPurple;
    }
    if (cleanType == 'TEAM') {
      return const Color(0xFFE67E22);
    }
    if (cleanType == 'SOLO') {
      return green;
    }
    return textGrey;
  }

  // =========================================================

  // ACCOUNT TYPE ICON

  // =========================================================

  IconData getAccountTypeIcon(String accountType) {
    final cleanType = accountType.toUpperCase().replaceAll(RegExp(r'[\s_-]+'), '');
    if (cleanType == 'ADMIN') {
      return Icons.admin_panel_settings_outlined;
    }
    if (cleanType == 'QUIZMASTER' || cleanType.contains('QUIZ')) {
      return Icons.school_outlined;
    }
    if (cleanType == 'TEAM') {
      return Icons.groups_outlined;
    }
    if (cleanType == 'SOLO') {
      return Icons.person_outline_rounded;
    }
    return Icons.person_outline_rounded;
  }

  // =========================================================

  // AVATAR

  // =========================================================

  Widget userAvatar({
    required String name,
    required String role,
    double size = 40,
    String? photoUrl,
  }) {
    final Color roleColor = getRoleColor(role);

    String initial = "?";

    if (name.trim().isNotEmpty) {
      initial = name.trim()[0].toUpperCase();
    }

    final bool hasValidPhoto = photoUrl != null &&
        photoUrl.trim().isNotEmpty &&
        (photoUrl.startsWith('http://') || photoUrl.startsWith('https://'));

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
        image: hasValidPhoto
            ? DecorationImage(
                image: NetworkImage(photoUrl.trim()),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: hasValidPhoto
          ? null
          : Center(
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
            isOnline ? "Active" : "Offline",

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
    Color? bgColor,
    Color? borderColor,
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
            color: bgColor ?? color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: borderColor ?? color.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Icon(
            icon,
            color: color,
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
    String? filterKey,
    VoidCallback? onTap,
    bool isSelected = false,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 86,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? color.withValues(alpha: 0.08) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? color : color.withValues(alpha: 0.22),
                width: isSelected ? 2.0 : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: isSelected
                      ? color.withValues(alpha: 0.24)
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                          if (isSelected)
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 11,
                              ),
                            ),
                        ],
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
    required bool isBlocked,
    required Map<String, dynamic> rawData,
  }) {
    final bool isTeam = accountType == "TEAM";
    final bool hasTeamName = isTeam && teamName.trim().isNotEmpty;
    final String displayName = hasTeamName ? teamName.trim() : name;

    return Material(
      color: isBlocked ? const Color(0xFFFFF8F8) : Colors.white,
      child: InkWell(
        onTap: () {
          _showUserDetailsDialog(context, uid, rawData);
        },
        hoverColor: primaryPurple.withValues(alpha: 0.04),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: const BorderSide(color: border, width: 1),
              left: isBlocked
                  ? const BorderSide(color: Color(0xFFEF4444), width: 3.5)
                  : BorderSide.none,
            ),
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
                    userAvatar(
                      name: displayName,
                      role: role,
                      size: 40,
                      photoUrl: rawData['photoUrl']?.toString(),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
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
                                    color: textDark,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (isBlocked) ...[
                                const SizedBox(width: 6),
                                blockedBadge(compact: true),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: textGrey,
                              fontSize: 10,
                            ),
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
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        statusBadge(isOnline),
                        if (isBlocked) blockedBadge(compact: true),
                      ],
                    ),
                  ),
                ),
              ),

              // JOINED
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        color: textGrey,
                        size: 14,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          _formatDate(rawData['createdAt']),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: textGrey, fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
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
    required bool isBlocked,
    required Map<String, dynamic> rawData,
  }) {
    final bool isTeam = accountType == "TEAM";
    final bool hasTeamName = isTeam && teamName.trim().isNotEmpty;
    final String displayName = hasTeamName ? teamName.trim() : name;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          _showUserDetailsDialog(context, uid, rawData);
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isBlocked ? const Color(0xFFFFF8F8) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isBlocked
                  ? const Color(0xFFFCA5A5)
                  : AdminThemeColors.primary.withValues(alpha: 0.12),
              width: isBlocked ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isBlocked
                    ? const Color(0xFFEF4444).withValues(alpha: 0.08)
                    : AdminThemeColors.primary.withValues(alpha: 0.05),
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
                  userAvatar(
                    name: displayName,
                    role: role,
                    size: 46,
                    photoUrl: rawData['photoUrl']?.toString(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
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
                                  color: textDark,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            if (isBlocked) ...[
                              const SizedBox(width: 6),
                              blockedBadge(compact: true),
                            ],
                          ],
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
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    "Click to view profile",
                    style: TextStyle(
                      color: primaryPurple.withValues(alpha: 0.75),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: primaryPurple.withValues(alpha: 0.75),
                    size: 10,
                  ),
                ],
              ),
            ],
          ),
        ),
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
    showAdminProfileSidePopup(context);
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

                  final filteredUsers = users.where((user) {
                    if (_selectedFilter == 'ALL') return true;
                    final accType = getAccountType(user.data());
                    return accType == _selectedFilter;
                  }).toList();

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
                                        filterKey: "SOLO",
                                        isSelected: _selectedFilter == "SOLO",
                                        onTap: () => _toggleFilter("SOLO"),
                                      ),

                                      const SizedBox(width: 9),

                                      statCard(
                                        icon: Icons.groups_outlined,
                                        value: teamUsers,
                                        label: "Teams",
                                        color: const Color(0xFFE67E22),
                                        filterKey: "TEAM",
                                        isSelected: _selectedFilter == "TEAM",
                                        onTap: () => _toggleFilter("TEAM"),
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
                                        filterKey: "QUIZ MASTER",
                                        isSelected:
                                            _selectedFilter == "QUIZ MASTER",
                                        onTap: () =>
                                            _toggleFilter("QUIZ MASTER"),
                                      ),

                                      const SizedBox(width: 9),

                                      statCard(
                                        icon:
                                            Icons.admin_panel_settings_outlined,
                                        value: admins,
                                        label: "Admins",
                                        color: blue,
                                        filterKey: "ADMIN",
                                        isSelected: _selectedFilter == "ADMIN",
                                        onTap: () => _toggleFilter("ADMIN"),
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
                                    filterKey: "SOLO",
                                    isSelected: _selectedFilter == "SOLO",
                                    onTap: () => _toggleFilter("SOLO"),
                                  ),

                                  const SizedBox(width: 12),

                                  statCard(
                                    icon: Icons.groups_outlined,
                                    value: teamUsers,
                                    label: "Teams",
                                    color: const Color(0xFFE67E22),
                                    filterKey: "TEAM",
                                    isSelected: _selectedFilter == "TEAM",
                                    onTap: () => _toggleFilter("TEAM"),
                                  ),

                                  const SizedBox(width: 12),

                                  statCard(
                                    icon: Icons.school_outlined,
                                    value: quizMasters,
                                    label: "Quiz Masters",
                                    color: primaryPurple,
                                    filterKey: "QUIZ MASTER",
                                    isSelected:
                                        _selectedFilter == "QUIZ MASTER",
                                    onTap: () =>
                                        _toggleFilter("QUIZ MASTER"),
                                  ),

                                  const SizedBox(width: 12),

                                  statCard(
                                    icon: Icons.admin_panel_settings_outlined,
                                    value: admins,
                                    label: "Admins",
                                    color: blue,
                                    filterKey: "ADMIN",
                                    isSelected: _selectedFilter == "ADMIN",
                                    onTap: () => _toggleFilter("ADMIN"),
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

                                        if (_selectedFilter != 'ALL') ...[
                                          InkWell(
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            onTap: () => setState(
                                                () => _selectedFilter = 'ALL'),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 9,
                                                vertical: 5,
                                              ),
                                              decoration: BoxDecoration(
                                                color: primaryPurple.withValues(
                                                    alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                border: Border.all(
                                                  color: primaryPurple
                                                      .withValues(alpha: 0.4),
                                                  width: 1,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    "Filter: $_selectedFilter",
                                                    style: const TextStyle(
                                                      color: primaryPurple,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  const Icon(
                                                    Icons.close_rounded,
                                                    size: 13,
                                                    color: primaryPurple,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                        ],
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
                                            _selectedFilter == 'ALL'
                                                ? "${users.length} Users"
                                                : "${filteredUsers.length} of ${users.length} Users",

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
                                        ],
                                      ),
                                    ),

                                  // =================================================
                                  // FILTERED EMPTY STATE
                                  // =================================================
                                  if (filteredUsers.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 36,
                                        horizontal: 20,
                                      ),
                                      child: Center(
                                        child: Column(
                                          children: [
                                            Icon(
                                              Icons.filter_list_off_rounded,
                                              size: 42,
                                              color: textGrey.withValues(
                                                alpha: 0.45,
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            Text(
                                              "No $_selectedFilter users found",
                                              style: const TextStyle(
                                                color: textDark,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            TextButton.icon(
                                              onPressed: () => setState(
                                                () => _selectedFilter = 'ALL',
                                              ),
                                              icon: const Icon(
                                                Icons.refresh_rounded,
                                                size: 15,
                                              ),
                                              label: const Text(
                                                "Show All Users",
                                              ),
                                              style: TextButton.styleFrom(
                                                foregroundColor: primaryPurple,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  // =================================================
                                  // MOBILE USERS
                                  // =================================================
                                  else if (isMobile)
                                    Padding(
                                      padding: const EdgeInsets.all(12),

                                      child: Column(
                                        children: filteredUsers.map((user) {
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
                                              UserPresenceService.isUserActive(
                                            data,
                                            docUid: user.id,
                                          );

                                          final teamName =
                                              (data['teamName'] ?? '')
                                                  .toString();

                                          final teamMembers = getTeamMembers(
                                            data,
                                          );

                                          final isBlocked = isUserBlocked(data);

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

                                            isBlocked: isBlocked,

                                            rawData: data,
                                          );
                                        }).toList(),
                                      ),
                                    )
                                  // =================================================
                                  // DESKTOP USERS
                                  // =================================================
                                  else
                                    Column(
                                      children: filteredUsers.map((user) {
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
                                            UserPresenceService.isUserActive(
                                          data,
                                          docUid: user.id,
                                        );

                                        final teamName =
                                            (data['teamName'] ?? '').toString();

                                        final teamMembers = getTeamMembers(
                                          data,
                                        );

                                        final isBlocked = isUserBlocked(data);

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

                                          isBlocked: isBlocked,

                                          rawData: data,
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
                                            _selectedFilter == 'ALL'
                                                ? "Showing ${users.length} registered user${users.length == 1 ? '' : 's'}"
                                                : "Showing ${filteredUsers.length} of ${users.length} registered user${users.length == 1 ? '' : 's'} ($_selectedFilter)",

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
