import 'dart:async';

import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'quiz_screen.dart';
import 'quiz_instructions_screen.dart';
import 'quiz_preparation_screen.dart';
import 'quiz_countdown_screen.dart';
import 'competitor_dashboard.dart';
import 'technowiz_theme.dart';

class WaitingRoomScreen extends StatefulWidget {
  final String quizCode;

  final int level;

  final String quizTitle;

  const WaitingRoomScreen({
    super.key,

    required this.quizCode,

    this.level = 1,

    this.quizTitle = "Quiz",
  });

  @override
  State<WaitingRoomScreen> createState() => _WaitingRoomScreenState();
}

class _WaitingRoomScreenState extends State<WaitingRoomScreen> {
  // ============================================================

  // COLORS

  // ============================================================

  static const String _contestantLastPageKey = 'contestant_last_page';
  static const String _contestantQuizCodeKey = 'contestant_current_quiz_code';
  static const String _contestantQuizTitleKey = 'contestant_current_quiz_title';
  static const String _contestantQuizLevelKey = 'contestant_current_quiz_level';
  static const String _contestantJoinedQuizCodeKey =
      'contestant_joined_quiz_code';
  static const String _joinCongratulationsShownPrefix =
      'contestant_join_congratulations_shown_v2';
  static const String _cachedContestantNameKey = 'contestant_cached_real_name';
  static const String _cachedTeamNameKey = 'contestant_cached_team_name';
  static const String _cachedContestantTypeKey = 'contestant_cached_type';
  static const String _cachedTeamMembersKey = 'contestant_cached_team_members';

  static const Color primaryGreen = Color(0xFF16A34A);



  static const Color lightGreen = Color(0xFFECFDF3);

  static const Color greenGradientStart = Color(0xFF22C55E);

  static const Color greenGradientEnd = Color(0xFF15803D);

  static const Color background = Color(0xFFF2FBF5);

  static const Color textDark = Color(0xFF172033);

  // The Waiting Room is opened for an accepted participant. Show CONNECTED
  // immediately instead of flashing a JOINING indicator on return visits.
  bool _joiningQuiz = false;

  // Show the join confirmation briefly, then hide it automatically.
  final ValueNotifier<bool> _joinConfirmationVisible = ValueNotifier<bool>(
    false,
  );
  Timer? _joinConfirmationTimer;

  bool _navigatedToQuiz = false;

  // Prevent a stale 'active' event status from skipping the Waiting Room
  // after a contestant leaves and joins again. The current visit must observe
  // the synchronized countdown before it can navigate to the Quiz Screen.
  bool _hasObservedCountdownForThisVisit = false;

  // Capture the event's start marker when this Waiting Room visit begins.
  // This lets us detect a new Level 1 start even if Firestore skips a brief
  // countdown snapshot, while avoiding auto-entry into an event that was
  // already active before this visit.
  bool _initialQuizStateLoaded = false;
  String? _initialLevelStartedAtKey;

  String? _lastReadyCheckShown;

  bool _readyDialogBusy = false;

  bool _showQuizInstructions = false;

  // Keep the contestant on the preparation page until the Quiz Master starts
  // the synchronized countdown from Quiz Control.
  bool _showQuizAboutToStart = false;

  bool _isCountdownHeaderHidden = false;

  // Contestant/team information shown in the green waiting-room card.

  String _contestantName = "Contestant";

  String _teamName = "";

  List<String> _teamMembers = [];

  String _contestantType = "solo";

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _participantRemovalSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _joinRequestRemovalSubscription;
  bool _participantDocumentObserved = false;
  bool _joinRequestDocumentObserved = false;
  bool _removalDialogShown = false;

  // ============================================================

  // INIT

  // ============================================================

  @override
  void initState() {
    super.initState();

    // Use account information immediately; refine it from cached/Firestore
    // profile data without making the Waiting Room wait for network loading.
    final user = FirebaseAuth.instance.currentUser;
    final authName = user?.displayName?.trim() ?? '';
    final emailName = user?.email?.trim().isNotEmpty == true
        ? user!.email!.split('@').first
        : '';
    if (authName.isNotEmpty || emailName.isNotEmpty) {
      _contestantName = authName.isNotEmpty ? authName : emailName;
    }

    // Check the one-time local flag immediately, without waiting for Firestore
    // initialization or participant/profile requests.
    _showJoinCongratulationsOnce();
    _initializeWaitingRoom();
  }

