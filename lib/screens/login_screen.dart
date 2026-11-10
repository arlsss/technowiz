import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'register_screen.dart';
import 'admin/admin_dashboard.dart';
import 'quizmaster/quizmaster_dashboard.dart';
import 'competitor/competitor_dashboard.dart';

class LoginScreen extends StatefulWidget {
  final bool clearCredentials;
  const LoginScreen({super.key, this.clearCredentials = false});

  static Future<void> clearSavedCredentials() async {
    try {
      const storage = FlutterSecureStorage();
      await storage.delete(key: 'saved_login_accounts');
      await storage.delete(key: 'saved_login_email');
      await storage.delete(key: 'saved_login_password');
      await storage.deleteAll();
    } catch (e) {
      debugPrint("Error clearing saved login credentials: $e");
    }
  }

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final FocusNode emailFocusNode = FocusNode();
  final TextEditingController passwordController = TextEditingController();
  final FocusNode passwordFocusNode = FocusNode();

  bool isLoading = false;
  bool obscurePassword = true;
  bool rememberMe = false;
  bool isLoadingSavedCredentials = true;

  final Map<String, String> _savedAccounts = <String, String>{};
  static const FlutterSecureStorage secureStorage = FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    emailFocusNode.addListener(() => setState(() {}));
    passwordFocusNode.addListener(() => setState(() {}));
    if (widget.clearCredentials) {
      emailController.clear();
      passwordController.clear();
      LoginScreen.clearSavedCredentials();
      setState(() {
        isLoadingSavedCredentials = false;
        rememberMe = false;
      });
    } else {
      loadSavedCredentials();
    }
  }

  // =========================================================
  // SAVED LOGIN CREDENTIALS
  // =========================================================
  Future<void> loadSavedCredentials() async {
    try {
      final savedAccountsJson = await secureStorage.read(
        key: 'saved_login_accounts',
      );

      final loadedAccounts = <String, String>{};

      if (savedAccountsJson != null && savedAccountsJson.isNotEmpty) {
        try {
          final decoded = jsonDecode(savedAccountsJson);
          if (decoded is Map) {
            for (final entry in decoded.entries) {
              final email = entry.key.toString().trim();
              final password = entry.value?.toString() ?? '';
              if (email.isNotEmpty && password.isNotEmpty) {
                loadedAccounts[email] = password;
              }
            }
          }
        } catch (e) {
          debugPrint("Error decoding saved login accounts: $e");
        }
      }

      final oldEmail = await secureStorage.read(key: 'saved_login_email');
      final oldPassword = await secureStorage.read(key: 'saved_login_password');

      if (oldEmail != null &&
          oldEmail.trim().isNotEmpty &&
          oldPassword != null &&
          oldPassword.isNotEmpty) {
        loadedAccounts[oldEmail.trim()] = oldPassword;
        await secureStorage.write(
          key: 'saved_login_accounts',
          value: jsonEncode(loadedAccounts),
        );
      }

      if (!mounted) return;

      setState(() {
        _savedAccounts
          ..clear()
          ..addAll(loadedAccounts);
        if (_savedAccounts.isNotEmpty && !widget.clearCredentials) {
          final firstEmail = _savedAccounts.keys.first;
          emailController.text = firstEmail;
          passwordController.text = _savedAccounts[firstEmail] ?? '';
          rememberMe = true;
        } else {
          emailController.clear();
          passwordController.clear();
          rememberMe = false;
        }
        isLoadingSavedCredentials = false;
      });
    } catch (e) {
      debugPrint("Error loading saved login accounts: $e");
      if (mounted) {
        setState(() {
          isLoadingSavedCredentials = false;
        });
      }
    }
  }

  Future<void> saveLoginCredentials({
    required String email,
    required String password,
  }) async {
    try {
      final String normalizedEmail = email.trim();
      final String savedAccountsJson =
          await secureStorage.read(key: 'saved_login_accounts') ?? '';

      Map<String, dynamic> savedAccounts = <String, dynamic>{};
      if (savedAccountsJson.isNotEmpty) {
        try {
          final dynamic decoded = jsonDecode(savedAccountsJson);
          if (decoded is Map) {
            savedAccounts = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {
          savedAccounts = <String, dynamic>{};
        }
      }

      savedAccounts[normalizedEmail] = password;

      await secureStorage.write(
        key: 'saved_login_accounts',
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
      debugPrint("Could not securely save login credentials: $e");
    }
  }

  // =========================================================
  // USER STATUS & NOTIFICATIONS
  // =========================================================
  Future<void> setUserOnline(String uid) async {
    try {
      await FirebaseFirestore.instance.collection("users").doc(uid).update({
        "isOnline": true,
        "lastLogin": FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Error setting user online: $e");
    }
  }

  Future<void> createLoginNotification({
    required String uid,
    required String email,
    required String role,
    String? name,
  }) async {
    try {
      final String displayName = (name != null && name.trim().isNotEmpty)
          ? name.trim()
          : email.split('@').first;

      await FirebaseFirestore.instance.collection("admin_notifications").add({
        "type": "login",
        "title": "User Logged In",
        "message": "$displayName has logged in to TechNoWiz.",
        "userId": uid,
        "userEmail": email,
        "userName": displayName,
        "role": role,
        "createdAt": FieldValue.serverTimestamp(),
        "isRead": false,
      });
    } catch (e) {
      debugPrint("Error creating login notification: $e");
    }
  }

  // =========================================================
  // LOGIN USER
  // =========================================================
  Future<void> loginUser() async {
    final rawInput = emailController.text.trim();
    final rawPassword = passwordController.text.trim();

    if (rawInput.isEmpty || rawPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter email/username and password"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      String emailToUse = rawInput;

      if (!rawInput.contains('@')) {
        final querySnap = await FirebaseFirestore.instance
            .collection('users')
            .where('username', isEqualTo: rawInput)
            .limit(1)
            .get();

        if (querySnap.docs.isNotEmpty) {
          emailToUse =
              (querySnap.docs.first.data()['email'] ?? rawInput).toString().trim();
        } else {
          final queryNameSnap = await FirebaseFirestore.instance
              .collection('users')
              .where('name', isEqualTo: rawInput)
              .limit(1)
              .get();
          if (queryNameSnap.docs.isNotEmpty) {
            emailToUse = (queryNameSnap.docs.first.data()['email'] ?? rawInput)
                .toString()
                .trim();
          }
        }
      }

      final UserCredential userCredential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailToUse,
        password: rawPassword,
      );

      final User? loggedInUser = userCredential.user;
      if (loggedInUser == null) {
        throw Exception("Unable to get logged-in user information.");
      }

      final String uid = loggedInUser.uid;
      final String email = loggedInUser.email ?? emailToUse;

      final DocumentSnapshot<Map<String, dynamic>> userDoc =
          await FirebaseFirestore.instance.collection("users").doc(uid).get();

      if (!userDoc.exists) {
        throw Exception("User account information not found.");
      }

      final Map<String, dynamic> userData = userDoc.data() ?? {};
      final String role = userData["role"]?.toString() ?? "";
      final String normalizedRole =
          role.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');

      if (rememberMe) {
        await saveLoginCredentials(email: emailToUse, password: rawPassword);
      } else {
        await LoginScreen.clearSavedCredentials();
      }

      final String? name = userData["name"]?.toString() ??
          userData["fullName"]?.toString() ??
          userData["displayName"]?.toString();

      await setUserOnline(uid);
      await createLoginNotification(
        uid: uid,
        email: email,
        role: role,
        name: name,
      );

      if (!mounted) return;

      if (normalizedRole == "admin") {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminDashboard()),
        );
      } else if (normalizedRole == "quizmaster") {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const QuizMasterDashboard()),
        );
      } else if (normalizedRole == "competitor" ||
          normalizedRole == "contestant") {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const CompetitorDashboard()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Unknown user role: $role"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String message = e.message ?? "Login Failed";
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        message = "Incorrect email/username or password.";
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
  // SIGN IN WITH GOOGLE
  // =========================================================
  Future<void> signInWithGoogle() async {
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
        // Native Google Sign-In for Android/iOS (uses native Google Play Services, no browser redirect or sessionStorage issues)
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
          // User dismissed account chooser
          if (mounted) {
            setState(() {
              isLoading = false;
            });
          }
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

      final DocumentSnapshot<Map<String, dynamic>> userDoc =
          await FirebaseFirestore.instance.collection("users").doc(uid).get();

      String role = "Contestant";

      if (!userDoc.exists) {
        // First-time Google user: Prompt user to choose their Role (Contestant, Quizmaster, Admin)
        if (!mounted) return;
        final Map<String, dynamic>? roleSelection =
            await showDialog<Map<String, dynamic>>(
          context: context,
          barrierDismissible: false,
          builder: (dialogCtx) => _GoogleRoleDialog(googleUser: googleUser),
        );

        if (roleSelection == null) {
          // User clicked Cancel
          await FirebaseAuth.instance.signOut();
          if (mounted) {
            setState(() {
              isLoading = false;
            });
          }
          return;
        }

        final String chosenRole =
            roleSelection["role"]?.toString() ?? "Contestant";
        final String displayName = (googleUser.displayName != null &&
                googleUser.displayName!.trim().isNotEmpty)
            ? googleUser.displayName!.trim()
            : (email.isNotEmpty ? email.split('@').first : chosenRole);

        final Map<String, dynamic> newUserData = {
          "uid": uid,
          "name": displayName,
          "fullName": displayName,
          "displayName": displayName,
          "email": email,
          "role": chosenRole,
          "photoUrl": googleUser.photoURL ?? "",
          "score": 0,
          "status": "Online",
          "createdAt": FieldValue.serverTimestamp(),
          "lastLogin": FieldValue.serverTimestamp(),
        };

        if (chosenRole == "Contestant") {
          final String cType =
              roleSelection["contestantType"]?.toString() ?? "Solo";
          if (cType == "Team") {
            final String teamName =
                roleSelection["teamName"]?.toString() ?? displayName;
            final List<String> teamMembers =
                List<String>.from(roleSelection["teamMembers"] ?? []);
            final int teamSize = teamMembers.isNotEmpty
                ? teamMembers.length
                : (int.tryParse(roleSelection["teamSize"]?.toString() ?? "2") ??
                    2);

            newUserData["contestantType"] = "team";
            newUserData["isTeam"] = true;
            newUserData["teamName"] = teamName;
            newUserData["teamSize"] = teamSize;
            newUserData["teamMembers"] = teamMembers;
            newUserData["members"] = teamMembers;
            newUserData["teamLeader"] = displayName;
            newUserData["leaderName"] = displayName;
            newUserData["name"] = teamName;
            newUserData["displayName"] = teamName;
            newUserData["fullName"] = teamName;

            try {
              await googleUser.updateDisplayName(teamName);
            } catch (_) {}
          } else {
            newUserData["contestantType"] = "solo";
            newUserData["isTeam"] = false;
            newUserData["teamName"] = "";
            newUserData["teamMembers"] = <String>[];
            newUserData["members"] = <String>[];
            newUserData["teamSize"] = 1;
            newUserData["name"] = displayName;
            newUserData["displayName"] = displayName;
            newUserData["fullName"] = displayName;

            try {
              await googleUser.updateDisplayName(displayName);
            } catch (_) {}
          }
        }

        await FirebaseFirestore.instance
            .collection("users")
            .doc(uid)
            .set(newUserData);

        // Add welcome notification
        final String notifUserName = (chosenRole == "Contestant" &&
                roleSelection["contestantType"] == "Team")
            ? (roleSelection["teamName"] ?? displayName)
            : displayName;
        final String notifMessage = (chosenRole == "Contestant" &&
                roleSelection["contestantType"] == "Team")
            ? "$notifUserName registered via Google as Team Contestant with ${roleSelection["teamMembers"]?.length ?? 2} members."
            : "$displayName registered via Google as $chosenRole in TechNoWiz.";

        try {
          await FirebaseFirestore.instance.collection("notifications").add({
            "title": "New User Registered",
            "message": notifMessage,
            "type": "new_user",
            "userName": notifUserName,
            "userEmail": email,
            "userId": uid,
            "role": chosenRole,
            "createdAt": FieldValue.serverTimestamp(),
            "isRead": false,
          });
        } catch (_) {}

        role = chosenRole;
      } else {
        final Map<String, dynamic> userData = userDoc.data() ?? {};
        role = userData["role"]?.toString() ?? "Contestant";

        // Update online status and photo if available
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
      }

      final String normalizedRole =
          role.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');

      final String name = googleUser.displayName ??
          (email.isNotEmpty ? email.split('@').first : "Contestant");

      await setUserOnline(uid);
      await createLoginNotification(
        uid: uid,
        email: email,
        role: role,
        name: name,
      );

      if (!mounted) return;

      if (normalizedRole == "admin") {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminDashboard()),
        );
      } else if (normalizedRole == "quizmaster") {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const QuizMasterDashboard()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const CompetitorDashboard()),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      debugPrint("Firebase Auth Exception (Google Sign-In): ${e.code} - ${e.message}");

      if (e.code == 'popup-closed-by-user' || e.code == 'cancelled') {
        // User closed the popup, no error message needed
        return;
      }

      String message = e.message ?? "Google Sign-In failed.";
      if (e.code == 'operation-not-allowed') {
        message =
            "Google Sign-In is not enabled yet in Firebase Console. Please enable Google provider under Authentication > Sign-in method.";
      } else if (e.code == 'unauthorized-domain' ||
          message.toLowerCase().contains('domain is not authorized') ||
          message.toLowerCase().contains('authorized domain')) {
        final currentHost =
            kIsWeb && Uri.base.host.isNotEmpty ? Uri.base.host : 'vercel.app';
        message =
            "Domain not authorized ($currentHost)! Palihug i-add ang '$currentHost' ug 'vercel.app' sa Firebase Console > Authentication > Settings > Authorized domains.";
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.security_rounded, color: Colors.orange, size: 28),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Domain Authorization",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Aron makasulod gamit ang Google Sign-In sa Vercel/Web, kinahanglan i-authorize ang domain sa Firebase Console:",
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: SelectableText(
                      currentHost,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    "Mga Lakang:\n1. Ablihi ang Firebase Console (technowiz-73132)\n2. Adto sa Authentication > Settings > Authorized domains\n3. I-click ang 'Add domain'\n4. I-paste ang domain sa ibabaw ug i-add pud ang 'vercel.app'",
                    style: TextStyle(
                        fontSize: 12.5, height: 1.5, color: Color(0xFF334155)),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text("OK",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }
      } else if (e.code == 'popup-blocked') {
        message =
            "Na-block ang Google login popup. Palihug i-allow/tugoti ang popups sa imong browser settings aron makapadayon.";
      } else if (message.toLowerCase().contains('package certificate hash') ||
          message.toLowerCase().contains('certificate hash')) {
        message =
            "Google Sign-In requires your app's SHA-1 fingerprint added to Firebase Console (Project Settings > Android app).";
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      debugPrint("General Exception (Google Sign-In): $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Google Sign-In Error: $e"),
          backgroundColor: Colors.redAccent,
        ),
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
  // FORGOT PASSWORD DIALOG
  // =========================================================
  void _showForgotPasswordDialog() {
    final TextEditingController resetEmailController =
        TextEditingController(text: emailController.text.trim());

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF93C5FD), width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.lock_reset_rounded, color: Color(0xFF2563EB), size: 24),
            SizedBox(width: 10),
            Text(
              'Reset Password',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your registered email address and we will send you a password reset link.',
              style: TextStyle(color: Color(0xFF475569), fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 18),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF1F6FD),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: TextField(
                controller: resetEmailController,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Enter your email',
                  hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  prefixIcon: Icon(Icons.email_outlined, color: Color(0xFF2563EB), size: 20),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 3,
            ),
            onPressed: () async {
              final email = resetEmailController.text.trim();
              if (email.isEmpty) return;
              Navigator.pop(dialogCtx);
              try {
                await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Password reset link sent to your email.'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
                );
              }
            },
            child: const Text(
              'Send Link',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    emailFocusNode.dispose();
    passwordController.dispose();
    passwordFocusNode.dispose();
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
          final bool isCompact = screenHeight < 720 || screenWidth < 360;
          final bool isLandscape = screenWidth > screenHeight && screenHeight < 550;

          final double horizontalPadding = screenWidth < 360 ? 12.0 : 18.0;
          final double maxCardWidth = screenWidth > 800 ? 440.0 : 410.0;
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

              // 2. High-Tech PCB Electronic Circuit Traces & Microchip Nodes
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
                          // Brand Header: Quantum Tech Processor Emblem + "TechNoWiz"
                          _buildBrandHeader(),

                          SizedBox(height: verticalSpacing),

                          // Clean Light Glass Card
                          _buildLoginCard(isCompact: isCompact, screenWidth: screenWidth),

                          SizedBox(height: verticalSpacing),

                          // Slogan
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF2563EB),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  "TECHNOWIZ",
                                  style: TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF2563EB),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
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
                offset: const Offset(0, 8),
                child: Text(
                  "TechNoWiz",
                  style: TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
                    foreground: Paint()
                      ..style = PaintingStyle.fill
                      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.35)
                      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
                  ),
                ),
              ),

              // 3D Extrusion Layer 4: Deep Midnight Blue Base
              Transform.translate(
                offset: const Offset(0, 5.0),
                child: const Text(
                  "TechNoWiz",
                  style: TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
                    color: Color(0xFF091E42),
                  ),
                ),
              ),

              // 3D Extrusion Layer 3: Dark Navy Bevel
              Transform.translate(
                offset: const Offset(0, 3.8),
                child: const Text(
                  "TechNoWiz",
                  style: TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
                    color: Color(0xFF0F3E8A),
                  ),
                ),
              ),

              // 3D Extrusion Layer 2: Cobalt Mid-Tone Bevel
              Transform.translate(
                offset: const Offset(0, 2.4),
                child: const Text(
                  "TechNoWiz",
                  style: TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
                    color: Color(0xFF1D4ED8),
                  ),
                ),
              ),

              // 3D Extrusion Layer 1: Bright Blue Top Bevel
              Transform.translate(
                offset: const Offset(0, 1.2),
                child: const Text(
                  "TechNoWiz",
                  style: TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
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
                    fontSize: 52,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
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
                Icon(Icons.hub_rounded, color: Color(0xFF2563EB), size: 14),
                SizedBox(width: 6),
                Text(
                  "TECH QUIZ ARENA  •  COMPETE  •  WIN",
                  style: TextStyle(
                    color: Color(0xFF1E40AF),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
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
  // CLEAN LIGHT GLASS LOGIN CARD
  // =========================================================
  Widget _buildLoginCard({bool isCompact = false, double screenWidth = 400}) {
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
                  Text('👋', style: TextStyle(fontSize: 14)),
                  SizedBox(width: 6),
                  Text(
                    "Welcome",
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
              screenWidth < 360 ? 16 : 22,
              isCompact ? 24 : 28,
              screenWidth < 360 ? 16 : 22,
              isCompact ? 16 : 22,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 6),
                const Text(
                  "Log in to continue your journey\nin TechNoWiz!",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),

                const SizedBox(height: 20),

                // 1. Email Address or Username Input
                _buildLightInputField(
                  controller: emailController,
                  focusNode: emailFocusNode,
                  hintText: "Email Address or Username",
                  icon: Icons.person_rounded,
                  keyboardType: TextInputType.emailAddress,
                ),

                const SizedBox(height: 14),

                // 2. Password Input
                _buildLightInputField(
                  controller: passwordController,
                  focusNode: passwordFocusNode,
                  hintText: "Password",
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

                // 3. Remember Me & Forgot Password Row
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Remember Me Checkbox
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () {
                          setState(() {
                            rememberMe = !rememberMe;
                          });
                          if (!rememberMe) {
                            LoginScreen.clearSavedCredentials();
                          }
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: rememberMe
                                    ? const Color(0xFF2563EB)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: rememberMe
                                      ? const Color(0xFF2563EB)
                                      : const Color(0xFF94A3B8),
                                  width: 1.4,
                                ),
                                boxShadow: rememberMe
                                    ? [
                                        BoxShadow(
                                          color: const Color(0xFF2563EB)
                                              .withValues(alpha: 0.35),
                                          blurRadius: 6,
                                        ),
                                      ]
                                    : null,
                              ),
                              child: rememberMe
                                  ? const Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                      size: 14,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              "Remember Me",
                              style: TextStyle(
                                color: Color(0xFF334155),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 16),

                      // Forgot Password
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: _showForgotPasswordDialog,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                          child: Text(
                            "Forgot Password?",
                            style: TextStyle(
                              color: Color(0xFF2563EB),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // 4. 3D Glossy Light-Tech Button
                _buildGlossyButton(
                  label: "Log In",
                  icon: Icons.sports_esports_rounded,
                  isLoading: isLoading || isLoadingSavedCredentials,
                  onPressed: (isLoading || isLoadingSavedCredentials)
                      ? null
                      : loginUser,
                ),

                const SizedBox(height: 18),

                // 5. Divider with "OR" Chip
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 1,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              const Color(0xFF93C5FD).withValues(alpha: 0.7),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F6FD),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFBFDBFE),
                            width: 1,
                          ),
                        ),
                        child: const Text(
                          "OR",
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 1,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF93C5FD).withValues(alpha: 0.7),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // 6. Continue with Google Button
                _buildGoogleButton(),

                const SizedBox(height: 18),

                // 7. Don't have an account? Sign Up >
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "Don't have an account? ",
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const RegisterScreen(),
                            ),
                          );
                        },
                        child: const Text(
                          "Sign Up >",
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
              onChanged: (_) => setState(() {}),
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
          onTap: isLoading ? null : signInWithGoogle,
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
                const Text(
                  "Continue with Google",
                  style: TextStyle(
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

    // Glowing track aura
    final glowPaint = Paint()
      ..color = const Color(0xFF3B82F6).withValues(alpha: 0.16)
      ..strokeWidth = 4.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Sharp PCB track trace
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

      // Solder via pads
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

    // Micro Solder Vias (Scattered in tech clusters)
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

// =========================================================
// GOOGLE ROLE SELECTION DIALOG (For new Google users)
// =========================================================
class _GoogleRoleDialog extends StatefulWidget {
  final User googleUser;
  const _GoogleRoleDialog({required this.googleUser});

  @override
  State<_GoogleRoleDialog> createState() => _GoogleRoleDialogState();
}

class _GoogleRoleDialogState extends State<_GoogleRoleDialog> {
  String selectedRole = "Contestant";
  String contestantType = "Solo";

  final TextEditingController teamNameController = TextEditingController();
  final TextEditingController teamSizeController =
      TextEditingController(text: "2");
  final List<TextEditingController> memberNameControllers = [
    TextEditingController(),
    TextEditingController(),
  ];

  @override
  void dispose() {
    teamNameController.dispose();
    teamSizeController.dispose();
    for (final c in memberNameControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _updateMemberControllers(int count) {
    if (count < 2) count = 2;
    if (count > 20) count = 20;
    while (memberNameControllers.length < count) {
      memberNameControllers.add(TextEditingController());
    }
    while (memberNameControllers.length > count) {
      final last = memberNameControllers.removeLast();
      last.dispose();
    }
  }

  void _confirm() {
    if (selectedRole == "Contestant" && contestantType == "Team") {
      final tName = teamNameController.text.trim();
      final size = int.tryParse(teamSizeController.text.trim()) ?? 2;
      if (tName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Palihug ibutang ang Team Name."),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
      final validMembers = memberNameControllers
          .map((c) => c.text.trim())
          .where((m) => m.isNotEmpty)
          .toList();
      if (validMembers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Palihug ibutang ang mga miyembro sa team."),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      Navigator.of(context).pop({
        "role": "Contestant",
        "contestantType": "Team",
        "teamName": tName,
        "teamSize": size,
        "teamMembers": validMembers,
      });
      return;
    }

    Navigator.of(context).pop({
      "role": selectedRole,
      "contestantType": contestantType,
    });
  }

  @override
  Widget build(BuildContext context) {
    final String displayName = widget.googleUser.displayName ??
        (widget.googleUser.email != null
            ? widget.googleUser.email!.split('@').first
            : "Contestant");

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Google User Info Banner
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: const Color(0xFF2563EB),
                    backgroundImage: widget.googleUser.photoURL != null
                        ? NetworkImage(widget.googleUser.photoURL!)
                        : null,
                    child: widget.googleUser.photoURL == null
                        ? Text(
                            displayName.isNotEmpty
                                ? displayName[0].toUpperCase()
                                : "U",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          widget.googleUser.email ?? "",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),
              const Divider(color: Color(0xFFE2E8F0), height: 1),
              const SizedBox(height: 16),

              // Title: SELECT YOUR ROLE
              const Row(
                children: [
                  Icon(Icons.workspace_premium_rounded,
                      color: Color(0xFF2563EB), size: 16),
                  SizedBox(width: 6),
                  Text(
                    "CHOOSE YOUR ROLE",
                    style: TextStyle(
                      color: Color(0xFF1E3A8A),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 3 Role Cards (Contestant, Quizmaster, Admin)
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
                      subtitle: "Host",
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

              // Contestant Type (Solo / Team)
              if (selectedRole == "Contestant") ...[
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Icon(Icons.category_rounded,
                        color: Color(0xFF2563EB), size: 15),
                    SizedBox(width: 6),
                    Text(
                      "CONTESTANT PARTICIPATION TYPE",
                      style: TextStyle(
                        color: Color(0xFF1E3A8A),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
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
                        child: _buildPill(
                          label: "Solo Contestant",
                          icon: Icons.person_rounded,
                          selected: contestantType == "Solo",
                          onTap: () => setState(() => contestantType = "Solo"),
                        ),
                      ),
                      Expanded(
                        child: _buildPill(
                          label: "Team Contestant",
                          icon: Icons.groups_rounded,
                          selected: contestantType == "Team",
                          onTap: () => setState(() => contestantType = "Team"),
                        ),
                      ),
                    ],
                  ),
                ),

                // Team options
                if (contestantType == "Team") ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: teamNameController,
                    decoration: InputDecoration(
                      hintText: "Team Name",
                      prefixIcon: const Icon(Icons.shield_rounded,
                          color: Color(0xFF2563EB), size: 20),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                            color: Color(0xFF2563EB), width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Team Size Stepper
                  TextField(
                    controller: teamSizeController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: "Number of members",
                      prefixIcon: const Icon(Icons.group_add_rounded,
                          color: Color(0xFF2563EB), size: 20),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                            color: Color(0xFF2563EB), width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(
                                Icons.remove_circle_outline_rounded,
                                size: 20,
                                color: Color(0xFF2563EB)),
                            onPressed: () {
                              final current =
                                  int.tryParse(teamSizeController.text.trim()) ??
                                      2;
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
                            icon: const Icon(Icons.add_circle_outline_rounded,
                                size: 20, color: Color(0xFF2563EB)),
                            onPressed: () {
                              final current =
                                  int.tryParse(teamSizeController.text.trim()) ??
                                      2;
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
                    ),
                    onChanged: (val) {
                      final size = int.tryParse(val.trim());
                      if (size != null && size >= 2 && size <= 20) {
                        setState(() {
                          _updateMemberControllers(size);
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 10),

                  // Member names
                  ...List.generate(memberNameControllers.length, (i) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        controller: memberNameControllers[i],
                        decoration: InputDecoration(
                          hintText: "Member ${i + 1} Name",
                          prefixIcon: const Icon(Icons.person_outline_rounded,
                              color: Color(0xFF64748B), size: 18),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                      ),
                    );
                  }),
                ],
              ],

              const SizedBox(height: 20),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                      ),
                      onPressed: () => Navigator.of(context).pop(null),
                      child: const Text(
                        "Cancel",
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFF2563EB).withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: _confirm,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Confirm & Enter",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(width: 6),
                            Icon(Icons.arrow_forward_rounded,
                                color: Colors.white, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEFF6FF) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
            width: selected ? 1.8 : 1.0,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color:
                  selected ? const Color(0xFF2563EB) : const Color(0xFF64748B),
              size: 24,
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(
                color: selected
                    ? const Color(0xFF1E3A8A)
                    : const Color(0xFF1E293B),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                color: selected
                    ? const Color(0xFF3B82F6)
                    : const Color(0xFF94A3B8),
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPill({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: selected
                    ? const Color(0xFF2563EB)
                    : const Color(0xFF64748B)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? const Color(0xFF1E3A8A)
                    : const Color(0xFF64748B),
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
