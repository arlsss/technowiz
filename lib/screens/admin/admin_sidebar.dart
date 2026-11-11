import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Shared Admin navigation drawer & desktop sidebar for TechNoWiz.
/// Standardized with the cohesive Light Purple theme.
class AdminSidebar extends StatelessWidget {
  const AdminSidebar({
    super.key,
    required this.currentPage,
    required this.onDestinationSelected,
    this.onProfileTap,
  });

  /// One of: dashboard, manage_users, add_question, question_list,
  /// quiz_sessions, leaderboard, reports.
  final String currentPage;

  /// Called with the destination key.
  final ValueChanged<String> onDestinationSelected;

  /// Keep each screen's profile-menu behavior.
  final VoidCallback? onProfileTap;

  static const Color _purple = Color(0xFF7C3AED);
  static const Color _purpleDark = Color(0xFF4C1D95);
  static const Color _text = Color(0xFF1E1B4B);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _selectedBackground = Color(0xFFF3E8FF);
  static const Color _selectedBorder = Color(0xFFDDD6FE);
  static const Color _profileBackground = Color(0xFFFAF7FF);

  static const List<_AdminMenuItem> _items = [
    _AdminMenuItem('dashboard', 'Dashboard', Icons.dashboard_rounded),
    _AdminMenuItem(
      'manage_users',
      'Manage Users',
      Icons.person_add_alt_1_rounded,
    ),
    _AdminMenuItem('question_list', 'Question Bank', Icons.grid_on_rounded),
    _AdminMenuItem(
      'quiz_sessions',
      'Quiz Sessions',
      Icons.manage_history_rounded,
    ),
    _AdminMenuItem('leaderboard', 'Leaderboard', Icons.bar_chart_rounded),
    _AdminMenuItem('reports', 'Reports', Icons.analytics_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final drawerWidth = screenWidth < 300 ? screenWidth * 0.86 : 245.0;

    return Drawer(
      width: drawerWidth,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            // Header: TechNoWiz Admin Brand
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_purple, _purpleDark],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(11),
                          boxShadow: [
                            BoxShadow(
                              color: _purple.withValues(alpha: 0.35),
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
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'TechNoWiz',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _purpleDark,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _selectedBackground,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _selectedBorder, width: 1),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shield_rounded, size: 11, color: _purple),
                        SizedBox(width: 4),
                        Text(
                          'ADMIN COMMAND CENTER',
                          style: TextStyle(
                            color: _purpleDark,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFFF3E8FF), height: 1),

            // Navigation Items List
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                children: [
                  for (final item in _items) _buildMenuItem(context, item),
                ],
              ),
            ),

            const Divider(color: Color(0xFFF3E8FF), height: 1),

            // Footer Profile Card
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onProfileTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: _profileBackground,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _selectedBorder, width: 1),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_purple, _purpleDark],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          stream: FirebaseAuth.instance.currentUser == null
                              ? null
                              : FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(FirebaseAuth.instance.currentUser!.uid)
                                  .snapshots(),
                          builder: (context, snapshot) {
                            final authUser = FirebaseAuth.instance.currentUser;
                            final userData = snapshot.data?.data();
                            final registeredName = (userData?['name'] ??
                                    userData?['fullName'] ??
                                    authUser?.displayName ??
                                    '')
                                .toString()
                                .trim();
                            final displayName = registeredName.isNotEmpty
                                ? registeredName
                                : (authUser?.email?.split('@').first ?? 'Admin');

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _purpleDark,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  authUser?.email ?? 'admin@technowiz.com',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _muted,
                                    fontSize: 9.5,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: _muted,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(BuildContext context, _AdminMenuItem item) {
    final selected = currentPage == item.keyName;
    final showChevron = item.keyName != 'dashboard';

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: selected ? _selectedBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            final scaffold = Scaffold.maybeOf(context);
            final bool hasDrawer = (scaffold?.isDrawerOpen ?? false) ||
                (scaffold?.isEndDrawerOpen ?? false);

            if (selected) {
              if (hasDrawer) {
                Navigator.of(context).pop();
              }
              return;
            }

            if (hasDrawer) {
              Navigator.of(context).pop();
            }
            onDestinationSelected(item.keyName);
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: selected
                  ? Border.all(color: _selectedBorder, width: 1.2)
                  : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: 20,
                  color: selected ? _purple : _muted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? _purpleDark : _text,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
                if (showChevron)
                  Icon(
                    Icons.chevron_right_rounded,
                    color: selected ? _purple : _muted.withValues(alpha: 0.5),
                    size: 18,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminMenuItem {
  const _AdminMenuItem(this.keyName, this.title, this.icon);

  final String keyName;
  final String title;
  final IconData icon;
}
