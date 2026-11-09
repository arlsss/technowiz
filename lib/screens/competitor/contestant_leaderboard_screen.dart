import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'technowiz_theme.dart';

class ContestantLeaderboardScreen extends StatefulWidget {
  const ContestantLeaderboardScreen({super.key});

  @override
  State<ContestantLeaderboardScreen> createState() =>
      _ContestantLeaderboardScreenState();
}

class _ContestantLeaderboardScreenState
    extends State<ContestantLeaderboardScreen> {
  static const Color primaryGreen = Color(0xFF07883D);
  static const Color darkGreen = Color(0xFF075C2B);
  static const Color lightGreen = Color(0xFFE9F8EF);
  static const Color backgroundColor = Color(0xFFF7FAF8);
  static const Color borderColor = Color(0xFFDCEDE3);
  static const Color textDark = Color(0xFF173426);
  static const Color textMuted = Color(0xFF72847A);

  final LayerLink _liveButtonLink = LayerLink();
  OverlayEntry? _liveOverlay;

  @override
  void dispose() {
    _removeLiveOverlay();
    super.dispose();
  }

  void _removeLiveOverlay() {
    _liveOverlay?.remove();
    _liveOverlay = null;
  }

  void _toggleLiveOverlay({required String sessionId}) {
    if (_liveOverlay != null) {
      _removeLiveOverlay();
      return;
    }

    final overlay = Overlay.of(context);
    _liveOverlay = OverlayEntry(
      builder: (overlayContext) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeLiveOverlay,
                child: const SizedBox.expand(),
              ),
            ),
            CompositedTransformFollower(
              link: _liveButtonLink,
              showWhenUnlinked: false,
              offset: const Offset(-300, 48),
              child: Material(
                color: Colors.transparent,
                child: SizedBox(
                  width: 300,
                  child: _liveRankingPopup(sessionId),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_liveOverlay!);
  }

  DateTime _dateValue(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  bool _isFinished(String status) {
    final normalized = status.trim().toLowerCase();

    // These statuses mean the quiz is already over.
    return normalized == 'finished' ||
        normalized == 'completed' ||
        normalized == 'ended';
  }

  bool _isLiveStatus(String status) {
    final normalized = status.trim().toLowerCase();

    // LIVE RANKING is available only while the quiz is actually running.
    // A "waiting" quiz must not expose old/current score documents.
    return normalized == 'active' ||
        normalized == 'ongoing' ||
        normalized == 'started';
  }

  bool _isApproved(dynamic value) {
    final valueText = value?.toString().trim().toLowerCase() ?? '';
    return valueText == 'approved' || valueText == 'accepted';
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _displayName(Map<String, dynamic> data) {
    return (data['teamName'] ??
                data['participantName'] ??
                data['displayName'] ??
                data['name'] ??
                'Contestant')
            .toString()
            .trim()
            .isEmpty
        ? 'Contestant'
        : (data['teamName'] ??
                  data['participantName'] ??
                  data['displayName'] ??
                  data['name'] ??
                  'Contestant')
              .toString()
              .trim();
  }

  List<String> _teamMembers(dynamic value) {
    if (value is! List) return [];

    final members = <String>[];

    for (final item in value) {
      String? name;

      if (item is String) {
        name = item.trim();
      } else if (item is Map) {
        final rawName = item['name'] ?? item['displayName'] ?? item['fullName'];
        name = rawName?.toString().trim();
      }

      if (name != null && name.isNotEmpty && !members.contains(name)) {
        members.add(name);
      }
    }

    return members;
  }

  List<_RankEntry> _buildRanking({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> requests,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> scores,
  }) {
    final Map<String, _RankEntry> grouped = {};

    // Add every approved contestant/team first so zero scores are included.
    // For team entries, keep the member names from the join request.
    for (final doc in requests) {
      final data = doc.data();
      if (!_isApproved(data['status'])) continue;

      final uid = data['uid']?.toString() ?? doc.id;
      final teamName = data['teamName']?.toString().trim() ?? '';
      final name = data['displayName']?.toString().trim().isNotEmpty == true
          ? data['displayName'].toString().trim()
          : data['name']?.toString().trim() ?? 'Contestant';
      final key = teamName.isNotEmpty ? 'team:$teamName' : 'user:$uid';
      final display = teamName.isNotEmpty ? teamName : name;
      final members = teamName.isNotEmpty
          ? _teamMembers(data['teamMembers'] ?? data['members'])
          : <String>[];

      final current = grouped[key];

      if (current == null) {
        grouped[key] = _RankEntry(name: display, score: 0, members: members);
      } else {
        grouped[key] = _RankEntry(
          name: current.name,
          score: current.score,
          members: {...current.members, ...members}.toList(),
        );
      }
    }

    // Add the real-time scores. updateScore() stores teamName in each score.
    for (final doc in scores) {
      final data = doc.data();
      final uid = data['uid']?.toString() ?? doc.id;
      final teamName = data['teamName']?.toString().trim() ?? '';
      final name = _displayName(data);
      final key = teamName.isNotEmpty ? 'team:$teamName' : 'user:$uid';
      final score = _toInt(data['score']);
      final members = teamName.isNotEmpty
          ? _teamMembers(data['teamMembers'] ?? data['members'])
          : <String>[];

      final current = grouped[key];
      if (current == null) {
        grouped[key] = _RankEntry(name: name, score: score, members: members);
      } else {
        // A team can have several member score documents; combine them.
        grouped[key] = _RankEntry(
          name: current.name,
          score: current.score + score,
          members: {...current.members, ...members}.toList(),
        );
      }
    }

    final result = grouped.values.toList();
    result.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return result;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _sessionsStream() {
    return FirebaseFirestore.instance
        .collection('quiz_sessions')
        .limit(20)
        .snapshots();
  }

  QueryDocumentSnapshot<Map<String, dynamic>>? _currentSession(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    if (snapshot.docs.isEmpty) return null;

    final docs = [...snapshot.docs];
    docs.sort((a, b) {
      final aData = a.data();
      final bData = b.data();
      final aDate = _dateValue(aData['updatedAt'] ?? aData['createdAt']);
      final bDate = _dateValue(bData['updatedAt'] ?? bData['createdAt']);
      return bDate.compareTo(aDate);
    });

    // Prefer the currently running/waiting quiz. This prevents an old
    // finished quiz from appearing as the current final ranking when there
    // is a newer quiz that is still waiting/active.
    for (final doc in docs) {
      final status =
          doc.data()['status']?.toString().trim().toLowerCase() ?? '';
      if (status == 'waiting' ||
          status == 'active' ||
          status == 'ongoing' ||
          status == 'started') {
        return doc;
      }
    }

    // Do NOT fall back to an old finished quiz.
    // If there is no waiting/active/current quiz, the contestant should see
    // the waiting state instead of an old FINAL RANKING.
    return null;
  }

  Widget _disabledLiveButton() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: lightGreen.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, color: textMuted, size: 9),
          SizedBox(width: 7),
          Text(
            'LIVE RANKING',
            style: TextStyle(
              color: textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: .4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveButton({required String sessionId}) {
    return CompositedTransformTarget(
      link: _liveButtonLink,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => _toggleLiveOverlay(sessionId: sessionId),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: lightGreen,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: borderColor),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, color: primaryGreen, size: 9),
                SizedBox(width: 7),
                Text(
                  'LIVE RANKING',
                  style: TextStyle(
                    color: darkGreen,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _liveRankingPopup(String sessionId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('quiz_sessions')
          .doc(sessionId)
          .collection('join_requests')
          .snapshots(),
      builder: (context, requestSnapshot) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('quiz_sessions')
              .doc(sessionId)
              .collection('scores')
              .snapshots(),
          builder: (context, scoreSnapshot) {
            if (requestSnapshot.hasError || scoreSnapshot.hasError) {
              return _popupCard(
                const Text(
                  'Unable to load live ranking.',
                  style: TextStyle(
                    color: textDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            }

            final entries = _buildRanking(
              requests: requestSnapshot.data?.docs ?? [],
              scores: scoreSnapshot.data?.docs ?? [],
            );

            return _popupCard(
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.bolt_rounded,
                        color: primaryGreen,
                        size: 19,
                      ),
                      const SizedBox(width: 7),
                      const Expanded(
                        child: Text(
                          'LIVE RANKING',
                          style: TextStyle(
                            color: darkGreen,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        '${entries.length} total',
                        style: const TextStyle(
                          color: textMuted,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 6),
                  if (entries.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                        'Waiting for participants...',
                        style: TextStyle(color: textMuted, fontSize: 11),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: entries.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 28,
                                  child: Text(
                                    '${index + 1}',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: index < 3
                                          ? primaryGreen
                                          : textMuted,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entry.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: textDark,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (entry.members.isNotEmpty)
                                        Text(
                                          'Members: ${entry.members.join(', ')}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: textMuted,
                                            fontSize: 8,
                                            height: 1.2,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${entry.score}',
                                  style: const TextStyle(
                                    color: primaryGreen,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
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

  Widget _popupCard(Widget child) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: borderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x25000000),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _waitingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: const Column(
        children: [
          Icon(Icons.hourglass_top_rounded, color: primaryGreen, size: 42),
          SizedBox(height: 14),
          Text(
            'Waiting for the quiz to finish',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: darkGreen,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 7),
          Text(
            'The final ranking will appear here after the Quiz Master finishes the quiz.\nUse LIVE RANKING above to view the current partial scores.',
            textAlign: TextAlign.center,
            style: TextStyle(color: textMuted, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _finalRankingCard({required List<_RankEntry> entries}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.emoji_events_rounded,
                color: primaryGreen,
                size: 21,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'FINAL RANKING',
                  style: TextStyle(
                    color: darkGreen,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: lightGreen,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'FINISHED',
                  style: TextStyle(
                    color: darkGreen,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text(
                  'No final ranking available.',
                  style: TextStyle(color: textMuted, fontSize: 11),
                ),
              ),
            )
          else
            for (int i = 0; i < entries.length; i++)
              Container(
                margin: EdgeInsets.only(
                  bottom: i == entries.length - 1 ? 0 : 7,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: i == 0 ? lightGreen : backgroundColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 32,
                      child: TechRankLeaderboardIcon(rank: i + 1),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entries[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: textDark,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (entries[i].members.isNotEmpty)
                            Text(
                              'Members: ${entries[i].members.join(', ')}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: textMuted,
                                fontSize: 8,
                                height: 1.2,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      '${entries[i].score}',
                      style: const TextStyle(
                        color: primaryGreen,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _content({required bool mobile}) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _sessionsStream(),
      builder: (context, sessionSnapshot) {
        if (sessionSnapshot.hasError) {
          return Center(
            child: Text('Unable to load leaderboard: ${sessionSnapshot.error}'),
          );
        }

        if (!sessionSnapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: primaryGreen),
          );
        }

        final session = _currentSession(sessionSnapshot.data!);
        if (session == null) {
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              mobile ? 18 : 30,
              mobile ? 16 : 28,
              mobile ? 18 : 35,
              35,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Leaderboard',
                            style: TextStyle(
                              color: darkGreen,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        _disabledLiveButton(),
                      ],
                    ),
                    const SizedBox(height: 22),
                    _waitingCard(),
                  ],
                ),
              ),
            ),
          );
        }

        final sessionData = session.data();
        final status = sessionData['status']?.toString() ?? '';
        final finished = _isFinished(status);

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('quiz_sessions')
              .doc(session.id)
              .collection('join_requests')
              .snapshots(),
          builder: (context, requestSnapshot) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('quiz_sessions')
                  .doc(session.id)
                  .collection('scores')
                  .snapshots(),
              builder: (context, scoreSnapshot) {
                final entries = _buildRanking(
                  requests: requestSnapshot.data?.docs ?? [],
                  scores: scoreSnapshot.data?.docs ?? [],
                );

                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    mobile ? 18 : 30,
                    mobile ? 16 : 28,
                    mobile ? 18 : 35,
                    35,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Leaderboard',
                                  style: TextStyle(
                                    color: darkGreen,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              if (_isLiveStatus(status))
                                _liveButton(sessionId: session.id),
                            ],
                          ),
                          const SizedBox(height: 22),
                          if (finished)
                            _finalRankingCard(entries: entries)
                          else
                            _waitingCard(),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _sidebarItem({
    required IconData icon,
    required String title,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Material(
        color: active ? Colors.white.withValues(alpha: 0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: active ? Colors.white : Colors.white.withValues(alpha: 0.58),
                  size: 21,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: active
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.62),
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
                if (active)
                  Container(
                    width: 4,
                    height: 24,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00B95A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _leaderboardDrawer(BuildContext context) {
    return Drawer(
      width: 264,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF062E1A), Color(0xFF075C2B), Color(0xFF07883D)],
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
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.psychology_alt_rounded,
                        color: Colors.white,
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 11),
                    const Text(
                      'TechNoWiz',
                      style: TextStyle(
                        color: Colors.white,
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
                      color: Colors.white.withValues(alpha: 0.48),
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
                active: false,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
              ),
              _sidebarItem(
                icon: Icons.leaderboard_rounded,
                title: 'Leaderboard',
                active: true,
                onTap: () => Navigator.pop(context),
              ),
              _sidebarItem(
                icon: Icons.workspace_premium_rounded,
                title: 'Badges',
                active: false,
                onTap: () {
                  Navigator.pop(context);
                  showTopSnackBar(context, 
                    const SnackBar(content: Text('Badges coming soon.')),
                  );
                },
              ),
              _sidebarItem(
                icon: Icons.history_rounded,
                title: 'History',
                active: false,
                onTap: () {
                  Navigator.pop(context);
                  showTopSnackBar(context, 
                    const SnackBar(content: Text('History coming soon.')),
                  );
                },
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      drawer: _leaderboardDrawer(context),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: 'Menu',
            icon: const Icon(Icons.menu_rounded),
            color: darkGreen,
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        titleSpacing: 0,
        title: const Row(
          children: [
            Icon(Icons.psychology_alt_rounded, color: primaryGreen, size: 26),
            SizedBox(width: 9),
            Text(
              'TechNoWiz',
              style: TextStyle(
                color: darkGreen,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) =>
            _content(mobile: constraints.maxWidth < 700),
      ),
    );
  }
}

class _RankEntry {
  final String name;
  final int score;
  final List<String> members;

  const _RankEntry({
    required this.name,
    required this.score,
    this.members = const [],
  });
}
