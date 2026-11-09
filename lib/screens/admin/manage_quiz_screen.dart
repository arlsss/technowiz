import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_theme.dart';

import 'admin_dashboard.dart';
import '../../navigation_persistence.dart';

class ManageQuizScreen extends StatefulWidget {
  const ManageQuizScreen({super.key});


  @override
  State<ManageQuizScreen> createState() => _ManageQuizScreenState();
}

class _ManageQuizScreenState extends State<ManageQuizScreen> {
  @override
  void initState() {
    super.initState();
    AdminNavPersistence.savePage('manage_quiz');
  }


  // ============================================================
  // COLORS - NEW UI
  // ============================================================

  static const Color primaryBlue = AdminThemeColors.primary;
  static const Color lightBlue = AdminThemeColors.primaryLight;
  static const Color darkBlue = AdminThemeColors.primaryDark;

  static const Color accentTeal = AdminThemeColors.accentLavender;
  static const Color backgroundColor = AdminThemeColors.background;
  static const Color textDark = AdminThemeColors.textPrimary;

  // ============================================================
  // TOP NOTIFICATION
  // ============================================================

  void showTopMessage(
    BuildContext context,
    String message, {
    Color? color,
  }) {
    AdminNotification.show(context, message);
  }

  // ============================================================
  // DELETE QUIZ
  // ============================================================

