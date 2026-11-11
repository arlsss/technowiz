import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'my_score_screen.dart';
import 'quiz_history_score_screen.dart';
import 'technowiz_theme.dart';
import 'contestant_profile_panel.dart';
import 'badges_screen.dart';
import 'contestant_history_screen.dart';
import 'waiting_room_screen.dart';
import '../login_screen.dart';
import '../../navigation_persistence.dart';

class CompetitorDashboard extends StatefulWidget {
  final String? initialPage;

  const CompetitorDashboard({super.key, this.initialPage});

  @override
  State<CompetitorDashboard> createState() => _CompetitorDashboardState();
}

class _CompetitorDashboardState extends State<CompetitorDashboard> {
  // =========================================================
  // COLORS
  // =========================================================

  static const Color primaryGreen = Color(0xFF16A34A);
  static const Color darkGreen = Color(0xFF14532D);
  static const Color lightGreen = Color(0xFFE8FBEF);
  static const Color backgroundColor = Color(0xFFF5FBF6);
  static const Color softBorder = Color(0xFFD5F0DE);

  // =========================================================
  // PROFILE
  // =========================================================

  Map<String, dynamic> profileData = {};
  bool profileLoading = true;

  // =========================================================
  // DASHBOARD / LEADERBOARD VIEW
  // =========================================================

  bool _showLeaderboard = false;
  bool _showBadges = false;
  bool _showHistory = false;
  String _pageBeforeProfile = 'dashboard';
  // ignore: unused_field
  final GlobalKey _liveRankingButtonKey = GlobalKey();
  String? _leaderboardSelectedSessionId;
  int? _leaderboardSelectedLevel;

  // Saves the last page/view so refresh or reopening the app/browser
  // returns the contestant to the same page.
  static const String _lastPageKey = 'contestant_last_page';

  // Remembers the quiz session that became the contestant's current quiz.
  // This lets the same session become FINAL RANKING after it is finished,
  // without ever falling back to an unrelated old finished quiz.
  static const String _currentLeaderboardSessionKey =
      'contestant_current_leaderboard_session';
  String? _currentLeaderboardSessionId;

