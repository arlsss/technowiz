import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../login_screen.dart';
import 'quizmaster_dashboard.dart';
import 'quizmaster_theme.dart';
import '../../navigation_persistence.dart';

/// Shows the Quiz Master profile as a smooth slide-out side panel from the right
void showQuizMasterProfileSideSheet(BuildContext context) {
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Profile',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (dialogContext, _, _) {
      final screenWidth = MediaQuery.of(dialogContext).size.width;
      final panelWidth = screenWidth < 460 ? screenWidth * 0.92 : 400.0;

      return Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: panelWidth,
            height: double.infinity,
            child: QuizMasterProfilePanel(
              onClose: () {
                if (Navigator.of(dialogContext).canPop()) {
                  Navigator.of(dialogContext).pop();
                }
              },
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, anim, _, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

/// Fallback full-screen route for legacy navigation (if directly invoked)
class QuizMasterProfileScreen extends StatelessWidget {
  const QuizMasterProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: QuizMasterCircuitBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: QuizMasterProfilePanel(
              onClose: () async {
                await QuizMasterNavPersistence.savePage('dashboard');
                if (!context.mounted) return;
                final nav = Navigator.of(context);
                if (nav.canPop()) {
                  nav.pop();
                } else {
                  nav.pushReplacement(
                    PageRouteBuilder<void>(
                      pageBuilder: (_, _, _) => const QuizMasterDashboard(),
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                      transitionsBuilder:
                          (_, animation, secondaryAnimation, child) => child,
                    ),
                  );
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// The slide-out profile side panel
class QuizMasterProfilePanel extends StatefulWidget {
  final VoidCallback? onClose;

  const QuizMasterProfilePanel({super.key, this.onClose});

  @override
  State<QuizMasterProfilePanel> createState() => _QuizMasterProfilePanelState();
}

class _QuizMasterProfilePanelState extends State<QuizMasterProfilePanel> {
  static const Color primaryBlue = Color(0xFF168BEB);
  static const Color deepBlue = Color(0xFF0F4C81);
  static const Color darkBlue = Color(0xFF1E293B);
  static const Color borderColor = Color(0xFFDCEAF8);
  static const Color textMuted = Color(0xFF64748B);

  User? get _user => FirebaseAuth.instance.currentUser;

  Future<void> _logout() async {
    await QuizMasterNavPersistence.clearAll();
    await LoginScreen.clearSavedCredentials();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => const LoginScreen(clearCredentials: true),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    if (user == null) {
      return Container(
        color: Colors.white,
        child: const Center(
          child: Text('Please sign in to view your profile.'),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFD),
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(24)),
        border: const Border(left: BorderSide(color: borderColor, width: 1.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 30,
            offset: const Offset(-5, 0),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Top App Bar for Panel
            Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(topLeft: Radius.circular(24)),
                border: Border(bottom: BorderSide(color: borderColor, width: 1)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5F4FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.person_rounded,
                      color: primaryBlue,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Quiz Master Profile',
                    style: TextStyle(
                      color: deepBlue,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            // Profile Body Content
            Expanded(
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .snapshots(),
                builder: (context, userSnapshot) {
                  final data =
                      userSnapshot.data?.data() ?? <String, dynamic>{};
                  final name = (data['name'] ??
                          data['displayName'] ??
                          user.displayName ??
                          user.email?.split('@').first ??
                          'Quiz Master')
                      .toString();

                  final initials = name.trim().isNotEmpty
                      ? name
                          .trim()
                          .split(RegExp(r'\s+'))
                          .map((w) => w.isNotEmpty ? w[0] : '')
                          .take(2)
                          .join()
                          .toUpperCase()
                      : 'QM';

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // =================================================
                        // HERO PROFILE CARD (Royal Blue Gradient)
                        // =================================================
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF0F4C81),
                                Color(0xFF1689E8),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF0F4C81,
                                ).withValues(alpha: 0.30),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Subtle Decorative glow
                              Positioned(
                                top: -20,
                                right: -20,
                                child: Container(
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withValues(
                                      alpha: 0.08,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: double.infinity,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    18,
                                    22,
                                    18,
                                    20,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      // Avatar with Ring & Verified Badge
                                      Center(
                                        child: Stack(
                                          alignment: Alignment.bottomRight,
                                          children: [
                                            Container(
                                              width: 84,
                                              height: 84,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.white,
                                                border: Border.all(
                                                  color: Colors.white,
                                                  width: 3,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withValues(alpha: 0.2),
                                                    blurRadius: 10,
                                                    offset: const Offset(0, 4),
                                                  ),
                                                ],
                                              ),
                                              child: CircleAvatar(
                                                backgroundColor: const Color(
                                                  0xFFE5F4FF,
                                                ),
                                                child: Text(
                                                  initials,
                                                  style: const TextStyle(
                                                    color: Color(0xFF0F4C81),
                                                    fontSize: 28,
                                                    fontWeight: FontWeight.w900,
                                                    letterSpacing: 1,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.all(4),
                                              decoration: const BoxDecoration(
                                                color: Color(0xFF10B981),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.verified_rounded,
                                                color: Colors.white,
                                                size: 16,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 12),

                                      // Name
                                      Center(
                                        child: Text(
                                          name,
                                          textAlign: TextAlign.center,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 19,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),

                                      // Email
                                      Center(
                                        child: Text(
                                          user.email ?? '',
                                          textAlign: TextAlign.center,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.85,
                                            ),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),

                                      // Role Badge
                                      Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.20,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            border: Border.all(
                                              color: Colors.white.withValues(
                                                alpha: 0.35,
                                              ),
                                            ),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.shield_rounded,
                                                color: Colors.amber,
                                                size: 13,
                                              ),
                                              SizedBox(width: 5),
                                              Text(
                                                'OFFICIAL QUIZ MASTER',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: 0.7,
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
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // =================================================
                        // ACCOUNT DETAILS CARD
                        // =================================================
                        Container(
                          padding: const EdgeInsets.all(16),
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.badge_rounded,
                                    size: 17,
                                    color: deepBlue,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Account Information',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: deepBlue,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _infoTile(
                                icon: Icons.person_rounded,
                                label: 'Full Name',
                                value: name,
                              ),
                              const Divider(height: 14, color: borderColor),
                              _infoTile(
                                icon: Icons.mail_rounded,
                                label: 'Email Address',
                                value: user.email ?? 'No email',
                                trailingBadge: 'VERIFIED',
                              ),
                              const Divider(height: 14, color: borderColor),
                              _infoTile(
                                icon: Icons.verified_user_rounded,
                                label: 'Assigned Role',
                                value: 'Quiz Master Host',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // =================================================
            // LOG OUT BUTTON (PINNED AT THE PINAKA UBOS)
            // =================================================
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _logout,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1F2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFFECDD3),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.logout_rounded,
                          color: Color(0xFFE11D48),
                          size: 19,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Log Out',
                          style: TextStyle(
                            color: Color(0xFFE11D48),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
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

  Widget _infoTile({
    required IconData icon,
    required String label,
    required String value,
    String? trailingBadge,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: primaryBlue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    color: textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: darkBlue,
                  ),
                ),
              ],
            ),
          ),
          if (trailingBadge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFD1FAE5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                trailingBadge,
                style: const TextStyle(
                  color: Color(0xFF059669),
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