  Future<void> deleteQuiz(BuildContext context, String quizCode) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 10),
          contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 10),
          actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          title: const Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.redAccent,
                size: 28,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Delete Quiz?",
                  style: TextStyle(
                    color: textDark,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            "Are you sure you want to delete quiz code:\n\n"
            "$quizCode\n\n"
            "This action cannot be undone.",
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade700,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
              child: const Text(
                "CANCEL",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text(
                "DELETE",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      final firestore = FirebaseFirestore.instance;

      // Reference sa quiz session
      final quizRef = firestore.collection('quiz_sessions').doc(quizCode);

      // --------------------------------------------------------
      // DELETE SCORES SUBCOLLECTION
      // --------------------------------------------------------

      final scoresSnapshot = await quizRef.collection('scores').get();

      for (final doc in scoresSnapshot.docs) {
        await doc.reference.delete();
      }

      // --------------------------------------------------------
      // DELETE QUIZ SESSION
      // --------------------------------------------------------

      await quizRef.delete();

      if (!context.mounted) return;

      showTopMessage(
        context,
        "Quiz $quizCode deleted successfully.",
        color: accentTeal,
      );
    } catch (e) {
      if (!context.mounted) return;

      showTopMessage(
        context,
        "Error deleting quiz: $e",
        color: Colors.redAccent,
      );
    }
  }

  // ============================================================
  // STATUS COLOR
  // ============================================================

  Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return accentTeal;

      case 'waiting':
        return Colors.orange;

      case 'finished':
      case 'completed':
        return primaryBlue;

      default:
        return Colors.grey;
    }
  }

  // ============================================================
  // STATUS ICON
  // ============================================================

  IconData getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Icons.play_circle_fill_rounded;

      case 'waiting':
        return Icons.hourglass_top_rounded;

      case 'finished':
      case 'completed':
        return Icons.check_circle_rounded;

      default:
        return Icons.info_rounded;
    }
  }

  // ============================================================
  // QUIZ CARD
  // ============================================================

  Widget quizCard(BuildContext context, DocumentSnapshot quiz) {
    final quizCode = quiz.id;

    final data = quiz.data() as Map<String, dynamic>? ?? {};

    final status = data['status']?.toString() ?? 'waiting';

    final currentQuestion = (data['currentQuestion'] ?? 0) as int;

    final currentLevel = (data['currentLevel'] ?? 1) as int;

    final statusColor = getStatusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        children: [
          // ====================================================
          // CARD HEADER
          // ====================================================
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(19),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [primaryBlue, darkBlue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.quiz_rounded,
                    color: Colors.white,
                    size: 29,
                  ),
                ),

                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "QUIZ SESSION",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),

                      const SizedBox(height: 5),

                      Text(
                        quizCode,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),

                // DELETE ICON
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    tooltip: "Delete Quiz",
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.white,
                      size: 21,
                    ),
                    onPressed: () {
                      deleteQuiz(context, quizCode);
                    },
                  ),
                ),
              ],
            ),
          ),

          // ====================================================
          // CARD BODY
          // ====================================================
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                // STATUS
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(
                          getStatusIcon(status),
                          color: statusColor,
                          size: 21,
                        ),
                      ),

                      const SizedBox(width: 12),

                      const Expanded(
                        child: Text(
                          "STATUS",
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),

                      Text(
                        status.replaceAll('_', ' ').toUpperCase(),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // LEVEL + QUESTION
                Row(
                  children: [
                    Expanded(
                      child: _infoBox(
                        icon: Icons.layers_rounded,
                        label: "LEVEL",
                        value: "$currentLevel",
                        iconColor: primaryBlue,
                      ),
                    ),

                    const SizedBox(width: 10),

                    Expanded(
                      child: _infoBox(
                        icon: Icons.help_outline_rounded,
                        label: "QUESTION",
                        value: "${currentQuestion + 1} / 30",
                        iconColor: accentTeal,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 17),

                // DELETE BUTTON
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.delete_outline_rounded, size: 21),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shadowColor: Colors.redAccent.withValues(alpha: 0.25),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      deleteQuiz(context, quizCode);
                    },
                    label: const Text(
                      "DELETE QUIZ",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // INFO BOX
  // ============================================================

  Widget _infoBox({
    required IconData icon,
    required String label,
    required String value,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 35,
            height: 35,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 19),
          ),

          const SizedBox(width: 9),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,

      // ========================================================
      // APP BAR
      // ========================================================
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: textDark),
          tooltip: 'Back to Dashboard',
          onPressed: () {
            final navigator = Navigator.of(context);
            if (navigator.canPop()) {
              navigator.pop();
            } else {
              AdminNavPersistence.savePage('dashboard');
              navigator.pushReplacement(
                MaterialPageRoute(
                  builder: (_) => const AdminDashboard(restoreLastPage: false),
                ),
              );
            }
          },
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,

        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Manage Quiz Sessions",
              style: TextStyle(
                color: textDark,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            SizedBox(height: 2),

            Text(
              "Manage your active quiz competitions",
              style: TextStyle(color: Colors.grey, fontSize: 11),
            ),
          ],
        ),

        actions: [
          Container(
            margin: const EdgeInsets.only(right: 15),
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AdminThemeColors.pillBg,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.dashboard_customize_rounded,
              color: primaryBlue,
              size: 21,
            ),
          ),
        ],
      ),

      // ========================================================
      // BODY
      // ========================================================
      body: AdminCircuitBackground(
        child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('quiz_sessions')
            .snapshots(),

        builder: (context, snapshot) {
          // ----------------------------------------------------
          // LOADING
          // ----------------------------------------------------

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: primaryBlue),
            );
          }

          // ----------------------------------------------------
          // ERROR
          // ----------------------------------------------------

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(25),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.error_outline_rounded,
                        size: 48,
                        color: Colors.redAccent,
                      ),
                    ),

                    const SizedBox(height: 18),

                    const Text(
                      "Unable to Load Quiz Sessions",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: textDark,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      "Something went wrong while loading "
                      "your quiz sessions.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // ----------------------------------------------------
          // NO QUIZZES
          // ----------------------------------------------------

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(25),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 110,
                      height: 110,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [lightBlue, primaryBlue],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.quiz_rounded,
                        color: Colors.white,
                        size: 52,
                      ),
                    ),

                    const SizedBox(height: 22),

                    const Text(
                      "No Quiz Sessions",
                      style: TextStyle(
                        color: textDark,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      "Create a quiz session first\n"
                      "to manage it here.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final quizzes = snapshot.data!.docs;

          // ----------------------------------------------------
          // QUIZ LIST
          // ----------------------------------------------------

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
            children: [
              // ==================================================
              // HEADER BANNER
              // ==================================================
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [primaryBlue, darkBlue],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: AdminThemeColors.primary.withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 57,
                      height: 57,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.settings_suggest_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),

                    const SizedBox(width: 15),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "ADMIN PANEL",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),

                          const SizedBox(height: 5),

                          const Text(
                            "Quiz Management",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          const SizedBox(height: 4),

                          Text(
                            "${quizzes.length} quiz session"
                            "${quizzes.length == 1 ? '' : 's'} available",
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 25),

              // ==================================================
              // SECTION TITLE
              // ==================================================
              const Text(
                "Quiz Sessions",
                style: TextStyle(
                  color: textDark,
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 5),

              const Text(
                "Manage and monitor your quiz competitions.",
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),

              const SizedBox(height: 16),

              // ==================================================
              // QUIZ CARDS
              // ==================================================
              ...quizzes.map((quiz) => quizCard(context, quiz)),
            ],
          );
        },
      ),
    ),
  );
  }
}
