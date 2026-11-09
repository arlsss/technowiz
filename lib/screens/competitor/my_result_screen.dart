import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MyResultScreen extends StatefulWidget {
  final String quizCode;

  const MyResultScreen({super.key, required this.quizCode});

  @override
  State<MyResultScreen> createState() => _MyResultScreenState();
}

class _MyResultScreenState extends State<MyResultScreen> {
  bool _showRanking = false;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  DocumentReference<Map<String, dynamic>> get _session => FirebaseFirestore
      .instance
      .collection('quiz_sessions')
      .doc(widget.quizCode);

  // Diri ginasulat sa contestant ang iyang confirmation
  // (parehas ra sa ready / resultConfirmed).
  DocumentReference<Map<String, dynamic>> get _myRequest =>
      _session.collection('join_requests').doc(_uid);

  int _scoreOf(Map<String, dynamic> data) =>
      int.tryParse(data['score']?.toString() ?? '') ?? 0;

  bool _isEliminated(Map<String, dynamic> data) =>
      data['eliminated'] == true ||
      data['status']?.toString().toLowerCase() == 'eliminated';

  // Parehas nga score: kinsay mas paspas ni-submit ang mas taas og rank
  List<int> _computeRanks(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final ranks = <int>[];
    for (int i = 0; i < docs.length; i++) {
      final data = docs[i].data();
      final raw = data['rank'] ?? data['levelRank'] ?? data['currentRank'];
      final int? saved = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
      if (saved != null && saved > 0) {
        ranks.add(saved);
        continue;
      }
      if (i == 0) {
        ranks.add(1);
        continue;
      }
      final prevData = docs[i - 1].data();
      final currData = docs[i].data();
      final prevScore = _scoreOf(prevData);
      final currScore = _scoreOf(currData);
      final rawPrev = prevData['updatedAt'];
      final rawCurr = currData['updatedAt'];
      final prevTime = rawPrev is Timestamp ? rawPrev.millisecondsSinceEpoch : 0;
      final currTime = rawCurr is Timestamp ? rawCurr.millisecondsSinceEpoch : 0;

      if (prevScore == currScore &&
          (prevTime == 0 || currTime == 0 || prevTime == currTime)) {
        ranks.add(ranks[i - 1]);
      } else {
        ranks.add(i + 1);
      }
    }
    return ranks;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Final Result'),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _session.snapshots(),
        builder: (context, sessionSnap) {
          if (!sessionSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final published =
              sessionSnap.data!.data()?['eliminationPublished'] == true;

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _myRequest.snapshots(),
            builder: (context, requestSnap) {
              final confirmed =
                  requestSnap.data?.data()?['eliminationConfirmed'] == true;

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _session.collection('scores').snapshots(),
                builder: (context, scoreSnap) {
                  if (!scoreSnap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  // Sort sa client aron dili kinahanglan ang index
                  final docs = [...scoreSnap.data!.docs]
                    ..sort(
                      (a, b) {
                        final byScore =
                            _scoreOf(b.data()).compareTo(_scoreOf(a.data()));
                        if (byScore != 0) return byScore;
                        final rawA = a.data()['updatedAt'];
                        final rawB = b.data()['updatedAt'];
                        final timeA = rawA is Timestamp
                            ? rawA.millisecondsSinceEpoch
                            : 0;
                        final timeB = rawB is Timestamp
                            ? rawB.millisecondsSinceEpoch
                            : 0;
                        if (timeA > 0 && timeB > 0 && timeA != timeB) {
                          return timeA.compareTo(timeB);
                        }
                        return (a.data()['name']?.toString() ?? a.id).compareTo(
                          b.data()['name']?.toString() ?? b.id,
                        );
                      },
                    );

                  final mine = docs.where((d) => d.id == _uid).toList();
                  final myData = mine.isEmpty
                      ? <String, dynamic>{}
                      : mine.first.data();

                  final myScore = _scoreOf(myData);
                  final eliminated = _isEliminated(myData);

                  // Eliminated: makita dayon pag-click sa Quiz Master.
                  // Wala ma-eliminate: makita human ma-announce.
                  if (published || eliminated) {
                    return _resultView(
                      eliminated: eliminated,
                      confirmed: confirmed,
                    );
                  }

                  if (_showRanking) {
                    return _rankingView(docs);
                  }

                  return _scoreView(myScore);
                },
              );
            },
          );
        },
      ),
    );
  }

  // ============================================================
  // SCORE VIEW
  // ============================================================

  Widget _scoreView(int myScore) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipOval(
              child: Image.asset(
                'assets/trophies/gold_trophy_3d.jpg',
                width: 100,
                height: 100,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.emoji_events, size: 90, color: Colors.orange),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'QUIZ FINISHED',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            Text('Your Score: $myScore', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () => setState(() => _showRanking = true),
                icon: const Icon(Icons.leaderboard),
                label: const Text(
                  'PARTIAL RANKING',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Waiting for the Quiz Master to announce the results.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // PARTIAL RANKING VIEW
  // ============================================================

  Widget _rankingView(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final ranks = _computeRanks(docs);

    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Partial Ranking',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final d = docs[i].data();
              final isMe = docs[i].id == _uid;
              final name = (d['name'] ?? d['displayName'] ?? docs[i].id)
                  .toString();
              final team = d['teamName']?.toString().trim() ?? '';
              final rawMembers = d['teamMembers'] ?? d['members'];
              final List<String> members = [];
              if (rawMembers is List) {
                for (final m in rawMembers) {
                  final s = m is Map ? (m['name'] ?? '').toString().trim() : m.toString().trim();
                  if (s.isNotEmpty && !members.contains(s)) members.add(s);
                }
              }

              return Card(
                color: isMe ? Colors.blue.shade50 : null,
                child: ListTile(
                  leading: CircleAvatar(child: Text('#${ranks[i]}')),
                  title: Text(
                    isMe ? '$name (You)' : name,
                    style: TextStyle(
                      fontWeight: isMe ? FontWeight.bold : FontWeight.w600,
                    ),
                  ),
                  subtitle: members.isNotEmpty
                      ? Text('Members: ${members.join(', ')}')
                      : (team.isNotEmpty && team != name ? Text(team) : null),
                  trailing: Text(
                    '${_scoreOf(d)} pts',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextButton(
            onPressed: () => setState(() => _showRanking = false),
            child: const Text('BACK'),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // RESULT VIEW (Eliminated / Congratulations)
  // ============================================================

  Widget _resultView({required bool eliminated, required bool confirmed}) {
    // Nag-confirm na ug eliminated: wala nay button
    if (confirmed && eliminated) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'You have been eliminated.\nThank you for participating!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    // Nag-proceed na: naghulat sa sunod nga round
    if (confirmed && !eliminated) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'You are through! Please wait for the Quiz Master to start the next round.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              eliminated ? Icons.sentiment_dissatisfied : Icons.celebration,
              size: 80,
              color: eliminated ? Colors.red : Colors.green,
            ),
            const SizedBox(height: 18),
            Text(
              eliminated ? 'Thank you for participating!' : 'Congratulations!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: eliminated ? Colors.red : Colors.green,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              eliminated
                  ? 'Sadly, you have been eliminated.'
                  : 'You are moving on to the next round.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: Colors.black54),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => _showConfirmDialog(eliminated),
                style: ElevatedButton.styleFrom(
                  backgroundColor: eliminated ? Colors.red : Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  eliminated ? 'CONFIRM' : 'PROCEED',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CONFIRM / PROCEED DIALOG
  // ============================================================

  Future<void> _showConfirmDialog(bool eliminated) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(eliminated ? 'Confirm' : 'Proceed'),
        content: Text(
          eliminated
              ? 'Are you sure you want to leave the quiz?'
              : 'Are you ready to proceed to the next round?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('YES'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    try {
      await _myRequest.set({
        'eliminationConfirmed': true,
        'eliminationConfirmedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}

    if (!mounted) return;

    if (eliminated) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    // Kung nag-proceed: mo-update ang screen ngadto sa "You are through!"
  }
}
