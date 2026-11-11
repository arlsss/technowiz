import 'package:shared_preferences/shared_preferences.dart';

class NavigationPersistence {
  static const String roleKey = 'technowiz_current_role';
  static const String pageKey = 'technowiz_current_page';
  static const String quizCodeKey = 'technowiz_current_quiz_code';
  static const String levelKey = 'technowiz_current_level';

  static Future<void> save({
    required String role,
    required String page,
    String? quizCode,
    int? level,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(roleKey, role);
    await prefs.setString(pageKey, page);

    if (quizCode != null && quizCode.trim().isNotEmpty) {
      await prefs.setString(quizCodeKey, quizCode);
    } else {
      await prefs.remove(quizCodeKey);
    }

    if (level != null) {
      await prefs.setInt(levelKey, level);
    } else {
      await prefs.remove(levelKey);
    }
  }

  static Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(roleKey);
  }

  static Future<String?> getPage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(pageKey);
  }

  static Future<String?> getQuizCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(quizCodeKey);
  }

  static Future<int?> getLevel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(levelKey);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(roleKey);
    await prefs.remove(pageKey);
    await prefs.remove(quizCodeKey);
    await prefs.remove(levelKey);
  }
}

/// Centralized navigation state persistence for all Admin screens and sub-screens.
/// Ensures that when the browser is refreshed or reloaded, the exact Admin page
/// is restored seamlessly without dropping back to the dashboard.
class AdminNavPersistence {
  static const String lastPageKey = 'technowiz_admin_last_page';
  static const String detailQuizCodeKey = 'technowiz_admin_detail_quiz_code';
  static const String historyQuizCodeKey = 'technowiz_admin_history_quiz_code';
  static const String historyQuizTitleKey = 'technowiz_admin_history_quiz_title';
  static const String historyQuizDateKey = 'technowiz_admin_history_quiz_date';
  static const String historyDocIdKey = 'technowiz_admin_history_doc_id';
  static const String editQuestionIdKey = 'technowiz_admin_edit_question_id';
  static const String leaderboardQuizCodeKey = 'technowiz_admin_leaderboard_quiz_code';

  /// Saves the current Admin page and any optional contextual identifiers.
  static Future<void> savePage(
    String pageKey, {
    String? detailQuizCode,
    String? historyQuizCode,
    String? historyQuizTitle,
    String? historyQuizDate,
    String? historyDocId,
    String? editQuestionId,
    String? leaderboardQuizCode,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(lastPageKey, pageKey);

      if (detailQuizCode != null && detailQuizCode.isNotEmpty) {
        await prefs.setString(detailQuizCodeKey, detailQuizCode);
      }
      if (historyQuizCode != null && historyQuizCode.isNotEmpty) {
        await prefs.setString(historyQuizCodeKey, historyQuizCode);
      }
      if (historyQuizTitle != null) {
        await prefs.setString(historyQuizTitleKey, historyQuizTitle);
      }
      if (historyQuizDate != null) {
        await prefs.setString(historyQuizDateKey, historyQuizDate);
      }
      if (historyDocId != null && historyDocId.isNotEmpty) {
        await prefs.setString(historyDocIdKey, historyDocId);
      }
      if (editQuestionId != null && editQuestionId.isNotEmpty) {
        await prefs.setString(editQuestionIdKey, editQuestionId);
      }
      if (leaderboardQuizCode != null && leaderboardQuizCode.isNotEmpty) {
        await prefs.setString(leaderboardQuizCodeKey, leaderboardQuizCode);
      }
    } catch (_) {
      // SharedPreferences failures should not crash the UI
    }
  }

  /// Retrieves the last recorded Admin page key.
  static Future<String?> getPage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(lastPageKey);
    } catch (_) {
      return null;
    }
  }

  /// Completely clears all Admin navigation state (used during logout).
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(lastPageKey);
      await prefs.remove(detailQuizCodeKey);
      await prefs.remove(historyQuizCodeKey);
      await prefs.remove(historyQuizTitleKey);
      await prefs.remove(historyQuizDateKey);
      await prefs.remove(historyDocIdKey);
      await prefs.remove(editQuestionIdKey);
      await prefs.remove(leaderboardQuizCodeKey);
    } catch (_) {}
  }
}

