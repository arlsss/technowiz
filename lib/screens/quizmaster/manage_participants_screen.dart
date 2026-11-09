import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'quizmaster_dashboard.dart';
import 'quiz_sessions_screen.dart';
import 'leaderboard_screen.dart';
import 'profile_screen.dart';
import 'quizmaster_theme.dart';

class ManageParticipantsScreen extends StatefulWidget {
  final String quizCode;
  final bool initialShowHistory;

  const ManageParticipantsScreen({
    super.key,
    required this.quizCode,
    this.initialShowHistory = false,
  });

  @override
  State<ManageParticipantsScreen> createState() =>
      _ManageParticipantsScreenState();
}

class _ManageParticipantsScreenState extends State<ManageParticipantsScreen> {
  final Set<int> _hoveredBottomItems = <int>{};
  final Map<String, String> _nameCache = {};

  static const String _lastPageKey = 'technowiz_quizmaster_last_page';
  static const String _quizCodeKey = 'technowiz_quizmaster_current_quiz_code';

  String? _selectedQuizCode;
  bool _showHistory = false;
  bool _isViewingFromHistory = false;

  @override
  void initState() {
    super.initState();
    _showHistory = widget.initialShowHistory;
    final initialCode = widget.quizCode.trim();
    if (initialCode.isNotEmpty) {
      _selectedQuizCode = initialCode;
    }
    _saveLastPage(
      _showHistory ? 'participants_history' : 'participants',
      savedQuizCode: _selectedQuizCode,
    );
  }

  Future<void> _saveLastPage(String page, {String? savedQuizCode}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastPageKey, page);

