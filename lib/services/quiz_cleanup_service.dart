import 'package:cloud_firestore/cloud_firestore.dart';

/// Centralized service to completely and permanently purge quiz sessions from Firestore,
/// including all subcollections, nested responses, reports, and notifications,
/// while immediately marking the records as deleted to instantly update active real-time listeners.
class QuizCleanupService {
  /// Thoroughly purges a quiz session from the database.
  static Future<void> purgeQuizSessionFully({
    required FirebaseFirestore firestore,
    required String docId,
    String quizCode = '',
  }) async {
    final effectiveCode =
        quizCode.trim().isNotEmpty ? quizCode.trim() : docId.trim();

    // 1. Gather all DocumentReferences that represent this quiz in quiz_sessions
    final Set<DocumentReference<Map<String, dynamic>>> sessionRefs = {};

    if (docId.trim().isNotEmpty) {
      sessionRefs.add(firestore.collection('quiz_sessions').doc(docId.trim()));
    }
    if (effectiveCode.isNotEmpty && effectiveCode != docId.trim()) {
      sessionRefs.add(firestore.collection('quiz_sessions').doc(effectiveCode));
    }

    // Also look up any documents where quizCode == code or code == code
    try {
      if (effectiveCode.isNotEmpty) {
        final queryByCode = await firestore
            .collection('quiz_sessions')
            .where('quizCode', isEqualTo: effectiveCode)
            .get();
        for (final doc in queryByCode.docs) {
          sessionRefs.add(doc.reference);
        }

        final queryByCodeField = await firestore
            .collection('quiz_sessions')
            .where('code', isEqualTo: effectiveCode)
            .get();
        for (final doc in queryByCodeField.docs) {
          sessionRefs.add(doc.reference);
        }
      }
    } catch (_) {}

    // 2. Mark ALL matching documents as deleted and unpublished immediately.
    // This instantly hides them from real-time streams across contestants and quizmasters.
    for (final ref in sessionRefs) {
      try {
        await ref.set({
          'deleted': true,
          'isDeleted': true,
          'status': 'deleted',
          'published': false,
          'isPublished': false,
        }, SetOptions(merge: true));
      } catch (_) {}
    }

    // Standard subcollections directly under quiz_sessions/{id}
    final subcollections = [
      'scores',
      'questions',
      'join_requests',
      'participants',
      'submissions',
      'contest_requests',
      'levels',
      'quiz_levels',
      'contestants',
      'finalScores',
      'results',
    ];

    Future<void> deleteQueryBatch(Query<Map<String, dynamic>> query) async {
      try {
        final snapshot = await query.get();
        for (int i = 0; i < snapshot.docs.length; i += 400) {
          final batch = firestore.batch();
          final end =
              (i + 400 < snapshot.docs.length) ? i + 400 : snapshot.docs.length;
          for (int j = i; j < end; j++) {
            batch.delete(snapshot.docs[j].reference);
          }
          await batch.commit();
        }
      } catch (_) {}
    }

    // 3. Purge all subcollections (and nested answers -> responses) for each session reference
    for (final ref in sessionRefs) {
      // First handle answers and its nested responses subcollection
      try {
        final answersSnap = await ref.collection('answers').get();
        for (final ansDoc in answersSnap.docs) {
          try {
            await deleteQueryBatch(ansDoc.reference.collection('responses'));
          } catch (_) {}
          try {
            await ansDoc.reference.delete();
          } catch (_) {}
        }
      } catch (_) {}

      // Delete other subcollections
      for (final subName in subcollections) {
        try {
          await deleteQueryBatch(ref.collection(subName));
        } catch (_) {}
      }

      // Finally delete the session document itself
      try {
        await ref.delete();
      } catch (_) {}
    }

    // 4. Purge quiz_reports for this quiz (including levels and contestants)
    if (effectiveCode.isNotEmpty) {
      try {
        final reportRef = firestore.collection('quiz_reports').doc(effectiveCode);
        final levelsSnap = await reportRef.collection('levels').get();
        for (final levelDoc in levelsSnap.docs) {
          try {
            await deleteQueryBatch(levelDoc.reference.collection('contestants'));
          } catch (_) {}
          try {
            await levelDoc.reference.delete();
          } catch (_) {}
        }
        await reportRef.delete();
      } catch (_) {}
    }

    // 5. Purge notifications linked to this quiz
    if (effectiveCode.isNotEmpty) {
      try {
        await deleteQueryBatch(
          firestore
              .collection('notifications')
              .where('quizCode', isEqualTo: effectiveCode),
        );
      } catch (_) {}
      try {
        await deleteQueryBatch(
          firestore
              .collection('admin_notifications')
              .where('quizCode', isEqualTo: effectiveCode),
        );
      } catch (_) {}
    }
  }
}
