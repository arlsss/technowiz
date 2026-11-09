import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AnalyticsScreen extends StatelessWidget {
  final String quizCode;

  const AnalyticsScreen({super.key, required this.quizCode});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Quiz Analytics")),
      body: FutureBuilder<QuerySnapshot>(
        future: FirebaseFirestore.instance
            .collection('quiz_sessions')
            .doc(quizCode)
            .collection('scores')
            .get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          var scores = snapshot.data!.docs;

          int totalPlayers = scores.length;

          int totalScore = 0;

          for (var doc in scores) {
            totalScore += (doc['score'] ?? 0) as int;
          }

          double averageScore = totalPlayers == 0
              ? 0
              : totalScore / totalPlayers;

          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Card(
                  child: ListTile(
                    title: const Text("Participants"),
                    trailing: Text("$totalPlayers"),
                  ),
                ),

                Card(
                  child: ListTile(
                    title: const Text("Total Score"),
                    trailing: Text("$totalScore"),
                  ),
                ),

                Card(
                  child: ListTile(
                    title: const Text("Average Score"),
                    trailing: Text(averageScore.toStringAsFixed(2)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
