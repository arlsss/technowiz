import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'screens/login_screen.dart';
import 'screens/admin/admin_dashboard.dart';
import 'screens/quizmaster/quizmaster_dashboard.dart';
import 'screens/competitor/competitor_dashboard.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),

      builder: (context, snapshot) {
        // =====================================================
        // WAITING FOR FIREBASE AUTH
        // =====================================================

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF020D2B),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF1688FF)),
            ),
          );
        }

        // =====================================================
        // NOT LOGGED IN
        // =====================================================

        final User? user = snapshot.data;

        if (user == null) {
          return const LoginScreen();
        }

        // =====================================================
        // LOGGED IN
        // GET USER DATA
        // =====================================================

        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get(),

          builder: (context, userSnapshot) {
            // =================================================
            // LOADING USER DATA
            // =================================================

            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                backgroundColor: Color(0xFF020D2B),
                body: Center(
                  child: CircularProgressIndicator(color: Color(0xFF1688FF)),
                ),
              );
            }

            // =================================================
            // USER DOCUMENT NOT FOUND
            // =================================================

            if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
              return const Scaffold(
                backgroundColor: Color(0xFF020D2B),
                body: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'User account information not found.',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }

            // =================================================
            // GET USER DATA
            // =================================================

            final Map<String, dynamic>? data = userSnapshot.data!.data();

            final String role = data?['role']?.toString() ?? '';

            // =================================================
            // ADMIN
            // =================================================

            if (role == 'Admin') {
              return const AdminDashboard();
            }

            // =================================================
            // QUIZ MASTER
            // =================================================

            if (role == 'Quiz Master') {
              return const QuizMasterDashboard();
            }

            // =================================================
            // CONTESTANT
            // =================================================

            if (role == 'Competitor') {
              return const CompetitorDashboard();
            }

            // =================================================
            // UNKNOWN ROLE
            // =================================================

            return Scaffold(
              backgroundColor: const Color(0xFF020D2B),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Unknown user role: $role',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