/// Centralized navigation state persistence for all Competitor screens and tabs.
/// Ensures that when the browser is refreshed or reloaded, the exact Competitor
/// tab or sub-screen is restored seamlessly without jumping back to Dashboard.
class CompetitorNavPersistence {
  static const String lastPageKey = 'contestant_last_page';
  static const String quizCodeKey = 'contestant_current_quiz_code';
  static const String quizTitleKey = 'contestant_current_quiz_title';
  static const String quizLevelKey = 'contestant_current_quiz_level';
  static const String currentLeaderboardSessionKey =
      'contestant_current_leaderboard_session';

  /// Saves the current Competitor page and any optional quiz parameters.
  static Future<void> savePage(
    String pageKey, {
    String? quizCode,
    String? quizTitle,
    int? level,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(lastPageKey, pageKey);
      if (quizCode != null && quizCode.isNotEmpty) {
        await prefs.setString(quizCodeKey, quizCode);
      }
      if (quizTitle != null && quizTitle.isNotEmpty) {
        await prefs.setString(quizTitleKey, quizTitle);
      }
      if (level != null) {
        await prefs.setInt(quizLevelKey, level);
      }
    } catch (_) {}
  }

  /// Retrieves the last recorded Competitor page key.
  static Future<String?> getPage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return prefs.getString(lastPageKey);
    } catch (_) {
      return null;
    }
  }

  /// Completely clears all Competitor navigation state (used during logout).
  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(lastPageKey);
      await prefs.remove(quizCodeKey);
      await prefs.remove(quizTitleKey);
      await prefs.remove(quizLevelKey);
      await prefs.remove(currentLeaderboardSessionKey);
    } catch (_) {}
  }
}

/// Centralized navigation state persistence for all Quiz Master screens and tabs.
/// Ensures that when the browser is refreshed or reloaded, the exact Quiz Master
/// screen is restored seamlessly without jumping back to Dashboard or another quiz.
class QuizMasterNavPersistence {
  static const String lastPageKey = 'technowiz_quizmaster_last_page';
  static const String quizCodeKey = 'technowiz_quizmaster_current_quiz_code';
  static const String resultModeKey = 'technowiz_quizmaster_result_mode';
  static const String leaderboardLevelKey =
      'technowiz_quizmaster_leaderboard_level';
  static const String rankingLevelKey = 'technowiz_quizmaster_ranking_level';
  static const String rankingIsFinalKey =
      'technowiz_quizmaster_ranking_is_final';
  static const String readinessLevelKey =
      'technowiz_quizmaster_readiness_level';
  static const String submittedQuestionIndexKey =
      'technowiz_quizmaster_submitted_question_index';

  /// Saves the current Quiz Master page and any optional contextual identifiers.
  static Future<void> savePage(
    String pageKey, {
    String? quizCode,
    String? resultMode,
    String? leaderboardLevel,
    int? rankingLevel,
    bool? rankingIsFinal,
    int? readinessLevel,
    int? submittedQuestionIndex,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(lastPageKey, pageKey);

      if (quizCode != null && quizCode.trim().isNotEmpty) {
        await prefs.setString(quizCodeKey, quizCode.trim());
      } else if (pageKey == 'dashboard') {
        await prefs.remove(quizCodeKey);
      }

      if (resultMode != null) {
        await prefs.setString(resultModeKey, resultMode);
      } else {
        await prefs.remove(resultModeKey);
      }

      if (leaderboardLevel != null) {
        await prefs.setString(leaderboardLevelKey, leaderboardLevel);
      }
      if (rankingLevel != null) {
        await prefs.setInt(rankingLevelKey, rankingLevel);
      }
      if (rankingIsFinal != null) {
        await prefs.setBool(rankingIsFinalKey, rankingIsFinal);
      }
      if (readinessLevel != null) {
        await prefs.setInt(readinessLevelKey, readinessLevel);
      }
      if (submittedQuestionIndex != null) {
        await prefs.setInt(submittedQuestionIndexKey, submittedQuestionIndex);
      }
    } catch (_) {}
  }

  /// Retrieves the last recorded Quiz Master page key.
  static Future<String?> getPage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return prefs.getString(lastPageKey);
    } catch (_) {
      return null;
    }
  }

  /// Completely clears all Quiz Master navigation state (used during logout).
  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(lastPageKey);
      await prefs.remove(quizCodeKey);
      await prefs.remove(resultModeKey);
      await prefs.remove(leaderboardLevelKey);
      await prefs.remove(rankingLevelKey);
      await prefs.remove(rankingIsFinalKey);
      await prefs.remove(readinessLevelKey);
      await prefs.remove(submittedQuestionIndexKey);
    } catch (_) {}
  }
}