    if (savedQuizCode != null && savedQuizCode.trim().isNotEmpty) {
      await prefs.setString(_quizCodeKey, savedQuizCode.trim());
    } else {
      await prefs.remove(_quizCodeKey);
    }
  }

  static const Color primaryBlue = Color(0xFF168BEB);
  static const Color darkBlue = Color(0xFF1E293B);

  // ============================================================
  // GET PARTICIPANT NAME
  // ============================================================
  final Map<String, Map<String, dynamic>> _participantDisplayCache = {};

  Future<Map<String, dynamic>> _getParticipantDisplayInfo(
    String uid,
    Map<String, dynamic> data,
  ) async {
    final cached = _participantDisplayCache[uid];
    if (cached != null) return cached;

    String docTeam = (data['teamName'] ?? '').toString().trim();
    String docType =
        (data['contestantType'] ?? '').toString().trim().toLowerCase();
    List<String> docMembers = [];
    final rawM = data['teamMembers'] ?? data['members'];
    if (rawM is List) {
      for (final m in rawM) {
        final s = m is Map
            ? (m['name'] ?? '').toString().trim()
            : m.toString().trim();
        if (s.isNotEmpty && !docMembers.contains(s)) docMembers.add(s);
      }
    }

    String personalName = (data['realName'] ??
            data['fullName'] ??
            data['displayName'] ??
            data['name'] ??
            data['username'] ??
            '')
        .toString()
        .trim();

    bool isTeam = docType == 'team' || docTeam.isNotEmpty;

    if (isTeam && docTeam.isNotEmpty && docMembers.isNotEmpty) {
      final info = {
        'title': docTeam,
        'isTeam': true,
        'teamName': docTeam,
        'members': docMembers,
      };
      _participantDisplayCache[uid] = info;
      return info;
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data() ?? {};
        final userType =
            (userData['contestantType'] ?? '').toString().trim().toLowerCase();
        final userTeam = (userData['teamName'] ?? '').toString().trim();
        final userPersonal = (userData['fullName'] ??
                userData['name'] ??
                userData['displayName'] ??
                personalName)
            .toString()
            .trim();

        final List<String> userMembers = [];
        final rawUserM = userData['teamMembers'] ?? userData['members'];
        if (rawUserM is List) {
          for (final m in rawUserM) {
            final s = m is Map
                ? (m['name'] ?? '').toString().trim()
                : m.toString().trim();
            if (s.isNotEmpty && !userMembers.contains(s)) userMembers.add(s);
          }
        }

        final effectiveTeam = docTeam.isNotEmpty ? docTeam : userTeam;
        final effectiveMembers =
            docMembers.isNotEmpty ? docMembers : userMembers;
        final effectiveIsTeam = docType == 'team' ||
            userType == 'team' ||
            effectiveTeam.isNotEmpty;
        final effectivePersonal = userPersonal.isNotEmpty
            ? userPersonal
            : (personalName.isNotEmpty ? personalName : uid);

        final title = effectiveIsTeam
            ? (effectiveTeam.isNotEmpty ? effectiveTeam : effectivePersonal)
            : effectivePersonal;

        final info = {
          'title': title,
          'isTeam': effectiveIsTeam,
          'teamName': effectiveTeam,
          'members': effectiveMembers,
        };
        _participantDisplayCache[uid] = info;
        return info;
      }
    } catch (_) {}

    final title = isTeam
        ? (docTeam.isNotEmpty
            ? docTeam
            : (personalName.isNotEmpty ? personalName : uid))
        : (personalName.isNotEmpty ? personalName : uid);

    final info = {
      'title': title,
      'isTeam': isTeam,
      'teamName': docTeam,
      'members': docMembers,
    };
    _participantDisplayCache[uid] = info;
    return info;
  }


  // ============================================================
  // REMOVE PARTICIPANT
  // ============================================================
  Future<void> _removeParticipant(
    BuildContext context,
    String quizCode,
    String uid,
    String participantName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.person_remove_rounded,
                  color: Colors.red.shade700,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Remove Participant?',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to remove "$participantName" from this quiz?\n\n'
            'They will be removed from this session.',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF475569),
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text(
                'CANCEL',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text(
                'REMOVE',
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
      final quizRef = firestore.collection('quiz_sessions').doc(quizCode);
      final batch = firestore.batch();

      batch.delete(quizRef.collection('join_requests').doc(uid));
      batch.delete(quizRef.collection('participants').doc(uid));
      batch.delete(quizRef.collection('scores').doc(uid));

      await batch.commit();

      _nameCache.remove(uid);

      if (!context.mounted) return;

      showQuizMasterTopNotification(
        context,
        '$participantName has been removed from this quiz.',
        isWarning: true,
      );
    } catch (e) {
      if (!context.mounted) return;

      showQuizMasterTopNotification(
        context,
        'Unable to remove participant: $e',
        isError: true,
      );
    }
  }

  // ============================================================
  // HERO CARD
  // ============================================================
  Widget _buildHeroCard({
    required BuildContext context,
    required String quizTitle,
    required String quizCode,
    required String status,
    required int totalParticipants,
    required int readyCount,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> allSessions,
  }) {
    final isLive = status == 'active' || status == 'live' || status == 'started';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F4C81), Color(0xFF1689E8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F4C81).withValues(alpha: 0.28),
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
            // Top row: Header Pill & Status Pill & History Button
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                      Icon(Icons.groups_rounded, color: Colors.white, size: 14),
                      SizedBox(width: 6),
                      Text(
                        'MANAGE PARTICIPANTS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                          color: isLive ? const Color(0xFF4ADE80) : const Color(0xFFFBBF24),
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
                const Spacer(),
                InkWell(
                  onTap: () {
                    setState(() => _showHistory = true);
                    _saveLastPage('participants_history');
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
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 5),

            // Quiz Code
            Text(
              'Quiz Code: $quizCode',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.88),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),

            // Switch Quiz Dropdown if multiple quizzes exist
            if (allSessions.length > 1) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    dropdownColor: const Color(0xFF0F4C81),
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
                        _saveLastPage('participants', savedQuizCode: newCode);
                      }
                    },
                  ),
                ),
              ),
            ],

            const SizedBox(height: 14),

            // Metrics row
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 9,
                      horizontal: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'TOTAL JOINED',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$totalParticipants',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
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
                      vertical: 9,
                      horizontal: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'READY',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$readyCount',
                          style: const TextStyle(
                            color: Color(0xFF4ADE80),
                            fontSize: 18,
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
                      vertical: 9,
                      horizontal: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'SESSION',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          status.isEmpty ? 'WAITING' : status.toUpperCase(),
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
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_showHistory && !_isViewingFromHistory,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_showHistory) {
          setState(() => _showHistory = false);
          return;
        }
        if (_isViewingFromHistory) {
          setState(() {
            _isViewingFromHistory = false;
            _selectedQuizCode = null;
          });
          return;
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        bottomNavigationBar: _buildBottomNavigation(),
        appBar: _showHistory
            ? null
            : AppBar(
                automaticallyImplyLeading: false,
                backgroundColor: Colors.white,
                foregroundColor: darkBlue,
                elevation: 0,
                scrolledUnderElevation: 0,
                surfaceTintColor: Colors.white,
                centerTitle: false,
                leading: const SizedBox.shrink(),
                leadingWidth: 12,
                toolbarHeight: 62,
                titleSpacing: 0,
                bottom: const PreferredSize(
                  preferredSize: Size.fromHeight(1),
                  child: Divider(height: 1, thickness: 1, color: Color(0xFFDCEAF5)),
                ),
                title: const QuizMasterBrandTitle(subtitle: 'Manage Participants'),
              ),
        drawer: _showHistory
            ? null
            : Drawer(
                backgroundColor: Colors.white,
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE5F4FF),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.school_rounded,
                                color: Color(0xFF168BEB),
                                size: 21,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'TechNoWiz',
                              style: TextStyle(
                                color: Color(0xFF245C91),
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _drawerItem(
                        context,
                        icon: Icons.dashboard_outlined,
                        label: 'Dashboard',
                        onTap: () async {
                          await _saveLastPage('dashboard');
                          if (!context.mounted) return;
                          Navigator.of(context).pushReplacement(
                            PageRouteBuilder<void>(
                              pageBuilder: (_, _, _) => const QuizMasterDashboard(),
                              transitionDuration: Duration.zero,
                              reverseTransitionDuration: Duration.zero,
                              transitionsBuilder:
                                  (_, animation, secondaryAnimation, child) => child,
                            ),
                          );
                        },
                      ),
                      _drawerItem(
                        context,
                        icon: Icons.quiz_outlined,
                        label: 'Quizzes',
                        onTap: () async {
                          await _saveLastPage('quiz_sessions');
                          if (!context.mounted) return;
                          Navigator.of(context).pushReplacement(
                            PageRouteBuilder<void>(
                              pageBuilder: (_, _, _) => const QuizSessionsScreen(),
                              transitionDuration: Duration.zero,
                              reverseTransitionDuration: Duration.zero,
                              transitionsBuilder:
                                  (_, animation, secondaryAnimation, child) => child,
                            ),
                          );
                        },
                      ),
                      _drawerItem(
                        context,
                        icon: Icons.leaderboard_outlined,
                        label: 'Leaderboard',
                        onTap: () async {
                          await _saveLastPage('leaderboard', savedQuizCode: _selectedQuizCode ?? widget.quizCode);
                          if (!context.mounted) return;
                          Navigator.of(context).pushReplacement(
                            PageRouteBuilder<void>(
                              pageBuilder: (_, _, _) =>
                                  LeaderboardScreen(quizCode: _selectedQuizCode ?? widget.quizCode),
                              transitionDuration: Duration.zero,
                              reverseTransitionDuration: Duration.zero,
                              transitionsBuilder:
                                  (_, animation, secondaryAnimation, child) => child,
                            ),
                          );
                        },
                      ),
                      _drawerItem(
                        context,
                        icon: Icons.groups_outlined,
                        label: 'Participants',
                        selected: true,
                        onTap: () async {
                          await _saveLastPage('participants', savedQuizCode: _selectedQuizCode ?? widget.quizCode);
                          if (!context.mounted) return;
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                ),
              ),
        body: QuizMasterCircuitBackground(
          child: _showHistory
              ? ParticipantsHistoryScreen(
                  onBack: () {
                    if (mounted) setState(() => _showHistory = false);
                  },
                  onSelectQuiz: (quizCode) {
                    if (!mounted) return;
                    setState(() {
                      _selectedQuizCode = quizCode;
                      _isViewingFromHistory = true;
                      _showHistory = false;
                    });
                  },
                )
              : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('quiz_sessions')
              .snapshots(),
          builder: (context, sessionListSnapshot) {
            if (sessionListSnapshot.connectionState == ConnectionState.waiting &&
                !sessionListSnapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: primaryBlue),
              );
            }

            if (sessionListSnapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(25),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 60),
                      const SizedBox(height: 14),
                      const Text(
                        'Unable to load quiz sessions.',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: darkBlue),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${sessionListSnapshot.error}',
                        style: const TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
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

            final isViewingHistoryQuiz = _isViewingFromHistory &&
                _selectedQuizCode != null &&
                _selectedQuizCode!.trim().isNotEmpty;

            QueryDocumentSnapshot<Map<String, dynamic>>? chosenDoc;

            if (isViewingHistoryQuiz) {
              for (final d in allSessions) {
                final code = (d.data()['quizCode'] ?? d.id).toString().trim();
                if (code == _selectedQuizCode!.trim() ||
                    d.id.trim() == _selectedQuizCode!.trim()) {
                  chosenDoc = d;
                  break;
                }
              }
            } else {
              if (activeSessions.isEmpty) {
                return Column(
                  children: [
                    _buildHeroCard(
                      context: context,
                      quizTitle: 'No Active Quiz',
                      quizCode: '------',
                      status: 'WAITING',
                      totalParticipants: 0,
                      readyCount: 0,
                      allSessions: const [],
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                        child: Center(
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              vertical: 36,
                              horizontal: 20,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: const Color(0xFFDCEAF5),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFEAF5FD),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.people_outline_rounded,
                                    size: 32,
                                    color: primaryBlue,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                const Text(
                                  'No Active Quiz',
                                  style: TextStyle(
                                    color: darkBlue,
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Participants will appear here once an active quiz begins.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Color(0xFF6B7280),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              chosenDoc = activeSessions.first;

              if (_selectedQuizCode != null &&
                  _selectedQuizCode!.trim().isNotEmpty) {
                final target = _selectedQuizCode!.trim();
                for (final d in activeSessions) {
                  final code = (d.data()['quizCode'] ?? d.id).toString().trim();
                  if (code == target || d.id.trim() == target) {
                    chosenDoc = d;
                    break;
                  }
                }
              }
            }

            if (chosenDoc == null) {
              return Column(
                children: [
                  _buildHeroCard(
                    context: context,
                    quizTitle: 'No Active Quiz',
                    quizCode: '------',
                    status: 'WAITING',
                    totalParticipants: 0,
                    readyCount: 0,
                    allSessions: const [],
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                      child: Center(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            vertical: 36,
                            horizontal: 20,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: const Color(0xFFDCEAF5),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFEAF5FD),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.people_outline_rounded,
                                  size: 32,
                                  color: primaryBlue,
                                ),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'No Active Quiz',
                                style: TextStyle(
                                  color: darkBlue,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Participants will appear here once an active quiz begins.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF6B7280),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            final effectiveCode =
                (chosenDoc.data()['quizCode'] ?? chosenDoc.id).toString().trim();
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

            // Stream both join_requests and participants to guarantee all joined contestants show up
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('quiz_sessions')
                  .doc(effectiveCode)
                  .collection('join_requests')
                  .snapshots(),
              builder: (context, joinSnap) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('quiz_sessions')
                      .doc(effectiveCode)
                      .collection('participants')
                      .snapshots(),
                  builder: (context, participantsSnap) {
                    if ((joinSnap.connectionState == ConnectionState.waiting &&
                            !joinSnap.hasData) ||
                        (participantsSnap.connectionState ==
                                ConnectionState.waiting &&
                            !participantsSnap.hasData)) {
                      return const Center(
                        child: CircularProgressIndicator(color: primaryBlue),
                      );
                    }

                    final joinDocs = joinSnap.data?.docs ?? [];
                    final partDocs = participantsSnap.data?.docs ?? [];

                    // Combine both collections keyed by uid so nothing is missed
                    final Map<String, Map<String, dynamic>> combined = {};

                    for (final doc in joinDocs) {
                      final data = Map<String, dynamic>.from(doc.data());
                      data['uid'] = (data['uid'] ?? doc.id).toString().trim();
                      combined[doc.id] = data;
                    }

                    for (final doc in partDocs) {
                      final data = Map<String, dynamic>.from(doc.data());
                      data['uid'] = (data['uid'] ?? doc.id).toString().trim();
                      if (combined.containsKey(doc.id)) {
                        combined[doc.id]!.addAll(data);
                      } else {
                        combined[doc.id] = data;
                      }
                    }

                    final participantsList = combined.values.toList();
                    final readyCount = participantsList
                        .where((p) => p['ready'] == true)
                        .length;

                    // Sort alphabetically by name
                    participantsList.sort((a, b) {
                      final nameA = (a['name'] ??
                              a['displayName'] ??
                              a['realName'] ??
                              '')
                          .toString()
                          .toLowerCase();
                      final nameB = (b['name'] ??
                              b['displayName'] ??
                              b['realName'] ??
                              '')
                          .toString()
                          .toLowerCase();
                      return nameA.compareTo(nameB);
                    });

                    return Column(
                      children: [
                        // Hero Card with Quiz Details & Stats
                        _buildHeroCard(
                          context: context,
                          quizTitle: quizTitle,
                          quizCode: effectiveCode,
                          status: rawStatus,
                          totalParticipants: participantsList.length,
                          readyCount: readyCount,
                          allSessions: isViewingHistoryQuiz
                              ? [chosenDoc!]
                              : activeSessions,
                        ),

                        if (isViewingHistoryQuiz) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                            child: Container(
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
                                      'Viewing History Participants',
                                      style: TextStyle(
                                        color: Color(0xFFC2410C),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        _isViewingFromHistory = false;
                                        _selectedQuizCode = null;
                                      });
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 2,
                                      ),
                                      child: Text(
                                        'Back to Live',
                                        style: TextStyle(
                                          color: primaryBlue,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],

                        // Participants list
                        Expanded(
                          child: participantsList.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 72,
                                        height: 72,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEAF5FD),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: const Color(0xFFD4E8F8),
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.people_outline_rounded,
                                          size: 36,
                                          color: Color(0xFF168BEB),
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      Text(
                                        isViewingHistoryQuiz
                                            ? 'No Participants'
                                            : 'No Participants Yet',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: darkBlue,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        isViewingHistoryQuiz
                                            ? 'No participants found in this past quiz session.'
                                            : 'Contestants who enter quiz code "$effectiveCode" will appear here live.',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.black54,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 4, 16, 20),
                                  itemCount: participantsList.length,
                                  itemBuilder: (context, index) {
                                    final p = participantsList[index];
                                    final uid = (p['uid'] ?? '').toString();
                                    final isReady = p['ready'] == true;
                                    final statusStr = (p['status'] ?? 'joined')
                                        .toString()
                                        .trim()
                                        .toLowerCase();
                                    final score =
                                        p['score']?.toString() ?? '0';

                                    return FutureBuilder<Map<String, dynamic>>(
                                      future: _getParticipantDisplayInfo(uid, p),
                                      builder: (context, infoSnapshot) {
                                        final info = infoSnapshot.data;
                                        final name = (info?['title'] ??
                                                p['name'] ??
                                                p['displayName'] ??
                                                p['realName'] ??
                                                uid)
                                            .toString();
                                        final isTeam =
                                            (info?['isTeam'] ?? false) as bool;
                                        final members = List<String>.from(
                                          (info?['members'] as List?) ??
                                              const [],
                                        );

                                         return Container(
                                           margin: const EdgeInsets.only(
                                             bottom: 10,
                                           ),
                                           decoration: BoxDecoration(
                                             color: Colors.white,
                                             borderRadius:
                                                 BorderRadius.circular(16),
                                             border: Border.all(
                                               color: const Color(0xFFDCEAF8),
                                             ),
                                             boxShadow: [
                                               BoxShadow(
                                                 color: Colors.black.withValues(
                                                   alpha: 0.03,
                                                 ),
                                                 blurRadius: 8,
                                                 offset: const Offset(0, 2),
                                               ),
                                             ],
                                           ),
                                           child: Padding(
                                             padding: const EdgeInsets.symmetric(
                                               horizontal: 14,
                                               vertical: 12,
                                             ),
                                             child: Row(
                                               children: [
                                                 // Number / Avatar index
                                                 Container(
                                                   width: 42,
                                                   height: 42,
                                                   decoration: BoxDecoration(
                                                     color: isTeam
                                                         ? const Color(0xFFE5F4FF)
                                                         : const Color(0xFFEAF5FF),
                                                     borderRadius:
                                                         BorderRadius.circular(12),
                                                   ),
                                                   child: Center(
                                                     child: Icon(
                                                       isTeam
                                                           ? Icons.groups_rounded
                                                           : Icons.person_rounded,
                                                       color: const Color(0xFF168BEB),
                                                       size: 22,
                                                     ),
                                                   ),
                                                 ),
                                                 const SizedBox(width: 12),

                                                 // Name, Team, Members, and Badges
                                                 Expanded(
                                                   child: Column(
                                                     crossAxisAlignment:
                                                         CrossAxisAlignment.start,
                                                     children: [
                                                       Text(
                                                         name,
                                                         maxLines: 1,
                                                         overflow: TextOverflow
                                                             .ellipsis,
                                                         style: const TextStyle(
                                                           color: darkBlue,
                                                           fontSize: 15,
                                                           fontWeight:
                                                               FontWeight.bold,
                                                         ),
                                                       ),
                                                       if (isTeam && members.isNotEmpty) ...[
                                                         const SizedBox(
                                                           height: 3,
                                                         ),
                                                         Row(
                                                           children: [
                                                             const Icon(
                                                               Icons.group_outlined,
                                                               size: 13,
                                                               color: Color(
                                                                 0xFF168BEB,
                                                               ),
                                                             ),
                                                             const SizedBox(
                                                               width: 4,
                                                             ),
                                                             Expanded(
                                                               child: Text(
                                                                 'Members: ${members.join(', ')}',
                                                                 maxLines: 2,
                                                                 overflow:
                                                                     TextOverflow
                                                                         .ellipsis,
                                                                 style:
                                                                     const TextStyle(
                                                                   color: Color(
                                                                     0xFF5B7A9C,
                                                                   ),
                                                                   fontSize: 11.5,
                                                                   fontWeight:
                                                                       FontWeight
                                                                           .w500,
                                                                 ),
                                                               ),
                                                             ),
                                                           ],
                                                         ),
                                                       ],
                                                       const SizedBox(height: 5),
                                                       Wrap(
                                                         spacing: 6,
                                                         runSpacing: 4,
                                                         children: [
                                                           // Team / Solo Badge
                                                           Container(
                                                             padding: const EdgeInsets.symmetric(
                                                               horizontal: 7,
                                                               vertical: 3,
                                                             ),
                                                             decoration: BoxDecoration(
                                                               color: isTeam
                                                                   ? const Color(0xFFE5F4FF)
                                                                   : const Color(0xFFF1F5F9),
                                                               borderRadius: BorderRadius.circular(6),
                                                             ),
                                                             child: Text(
                                                               isTeam
                                                                   ? (members.isNotEmpty
                                                                       ? 'TEAM (${members.length})'
                                                                       : 'TEAM')
                                                                   : 'SOLO',
                                                               style: TextStyle(
                                                                 color: isTeam
                                                                     ? const Color(0xFF168BEB)
                                                                     : const Color(0xFF475569),
                                                                 fontSize: 9,
                                                                 fontWeight: FontWeight.w700,
                                                                 letterSpacing: 0.3,
                                                               ),
                                                             ),
                                                           ),
                                                          // Ready Badge
                                                          if (isReady)
                                                            Container(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                horizontal: 7,
                                                                vertical: 3,
                                                              ),
                                                              decoration:
                                                                  BoxDecoration(
                                                                color: Colors
                                                                    .green
                                                                    .withValues(
                                                                      alpha: 0.12,
                                                                    ),
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                  10,
                                                                ),
                                                              ),
                                                              child: const Text(
                                                                'READY',
                                                                style:
                                                                    TextStyle(
                                                                  color: Colors
                                                                      .green,
                                                                  fontSize: 9,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                ),
                                                              ),
                                                            ),

                                                          // Status badge
                                                          Container(
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                              horizontal: 7,
                                                              vertical: 3,
                                                            ),
                                                            decoration:
                                                                BoxDecoration(
                                                              color:
                                                                  const Color(
                                                                0xFFE5F4FF,
                                                              ),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                10,
                                                              ),
                                                            ),
                                                            child: Text(
                                                              statusStr
                                                                  .replaceAll(
                                                                    '_',
                                                                    ' ',
                                                                  )
                                                                  .toUpperCase(),
                                                              style:
                                                                  const TextStyle(
                                                                color: Color(
                                                                  0xFF168BEB,
                                                                ),
                                                                fontSize: 9,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                            ),
                                                          ),

                                                          // Score badge if score > 0
                                                          if (score != '0')
                                                            Container(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                horizontal: 7,
                                                                vertical: 3,
                                                              ),
                                                              decoration:
                                                                  BoxDecoration(
                                                                color: Colors
                                                                    .purple
                                                                    .withValues(
                                                                      alpha: 0.10,
                                                                    ),
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                  10,
                                                                ),
                                                              ),
                                                              child: Text(
                                                                'Score: $score pts',
                                                                style:
                                                                    const TextStyle(
                                                                  color: Colors
                                                                      .purple,
                                                                  fontSize: 9,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                ),
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 8),

                                                // REMOVE BUTTON
                                                Material(
                                                  color: Colors.transparent,
                                                  child: InkWell(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      10,
                                                    ),
                                                    onTap: () =>
                                                        _removeParticipant(
                                                      context,
                                                      effectiveCode,
                                                      uid,
                                                      name,
                                                    ),
                                                    child: Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 10,
                                                        vertical: 6,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: Colors.red
                                                            .withValues(
                                                          alpha: 0.08,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(10),
                                                        border: Border.all(
                                                          color: Colors.red
                                                              .withValues(
                                                            alpha: 0.22,
                                                          ),
                                                        ),
                                                      ),
                                                      child: const Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            Icons
                                                                .delete_outline_rounded,
                                                            color: Colors.red,
                                                            size: 16,
                                                          ),
                                                          SizedBox(width: 4),
                                                          Text(
                                                            'Remove',
                                                            style: TextStyle(
                                                              color: Colors.red,
                                                              fontSize: 11,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
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
                                      },
                                    );
                                  },
                                ),
                        ),
                      ],
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
        child: StatefulBuilder(
          builder: (context, setNavState) {
            return Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFD8EAF8))),
              ),
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 5),
              child: Row(
                children: items.map((item) {
                  final selected = item.index == 3;
                  final hovered = _hoveredBottomItems.contains(item.index);
                  return Expanded(
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      onEnter: (_) => setNavState(
                        () => _hoveredBottomItems.add(item.index),
                      ),
                      onExit: (_) => setNavState(
                        () => _hoveredBottomItems.remove(item.index),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _handleBottomNavigation(item.index),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 3,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: selected || hovered
                                ? const Color(0xFFE5F4FF)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                item.icon,
                                size: 20,
                                color: selected || hovered
                                    ? const Color(0xFF168BEB)
                                    : const Color(0xFF718096),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: selected || hovered
                                      ? const Color(0xFF168BEB)
                                      : const Color(0xFF718096),
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
            );
          },
        ),
      ),
    );
  }

  Future<void> _handleBottomNavigation(int index) async {
    if (index == 3) {
      if (_showHistory) {
        setState(() => _showHistory = false);
      }
      return; // Already on Participants.
    }
    if (index == 4) {
      showQuizMasterProfileSideSheet(context);
      return;
    }

    if (index == 0) {
      await _saveLastPage('dashboard');
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => const QuizMasterDashboard(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, animation, secondaryAnimation, child) =>
              child,
        ),
      );
      return;
    }

    if (index == 1) {
      await _saveLastPage('quiz_sessions');
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => const QuizSessionsScreen(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, animation, secondaryAnimation, child) =>
              child,
        ),
      );
      return;
    }

    if (index == 2) {
      final codeToUse = _selectedQuizCode ?? widget.quizCode;
      await _saveLastPage('leaderboard', savedQuizCode: codeToUse);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => LeaderboardScreen(quizCode: codeToUse),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, animation, secondaryAnimation, child) =>
              child,
        ),
      );
    }
  }

  Widget _drawerItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool selected = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 1),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFE4F2FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? const Color(0xFF2196F3)
                    : const Color(0xFF68737D),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? const Color(0xFF2196F3)
                      : const Color(0xFF4D5964),
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================================================================
// PARTICIPANTS HISTORY SCREEN
// ================================================================
class ParticipantsHistoryScreen extends StatefulWidget {
  final VoidCallback? onBack;
  final ValueChanged<String>? onSelectQuiz;

  const ParticipantsHistoryScreen({
    super.key,
    this.onBack,
    this.onSelectQuiz,
  });

  @override
  State<ParticipantsHistoryScreen> createState() =>
      _ParticipantsHistoryScreenState();
}

class _ParticipantsHistoryScreenState extends State<ParticipantsHistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  static const Color primaryBlue = Color(0xFF168BEB);
  static const Color textDark = Color(0xFF17245A);
  static const Color textMuted = Color(0xFF71849E);
  static const Color borderColor = Color(0xFFDCEAF5);

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
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: textDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.white,
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded, color: textDark),
          onPressed: () {
            if (widget.onBack != null) {
              widget.onBack!();
            } else {
              Navigator.maybePop(context);
            }
          },
        ),
        titleSpacing: 0,
        title: const Text(
          'Participants History',
          style: TextStyle(
            color: textDark,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: borderColor),
        ),
      ),
      body: QuizMasterCircuitBackground(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: TextField(
                controller: _searchController,
                onChanged: (val) {
                  setState(() => _searchQuery = val.trim().toLowerCase());
                },
                decoration: InputDecoration(
                  hintText: 'Search quiz title or code...',
                  hintStyle: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 13,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: primaryBlue,
                    size: 20,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: primaryBlue, width: 1.5),
                  ),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('quiz_sessions')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(color: primaryBlue),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'Unable to load quiz history.\n${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: textMuted, fontSize: 12),
                        ),
                      ),
                    );
                  }

                  final allQuizzes = snapshot.data?.docs ?? [];

                  final quizzes = allQuizzes.where((quiz) {
                    if (_searchQuery.isEmpty) return true;
                    final data = quiz.data() as Map<String, dynamic>;
                    final title = (data['title'] ??
                            data['quizName'] ??
                            data['name'] ??
                            '')
                        .toString()
                        .toLowerCase();
                    final code = (data['quizCode'] ?? quiz.id)
                        .toString()
                        .toLowerCase();
                    return title.contains(_searchQuery) ||
                        code.contains(_searchQuery);
                  }).toList();

                  if (quizzes.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(25),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: const BoxDecoration(
                                color: Color(0xFFEAF5FD),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.history_rounded,
                                size: 34,
                                color: primaryBlue,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'No Matching Quizzes'
                                  : 'No Quiz History',
                              style: const TextStyle(
                                color: textDark,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'Try searching with another keyword or quiz code.'
                                  : 'Past and finished quizzes will appear here.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
                    itemCount: quizzes.length,
                    itemBuilder: (context, index) {
                      final quiz = quizzes[index];
                      final data = quiz.data() as Map<String, dynamic>;
                      final title =
                          (data['title'] ?? data['quizName'] ?? data['name'])
                                      ?.toString()
                                      .trim()
                                      .isNotEmpty ==
                                  true
                              ? (data['title'] ??
                                      data['quizName'] ??
                                      data['name'])
                                  .toString()
                                  .trim()
                              : 'Untitled Quiz';
                      final quizCode =
                          (data['quizCode'] ?? quiz.id).toString().trim();
                      final friendlyStatus =
                          _friendlyQuizStatus(data['status']);
                      final isFinished = friendlyStatus == 'FINISHED';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFE5F4FF),
                            child: Icon(
                              Icons.groups_rounded,
                              color: primaryBlue,
                            ),
                          ),
                          title: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: textDark,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Row(
                              children: [
                                Text(
                                  'Code: $quizCode',
                                  style: const TextStyle(
                                    color: textMuted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isFinished
                                        ? const Color(0xFFF1F5F9)
                                        : const Color(0xFFE0F2FE),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    friendlyStatus,
                                    style: TextStyle(
                                      color: isFinished
                                          ? const Color(0xFF64748B)
                                          : primaryBlue,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            color: primaryBlue,
                          ),
                          onTap: () {
                            widget.onSelectQuiz?.call(quizCode);
                          },
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
    );
  }
}
