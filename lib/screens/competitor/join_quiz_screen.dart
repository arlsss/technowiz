import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'waiting_room_screen.dart';
import 'technowiz_theme.dart';

class JoinQuizScreen extends StatefulWidget {
  final String quizCode;

  const JoinQuizScreen({super.key, required this.quizCode});

  @override
  State<JoinQuizScreen> createState() => _JoinQuizScreenState();
}

class _JoinQuizScreenState extends State<JoinQuizScreen> {
  bool joining = true;
  bool waitingApproval = false;
  bool _completingApproval = false;
  bool _navigationStarted = false;
  String? errorMessage;
  String _realName = 'Contestant';
  String _email = '';
  String _role = 'Contestant';
  String _quizTitle = 'TechNoWiz Quiz';
  int _currentLevel = 1;

  static const Color primaryGreen = Color(0xFF16A34A);
  static const Color darkGreen = Color(0xFF166534);

  @override
  void initState() {
    super.initState();

    // ==========================================================
    // AUTOMATICALLY JOIN QUIZ
    // ==========================================================

    WidgetsBinding.instance.addPostFrameCallback((_) {
      joinQuiz();
    });
  }

  // ============================================================
  // JOIN QUIZ
  // ============================================================

  Future<void> joinQuiz() async {
    if (_completingApproval || _navigationStarted) return;

    try {
      if (mounted) {
        setState(() {
          joining = true;
          waitingApproval = false;
          errorMessage = null;
        });
      }

      final code = widget.quizCode.trim().toUpperCase();
      if (code.isEmpty) throw Exception("Quiz code is empty.");

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("User is not logged in.");

      final uid = user.uid;
      final firestore = FirebaseFirestore.instance;
      final userDoc = await firestore.collection('users').doc(uid).get();
      if (!userDoc.exists) {
        throw Exception("Your registered account information was not found.");
      }

      final userData = userDoc.data() ?? <String, dynamic>{};
      var realName =
          (userData['realName'] ??
                  userData['fullName'] ??
                  userData['name'] ??
                  userData['displayName'] ??
                  user.displayName ??
                  '')
              .toString()
              .trim();
      if (realName.isEmpty) {
        realName = (user.email ?? '').split('@').first;
      }
      if (realName.isEmpty) realName = 'Unknown Player';

      var email = (userData['email'] ?? user.email ?? '').toString().trim();
      final role = (userData['role'] ?? 'Contestant').toString();

      final quizRef = firestore.collection('quiz_sessions').doc(code);
      final quizDoc = await quizRef.get();
      if (!quizDoc.exists) throw Exception("Quiz session not found.");

      final quizData = quizDoc.data() ?? <String, dynamic>{};
      final status = (quizData['status'] ?? 'waiting')
          .toString()
          .trim()
          .toLowerCase();
      if (const {'finished', 'ended', 'completed', 'closed'}.contains(status)) {
        throw Exception("This quiz has already ended.");
      }

      final quizTitle = (quizData['title'] ?? '').toString().trim().isNotEmpty
          ? quizData['title'].toString().trim()
          : 'TechNoWiz Quiz';
      final currentLevel =
          int.tryParse(quizData['currentLevel']?.toString() ?? '1') ?? 1;

      _realName = realName;
      _email = email;
      _role = role;
      _quizTitle = quizTitle;
      _currentLevel = currentLevel;

      final requestRef = quizRef.collection('join_requests').doc(uid);
      final requestDoc = await requestRef.get();
      final requestData = requestDoc.data() ?? {};
      final requestStatus = (requestData['status'] ?? '')
          .toString()
          .trim()
          .toLowerCase();

      final isElim = requestData['eliminated'] == true ||
          requestData['isEliminated'] == true ||
          requestStatus == 'eliminated' ||
          requestData['contestantDecision']?.toString().trim().toLowerCase() ==
              'eliminated';

      if (isElim) {
        if (!mounted) return;
        setState(() {
          joining = false;
        });
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

      // Only an Admin-approved request may proceed into the Waiting Room.
      if (requestDoc.exists && requestStatus == 'approved') {
        await _completeApprovedJoin(
          code,
          uid,
          realName,
          email,
          role,
          quizTitle,
          currentLevel,
        );
        return;
      }

      // Existing pending request: keep waiting instead of creating duplicates.
      if (requestDoc.exists && requestStatus == 'pending') {
        if (!mounted) return;
        setState(() {
          joining = false;
          waitingApproval = true;
        });
        return;
      }

      // Fetch team details if this contestant is registered as a team
      final teamName = (userData['teamName'] ?? '').toString().trim();
      final contestantType =
          (userData['contestantType'] ?? '').toString().trim().toLowerCase();
      final bool isTeam = contestantType == 'team' || teamName.isNotEmpty;
      final rawMembers = userData['teamMembers'] ?? userData['members'];
      final List<String> teamMembers = [];
      if (rawMembers is List) {
        for (final m in rawMembers) {
          final s = m is Map ? (m['name'] ?? '').toString() : m.toString();
          if (s.trim().isNotEmpty) teamMembers.add(s.trim());
        }
      }

      final String effectiveName =
          isTeam && teamName.isNotEmpty ? teamName : realName;

      // A new request is required after leaving or a previous rejection.
      // Do NOT create the participant document until Admin approves this request.
      await requestRef.set({
        'uid': uid,
        'name': effectiveName,
        'displayName': effectiveName,
        'realName': realName,
        'email': email,
        'role': role,
        'contestantType': isTeam ? 'team' : 'solo',
        'isTeam': isTeam,
        'teamName': isTeam ? teamName : '',
        'teamMembers': isTeam ? teamMembers : <String>[],
        'members': isTeam ? teamMembers : <String>[],
        'leaderName': realName,
        'quizCode': code,
        'quizTitle': quizTitle,
        'level': currentLevel,
        'status': 'pending',
        'ready': false,
        'readyResponded': false,
        'requestedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        joining = false;
        waitingApproval = true;
      });
    } on FirebaseException catch (e) {
      debugPrint("FIREBASE JOIN ERROR: ${e.code}");
      debugPrint("MESSAGE: ${e.message}");
      if (!mounted) return;
      setState(() {
        joining = false;
        waitingApproval = false;
        errorMessage = e.message ?? "Unable to request to join quiz.";
      });
    } catch (e) {
      debugPrint("JOIN QUIZ ERROR: $e");
      if (!mounted) return;
      setState(() {
        joining = false;
        waitingApproval = false;
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _completeApprovedJoin(
    String code,
    String uid,
    String realName,
    String email,
    String role,
    String quizTitle,
    int currentLevel,
  ) async {
    if (_completingApproval || _navigationStarted || !mounted) return;
    _completingApproval = true;

    try {
      final firestore = FirebaseFirestore.instance;
      final quizRef = firestore.collection('quiz_sessions').doc(code);
      final requestRef = quizRef.collection('join_requests').doc(uid);

      // Re-read approval immediately before granting access.
      final latestRequest = await requestRef.get();
      final latestStatus = (latestRequest.data()?['status'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (!latestRequest.exists || latestStatus != 'approved') {
        if (mounted) {
          setState(() {
            joining = false;
            waitingApproval = true;
          });
        }
        return;
      }

      final requestData = latestRequest.data() ?? {};
      final reqType = (requestData['contestantType'] ?? '').toString().trim().toLowerCase();
      final reqTeamName = (requestData['teamName'] ?? '').toString().trim();
      final bool isTeam = reqType == 'team' || reqTeamName.isNotEmpty;
      final rawMembers = requestData['teamMembers'] ?? requestData['members'];
      final List<String> teamMembers = [];
      if (rawMembers is List) {
        for (final m in rawMembers) {
          final s = m is Map ? (m['name'] ?? '').toString() : m.toString();
          if (s.trim().isNotEmpty) teamMembers.add(s.trim());
        }
      }
      final String effectiveName =
          isTeam && reqTeamName.isNotEmpty ? reqTeamName : realName;

      final participantRef = quizRef.collection('participants').doc(uid);
      await participantRef.set({
        'uid': uid,
        'name': effectiveName,
        'displayName': effectiveName,
        'realName': realName,
        'email': email,
        'role': role,
        'contestantType': isTeam ? 'team' : 'solo',
        'isTeam': isTeam,
        'teamName': isTeam ? reqTeamName : '',
        'teamMembers': isTeam ? teamMembers : <String>[],
        'members': isTeam ? teamMembers : <String>[],
        'joinedAt': FieldValue.serverTimestamp(),
        'status': 'joined',
        'quizCode': code,
        'quizTitle': quizTitle,
        'level': currentLevel,
      }, SetOptions(merge: true));

      if (!mounted || _navigationStarted) return;
      _navigationStarted = true;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => WaitingRoomScreen(
            quizCode: code,
            level: currentLevel,
            quizTitle: quizTitle,
          ),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, animation, secondaryAnimation, child) =>
              child,
        ),
      );
    } catch (e) {
      debugPrint('Unable to finish approved join: $e');
      if (mounted) {
        setState(() {
          joining = false;
          waitingApproval = false;
          errorMessage =
              'Approved, but unable to enter the quiz. Please retry.';
        });
      }
    } finally {
      _completingApproval = false;
    }
  }

  Widget _approvalStatusView() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return _errorView();
    }

    final requestStream = FirebaseFirestore.instance
        .collection('quiz_sessions')
        .doc(widget.quizCode.trim().toUpperCase())
        .collection('join_requests')
        .doc(user.uid)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: requestStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _approvalMessage(
            icon: Icons.cloud_off_rounded,
            title: 'Unable to check approval',
            message: 'Check your connection and try again.',
            showRetry: true,
          );
        }

        final data = snapshot.data?.data();
        final status = (data?['status'] ?? 'pending')
            .toString()
            .trim()
            .toLowerCase();

        if (snapshot.hasData && snapshot.data!.exists && status == 'approved') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _completeApprovedJoin(
              widget.quizCode.trim().toUpperCase(),
              user.uid,
              _realName,
              _email,
              _role,
              _quizTitle,
              _currentLevel,
            );
          });
        }

        if (status == 'rejected' || status == 'denied') {
          return _approvalMessage(
            icon: Icons.block_rounded,
            title: 'Join Request Not Approved',
            message:
                'Your request was not approved. You may try requesting again.',
            showRetry: true,
          );
        }

        return _approvalMessage(
          icon: Icons.hourglass_top_rounded,
          title: 'Waiting for Admin Approval',
          message:
              'Please wait for Admin to approve.',
          showRetry: false,
        );
      },
    );
  }

  Widget _approvalMessage({
    required IconData icon,
    required String title,
    required String message,
    required bool showRetry,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: primaryGreen.withValues(alpha: 0.10),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(
                color: Color(0xFFE9F8EF),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: primaryGreen, size: 38),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
                color: darkGreen,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54, height: 1.5),
            ),
            if (showRetry) ...[
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: retryJoin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryGreen,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('REQUEST AGAIN'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('BACK TO DASHBOARD'),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // RETRY
  // ============================================================

  void retryJoin() {
    setState(() {
      joining = true;
      waitingApproval = false;
      errorMessage = null;
    });

    joinQuiz();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return TechCircuitBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: joining
                ? _joiningView()
                : waitingApproval
                ? _approvalStatusView()
                : _errorView(),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // JOINING VIEW
  // ============================================================

  Widget _joiningView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // ICON
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            color: const Color(0xFFE9F8EF),
            borderRadius: BorderRadius.circular(25),
          ),
          child: const Icon(Icons.login_rounded, color: primaryGreen, size: 45),
        ),

        const SizedBox(height: 25),

        const SizedBox(
          width: 42,
          height: 42,
          child: CircularProgressIndicator(color: primaryGreen, strokeWidth: 4),
        ),

        const SizedBox(height: 22),

        const Text(
          "Joining Quiz...",
          style: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.bold,
            color: darkGreen,
          ),
        ),

        const SizedBox(height: 9),

        Text(
          "Quiz Code: ${widget.quizCode.toUpperCase()}",
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 15,
            fontWeight: FontWeight.w500,
            letterSpacing: 1,
          ),
        ),

        const SizedBox(height: 8),

        const Text(
          "Please wait while we connect you.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black45, fontSize: 13),
        ),
      ],
    );
  }

  // ============================================================
  // ERROR VIEW
  // ============================================================

  Widget _errorView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // ERROR ICON
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(25),
          ),
          child: const Icon(
            Icons.error_outline_rounded,
            color: Colors.red,
            size: 48,
          ),
        ),

        const SizedBox(height: 22),

        const Text(
          "Unable to Join Quiz",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.bold,
            color: darkGreen,
          ),
        ),

        const SizedBox(height: 12),

        Text(
          errorMessage ?? "Something went wrong.",
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.grey, fontSize: 14, height: 1.4),
        ),

        const SizedBox(height: 28),

        // RETRY
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton.icon(
            onPressed: retryJoin,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text(
              "TRY AGAIN",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // BACK
        SizedBox(
          width: double.infinity,
          height: 54,
          child: OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: darkGreen,
              side: const BorderSide(color: primaryGreen),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              "GO BACK",
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}
