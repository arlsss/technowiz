import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'admin_dashboard.dart';
import 'manage_users_screen.dart';
import 'add_question_screen.dart';
import 'question_list_screen.dart';
import 'manage_quiz_sessions_screen.dart';
import 'admin_leaderboard_screen.dart';
import 'admin_sidebar.dart';
import 'admin_theme.dart';
import '../login_screen.dart';
import '../../navigation_persistence.dart';

// ============================================================================
// TECHNOWIZ ADMIN REPORT & DOCUMENTATION CENTER
// ============================================================================
// Objective 4: To generate reliable reports such as participant records,
// score summaries, and final rankings for easier management and documentation.
// ============================================================================

class AdminReportScreen extends StatefulWidget {
  const AdminReportScreen({super.key});

  @override
  State<AdminReportScreen> createState() => _AdminReportScreenState();
}

class _AdminReportScreenState extends State<AdminReportScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String? selectedQuizCode;
  String _selectedReportTab = 'rankings'; // 'rankings', 'scores', 'participants'
  String _quizFilter = 'all'; // 'all', 'completed', 'ongoing'
  String _quizSearchQuery = '';
  String _participantSearchQuery = '';

  final TextEditingController _quizSearchController = TextEditingController();
  final TextEditingController _participantSearchController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    AdminNavPersistence.savePage('reports');
  }

  @override
  void dispose() {
    _quizSearchController.dispose();
    _participantSearchController.dispose();
    super.dispose();
  }

  // =========================================================
  // NAVIGATION & SIDEBAR
  // =========================================================

  Future<void> _navigateFromAdminSidebar(String destination) async {
    const pageKeys = <String, String>{
      'dashboard': 'dashboard',
      'manage_users': 'manage_users',
      'add_question': 'add_question',
      'question_list': 'question_list',
      'quiz_sessions': 'quiz_sessions',
      'leaderboard': 'leaderboard',
      'reports': 'reports',
    };

    final pageKey = pageKeys[destination];
    if (pageKey != null) {
      await AdminNavPersistence.savePage(pageKey);
    }

    if (!mounted || destination == 'reports') return;

    final Widget? page;
    switch (destination) {
      case 'dashboard':
        page = const AdminDashboard(restoreLastPage: false);
        break;
      case 'manage_users':
        page = const ManageUsersScreen();
        break;
      case 'add_question':
        page = const AddQuestionScreen();
        break;
      case 'question_list':
        page = const QuestionListScreen();
        break;
      case 'quiz_sessions':
        page = const ManageQuizSessionsScreen();
        break;
      case 'leaderboard':
        page = const AdminLeaderboardScreen();
        break;
      default:
        page = null;
    }

    if (page == null || !mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => page!,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  Widget _adminDrawer() {
    return AdminSidebar(
      currentPage: 'reports',
      onDestinationSelected: _navigateFromAdminSidebar,
      onProfileTap: () => _showProfileMenu(context),
    );
  }

  void _showProfileMenu(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0EBFF),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFD8CCF7), width: 2),
                ),
                child: const Icon(
                  Icons.admin_panel_settings_rounded,
                  color: AdminThemeColors.primary,
                  size: 36,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Admin',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AdminThemeColors.textPrimary,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                user?.email ?? 'No email available',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AdminThemeColors.textMuted,
                ),
              ),
              const SizedBox(height: 18),
              const Divider(color: AdminThemeColors.border),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(sheetContext);
                    try {
                      await AdminNavPersistence.clear();
                      await LoginScreen.clearSavedCredentials();
                      await FirebaseAuth.instance.signOut();
                      if (!context.mounted) return;
                      Navigator.of(context, rootNavigator: true)
                          .pushAndRemoveUntil<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => const LoginScreen(clearCredentials: true),
                        ),
                        (route) => false,
                      );
                    } catch (e) {
                      if (context.mounted) {
                        AdminNotification.error(
                          context,
                          'Unable to log out: $e',
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text(
                    'Logout',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF0E9FF),
                    foregroundColor: AdminThemeColors.primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================
  // CERTIFICATE PDF BUILDER (EXACT TEMPLATE DESIGNS)
  // =========================================================
  // Rank 1: 1ST PLACE (Gold Theme with Trophy & Laurels)
  // Rank 2: 2ND PLACE (Silver / Blue Theme with Trophy & Laurels)
  // Rank 3: 3RD PLACE (Bronze / Orange Theme with Trophy & Laurels)
  // Others: APPRECIATION (Emerald Green Theme with Star & Laurels)
  // =========================================================

  Future<void> _printCertificate({
    required String contestantName,
    required String quizTitle,
    required int rank,
    String teamName = '',
    String school = '',
    int totalScore = 0,
    int level1Score = 0,
    int level2Score = 0,
    int level3Score = 0,
    String quizCode = '',
    String quizDate = '',
    bool eliminated = false,
    int? eliminatedLevel,
    pw.Document? document,
    bool printAfter = true,
  }) async {
    final pdf = document ?? pw.Document();

    final String darkCorner;
    final String midCorner;
    final String lightCorner;
    final PdfColor borderColor;
    final String ribbonMain;
    final String ribbonStroke;
    final String ribbonTail;
    final String ribbonFold;
    final String ribbonTitle;
    final PdfColor ribbonTextColor;
    final double ribbonFontSize;
    final String citation1;
    final String citation2;
    final String centerGraphicSvg;

    if (rank == 1 && !eliminated) {
      // 1ST PLACE - GOLD EDITION
      darkCorner = '#1E293B';
      midCorner = '#D97706';
      lightCorner = '#FBBF24';
      borderColor = const PdfColor.fromInt(0xFFEAB308);
      ribbonMain = '#FBBF24';
      ribbonStroke = '#F59E0B';
      ribbonTail = '#D97706';
      ribbonFold = '#92400E';
      ribbonTitle = '1ST PLACE';
      ribbonTextColor = const PdfColor.fromInt(0xFF1E293B);
      ribbonFontSize = 24;
      citation1 = 'for outstanding performance in the TechNoWiz Quiz Competition.';
      citation2 = 'Keep up the great work!';
      centerGraphicSvg = '''<svg viewBox="0 0 180 65" width="180" height="65">
  <path d="M 54,55 C 42,44 42,22 54,6" stroke="#D97706" stroke-width="2.5" fill="none" stroke-linecap="round" />
  <polygon points="46,46 36,44 42,52" fill="#D97706" />
  <polygon points="40,34 30,32 36,40" fill="#D97706" />
  <polygon points="40,22 30,22 36,28" fill="#D97706" />
  <polygon points="46,12 38,14 42,20" fill="#D97706" />
  <polygon points="54,6 48,10 54,14" fill="#D97706" />
  <polygon points="48,42 56,40 50,48" fill="#D97706" />
  <polygon points="44,30 52,28 46,36" fill="#D97706" />
  <polygon points="44,18 52,18 46,24" fill="#D97706" />
  <path d="M 126,55 C 138,44 138,22 126,6" stroke="#D97706" stroke-width="2.5" fill="none" stroke-linecap="round" />
  <polygon points="134,46 144,44 138,52" fill="#D97706" />
  <polygon points="140,34 150,32 144,40" fill="#D97706" />
  <polygon points="140,22 150,22 144,28" fill="#D97706" />
  <polygon points="134,12 142,14 138,20" fill="#D97706" />
  <polygon points="126,6 132,10 126,14" fill="#D97706" />
  <polygon points="132,42 124,40 130,48" fill="#D97706" />
  <polygon points="136,30 128,28 134,36" fill="#D97706" />
  <polygon points="136,18 128,18 134,24" fill="#D97706" />
  <!-- Trophy Cup Body -->
  <path d="M 68,8 C 68,40 112,40 112,8 Z" fill="#F59E0B" />
  <!-- Rounded Top Rim -->
  <rect x="64" y="6" width="52" height="6" rx="3" fill="#FDE047" stroke="#D97706" stroke-width="1" />
  <!-- Ear Handles -->
  <path d="M 68,14 C 48,14 48,34 68,36" stroke="#D97706" stroke-width="4.5" fill="none" stroke-linecap="round" />
  <path d="M 68,14 C 48,14 48,34 68,36" stroke="#FDE047" stroke-width="2" fill="none" stroke-linecap="round" />
  <path d="M 112,14 C 132,14 132,34 112,36" stroke="#D97706" stroke-width="4.5" fill="none" stroke-linecap="round" />
  <path d="M 112,14 C 132,14 132,34 112,36" stroke="#FDE047" stroke-width="2" fill="none" stroke-linecap="round" />
  <!-- Crown on Cup (NO number 6) -->
  <path d="M 78,18 L 81,31 L 99,31 L 102,18 L 96,23 L 90,15 L 84,23 Z" fill="#FFFBEB" stroke="#FDE047" stroke-width="0.8" />
  <circle cx="78" cy="18" r="2.2" fill="#FFFBEB" />
  <circle cx="90" cy="15" r="2.5" fill="#FFFBEB" />
  <circle cx="102" cy="18" r="2.2" fill="#FFFBEB" />
  <!-- Pedestal Stem & Stepped Base -->
  <rect x="86" y="38" width="8" height="12" fill="#B45309" />
  <rect x="76" y="50" width="28" height="5" rx="2" fill="#F59E0B" />
  <rect x="72" y="55" width="36" height="5" rx="2.5" fill="#B45309" stroke="#D97706" stroke-width="0.8" />
</svg>''';
    } else if (rank == 2 && !eliminated) {
      // 2ND PLACE - SILVER / BLUE EDITION
      darkCorner = '#0F172A';
      midCorner = '#1D4ED8';
      lightCorner = '#38BDF8';
      borderColor = const PdfColor.fromInt(0xFF0284C7);
      ribbonMain = '#CBD5E1';
      ribbonStroke = '#94A3B8';
      ribbonTail = '#94A3B8';
      ribbonFold = '#475569';
      ribbonTitle = '2ND PLACE';
      ribbonTextColor = const PdfColor.fromInt(0xFF0F172A);
      ribbonFontSize = 24;
      citation1 = 'for outstanding performance in the TechNoWiz Quiz Competition.';
      citation2 = 'Keep up the great work!';
      centerGraphicSvg = '''<svg viewBox="0 0 180 65" width="180" height="65">
  <path d="M 54,55 C 42,44 42,22 54,6" stroke="#94A3B8" stroke-width="2.5" fill="none" stroke-linecap="round" />
  <polygon points="46,46 36,44 42,52" fill="#94A3B8" />
  <polygon points="40,34 30,32 36,40" fill="#94A3B8" />
  <polygon points="40,22 30,22 36,28" fill="#94A3B8" />
  <polygon points="46,12 38,14 42,20" fill="#94A3B8" />
  <polygon points="54,6 48,10 54,14" fill="#94A3B8" />
  <polygon points="48,42 56,40 50,48" fill="#94A3B8" />
  <polygon points="44,30 52,28 46,36" fill="#94A3B8" />
  <polygon points="44,18 52,18 46,24" fill="#94A3B8" />
  <path d="M 126,55 C 138,44 138,22 126,6" stroke="#94A3B8" stroke-width="2.5" fill="none" stroke-linecap="round" />
  <polygon points="134,46 144,44 138,52" fill="#94A3B8" />
  <polygon points="140,34 150,32 144,40" fill="#94A3B8" />
  <polygon points="140,22 150,22 144,28" fill="#94A3B8" />
  <polygon points="134,12 142,14 138,20" fill="#94A3B8" />
  <polygon points="126,6 132,10 126,14" fill="#94A3B8" />
  <polygon points="132,42 124,40 130,48" fill="#94A3B8" />
  <polygon points="136,30 128,28 134,36" fill="#94A3B8" />
  <polygon points="136,18 128,18 134,24" fill="#94A3B8" />
  <!-- Trophy Cup Body -->
  <path d="M 68,8 C 68,40 112,40 112,8 Z" fill="#94A3B8" />
  <!-- Rounded Top Rim -->
  <rect x="64" y="6" width="52" height="6" rx="3" fill="#E2E8F0" stroke="#64748B" stroke-width="1" />
  <!-- Ear Handles -->
  <path d="M 68,14 C 48,14 48,34 68,36" stroke="#64748B" stroke-width="4.5" fill="none" stroke-linecap="round" />
  <path d="M 68,14 C 48,14 48,34 68,36" stroke="#E2E8F0" stroke-width="2" fill="none" stroke-linecap="round" />
  <path d="M 112,14 C 132,14 132,34 112,36" stroke="#64748B" stroke-width="4.5" fill="none" stroke-linecap="round" />
  <path d="M 112,14 C 132,14 132,34 112,36" stroke="#E2E8F0" stroke-width="2" fill="none" stroke-linecap="round" />
  <!-- Crown on Cup (NO number 6) -->
  <path d="M 78,18 L 81,31 L 99,31 L 102,18 L 96,23 L 90,15 L 84,23 Z" fill="#F8FAFC" stroke="#CBD5E1" stroke-width="0.8" />
  <circle cx="78" cy="18" r="2.2" fill="#F8FAFC" />
  <circle cx="90" cy="15" r="2.5" fill="#F8FAFC" />
  <circle cx="102" cy="18" r="2.2" fill="#F8FAFC" />
  <!-- Pedestal Stem & Stepped Base -->
  <rect x="86" y="38" width="8" height="12" fill="#475569" />
  <rect x="76" y="50" width="28" height="5" rx="2" fill="#94A3B8" />
  <rect x="72" y="55" width="36" height="5" rx="2.5" fill="#475569" stroke="#64748B" stroke-width="0.8" />
</svg>''';
    } else if (rank == 3 && !eliminated) {
      // 3RD PLACE - BRONZE / ORANGE EDITION
      darkCorner = '#1E293B';
      midCorner = '#C2410C';
      lightCorner = '#FB923C';
      borderColor = const PdfColor.fromInt(0xFFEA580C);
      ribbonMain = '#FB923C';
      ribbonStroke = '#EA580C';
      ribbonTail = '#EA580C';
      ribbonFold = '#7C2D12';
      ribbonTitle = '3RD PLACE';
      ribbonTextColor = const PdfColor.fromInt(0xFF1E293B);
      ribbonFontSize = 24;
      citation1 = 'for outstanding performance in the TechNoWiz Quiz Competition.';
      citation2 = 'Keep up the great work!';
      centerGraphicSvg = '''<svg viewBox="0 0 180 65" width="180" height="65">
  <path d="M 54,55 C 42,44 42,22 54,6" stroke="#C2410C" stroke-width="2.5" fill="none" stroke-linecap="round" />
  <polygon points="46,46 36,44 42,52" fill="#C2410C" />
  <polygon points="40,34 30,32 36,40" fill="#C2410C" />
  <polygon points="40,22 30,22 36,28" fill="#C2410C" />
  <polygon points="46,12 38,14 42,20" fill="#C2410C" />
  <polygon points="54,6 48,10 54,14" fill="#C2410C" />
  <polygon points="48,42 56,40 50,48" fill="#C2410C" />
  <polygon points="44,30 52,28 46,36" fill="#C2410C" />
  <polygon points="44,18 52,18 46,24" fill="#C2410C" />
  <path d="M 126,55 C 138,44 138,22 126,6" stroke="#C2410C" stroke-width="2.5" fill="none" stroke-linecap="round" />
  <polygon points="134,46 144,44 138,52" fill="#C2410C" />
  <polygon points="140,34 150,32 144,40" fill="#C2410C" />
  <polygon points="140,22 150,22 144,28" fill="#C2410C" />
  <polygon points="134,12 142,14 138,20" fill="#C2410C" />
  <polygon points="126,6 132,10 126,14" fill="#C2410C" />
  <polygon points="132,42 124,40 130,48" fill="#C2410C" />
  <polygon points="136,30 128,28 134,36" fill="#C2410C" />
  <polygon points="136,18 128,18 134,24" fill="#C2410C" />
  <!-- Trophy Cup Body -->
  <path d="M 68,8 C 68,40 112,40 112,8 Z" fill="#EA580C" />
  <!-- Rounded Top Rim -->
  <rect x="64" y="6" width="52" height="6" rx="3" fill="#FED7AA" stroke="#C2410C" stroke-width="1" />
  <!-- Ear Handles -->
  <path d="M 68,14 C 48,14 48,34 68,36" stroke="#C2410C" stroke-width="4.5" fill="none" stroke-linecap="round" />
  <path d="M 68,14 C 48,14 48,34 68,36" stroke="#FED7AA" stroke-width="2" fill="none" stroke-linecap="round" />
  <path d="M 112,14 C 132,14 132,34 112,36" stroke="#C2410C" stroke-width="4.5" fill="none" stroke-linecap="round" />
  <path d="M 112,14 C 132,14 132,34 112,36" stroke="#FED7AA" stroke-width="2" fill="none" stroke-linecap="round" />
  <!-- Crown on Cup (NO number 6) -->
  <path d="M 78,18 L 81,31 L 99,31 L 102,18 L 96,23 L 90,15 L 84,23 Z" fill="#FFF7ED" stroke="#FDBA74" stroke-width="0.8" />
  <circle cx="78" cy="18" r="2.2" fill="#FFF7ED" />
  <circle cx="90" cy="15" r="2.5" fill="#FFF7ED" />
  <circle cx="102" cy="18" r="2.2" fill="#FFF7ED" />
  <!-- Pedestal Stem & Stepped Base -->
  <rect x="86" y="38" width="8" height="12" fill="#9A3412" />
  <rect x="76" y="50" width="28" height="5" rx="2" fill="#EA580C" />
  <rect x="72" y="55" width="36" height="5" rx="2.5" fill="#9A3412" stroke="#C2410C" stroke-width="0.8" />
</svg>''';
    } else {
      // APPRECIATION - GREEN EDITION (Finalists & Participants)
      darkCorner = '#14532D';
      midCorner = '#16A34A';
      lightCorner = '#4ADE80';
      borderColor = const PdfColor.fromInt(0xFF16A34A);
      ribbonMain = '#16A34A';
      ribbonStroke = '#15803D';
      ribbonTail = '#15803D';
      ribbonFold = '#14532D';
      ribbonTitle = 'APPRECIATION';
      ribbonTextColor = const PdfColor.fromInt(0xFFFFFFFF);
      ribbonFontSize = 21;
      citation1 = 'for your participation and support in the TechNoWiz Quiz Competition.';
      citation2 = 'Thank you for being a part of TechNoWiz!';
      centerGraphicSvg = '''<svg viewBox="0 0 180 65" width="180" height="65">
  <path d="M 54,55 C 42,44 42,22 54,6" stroke="#16A34A" stroke-width="2.5" fill="none" stroke-linecap="round" />
  <polygon points="46,46 36,44 42,52" fill="#16A34A" />
  <polygon points="40,34 30,32 36,40" fill="#16A34A" />
  <polygon points="40,22 30,22 36,28" fill="#16A34A" />
  <polygon points="46,12 38,14 42,20" fill="#16A34A" />
  <polygon points="54,6 48,10 54,14" fill="#16A34A" />
  <polygon points="48,42 56,40 50,48" fill="#16A34A" />
  <polygon points="44,30 52,28 46,36" fill="#16A34A" />
  <polygon points="44,18 52,18 46,24" fill="#16A34A" />
  <path d="M 126,55 C 138,44 138,22 126,6" stroke="#16A34A" stroke-width="2.5" fill="none" stroke-linecap="round" />
  <polygon points="134,46 144,44 138,52" fill="#16A34A" />
  <polygon points="140,34 150,32 144,40" fill="#16A34A" />
  <polygon points="140,22 150,22 144,28" fill="#16A34A" />
  <polygon points="134,12 142,14 138,20" fill="#16A34A" />
  <polygon points="126,6 132,10 126,14" fill="#16A34A" />
  <polygon points="132,42 124,40 130,48" fill="#16A34A" />
  <polygon points="136,30 128,28 134,36" fill="#16A34A" />
  <polygon points="136,18 128,18 134,24" fill="#16A34A" />
  <polygon points="90,8 96,24 113,24 99,35 104,51 90,40 76,51 81,35 67,24 84,24" fill="#F59E0B" />
</svg>''';
    }

    final cornerTopLeftSvg = '''<svg viewBox="0 0 140 140" width="140" height="140">
  <polygon points="0,0 35,0 0,35" fill="$darkCorner" />
  <polygon points="15,0 80,0 0,80 0,15" fill="$midCorner" />
  <polygon points="60,0 135,0 0,135 0,60" fill="$lightCorner" />
</svg>''';

    final cornerBottomRightSvg = '''<svg viewBox="0 0 140 140" width="140" height="140">
  <polygon points="140,140 105,140 140,105" fill="$darkCorner" />
  <polygon points="125,140 60,140 140,60 140,125" fill="$midCorner" />
  <polygon points="80,140 5,140 140,5 140,80" fill="$lightCorner" />
</svg>''';

    final ribbonSvg = '''<svg viewBox="0 0 440 52" width="440" height="52">
  <polygon points="45,42 45,50 58,42" fill="$ribbonFold" />
  <polygon points="12,12 45,8 45,42 22,46 34,27" fill="$ribbonTail" />
  <polygon points="395,42 395,50 382,42" fill="$ribbonFold" />
  <polygon points="428,12 395,8 395,42 418,46 406,27" fill="$ribbonTail" />
  <rect x="45" y="4" width="350" height="38" rx="3" fill="$ribbonMain" stroke="$ribbonStroke" stroke-width="1.5" />
</svg>''';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(16),
        build: (context) {
          return pw.Container(
            width: double.infinity,
            height: double.infinity,
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              border: pw.Border.all(color: borderColor, width: 2),
            ),
            child: pw.Stack(
              children: [
                // Top-Left Corner Geometric Stripes
                pw.Positioned(
                  top: 0,
                  left: 0,
                  child: pw.SvgImage(svg: cornerTopLeftSvg, width: 130, height: 130),
                ),

                // Bottom-Right Corner Geometric Stripes
                pw.Positioned(
                  bottom: 0,
                  right: 0,
                  child: pw.SvgImage(svg: cornerBottomRightSvg, width: 130, height: 130),
                ),

                // Center Content Body
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 22, horizontal: 30),
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      // Header: TechNoWiz QUIZ COMPETITION
                      pw.Column(
                        children: [
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.center,
                            children: [
                              pw.Text(
                                'TechNo',
                                style: pw.TextStyle(
                                  fontSize: 27,
                                  fontWeight: pw.FontWeight.bold,
                                  color: const PdfColor.fromInt(0xFF0F172A),
                                ),
                              ),
                              pw.Text(
                                'Wiz',
                                style: pw.TextStyle(
                                  fontSize: 27,
                                  fontWeight: pw.FontWeight.bold,
                                  color: const PdfColor.fromInt(0xFF0284C7),
                                ),
                              ),
                            ],
                          ),
                          pw.SizedBox(height: 2),
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.center,
                            children: [
                              pw.Container(width: 44, height: 1.2, color: const PdfColor.fromInt(0xFF0F172A)),
                              pw.Padding(
                                padding: const pw.EdgeInsets.symmetric(horizontal: 10),
                                child: pw.Text(
                                  'QUIZ COMPETITION',
                                  style: pw.TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: pw.FontWeight.bold,
                                    letterSpacing: 2,
                                    color: const PdfColor.fromInt(0xFF0F172A),
                                  ),
                                ),
                              ),
                              pw.Container(width: 44, height: 1.2, color: const PdfColor.fromInt(0xFF0F172A)),
                            ],
                          ),
                        ],
                      ),

                      // Center Graphic: Trophy & Laurels or Star & Laurels
                      pw.SvgImage(
                        svg: centerGraphicSvg,
                        width: 170,
                        height: 56,
                      ),

                      // 3D Ribbon Banner with Title
                      pw.Container(
                        width: 440,
                        height: 50,
                        child: pw.Stack(
                          alignment: pw.Alignment.center,
                          children: [
                            pw.SvgImage(svg: ribbonSvg, width: 440, height: 50),
                            pw.Positioned(
                              top: 7,
                              child: pw.Text(
                                ribbonTitle,
                                style: pw.TextStyle(
                                  fontSize: ribbonFontSize,
                                  fontWeight: pw.FontWeight.bold,
                                  color: ribbonTextColor,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Certificate Subtitles
                      pw.Column(
                        children: [
                          pw.Text(
                            'CERTIFICATE OF ACHIEVEMENT',
                            style: pw.TextStyle(
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                              color: const PdfColor.fromInt(0xFF0F172A),
                              letterSpacing: 2,
                            ),
                          ),
                          pw.SizedBox(height: 5),
                          pw.Text(
                            'This certificate is proudly awarded to',
                            style: const pw.TextStyle(
                              fontSize: 11.5,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColor.fromInt(0xFF334155),
                            ),
                          ),
                        ],
                      ),

                      // Contestant Name & Underline
                      pw.Column(
                        children: [
                          pw.Text(
                            contestantName.toUpperCase(),
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(
                              fontSize: 25,
                              fontWeight: pw.FontWeight.bold,
                              color: const PdfColor.fromInt(0xFF0F172A),
                              letterSpacing: 1.2,
                            ),
                          ),
                          pw.SizedBox(height: 5),
                          pw.Container(
                            width: 440,
                            height: 1.5,
                            color: const PdfColor.fromInt(0xFF0F172A),
                          ),
                        ],
                      ),

                      // Citations
                      pw.Column(
                        children: [
                          pw.Text(
                            citation1,
                            textAlign: pw.TextAlign.center,
                            style: const pw.TextStyle(
                              fontSize: 10.5,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColor.fromInt(0xFF1E293B),
                            ),
                          ),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            citation2,
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(
                              fontSize: 10.5,
                              fontWeight: pw.FontWeight.bold,
                              fontStyle: pw.FontStyle.italic,
                              color: const PdfColor.fromInt(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),

                      // Signatures: Event Organizer & TechNoWiz Host
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 40),
                        child: pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Column(
                              children: [
                                pw.Container(width: 170, height: 1.5, color: const PdfColor.fromInt(0xFF0F172A)),
                                pw.SizedBox(height: 4),
                                pw.Text(
                                  'Event Organizer',
                                  style: pw.TextStyle(
                                    fontSize: 10,
                                    fontWeight: pw.FontWeight.bold,
                                    color: const PdfColor.fromInt(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                            pw.Column(
                              children: [
                                pw.Container(width: 170, height: 1.5, color: const PdfColor.fromInt(0xFF0F172A)),
                                pw.SizedBox(height: 4),
                                pw.Text(
                                  'TechNoWiz Host',
                                  style: pw.TextStyle(
                                    fontSize: 10,
                                    fontWeight: pw.FontWeight.bold,
                                    color: const PdfColor.fromInt(0xFF0F172A),
                                  ),
                                ),
                              ],
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
        },
      ),
    );

    if (printAfter) {
      final safeName = contestantName.replaceAll(' ', '_').replaceAll(RegExp(r'[^\w\.-]'), '');
      await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
        name: 'TechNoWiz_Certificate_Rank${rank}_$safeName.pdf',
      );
    }
  }

  Future<void> _printAllTopThreeCertificates({
    required List<ReportContestant> contestants,
    required String quizTitle,
  }) async {
    if (contestants.isEmpty) return;
    final pdf = pw.Document();

    final topContestants = contestants.take(3).toList();
    for (var index = 0; index < topContestants.length; index++) {
      final c = topContestants[index];
      await _printCertificate(
        contestantName: c.name,
        quizTitle: quizTitle,
        rank: index + 1,
        teamName: c.teamName,
        school: c.school,
        totalScore: c.totalScore,
        level1Score: c.level1Score,
        level2Score: c.level2Score,
        level3Score: c.level3Score,
        quizCode: selectedQuizCode ?? '',
        quizDate: _dateText(),
        eliminated: c.isEliminated,
        document: pdf,
        printAfter: false,
      );
    }

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'TechNoWiz_Top_3_Official_Certificates.pdf',
    );
  }


  // =========================================================
  // OFFICIAL REPORT GENERATOR (PDF DOCUMENTATION EXPORT)
  // =========================================================
  // Fulfills Objective 4: Comprehensive documentation including
  // participant records, score summaries, and final rankings.
  // =========================================================

  Future<void> _generateOfficialReportPdf({
    required String quizTitle,
    required String quizCode,
    required String quizStatus,
    required String quizDate,
    required String location,
    required List<ReportContestant> rankings,
    required List<ReportContestant> participants,
  }) async {
    final pdf = pw.Document();

    // Summary calculations
    final totalParticipants = participants.length;
    final totalFinished = rankings.where((c) => !c.isEliminated).length;
    final totalEliminated = participants.where((c) => c.isEliminated).length;
    final topScore = rankings.isNotEmpty ? rankings.first.totalScore : 0;
    final averageScore = rankings.isNotEmpty
        ? (rankings.map((c) => c.totalScore).reduce((a, b) => a + b) /
                rankings.length)
            .toStringAsFixed(1)
        : '0.0';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 16),
            padding: const pw.EdgeInsets.only(bottom: 10),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.deepPurple700, width: 2),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'TECHNOWIZ COMPETITION SYSTEM',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.deepPurple800,
                        letterSpacing: 1,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Official Session Report & Documentation',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Generated: ${_dateText()}',
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.Text(
                      'Quiz Code: $quizCode',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.deepPurple800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
        footer: (context) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(top: 14),
            padding: const pw.EdgeInsets.only(top: 8),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(color: PdfColors.grey300, width: 1),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'TechNoWiz - System Generated Official Document',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                ),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                ),
              ],
            ),
          );
        },
        build: (context) => [
          // Section 1: Event Information & Summary Box
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: PdfColors.grey300),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  quizTitle,
                  style: pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        'Date: ${quizDate.isNotEmpty ? quizDate : _dateText()}',
                        style: const pw.TextStyle(fontSize: 9.5),
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Text(
                        'Location: ${location.isNotEmpty ? location : "Main Hall"}',
                        style: const pw.TextStyle(fontSize: 9.5),
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Text(
                        'Status: ${quizStatus.toUpperCase()}',
                        style: pw.TextStyle(
                          fontSize: 9.5,
                          fontWeight: pw.FontWeight.bold,
                          color: quizStatus.toLowerCase().contains('finish')
                              ? PdfColors.green800
                              : PdfColors.deepPurple700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),

          // Section 2: Score Summary KPI Table
          pw.Text(
            '1. SCORE SUMMARY & STATISTICS',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.deepPurple800,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Table.fromTextArray(
            headers: [
              'Total Contestants',
              'Active / Completed',
              'Eliminated',
              'Top Score',
              'Average Score',
            ],
            data: [
              [
                '$totalParticipants',
                '$totalFinished',
                '$totalEliminated',
                '$topScore pts',
                '$averageScore pts',
              ]
            ],
            headerStyle: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.deepPurple700,
            ),
            cellAlignment: pw.Alignment.center,
            cellStyle: pw.TextStyle(
              fontSize: 9.5,
              fontWeight: pw.FontWeight.bold,
            ),
            cellPadding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          ),
          pw.SizedBox(height: 18),

          // Section 3: Final Rankings Table
          pw.Text(
            '2. FINAL STANDINGS & RANKINGS',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.deepPurple800,
            ),
          ),
          pw.SizedBox(height: 6),
          if (rankings.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.all(12),
              child: pw.Text(
                'No recorded standings for this quiz session.',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
              ),
            )
          else
            pw.Table.fromTextArray(
              headers: [
                'Rank',
                'Contestant Name',
                'Team / School',
                'Level 1',
                'Level 2',
                'Level 3',
                'Total Score',
                'Award / Status',
              ],
              data: rankings.asMap().entries.map((entry) {
                final rank = entry.key + 1;
                final c = entry.value;
                final schoolText = c.teamName.isNotEmpty
                    ? (c.school.isNotEmpty ? '${c.teamName} (${c.school})' : c.teamName)
                    : c.school;
                final award = c.isEliminated
                    ? 'Eliminated'
                    : (rank == 1
                        ? 'Champion'
                        : (rank == 2
                            ? '1st Runner-Up'
                            : (rank == 3
                                ? '2nd Runner-Up'
                                : 'Finalist')));

                return [
                  '$rank',
                  c.name,
                  schoolText.isNotEmpty ? schoolText : '-',
                  '${c.level1Score}',
                  '${c.level2Score}',
                  '${c.level3Score}',
                  '${c.totalScore} pts',
                  award,
                ];
              }).toList(),
              headerStyle: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.deepPurple700,
              ),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignment: pw.Alignment.centerLeft,
              headerAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
            ),
          pw.SizedBox(height: 18),

          // Section 4: Participant Records Directory
          pw.Text(
            '3. PARTICIPANT RECORDS DIRECTORY',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.deepPurple800,
            ),
          ),
          pw.SizedBox(height: 6),
          if (participants.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.all(12),
              child: pw.Text(
                'No participant records found for this quiz.',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
              ),
            )
          else
            pw.Table.fromTextArray(
              headers: ['#', 'Contestant Name', 'Team Name', 'School Name', 'Status'],
              data: participants.asMap().entries.map((entry) {
                final p = entry.value;
                return [
                  '${entry.key + 1}',
                  p.name,
                  p.teamName.isNotEmpty ? p.teamName : '-',
                  p.school.isNotEmpty ? p.school : '-',
                  p.isEliminated ? 'ELIMINATED' : p.status.toUpperCase(),
                ];
              }).toList(),
              headerStyle: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey800,
              ),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellPadding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
            ),
          pw.SizedBox(height: 30),

          // Section 5: Official Signatures
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(width: 170, height: 1, color: PdfColors.black),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Prepared By: Administrator',
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text('TechNoWiz Admin', style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(width: 170, height: 1, color: PdfColors.black),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Verified By: Quiz Master',
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'Event Head / Coordinator',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'TechNoWiz_Official_Report_${quizCode}.pdf',
    );
  }

  // =========================================================
  // UTILITY HELPERS
  // =========================================================

  String _dateText() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/'
        '${now.year}';
  }

  String _formatDateValue(dynamic val) {
    if (val == null) return _dateText();
    if (val is Timestamp) {
      final dt = val.toDate();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    }
    if (val is DateTime) {
      return '${val.day.toString().padLeft(2, '0')}/${val.month.toString().padLeft(2, '0')}/${val.year}';
    }
    final s = val.toString().trim();
    if (s.isEmpty) return _dateText();
    if (s.startsWith('Timestamp(')) {
      final match = RegExp(r'seconds=(\d+)').firstMatch(s);
      if (match != null) {
        final secs = int.tryParse(match.group(1) ?? '');
        if (secs != null) {
          final dt = DateTime.fromMillisecondsSinceEpoch(secs * 1000);
          return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
        }
      }
    }
    return s;
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  // =========================================================
  // DATA PARSER FOR PARTICIPANTS, SCORES & RANKINGS
  // =========================================================

  List<ReportContestant> _computeContestants({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> requestDocs,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> scoreDocs,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> participantDocs,
  }) {
    final Map<String, ReportContestant> map = {};

    // 1. Join Requests
    for (final doc in requestDocs) {
      final d = doc.data();
      final status = (d['status'] ?? '').toString().toLowerCase();
      if (status == 'rejected' || status == 'denied') continue;

      final name = (d['displayName'] ?? d['name'] ?? d['fullName'] ?? 'Contestant')
          .toString()
          .trim();
      final team = (d['teamName'] ?? '').toString().trim();
      final school = (d['school'] ?? d['schoolName'] ?? '').toString().trim();
      final isElim = status == 'eliminated' || d['isEliminated'] == true;

      DateTime? regTime;
      if (d['createdAt'] is Timestamp) {
        regTime = (d['createdAt'] as Timestamp).toDate();
      }

      map[doc.id] = ReportContestant(
        id: doc.id,
        name: name.isEmpty ? 'Contestant' : name,
        teamName: team,
        school: school,
        totalScore: 0,
        isEliminated: isElim,
        status: status.isEmpty ? 'joined' : status,
        registeredAt: regTime,
      );
    }

    // 2. Participants
    for (final doc in participantDocs) {
      final d = doc.data();
      final name = (d['displayName'] ?? d['name'] ?? d['fullName'] ?? '')
          .toString()
          .trim();
      final team = (d['teamName'] ?? '').toString().trim();
      final school = (d['school'] ?? d['schoolName'] ?? '').toString().trim();
      final isElim = (d['status'] ?? '').toString().toLowerCase() == 'eliminated' ||
          d['isEliminated'] == true;

      final existing = map[doc.id];
      map[doc.id] = ReportContestant(
        id: doc.id,
        name: name.isNotEmpty ? name : (existing?.name ?? 'Contestant'),
        teamName: team.isNotEmpty ? team : (existing?.teamName ?? ''),
        school: school.isNotEmpty ? school : (existing?.school ?? ''),
        totalScore: existing?.totalScore ?? 0,
        isEliminated: isElim || (existing?.isEliminated ?? false),
        status: (d['status'] ?? existing?.status ?? 'active').toString(),
        registeredAt: existing?.registeredAt,
      );
    }

    // 3. Scores
    for (final doc in scoreDocs) {
      final d = doc.data();
      final uid = (d['uid'] ?? doc.id).toString();
      final name = (d['displayName'] ?? d['name'] ?? d['fullName'] ?? '')
          .toString()
          .trim();
      final team = (d['teamName'] ?? '').toString().trim();
      final school = (d['school'] ?? d['schoolName'] ?? '').toString().trim();
      final isElim = (d['status'] ?? '').toString().toLowerCase() == 'eliminated' ||
          d['isEliminated'] == true ||
          d['eliminated'] == true;

      final total = _toInt(d['score'] ?? d['totalScore'] ?? d['points'] ?? 0);
      final l1 = _toInt(d['level1Score'] ?? d['level_1'] ?? (d['levelScores'] is Map ? d['levelScores']['Level 1'] : 0));
      final l2 = _toInt(d['level2Score'] ?? d['level_2'] ?? (d['levelScores'] is Map ? d['levelScores']['Level 2'] : 0));
      final l3 = _toInt(d['level3Score'] ?? d['level_3'] ?? (d['levelScores'] is Map ? d['levelScores']['Level 3'] : 0));

      int finalTotal = total;
      if (finalTotal == 0 && (l1 > 0 || l2 > 0 || l3 > 0)) {
        finalTotal = l1 + l2 + l3;
      }

      int timeMs = 0;
      final rawTime = d['lastSubmissionTime'] ?? d['updatedAt'] ?? d['answeredAt'];
      if (rawTime is Timestamp) timeMs = rawTime.millisecondsSinceEpoch;

      final existing = map[uid];
      map[uid] = ReportContestant(
        id: uid,
        name: name.isNotEmpty ? name : (existing?.name ?? 'Contestant'),
        teamName: team.isNotEmpty ? team : (existing?.teamName ?? ''),
        school: school.isNotEmpty ? school : (existing?.school ?? ''),
        totalScore: finalTotal,
        level1Score: l1,
        level2Score: l2,
        level3Score: l3,
        isEliminated: isElim || (existing?.isEliminated ?? false),
        eliminatedLevel: d['eliminatedLevel'] != null ? _toInt(d['eliminatedLevel']) : null,
        status: (d['status'] ?? existing?.status ?? 'active').toString(),
        submissionTimeMs: timeMs,
        registeredAt: existing?.registeredAt,
      );
    }

    final list = map.values.toList();
    // Accurate Sorting:
    // 1. Highest total score first
    // 2. Earliest submission time (speed tiebreaker)
    // 3. Alphabetical name
    list.sort((a, b) {
      if (a.isEliminated != b.isEliminated) {
        return a.isEliminated ? 1 : -1;
      }
      final s = b.totalScore.compareTo(a.totalScore);
      if (s != 0) return s;
      if (a.submissionTimeMs > 0 && b.submissionTimeMs > 0) {
        final t = a.submissionTimeMs.compareTo(b.submissionTimeMs);
        if (t != 0) return t;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return list;
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AdminThemeColors.background,
      drawer: _adminDrawer(),
      endDrawer: _adminDrawer(),

      // Unified Admin AppBar
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        toolbarHeight: 62,
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    AdminThemeColors.primary,
                    AdminThemeColors.primaryDark,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(11),
                boxShadow: [
                  BoxShadow(
                    color: AdminThemeColors.primary.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.admin_panel_settings_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'TechNoWiz',
                          style: TextStyle(
                            color: AdminThemeColors.primaryDark,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AdminThemeColors.pillBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AdminThemeColors.primary
                                  .withValues(alpha: 0.22),
                              width: 1,
                            ),
                          ),
                          child: const Text(
                            'Reports & Analytics',
                            style: TextStyle(
                              color: AdminThemeColors.primary,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Participant records, score summaries & final rankings.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AdminThemeColors.textMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Builder(
                builder: (drawerContext) => IconButton(
                  icon: const Icon(
                    Icons.menu_rounded,
                    color: AdminThemeColors.textPrimary,
                    size: 24,
                  ),
                  tooltip: 'Open navigation menu',
                  padding: EdgeInsets.zero,
                  onPressed: () => Scaffold.of(drawerContext).openEndDrawer(),
                ),
              ),
            ),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: AdminThemeColors.border,
          ),
        ),
      ),

      body: SafeArea(
        child: AdminCircuitBackground(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('quiz_sessions')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, sessionSnap) {
              if (sessionSnap.connectionState == ConnectionState.waiting &&
                  !sessionSnap.hasData) {
                return const Center(
                  child: CircularProgressIndicator(
                    color: AdminThemeColors.primary,
                  ),
                );
              }

              if (sessionSnap.hasError) {
                return Center(
                  child: Text('Error loading quiz sessions: ${sessionSnap.error}'),
                );
              }

              final allQuizzes = sessionSnap.data?.docs ?? [];

              // Filter quizzes
              final filteredQuizzes = allQuizzes.where((doc) {
                final d = doc.data();
                final title = (d['title'] ?? d['quizName'] ?? '').toString().toLowerCase();
                final code = (d['quizCode'] ?? doc.id).toString().toLowerCase();
                final status = (d['status'] ?? '').toString().toLowerCase();
                final isCompleted = status == 'finished' || status == 'completed';

                if (_quizFilter == 'completed' && !isCompleted) return false;
                if (_quizFilter == 'ongoing' && isCompleted) return false;

                if (_quizSearchQuery.isNotEmpty) {
                  final q = _quizSearchQuery.toLowerCase();
                  if (!title.contains(q) && !code.contains(q)) return false;
                }
                return true;
              }).toList();

              // If a quiz is selected, verify it exists
              QueryDocumentSnapshot<Map<String, dynamic>>? currentQuizDoc;
              if (selectedQuizCode != null && selectedQuizCode!.isNotEmpty) {
                for (final doc in allQuizzes) {
                  final code = (doc.data()['quizCode'] ?? doc.id).toString().trim();
                  if (code == selectedQuizCode || doc.id == selectedQuizCode) {
                    currentQuizDoc = doc;
                    break;
                  }
                }
              }

              // Default to first completed quiz or first active quiz if none selected
              if (currentQuizDoc == null && allQuizzes.isNotEmpty) {
                currentQuizDoc = allQuizzes.first;
                selectedQuizCode = (currentQuizDoc.data()['quizCode'] ?? currentQuizDoc.id).toString();
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Quiz Selector Header Card
                    _buildQuizSelectorCard(allQuizzes, filteredQuizzes, currentQuizDoc),
                    const SizedBox(height: 16),

                    if (currentQuizDoc != null) ...[
                      // Detail Report for Selected Quiz
                      _buildSelectedQuizReportDashboard(currentQuizDoc),
                    ] else
                      _buildNoQuizSelectedCard(),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // =========================================================
  // QUIZ SELECTOR WIDGET
  // =========================================================

  Widget _buildQuizSearchField() {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFFF8F5FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminThemeColors.border),
      ),
      child: TextField(
        controller: _quizSearchController,
        onChanged: (val) => setState(() => _quizSearchQuery = val.trim()),
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          hintText: 'Search quiz title or code...',
          hintStyle: const TextStyle(
            fontSize: 12,
            color: AdminThemeColors.textMuted,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 17,
            color: AdminThemeColors.textMuted,
          ),
          suffixIcon: _quizSearchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 15),
                  onPressed: () {
                    _quizSearchController.clear();
                    setState(() => _quizSearchQuery = '');
                  },
                )
              : null,
          border: InputBorder.none,
        ),
        style: const TextStyle(
          fontSize: 12,
          color: AdminThemeColors.textPrimary,
        ),
      ),
    );
  }

  Widget _buildQuizDropdownField(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> allQuizzes, {
    required bool isFullWidth,
  }) {
    final validCode = allQuizzes.any((d) => (d.data()['quizCode'] ?? d.id).toString().trim() == selectedQuizCode)
        ? selectedQuizCode
        : (allQuizzes.isNotEmpty ? (allQuizzes.first.data()['quizCode'] ?? allQuizzes.first.id).toString().trim() : null);

    return Container(
      height: 38,
      width: isFullWidth ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AdminThemeColors.pillBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminThemeColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: isFullWidth,
          value: validCode,
          icon: const Icon(
            Icons.arrow_drop_down_rounded,
            color: AdminThemeColors.primary,
          ),
          dropdownColor: Colors.white,
          items: allQuizzes.map((doc) {
            final code = (doc.data()['quizCode'] ?? doc.id).toString().trim();
            final title = (doc.data()['title'] ?? doc.data()['quizName'] ?? 'Quiz').toString().trim();
            return DropdownMenuItem<String>(
              value: code,
              child: Text(
                '$title ($code)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: AdminThemeColors.textPrimary,
                ),
              ),
            );
          }).toList(),
          onChanged: (newCode) {
            if (newCode != null) {
              setState(() => selectedQuizCode = newCode);
            }
          },
        ),
      ),
    );
  }

  Widget _buildQuizSelectorCard(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> allQuizzes,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> filteredQuizzes,
    QueryDocumentSnapshot<Map<String, dynamic>>? currentDoc,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AdminThemeColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0617245A),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 480;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      color: AdminThemeColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Select Quiz Competition to Generate Report',
                      style: TextStyle(
                        color: AdminThemeColors.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Search & Dropdown (Responsive: Stack on mobile, side-by-side on wide screens)
              if (isNarrow) ...[
                _buildQuizSearchField(),
                if (allQuizzes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildQuizDropdownField(allQuizzes, isFullWidth: true),
                ],
              ] else ...[
                Row(
                  children: [
                    Expanded(child: _buildQuizSearchField()),
                    const SizedBox(width: 8),
                    if (allQuizzes.isNotEmpty)
                      _buildQuizDropdownField(allQuizzes, isFullWidth: false),
                  ],
                ),
              ],
              const SizedBox(height: 10),

              // Filter chips (SingleChildScrollView to never overflow on phone)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    _buildFilterChip('all', 'All Quizzes (${allQuizzes.length})'),
                    const SizedBox(width: 6),
                    _buildFilterChip('completed', 'Completed Quizzes'),
                    const SizedBox(width: 6),
                    _buildFilterChip('ongoing', 'Ongoing Quizzes'),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final bool isSelected = _quizFilter == key;
    return InkWell(
      onTap: () => setState(() => _quizFilter = key),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AdminThemeColors.primary : AdminThemeColors.pillBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AdminThemeColors.primary : AdminThemeColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? Colors.white : AdminThemeColors.textPrimary,
          ),
        ),
      ),
    );
  }

  // =========================================================
  // SELECTED QUIZ DASHBOARD (REPORTS, RANKINGS, SUMMARY)
  // =========================================================

  Widget _buildSelectedQuizReportDashboard(
    QueryDocumentSnapshot<Map<String, dynamic>> quizDoc,
  ) {
    final data = quizDoc.data();
    final quizCode = (data['quizCode'] ?? quizDoc.id).toString().trim();
    final quizTitle = (data['title'] ?? data['quizName'] ?? 'TechNoWiz Quiz').toString().trim();
    final status = (data['status'] ?? 'Active').toString().trim();
    final isFinished = status.toLowerCase() == 'finished' || status.toLowerCase() == 'completed';
    final quizDate = _formatDateValue(data['date'] ?? data['quizDate']);
    final location = (data['location'] ?? data['venue'] ?? '').toString();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('quiz_sessions')
          .doc(quizDoc.id)
          .collection('join_requests')
          .snapshots(),
      builder: (context, requestSnap) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('quiz_sessions')
              .doc(quizDoc.id)
              .collection('scores')
              .snapshots(),
          builder: (context, scoreSnap) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('quiz_sessions')
                  .doc(quizDoc.id)
                  .collection('participants')
                  .snapshots(),
              builder: (context, participantSnap) {
                if ((requestSnap.connectionState == ConnectionState.waiting && !requestSnap.hasData) ||
                    (scoreSnap.connectionState == ConnectionState.waiting && !scoreSnap.hasData)) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(28),
                      child: CircularProgressIndicator(color: AdminThemeColors.primary),
                    ),
                  );
                }

                final reqDocs = requestSnap.data?.docs ?? [];
                final scoreDocs = scoreSnap.data?.docs ?? [];
                final partDocs = participantSnap.data?.docs ?? [];

                // Accurate extraction
                final contestants = _computeContestants(
                  requestDocs: reqDocs,
                  scoreDocs: scoreDocs,
                  participantDocs: partDocs,
                );

                // Participants roster
                final participants = [...contestants];
                participants.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Report Overview Hero Card
                    _buildReportHeroCard(
                      quizTitle: quizTitle,
                      quizCode: quizCode,
                      status: status,
                      isFinished: isFinished,
                      date: quizDate,
                      location: location,
                      contestants: contestants,
                      participants: participants,
                    ),
                    const SizedBox(height: 16),

                    // Three Objective #4 Navigation Tabs
                    _buildReportSegmentedTabs(contestants.length, participants.length),
                    const SizedBox(height: 14),

                    // Active Tab View Content
                    if (_selectedReportTab == 'rankings') ...[
                      _buildFinalRankingsSection(contestants, quizTitle, quizCode),
                    ] else if (_selectedReportTab == 'scores') ...[
                      _buildScoreSummariesSection(contestants),
                    ] else ...[
                      _buildParticipantRecordsSection(participants),
                    ],
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  // =========================================================
  // HERO BANNER & PDF EXPORT ACTIONS
  // =========================================================

  Widget _buildReportHeroCard({
    required String quizTitle,
    required String quizCode,
    required String status,
    required bool isFinished,
    required String date,
    required String location,
    required List<ReportContestant> contestants,
    required List<ReportContestant> participants,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AdminThemeColors.primaryDark, AdminThemeColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AdminThemeColors.primary.withValues(alpha: 0.32),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top badges
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.description_rounded, color: Colors.white, size: 13),
                      const SizedBox(width: 5),
                      Text(
                        'OFFICIAL REPORT',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.95),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isFinished
                        ? const Color(0xFF10B981).withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Quiz Title & Code
            Text(
              quizTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Quiz Code: $quizCode  •  Date: $date',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),

            // Main Action Buttons: Generate Official PDF & Print Certificates
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => _generateOfficialReportPdf(
                    quizTitle: quizTitle,
                    quizCode: quizCode,
                    quizStatus: status,
                    quizDate: date,
                    location: location,
                    rankings: contestants,
                    participants: participants,
                  ),
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                  label: const Text('Export Official PDF Report'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AdminThemeColors.primaryDark,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _printAllTopThreeCertificates(
                    contestants: contestants,
                    quizTitle: quizTitle,
                  ),
                  icon: const Icon(Icons.workspace_premium_rounded, size: 16),
                  label: const Text('Print Top 3 Certificates'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // SEGMENTED TABS (FINAL RANKINGS, SCORE SUMMARIES, RECORDS)
  // =========================================================

  Widget _buildReportSegmentedTabs(int rankingCount, int participantCount) {
    final tabs = [
      {'key': 'rankings', 'label': 'Final Rankings', 'icon': Icons.emoji_events_rounded, 'count': rankingCount},
      {'key': 'scores', 'label': 'Score Summaries', 'icon': Icons.bar_chart_rounded, 'count': null},
      {'key': 'participants', 'label': 'Participant Records', 'icon': Icons.people_alt_rounded, 'count': participantCount},
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AdminThemeColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0617245A),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: tabs.map((t) {
          final isSelected = _selectedReportTab == t['key'];
          return Expanded(
            child: InkWell(
              onTap: () => setState(() => _selectedReportTab = t['key'] as String),
              borderRadius: BorderRadius.circular(11),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? const LinearGradient(
                          colors: [AdminThemeColors.primary, AdminThemeColors.primaryDark],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      t['icon'] as IconData,
                      size: 16,
                      color: isSelected ? Colors.white : AdminThemeColors.textMuted,
                    ),
                    const SizedBox(height: 3),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        t['label'] as String,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                          color: isSelected ? Colors.white : AdminThemeColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // =========================================================
  // TAB 1: FINAL RANKINGS (OFFICIAL STANDINGS)
  // =========================================================

  Widget _buildFinalRankingsSection(
    List<ReportContestant> contestants,
    String quizTitle,
    String quizCode,
  ) {
    if (contestants.isEmpty) {
      return _buildEmptySection(
        icon: Icons.emoji_events_outlined,
        title: 'No Final Rankings Yet',
        subtitle: 'Rankings will appear here as contestants participate and score points.',
      );
    }

    final top1 = contestants.isNotEmpty ? contestants[0] : null;
    final top2 = contestants.length > 1 ? contestants[1] : null;
    final top3 = contestants.length > 2 ? contestants[2] : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Podium summary cards
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (top1 != null)
              Expanded(
                child: _buildPodiumHighlightCard(
                  rank: 1,
                  title: 'Champion',
                  contestant: top1,
                  color: const Color(0xFFF59E0B),
                  bg: const Color(0xFFFFFBEB),
                  quizTitle: quizTitle,
                ),
              ),
            if (top2 != null) ...[
              const SizedBox(width: 6),
              Expanded(
                child: _buildPodiumHighlightCard(
                  rank: 2,
                  title: '1st Runner-Up',
                  contestant: top2,
                  color: const Color(0xFF64748B),
                  bg: const Color(0xFFF8FAFC),
                  quizTitle: quizTitle,
                ),
              ),
            ],
            if (top3 != null) ...[
              const SizedBox(width: 6),
              Expanded(
                child: _buildPodiumHighlightCard(
                  rank: 3,
                  title: '2nd Runner-Up',
                  contestant: top3,
                  color: const Color(0xFFD97706),
                  bg: const Color(0xFFFFF7ED),
                  quizTitle: quizTitle,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),

        // Section Title
        Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                color: AdminThemeColors.primary,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Official Final Standings',
              style: TextStyle(
                color: AdminThemeColors.textPrimary,
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            Text(
              '${contestants.length} Contestants',
              style: const TextStyle(
                color: AdminThemeColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // List of all contestants with rankings
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: contestants.length,
          itemBuilder: (context, index) {
            final rank = index + 1;
            final c = contestants[index];
            return _buildRankRowCard(rank, c, quizTitle);
          },
        ),
      ],
    );
  }

  Widget _buildPodiumHighlightCard({
    required int rank,
    required String title,
    required ReportContestant contestant,
    required Color color,
    required Color bg,
    required String quizTitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Text(
              '$rank',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              contestant.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AdminThemeColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${contestant.totalScore} pts',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => _printCertificate(
              contestantName: contestant.name,
              quizTitle: quizTitle,
              rank: rank,
              teamName: contestant.teamName,
              school: contestant.school,
              totalScore: contestant.totalScore,
              level1Score: contestant.level1Score,
              level2Score: contestant.level2Score,
              level3Score: contestant.level3Score,
              quizCode: selectedQuizCode ?? '',
              quizDate: _dateText(),
              eliminated: false,
            ),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3.5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.workspace_premium_rounded, size: 12, color: color),
                    const SizedBox(width: 3),
                    Text(
                      'Certificate',
                      style: TextStyle(
                        color: color,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRankRowCard(int rank, ReportContestant c, String quizTitle) {
    final bool isTop3 = rank <= 3;
    Color badgeBg;
    Color badgeBorder;
    Color badgeText;

    if (rank == 1) {
      badgeBg = const Color(0xFFFEF3C7);
      badgeBorder = const Color(0xFFF59E0B);
      badgeText = const Color(0xFFB45309);
    } else if (rank == 2) {
      badgeBg = const Color(0xFFF1F5F9);
      badgeBorder = const Color(0xFF94A3B8);
      badgeText = const Color(0xFF475569);
    } else if (rank == 3) {
      badgeBg = const Color(0xFFFFEDD5);
      badgeBorder = const Color(0xFFFB923C);
      badgeText = const Color(0xFFC2410C);
    } else {
      badgeBg = AdminThemeColors.pillBg;
      badgeBorder = AdminThemeColors.border;
      badgeText = AdminThemeColors.primary;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isTop3 ? badgeBorder.withValues(alpha: 0.5) : AdminThemeColors.border,
          width: isTop3 ? 1.3 : 1.0,
        ),
      ),
      child: Row(
        children: [
          // Rank Badge
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: badgeBorder, width: isTop3 ? 1.2 : 0.8),
            ),
            child: Text(
              '$rank',
              style: TextStyle(
                color: badgeText,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AdminThemeColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (c.isEliminated)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'ELIMINATED',
                          style: TextStyle(
                            color: Color(0xFFDC2626),
                            fontSize: 7.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                  ],
                ),
                if (c.teamName.isNotEmpty || c.school.isNotEmpty)
                  Text(
                    c.teamName.isNotEmpty
                        ? (c.school.isNotEmpty ? '${c.teamName} • ${c.school}' : c.teamName)
                        : c.school,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AdminThemeColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                const SizedBox(height: 3),
                // Level scores breakdown
                Wrap(
                  spacing: 6,
                  children: [
                    Text('L1: ${c.level1Score}', style: const TextStyle(fontSize: 9.5, color: AdminThemeColors.textMuted)),
                    Text('L2: ${c.level2Score}', style: const TextStyle(fontSize: 9.5, color: AdminThemeColors.textMuted)),
                    Text('L3: ${c.level3Score}', style: const TextStyle(fontSize: 9.5, color: AdminThemeColors.textMuted)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Total Points badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFF0EBFF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFDDD6FE)),
            ),
            child: Text(
              '${c.totalScore} pts',
              style: const TextStyle(
                color: AdminThemeColors.primary,
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 4),

          // Print / Download Certificate icon button
          IconButton(
            tooltip: 'Print / Download Certificate',
            icon: const Icon(Icons.workspace_premium_rounded, size: 20, color: AdminThemeColors.primary),
            onPressed: () => _printCertificate(
              contestantName: c.name,
              quizTitle: quizTitle,
              rank: rank,
              teamName: c.teamName,
              school: c.school,
              totalScore: c.totalScore,
              level1Score: c.level1Score,
              level2Score: c.level2Score,
              level3Score: c.level3Score,
              quizCode: selectedQuizCode ?? '',
              quizDate: _dateText(),
              eliminated: c.isEliminated,
              eliminatedLevel: c.eliminatedLevel,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // TAB 2: SCORE SUMMARIES (STATISTICS & ANALYSIS)
  // =========================================================

  Widget _buildScoreSummariesSection(List<ReportContestant> contestants) {
    if (contestants.isEmpty) {
      return _buildEmptySection(
        icon: Icons.bar_chart_rounded,
        title: 'No Score Data Available',
        subtitle: 'Score summaries will calculate as contestants complete answers.',
      );
    }

    final total = contestants.length;
    final highest = contestants.map((c) => c.totalScore).reduce((a, b) => a > b ? a : b);
    final lowest = contestants.map((c) => c.totalScore).reduce((a, b) => a < b ? a : b);
    final avg = (contestants.map((c) => c.totalScore).reduce((a, b) => a + b) / total).toStringAsFixed(1);
    final activeCount = contestants.where((c) => !c.isEliminated).length;
    final activeRate = ((activeCount / total) * 100).toStringAsFixed(0);

    // Levels
    final l1Avg = (contestants.map((c) => c.level1Score).reduce((a, b) => a + b) / total).toStringAsFixed(1);
    final l2Avg = (contestants.map((c) => c.level2Score).reduce((a, b) => a + b) / total).toStringAsFixed(1);
    final l3Avg = (contestants.map((c) => c.level3Score).reduce((a, b) => a + b) / total).toStringAsFixed(1);

    final l1Max = contestants.map((c) => c.level1Score).reduce((a, b) => a > b ? a : b);
    final l2Max = contestants.map((c) => c.level2Score).reduce((a, b) => a > b ? a : b);
    final l3Max = contestants.map((c) => c.level3Score).reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 4 KPI Summary Cards
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                icon: Icons.stars_rounded,
                label: 'Top Score',
                value: '$highest pts',
                color: const Color(0xFF10B981),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricCard(
                icon: Icons.calculate_rounded,
                label: 'Average Score',
                value: '$avg pts',
                color: AdminThemeColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                icon: Icons.trending_down_rounded,
                label: 'Lowest Score',
                value: '$lowest pts',
                color: const Color(0xFFF59E0B),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricCard(
                icon: Icons.verified_user_rounded,
                label: 'Completion Rate',
                value: '$activeRate%',
                color: const Color(0xFF3B82F6),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // Level-by-Level Analysis
        Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                color: AdminThemeColors.primary,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Level Breakdown Statistics',
              style: TextStyle(
                color: AdminThemeColors.textPrimary,
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        _buildLevelStatRow('Level 1 (Easy / Qualifier)', l1Avg, l1Max),
        const SizedBox(height: 8),
        _buildLevelStatRow('Level 2 (Moderate / Semi-Finals)', l2Avg, l2Max),
        const SizedBox(height: 8),
        _buildLevelStatRow('Level 3 (Championship / Finals)', l3Avg, l3Max),
      ],
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: const [
          BoxShadow(color: Color(0x0617245A), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AdminThemeColors.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelStatRow(String levelTitle, String avg, int max) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminThemeColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 360;
          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.analytics_rounded, size: 18, color: AdminThemeColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        levelTitle,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AdminThemeColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AdminThemeColors.pillBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Avg: $avg pts',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AdminThemeColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Max: $max pts',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              const Icon(Icons.analytics_rounded, size: 20, color: AdminThemeColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  levelTitle,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AdminThemeColors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AdminThemeColors.pillBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Avg: $avg pts',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AdminThemeColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Max: $max pts',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF10B981),
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
  // TAB 3: PARTICIPANT RECORDS (REGISTRATION DIRECTORY)
  // =========================================================

  Widget _buildParticipantRecordsSection(List<ReportContestant> participants) {
    final filtered = participants.where((p) {
      if (_participantSearchQuery.isEmpty) return true;
      final q = _participantSearchQuery.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.teamName.toLowerCase().contains(q) ||
          p.school.toLowerCase().contains(q) ||
          p.id.toLowerCase().contains(q);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search & Count Bar
        Row(
          children: [
            Expanded(
              child: Container(
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AdminThemeColors.border),
                ),
                child: TextField(
                  controller: _participantSearchController,
                  onChanged: (val) => setState(() => _participantSearchQuery = val.trim()),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    hintText: 'Search participant by name or school...',
                    hintStyle: const TextStyle(
                      fontSize: 12,
                      color: AdminThemeColors.textMuted,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 17,
                      color: AdminThemeColors.textMuted,
                    ),
                    suffixIcon: _participantSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 15),
                            onPressed: () {
                              _participantSearchController.clear();
                              setState(() => _participantSearchQuery = '');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                  ),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminThemeColors.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: AdminThemeColors.pillBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AdminThemeColors.border),
              ),
              child: Text(
                'Total: ${participants.length}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AdminThemeColors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (filtered.isEmpty)
          _buildEmptySection(
            icon: Icons.person_search_rounded,
            title: 'No Participant Records Found',
            subtitle: 'No participants match the search query.',
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final p = filtered[index];
              return _buildParticipantRecordCard(index + 1, p);
            },
          ),
      ],
    );
  }

  Widget _buildParticipantRecordCard(int index, ReportContestant p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminThemeColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: const Color(0xFFF0EBFF),
            child: Text(
              '$index',
              style: const TextStyle(
                color: AdminThemeColors.primary,
                fontWeight: FontWeight.w900,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AdminThemeColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (p.teamName.isNotEmpty || p.school.isNotEmpty)
                  Text(
                    p.teamName.isNotEmpty
                        ? (p.school.isNotEmpty ? '${p.teamName} • ${p.school}' : p.teamName)
                        : p.school,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AdminThemeColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                Text(
                  'ID: ${p.id}',
                  style: const TextStyle(fontSize: 8.5, color: AdminThemeColors.textSubtle),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: p.isEliminated
                  ? const Color(0xFFFEE2E2)
                  : const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              p.isEliminated ? 'ELIMINATED' : p.status.toUpperCase(),
              style: TextStyle(
                color: p.isEliminated ? const Color(0xFFDC2626) : const Color(0xFF10B981),
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // EMPTY STATE HELPER
  // =========================================================

  Widget _buildEmptySection({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminThemeColors.border),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              color: Color(0xFFF0EBFF),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AdminThemeColors.primary, size: 28),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AdminThemeColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11.5,
              color: AdminThemeColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoQuizSelectedCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AdminThemeColors.border),
      ),
      child: const Column(
        children: [
          Icon(Icons.assignment_outlined, size: 40, color: AdminThemeColors.primary),
          SizedBox(height: 12),
          Text(
            'No Quiz Selected',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AdminThemeColors.textPrimary,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Please pick a quiz competition session above to inspect participant records, score summaries, and final rankings.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AdminThemeColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Participant / Contestant data model for Admin Reports & Documentation
class ReportContestant {
  final String id;
  final String name;
  final String teamName;
  final String school;
  final int totalScore;
  final int level1Score;
  final int level2Score;
  final int level3Score;
  final bool isEliminated;
  final int? eliminatedLevel;
  final String status;
  final int submissionTimeMs;
  final DateTime? registeredAt;

  const ReportContestant({
    required this.id,
    required this.name,
    this.teamName = '',
    this.school = '',
    this.totalScore = 0,
    this.level1Score = 0,
    this.level2Score = 0,
    this.level3Score = 0,
    this.isEliminated = false,
    this.eliminatedLevel,
    this.status = 'active',
    this.submissionTimeMs = 0,
    this.registeredAt,
  });
}

