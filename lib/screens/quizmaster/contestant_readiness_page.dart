import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'quizmaster_theme.dart';

class ContestantReadinessPage extends StatefulWidget {
  final String quizCode;
  final int startLevel;
  final bool closeParentPagesOnStart;
  final Future<void> Function() onStartQuiz;
  final Future<void> Function()? onReturnToSessions;

  const ContestantReadinessPage({
    super.key,
    required this.quizCode,
    this.startLevel = 1,
    this.closeParentPagesOnStart = true,
    required this.onStartQuiz,
    this.onReturnToSessions,
  });

  @override
  State<ContestantReadinessPage> createState() =>
      _ContestantReadinessPageState();
}

class _ContestantReadinessPageState extends State<ContestantReadinessPage> {
  String get quizCode => widget.quizCode;
  int get startLevel => widget.startLevel;
  bool get closeParentPagesOnStart => widget.closeParentPagesOnStart;
  Future<void> Function() get onStartQuiz => widget.onStartQuiz;
  Future<void> Function()? get onReturnToSessions => widget.onReturnToSessions;

  @override
  void initState() {
    super.initState();
    _saveCurrentPage();
  }

  Future<void> _saveCurrentPage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'technowiz_quizmaster_last_page',
        'participant_readiness',
      );
      await prefs.setString(
        'technowiz_quizmaster_current_quiz_code',
        widget.quizCode,
      );
      await prefs.setInt(
        'technowiz_quizmaster_readiness_level',
        widget.startLevel,
      );
    } catch (_) {}
  }

  static const Color _primaryBlue = QuizMasterColors.primaryBlue;
  static const Color _darkBlue = QuizMasterColors.darkBlue;

  String _participantName(Map<String, dynamic> data) {
    for (final key in [
      'displayName',
      'name',
      'fullName',
      'username',
      'email',
    ]) {
      final value = data[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return 'Contestant';
  }

  static List<String> _extractMembers(dynamic rawMembers) {
    if (rawMembers is! List) return [];
    final List<String> list = [];
    for (final m in rawMembers) {
      if (m is Map) {
        final name = (m['name'] ?? m['displayName'] ?? m['fullName'] ?? '')
            .toString()
            .trim();
        if (name.isNotEmpty) list.add(name);
      } else if (m != null) {
        final name = m.toString().trim();
        if (name.isNotEmpty) list.add(name);
      }
    }
    return list;
  }

  Widget _buildParticipantCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    bool isReady,
  ) {
    final data = doc.data();
    final uid = (data['uid'] ?? doc.id).toString();

    // Susiha kon ang team name ug members anaa na daan sa join_request doc
    final docTeamName = (data['teamName'] ?? '').toString().trim();
    final docMembers = _extractMembers(data['teamMembers'] ?? data['members']);
    final docType =
        (data['contestantType'] ?? '').toString().trim().toLowerCase();
    final individualName = _participantName(data);

    // Kon anaa na daan ang team details sa join_request, ipakita dayon
    if (docTeamName.isNotEmpty && docMembers.isNotEmpty) {
      return _participantCardLayout(
        title: docTeamName,
        subtitle: 'Members: ${docMembers.join(', ')}',
        isTeam: true,
        isReady: isReady,
      );
    }

    // Kon wala pa, kuhaa gikan sa users/{uid} aron masiguro nga makita ang team name ug members
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (context, userSnap) {
        final userData = userSnap.data?.data() ?? {};
        final userTeamName = (userData['teamName'] ?? '').toString().trim();
        final userMembers =
            _extractMembers(userData['teamMembers'] ?? userData['members']);
        final userType =
            (userData['contestantType'] ?? '').toString().trim().toLowerCase();

        final effectiveTeamName =
            docTeamName.isNotEmpty ? docTeamName : userTeamName;
        final effectiveMembers =
            docMembers.isNotEmpty ? docMembers : userMembers;
        final isTeam = docType == 'team' ||
            userType == 'team' ||
            effectiveTeamName.isNotEmpty;

        if (isTeam && effectiveTeamName.isNotEmpty) {
          final subtitle = effectiveMembers.isNotEmpty
              ? 'Members: ${effectiveMembers.join(', ')}'
              : (individualName.isNotEmpty &&
                      individualName != effectiveTeamName
                  ? 'Leader: $individualName'
                  : null);

          return _participantCardLayout(
            title: effectiveTeamName,
            subtitle: subtitle,
            isTeam: true,
            isReady: isReady,
          );
        }

        return _participantCardLayout(
          title: individualName,
          subtitle: null,
          isTeam: false,
          isReady: isReady,
        );
      },
    );
  }

  Widget _participantCardLayout({
    required String title,
    required String? subtitle,
    required bool isTeam,
    required bool isReady,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isReady
              ? const Color(0xFFBFE8CC)
              : QuizMasterColors.cardBorder,
          width: 1.2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x081E88E5),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: isReady
                ? const Color(0xFFE2F7E8)
                : const Color(0xFFE5F4FF),
            child: Icon(
              isTeam ? Icons.groups_rounded : Icons.person_rounded,
              color: isReady
                  ? const Color(0xFF198754)
                  : _primaryBlue,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _darkBlue,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
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
                          color: const Color(0xFFE5F4FF),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'TEAM',
                          style: TextStyle(
                            color: _primaryBlue,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF5B7A9C),
                      fontWeight: FontWeight.w500,
                      fontSize: 11.5,
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: isReady
                  ? const Color(0xFFE2F7E8)
                  : const Color(0xFFFFF1D6),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isReady ? 'READY' : 'WAITING',
              style: TextStyle(
                color: isReady
                    ? const Color(0xFF198754)
                    : const Color(0xFF9A6700),
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final quizRef = FirebaseFirestore.instance
        .collection('quiz_sessions')
        .doc(quizCode);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: QuizMasterAppBar(
        title: 'Contestant Readiness',
        subtitle: 'Code: $quizCode',
        badgeText: 'TECHNOWIZ • ARENA READINESS',
        badgeIcon: Icons.how_to_reg_rounded,
        onBack: () async {
          final navigator = Navigator.of(context);

          // Normal navigation: return to the previous page.
          if (navigator.canPop()) {
            navigator.pop();
            return;
          }

          // After a browser refresh, this page may be the first route,
          // so there may be nothing for maybePop() to pop. Restore Quiz
          // Sessions explicitly without changing quiz state or readiness.
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            'technowiz_quizmaster_last_page',
            'quiz_sessions',
          );
          await prefs.remove('technowiz_quizmaster_current_quiz_code');

          if (!context.mounted) return;
          final returnToSessions = onReturnToSessions;
          if (returnToSessions != null) {
            await returnToSessions();
          } else if (navigator.canPop()) {
            navigator.pop();
          } else {
            showQuizMasterTopNotification(
              context,
              'Unable to return to Quiz Sessions. Please reopen Quiz Sessions.',
              isError: true,
            );
          }
        },
      ),
      body: QuizMasterCircuitBackground(
        child: SafeArea(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: quizRef.collection('join_requests').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Unable to load contestants: ${snapshot.error}'),
                ),
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: _primaryBlue),
              );
            }

            // Makit-an ang tanang contestant nga naka-apil sa quiz:
            // - Dili makita ang na-eliminate (eliminated)
            // - Makita ang tanang maka-proceed o approved nga mga contestant
            final participants = (snapshot.data?.docs ?? []).where((doc) {
              final data = doc.data();
              final status =
                  (data['status'] ?? '').toString().trim().toLowerCase();
              final decision = (data['contestantDecision'] ?? '')
                  .toString()
                  .trim()
                  .toLowerCase();

              // Dili apil ang ni-leave o gi-reject
              if (status == 'left' ||
                  status == 'rejected' ||
                  status == 'declined' ||
                  data['leftQuiz'] == true) {
                return false;
              }

              // Dili pa apil ang nagpaabot pa og admin approval
              if (status == 'pending') {
                return false;
              }

              // Kung ang contestant gitugotan nga maka-proceed sa sunod level,
              // sigurado nga makita sila sa contestant readiness!
              if (decision == 'proceeding' || status == 'proceeding') {
                return true;
              }

              // Kung na-eliminate ang contestant, dili na sila makita
              if (decision == 'eliminated' ||
                  status == 'eliminated' ||
                  data['eliminated'] == true ||
                  data['isEliminated'] == true) {
                return false;
              }

              // Ang mga na-aprubahan nga contestant makita sa listahan
              return status == 'approved' || status.isEmpty;
            }).toList();

            // Readiness is level-specific. A contestant who was READY for
            // the previous level must remain WAITING for this level until they
            // press NEXT LEVEL and save readyForLevel == startLevel.
            bool isReadyForThisLevel(
              QueryDocumentSnapshot<Map<String, dynamic>> doc,
            ) {
              final data = doc.data();
              if (data['ready'] != true) return false;

              final rawReadyForLevel = data['readyForLevel'];
              final readyForLevel = rawReadyForLevel is num
                  ? rawReadyForLevel.toInt()
                  : int.tryParse(rawReadyForLevel?.toString() ?? '');

              // Keep the existing initial Level 1 ready-check compatible with
              // older records that do not yet have readyForLevel saved.
              if (startLevel == 1 && readyForLevel == null) return true;
              return readyForLevel == startLevel;
            }

            final readyCount = participants.where(isReadyForThisLevel).length;
            final allReady =
                participants.isNotEmpty && readyCount == participants.length;

            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: QuizMasterColors.cardBorder, width: 1.2),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x0A1E88E5),
                              blurRadius: 16,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.groups_rounded,
                                color: _primaryBlue,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'CONTESTANT',
                                style: TextStyle(
                                  color: _darkBlue,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE5F4FF),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFFBBDEFB)),
                              ),
                              child: Text(
                                '$readyCount/${participants.length} READY',
                                style: const TextStyle(
                                  color: _darkBlue,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (participants.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFDCEAF5)),
                          ),
                          child: const Text(
                            'No approved contestant yet.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black54),
                          ),
                        )
                      else
                        ...participants.map((doc) {
                          final isReady = isReadyForThisLevel(doc);
                          return _buildParticipantCard(doc, isReady);
                        }),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: allReady
                          ? () async {
                              // Notify the contestant screen that preparation has begun for this level.
                              // Do not start the countdown here; Quiz Control owns that step.
                              await quizRef.set({
                                'status': 'waiting',
                                'eventStatus': 'preparing_to_begin',
                                'preparedLevel': startLevel,
                                'preparationStartedAt':
                                    FieldValue.serverTimestamp(),
                                'levelStartedAt':
                                    FieldValue.serverTimestamp(),
                                'readyCheckActive': false,
                                'readyCheckType': 'level',
                                'readyCheckTitle':
                                    'Level $startLevel is about to begin',
                                'readyCheckMessage':
                                    'Please get ready. Level $startLevel will begin shortly.',
                                'countdownActive': false,
                                'countdown': 0,
                                'timer': 0,
                                'currentLevel': startLevel,
                                'level': startLevel,
                              }, SetOptions(merge: true));

                              if (!context.mounted) return;

                              // The callback handles navigation to Quiz Control.
                              // Keep the readiness page in place until it succeeds.
                              await onStartQuiz();
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryBlue,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFFB8D9F3),
                        disabledForegroundColor: Colors.white,
                        elevation: allReady ? 3 : 0,
                        shadowColor: const Color(0x401E88E5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'START LEVEL $startLevel',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
                if (!allReady)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Text(
                      'START LEVEL $startLevel becomes available when all eligible contestants are READY.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
}
