import 'package:flutter/material.dart';

import 'admin/admin_dashboard.dart';
import 'quizmaster/quizmaster_dashboard.dart';
import 'competitor/competitor_dashboard.dart';

class RoleSelectionScreen extends StatelessWidget {
  final String userRole;

  const RoleSelectionScreen({super.key, required this.userRole});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Select Role"), centerTitle: true),

      body: Padding(
        padding: const EdgeInsets.all(20),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            const Icon(Icons.quiz, size: 90, color: Colors.blue),

            const SizedBox(height: 20),

            const Text(
              "TechNoWiz",
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            Text(
              "Logged in as: $userRole",
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),

            const SizedBox(height: 40),

            // =========================
            // ADMIN
            // =========================
            SizedBox(
              width: double.infinity,
              height: 60,

              child: ElevatedButton.icon(
                icon: const Icon(Icons.admin_panel_settings),

                label: const Text("ADMIN", style: TextStyle(fontSize: 18)),

                onPressed: userRole == "Admin"
                    ? () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdminDashboard(),
                          ),
                        );
                      }
                    : null,
              ),
            ),

            const SizedBox(height: 15),

            // =========================
            // QUIZ MASTER
            // =========================
            SizedBox(
              width: double.infinity,
              height: 60,

              child: ElevatedButton.icon(
                icon: const Icon(Icons.school),

                label: const Text(
                  "QUIZ MASTER",
                  style: TextStyle(fontSize: 18),
                ),

                onPressed: userRole == "Quiz Master"
                    ? () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const QuizMasterDashboard(),
                          ),
                        );
                      }
                    : null,
              ),
            ),

            const SizedBox(height: 15),

            // =========================
            // COMPETITOR
            // =========================
            SizedBox(
              width: double.infinity,
              height: 60,

              child: ElevatedButton.icon(
                icon: const Icon(Icons.person),

                label: const Text("COMPETITOR", style: TextStyle(fontSize: 18)),

                onPressed: userRole == "Competitor"
                    ? () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CompetitorDashboard(),
                          ),
                        );
                      }
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
