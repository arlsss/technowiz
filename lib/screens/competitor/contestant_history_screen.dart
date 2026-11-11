import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'my_score_screen.dart';
import '../../navigation_persistence.dart';

/// Unified Contestant Quiz History View with Emerald Arena styling.
/// Displays completed quizzes, scores, ranks, and allows deleting history items.
class ContestantHistoryScreen extends StatefulWidget {
  final bool mobile;
  final Widget? mobileHeader;

  const ContestantHistoryScreen({
    super.key,
    this.mobile = false,
    this.mobileHeader,
  });

  @override
  State<ContestantHistoryScreen> createState() =>
      _ContestantHistoryScreenState();
}

class _ContestantHistoryScreenState extends State<ContestantHistoryScreen> {
  static const Color primaryGreen = Color(0xFF16A34A);
  static const Color darkGreen = Color(0xFF14532D);
  static const Color lightGreen = Color(0xFFF0FDF4);
  static const Color softBorder = Color(0xFFDCEFE1);

  bool _loading = true;
  String? _error;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _quizzes = [];
  final Map<String, Map<String, dynamic>> _scoresByQuizId = {};
  final Set<String> _deletedIds = {};

  int _totalScoreSum = 0;
  int? _bestRank;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  String _prefsKey(String uid) => 'contestant_deleted_history_$uid';

  DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  String _formatDate(dynamic value) {
    final date = _toDate(value);
    if (date == null) return 'Date not available';

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

    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';

    return '${months[date.month - 1]} ${date.day}, ${date.year} • $hour:$minute $period';
  }

