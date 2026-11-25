import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CompetitorScoreScreen extends StatelessWidget {
  const CompetitorScoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Score"),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collectionGroup('scores')
            .where(FieldPath.documentId, isEqualTo: uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          int totalScore = 0;
          if (snapshot.data!.docs.isNotEmpty) {
            final data = snapshot.data!.docs.first.data() as Map<String, dynamic>;
            totalScore = int.tryParse(data['score']?.toString() ?? '') ??
                int.tryParse(data['totalScore']?.toString() ?? '') ?? 0;
            int lvlSum = 0;
            for (int l = 1; l <= 20; l++) {
              final v = data['level${l}Score'] ?? data['level_$l'];
              if (v != null) lvlSum += int.tryParse(v.toString()) ?? 0;
            }
            if (data['levelScores'] is Map) {
              int mSum = 0;
              for (final v in (data['levelScores'] as Map).values) {
                if (v != null) mSum += int.tryParse(v.toString()) ?? 0;
              }
              if (mSum > lvlSum) lvlSum = mSum;
            }
            final tiePts = int.tryParse(data['tieBreakerScore']?.toString() ?? '') ?? 0;
            if (lvlSum > 0) {
              totalScore = lvlSum + tiePts;
            } else if (tiePts > 0) {
              totalScore += tiePts;
            }
          }

          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.emoji_events,
                    size: 100,
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 30),
                  const Text(
                    "YOUR CURRENT SCORE",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "$totalScore",
                    style: const TextStyle(
                      fontSize: 80,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Score updates automatically.",
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
