import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../login_screen.dart';
import '../../navigation_persistence.dart';

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
              child: Builder(
                builder: (cardCtx) => InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    if (onProfileTap != null) {
                      onProfileTap!();
                    } else {
                      showAdminProfileSidePopup(cardCtx);
                    }
                  },
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

/// Displays the Admin profile popup on the side (docked above the profile card in the sidebar/drawer).
void showAdminProfileSidePopup(BuildContext context) {
  final user = FirebaseAuth.instance.currentUser;
  final mediaQuery = MediaQuery.of(context);
  final screenWidth = mediaQuery.size.width;
  final screenHeight = mediaQuery.size.height;

  final scaffold = Scaffold.maybeOf(context);
  final renderBox = context.findRenderObject() as RenderBox?;
  Offset? offset;
  if (renderBox != null && renderBox.hasSize) {
    try {
      offset = renderBox.localToGlobal(Offset.zero);
    } catch (_) {}
  }

  final bool isRightSide;
  if (offset != null) {
    isRightSide = offset.dx > (screenWidth / 2);
  } else if (scaffold != null && scaffold.isEndDrawerOpen) {
    isRightSide = true;
  } else if (scaffold != null && scaffold.isDrawerOpen) {
    isRightSide = false;
  } else {
    isRightSide = (screenWidth < 960);
  }

  final double bottomPos = screenHeight < 550 ? 12.0 : 84.0;
  final double popupWidth = (screenWidth * 0.85).clamp(240.0, 275.0);

  showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: const Color(0x1F000000),
    useSafeArea: false,
    builder: (dialogContext) {
      return Stack(
        children: [
          Positioned(
            bottom: bottomPos,
            right: isRightSide ? 14.0 : null,
            left: isRightSide ? null : 14.0,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: popupWidth,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: const Color(0xFFDDD6FE),
                    width: 1.5,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x2E4C1D95),
                      blurRadius: 26,
                      spreadRadius: 2,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top header with close button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3E8FF),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFDDD6FE), width: 1),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.shield_rounded, size: 11, color: Color(0xFF7C3AED)),
                              SizedBox(width: 4),
                              Text(
                                'ADMIN',
                                style: TextStyle(
                                  color: Color(0xFF4C1D95),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => Navigator.of(dialogContext).pop(),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Avatar
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0EBFF),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFD8CCF7), width: 2),
                      ),
                      child: const Icon(
                        Icons.admin_panel_settings_rounded,
                        color: Color(0xFF7C3AED),
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Display Name
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: user == null
                          ? null
                          : FirebaseFirestore.instance
                              .collection('users')
                              .doc(user.uid)
                              .snapshots(),
                      builder: (context, snapshot) {
                        final userData = snapshot.data?.data();
                        final registeredName = (userData?['name'] ??
                                userData?['fullName'] ??
                                user?.displayName ??
                                '')
                            .toString()
                            .trim();
                        final displayName = registeredName.isNotEmpty
                            ? registeredName
                            : (user?.email?.split('@').first ?? 'Admin');

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E1B4B),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              user?.email ?? 'admin@technowiz.com',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 14),
                    const Divider(color: Color(0xFFF3E8FF), height: 1),
                    const SizedBox(height: 12),

                    // Logout Button
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.of(dialogContext).pop();
                          final s = Scaffold.maybeOf(context);
                          if (s != null) {
                            if (s.isEndDrawerOpen || s.isDrawerOpen) {
                              Navigator.of(context).pop();
                            }
                          }
                          try {
                            await AdminNavPersistence.clear();
                            await LoginScreen.clearSavedCredentials();
                            await FirebaseAuth.instance.signOut();
                            if (!context.mounted) return;
                            Navigator.of(context, rootNavigator: true)
                                .pushAndRemoveUntil<void>(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    const LoginScreen(clearCredentials: true),
                              ),
                              (route) => false,
                            );
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Unable to log out: $e')),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.logout_rounded, size: 18),
                        label: const Text(
                          'Logout',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF5F3FF),
                          foregroundColor: const Color(0xFF7C3AED),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(
                              color: Color(0xFFDDD6FE),
                              width: 1,
                            ),
                          ),
                        ),
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