  Future<void> _showJoinCongratulationsOnce() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final shownKey =
        '${_joinCongratulationsShownPrefix}_${user.uid}_${widget.quizCode}';
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted || (prefs.getBool(shownKey) ?? false)) return;

      // Persist first so navigating back and reopening cannot show it again.
      await prefs.setBool(shownKey, true);
      if (!mounted) return;

      _joinConfirmationTimer?.cancel();
      _joinConfirmationVisible.value = true;
      _joinConfirmationTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) _joinConfirmationVisible.value = false;
      });
    } catch (e) {
      debugPrint('Could not show one-time join congratulations: $e');
    }
  }

  Future<void> _initializeWaitingRoom() async {
    // Restore the connected state immediately when reopening the same event.
    // Firestore is still checked below to verify that the participant exists.
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedName =
          prefs.getString(_cachedContestantNameKey)?.trim() ?? '';
      final cachedTeam = prefs.getString(_cachedTeamNameKey)?.trim() ?? '';
      final cachedType =
          prefs.getString(_cachedContestantTypeKey)?.trim() ?? '';
      final cachedMembers = prefs.getStringList(_cachedTeamMembersKey) ?? [];
      if (mounted && (cachedName.isNotEmpty || cachedTeam.isNotEmpty)) {
        setState(() {
          if (cachedName.isNotEmpty) _contestantName = cachedName;
          if (cachedTeam.isNotEmpty) _teamName = cachedTeam;
          if (cachedType.isNotEmpty) _contestantType = cachedType;
          if (cachedMembers.isNotEmpty) _teamMembers = cachedMembers;
        });
      }
      final alreadyJoined =
          prefs.getString(_contestantJoinedQuizCodeKey) == widget.quizCode;
      if (mounted && alreadyJoined) {
        setState(() {
          _joiningQuiz = false;
        });
      }
    } catch (e) {
      debugPrint('Could not restore contestant connection state: $e');
    }

    await _saveWaitingRoomPage();
    if (!mounted) return;

    // Record the start marker before listening for this visit's new start.
    // Do not change the event status or any quiz data here.
    try {
      final initialQuizSnapshot = await FirebaseFirestore.instance
          .collection('quiz_sessions')
          .doc(widget.quizCode)
          .get();
      if (!mounted) return;
      final initialData = initialQuizSnapshot.data() ?? {};
      _initialLevelStartedAtKey = _levelStartedAtKey(
        initialData['levelStartedAt'],
      );
      _initialQuizStateLoaded = true;
    } catch (e) {
      debugPrint('Could not capture initial quiz start state: $e');
    }

    _joinQuizAutomatically();
  }

  String? _levelStartedAtKey(dynamic value) {
    if (value is Timestamp) {
      return value.millisecondsSinceEpoch.toString();
    }
    if (value is DateTime) {
      return value.millisecondsSinceEpoch.toString();
    }
    if (value == null) return null;
    return value.toString();
  }

  Future<void> _saveWaitingRoomPage() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(_contestantLastPageKey, 'waiting_room');
      await prefs.setString(_contestantQuizCodeKey, widget.quizCode);
      await prefs.setString(_contestantQuizTitleKey, widget.quizTitle);
      await prefs.setInt(_contestantQuizLevelKey, widget.level);
    } catch (e) {
      debugPrint('Waiting Room persistence error: $e');
    }
  }

  Future<void> _saveQuizScreenPage() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(_contestantLastPageKey, 'quiz_screen');
      await prefs.setString(_contestantQuizCodeKey, widget.quizCode);
      await prefs.setString(_contestantQuizTitleKey, widget.quizTitle);
      await prefs.setInt(_contestantQuizLevelKey, widget.level);
    } catch (e) {
      debugPrint('Quiz Screen persistence save error: $e');
    }
  }

  Future<void> _clearContestantQuizPersistence() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.remove(_contestantQuizCodeKey);
      await prefs.remove(_contestantQuizTitleKey);
      await prefs.remove(_contestantQuizLevelKey);
      await prefs.remove(_contestantJoinedQuizCodeKey);
      await prefs.setString(_contestantLastPageKey, 'dashboard');
    } catch (e) {
      debugPrint('Contestant quiz persistence clear error: $e');
    }
  }

  // ============================================================

  // AUTOMATIC JOIN

  // ============================================================

  Future<void> _joinQuizAutomatically() async {
    try {
      final User? user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        if (!mounted) return;

        setState(() {
          _joiningQuiz = false;
        });

        return;
      }

      final FirebaseFirestore firestore = FirebaseFirestore.instance;

      final participantRef = firestore
          .collection('quiz_sessions')
          .doc(widget.quizCode)
          .collection('participants')
          .doc(user.uid);
      final existingParticipant = await participantRef.get();
      final Map<String, dynamic> participantData = existingParticipant.data() ?? {};

      // Also check join_requests for this quiz session
      Map<String, dynamic> joinData = {};
      try {
        final joinDoc = await firestore
            .collection('quiz_sessions')
            .doc(widget.quizCode)
            .collection('join_requests')
            .doc(user.uid)
            .get();
        if (joinDoc.exists) {
          joinData = joinDoc.data() ?? {};
        }
      } catch (e) {
        debugPrint('Could not fetch join_requests data: $e');
      }

      // Also check users collection profile
      Map<String, dynamic> userData = {};
      try {
        final userSnapshot = await firestore.collection('users').doc(user.uid).get();
        if (userSnapshot.exists) {
          userData = userSnapshot.data() ?? {};
        }
      } catch (e) {
        debugPrint('Could not fetch users collection data: $e');
      }

      // ========================================================
      // CONTESTANT / TEAM INFORMATION RESOLUTION
      // ========================================================
      final String rawTeam = (participantData['teamName'] ??
              joinData['teamName'] ??
              userData['teamName'] ??
              '')
          .toString()
          .trim();

      final String rawType = (participantData['contestantType'] ??
              joinData['contestantType'] ??
              userData['contestantType'] ??
              '')
          .toString()
          .trim()
          .toLowerCase();

      final dynamic rawMembers = participantData['teamMembers'] ??
          participantData['members'] ??
          joinData['teamMembers'] ??
          joinData['members'] ??
          userData['teamMembers'] ??
          userData['members'];

      final List<String> teamMembers = [];
      if (rawMembers is List) {
        for (final dynamic member in rawMembers) {
          if (member is String) {
            final String name = member.trim();
            if (name.isNotEmpty && !teamMembers.contains(name)) {
              teamMembers.add(name);
            }
          } else if (member is Map) {
            final dynamic nameValue =
                member['name'] ?? member['displayName'] ?? member['fullName'];
            if (nameValue != null) {
              final String name = nameValue.toString().trim();
              if (name.isNotEmpty && !teamMembers.contains(name)) {
                teamMembers.add(name);
              }
            }
          }
        }
      }

      String realName = "";
      final List<String> possibleNameFields = [
        'realName',
        'fullName',
        'name',
        'displayName',
      ];

      for (final String field in possibleNameFields) {
        final dynamic value = participantData[field] ?? joinData[field] ?? userData[field];
        if (value != null) {
          final String text = value.toString().trim();
          if (text.isNotEmpty) {
            realName = text;
            break;
          }
        }
      }

      if (realName.isEmpty) {
        final String authDisplayName = user.displayName?.trim() ?? "";
        if (authDisplayName.isNotEmpty) {
          realName = authDisplayName;
        }
      }

      if (realName.isEmpty) {
        final String email = user.email?.trim() ?? "";
        if (email.isNotEmpty) {
          realName = email.split('@').first;
        }
      }

      if (realName.isEmpty) {
        realName = "Contestant";
      }

      final bool isTeam = rawType == 'team' ||
          participantData['isTeam'] == true ||
          joinData['isTeam'] == true ||
          userData['isTeam'] == true ||
          rawTeam.isNotEmpty ||
          teamMembers.isNotEmpty;

      final String effectiveType = isTeam ? 'team' : 'solo';
      final String teamName = rawTeam.isNotEmpty ? rawTeam : (isTeam ? 'Team' : '');
      final String effectiveName = isTeam && teamName.isNotEmpty ? teamName : realName;

      if (mounted) {
        setState(() {
          _joiningQuiz = false;
          _contestantName = realName;
          _teamName = teamName;
          _teamMembers = teamMembers;
          _contestantType = effectiveType;
        });
      }

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_contestantJoinedQuizCodeKey, widget.quizCode);
        await prefs.setString(_cachedContestantNameKey, realName);
        await prefs.setString(_cachedTeamNameKey, teamName);
        await prefs.setString(_cachedContestantTypeKey, effectiveType);
        await prefs.setStringList(_cachedTeamMembersKey, teamMembers);
      } catch (e) {
        debugPrint('Could not save contestant connection state: $e');
      }

      // Sync participant document in Firestore
      final Map<String, dynamic> updateData = {
        'uid': user.uid,
        'name': effectiveName,
        'displayName': effectiveName,
        'realName': realName,
        'contestantType': effectiveType,
        'isTeam': isTeam,
        'teamName': isTeam ? teamName : '',
        'teamMembers': isTeam ? teamMembers : <String>[],
        'members': isTeam ? teamMembers : <String>[],
        'email': user.email ?? '',
        'level': widget.level,
        'status': 'joined',
      };

      if (!existingParticipant.exists) {
        updateData['joinedAt'] = FieldValue.serverTimestamp();
      }

      await participantRef.set(updateData, SetOptions(merge: true));

      _watchForAdminRemoval(user.uid);
    } catch (e) {
      debugPrint("Error joining quiz: $e");

      if (!mounted) return;

      setState(() {
        _joiningQuiz = false;
      });
    }
  }

  // ============================================================

  // WATCH FOR ADMIN REMOVAL

  // ============================================================

  void _updateTeamInfoFromSnapshot(Map<String, dynamic> data) {
    final rawTeam = (data['teamName'] ?? '').toString().trim();
    final rawType = (data['contestantType'] ?? '').toString().trim().toLowerCase();
    final rawMembers = data['teamMembers'] ?? data['members'];
    final List<String> members = [];
    if (rawMembers is List) {
      for (final m in rawMembers) {
        final s = m is Map
            ? (m['name'] ?? m['displayName'] ?? m['fullName'] ?? '').toString().trim()
            : m.toString().trim();
        if (s.isNotEmpty && !members.contains(s)) {
          members.add(s);
        }
      }
    }
    final bool isTeam = rawType == 'team' ||
        data['isTeam'] == true ||
        rawTeam.isNotEmpty ||
        members.isNotEmpty;

    final String realName = (data['realName'] ?? data['fullName'] ?? data['name'] ?? '').toString().trim();

    if (!mounted) return;
    setState(() {
      if (realName.isNotEmpty) _contestantName = realName;
      if (isTeam) {
        _contestantType = 'team';
        if (rawTeam.isNotEmpty) _teamName = rawTeam;
        if (members.isNotEmpty) _teamMembers = members;
      }
    });
  }

  void _watchForAdminRemoval(String uid) {
    if (_removalDialogShown) return;

    final eventRef = FirebaseFirestore.instance
        .collection('quiz_sessions')
        .doc(widget.quizCode);

    final participantRef = eventRef.collection('participants').doc(uid);
    final joinRequestRef = eventRef.collection('join_requests').doc(uid);

    _participantRemovalSubscription?.cancel();
    _joinRequestRemovalSubscription?.cancel();

    _participantRemovalSubscription = participantRef.snapshots().listen(
      (snapshot) {
        if (snapshot.exists) {
          _participantDocumentObserved = true;
          final data = snapshot.data();
          if (data != null) {
            _updateTeamInfoFromSnapshot(data);
          }
        } else if (_participantDocumentObserved) {
          _handleAdminRemoval();
        }
      },
      onError: (Object error) {
        debugPrint('Participant removal listener error: $error');
      },
    );

    _joinRequestRemovalSubscription = joinRequestRef.snapshots().listen(
      (snapshot) {
        if (snapshot.exists) {
          _joinRequestDocumentObserved = true;
          final data = snapshot.data();
          if (data != null) {
            _updateTeamInfoFromSnapshot(data);
          }
        } else if (_joinRequestDocumentObserved) {
          _handleAdminRemoval();
        }
      },
      onError: (Object error) {
        debugPrint('Join request removal listener error: $error');
      },
    );
  }

  Future<void> _handleAdminRemoval() async {
    if (!mounted || _removalDialogShown) return;
    _removalDialogShown = true;

    await _participantRemovalSubscription?.cancel();
    await _joinRequestRemovalSubscription?.cancel();

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.person_remove_alt_1_rounded, color: Colors.red),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                "You've Been Removed from the Quiz",
                style: TextStyle(color: textDark, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Text(
          "The Admin has removed you from this quiz. You will be returned to the Contestant Dashboard.",
          style: TextStyle(color: Colors.black54, height: 1.5),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              "OK",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (!mounted) return;

    await _clearContestantQuizPersistence();
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const CompetitorDashboard()),
      (route) => false,
    );
  }

  // ============================================================

  // LEAVE QUIZ

  // ============================================================

  Future<void> _leaveQuiz() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    final shouldLeave = await showDialog<bool>(
      context: context,

      barrierDismissible: false,

      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),

          title: const Row(
            children: [
              Icon(Icons.logout_rounded, color: Colors.red),

              SizedBox(width: 10),

              Expanded(
                child: Text(
                  "Leave Quiz?",

                  style: TextStyle(
                    color: textDark,

                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          content: const Text(
            "Are you really sure you want to leave the quiz?\n\n"
            "You will be removed from the participant list. If you join again, "
            "you will need to wait for Admin approval again.",

            style: TextStyle(color: Colors.black54, height: 1.5),
          ),

          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),

              child: const Text(
                "CANCEL",

                style: TextStyle(
                  color: Colors.grey,

                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),

              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,

                foregroundColor: Colors.white,

                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),

              child: const Text(
                "LEAVE QUIZ",

                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );

    if (shouldLeave != true || !mounted) return;

    // Prevent our own Leave Quiz cleanup from being mistaken for Admin removal.
    _removalDialogShown = true;
    await _participantRemovalSubscription?.cancel();
    await _joinRequestRemovalSubscription?.cancel();

    try {
      final firestore = FirebaseFirestore.instance;

      final batch = firestore.batch();

      // Remove contestant from the Admin participant list.

      final participantRef = firestore
          .collection('quiz_sessions')
          .doc(widget.quizCode)
          .collection('participants')
          .doc(user.uid);

      // Remove the approved join request so joining again requires

      // a fresh Admin approval.

      final requestRef = firestore
          .collection('quiz_sessions')
          .doc(widget.quizCode)
          .collection('join_requests')
          .doc(user.uid);

      // Remove the current score entry, if one exists.

      final scoreRef = firestore
          .collection('quiz_sessions')
          .doc(widget.quizCode)
          .collection('scores')
          .doc(user.uid);

      batch.delete(participantRef);

      batch.delete(requestRef);

      batch.delete(scoreRef);

      await batch.commit();

      if (!mounted) return;

      await _clearContestantQuizPersistence();

      if (!mounted) return;

      showTopSnackBar(context, 
        const SnackBar(
          content: Text("You have left the quiz."),
          backgroundColor: primaryGreen,
        ),
      );

      // Return safely to the Contestant Dashboard even when this screen
      // is the root route and there is no previous route to pop.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const CompetitorDashboard()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;

      showTopSnackBar(context, 
        SnackBar(
          content: Text("Failed to leave quiz: $e"),

          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ============================================================

  // READY CHECK

  // ============================================================

  Future<void> _showReadyCheckDialog(String checkId) async {
    if (!mounted || _readyDialogBusy) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    _readyDialogBusy = true;

    _lastReadyCheckShown = checkId;

    final requestRef = FirebaseFirestore.instance
        .collection('quiz_sessions')
        .doc(widget.quizCode)
        .collection('join_requests')
        .doc(user.uid);

    Timer? countdownTimer;
    int secondsRemaining = 15;
    bool autoMarkedReady = false;

    // This dialog checks event-wide contestant readiness, not a specific level.
    const String readinessTitle = 'ARE YOU READY TO TAKE THIS QUIZ?';
    const String readinessMessage =
        'Please confirm that you are ready to participate in this quiz event.';
    // Show the dialog immediately when the Firestore listener detects the
    // readiness check. Avoid an extra network read before opening the dialog.
    // The master and contestant use the same 15-second readiness window.
    try {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              // Count down using the shared deadline-derived remaining time.
              countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (
                timer,
              ) {
                if (!dialogContext.mounted) {
                  timer.cancel();
                  return;
                }

                if (secondsRemaining <= 1) {
                  timer.cancel();
                  countdownTimer = null;
                  autoMarkedReady = true;
                  Navigator.of(dialogContext).pop(true);
                  return;
                }

                setDialogState(() {
                  secondsRemaining--;
                });
              });

              return AlertDialog(
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
                titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 4),
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                title: Text(
                  readinessTitle,
                  textAlign: TextAlign.center,
                  softWrap: true,
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 21,
                    height: 1.18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      readinessMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Auto READY in ${secondsRemaining}s',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: const TextStyle(
                        color: primaryGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                actionsAlignment: MainAxisAlignment.center,
                actions: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        countdownTimer?.cancel();
                        countdownTimer = null;
                        Navigator.pop(dialogContext, true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        "I'M READY",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      );

      countdownTimer?.cancel();
      countdownTimer = null;

      if (!mounted) return;

      // After confirming readiness, stay on the preparation page. The
      // contestant must not see a countdown until the Quiz Master presses
      // START in Quiz Control and Firestore status changes to 'countdown'.
      if (result == true) {
        // After the contestant confirms readiness, show the level instructions
        // in the Waiting Room. Keep this screen visible until the Quiz Master
        // starts the synchronized countdown.
        setState(() {
          _showQuizInstructions = true;
          _showQuizAboutToStart = false;
        });
      } else {
        setState(() {
          _showQuizInstructions = false;
          _showQuizAboutToStart = false;
        });
      }

      // Persist readiness in the background flow after the immediate UI update.
      // Ensure this response belongs to the current readiness round.
      final quizSnapshot = await FirebaseFirestore.instance
          .collection('quiz_sessions')
          .doc(widget.quizCode)
          .get();
      final currentCheckId =
          quizSnapshot.data()?['readyCheckId']?.toString().trim() ?? '';
      if (!quizSnapshot.exists || currentCheckId != checkId) return;

      await requestRef.set({
        'ready': result == true,
        'readyResponded': true,
        'readyAt': result == true ? FieldValue.serverTimestamp() : null,
        'readyCheckId': checkId,
        'readyAutomatically': result == true && autoMarkedReady,
      }, SetOptions(merge: true));

      if (!mounted) return;
    } catch (e) {
      debugPrint('Ready check error: $e');
    } finally {
      countdownTimer?.cancel();
      _readyDialogBusy = false;
    }
  }

  int _readInstructionInt(dynamic value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  Widget _instructionsScreen(Map<String, dynamic> quizData) {
    final int instructionLevel = _readInstructionInt(
      quizData['currentLevel'] ?? quizData['level'] ?? widget.level,
      fallback: widget.level,
    ).clamp(1, 99).toInt();

    return QuizInstructionsScreen(
      quizData: quizData,
      level: instructionLevel,
      quizCode: widget.quizCode,
    );
  }

  Widget _countdownScreen(int countdown, {int questionNumber = 1}) {
    return QuizCountdownScreen(
      countdown: countdown,
      questionNumber: questionNumber,
    );
  }

  String _firstNonEmpty(
    Map<String, dynamic> data,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final key in keys) {
      final value = data[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty && text != 'null') return text;
    }
    return fallback;
  }

  Widget _eventDetailsCard(Map<String, dynamic> quizData, String status) {
    final generalGuidelines = _firstNonEmpty(
      quizData,
      ['participationGuidelines', 'guidelines', 'rules', 'instructions'],
      fallback:
          'Stay on this page while waiting.\\nFollow the Quiz Master’s directions.\\nRead the instructions before each level.\\nSubmit your answers before the timer ends.',
    );
    final guidelineItems = generalGuidelines
        .split(RegExp(r'\\n|[.!?](?:\\s+|$)'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD5F0DE)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
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
                child: const Icon(Icons.rule_rounded, color: primaryGreen),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'PARTICIPANTS GUIDELINES',
                  style: TextStyle(
                    color: textDark,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: .4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...guidelineItems.map(
            (guideline) => Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: primaryGreen,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      guideline,
                      style: const TextStyle(
                        color: Color(0xFF4B5563),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================

  // STATUS TEXT

  // ============================================================

  String getStatusText(String status, {String? eventStatus}) {
    final normalizedEventStatus = (eventStatus ?? '').trim().toLowerCase();

    // Prefer the event's explicit status when it indicates preparation.
    if (normalizedEventStatus == 'countdown' ||
        normalizedEventStatus == 'preparing' ||
        normalizedEventStatus == 'preparing_to_begin') {
      return "Preparing to Begin";
    }

    switch (status) {
      case 'waiting':
        return "Preparing to Begin";

      case 'countdown':
        return "Preparing to Begin";

      case 'active':
        return "Event in Progress";

      case 'ended':
        return "Event Ended";

      case 'finished':
        return "Event Completed";

      default:
        return status.toUpperCase();
    }
  }

  // ============================================================

  // STATUS COLOR

  // ============================================================

  Color getStatusColor(String status) {
    switch (status) {
      case 'active':
      case 'countdown':
        return primaryGreen;

      case 'ended':
        return Colors.red;

      case 'finished':
        return primaryGreen;

      default:
        return primaryGreen;
    }
  }

  // ============================================================

  // BUILD

  // ============================================================

  @override
  void dispose() {
    _joinConfirmationTimer?.cancel();
    _participantRemovalSubscription?.cancel();
    _joinRequestRemovalSubscription?.cancel();
    _joinConfirmationVisible.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,

      // Waiting Room header is rendered inside the main content column.

      // ==========================================================

      // QUIZ SESSION

      // ==========================================================
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('quiz_sessions')
            .doc(widget.quizCode)
            .snapshots(),

        builder: (context, quizSnapshot) {
          // Render the complete Waiting Room immediately with safe defaults
          // while Firestore is fetching the quiz event. The live snapshot will
          // replace these defaults as soon as it arrives.
          if (quizSnapshot.hasError) {
            return _errorState("Unable to load quiz session.");
          }

          final Map<String, dynamic> quizData =
              quizSnapshot.data?.data() ?? <String, dynamic>{};

          // Only show the not-found state after the initial stream load has
          // completed; during loading, keep the full Waiting Room visible.
          if (quizSnapshot.connectionState != ConnectionState.waiting &&
              (!quizSnapshot.hasData || !quizSnapshot.data!.exists)) {
            return _errorState("Quiz session not found.");
          }

          final String status = (quizData['status'] ?? 'waiting').toString();
          final String eventStatus = (quizData['eventStatus'] ?? '')
              .toString()
              .trim()
              .toLowerCase();

          // ======================================================

          // READY CHECK

          // ======================================================

          // Show the contestant's Ready Check ONLY when the Quiz Master
          // explicitly activates a new ready check in Firestore.
          final bool readyCheckActive = quizData['readyCheckActive'] == true;

          // Use the explicit check ID first. This prevents an old
          // readyCheckStartedAt value from being mistaken for a new check.
          final String readyCheckId = (quizData['readyCheckId'] ?? '')
              .toString()
              .trim();

          // Show the dialog whenever the Quiz Master has an active,
          // identified readiness round. This also handles contestants who
          // enter/refresh the Waiting Room after the Quiz Master activates it.
          // _lastReadyCheckShown and _readyDialogBusy prevent duplicate dialogs
          // during repeated Firestore snapshots on the same screen.
          final bool hasValidReadyCheck =
              readyCheckId.isNotEmpty && readyCheckActive;

          // Do not replace the contestant's Waiting Room with the green
          // "QUIZ IS ABOUT TO START" page during readiness. The contestant
          // must first respond to the event Ready Check. The synchronized
          // countdown/question UI takes over only when Quiz Master starts
          // Level 1 and Firestore status changes to 'countdown'.

          // START QUIZ EVENT must show the contestant's "Are You Ready?"
          // dialog. Only a Quiz Master level-start check uses the green
          // "Quiz is about to start" preparation page.
          // Show the dialog whenever Firestore has an active, identified
          // readiness round. Do not let a stale readyCheckType='level' value
          // suppress the initial START QUIZ EVENT confirmation on contestants.
          if (hasValidReadyCheck &&
              _lastReadyCheckShown != readyCheckId &&
              !_readyDialogBusy) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted &&
                  _lastReadyCheckShown != readyCheckId &&
                  !_readyDialogBusy) {
                _showReadyCheckDialog(readyCheckId);
              }
            });
          }

          // ======================================================

          // ======================================================

          // LEVEL 1 INSTRUCTIONS / WAITING

          // ======================================================

          // Keep the initial instructions visible during the preparation/waiting
          // states. Hide them only when the synchronized countdown begins or
          // the quiz is already active/over.

          // Show preparation only when:
          // 1. The contestant has confirmed readiness (_showQuizInstructions || _showQuizAboutToStart)
          // 2. AND the Quiz Master has clicked START LEVEL 1 (eventStatus == 'preparing_to_begin' && readyCheckType == 'level')
          // When a contestant first joins and is approved by Admin, they stay in the Waiting Room (Step 2).
          final bool isLevelPreparationCommand =
              eventStatus == 'preparing_to_begin' &&
              (quizData['readyCheckType']?.toString().trim().toLowerCase() ==
                  'level') &&
              status == 'waiting';

          if ((_showQuizAboutToStart ||
                  (_showQuizInstructions && isLevelPreparationCommand)) &&
              status != 'countdown' &&
              status != 'active' &&
              status != 'ended' &&
              status != 'finished') {
            _showQuizInstructions = false;
            _showQuizAboutToStart = true;
            // The preparation banner must identify the active LEVEL, not the
            // global question number. After Level 1 ends, currentQuestion may
            // still be 2 or 3; use the event's currentLevel for this label.
            final dynamic rawCurrentLevel =
                quizData['currentLevel'] ??
                quizData['level'] ??
                quizData['activeLevel'] ??
                widget.level;
            final String currentLevelText = rawCurrentLevel.toString().trim();
            final RegExpMatch? levelMatch = RegExp(
              r'(\d+)',
            ).firstMatch(currentLevelText);
            final int preparationLevel = levelMatch == null
                ? widget.level
                : (int.tryParse(levelMatch.group(1)!) ?? widget.level);

            return QuizPreparationScreen(
              currentQuestion: _readInstructionInt(
                quizData['currentQuestion'] ?? 0,
                fallback: 0,
              ),
              currentLevel: preparationLevel,
            );
          }

          if (_showQuizInstructions &&
              status != 'countdown' &&
              status != 'active' &&
              status != 'ended' &&
              status != 'finished') {
            return _instructionsScreen(quizData);
          }

          // SYNCHRONIZED COUNTDOWN

          // ======================================================

          if (status != 'countdown' && _isCountdownHeaderHidden) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _isCountdownHeaderHidden) {
                setState(() {
                  _isCountdownHeaderHidden = false;
                });
              }
            });
          }

          final int questionNumber =
              ((int.tryParse((quizData['currentQuestion'] ?? 0).toString()) ??
                          0) +
                      1)
                  .clamp(1, 999);

          if (status == 'countdown') {
            // Only navigate to QuizScreen if this visit has seen the current
            // countdown. This avoids jumping straight into an already-active
            // event when the contestant rejoins after leaving.
            _hasObservedCountdownForThisVisit = true;
            if (!_isCountdownHeaderHidden) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_isCountdownHeaderHidden) {
                  setState(() {
                    _isCountdownHeaderHidden = true;
                  });
                }
              });
            }

            // Countdown has started, so clear the instructions state.

            if (_showQuizInstructions || _showQuizAboutToStart) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;

                setState(() {
                  _showQuizInstructions = false;
                  _showQuizAboutToStart = false;
                });
              });
            }

            final countdown =
                int.tryParse((quizData['countdown'] ?? 0).toString()) ?? 0;
            // Open QuizScreen as soon as the synchronized countdown starts.
            // QuizScreen preloads the questions during the countdown, so the
            // contestant can go straight to Question 1 when GO ends instead
            // of first rendering the Waiting Room or a question-loading page.
            if (!_navigatedToQuiz) {
              _navigatedToQuiz = true;
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                if (!mounted) return;
                await _saveQuizScreenPage();
                if (!mounted || !context.mounted) return;
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => QuizScreen(quizCode: widget.quizCode),
                  ),
                );
              });
            }

            return _countdownScreen(countdown, questionNumber: questionNumber);
          }

          // After this visit has seen the initial synchronized countdown,
          // never fall back to the Waiting Room while Firestore is handing
          // off from countdown to the active quiz. Some session fields may
          // arrive in separate snapshots; keep GO visible until navigation
          // to QuizScreen can happen.
          if (_hasObservedCountdownForThisVisit && status != 'active') {
            return _countdownScreen(0, questionNumber: questionNumber);
          }

          // ======================================================

          // QUIZ MASTER STARTED

          // ======================================================

          final bool newLevelStartDetected =
              _initialQuizStateLoaded &&
              _levelStartedAtKey(quizData['levelStartedAt']) !=
                  _initialLevelStartedAtKey;

          if (status == 'active' &&
              (_hasObservedCountdownForThisVisit || newLevelStartDetected) &&
              !_navigatedToQuiz) {
            _navigatedToQuiz = true;

            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!mounted) return;

              await _saveQuizScreenPage();

              if (!mounted || !context.mounted) return;

              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => QuizScreen(quizCode: widget.quizCode),
                ),
              );
            });

            // Keep the GO screen in place for this build too, rather than
            // briefly rendering the Waiting Room before the route replacement.
            return _countdownScreen(0, questionNumber: questionNumber);
          }

          // ======================================================

          // MAIN CONTENT

          // ======================================================

          return Column(
            children: [
              // WAITING ROOM TOP BAR
              // Keep the green header and back arrow visible above the
              // Waiting Room content, matching the previous design.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(8, 10, 16, 10),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [greenGradientStart, greenGradientEnd],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x1A000000),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: () {
                          if (Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          } else {
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute<void>(
                                builder: (_) => const CompetitorDashboard(),
                              ),
                              (route) => false,
                            );
                          }
                        },
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                          size: 25,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Expanded(
                        child: Text(
                          'WAITING ROOM',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 25),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      // ==================================================

                      const Center(child: TechArenaBadge(label: 'TECHNOWIZ • CONTESTANT LOBBY', icon: Icons.sensors_rounded)),
                      const SizedBox(height: 12),

                      // ==================================================
                      Container(
                        width: double.infinity,

                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 15),

                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [greenGradientStart, greenGradientEnd],

                            begin: Alignment.topLeft,

                            end: Alignment.bottomRight,
                          ),

                          borderRadius: BorderRadius.circular(24),

                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x4016A34A),

                              blurRadius: 15,

                              offset: Offset(0, 7),
                            ),
                          ],
                        ),

                        child: Column(
                          children: [
                            if (status == 'waiting')
                              ValueListenableBuilder<bool>(
                                valueListenable: _joinConfirmationVisible,
                                builder: (context, visible, child) {
                                  if (!visible) return const SizedBox.shrink();
                                  return Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(bottom: 18),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.30),
                                      ),
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(
                                          Icons.notifications_active_rounded,
                                          color: Colors.white,
                                          size: 22,
                                        ),
                                        SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                "Congratulations, You’re in!",
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              SizedBox(height: 2),
                                              Text(
                                                "Please wait for the Quiz Master to start the quiz.",
                                                style: TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 11,
                                                  height: 1.3,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            Container(
                              width: 60,

                              height: 60,

                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),

                                shape: BoxShape.circle,
                              ),

                              child: Icon(
                                (_contestantType == 'team' || _teamName.isNotEmpty || _teamMembers.isNotEmpty)
                                    ? Icons.groups_rounded
                                    : Icons.person_rounded,

                                color: Colors.white,

                                size: 32,
                              ),
                            ),

                            const SizedBox(height: 10),

                            Text(
                              (_contestantType == 'team' || _teamName.isNotEmpty) && _teamName.isNotEmpty
                                  ? _teamName
                                  : _contestantName,

                              textAlign: TextAlign.center,

                              maxLines: 2,

                              overflow: TextOverflow.ellipsis,

                              style: const TextStyle(
                                color: Colors.white,

                                fontSize: 21,

                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            if ((_contestantType == 'team' || _teamName.isNotEmpty || _teamMembers.isNotEmpty) &&
                                _teamMembers.isNotEmpty) ...[
                              const SizedBox(height: 14),

                              Container(
                                width: double.infinity,

                                padding: const EdgeInsets.fromLTRB(
                                  15,

                                  12,

                                  15,

                                  12,
                                ),

                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.14),

                                  borderRadius: BorderRadius.circular(16),
                                ),

                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,

                                  children: [
                                    const Text(
                                      "TEAM MEMBERS",

                                      style: TextStyle(
                                        color: Colors.white70,

                                        fontSize: 10,

                                        fontWeight: FontWeight.bold,

                                        letterSpacing: 1.4,
                                      ),
                                    ),

                                    const SizedBox(height: 7),

                                    ..._teamMembers.map(
                                      (member) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 4,
                                        ),

                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,

                                          children: [
                                            const Text(
                                              "• ",

                                              style: TextStyle(
                                                color: Colors.white,

                                                fontSize: 14,

                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),

                                            Expanded(
                                              child: Text(
                                                member,

                                                style: const TextStyle(
                                                  color: Colors.white,

                                                  fontSize: 13,

                                                  fontWeight: FontWeight.w500,
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
                            ],

                            // Level badge removed from the contestant header.
                          ],
                        ),
                      ),

                      // Add breathing room between the contestant profile
                      // card and the Participants Guidelines card.
                      const SizedBox(height: 12),

                      // Event details remain visible while the participant waits.
                      _eventDetailsCard(quizData, status),

                      const SizedBox(height: 2),

                      // ==================================================

                      // STATUS CARD

                      // ==================================================
                      Container(
                        width: double.infinity,

                        padding: const EdgeInsets.all(20),

                        decoration: BoxDecoration(
                          color: Colors.white,

                          borderRadius: BorderRadius.circular(20),

                          border: Border.all(
                            color: getStatusColor(status).withValues(alpha: 0.25),
                          ),

                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x12000000),

                              blurRadius: 8,

                              offset: Offset(0, 3),
                            ),
                          ],
                        ),

                        child: Row(
                          children: [
                            Container(
                              width: 58,

                              height: 58,

                              decoration: BoxDecoration(
                                color: getStatusColor(status).withValues(alpha: 0.10),

                                borderRadius: BorderRadius.circular(17),
                              ),

                              child: Icon(
                                status == 'active'
                                    ? Icons.play_arrow_rounded
                                    : status == 'countdown'
                                    ? Icons.hourglass_top_rounded
                                    : status == 'ended'
                                    ? Icons.flag_rounded
                                    : status == 'finished'
                                    ? Icons.emoji_events_rounded
                                    : Icons.hourglass_top_rounded,

                                color: getStatusColor(status),

                                size: 30,
                              ),
                            ),

                            const SizedBox(width: 15),

                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,

                                children: [
                                  Text(
                                    getStatusText(
                                      status,
                                      eventStatus: quizData['eventStatus']
                                          ?.toString(),
                                    ),

                                    style: TextStyle(
                                      fontSize: 18,

                                      fontWeight: FontWeight.bold,

                                      color: getStatusColor(status),
                                    ),
                                  ),

                                  const SizedBox(height: 5),

                                  Text(
                                    status == 'active'
                                        ? "The Quiz Event is now in progress."
                                        : status == 'countdown'
                                        ? "Please get ready. The Quiz Event is about to begin."
                                        : status == 'ended'
                                        ? "This Quiz Event has already ended."
                                        : status == 'finished'
                                        ? "This Quiz Event has been completed."
                                        : "The Quiz Master is checking if participants are ready. Please wait.",

                                    style: const TextStyle(
                                      color: Colors.grey,

                                      fontSize: 13,

                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ==================================================

                      // LEAVE QUIZ BUTTON

                      // ==================================================
                      SizedBox(
                        width: double.infinity,

                        height: 50,

                        child: OutlinedButton.icon(
                          onPressed: _joiningQuiz ? null : _leaveQuiz,

                          icon: const Icon(Icons.logout_rounded, size: 20),

                          label: const Text(
                            "LEAVE QUIZ",

                            style: TextStyle(
                              fontWeight: FontWeight.bold,

                              letterSpacing: 0.5,
                            ),
                          ),

                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,

                            side: const BorderSide(
                              color: Colors.red,

                              width: 1.4,
                            ),

                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      const Center(
                        child: Text(
                          "You can join again, but Admin approval will be required.",

                          textAlign: TextAlign.center,

                          style: TextStyle(color: Colors.black45, fontSize: 11),
                        ),
                      ),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ============================================================

  // ERROR STATE

  // ============================================================

  Widget _errorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            Container(
              width: 85,

              height: 85,

              decoration: BoxDecoration(
                color: Colors.red.shade50,

                borderRadius: BorderRadius.circular(24),
              ),

              child: const Icon(
                Icons.error_outline,

                size: 45,

                color: Colors.red,
              ),
            ),

            const SizedBox(height: 18),

            const Text(
              "Something went wrong",

              textAlign: TextAlign.center,

              style: TextStyle(
                fontSize: 20,

                fontWeight: FontWeight.bold,

                color: textDark,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              message,

              textAlign: TextAlign.center,

              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