  Future<void> _restoreCurrentLeaderboardSession() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_currentLeaderboardSessionKey);
    if (!mounted) return;
    setState(() {
      _currentLeaderboardSessionId = (saved == null || saved.trim().isEmpty)
          ? null
          : saved.trim();
    });
  }

  // ignore: unused_element
  Future<void> _rememberCurrentLeaderboardSession(String sessionId) async {
    if (sessionId.trim().isEmpty) return;
    final normalized = sessionId.trim();
    if (_currentLeaderboardSessionId != normalized && mounted) {
      setState(() {
        _currentLeaderboardSessionId = normalized;
      });
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentLeaderboardSessionKey, normalized);
  }

  void _applyTabSelection(String page) {
    if (page == 'history') {
      _showLeaderboard = false;
      _showBadges = false;
      _showHistory = true;
    } else if (page == 'leaderboard') {
      _showLeaderboard = true;
      _showBadges = false;
      _showHistory = false;
    } else if (page == 'badges') {
      _showLeaderboard = false;
      _showBadges = true;
      _showHistory = false;
    } else if (page == 'profile') {
      _showLeaderboard = false;
      _showBadges = false;
      _showHistory = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showProfileDrawer(context, savePage: false);
      });
    } else {
      _showLeaderboard = false;
      _showBadges = false;
      _showHistory = false;
    }
  }

  Future<void> _restoreLastPage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final lastPage =
        widget.initialPage ?? prefs.getString(_lastPageKey) ?? 'dashboard';

    if (!mounted) return;

    if (lastPage == 'profile') {
      setState(() {
        _showLeaderboard = false;
        _showBadges = false;
        _showHistory = false;
      });

      // Re-open My Profile automatically after refresh/restart.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showProfileDrawer(context, savePage: false);
      });
      return;
    }

    if (lastPage == 'history') {
      setState(() {
        _showLeaderboard = false;
        _showBadges = false;
        _showHistory = true;
      });
      await _saveCurrentPage('history');
      return;
    }

    // Child quiz pages are restored by SplashScreen using these saved values.
    // Do not push them from the Dashboard itself because that would create a
    // temporary Dashboard flash during browser refresh.
    if (lastPage == 'waiting_room' ||
        lastPage == 'quiz_screen' ||
        lastPage == 'my_score' ||
        lastPage == 'quiz_history_score' ||
        lastPage == 'final_ranking') {
      setState(() {
        _showLeaderboard = false;
        _showBadges = false;
        _showHistory = false;
      });
      return;
    }

    setState(() {
      _showLeaderboard = lastPage == 'leaderboard';
      _showBadges = lastPage == 'badges';
      _showHistory = false;
    });
    await _saveCurrentPage(lastPage);
  }

  Future<void> _saveCurrentPage(String page) async {
    await CompetitorNavPersistence.savePage(page);
  }

  void _closeSidebarDrawer(BuildContext pageContext) {
    final scaffold = Scaffold.maybeOf(pageContext);
    if (scaffold?.isDrawerOpen == true) {
      // The sidebar is a Drawer route. Pop that route immediately so the
      // drawer disappears as soon as Dashboard/Leaderboard/Badges/History
      // is tapped.
      Navigator.of(pageContext).pop();
    }
  }

  Future<void> _openLeaderboard([BuildContext? drawerContext]) async {
    if (!mounted) return;

    _closeSidebarDrawer(drawerContext ?? context);

    setState(() {
      _showLeaderboard = true;
      _showBadges = false;
      _showHistory = false;
    });

    await _saveCurrentPage('leaderboard');
  }

  Future<void> _openBadges([BuildContext? drawerContext]) async {
    if (!mounted) return;

    _closeSidebarDrawer(drawerContext ?? context);

    setState(() {
      _showLeaderboard = false;
      _showBadges = true;
      _showHistory = false;
    });

    await _saveCurrentPage('badges');
  }

  Future<void> _openDashboard([BuildContext? drawerContext]) async {
    if (!mounted) return;

    _closeSidebarDrawer(drawerContext ?? context);

    setState(() {
      _showLeaderboard = false;
      _showBadges = false;
      _showHistory = false;
    });

    await _saveCurrentPage('dashboard');
  }

  Future<void> _openHistory([BuildContext? drawerContext]) async {
    if (!mounted) return;

    _closeSidebarDrawer(drawerContext ?? context);

    setState(() {
      _showLeaderboard = false;
      _showBadges = false;
      _showHistory = true;
    });

    await _saveCurrentPage('history');
  }

  DocumentReference<Map<String, dynamic>>? get userProfileRef {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) return null;

    return FirebaseFirestore.instance.collection('users').doc(uid);
  }

  // =========================================================
  // LOAD PROFILE
  // =========================================================

  Future<void> loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (mounted) {
        setState(() {
          profileLoading = false;
        });
      }
      return;
    }

    try {
      final ref = userProfileRef;

      if (ref == null) return;

      final snapshot = await ref.get();
      final data = snapshot.data() ?? {};

      if (mounted) {
        setState(() {
          profileData = data;
          profileLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          profileLoading = false;
        });
      }
    }
  }

  // =========================================================
  // LOGOUT
  // =========================================================

  Future<void> logout(BuildContext context) async {
    await CompetitorNavPersistence.clearAll();

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

  // =========================================================
  // OPEN PAGE
  // =========================================================

  Future<void> _rememberQuizPage({
    required String page,
    required String quizCode,
    String? quizTitle,
    int? level,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_lastPageKey, page);
    await prefs.setString('contestant_current_quiz_code', quizCode);

    if (quizTitle != null && quizTitle.trim().isNotEmpty) {
      await prefs.setString('contestant_current_quiz_title', quizTitle.trim());
    } else {
      await prefs.remove('contestant_current_quiz_title');
    }

    if (level != null) {
      await prefs.setInt('contestant_current_quiz_level', level);
    }
  }

  Future<void> openPage(BuildContext context, Widget page) async {
    // Waiting Room is a real page, so remember the exact quiz before opening it.
    if (page is WaitingRoomScreen) {
      await _rememberQuizPage(
        page: 'waiting_room',
        quizCode: page.quizCode,
        quizTitle: page.quizTitle,
        level: page.level,
      );
    } else if (page is MyScoreScreen) {
      // Keep My Score refresh-safe as well.
      await _rememberQuizPage(page: 'my_score', quizCode: page.quizCode);
    } else if (page is QuizHistoryScoreScreen) {
      await _rememberQuizPage(
        page: 'quiz_history_score',
        quizCode: page.quizCode,
        quizTitle: page.quizTitle,
      );
    }

    if (!context.mounted) return;

    // Open child quiz pages immediately without the default Material fade/slide.
    // This keeps View Quiz Event from briefly flashing during navigation.
    await Navigator.push(
      context,
      PageRouteBuilder<void>(
        pageBuilder: (routeContext, animation, secondaryAnimation) => page,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        transitionsBuilder:
            (routeContext, animation, secondaryAnimation, child) {
              return child;
            },
      ),
    );

    // Returning from a child page restores the contestant to their previous tab.
    if (!context.mounted) return;

    final String returnPage = _showHistory
        ? 'history'
        : _showLeaderboard
            ? 'leaderboard'
            : _showBadges
                ? 'badges'
                : 'dashboard';
    await _saveCurrentPage(returnPage);
  }

  // =========================================================
  // PARTICIPATION TYPE
  // =========================================================

  String getParticipationType() {
    // IMPORTANT: contestantType is the exact field saved by RegisterScreen.
    // Registration saves it as lowercase: "solo" or "team".
    // Use this field first so old/legacy profile fields cannot override the
    // contestant's actual registration type.
    final registeredType = profileData['contestantType']?.toString().trim();

    if (registeredType != null && registeredType.isNotEmpty) {
      return registeredType.toLowerCase() == 'team' ? 'Team' : 'Solo';
    }

    // Legacy fallback for older contestant records.
    final legacyType =
        profileData['participationType'] ??
        profileData['participation'] ??
        profileData['type'];

    final result = legacyType?.toString().trim();

    if (result != null && result.isNotEmpty && result.toLowerCase() == 'team') {
      return 'Team';
    }

    return 'Solo';
  }

  // =========================================================
  // TEAM MEMBERS
  // =========================================================

  List<String> getTeamMembers() {
    // IMPORTANT: RegisterScreen saves the member names in the exact
    // Firestore field "teamMembers" as List<String>.
    final rawMembers = profileData['teamMembers'];

    if (rawMembers is! List) {
      // Legacy fallback only for older records.
      final legacyMembers = profileData['members'];
      if (legacyMembers is! List) return [];
      return _parseTeamMemberList(legacyMembers);
    }

    return _parseTeamMemberList(rawMembers);
  }

  List<String> _parseTeamMemberList(List rawMembers) {
    final List<String> names = [];

    for (final member in rawMembers) {
      if (member is String) {
        final name = member.trim();

        if (name.isNotEmpty) {
          names.add(name);
        }
      } else if (member is Map) {
        final name =
            member['name'] ?? member['displayName'] ?? member['fullName'];

        if (name != null) {
          final value = name.toString().trim();

          if (value.isNotEmpty) {
            names.add(value);
          }
        }
      }
    }

    return names;
  }

  // =========================================================
  // SCHOOL NAME
  // =========================================================

  String getSchoolName() {
    final school = profileData['schoolName']?.toString().trim();

    if (school != null && school.isNotEmpty) {
      return school;
    }

    final oldAddress = profileData['address']?.toString().trim();

    if (oldAddress != null && oldAddress.isNotEmpty) {
      return oldAddress;
    }

    return "Not yet set";
  }

  // =========================================================
  // ENTER QUIZ CODE
  // =========================================================

  void showJoinQuizDialog(
    BuildContext pageContext, {
    String? expectedQuizCode,
    String? expectedQuizTitle,
  }) {
    final codeController = TextEditingController();
    bool checking = false;

    showDialog(
      context: context,
      barrierDismissible: !checking,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogBodyContext, setDialogState) {
            Future<void> submitCode() async {
              final code = codeController.text.trim();

              if (code.isEmpty) {
                showTopSnackBar(
                  pageContext,
                  const SnackBar(
                    content: Text('Please enter the quiz code.'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              setDialogState(() => checking = true);

              try {
                final quizRef = FirebaseFirestore.instance
                    .collection('quiz_sessions')
                    .doc(code);

                final quizSnapshot = await quizRef.get();

                if (!quizSnapshot.exists) {
                  if (pageContext.mounted) {
                    setDialogState(() => checking = false);
                    showTopSnackBar(
                      pageContext,
                      const SnackBar(
                        content: Text('Quiz code not found.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                  return;
                }

                final data = quizSnapshot.data() ?? {};
                final published =
                    data['published'] == true || data['isPublished'] == true;
                final status =
                    data['status']?.toString().trim().toLowerCase() ?? '';

                // When Join Quiz is opened from a published quiz card,
                // require the contestant to enter the same quiz code shown
                // on that card. This prevents accidentally joining another
                // quiz from the wrong card.
                if (expectedQuizCode != null &&
                    code.toUpperCase() !=
                        expectedQuizCode.trim().toUpperCase()) {
                  if (pageContext.mounted) {
                    setDialogState(() => checking = false);
                    showTopSnackBar(
                      pageContext,
                      const SnackBar(
                        content: Text(
                          'The quiz code does not match the selected quiz.',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                  return;
                }

                if (!published || (status != 'waiting' && status != 'active')) {
                  if (pageContext.mounted) {
                    setDialogState(() => checking = false);
                    showTopSnackBar(
                      pageContext,
                      const SnackBar(
                        content: Text(
                          'This quiz is not currently available for joining.',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                  return;
                }

                final title =
                    data['title']?.toString().trim().isNotEmpty == true
                    ? data['title'].toString().trim()
                    : 'TechNoWiz Quiz';

                if (!context.mounted) return;

                Navigator.of(dialogContext).pop();

                final shouldJoin = await _showJoinConfirmationDialog(
                  pageContext,
                  quizCode: code,
                  quizTitle: expectedQuizTitle ?? title,
                );

                if (!shouldJoin || !pageContext.mounted) return;

                await joinQuiz(
                  context: pageContext,
                  quizCode: code,
                  quizTitle: expectedQuizTitle ?? title,
                );
              } catch (e) {
                if (!context.mounted) return;

                setDialogState(() => checking = false);
                showTopSnackBar(
                  pageContext,
                  SnackBar(
                    content: Text('Unable to check quiz code: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }

            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Row(
                children: [
                  Icon(Icons.login_rounded, color: primaryGreen),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Join Quiz',
                      style: TextStyle(
                        color: darkGreen,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: TextField(
                controller: codeController,
                enabled: !checking,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!checking) submitCode();
                },
                decoration: InputDecoration(
                  labelText: 'Quiz Code',
                  hintText: 'Enter the code from the Admin',
                  prefixIcon: const Icon(Icons.key_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: checking
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('CANCEL'),
                ),
                ElevatedButton(
                  onPressed: checking ? null : submitCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: checking
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'JOIN',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(codeController.dispose);
  }

  // =========================================================
  // JOIN CONFIRMATION
  // =========================================================

  Future<bool> _showJoinConfirmationDialog(
    BuildContext context, {
    required String quizCode,
    required String quizTitle,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Row(
            children: [
              Icon(Icons.help_outline_rounded, color: primaryGreen),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Confirm Join',
                  style: TextStyle(
                    color: darkGreen,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to join "$quizTitle"?\r\n\r\n'
            'Quiz Code: $quizCode\r\n\r\n'
            'After you confirm, your request will be sent to the Admin. '
            'You will enter the waiting room only after the Admin approves your request.',
            style: const TextStyle(
              color: Colors.black54,
              height: 1.5,
              fontSize: 14,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text(
                'CANCEL',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'YES, JOIN',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  // =========================================================
  // JOIN QUIZ
  // =========================================================

  Future<void> joinQuiz({
    required BuildContext context,
    required String quizCode,
    required String quizTitle,
  }) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      showTopSnackBar(
        context,
        const SnackBar(
          content: Text("Please login first."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final uid = user.uid;

    final requestRef = FirebaseFirestore.instance
        .collection('quiz_sessions')
        .doc(quizCode)
        .collection('join_requests')
        .doc(uid);

    // Show the existing Waiting for Approval dialog immediately on tap.
    // Firestore checks/writes continue afterward, without delaying the UI.
    _showPendingDialog(context, quizCode: quizCode, quizTitle: quizTitle);

    try {
      final requestSnapshot = await requestRef.get();

      if (requestSnapshot.exists) {
        final data = requestSnapshot.data() ?? {};

        final status = data['status']?.toString().trim().toLowerCase() ?? '';

        final isElim = data['eliminated'] == true ||
            data['isEliminated'] == true ||
            status == 'eliminated' ||
            data['contestantDecision']?.toString().trim().toLowerCase() ==
                'eliminated';

        if (isElim) {
          if (context.mounted) {
            Navigator.of(context, rootNavigator: true).maybePop();
            showTopSnackBar(
              context,
              const SnackBar(
                content: Text(
                  'You have been eliminated from this quiz and cannot rejoin.',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        // The already-open Waiting for Approval dialog listens to this
        // document and handles approved/rejected states automatically.
        if (status == 'approved' ||
            status == 'pending' ||
            status == 'rejected' ||
            status == 'declined') {
          return;
        }
      }

      final contestantType =
          profileData['contestantType']?.toString().trim().toLowerCase() ?? '';
      final teamName = profileData['teamName']?.toString().trim() ?? '';
      final bool isTeam = contestantType == 'team' || teamName.isNotEmpty;
      final teamMembers = isTeam ? getTeamMembers() : <String>[];

      final personalName = user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : (profileData['fullName'] ?? profileData['name'] ?? user.email?.split('@').first ?? 'Contestant').toString().trim();

      final String effectiveName =
          isTeam && teamName.isNotEmpty ? teamName : personalName;

      await requestRef.set({
        'uid': uid,
        'email': user.email ?? '',
        'displayName': effectiveName,
        'name': effectiveName,
        'realName': personalName,
        'contestantType': isTeam ? 'team' : 'solo',
        'isTeam': isTeam,
        'teamName': isTeam ? teamName : '',
        'teamMembers': teamMembers,
        'members': teamMembers,
        'quizCode': quizCode,
        'quizTitle': quizTitle,
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
        'respondedAt': null,
      }, SetOptions(merge: true));

      // The Waiting for Approval dialog is already visible while this write
      // completes; its Firestore stream will continue monitoring the decision.
    } catch (e) {
      if (!context.mounted) return;

      showTopSnackBar(
        context,
        SnackBar(
          content: Text("Failed to join quiz: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // =========================================================
  // PENDING DIALOG
  // =========================================================

  void _showPendingDialog(
    BuildContext context, {
    required String quizCode,
    required String quizTitle,
  }) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final requestRef = FirebaseFirestore.instance
        .collection('quiz_sessions')
        .doc(quizCode)
        .collection('join_requests')
        .doc(user.uid);

    bool navigating = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: requestRef.snapshots(),
          builder: (context, snapshot) {
            final data = snapshot.data?.data() ?? {};
            final status =
                data['status']?.toString().trim().toLowerCase() ?? 'pending';

            if (status == 'approved' && !navigating) {
              navigating = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!dialogContext.mounted || !context.mounted) return;
                Navigator.of(dialogContext).pop();
                openPage(
                  context,
                  WaitingRoomScreen(
                    quizCode: quizCode,
                    level: 1,
                    quizTitle: quizTitle,
                  ),
                );
              });
            } else if ((status == 'rejected' || status == 'declined') &&
                !navigating) {
              navigating = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!dialogContext.mounted || !context.mounted) return;
                Navigator.of(dialogContext).pop();
                _showRejectedDialog(context, quizTitle: quizTitle);
              });
            }

            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Row(
                children: [
                  Icon(Icons.hourglass_top_rounded, color: primaryGreen),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Waiting for Approval',
                      style: TextStyle(
                        color: darkGreen,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: primaryGreen),
                  const SizedBox(height: 18),
                  Text(
                    'Your request to join "$quizTitle" has been sent to the Admin.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54, height: 1.45),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Please wait for Admin to approve.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black45,
                      fontSize: 12,
                      height: 1.4,
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

  // =========================================================
  // REJECTED DIALOG
  // =========================================================

  void _showRejectedDialog(BuildContext context, {required String quizTitle}) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Row(
            children: [
              Icon(Icons.cancel_rounded, color: Colors.red),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Request Rejected",
                  style: TextStyle(
                    color: darkGreen,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Your request to join "$quizTitle" was rejected by the Admin.',
            style: const TextStyle(color: Colors.black54, height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text(
                "CLOSE",
                style: TextStyle(
                  color: primaryGreen,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // =========================================================
  // OPEN QUIZ
  // =========================================================

  Future<void> openQuiz({
    required BuildContext context,
    required String quizCode,
    required String quizTitle,
  }) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      showTopSnackBar(
        context,
        const SnackBar(
          content: Text("Please login first."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final requestRef = FirebaseFirestore.instance
        .collection('quiz_sessions')
        .doc(quizCode)
        .collection('join_requests')
        .doc(user.uid);

    try {
      final requestSnapshot = await requestRef.get();

      if (!context.mounted) return;

      if (!requestSnapshot.exists) {
        await joinQuiz(
          context: context,
          quizCode: quizCode,
          quizTitle: quizTitle,
        );
        return;
      }

      final data = requestSnapshot.data() ?? {};

      final status = data['status']?.toString().trim().toLowerCase() ?? '';

      final isElim = data['eliminated'] == true ||
          data['isEliminated'] == true ||
          status == 'eliminated' ||
          data['contestantDecision']?.toString().trim().toLowerCase() ==
              'eliminated';

      if (isElim) {
        if (!context.mounted) return;
        showTopSnackBar(
          context,
          const SnackBar(
            content: Text(
              'You have been eliminated from this quiz and cannot rejoin.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (status == 'pending') {
        _showPendingDialog(context, quizCode: quizCode, quizTitle: quizTitle);
        return;
      }

      if (status == 'rejected' || status == 'declined') {
        _showRejectedDialog(context, quizTitle: quizTitle);
        return;
      }

      if (status == 'approved') {
        openPage(
          context,
          WaitingRoomScreen(quizCode: quizCode, level: 1, quizTitle: quizTitle),
        );
        return;
      }

      await joinQuiz(
        context: context,
        quizCode: quizCode,
        quizTitle: quizTitle,
      );
    } catch (e) {
      if (!context.mounted) return;

      showTopSnackBar(
        context,
        SnackBar(
          content: Text("Unable to open quiz: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // =========================================================
  // QUIZ CARD
  // =========================================================

  Widget quizCard(BuildContext context, QueryDocumentSnapshot quiz) {
    final data = quiz.data() as Map<String, dynamic>;

    final quizCode = data['quizCode']?.toString().trim().isNotEmpty == true
        ? data['quizCode'].toString().trim()
        : quiz.id;

    final title = data['title']?.toString().trim().isNotEmpty == true
        ? data['title'].toString().trim()
        : "TechNoWiz Quiz";

    final status = data['status']?.toString().trim().toLowerCase() ?? "waiting";

    final published = data['published'] == true || data['isPublished'] == true;

    // These are the exact fields saved by the Admin Create Quiz screen:
    // date, startTime, endTime, and location.
    DateTime? toDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      return null;
    }

    String formatDate(dynamic value) {
      final date = toDate(value);
      if (date == null) return 'Date not set';

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

    String formatTime(dynamic value) {
      final date = toDate(value);
      if (date == null) return 'Time not set';

      final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
      final minute = date.minute.toString().padLeft(2, '0');
      final period = date.hour >= 12 ? 'PM' : 'AM';

      return '$hour:$minute $period';
    }

    final dateText = formatDate(
      data['date'] ?? data['quizDate'] ?? data['startDate'],
    );

    final startTimeText = formatTime(
      data['startTime'] ?? data['time'] ?? data['quizTime'],
    );

    final endTimeText = formatTime(
      data['endTime'] ?? data['quizEndTime'] ?? data['finishTime'],
    );

    final locationValue = data['location'] ?? data['venue'] ?? data['where'];

    final locationText = locationValue?.toString().trim().isNotEmpty == true
        ? locationValue.toString().trim()
        : 'Location not set';

    final descriptionValue =
        data['description'] ?? data['quizDescription'] ?? data['desc'];

    final descriptionText =
        descriptionValue?.toString().trim().isNotEmpty == true
            ? descriptionValue.toString().trim()
            : 'No description provided';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFEAFBF0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Color(0x2E16A34A),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // STATUS
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: lightGreen,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color:
                            status == 'active' ||
                                status == 'ongoing' ||
                                status == 'started'
                            ? Colors.greenAccent
                            : Colors.white70,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      published
                          ? (status == 'active' ||
                                    status == 'ongoing' ||
                                    status == 'started'
                                ? 'QUIZ ONGOING'
                                : status == 'countdown'
                                ? 'GET READY'
                                : status == 'level_pause'
                                ? 'WAITING FOR NEXT LEVEL'
                                : status == 'contest_review'
                                ? 'CONTEST REVIEW'
                                : 'QUIZ AVAILABLE')
                          : 'QUIZ',
                      style: const TextStyle(
                        color: darkGreen,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 13),

          // TITLE
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: darkGreen,
              fontSize: 21,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 12),

          // WHEN
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.calendar_today_rounded,
                color: Color(0xB814532D),
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'When: $dateText',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: darkGreen, fontSize: 12),
                ),
              ),
            ],
          ),

          const SizedBox(height: 7),

          // TIME
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.access_time_rounded,
                color: Color(0xB814532D),
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  endTimeText == 'Time not set'
                      ? 'Time: $startTimeText'
                      : 'Time: $startTimeText - $endTimeText',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: darkGreen, fontSize: 12),
                ),
              ),
            ],
          ),

          const SizedBox(height: 7),

          // WHERE
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.location_on_rounded,
                color: Color(0xB814532D),
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Where: $locationText',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: darkGreen, fontSize: 12),
                ),
              ),
            ],
          ),

          const SizedBox(height: 7),

          // DESCRIPTION
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.description_outlined,
                color: Color(0xB814532D),
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Description: $descriptionText',
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: darkGreen,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 7),

          // QUIZ CODE
          Row(
            children: [
              const Icon(Icons.key_rounded, color: Color(0xB814532D), size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Quiz Code: $quizCode',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xB814532D),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 15),

          // JOIN / APPROVAL / VIEW EVENT BUTTON
          // Listen to this contestant's request so the label changes in
          // real time after the Admin approves or rejects the request.
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseAuth.instance.currentUser == null
                ? null
                : FirebaseFirestore.instance
                      .collection('quiz_sessions')
                      .doc(quizCode)
                      .collection('join_requests')
                      .doc(FirebaseAuth.instance.currentUser!.uid)
                      .snapshots(),
            builder: (context, requestSnapshot) {
              final requestData = requestSnapshot.data?.data() ?? {};
              final requestStatus =
                  requestData['status']?.toString().trim().toLowerCase() ?? '';

              final isEliminated = requestData['eliminated'] == true ||
                  requestData['isEliminated'] == true ||
                  requestStatus == 'eliminated' ||
                  requestData['contestantDecision']
                          ?.toString()
                          .trim()
                          .toLowerCase() ==
                      'eliminated';

              // Kon na-eliminate ang contestant, dili na sila maka-join pagbalik.
              // Ilisan ang 'JOIN QUIZ' button og 'ONGOING QUIZ'.
              if (isEliminated) {
                return SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      showTopSnackBar(
                        context,
                        const SnackBar(
                          content: Text(
                            'You have been eliminated from this quiz and cannot rejoin.',
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.play_circle_outline_rounded,
                      size: 20,
                    ),
                    label: const Text(
                      'ONGOING QUIZ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade600,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                );
              }

              final buttonLabel = requestStatus == 'approved'
                  ? 'VIEW QUIZ EVENT'
                  : (requestStatus == 'pending'
                        ? 'WAITING FOR APPROVAL'
                        : 'JOIN QUIZ');

              final buttonIcon = requestStatus == 'approved'
                  ? Icons.event_available_rounded
                  : (requestStatus == 'pending'
                        ? Icons.hourglass_top_rounded
                        : Icons.login_rounded);

              return SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (requestStatus == 'approved') {
                      // Approved contestants can open the Waiting Room directly.
                      openQuiz(
                        context: context,
                        quizCode: quizCode,
                        quizTitle: title,
                      );
                      return;
                    }

                    // Send the join request directly for this quiz card.
                    // No quiz-code input or extra confirmation dialog is needed.
                    // The existing joinQuiz flow shows the Waiting for Approval
                    // dialog and automatically opens the Waiting Room if approved.
                    joinQuiz(
                      context: context,
                      quizCode: quizCode,
                      quizTitle: title,
                    );
                  },
                  icon: Icon(buttonIcon, size: 20),
                  label: Text(
                    buttonLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // =========================================================
  // PUBLISHED QUIZ FOR CONTESTANTS
  // =========================================================

  Widget publishedQuizSection({required bool mobile}) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('quiz_sessions')
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return welcomeQuizMessage();
        }

        if (!snapshot.hasData) {
          return Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: mobile ? 18 : 24,
              vertical: mobile ? 24 : 30,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: softBorder),
            ),
            child: const Center(
              child: CircularProgressIndicator(color: primaryGreen),
            ),
          );
        }

        final quizzes = snapshot.data!.docs.where((doc) {
          final data = doc.data();

          final published =
              data['published'] == true || data['isPublished'] == true;

          final status = data['status']?.toString().trim().toLowerCase() ?? '';

          // Dili na ipakita kon ang quiz opisyal na nga nahuman o na-archive
          if (status == 'finished' ||
              status == 'completed' ||
              status == 'closed' ||
              status == 'archived') {
            return false;
          }

          // Ipakita ang published quiz sa dashboard samtang nagpadayon pa kini,
          // aron makita gihapon kini sa mga contestant bisan na-eliminate na sila
          return published;
        }).toList();

        if (quizzes.isEmpty) {
          return welcomeQuizMessage();
        }

        quizzes.sort((a, b) {
          final aData = a.data();
          final bData = b.data();

          final aDate = _dateValue(aData['updatedAt'] ?? aData['createdAt']);
          final bDate = _dateValue(bData['updatedAt'] ?? bData['createdAt']);

          return bDate.compareTo(aDate);
        });

        return quizCard(context, quizzes.first);
      },
    );
  }

  // =========================================================
  // WELCOME MESSAGE
  // =========================================================

  Widget welcomeQuizMessage() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: softBorder),
      ),
      child: const Column(
        children: [
          Icon(Icons.emoji_events_outlined, color: primaryGreen, size: 48),
          SizedBox(height: 14),
          Text(
            'Welcome to the Quiz!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: darkGreen,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 7),
          Text(
            'There is no quiz available right now.\r\n'
            'Please wait for the Admin to publish a quiz.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }
  // =========================================================
  // PROFILE IMAGE
  // =========================================================

  String get profileImageUrl {
    final value = profileData['profileImageUrl']?.toString().trim() ?? '';
    return value;
  }

  ImageProvider<Object>? get profileImageProvider {
    final url = profileImageUrl;
    if (url.isEmpty) return null;
    return NetworkImage(url);
  }

  // =========================================================
  // PROFILE DRAWER
  // =========================================================

  void showProfileDrawer(BuildContext context, {bool savePage = true}) {
    if (savePage) {
      _pageBeforeProfile = _showLeaderboard
          ? 'leaderboard'
          : _showBadges
          ? 'badges'
          : 'dashboard';

      _saveCurrentPage('profile');
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Profile",
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final screenWidth = MediaQuery.of(context).size.width;
        final drawerWidth = (screenWidth * 0.88).clamp(280.0, 400.0);

        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: SafeArea(
              child: SizedBox(
                width: drawerWidth,
                height: double.infinity,
                child: ContestantProfilePanel(
                  profileData: profileData,
                  profileImageProvider: profileImageProvider,
                  onClose: () => _closeProfileDrawer(dialogContext),
                  onEdit: () => _showEditProfileDialog(dialogContext),
                  onLogout: () => logout(dialogContext),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final slide = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );

        return SlideTransition(position: slide, child: child);
      },
    );
  }

  Future<void> _closeProfileDrawer(BuildContext context) async {
    await _saveCurrentPage(_pageBeforeProfile);

    if (!context.mounted) return;
    Navigator.pop(context);
  }

  // =========================================================
  // PROFILE PANEL
  // =========================================================

  // ignore: unused_element
  Widget _profilePanel(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    final name = profileData['name']?.toString().trim().isNotEmpty == true
        ? profileData['name'].toString()
        : user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!
        : "Contestant";

    final email = profileData['email']?.toString().trim().isNotEmpty == true
        ? profileData['email'].toString()
        : user?.email ?? "";

    final participation = getParticipationType();

    final education =
        profileData['educationLevel']?.toString().trim().isNotEmpty == true
        ? profileData['educationLevel'].toString()
        : "Not yet set";

    final grade =
        profileData['gradeLevel']?.toString().trim().isNotEmpty == true
        ? profileData['gradeLevel'].toString()
        : "Not yet set";

    final schoolName = getSchoolName();

    final teamMembers = getTeamMembers();

    return Column(
      children: [
        // =====================================================
        // HEADER
        // =====================================================
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 18, 18, 25),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [primaryGreen, Color(0xFF006B30)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(28),
              bottomRight: Radius.circular(28),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () {
                      _closeProfileDrawer(context);
                    },
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 21,
                    ),
                  ),

                  const Expanded(
                    child: Text(
                      "Profile",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  IconButton(
                    onPressed: () {
                      _showEditProfileDialog(context);
                    },
                    icon: const Icon(Icons.edit_rounded, color: Colors.white),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.4),
                    width: 2,
                  ),
                  image: profileImageProvider == null
                      ? null
                      : DecorationImage(
                          image: profileImageProvider!,
                          fit: BoxFit.cover,
                        ),
                ),
                child: profileImageProvider == null
                    ? const Icon(
                        Icons.person_rounded,
                        color: Colors.white,
                        size: 45,
                      )
                    : null,
              ),

              const SizedBox(height: 12),

              Text(
                name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 5),

              Text(
                email,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),

        // =====================================================
        // DETAILS
        // =====================================================
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _profileInfoTile(
                  icon: Icons.location_on_outlined,
                  title: "School Name",
                  value: schoolName,
                ),

                _profileInfoTile(
                  icon: Icons.groups_outlined,
                  title: "Participation",
                  value: participation,
                ),

                if (participation == "Team") ...[
                  _profileInfoTile(
                    icon: Icons.badge_outlined,
                    title: "Team Name",
                    value:
                        profileData['teamName']?.toString().trim().isNotEmpty ==
                            true
                        ? profileData['teamName'].toString()
                        : "Not yet set",
                  ),
                  _teamMembersTile(teamMembers),
                ],

                _profileInfoTile(
                  icon: Icons.school_outlined,
                  title: "Education",
                  value: education,
                ),

                _profileInfoTile(
                  icon: Icons.menu_book_outlined,
                  title: "Grade / Year",
                  value: grade,
                ),

                const SizedBox(height: 15),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await _saveCurrentPage('dashboard');
                      if (!mounted || !context.mounted) return;
                      Navigator.pop(context);
                      logout(this.context);
                    },
                    icon: const Icon(Icons.logout_rounded, color: Colors.red),
                    label: const Text(
                      "LOGOUT",
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.red.shade200),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                const Text(
                  "TechNoWiz • Contestant Profile",
                  style: TextStyle(color: Colors.black38, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // =========================================================
  // TEAM MEMBERS TILE
  // =========================================================

  Widget _teamMembersTile(List<String> teamMembers) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: softBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: lightGreen,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.groups_rounded,
                  color: primaryGreen,
                  size: 21,
                ),
              ),

              const SizedBox(width: 13),

              const Expanded(
                child: Text(
                  "Team Members",
                  style: TextStyle(color: Colors.black45, fontSize: 11),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          if (teamMembers.isEmpty)
            const Text(
              "Team members not yet set",
              style: TextStyle(
                color: darkGreen,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            ...teamMembers.asMap().entries.map((entry) {
              final index = entry.key;
              final name = entry.value;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 27,
                      height: 27,
                      decoration: const BoxDecoration(
                        color: lightGreen,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        "${index + 1}",
                        style: const TextStyle(
                          color: primaryGreen,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    const SizedBox(width: 10),

                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: darkGreen,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // =========================================================
  // PROFILE INFO TILE
  // =========================================================

  Widget _profileInfoTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: softBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: lightGreen,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: primaryGreen, size: 21),
          ),

          const SizedBox(width: 13),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.black45, fontSize: 11),
                ),

                const SizedBox(height: 4),

                Text(
                  value,
                  style: const TextStyle(
                    color: darkGreen,
                    fontSize: 14,
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

  String _buildProfileUpdateMessage({
    required bool emailVerificationSent,
    String? authEmailError,
    String? authNameError,
  }) {
    final parts = <String>[
      'Your profile information has been successfully updated.',
    ];

    if (emailVerificationSent) {
      parts.add(
        'A verification email was sent to your new email address. Please verify it to complete the email change.',
      );
    }



    if (authNameError != null) {
      parts.add('Name: $authNameError');
    }

    return parts.join('\r\n\r\n');
  }

  // =========================================================
  // EDIT PROFILE DIALOG
  // =========================================================

  void _showEditProfileDialog(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    final nameController = TextEditingController(
      text: profileData['name']?.toString() ?? user?.displayName ?? '',
    );

    final emailController = TextEditingController(
      text: profileData['email']?.toString() ?? user?.email ?? '',
    );

    final schoolController = TextEditingController(
      text:
          profileData['schoolName']?.toString() ??
          profileData['address']?.toString() ??
          '',
    );

    final gradeController = TextEditingController(
      text: profileData['gradeLevel']?.toString() ?? '',
    );

    final participation = getParticipationType();

    String education =
        profileData['educationLevel']?.toString() ?? "High School";

    if (!["College", "High School", "Senior High"].contains(education)) {
      education = "High School";
    }

    // Keep the profile drawer's route context. The StatefulBuilder below
    // has its own BuildContext, so we must not accidentally use that one
    // when closing the drawer after a successful save.
    final profileDrawerContext = context;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        String selectedEducation = education;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Row(
                children: [
                  Icon(Icons.edit_rounded, color: primaryGreen),
                  SizedBox(width: 10),
                  Text(
                    "Edit Profile",
                    style: TextStyle(
                      color: darkGreen,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // =================================================
                    // PROFILE PICTURE (READ-ONLY)
                    // =================================================
                    Column(
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: lightGreen,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Color(0x4016A34A),
                              width: 2,
                            ),
                            image: profileImageProvider == null
                                ? null
                                : DecorationImage(
                                    image: profileImageProvider!,
                                    fit: BoxFit.cover,
                                  ),
                          ),
                          child: profileImageProvider == null
                              ? const Icon(
                                  Icons.person_rounded,
                                  color: primaryGreen,
                                  size: 48,
                                )
                              : null,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          "Profile picture cannot be changed.",
                          style: TextStyle(color: Colors.black45, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    // =================================================
                    // NAME
                    // =================================================
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: "Full Name",
                        prefixIcon: const Icon(Icons.person_outline_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: primaryGreen),
                        ),
                      ),
                    ),

                    const SizedBox(height: 13),

                    // =================================================
                    // EMAIL
                    // =================================================
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: "Email",
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: primaryGreen),
                        ),
                      ),
                    ),

                    const SizedBox(height: 13),

                    // =================================================
                    // SCHOOL
                    // =================================================
                    TextField(
                      controller: schoolController,
                      decoration: InputDecoration(
                        labelText: "School Name",
                        prefixIcon: const Icon(Icons.location_city_rounded),
                        hintText: "Enter your school name",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: primaryGreen),
                        ),
                      ),
                    ),

                    const SizedBox(height: 13),

                    // =================================================
                    // PARTICIPATION READ ONLY
                    // =================================================
                    _readOnlyProfileField(
                      icon: Icons.groups_outlined,
                      label: "Participation",
                      value: participation,
                    ),

                    const SizedBox(height: 13),

                    // =================================================
                    // EDUCATION LEVEL
                    // =================================================
                    DropdownButtonFormField<String>(
                      initialValue: selectedEducation,
                      decoration: InputDecoration(
                        labelText: "Education Level",
                        prefixIcon: const Icon(Icons.school_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: primaryGreen),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: "College",
                          child: Text("College"),
                        ),
                        DropdownMenuItem(
                          value: "High School",
                          child: Text("High School"),
                        ),
                        DropdownMenuItem(
                          value: "Senior High",
                          child: Text("Senior High"),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;

                        setDialogState(() {
                          selectedEducation = value;
                        });
                      },
                    ),

                    const SizedBox(height: 13),

                    // =================================================
                    // GRADE / YEAR
                    // =================================================
                    TextField(
                      controller: gradeController,
                      decoration: InputDecoration(
                        labelText: selectedEducation == "College"
                            ? "Year Level"
                            : "Grade Level",
                        prefixIcon: const Icon(Icons.menu_book_outlined),
                        hintText: selectedEducation == "College"
                            ? "e.g. 1st Year"
                            : "e.g. Grade 12",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: primaryGreen),
                        ),
                      ),
                    ),

                    const SizedBox(height: 13),

                    // =================================================
                    // TEAM MEMBERS
                    // =================================================
                    if (participation == "Team")
                      _editTeamMembersPreview(getTeamMembers()),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text(
                    "CANCEL",
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                ElevatedButton(
                  onPressed: () async {
                    await _confirmSaveProfile(
                      dialogContext: dialogContext,
                      profileDrawerContext: profileDrawerContext,
                      name: nameController.text.trim(),
                      email: emailController.text.trim(),
                      schoolName: schoolController.text.trim(),
                      gradeLevel: gradeController.text.trim(),
                      educationLevel: selectedEducation,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    "SAVE",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // =========================================================
  // READ ONLY FIELD
  // =========================================================

  Widget _readOnlyProfileField({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(icon, color: primaryGreen, size: 22),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.black45, fontSize: 11),
                ),

                const SizedBox(height: 3),

                Text(
                  value,
                  style: const TextStyle(
                    color: darkGreen,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          const Icon(
            Icons.lock_outline_rounded,
            size: 17,
            color: Colors.black26,
          ),
        ],
      ),
    );
  }

  // =========================================================
  // TEAM MEMBERS PREVIEW
  // =========================================================

  Widget _editTeamMembersPreview(List<String> members) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: lightGreen,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: softBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.groups_rounded, color: primaryGreen, size: 21),
              SizedBox(width: 9),
              Text(
                "Team Members",
                style: TextStyle(
                  color: darkGreen,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          if (members.isEmpty)
            const Text(
              "No team members registered.",
              style: TextStyle(color: Colors.black54, fontSize: 12),
            )
          else
            ...members.asMap().entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  "${entry.key + 1}. ${entry.value}",
                  style: const TextStyle(color: darkGreen, fontSize: 13),
                ),
              );
            }),
        ],
      ),
    );
  }

  // =========================================================
  // CONFIRM SAVE PROFILE
  // =========================================================

  Future<void> _confirmSaveProfile({
    required BuildContext dialogContext,
    required BuildContext profileDrawerContext,
    required String name,
    required String email,
    required String schoolName,
    required String gradeLevel,
    required String educationLevel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (confirmContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Row(
            children: [
              Icon(Icons.save_rounded, color: primaryGreen),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Save Changes?",
                  style: TextStyle(
                    color: darkGreen,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: const Text(
            "Are you sure you want to save these changes?",
            style: TextStyle(color: Colors.black54, height: 1.5, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(confirmContext, false),
              child: const Text(
                "CANCEL",
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(confirmContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                "SAVE CHANGES",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted || !dialogContext.mounted || !profileDrawerContext.mounted) return;

    await _saveProfile(
      context: dialogContext,
      profileDrawerContext: profileDrawerContext,
      name: name,
      email: email,
      schoolName: schoolName,
      gradeLevel: gradeLevel,
      educationLevel: educationLevel,
    );
  }

  // =========================================================
  // SAVE PROFILE
  // =========================================================

  Future<void> _saveProfile({
    required BuildContext context,
    required BuildContext profileDrawerContext,
    required String name,
    required String email,
    required String schoolName,
    required String gradeLevel,
    required String educationLevel,
  }) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (context.mounted) {
        showTopSnackBar(
          context,
          const SnackBar(
            content: Text("Please login first."),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (name.trim().isEmpty) {
      showTopSnackBar(
        context,
        const SnackBar(
          content: Text("Please enter your name."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (email.trim().isEmpty) {
      showTopSnackBar(
        context,
        const SnackBar(
          content: Text("Please enter your email."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final ref = userProfileRef;

    if (ref == null) {
      showTopSnackBar(
        context,
        const SnackBar(
          content: Text("Unable to find your profile. Please login again."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    bool emailVerificationSent = false;
    String? authEmailError;
    String? authNameError;

    try {
      // =====================================================
      // 1. SAVE NORMAL PROFILE FIELDS FIRST
      // =====================================================
      // Profile picture upload is intentionally NOT awaited here.
      // This prevents Firebase Storage from blocking the normal profile
      // save when Storage is slow, unavailable, or has a rules problem.
      // Registration-controlled fields are intentionally untouched.
      final Map<String, dynamic> updatedData = {
        'uid': user.uid,
        'name': name.trim(),
        'displayName': name.trim(),
        'schoolName': schoolName.trim(),
        'address': schoolName.trim(),
        'educationLevel': educationLevel.trim(),
        'gradeLevel': gradeLevel.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final currentAuthEmail = user.email?.trim() ?? '';
      final requestedEmail = email.trim();

      if (requestedEmail == currentAuthEmail) {
        updatedData['email'] = requestedEmail;
      }

      await ref
          .set(updatedData, SetOptions(merge: true))
          .timeout(const Duration(seconds: 15));

      // =====================================================
      // 2. FIREBASE AUTH NAME
      // =====================================================
      if ((user.displayName ?? '').trim() != name.trim()) {
        try {
          await user.updateDisplayName(name.trim());
        } on FirebaseAuthException catch (e) {
          authNameError = e.message?.trim().isNotEmpty == true
              ? e.message!.trim()
              : 'Unable to update the Firebase Auth display name (${e.code}).';
        } catch (e) {
          authNameError = 'Unable to update the Firebase Auth display name: $e';
        }
      }

      // =====================================================
      // 3. FIREBASE AUTH EMAIL
      // =====================================================
      if (currentAuthEmail != requestedEmail) {
        try {
          await user.verifyBeforeUpdateEmail(requestedEmail);
          emailVerificationSent = true;

          await ref
              .set({
                'email': requestedEmail,
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true))
              .timeout(const Duration(seconds: 15));
        } on FirebaseAuthException catch (e) {
          if (e.code == 'requires-recent-login') {
            authEmailError =
                'Please login again before changing your email. Your other profile changes were still saved.';
          } else if (e.code == 'email-already-in-use') {
            authEmailError =
                'That email is already being used by another account. Your other profile changes were still saved.';
          } else if (e.code == 'invalid-email') {
            authEmailError =
                'Please enter a valid email address. Your other profile changes were still saved.';
          } else {
            authEmailError = e.message?.trim().isNotEmpty == true
                ? '${e.message!.trim()} Your other profile changes were still saved.'
                : 'Unable to change the email (${e.code}). Your other profile changes were still saved.';
          }
        } catch (e) {
          authEmailError =
              'Unable to change the email: $e\r\nYour other profile changes were still saved.';
        }
      }

      // =====================================================
      // 4. RELOAD NORMAL PROFILE DATA NOW
      // =====================================================
      final freshSnapshot = await ref.get().timeout(
        const Duration(seconds: 15),
      );
      final freshData = freshSnapshot.data() ?? {};

      if (mounted) {
        setState(() {
          profileData = freshData;
        });
      }

      if (!context.mounted) return;

      // =====================================================
      // 5. CLOSE EDIT PROFILE + PROFILE DRAWER
      // =====================================================
      Navigator.of(context).pop();

      if (profileDrawerContext.mounted) {
        Navigator.of(profileDrawerContext).pop();
      }

      if (!mounted) return;

      // =====================================================
      // 6. SHOW SUCCESS IMMEDIATELY FOR THE NORMAL PROFILE SAVE
      // =====================================================
      _showProfileUpdatedDialog(
        this.context,
        emailVerificationSent: emailVerificationSent,
        authEmailError: authEmailError,
        authNameError: authNameError,
      );
    } on TimeoutException {
      if (!context.mounted) return;

      showTopSnackBar(
        context,
        const SnackBar(
          content: Text(
            'Profile save timed out. Please check your internet connection and try again.',
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 6),
        ),
      );
    } on FirebaseException catch (e) {
      if (!context.mounted) return;

      final message = e.message?.trim().isNotEmpty == true
          ? e.message!.trim()
          : 'Firebase error (${e.code}).';

      showTopSnackBar(
        context,
        SnackBar(
          content: Text('Profile could not be saved: $message'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;

      showTopSnackBar(
        context,
        SnackBar(
          content: Text('Profile could not be saved: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  // =========================================================
  // PROFILE UPDATED DIALOG
  // =========================================================

  void _showProfileUpdatedDialog(
    BuildContext context, {
    required bool emailVerificationSent,
    String? authEmailError,
    String? authNameError,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          contentPadding: const EdgeInsets.fromLTRB(25, 28, 25, 10),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: const BoxDecoration(
                  color: lightGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: primaryGreen,
                  size: 40,
                ),
              ),

              const SizedBox(height: 17),

              const Text(
                "Profile Updated!",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: darkGreen,
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 9),

              Text(
                _buildProfileUpdateMessage(
                  emailVerificationSent: emailVerificationSent,
                  authEmailError: authEmailError,
                  authNameError: authNameError,
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ),
          actions: [
            Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGreen,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(130, 45),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                child: const Text(
                  "DONE",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // =========================================================
  // MODERN CONTESTANT DASHBOARD UI
  // =========================================================

  Widget _sidebarItem({
    required IconData icon,
    required String title,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: active ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: active ? primaryGreen : Color(0xC714532D),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: active ? primaryGreen : Color(0xC714532D),
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (active)
                  Container(
                    width: 5,
                    height: 22,
                    decoration: BoxDecoration(
                      color: primaryGreen,
                      borderRadius: BorderRadius.circular(10),
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
  // LEADERBOARD DATA
  // =========================================================

  int _scoreToInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  DateTime _dateValue(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  // ignore: unused_element
  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _getLatestQuiz() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('quiz_sessions')
        .limit(50)
        .get();

    // IMPORTANT:
    // Only published quizzes are allowed to appear in the contestant
    // leaderboard/live ranking. Unpublished/admin-draft quizzes must be
    // completely ignored.
    final docs = snapshot.docs.where((doc) {
      final data = doc.data();
      final published =
          data['published'] == true || data['isPublished'] == true;
      final status = data['status']?.toString().trim().toLowerCase() ?? '';
      return published &&
          (status == 'active' || status == 'ongoing' || status == 'started');
    }).toList();

    if (docs.isEmpty) return null;

    docs.sort((a, b) {
      final aData = a.data();
      final bData = b.data();
      final aDate = _dateValue(aData['updatedAt'] ?? aData['createdAt']);
      final bDate = _dateValue(bData['updatedAt'] ?? bData['createdAt']);
      return bDate.compareTo(aDate);
    });

    return docs.first;
  }

  Future<List<Map<String, dynamic>>> _buildLeaderboardRows(
    String quizCode,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> scoreDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> joinDocs,
  ) async {
    final users = <String, Map<String, dynamic>>{};
    final uids = <String>{};

    for (final doc in joinDocs) {
      final data = doc.data();
      final uid = data['uid']?.toString().trim();
      if (uid != null && uid.isNotEmpty) uids.add(uid);
    }

    for (final doc in scoreDocs) {
      final data = doc.data();
      final uid = data['uid']?.toString().trim().isNotEmpty == true
          ? data['uid'].toString().trim()
          : doc.id;
      if (uid.isNotEmpty) uids.add(uid);
    }

    await Future.wait(
      uids.map((uid) async {
        try {
          final snap = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get();
          users[uid] = snap.data() ?? {};
        } catch (_) {
          users[uid] = {};
        }
      }),
    );

    final grouped = <String, Map<String, dynamic>>{};

    void addParticipant({
      required String uid,
      required String fallbackName,
      required String fallbackTeamName,
      required int score,
      List<String> fallbackTeamMembers = const [],
    }) {
      final user = users[uid] ?? {};
      final teamName =
          (fallbackTeamName.isNotEmpty
                  ? fallbackTeamName
                  : user['teamName']?.toString() ?? '')
              .trim();
      final personalName =
          (user['name']?.toString().trim().isNotEmpty == true
                  ? user['name'].toString().trim()
                  : fallbackName.isNotEmpty
                  ? fallbackName
                  : 'Contestant')
              .trim();

      // Team member names are stored in users/{uid}.teamMembers.
      // Keep a fallback for older records that used "members".
      final userRawMembers = user['teamMembers'] ?? user['members'];
      final userMembers = userRawMembers is List
          ? _parseTeamMemberList(userRawMembers)
          : <String>[];
      final members = userMembers.isNotEmpty
          ? userMembers
          : List<String>.from(fallbackTeamMembers);

      final isTeam = teamName.isNotEmpty;
      final key = isTeam ? 'team:${teamName.toLowerCase()}' : 'solo:$uid';

      final existing = grouped[key];
      if (existing == null) {
        grouped[key] = {
          'displayName': isTeam ? teamName : personalName,
          'score': score,
          'isTeam': isTeam,
          'teamMembers': isTeam ? members : <String>[],
          'uid': uid,
          'uids': [uid],
        };
      } else {
        existing['score'] = _scoreToInt(existing['score']) + score;

        if (isTeam && members.isNotEmpty) {
          final currentMembers = List<String>.from(
            existing['teamMembers'] ?? const [],
          );
          for (final member in members) {
            if (!currentMembers.contains(member)) {
              currentMembers.add(member);
            }
          }
          existing['teamMembers'] = currentMembers;
        }

        final currentUids = List<String>.from(existing['uids'] ?? const []);
        if (!currentUids.contains(uid)) {
          currentUids.add(uid);
          existing['uids'] = currentUids;
        }
      }
    }

    // Approved/joined contestants are included even when their score is 0.
    for (final doc in joinDocs) {
      final data = doc.data();
      final status = data['status']?.toString().trim().toLowerCase() ?? '';
      if (status.isNotEmpty &&
          status != 'approved' &&
          status != 'accepted' &&
          status != 'joined') {
        continue;
      }

      final uid = data['uid']?.toString().trim() ?? doc.id;
      if (uid.isEmpty) continue;

      final rawMembers = data['teamMembers'] ?? data['members'];
      final requestMembers = rawMembers is List
          ? _parseTeamMemberList(rawMembers)
          : <String>[];

      addParticipant(
        uid: uid,
        fallbackName:
            data['displayName']?.toString() ?? data['name']?.toString() ?? '',
        fallbackTeamName: data['teamName']?.toString() ?? '',
        score: 0,
        fallbackTeamMembers: requestMembers,
      );
    }

    // Replace/add the actual score for contestants who have answered.
    for (final doc in scoreDocs) {
      final data = doc.data();
      final uid = data['uid']?.toString().trim().isNotEmpty == true
          ? data['uid'].toString().trim()
          : doc.id;
      if (uid.isEmpty) continue;

      final user = users[uid] ?? {};
      final teamName =
          (data['teamName']?.toString() ?? user['teamName']?.toString() ?? '')
              .trim();
      final name =
          data['name']?.toString() ?? user['name']?.toString() ?? 'Contestant';
      final isTeam = teamName.isNotEmpty;
      final key = isTeam ? 'team:${teamName.toLowerCase()}' : 'solo:$uid';

      final score = _scoreToInt(data['score']);
      if (grouped.containsKey(key)) {
        grouped[key]!['score'] = score;
      } else {
        final rawMembers = data['teamMembers'] ?? data['members'];
        final scoreMembers = rawMembers is List
            ? _parseTeamMemberList(rawMembers)
            : <String>[];

        addParticipant(
          uid: uid,
          fallbackName: name,
          fallbackTeamName: teamName,
          score: score,
          fallbackTeamMembers: scoreMembers,
        );
      }
    }

    final result = grouped.values.toList();
    result.sort((a, b) {
      final scoreCompare = _scoreToInt(
        b['score'],
      ).compareTo(_scoreToInt(a['score']));
      if (scoreCompare != 0) return scoreCompare;
      return (a['displayName']?.toString() ?? '').toLowerCase().compareTo(
        (b['displayName']?.toString() ?? '').toLowerCase(),
      );
    });

    return result;
  }

  Widget _buildRankTrophyBadge(int rank) {
    if (rank <= 3) {
      final trophyAsset = rank == 1
          ? 'assets/trophies/gold_trophy_3d.jpg'
          : (rank == 2
              ? 'assets/trophies/silver_trophy_3d.jpg'
              : 'assets/trophies/bronze_trophy_3d.jpg');

      final rankColor = rank == 1
          ? const Color(0xFFF59E0B)
          : (rank == 2 ? const Color(0xFF94A3B8) : const Color(0xFFD97706));

      return Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: rankColor, width: 1.8),
              boxShadow: [
                BoxShadow(
                  color: rankColor.withValues(alpha: 0.35),
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
                  rank == 1
                      ? Icons.emoji_events_rounded
                      : (rank == 2
                          ? Icons.workspace_premium_rounded
                          : Icons.military_tech_rounded),
                  size: 18,
                  color: rankColor,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -2,
            right: -3,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: rankColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.2),
              ),
              alignment: Alignment.center,
              child: Text(
                '$rank',
                style: const TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: rank <= 10 ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
        border: Border.all(
          color: rank <= 10 ? const Color(0xFFBBF7D0) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        '$rank',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: rank <= 10 ? primaryGreen : const Color(0xFF64748B),
        ),
      ),
    );
  }

  Widget _leaderboardRows(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text(
            'Waiting for contestants to join...',
            style: TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          color: const Color(0xFFF7FAF8),
          child: const Row(
            children: [
              SizedBox(
                width: 42,
                child: Text(
                  '#',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.black45,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'TEAM / CONTESTANT',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.black45,
                  ),
                ),
              ),
              Text(
                'SCORE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.black45,
                ),
              ),
            ],
          ),
        ),
        ...List.generate(rows.length, (index) {
          final row = rows[index];
          final score = _scoreToInt(row['score']);
          final rank = index + 1;

          final currentUid = FirebaseAuth.instance.currentUser?.uid;
          final isCurrentUser = currentUid != null &&
              (row['uid'] == currentUid ||
                  (row['uids'] as List?)?.contains(currentUid) == true);

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isCurrentUser
                  ? const Color(0xFFF0FDF4)
                  : (rank == 1
                      ? const Color(0xFFFFFDF5)
                      : (rank == 2
                          ? const Color(0xFFFAFBFC)
                          : (rank == 3
                              ? const Color(0xFFFFFBF7)
                              : Colors.transparent))),
              border: const Border(top: BorderSide(color: softBorder)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 42,
                  child: Center(
                    child: _buildRankTrophyBadge(rank),
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: rank == 1
                              ? const Color(0xFFFEF3C7)
                              : (rank == 2
                                  ? const Color(0xFFF1F5F9)
                                  : (rank == 3
                                      ? const Color(0xFFFFEDD5)
                                      : lightGreen)),
                          borderRadius: BorderRadius.circular(10),
                          border: rank <= 3
                              ? Border.all(
                                  color: rank == 1
                                      ? const Color(0xFFFDE68A)
                                      : (rank == 2
                                          ? const Color(0xFFCBD5E1)
                                          : const Color(0xFFFED7AA)),
                                  width: 1,
                                )
                              : null,
                        ),
                        child: Icon(
                          row['isTeam'] == true
                              ? Icons.groups_rounded
                              : Icons.person_rounded,
                          color: rank == 1
                              ? const Color(0xFFD97706)
                              : (rank == 2
                                  ? const Color(0xFF64748B)
                                  : (rank == 3
                                      ? const Color(0xFFB45309)
                                      : primaryGreen)),
                          size: 19,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: row['isTeam'] == true
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    row['displayName']?.toString() ?? 'Team',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: darkGreen,
                                    ),
                                  ),
                                  if ((row['teamMembers'] as List?)
                                          ?.isNotEmpty ==
                                      true) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      'Members: ${(row['teamMembers'] as List).join(', ')}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.black45,
                                        height: 1.25,
                                      ),
                                    ),
                                  ],
                                ],
                              )
                            : Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      row['displayName']?.toString() ?? 'Contestant',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: darkGreen,
                                      ),
                                    ),
                                  ),
                                  if (isCurrentUser) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: primaryGreen,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'YOU',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$score',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: primaryGreen,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _rankingMessageCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 42),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: softBorder),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.hourglass_empty_rounded,
            color: primaryGreen,
            size: 48,
          ),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _badgesContent({required bool mobile}) {
    return ContestantBadgesView(
      mobile: mobile,
      mobileHeader: mobile ? _mobileHeader() : null,
    );
  }

  // =========================================================
  // LEADERBOARD / REAL-TIME LIVE RANKING & HISTORY
  // =========================================================

  int _parseLeaderboardLevel(dynamic value, {int fallback = 1}) {
    if (value is int && value > 0) return value;
    if (value is num && value > 0) return value.toInt();
    if (value is String) {
      final trimmed = value.trim();
      final direct = int.tryParse(trimmed);
      if (direct != null && direct > 0) return direct;

      final match = RegExp(r'\d+').firstMatch(trimmed);
      if (match != null) {
        final parsed = int.tryParse(match.group(0)!);
        if (parsed != null && parsed > 0) return parsed;
      }

      final lower = trimmed.toLowerCase();
      if (lower.contains('easy') || lower == 'level 1') return 1;
      if (lower.contains('moderate') ||
          lower.contains('medium') ||
          lower == 'level 2') {
        return 2;
      }
      if (lower.contains('difficult') ||
          lower.contains('hard') ||
          lower == 'level 3') {
        return 3;
      }
      if (lower.contains('clincher') || lower == 'level 4') return 4;
    }
    return fallback;
  }

  String _getLeaderboardLevelTitle(int level) {
    switch (level) {
      case 1:
        return 'Level 1 (Easy)';
      case 2:
        return 'Level 2 (Moderate)';
      case 3:
        return 'Level 3 (Difficult)';
      case 4:
        return 'Level 4 (Clincher)';
      default:
        return 'Level $level';
    }
  }

  Color _getLeaderboardLevelColor(int level) {
    switch (level) {
      case 1:
        return const Color(0xFF16A34A);
      case 2:
        return const Color(0xFFD97706);
      case 3:
        return const Color(0xFFDC2626);
      case 4:
        return const Color(0xFF7C3AED);
      default:
        return primaryGreen;
    }
  }

  Future<List<Map<String, dynamic>>> _buildLevelLeaderboardRows({
    required DocumentSnapshot<Map<String, dynamic>> sessionDoc,
    required String quizCode,
    required int selectedLevel,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> scoreDocs,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> joinDocs,
  }) async {
    final baseRows = await _buildLeaderboardRows(quizCode, scoreDocs, joinDocs);
    if (baseRows.isEmpty) return [];

    final allUids = <String>{};
    for (final row in baseRows) {
      final u = row['uid']?.toString();
      if (u != null && u.isNotEmpty) allUids.add(u);
      final list = row['uids'] as List?;
      if (list != null) {
        for (final item in list) {
          final s = item?.toString();
          if (s != null && s.isNotEmpty) allUids.add(s);
        }
      }
    }

    final uidLevelScores = <String, int>{};
    await Future.wait(
      allUids.map((uid) async {
        try {
          final responsesSnap = await sessionDoc.reference
              .collection('answers')
              .doc(uid)
              .collection('responses')
              .get();

          int sum = 0;
          for (final doc in responsesSnap.docs) {
            final data = doc.data();
            final lvl = _parseLeaderboardLevel(data['level']);
            final isCorrect = data['isCorrect'] == true ||
                data['answerStatus']?.toString().toLowerCase() == 'correct';
            if (lvl == selectedLevel && isCorrect) {
              final pts = int.tryParse(data['points']?.toString() ?? '') ?? 1;
              sum += pts;
            }
          }
          uidLevelScores[uid] = sum;
        } catch (_) {
          uidLevelScores[uid] = 0;
        }
      }),
    );

    final levelRows = <Map<String, dynamic>>[];
    for (final base in baseRows) {
      int rowLevelScore = 0;
      final uidsList = (base['uids'] as List?)?.cast<String>() ??
          (base['uid'] != null ? [base['uid'].toString()] : <String>[]);

      for (final u in uidsList) {
        rowLevelScore += uidLevelScores[u] ?? 0;
      }

      levelRows.add({
        ...base,
        'score': rowLevelScore,
        'level': selectedLevel,
      });
    }

    levelRows.sort((a, b) {
      final scoreCompare =
          _scoreToInt(b['score']).compareTo(_scoreToInt(a['score']));
      if (scoreCompare != 0) return scoreCompare;
      return (a['displayName']?.toString() ?? '').toLowerCase().compareTo(
        (b['displayName']?.toString() ?? '').toLowerCase(),
      );
    });

    return levelRows;
  }

  Widget _buildLeaderboardQuizHistoryPicker({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> publishedSessions,
    required QueryDocumentSnapshot<Map<String, dynamic>> selectedSession,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: softBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: lightGreen,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.history_rounded,
                  color: primaryGreen,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'QUIZ SESSION HISTORY',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF047857),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FBF9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: softBorder),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedSession.id,
                isExpanded: true,
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: primaryGreen,
                ),
                items: publishedSessions.map((session) {
                  final data = session.data();
                  final title =
                      data['quizTitle']?.toString().trim().isNotEmpty == true
                          ? data['quizTitle'].toString().trim()
                          : (data['title']?.toString().trim().isNotEmpty == true
                              ? data['title'].toString().trim()
                              : 'Quiz Session');
                  final code =
                      data['quizCode']?.toString().trim().isNotEmpty == true
                          ? data['quizCode'].toString().trim()
                          : session.id;
                  final s =
                      data['status']?.toString().toLowerCase().trim() ?? '';
                  final live =
                      s == 'active' || s == 'ongoing' || s == 'started';
                  final waiting = s == 'waiting';

                  final tag = live
                      ? '🔴 LIVE'
                      : (waiting ? '⏳ WAITING' : '🏁 FINISHED');

                  return DropdownMenuItem<String>(
                    value: session.id,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: live
                                ? const Color(0xFFDCFCE7)
                                : (waiting
                                    ? const Color(0xFFFEF3C7)
                                    : const Color(0xFFF1F5F9)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: live
                                  ? const Color(0xFF15803D)
                                  : (waiting
                                      ? const Color(0xFFB45309)
                                      : const Color(0xFF475569)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$title (Code: $code)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF172033),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (newId) {
                  if (newId != null && newId != selectedSession.id) {
                    setState(() {
                      _leaderboardSelectedSessionId = newId;
                      _leaderboardSelectedLevel = null;
                    });
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardLevelSelectorBar(
    DocumentSnapshot<Map<String, dynamic>> sessionDoc,
  ) {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: sessionDoc.reference.collection('questions').get(),
      builder: (context, questionsSnapshot) {
        final distinctLevels = <int>{};
        if (questionsSnapshot.hasData &&
            questionsSnapshot.data!.docs.isNotEmpty) {
          for (final qDoc in questionsSnapshot.data!.docs) {
            final qData = qDoc.data();
            final lvl = _parseLeaderboardLevel(
              qData['sessionLevel'] ?? qData['level'],
            );
            if (lvl > 0) distinctLevels.add(lvl);
          }
        }

        final sortedLevels = distinctLevels.toList()..sort();
        if (sortedLevels.isEmpty) {
          sortedLevels.addAll([1, 2, 3]);
        }

        return ScrollConfiguration(
          behavior: const _LeaderboardSwipeableScrollBehavior(),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                _buildLeaderboardLevelPill(
                  title: 'Overall Live Ranking',
                  level: null,
                  color: primaryGreen,
                  isSelected: _leaderboardSelectedLevel == null,
                ),
                const SizedBox(width: 8),
                ...sortedLevels.map((lvl) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _buildLeaderboardLevelPill(
                      title: _getLeaderboardLevelTitle(lvl),
                      level: lvl,
                      color: _getLeaderboardLevelColor(lvl),
                      isSelected: _leaderboardSelectedLevel == lvl,
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLeaderboardLevelPill({
    required String title,
    required int? level,
    required Color color,
    required bool isSelected,
  }) {
    return InkWell(
      onTap: () {
        setState(() {
          _leaderboardSelectedLevel = level;
        });
      },
      borderRadius: BorderRadius.circular(24),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? color : softBorder,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.28),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              const Icon(
                Icons.check_circle_rounded,
                size: 14,
                color: Colors.white,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFF374151),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveLeaderboardTable({
    required DocumentSnapshot<Map<String, dynamic>> session,
    required String quizCode,
    required bool isLive,
    required bool isWaiting,
    required bool isFinished,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: session.reference.collection('scores').snapshots(),
      builder: (context, scoreSnapshot) {
        if (!scoreSnapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: primaryGreen),
          );
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: session.reference.collection('join_requests').snapshots(),
          builder: (context, joinSnapshot) {
            if (!joinSnapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: primaryGreen),
              );
            }

            final scoreDocs = scoreSnapshot.data!.docs;
            final joinDocs = joinSnapshot.data!.docs;

            if (_leaderboardSelectedLevel == null) {
              return FutureBuilder<List<Map<String, dynamic>>>(
                future: _buildLeaderboardRows(quizCode, scoreDocs, joinDocs),
                builder: (context, rowsSnapshot) {
                  if (!rowsSnapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(30),
                      child: Center(
                        child: CircularProgressIndicator(color: primaryGreen),
                      ),
                    );
                  }

                  return _buildLeaderboardCardContainer(
                    rows: rowsSnapshot.data!,
                    isLive: isLive,
                    isWaiting: isWaiting,
                    levelTitle: 'Overall',
                  );
                },
              );
            }

            return FutureBuilder<List<Map<String, dynamic>>>(
              future: _buildLevelLeaderboardRows(
                sessionDoc: session,
                quizCode: quizCode,
                selectedLevel: _leaderboardSelectedLevel!,
                scoreDocs: scoreDocs,
                joinDocs: joinDocs,
              ),
              builder: (context, rowsSnapshot) {
                if (!rowsSnapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(30),
                    child: Center(
                      child: CircularProgressIndicator(color: primaryGreen),
                    ),
                  );
                }

                return _buildLeaderboardCardContainer(
                  rows: rowsSnapshot.data!,
                  isLive: isLive,
                  isWaiting: isWaiting,
                  levelTitle:
                      _getLeaderboardLevelTitle(_leaderboardSelectedLevel!),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildPodiumCard(List<Map<String, dynamic>> rows) {
    final first = rows.isNotEmpty ? rows[0] : null;
    final second = rows.length > 1 ? rows[1] : null;
    final third = rows.length > 2 ? rows[2] : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: softBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 10,
            offset: Offset(0, 4),
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
                  color: primaryGreen,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Top Performers',
                  style: TextStyle(
                    color: darkGreen,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: lightGreen,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'TOP 3 PODIUM',
                  style: TextStyle(
                    color: primaryGreen,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: _buildPodiumPerson(entry: second, rank: 2, height: 95),
              ),
              Expanded(
                child: _buildPodiumPerson(entry: first, rank: 1, height: 125),
              ),
              Expanded(
                child: _buildPodiumPerson(entry: third, rank: 3, height: 80),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPodiumPerson({
    required Map<String, dynamic>? entry,
    required int rank,
    required double height,
  }) {
    final bool isFirst = rank == 1;
    final trophyAsset = rank == 1
        ? 'assets/trophies/gold_trophy_3d.jpg'
        : (rank == 2
            ? 'assets/trophies/silver_trophy_3d.jpg'
            : 'assets/trophies/bronze_trophy_3d.jpg');

    final rankColor = rank == 1
        ? const Color(0xFFF59E0B)
        : (rank == 2 ? const Color(0xFF94A3B8) : const Color(0xFFD97706));

    final pedestalGradient = rank == 1
        ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
          )
        : (rank == 2
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFF8FAFC), Color(0xFFE2E8F0)],
              )
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFF7ED), Color(0xFFFED7AA)],
              ));

    final name = entry?['displayName']?.toString() ?? '---';
    final score = entry != null ? _scoreToInt(entry['score']) : 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 3D Trophy Circle Avatar
        Container(
          width: isFirst ? 58 : 50,
          height: isFirst ? 58 : 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: rankColor, width: 2),
            boxShadow: [
              BoxShadow(
                color: rankColor.withValues(alpha: isFirst ? 0.35 : 0.22),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipOval(
            child: entry != null
                ? Image.asset(
                    trophyAsset,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Icon(
                      Icons.emoji_events_rounded,
                      size: isFirst ? 30 : 24,
                      color: rankColor,
                    ),
                  )
                : Container(
                    color: const Color(0xFFF1F5F9),
                    child: Icon(
                      Icons.person_outline_rounded,
                      size: 24,
                      color: Colors.grey.shade400,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 6),

        // Contestant / Team Name
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: darkGreen,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Score
        Text(
          entry != null ? '$score pts' : '-',
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: primaryGreen,
          ),
        ),
        const SizedBox(height: 8),

        // Pedestal
        Container(
          height: height,
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            gradient: pedestalGradient,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            border: Border.all(
              color: rankColor.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Center(
            child: Container(
              width: isFirst ? 38 : 32,
              height: isFirst ? 38 : 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: rankColor, width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x10000000),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  '$rank',
                  style: TextStyle(
                    fontSize: isFirst ? 18 : 15,
                    fontWeight: FontWeight.w900,
                    color: rankColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLeaderboardCardContainer({
    required List<Map<String, dynamic>> rows,
    required bool isLive,
    required bool isWaiting,
    required String levelTitle,
  }) {
    if (rows.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: softBorder),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.people_outline_rounded,
              color: primaryGreen,
              size: 44,
            ),
            const SizedBox(height: 12),
            Text(
              isWaiting
                  ? 'Waiting for contestants to join and start answering...\r\nQuiz will begin shortly.'
                  : 'No contestants or scores recorded for this quiz yet.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rows.isNotEmpty) ...[
          _buildPodiumCard(rows),
          const SizedBox(height: 16),
        ],
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: softBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x08000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  color: Color(0xFFF7FAF8),
                  border: Border(bottom: BorderSide(color: softBorder)),
                ),
                child: Row(
                  children: [
                    Icon(
                      isLive
                          ? Icons.sensors_rounded
                          : Icons.leaderboard_rounded,
                      size: 16,
                      color: isLive ? primaryGreen : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$levelTitle Ranking (${rows.length} Contestants)',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: darkGreen,
                      ),
                    ),
                    const Spacer(),
                    if (isLive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'REAL-TIME',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF15803D),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _leaderboardRows(rows),
            ],
          ),
        ),
      ],
    );
  }

  Widget _leaderboardContent({required bool mobile}) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        mobile ? 18 : 30,
        mobile ? 20 : 28,
        mobile ? 18 : 30,
        35,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (mobile) ...[_mobileHeader(), const SizedBox(height: 20)],
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('quiz_sessions')
                    .limit(50)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _rankingMessageCard(
                      'Unable to load the leaderboard right now.',
                    );
                  }

                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(color: primaryGreen),
                    );
                  }

                  final allDocs = snapshot.data!.docs;
                  final published = allDocs.where((doc) {
                    final data = doc.data();
                    return data['published'] == true ||
                        data['isPublished'] == true;
                  }).toList();

                  if (published.isEmpty) {
                    return _rankingMessageCard(
                      'No published quizzes found yet.',
                    );
                  }

                  published.sort((a, b) {
                    final aStatus =
                        a.data()['status']?.toString().toLowerCase() ?? '';
                    final bStatus =
                        b.data()['status']?.toString().toLowerCase() ?? '';
                    final aIsLive =
                        aStatus == 'active' ||
                        aStatus == 'ongoing' ||
                        aStatus == 'started' ||
                        aStatus == 'waiting';
                    final bIsLive =
                        bStatus == 'active' ||
                        bStatus == 'ongoing' ||
                        bStatus == 'started' ||
                        bStatus == 'waiting';
                    if (aIsLive && !bIsLive) return -1;
                    if (!aIsLive && bIsLive) return 1;

                    final aDate = _dateValue(
                      a.data()['updatedAt'] ?? a.data()['createdAt'],
                    );
                    final bDate = _dateValue(
                      b.data()['updatedAt'] ?? b.data()['createdAt'],
                    );
                    return bDate.compareTo(aDate);
                  });

                  QueryDocumentSnapshot<Map<String, dynamic>>? selectedSession;
                  if (_leaderboardSelectedSessionId != null) {
                    for (final doc in published) {
                      if (doc.id == _leaderboardSelectedSessionId) {
                        selectedSession = doc;
                        break;
                      }
                    }
                  }

                  selectedSession ??= published.first;

                  final sessionData = selectedSession.data();
                  final status =
                      sessionData['status']?.toString().trim().toLowerCase() ??
                      '';
                  final isLive =
                      status == 'active' ||
                      status == 'ongoing' ||
                      status == 'started';
                  final isWaiting = status == 'waiting';
                  final isFinished =
                      status == 'finished' ||
                      status == 'completed' ||
                      status == 'ended';
                  final quizCode =
                      sessionData['quizCode']?.toString().trim().isNotEmpty ==
                              true
                          ? sessionData['quizCode'].toString().trim()
                          : selectedSession.id;

                  final quizTitle =
                      sessionData['quizTitle']?.toString().trim().isNotEmpty == true
                          ? sessionData['quizTitle'].toString().trim()
                          : (sessionData['title']?.toString().trim().isNotEmpty == true
                              ? sessionData['title'].toString().trim()
                              : 'TechNoWiz Quiz');

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Dark Green Hero Header Card (matching Badges format)
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(mobile ? 14 : 20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF14532D), Color(0xFF16A34A)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(mobile ? 20 : 24),
                          boxShadow: [
                            BoxShadow(
                              color: primaryGreen.withValues(alpha: 0.28),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: EdgeInsets.all(mobile ? 8 : 10),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.16),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          Icons.emoji_events_rounded,
                                          color: Colors.white,
                                          size: mobile ? 22 : 26,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'Live Leaderboard',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: mobile ? 16 : 18,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: -0.3,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              quizTitle,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                if (isLive)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: Colors.white30),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 7,
                                          height: 7,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF4ADE80),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Text(
                                          'LIVE',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else if (isWaiting)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: Colors.white30),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.hourglass_top_rounded,
                                          color: Colors.white,
                                          size: 12,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'WAITING',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else if (isFinished)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: Colors.white30),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.check_circle_rounded,
                                          color: Colors.white,
                                          size: 12,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'FINISHED',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: mobile ? 10 : 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'QUIZ CODE',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.white60,
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          quizCode,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: mobile ? 11.5 : 13,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    width: 1,
                                    height: 24,
                                    color: Colors.white24,
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: mobile ? 6 : 10,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'STATUS',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Colors.white60,
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            isLive
                                                ? 'Active'
                                                : (isWaiting
                                                    ? 'Waiting'
                                                    : 'Final Results'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: mobile ? 11.5 : 13,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 1,
                                    height: 24,
                                    color: Colors.white24,
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        left: mobile ? 6 : 10,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'ACTIVE FILTER',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Colors.white60,
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _leaderboardSelectedLevel == null
                                                ? 'Overall'
                                                : 'Level $_leaderboardSelectedLevel',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: const Color(0xFF86EFAC),
                                              fontSize: mobile ? 11.5 : 13,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 1. QUIZ HISTORY SELECTOR (History dropdown at top)
                      _buildLeaderboardQuizHistoryPicker(
                        publishedSessions: published,
                        selectedSession: selectedSession,
                      ),
                      const SizedBox(height: 14),

                      // 2. LEVEL SELECTOR TABS (Overall, Level 1, Level 2, Level 3)
                      _buildLeaderboardLevelSelectorBar(selectedSession),
                      const SizedBox(height: 16),

                      // 3. REAL-TIME LIVE TABLE
                      _buildLiveLeaderboardTable(
                        session: selectedSession,
                        quizCode: quizCode,
                        isLive: isLive,
                        isWaiting: isWaiting,
                        isFinished: isFinished,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 25),
              const Center(
                child: Text(
                  'TechNoWiz • Leaderboard',
                  style: TextStyle(color: Colors.black26, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _desktopSidebar([BuildContext? sidebarContext]) {
    final actionContext = sidebarContext ?? context;
    final user = FirebaseAuth.instance.currentUser;
    final name = profileData['name']?.toString().trim().isNotEmpty == true
        ? profileData['name'].toString()
        : user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!
        : 'Contestant';

    final role = getParticipationType();

    return Container(
      width: 238,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF0FFF4), Color(0xFFE5F9EB), Color(0xFFD8F5E1)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 18, 24),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [primaryGreen, darkGreen],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.school_rounded,
                      color: Colors.white,
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Text(
                    'TechNoWiz',
                    style: TextStyle(
                      color: darkGreen,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'CONTESTANT',
                  style: TextStyle(
                    color: Color(0x8C14532D),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            _sidebarItem(
              icon: Icons.dashboard_rounded,
              title: 'Dashboard',
              active: !_showLeaderboard && !_showBadges && !_showHistory,
              onTap: () => _openDashboard(actionContext),
            ),
            _sidebarItem(
              icon: Icons.leaderboard_rounded,
              title: 'Leaderboard',
              active: _showLeaderboard,
              onTap: () => _openLeaderboard(actionContext),
            ),
            _sidebarItem(
              icon: Icons.workspace_premium_rounded,
              title: 'Badges',
              active: _showBadges,
              onTap: () => _openBadges(actionContext),
            ),
            _sidebarItem(
              icon: Icons.history_rounded,
              title: 'History',
              active: _showHistory,
              onTap: () => _openHistory(actionContext),
            ),
            const Spacer(),

            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
              child: Material(
                color: Colors.white.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => showProfileDrawer(actionContext),
                  child: Padding(
                    padding: const EdgeInsets.all(11),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFD0F4DA),
                            image: profileImageProvider == null
                                ? null
                                : DecorationImage(
                                    image: profileImageProvider!,
                                    fit: BoxFit.cover,
                                  ),
                          ),
                          child: profileImageProvider == null
                              ? const Icon(
                                  Icons.person_rounded,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: darkGreen,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                role,
                                style: const TextStyle(
                                  color: Color(0xA614532D),
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Color(0x8C14532D),
                          size: 19,
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

  Widget _mobileHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final iconBox = compact ? 38.0 : 42.0;
        final logoSize = compact ? 22.0 : 25.0;
        final titleSize = compact ? 20.0 : 20.0;

        return Row(
          children: [
            Container(
              width: iconBox,
              height: iconBox,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [primaryGreen, darkGreen],
                ),
                borderRadius: BorderRadius.circular(compact ? 11 : 12),
              ),
              child: Icon(
                Icons.school_rounded,
                color: Colors.white,
                size: logoSize,
              ),
            ),
            SizedBox(width: compact ? 10 : 12),
            Expanded(
              child: Text(
                'TechNoWiz',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: darkGreen,
                  fontSize: titleSize,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _welcomeHero() {
    final user = FirebaseAuth.instance.currentUser;

    final participation = getParticipationType();
    final teamMembers = getTeamMembers();

    final personalName =
        profileData['name']?.toString().trim().isNotEmpty == true
        ? profileData['name'].toString().trim()
        : user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!.trim()
        : 'Contestant';

    final teamName =
        profileData['teamName']?.toString().trim().isNotEmpty == true
        ? profileData['teamName'].toString().trim()
        : 'Team';

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final compact = width < 600;
        final horizontalPadding = compact ? 14.0 : 24.0;
        final verticalPadding = compact ? 10.0 : 22.0;
        final titleSize = compact ? 19.0 : 24.0;
        final memberSize = compact ? 11.0 : 13.0;

        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFE9FBEF), Color(0xFFD4F7DF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(compact ? 16 : 20),
            boxShadow: [
              BoxShadow(
                color: Color(0x1A16A34A),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (participation == 'Team') ...[
                Text(
                  teamName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: darkGreen,
                    fontSize: titleSize,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                SizedBox(height: compact ? 4 : 8),
                Text(
                  'Team Members',
                  style: TextStyle(
                    color: Color(0xC714532D),
                    fontSize: memberSize,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                if (teamMembers.isEmpty)
                  Text(
                    'No team members yet',
                    style: TextStyle(
                      color: Color(0xC714532D),
                      fontSize: memberSize,
                    ),
                  )
                else
                  ...teamMembers.map(
                    (member) => Padding(
                      padding: const EdgeInsets.only(bottom: 1),
                      child: Text(
                        '• $member',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: darkGreen,
                          fontSize: memberSize,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
              ] else ...[
                Text(
                  personalName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: darkGreen,
                    fontSize: titleSize,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _dashboardContent({required bool mobile}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final compact = width < 600;

        // Keep Dashboard spacing consistent with the Leaderboard.
        final horizontalPadding = compact ? 18.0 : 30.0;
        final topPadding = compact ? 20.0 : 28.0;
        final bottomPadding = 35.0;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            topPadding,
            horizontalPadding,
            bottomPadding,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (mobile) ...[_mobileHeader(), const SizedBox(height: 20)],
                  _welcomeHero(),
                  const SizedBox(height: 18),
                  publishedQuizSection(mobile: mobile),
                  const SizedBox(height: 25),
                  const Center(
                    child: Text(
                      'TechNoWiz • Contestant Dashboard',
                      style: TextStyle(color: Colors.black26, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // =========================================================
  // BUILD
  // =========================================================

  int get _selectedBottomNavigationIndex {
    if (_showLeaderboard) return 1;
    if (_showBadges) return 2;
    if (_showHistory) return 3;
    return 0;
  }

  Widget _buildContestantBottomNavigation() {
    final items = <({IconData icon, String label, int index})>[
      (icon: Icons.dashboard_rounded, label: 'Dashboard', index: 0),
      (icon: Icons.bar_chart_rounded, label: 'Leaderboard', index: 1),
      (icon: Icons.workspace_premium_rounded, label: 'Badges', index: 2),
      (icon: Icons.history_rounded, label: 'History', index: 3),
      (icon: Icons.person_rounded, label: 'Profile', index: 4),
    ];

    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: softBorder)),
          boxShadow: [
            BoxShadow(
              color: Color(0x10000000),
              blurRadius: 10,
              offset: Offset(0, -3),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(5, 7, 5, 4),
        child: Row(
          children: items.map((item) {
            final selected = item.index == _selectedBottomNavigationIndex;
            return Expanded(
              child: InkWell(
                mouseCursor: SystemMouseCursors.click,
                borderRadius: BorderRadius.circular(13),
                hoverColor: lightGreen,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                splashFactory: NoSplash.splashFactory,
                onTap: () {
                  switch (item.index) {
                    case 0:
                      _openDashboard();
                      break;
                    case 1:
                      _openLeaderboard();
                      break;
                    case 2:
                      _openBadges();
                      break;
                    case 3:
                      _openHistory();
                      break;
                    case 4:
                      showProfileDrawer(context);
                      break;
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? lightGreen : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.icon,
                        size: 22,
                        color: selected
                            ? primaryGreen
                            : const Color(0xFF64816D),
                      ),
                      const SizedBox(height: 3),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: selected
                                ? primaryGreen
                                : const Color(0xFF64816D),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      drawer: Drawer(
        width: MediaQuery.of(context).size.width < 420
            ? MediaQuery.of(context).size.width * 0.82
            : 270,
        child: Builder(
          builder: (drawerContext) => _desktopSidebar(drawerContext),
        ),
      ),
      bottomNavigationBar: MediaQuery.of(context).size.width < 900
          ? _buildContestantBottomNavigation()
          : null,
      body: TechCircuitBackground(
        child: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 900;

          if (desktop) {
            return Row(
              children: [
                _desktopSidebar(),
                Expanded(
                  child: IndexedStack(
                    index: _selectedBottomNavigationIndex,
                    children: [
                      _dashboardContent(mobile: false),
                      _leaderboardContent(mobile: false),
                      _badgesContent(mobile: false),
                      const ContestantHistoryScreen(mobile: false),
                    ],
                  ),
                ),
              ],
            );
          }

          return IndexedStack(
            index: _selectedBottomNavigationIndex,
            children: [
              _dashboardContent(mobile: true),
              _leaderboardContent(mobile: true),
              _badgesContent(mobile: true),
              ContestantHistoryScreen(
                mobile: true,
                mobileHeader: _mobileHeader(),
              ),
            ],
          );
        },
      ),
    ),
  ),
    );
  }

  // =========================================================
  // RESULT QUIZ PICKER
  // =========================================================

  void showResultQuizPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('quiz_sessions')
                .orderBy('createdAt', descending: true)
                .limit(10)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox(
                  height: 220,
                  child: Center(
                    child: CircularProgressIndicator(color: primaryGreen),
                  ),
                );
              }

              final quizzes = snapshot.data!.docs;

              if (quizzes.isEmpty) {
                return const SizedBox(
                  height: 220,
                  child: Center(child: Text("No quiz results available.")),
                );
              }

              return Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Select Quiz",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: darkGreen,
                      ),
                    ),

                    const SizedBox(height: 15),

                    ...quizzes.map((quiz) {
                      final data = quiz.data() as Map<String, dynamic>;

                      final code = data['quizCode']?.toString() ?? quiz.id;

                      final title =
                          data['title']?.toString() ?? "TechNoWiz Quiz";

                      return ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: lightGreen,
                          child: Icon(
                            Icons.emoji_events_rounded,
                            color: primaryGreen,
                          ),
                        ),
                        title: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text("Code: $code"),
                        trailing: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 17,
                        ),
                        onTap: () {
                          Navigator.pop(sheetContext);

                          openPage(context, MyScoreScreen(quizCode: code));
                        },
                      );
                    }),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  // =========================================================
  // INIT
  // =========================================================

  @override
  void initState() {
    super.initState();
    if (widget.initialPage != null) {
      _applyTabSelection(widget.initialPage!);
    }
    loadProfile();
    _restoreLastPage();
    _restoreCurrentLeaderboardSession();
  }
}

class _LeaderboardSwipeableScrollBehavior extends MaterialScrollBehavior {
  const _LeaderboardSwipeableScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}
