import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'admin/admin_dashboard.dart';
import 'quizmaster/quizmaster_dashboard.dart';
import 'competitor/competitor_dashboard.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController nameController = TextEditingController();
  final FocusNode nameFocusNode = FocusNode();

  final TextEditingController emailController = TextEditingController();
  final FocusNode emailFocusNode = FocusNode();

  final TextEditingController passwordController = TextEditingController();
  final FocusNode passwordFocusNode = FocusNode();

  final TextEditingController confirmPasswordController =
      TextEditingController();
  final FocusNode confirmPasswordFocusNode = FocusNode();

  static const FlutterSecureStorage secureStorage = FlutterSecureStorage();
  static const String savedAccountsKey = 'saved_login_accounts';

  String selectedRole = "Contestant";
  String contestantType = "Solo";

  final TextEditingController teamNameController = TextEditingController();
  final FocusNode teamNameFocusNode = FocusNode();

  final TextEditingController teamSizeController =
      TextEditingController(text: "2");
  final FocusNode teamSizeFocusNode = FocusNode();
  final List<TextEditingController> memberNameControllers = [];
  final List<FocusNode> memberFocusNodes = [];

  bool isLoading = false;
  bool obscurePassword = true;
  bool obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    nameFocusNode.addListener(() => setState(() {}));
    emailFocusNode.addListener(() => setState(() {}));
    passwordFocusNode.addListener(() => setState(() {}));
    confirmPasswordFocusNode.addListener(() => setState(() {}));
    teamNameFocusNode.addListener(() => setState(() {}));
    teamSizeFocusNode.addListener(() => setState(() {}));
    _updateMemberControllers(2);
  }

  void _updateMemberControllers(int size) {
    if (size < 1) size = 1;
    if (size > 50) size = 50;
    while (memberNameControllers.length < size) {
      final ctrl = TextEditingController();
      final node = FocusNode();
      node.addListener(() => setState(() {}));
      memberNameControllers.add(ctrl);
      memberFocusNodes.add(node);
    }
    while (memberNameControllers.length > size) {
      memberFocusNodes.removeLast().dispose();
      memberNameControllers.removeLast().dispose();
    }
  }

  Future<void> saveRegisteredAccountLocally({
    required String email,
    required String password,
  }) async {
    try {
      final String normalizedEmail = email.trim().toLowerCase();
      final String savedJson =
          await secureStorage.read(key: savedAccountsKey) ?? '';
      Map<String, dynamic> savedAccounts = {};
      if (savedJson.isNotEmpty) {
        try {
          final dynamic decoded = jsonDecode(savedJson);
          if (decoded is Map) {
            savedAccounts = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {
          savedAccounts = {};
        }
      }
      savedAccounts[normalizedEmail] = password;
      await secureStorage.write(
        key: savedAccountsKey,
        value: jsonEncode(savedAccounts),
      );
      await secureStorage.write(
        key: 'saved_login_email',
        value: normalizedEmail,
      );
      await secureStorage.write(
        key: 'saved_login_password',
        value: password,
      );
    } catch (e) {
      debugPrint('Could not save registered account locally: $e');
    }
  }

  Future<void> registerUser() async {
    final name = nameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text;
    final confirmPassword = confirmPasswordController.text;

    if (name.isEmpty || email.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please complete all required fields"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Passwords do not match."),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Password must be at least 6 characters."),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (selectedRole == "Contestant" && contestantType == "Team") {
      final teamName = teamNameController.text.trim();
      final teamSize = int.tryParse(teamSizeController.text.trim());

      if (teamName.isEmpty || teamSize == null || teamSize < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Please enter a team name and at least 2 members."),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      if (memberNameControllers.length != teamSize) {
        _updateMemberControllers(teamSize);
      }

      if (memberNameControllers.length != teamSize ||
          memberNameControllers.any((c) => c.text.trim().isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Please complete all team member names."),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    }

    setState(() {
      isLoading = true;
    });

    try {
      final UserCredential userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final User? registeredUser = userCredential.user;
      if (registeredUser == null) {
        throw Exception("Unable to get registered user details.");
      }

      final String uid = registeredUser.uid;
      final String role = selectedRole;

      final Map<String, dynamic> userData = {
        "uid": uid,
        "name": name,
        "fullName": name,
        "displayName": name,
        "email": email,
        "role": role,
        "createdAt": FieldValue.serverTimestamp(),
      };

      if (role == "Contestant") {
        if (contestantType == "Team") {
          final String teamName = teamNameController.text.trim();
          final List<String> teamMembers = memberNameControllers
              .map((c) => c.text.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          final int teamSize = teamMembers.isNotEmpty
              ? teamMembers.length
              : (int.tryParse(teamSizeController.text.trim()) ?? 1);

          userData["contestantType"] = "team";
          userData["isTeam"] = true;
          userData["teamName"] = teamName;
          userData["teamSize"] = teamSize;
          userData["teamMembers"] = teamMembers;
          userData["members"] = teamMembers;
          userData["teamLeader"] = name;
          userData["leaderName"] = name;
          userData["name"] = teamName;
          userData["displayName"] = teamName;
          userData["fullName"] = teamName;

          await registeredUser.updateDisplayName(teamName);
        } else {
          userData["contestantType"] = "solo";
          userData["isTeam"] = false;
          userData["teamName"] = "";
          userData["teamMembers"] = <String>[];
          userData["members"] = <String>[];
          userData["teamSize"] = 1;
          userData["name"] = name;
          userData["displayName"] = name;
          userData["fullName"] = name;

          await registeredUser.updateDisplayName(name);
        }
      } else {
        await registeredUser.updateDisplayName(name);
      }

      await FirebaseFirestore.instance
          .collection("users")
          .doc(uid)
          .set(userData);

      await saveRegisteredAccountLocally(email: email, password: password);

      final String notifUserName =
          (role == "Contestant" && contestantType == "Team")
              ? teamNameController.text.trim()
              : name;
      final String notifMessage =
          (role == "Contestant" && contestantType == "Team")
              ? "${teamNameController.text.trim()} registered as Team Contestant with ${memberNameControllers.length} members in TechNoWiz."
              : "$name registered as ${role == 'Contestant' ? 'Solo Contestant' : role} in TechNoWiz.";

      await FirebaseFirestore.instance.collection("notifications").add({
        "type": "new_user",
        "title": "New User Registered",
        "message": notifMessage,
        "userName": notifUserName,
        "userEmail": email,
        "role": role,
        "createdAt": FieldValue.serverTimestamp(),
        "isRead": false,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Registration Successful! Please log in."),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String message;
      switch (e.code) {
        case "email-already-in-use":
          message = "This email is already registered.";
          break;
        case "invalid-email":
          message = "Please enter a valid email address.";
          break;
        case "weak-password":
          message = "Password is too weak.";
          break;
        case "network-request-failed":
          message = "Network error. Please check your internet connection.";
          break;
        default:
          message = e.message ?? "Registration failed.";
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // =========================================================
  // REGISTER / CONTINUE WITH GOOGLE
  // =========================================================
  Future<void> registerWithGoogle() async {
    if (selectedRole == "Contestant" && contestantType == "Team") {
      final teamName = teamNameController.text.trim();
      final teamSize = int.tryParse(teamSizeController.text.trim());
      if (teamName.isEmpty || teamSize == null || teamSize < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                "Palihug ibutang ang Team Name ug Team Size (at least 2 members)."),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    }

    setState(() {
      isLoading = true;
    });

    try {
      UserCredential userCredential;
      if (kIsWeb) {
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.addScope('profile');
        googleProvider.setCustomParameters({'prompt': 'select_account'});
        userCredential =
            await FirebaseAuth.instance.signInWithPopup(googleProvider);
      } else {
        final GoogleSignIn googleSignIn = GoogleSignIn(
          serverClientId:
              '275534919089-9b4ulah2fub1uob6gbaa6ggh5tnkq3f9.apps.googleusercontent.com',
          scopes: ['email', 'profile'],
        );

        try {
          await googleSignIn.signOut();
        } catch (_) {}

        final GoogleSignInAccount? googleSignInAccount =
            await googleSignIn.signIn();

        if (googleSignInAccount == null) {
          if (mounted) setState(() => isLoading = false);
          return;
        }

        final GoogleSignInAuthentication googleAuth =
            await googleSignInAccount.authentication;

        final OAuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        userCredential =
            await FirebaseAuth.instance.signInWithCredential(credential);
      }

      final User? googleUser = userCredential.user;
      if (googleUser == null) {
        throw Exception("Unable to sign in with Google account.");
      }

      final String uid = googleUser.uid;
      final String email = googleUser.email ?? '';
      final String name = (googleUser.displayName != null &&
              googleUser.displayName!.trim().isNotEmpty)
          ? googleUser.displayName!.trim()
          : (nameController.text.trim().isNotEmpty
              ? nameController.text.trim()
              : (email.isNotEmpty ? email.split('@').first : selectedRole));

      final DocumentSnapshot<Map<String, dynamic>> userDoc =
          await FirebaseFirestore.instance.collection("users").doc(uid).get();

      String role = selectedRole;

      if (userDoc.exists) {
        // User already registered: retain existing role
        final Map<String, dynamic> userData = userDoc.data() ?? {};
        role = userData["role"]?.toString() ?? selectedRole;

        final Map<String, dynamic> updateData = {
          "status": "Online",
          "lastLogin": FieldValue.serverTimestamp(),
        };
        if (googleUser.photoURL != null &&
            (userData["photoUrl"] == null ||
                userData["photoUrl"].toString().isEmpty)) {
          updateData["photoUrl"] = googleUser.photoURL;
        }
        await FirebaseFirestore.instance
            .collection("users")
            .doc(uid)
            .update(updateData);
      } else {
        // First-time Google user: Register using the selected role on this screen
        final Map<String, dynamic> userData = {
          "uid": uid,
          "name": name,
          "fullName": name,
          "displayName": name,
          "email": email,
          "role": selectedRole,
          "photoUrl": googleUser.photoURL ?? "",
          "score": 0,
          "status": "Online",
          "createdAt": FieldValue.serverTimestamp(),
          "lastLogin": FieldValue.serverTimestamp(),
        };

        if (selectedRole == "Contestant") {
          if (contestantType == "Team") {
            final String teamName = teamNameController.text.trim().isNotEmpty
                ? teamNameController.text.trim()
                : "$name's Team";
            final List<String> teamMembers = memberNameControllers
                .map((c) => c.text.trim())
                .where((s) => s.isNotEmpty)
                .toList();
            final int teamSize = teamMembers.isNotEmpty
                ? teamMembers.length
                : (int.tryParse(teamSizeController.text.trim()) ?? 2);

            userData["contestantType"] = "team";
            userData["isTeam"] = true;
            userData["teamName"] = teamName;
            userData["teamSize"] = teamSize;
            userData["teamMembers"] = teamMembers;
            userData["members"] = teamMembers;
            userData["teamLeader"] = name;
            userData["leaderName"] = name;
            userData["name"] = teamName;
            userData["displayName"] = teamName;
            userData["fullName"] = teamName;

            try {
              await googleUser.updateDisplayName(teamName);
            } catch (_) {}
          } else {
            userData["contestantType"] = "solo";
            userData["isTeam"] = false;
            userData["teamName"] = "";
            userData["teamMembers"] = <String>[];
            userData["members"] = <String>[];
            userData["teamSize"] = 1;
            userData["name"] = name;
            userData["displayName"] = name;
            userData["fullName"] = name;

            try {
              await googleUser.updateDisplayName(name);
            } catch (_) {}
          }
        }

        await FirebaseFirestore.instance
            .collection("users")
            .doc(uid)
            .set(userData);

        final String notifUserName =
            (selectedRole == "Contestant" && contestantType == "Team")
                ? teamNameController.text.trim()
                : name;
        final String notifMessage =
            (selectedRole == "Contestant" && contestantType == "Team")
                ? "${teamNameController.text.trim()} registered via Google as Team Contestant with ${memberNameControllers.length} members in TechNoWiz."
                : "$name registered via Google as ${selectedRole == 'Contestant' ? 'Solo Contestant' : selectedRole} in TechNoWiz.";

        try {
          await FirebaseFirestore.instance.collection("notifications").add({
            "type": "new_user",
            "title": "New User Registered",
            "message": notifMessage,
            "userName": notifUserName,
            "userEmail": email,
            "role": selectedRole,
            "createdAt": FieldValue.serverTimestamp(),
            "isRead": false,
          });
        } catch (_) {}
      }

      final String normalizedRole =
          role.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');

      if (!mounted) return;

      if (normalizedRole == "admin") {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AdminDashboard()),
          (route) => false,
        );
      } else if (normalizedRole == "quizmaster") {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const QuizMasterDashboard()),
          (route) => false,
        );
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const CompetitorDashboard()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'popup-closed-by-user' || e.code == 'cancelled') {
        return;
      }
      String message = e.message ?? "Google Sign-In failed.";
      if (e.code == 'operation-not-allowed') {
        message =
            "Google Sign-In is not enabled yet in Firebase Console. Please enable Google provider under Authentication > Sign-in method.";
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    nameFocusNode.dispose();
    emailController.dispose();
    emailFocusNode.dispose();
    passwordController.dispose();
    passwordFocusNode.dispose();
    confirmPasswordController.dispose();
    confirmPasswordFocusNode.dispose();
    teamNameController.dispose();
    teamNameFocusNode.dispose();
    teamSizeController.dispose();
    teamSizeFocusNode.dispose();
    for (final node in memberFocusNodes) {
      node.dispose();
    }
    for (final controller in memberNameControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  // =========================================================
  // BUILD
  // =========================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F6FF),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double screenWidth = constraints.maxWidth;
          final double screenHeight = constraints.maxHeight;
          final bool isCompact = screenHeight < 740 || screenWidth < 360;
          final bool isLandscape = screenWidth > screenHeight && screenHeight < 550;

          final double horizontalPadding = screenWidth < 360 ? 12.0 : 18.0;
          final double maxCardWidth = screenWidth > 800 ? 460.0 : 430.0;
          final double cardWidth =
              (screenWidth - (horizontalPadding * 2)).clamp(260.0, maxCardWidth);
          final double verticalSpacing = isLandscape
              ? 10.0
              : (isCompact ? 14.0 : 20.0);

          return Stack(
            fit: StackFit.expand,
            children: [
              // 1. Radiant Clean Sky-Blue Tech Background
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFFE8F3FF),
                      Color(0xFFDCEBFC),
                      Color(0xFFD0E4FB),
                      Color(0xFFE5F1FE),
                      Color(0xFFF2F7FE),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.0, 0.25, 0.55, 0.82, 1.0],
                  ),
                ),
              ),

              // 2. High-Tech PCB Electronic Circuit Traces
              CustomPaint(
                painter: _TechCircuitBackgroundPainter(),
              ),

              // 3. Foreground Scrollable Content
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                      vertical: isLandscape ? 12 : 24,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: cardWidth),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: 10),

                          // Brand Header: Quantum Tech Processor + "TechNoWiz"
                          _buildBrandHeader(),

                          SizedBox(height: verticalSpacing),

                          // Clean Light Registration Card
                          _buildRegisterCard(isCompact: isCompact, screenWidth: screenWidth),

                          SizedBox(height: verticalSpacing),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // =========================================================
  // BRAND HEADER: 3D EXTRUDED METALLIC TECH TYPOGRAPHY
  // =========================================================
  Widget _buildBrandHeader() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. 3D Extruded Metallic "TechNoWiz" Typography Logo
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Ambient Floor Drop Shadow with Cyan Energy Glow
              Transform.translate(
                offset: const Offset(0, 7),
                child: Text(
                  "TechNoWiz",
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    foreground: Paint()
                      ..style = PaintingStyle.fill
                      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.35)
                      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
                  ),
                ),
              ),

              // 3D Extrusion Layer 4: Deep Midnight Blue Base
              Transform.translate(
                offset: const Offset(0, 4.6),
                child: const Text(
                  "TechNoWiz",
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: Color(0xFF091E42),
                  ),
                ),
              ),

              // 3D Extrusion Layer 3: Dark Navy Bevel
              Transform.translate(
                offset: const Offset(0, 3.5),
                child: const Text(
                  "TechNoWiz",
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: Color(0xFF0F3E8A),
                  ),
                ),
              ),

              // 3D Extrusion Layer 2: Cobalt Mid-Tone Bevel
              Transform.translate(
                offset: const Offset(0, 2.2),
                child: const Text(
                  "TechNoWiz",
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: Color(0xFF1D4ED8),
                  ),
                ),
              ),

              // 3D Extrusion Layer 1: Bright Blue Top Bevel
              Transform.translate(
                offset: const Offset(0, 1.1),
                child: const Text(
                  "TechNoWiz",
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: Color(0xFF3B82F6),
                  ),
                ),
              ),

              // 3D Front Face: Radiant Metallic Ice-Cyan to Deep Cobalt Gradient
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [
                    Color(0xFFF0F9FF), // Specular ice shine
                    Color(0xFF38BDF8), // Electric cyan
                    Color(0xFF2563EB), // Cobalt tech blue
                    Color(0xFF1E40AF), // Deep royal blue
                  ],
                  stops: [0.0, 0.25, 0.65, 1.0],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ).createShader(bounds),
                child: Text(
                  "TechNoWiz",
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: Colors.white,
                    shadows: [
                      // Crisp Top Specular Highlight Edge
                      Shadow(
                        color: Colors.white.withValues(alpha: 0.9),
                        offset: const Offset(0, -1),
                        blurRadius: 1.5,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // 2. Tech Subtitle Pill Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4.5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFBFDBFE),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2563EB).withValues(alpha: 0.10),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hub_rounded, color: Color(0xFF2563EB), size: 13),
                SizedBox(width: 5),
                Text(
                  "JOIN THE ULTIMATE QUIZ ARENA",
                  style: TextStyle(
                    color: Color(0xFF1E40AF),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // =========================================================
  // CLEAN LIGHT REGISTRATION CARD
  // =========================================================
  Widget _buildRegisterCard({bool isCompact = false, double screenWidth = 400}) {
    final double cardInnerHPad = screenWidth < 360 ? 14 : 18;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: const Color(0xFFBFDBFE),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E40AF).withValues(alpha: 0.09),
            blurRadius: 36,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: const Color(0xFF3B82F6).withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          // Floating Top Badge
          Positioned(
            top: -16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFF93C5FD),
                  width: 1.4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('✨', style: TextStyle(fontSize: 14)),
                  SizedBox(width: 6),
                  Text(
                    "Create Account",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),

          Padding(
            padding: EdgeInsets.fromLTRB(
              cardInnerHPad,
              isCompact ? 24 : 28,
              cardInnerHPad,
              isCompact ? 16 : 22,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 6),
                const Text(
                  "Sign up to start your journey\nin TechNoWiz!",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),

                const SizedBox(height: 20),

                // 1. Full Name Input
                _buildLightInputField(
                  controller: nameController,
                  focusNode: nameFocusNode,
                  hintText: "Full Name",
                  icon: Icons.person_outline_rounded,
                ),

                const SizedBox(height: 12),

                // 2. Email Address Input
                _buildLightInputField(
                  controller: emailController,
                  focusNode: emailFocusNode,
                  hintText: "Email Address",
                  icon: Icons.alternate_email_rounded,
                  keyboardType: TextInputType.emailAddress,
                ),

                const SizedBox(height: 16),

                // 3. SELECT ROLE SECTION
                const Row(
                  children: [
                    Icon(Icons.workspace_premium_rounded,
                        color: Color(0xFF2563EB), size: 16),
                    SizedBox(width: 6),
                    Text(
                      "SELECT ROLE",
                      style: TextStyle(
                        color: Color(0xFF1E3A8A),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Expanded(
                      child: _buildRoleCard(
                        title: "Contestant",
                        subtitle: "Compete",
                        icon: Icons.sports_esports_rounded,
                        selected: selectedRole == "Contestant",
                        onTap: () => setState(() => selectedRole = "Contestant"),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildRoleCard(
                        title: "Quizmaster",
                        subtitle: "Host & Manage",
                        icon: Icons.school_rounded,
                        selected: selectedRole == "Quizmaster",
                        onTap: () => setState(() => selectedRole = "Quizmaster"),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildRoleCard(
                        title: "Admin",
                        subtitle: "Control",
                        icon: Icons.admin_panel_settings_rounded,
                        selected: selectedRole == "Admin",
                        onTap: () => setState(() => selectedRole = "Admin"),
                      ),
                    ),
                  ],
                ),

                // 4. SOLO / TEAM SELECTION (If Contestant)
                if (selectedRole == "Contestant") ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F6FD),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFFBFDBFE),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildPillOption(
                            label: "Solo Contestant",
                            icon: Icons.person_rounded,
                            selected: contestantType == "Solo",
                            onTap: () =>
                                setState(() => contestantType = "Solo"),
                          ),
                        ),
                        Expanded(
                          child: _buildPillOption(
                            label: "Team Contestant",
                            icon: Icons.groups_rounded,
                            selected: contestantType == "Team",
                            onTap: () =>
                                setState(() => contestantType = "Team"),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // If Team Selected
                  if (contestantType == "Team") ...[
                    const SizedBox(height: 12),
                    _buildLightInputField(
                      controller: teamNameController,
                      focusNode: teamNameFocusNode,
                      hintText: "Team Name",
                      icon: Icons.shield_rounded,
                    ),

                    const SizedBox(height: 10),

                    // Team Size Input (User can type any number of members or use steppers)
                    _buildLightInputField(
                      controller: teamSizeController,
                      focusNode: teamSizeFocusNode,
                      hintText: "Enter number of team members",
                      icon: Icons.group_add_rounded,
                      keyboardType: TextInputType.number,
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.remove_circle_outline_rounded,
                              size: 20,
                              color: Color(0xFF2563EB),
                            ),
                            tooltip: "Decrease members",
                            onPressed: () {
                              final current =
                                  int.tryParse(teamSizeController.text.trim()) ?? 2;
                              if (current > 2) {
                                final next = current - 1;
                                teamSizeController.text = next.toString();
                                setState(() {
                                  _updateMemberControllers(next);
                                });
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.add_circle_outline_rounded,
                              size: 20,
                              color: Color(0xFF2563EB),
                            ),
                            tooltip: "Increase members",
                            onPressed: () {
                              final current =
                                  int.tryParse(teamSizeController.text.trim()) ?? 2;
                              final next = current + 1;
                              teamSizeController.text = next.toString();
                              setState(() {
                                _updateMemberControllers(next);
                              });
                            },
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                      onChanged: (val) {
                        final size = int.tryParse(val.trim());
                        if (size != null && size >= 1 && size <= 50) {
                          setState(() {
                            _updateMemberControllers(size);
                          });
                        }
                      },
                    ),

                    const SizedBox(height: 10),

                    // Dynamic Team Member Names
                    ...List.generate(memberNameControllers.length, (i) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildLightInputField(
                          controller: memberNameControllers[i],
                          focusNode: memberFocusNodes[i],
                          hintText: "Member ${i + 1} Full Name",
                          icon: Icons.badge_rounded,
                        ),
                      );
                    }),
                  ],
                ],

                const SizedBox(height: 12),

                // 5. Password Input
                _buildLightInputField(
                  controller: passwordController,
                  focusNode: passwordFocusNode,
                  hintText: "Password (min 6 characters)",
                  icon: Icons.lock_rounded,
                  obscureText: obscurePassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscurePassword
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: passwordFocusNode.hasFocus
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF64748B),
                      size: 20,
                    ),
                    onPressed: () {
                      setState(() {
                        obscurePassword = !obscurePassword;
                      });
                    },
                  ),
                ),

                const SizedBox(height: 12),

                // 6. Confirm Password Input
                _buildLightInputField(
                  controller: confirmPasswordController,
                  focusNode: confirmPasswordFocusNode,
                  hintText: "Confirm Password",
                  icon: Icons.lock_outline_rounded,
                  obscureText: obscureConfirmPassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscureConfirmPassword
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: confirmPasswordFocusNode.hasFocus
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF64748B),
                      size: 20,
                    ),
                    onPressed: () {
                      setState(() {
                        obscureConfirmPassword = !obscureConfirmPassword;
                      });
                    },
                  ),
                ),

                const SizedBox(height: 22),

                // 7. 3D Glossy Light-Tech "Sign Up" Button
                _buildGlossyButton(
                  label: "Sign Up",
                  icon: Icons.rocket_launch_rounded,
                  isLoading: isLoading,
                  onPressed: isLoading ? null : registerUser,
                ),

                const SizedBox(height: 16),

                // OR Divider
                const Row(
                  children: [
                    Expanded(
                      child: Divider(
                        color: Color(0xFFE2E8F0),
                        thickness: 1,
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        "OR",
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Divider(
                        color: Color(0xFFE2E8F0),
                        thickness: 1,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Continue with Google Button
                _buildGoogleButton(),

                const SizedBox(height: 18),

                // 8. Already have an account? Log In >
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "Already have an account? ",
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        child: const Text(
                          "Log In >",
                          style: TextStyle(
                            color: Color(0xFF2563EB),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // ROLE CARD CHIP
  // =========================================================
  Widget _buildRoleCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xFFEFF6FF)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected
              ? const Color(0xFF2563EB)
              : const Color(0xFFCBD5E1),
          width: selected ? 1.8 : 1.0,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Column(
              children: [
                Icon(
                  icon,
                  color: selected ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                  size: 24,
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    title,
                    style: TextStyle(
                      color: selected ? const Color(0xFF1E3A8A) : const Color(0xFF334155),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    subtitle,
                    style: TextStyle(
                      color: selected
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF64748B),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
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
  // PILL OPTION SELECTOR
  // =========================================================
  Widget _buildPillOption({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF2563EB) : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.28),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    color: selected ? Colors.white : const Color(0xFF64748B),
                    size: 15,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFF475569),
                      fontSize: 11.5,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================
  // LIGHT INPUT FIELD
  // =========================================================
  Widget _buildLightInputField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType keyboardType = TextInputType.text,
    void Function(String)? onChanged,
  }) {
    final bool isFocused = focusNode.hasFocus;
    final bool hasText = controller.text.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F6FD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isFocused
              ? const Color(0xFF2563EB)
              : hasText
                  ? const Color(0xFF60A5FA)
                  : const Color(0xFFCFE0F5),
          width: isFocused ? 1.8 : 1.2,
        ),
        boxShadow: isFocused
            ? [
                BoxShadow(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.20),
                  blurRadius: 10,
                  spreadRadius: -1,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Icon(
              icon,
              color: isFocused
                  ? const Color(0xFF2563EB)
                  : const Color(0xFF64748B),
              size: 20,
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              obscureText: obscureText,
              keyboardType: keyboardType,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onChanged: (val) {
                onChanged?.call(val);
                setState(() {});
              },
            ),
          ),
          if (suffixIcon != null) suffixIcon,
        ],
      ),
    );
  }

  // =========================================================
  // 3D GLOSSY BUTTON
  // =========================================================
  Widget _buildGlossyButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF3B82F6),
            Color(0xFF2563EB),
            Color(0xFF1D4ED8),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: const Color(0xFF93C5FD),
          width: 1.3,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.38),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: onPressed,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Top Specular Shine
              Positioned(
                top: 2,
                left: 20,
                right: 20,
                height: 14,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.45),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

              if (isLoading)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.2,
                  ),
                )
              else
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: Colors.white, size: 21),
                      const SizedBox(width: 10),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          color: Color(0xFF1E3A8A),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================
  // CONTINUE WITH GOOGLE BUTTON
  // =========================================================
  Widget _buildGoogleButton() {
    String roleLabel = selectedRole;
    if (selectedRole == "Contestant") {
      roleLabel =
          contestantType == "Team" ? "Team Contestant" : "Solo Contestant";
    }

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFCBD5E1),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: isLoading ? null : registerWithGoogle,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text(
                      "G",
                      style: TextStyle(
                        color: Color(0xFF4285F4),
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  "Continue with Google as $roleLabel",
                  style: const TextStyle(
                    color: Color(0xFF1E293B),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =========================================================
// REAL HIGH-TECH PCB CIRCUIT TRACES PAINTER
// =========================================================
class _TechCircuitBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final glowPaint = Paint()
      ..color = const Color(0xFF3B82F6).withValues(alpha: 0.16)
      ..strokeWidth = 4.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final tracePaint = Paint()
      ..color = const Color(0xFF2563EB).withValues(alpha: 0.32)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final nodeFillPaint = Paint()
      ..color = const Color(0xFF2563EB).withValues(alpha: 0.45)
      ..style = PaintingStyle.fill;

    final nodeRingPaint = Paint()
      ..color = const Color(0xFF2563EB).withValues(alpha: 0.35)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = const Color(0xFF3B82F6).withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    void drawCircuitTrace(List<Offset> points, {bool drawGlow = true, bool endRing = true}) {
      if (points.length < 2) return;
      final path = Path()..moveTo(points[0].dx, points[0].dy);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      if (drawGlow) {
        canvas.drawPath(path, glowPaint);
      }
      canvas.drawPath(path, tracePaint);

      canvas.drawCircle(points.first, 3.2, nodeFillPaint);
      canvas.drawCircle(points.last, 3.8, nodeFillPaint);
      if (endRing) {
        canvas.drawCircle(points.last, 7.5, nodeRingPaint);
      }
    }

    void drawChipFootprint(Offset center, double width, double height, int pinsPerSide) {
      final chipRect = Rect.fromCenter(center: center, width: width, height: height);
      final chipPaint = Paint()
        ..color = const Color(0xFF1E40AF).withValues(alpha: 0.16)
        ..style = PaintingStyle.fill;
      final chipBorder = Paint()
        ..color = const Color(0xFF2563EB).withValues(alpha: 0.35)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;

      canvas.drawRRect(RRect.fromRectAndRadius(chipRect, const Radius.circular(3)), chipPaint);
      canvas.drawRRect(RRect.fromRectAndRadius(chipRect, const Radius.circular(3)), chipBorder);

      final pinPaint = Paint()
        ..color = const Color(0xFF2563EB).withValues(alpha: 0.35)
        ..strokeWidth = 1.0;
      final pinStep = height / (pinsPerSide + 1);
      for (int i = 1; i <= pinsPerSide; i++) {
        final py = chipRect.top + i * pinStep;
        canvas.drawLine(Offset(chipRect.left - 4, py), Offset(chipRect.left, py), pinPaint);
        canvas.drawLine(Offset(chipRect.right, py), Offset(chipRect.right + 4, py), pinPaint);
      }
    }

    // Top-Left PCB Traces
    drawCircuitTrace([
      Offset(0, h * 0.08),
      Offset(w * 0.16, h * 0.08),
      Offset(w * 0.24, h * 0.16),
      Offset(w * 0.38, h * 0.16),
    ]);
    drawCircuitTrace([
      Offset(0, h * 0.12),
      Offset(w * 0.13, h * 0.12),
      Offset(w * 0.19, h * 0.18),
      Offset(w * 0.28, h * 0.18),
    ], endRing: false);
    drawCircuitTrace([
      Offset(w * 0.09, 0),
      Offset(w * 0.09, h * 0.05),
      Offset(w * 0.15, h * 0.11),
    ]);

    // Top-Right PCB Traces
    drawCircuitTrace([
      Offset(w, h * 0.09),
      Offset(w * 0.84, h * 0.09),
      Offset(w * 0.76, h * 0.17),
      Offset(w * 0.62, h * 0.17),
    ]);
    drawCircuitTrace([
      Offset(w, h * 0.14),
      Offset(w * 0.86, h * 0.14),
      Offset(w * 0.79, h * 0.21),
      Offset(w * 0.70, h * 0.21),
    ], endRing: false);
    drawCircuitTrace([
      Offset(w * 0.91, 0),
      Offset(w * 0.91, h * 0.06),
      Offset(w * 0.85, h * 0.12),
    ]);

    // Mid-Left Traces
    drawCircuitTrace([
      Offset(0, h * 0.36),
      Offset(w * 0.08, h * 0.36),
      Offset(w * 0.14, h * 0.42),
      Offset(w * 0.22, h * 0.42),
    ]);
    drawCircuitTrace([
      Offset(0, h * 0.62),
      Offset(w * 0.09, h * 0.62),
      Offset(w * 0.15, h * 0.56),
      Offset(w * 0.20, h * 0.56),
    ], endRing: false);

    // Mid-Right Traces
    drawCircuitTrace([
      Offset(w, h * 0.38),
      Offset(w * 0.91, h * 0.38),
      Offset(w * 0.84, h * 0.45),
      Offset(w * 0.78, h * 0.45),
    ]);
    drawCircuitTrace([
      Offset(w, h * 0.66),
      Offset(w * 0.89, h * 0.66),
      Offset(w * 0.83, h * 0.60),
      Offset(w * 0.76, h * 0.60),
    ], endRing: false);

    // Bottom-Left Traces
    drawCircuitTrace([
      Offset(0, h * 0.88),
      Offset(w * 0.16, h * 0.88),
      Offset(w * 0.23, h * 0.81),
      Offset(w * 0.36, h * 0.81),
    ]);
    drawCircuitTrace([
      Offset(w * 0.08, h),
      Offset(w * 0.08, h * 0.93),
      Offset(w * 0.14, h * 0.87),
    ]);

    // Bottom-Right Traces
    drawCircuitTrace([
      Offset(w, h * 0.86),
      Offset(w * 0.82, h * 0.86),
      Offset(w * 0.75, h * 0.79),
      Offset(w * 0.62, h * 0.79),
    ]);
    drawCircuitTrace([
      Offset(w * 0.90, h),
      Offset(w * 0.90, h * 0.92),
      Offset(w * 0.83, h * 0.85),
    ]);

    // SMD IC Chip Footprints along the motherboard
    drawChipFootprint(Offset(w * 0.38, h * 0.16), 18, 14, 3);
    drawChipFootprint(Offset(w * 0.62, h * 0.17), 18, 14, 3);
    drawChipFootprint(Offset(w * 0.22, h * 0.42), 16, 12, 2);
    drawChipFootprint(Offset(w * 0.78, h * 0.45), 16, 12, 2);
    drawChipFootprint(Offset(w * 0.36, h * 0.81), 20, 15, 3);
    drawChipFootprint(Offset(w * 0.62, h * 0.79), 20, 15, 3);

    // Micro Solder Vias
    final viaPoints = [
      Offset(w * 0.05, h * 0.22),
      Offset(w * 0.07, h * 0.25),
      Offset(w * 0.93, h * 0.24),
      Offset(w * 0.95, h * 0.28),
      Offset(w * 0.06, h * 0.72),
      Offset(w * 0.94, h * 0.74),
    ];
    for (final pt in viaPoints) {
      canvas.drawCircle(pt, 2.4, dotPaint);
      canvas.drawCircle(pt, 5.0, nodeRingPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