  Future<void> _fetchHistory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _loading = _quizzes.isEmpty;
        _error = null;
      });
    }

    try {
      final uid = user.uid;
      final prefs = await SharedPreferences.getInstance();
      final localDeleted = prefs.getStringList(_prefsKey(uid)) ?? const [];
      _deletedIds.addAll(localDeleted);

      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        final remoteDeleted = userDoc.data()?['deletedHistoryQuizIds'];
        if (remoteDeleted is List) {
          for (final item in remoteDeleted) {
            final id = item?.toString().trim() ?? '';
            if (id.isNotEmpty) {
              _deletedIds.add(id);
            }
          }
        }
      } catch (_) {}

      final quizSnapshot = await FirebaseFirestore.instance
          .collection('quiz_sessions')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      final scoresMap = <String, Map<String, dynamic>>{};
      int scoreSum = 0;
      int? topRank;

      final checked = await Future.wait(
        quizSnapshot.docs.map((quiz) async {
          final data = quiz.data();
          final code = data['quizCode']?.toString().trim().isNotEmpty == true
              ? data['quizCode'].toString().trim()
              : quiz.id;
          if (_deletedIds.contains(quiz.id) || _deletedIds.contains(code)) {
            return null;
          }

          final scoreSnapshot = await quiz.reference
              .collection('scores')
              .doc(uid)
              .get();

          if (!scoreSnapshot.exists) return null;
          final scoreData = scoreSnapshot.data() ?? {};
          if (scoreData['hiddenFromHistory'] == true) {
            _deletedIds.add(quiz.id);
            _deletedIds.add(code);
            return null;
          }

          scoresMap[quiz.id] = scoreData;

          final sc = scoreData['score'];
          if (sc is num) scoreSum += sc.toInt();

          final rk = scoreData['rank'];
          if (rk is num) {
            final rInt = rk.toInt();
            if (rInt > 0) {
              topRank = topRank == null
                  ? rInt
                  : (rInt < topRank! ? rInt : topRank);
            }
          }

          return quiz;
        }),
      );

      if (!mounted) return;
      setState(() {
        _scoresByQuizId
          ..clear()
          ..addAll(scoresMap);
        _quizzes = checked
            .whereType<QueryDocumentSnapshot<Map<String, dynamic>>>()
            .toList();
        _totalScoreSum = scoreSum;
        _bestRank = topRank;
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

  Future<void> _deleteSingleHistory(
    QueryDocumentSnapshot<Map<String, dynamic>> quiz,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final data = quiz.data();
    final code = data['quizCode']?.toString().trim().isNotEmpty == true
        ? data['quizCode'].toString().trim()
        : quiz.id;
    final title = data['title']?.toString().trim().isNotEmpty == true
        ? data['title'].toString().trim()
        : 'TechNoWiz Quiz';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.red),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Delete History',
                style: TextStyle(
                  color: darkGreen,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "$title" (Code: $code) from your history?',
          style: const TextStyle(color: Colors.black54, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final uid = user.uid;
    setState(() {
      _deletedIds.add(quiz.id);
      _deletedIds.add(code);
      _quizzes.removeWhere((q) => q.id == quiz.id);
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey(uid), _deletedIds.toList());

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'deletedHistoryQuizIds': FieldValue.arrayUnion([quiz.id, code]),
      }, SetOptions(merge: true));
    } catch (_) {}

    try {
      await quiz.reference.collection('scores').doc(uid).set({
        'hiddenFromHistory': true,
      }, SetOptions(merge: true));
    } catch (_) {}

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Quiz removed from your history.'),
        backgroundColor: primaryGreen,
      ),
    );
  }

  Future<void> _clearAllHistory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _quizzes.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.delete_sweep_rounded, color: Colors.red),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Clear All History',
                style: TextStyle(
                  color: darkGreen,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to clear your entire quiz history? This action cannot be undone.',
          style: TextStyle(color: Colors.black54, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('CLEAR ALL'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final uid = user.uid;
    final allIds = <String>[];
    for (final quiz in _quizzes) {
      allIds.add(quiz.id);
      final data = quiz.data();
      final code = data['quizCode']?.toString().trim();
      if (code != null && code.isNotEmpty) {
        allIds.add(code);
      }
    }

    setState(() {
      _deletedIds.addAll(allIds);
      _quizzes.clear();
      _scoresByQuizId.clear();
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey(uid), _deletedIds.toList());

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'deletedHistoryQuizIds': FieldValue.arrayUnion(allIds),
      }, SetOptions(merge: true));
    } catch (_) {}

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All quiz history has been cleared.'),
        backgroundColor: primaryGreen,
      ),
    );
  }

  Widget _buildHeroHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF14532D), Color(0xFF16A34A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: darkGreen.withValues(alpha: 0.18),
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
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
                child: const Icon(
                  Icons.history_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quiz History',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Review your past scores, rankings, and completed quiz challenges.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (_quizzes.isNotEmpty)
                IconButton(
                  tooltip: 'Clear All History',
                  onPressed: _clearAllHistory,
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.delete_sweep_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _statBadge(
                icon: Icons.assignment_turned_in_rounded,
                label: 'Completed',
                value: '${_quizzes.length}',
              ),
              _statBadge(
                icon: Icons.emoji_events_rounded,
                label: 'Best Rank',
                value: _bestRank != null ? '#$_bestRank' : 'N/A',
              ),
              _statBadge(
                icon: Icons.stars_rounded,
                label: 'Total Points',
                value: '$_totalScoreSum',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statBadge({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: softBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: lightGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.history_rounded,
                  size: 38,
                  color: primaryGreen,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'No Quiz History Yet',
                style: TextStyle(
                  color: darkGreen,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your completed quiz results will appear here after you participate in quizzes.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _historyChip({
    required IconData icon,
    required String text,
    Color? chipColor,
    Color? textColor,
  }) {
    final fg = textColor ?? darkGreen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: chipColor ?? lightGreen,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: textColor != null
              ? textColor.withValues(alpha: 0.3)
              : softBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: fg, size: 14),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuizCard(
    QueryDocumentSnapshot<Map<String, dynamic>> quiz,
    String uid,
  ) {
    final data = quiz.data();
    final code = data['quizCode']?.toString().trim().isNotEmpty == true
        ? data['quizCode'].toString().trim()
        : quiz.id;
    final title = data['title']?.toString().trim().isNotEmpty == true
        ? data['title'].toString().trim()
        : 'TechNoWiz Quiz';

    final scoreData = _scoresByQuizId[quiz.id] ?? {};
    final score = scoreData['score'] ?? 0;
    final rank = scoreData['rank'];
    final updatedAt = scoreData['updatedAt'];

    Color? rankBgColor;
    Color? rankTextColor;
    IconData rankIcon = Icons.leaderboard_rounded;
    String? trophyAsset;

    if (rank != null) {
      final rankInt = int.tryParse(rank.toString()) ?? 0;
      if (rankInt == 1) {
        rankBgColor = const Color(0xFFFEF3C7);
        rankTextColor = const Color(0xFFB45309);
        rankIcon = Icons.emoji_events_rounded;
        trophyAsset = 'assets/trophies/gold_trophy_3d.jpg';
      } else if (rankInt == 2) {
        rankBgColor = const Color(0xFFF1F5F9);
        rankTextColor = const Color(0xFF475569);
        rankIcon = Icons.military_tech_rounded;
        trophyAsset = 'assets/trophies/silver_trophy_3d.jpg';
      } else if (rankInt == 3) {
        rankBgColor = const Color(0xFFFFEDD5);
        rankTextColor = const Color(0xFFC2410C);
        rankIcon = Icons.workspace_premium_rounded;
        trophyAsset = 'assets/trophies/bronze_trophy_3d.jpg';
      }
    }

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          await CompetitorNavPersistence.savePage('my_score', quizCode: code);
          if (!context.mounted) return;
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MyScoreScreen(quizCode: code),
            ),
          );
          if (mounted) {
            await CompetitorNavPersistence.savePage('history');
          }
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: softBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: rankBgColor ?? lightGreen,
                  shape: BoxShape.circle,
                  border: trophyAsset != null
                      ? Border.all(
                          color: (int.tryParse(rank.toString()) ?? 0) == 1
                              ? const Color(0xFFF59E0B)
                              : ((int.tryParse(rank.toString()) ?? 0) == 2
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFFD97706)),
                          width: 1.8,
                        )
                      : null,
                ),
                child: trophyAsset != null
                    ? ClipOval(
                        child: Image.asset(
                          trophyAsset,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            rankIcon,
                            color: rankTextColor ?? primaryGreen,
                            size: 26,
                          ),
                        ),
                      )
                    : Icon(
                        rankIcon,
                        color: rankTextColor ?? primaryGreen,
                        size: 26,
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: darkGreen,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Code: $code',
                            style: const TextStyle(
                              color: Color(0xFF4B5563),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _formatDate(updatedAt ?? data['createdAt']),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.black45,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _historyChip(
                          icon: Icons.stars_rounded,
                          text: 'Score: $score pts',
                        ),
                        if (rank != null)
                          _historyChip(
                            icon: rankIcon,
                            text: 'Rank: #$rank',
                            chipColor: rankBgColor,
                            textColor: rankTextColor,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Delete from history',
                onPressed: () => _deleteSingleHistory(quiz),
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.red.shade400,
                  size: 22,
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.black26,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        widget.mobile ? 18 : 30,
        widget.mobile ? 20 : 28,
        widget.mobile ? 18 : 30,
        35,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.mobile && widget.mobileHeader != null) ...[
                widget.mobileHeader!,
                const SizedBox(height: 20),
              ],
              _buildHeroHeader(),
              const SizedBox(height: 20),
              if (user == null)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Please log in to view your history.'),
                  ),
                )
              else if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: CircularProgressIndicator(color: primaryGreen),
                  ),
                )
              else if (_error != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Unable to load your history.\n$_error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ),
                )
              else if (_quizzes.isEmpty)
                _buildEmptyState()
              else
                RefreshIndicator(
                  color: primaryGreen,
                  onRefresh: _fetchHistory,
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _quizzes.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final quiz = _quizzes[index];
                      return _buildQuizCard(quiz, user.uid);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
