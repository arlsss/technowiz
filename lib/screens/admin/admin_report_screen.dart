import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_dashboard.dart';
import 'manage_users_screen.dart';
import 'add_question_screen.dart';
import 'question_list_screen.dart';
import 'manage_quiz_sessions_screen.dart';
import 'admin_leaderboard_screen.dart';
import 'admin_sidebar.dart';
import 'admin_theme.dart';
import '../../navigation_persistence.dart';

// ============================================================================
// TECHNOWIZ ADMIN REPORT & DOCUMENTATION CENTER
// ============================================================================
// Objective 4: To generate reliable reports such as participant records,
// score summaries, and final rankings for easier management and documentation.
// ============================================================================

class AdminReportScreen extends StatefulWidget {
  final String? initialTab;
  final String? initialQuizCode;

  const AdminReportScreen({
    super.key,
    this.initialTab,
    this.initialQuizCode,
  });

  @override
  State<AdminReportScreen> createState() => _AdminReportScreenState();
}

class _AdminReportScreenState extends State<AdminReportScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String? selectedQuizCode;
  String _selectedReportTab = 'rankings'; // 'rankings', 'scores', 'participants'
  String _quizSearchQuery = '';
  String _participantSearchQuery = '';

  final TextEditingController _quizSearchController = TextEditingController();
  final TextEditingController _participantSearchController =
      TextEditingController();

  CertificateConfig _certificateConfig = CertificateConfig.defaultTemplate();
  ReportConfig _reportConfig = ReportConfig.defaultTemplate();

  final Map<String, Map<int, int>> _levelScoresCache = {};
  final Set<String> _syncingUids = {};
  final Set<String> _checkedUids = {};
  String? _lastSyncedQuizCode;

  @override
  void initState() {
    super.initState();
    if (widget.initialTab != null && widget.initialTab!.isNotEmpty) {
      _selectedReportTab = widget.initialTab!;
    }
    if (widget.initialQuizCode != null && widget.initialQuizCode!.isNotEmpty) {
      selectedQuizCode = widget.initialQuizCode;
    }
    _restorePreferencesAndSave();
  }

  Future<void> _restorePreferencesAndSave() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      if (widget.initialTab == null &&
          prefs.containsKey(AdminNavPersistence.reportTabKey)) {
        final savedTab = prefs.getString(AdminNavPersistence.reportTabKey);
        if (savedTab != null && savedTab.isNotEmpty) {
          _selectedReportTab = savedTab;
        }
      }
      if (widget.initialQuizCode == null &&
          prefs.containsKey(AdminNavPersistence.reportQuizCodeKey)) {
        final savedCode =
            prefs.getString(AdminNavPersistence.reportQuizCodeKey);
        if (savedCode != null && savedCode.isNotEmpty) {
          selectedQuizCode = savedCode;
        }
      }
    } catch (_) {}
    await _loadCertificateConfig(selectedQuizCode);
    await _loadReportConfig(selectedQuizCode);
    if (mounted) setState(() {});
    await _savePage();
  }

  Future<void> _savePage() async {
    await AdminNavPersistence.savePage(
      'reports',
      reportTab: _selectedReportTab,
      reportQuizCode: selectedQuizCode,
    );
  }

  // =========================================================
  // CERTIFICATE CONFIG PERSISTENCE & MANAGEMENT
  // =========================================================

  Future<void> _loadCertificateConfig([String? quizCode]) async {
    final code = quizCode ?? selectedQuizCode;
    try {
      // 1. Check if the specific quiz session has custom certificate config in Firestore
      if (code != null && code.trim().isNotEmpty) {
        final doc = await FirebaseFirestore.instance
            .collection('quiz_sessions')
            .doc(code.trim())
            .get();
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          if (data['certificateConfig'] is Map) {
            final config = CertificateConfig.fromMap(
              Map<String, dynamic>.from(data['certificateConfig'] as Map),
            );
            if (mounted) {
              setState(() => _certificateConfig = config);
            }
            return;
          }
        }
      }

      // 2. Check global template in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final savedStr = prefs.getString('global_certificate_config');
      if (savedStr != null && savedStr.trim().isNotEmpty) {
        final decoded = jsonDecode(savedStr);
        if (decoded is Map) {
          final config = CertificateConfig.fromMap(
            Map<String, dynamic>.from(decoded),
          );
          if (mounted) {
            setState(() => _certificateConfig = config);
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('Error loading certificate config: $e');
    }

    if (mounted) {
      setState(() => _certificateConfig = CertificateConfig.defaultTemplate());
    }
  }

  Future<void> _saveCertificateConfig(CertificateConfig config) async {
    setState(() => _certificateConfig = config);

    try {
      // 1. Save globally in SharedPreferences as default template
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'global_certificate_config',
        jsonEncode(config.toMap()),
      );

      // 2. Save specifically to Firestore quiz session if selected
      if (selectedQuizCode != null && selectedQuizCode!.trim().isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('quiz_sessions')
            .doc(selectedQuizCode!.trim())
            .set({
          'certificateConfig': config.toMap(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Error saving certificate config: $e');
    }
  }

  void _openManageCertificateDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _ManageCertificateDialog(
          initialConfig: _certificateConfig,
          quizCode: selectedQuizCode ?? '',
          onSave: (newConfig) async {
            await _saveCertificateConfig(newConfig);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Certificate signatures and layout updated successfully!'),
                  backgroundColor: Color(0xFF16A34A),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          onPreview: (previewConfig) async {
            await _printCertificate(
              contestantName: 'JUAN DELA CRUZ',
              quizTitle: 'TechNoWiz Championship',
              rank: 1,
              teamName: 'TECHNOWIZ CHAMPIONS',
              school: 'College of Computer Studies',
              totalScore: 98,
              quizCode: selectedQuizCode ?? 'SAMPLE',
              quizDate: _dateText(),
              customConfig: previewConfig,
            );
          },
        );
      },
    );
  }

  // =========================================================
  // REPORT CONFIG (SIGNATURES) PERSISTENCE & MANAGEMENT
  // =========================================================

  Future<void> _loadReportConfig([String? quizCode]) async {
    final code = quizCode ?? selectedQuizCode;
    try {
      if (code != null && code.trim().isNotEmpty) {
        final doc = await FirebaseFirestore.instance
            .collection('quiz_sessions')
            .doc(code.trim())
            .get();
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          if (data['reportConfig'] is Map) {
            final config = ReportConfig.fromMap(
              Map<String, dynamic>.from(data['reportConfig'] as Map),
            );
            if (mounted) {
              setState(() => _reportConfig = config);
            }
            return;
          }
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final savedStr = prefs.getString('global_report_config');
      if (savedStr != null && savedStr.trim().isNotEmpty) {
        final decoded = jsonDecode(savedStr);
        if (decoded is Map) {
          final config = ReportConfig.fromMap(
            Map<String, dynamic>.from(decoded),
          );
          if (mounted) {
            setState(() => _reportConfig = config);
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('Error loading report config: $e');
    }

    if (mounted) {
      setState(() => _reportConfig = ReportConfig.defaultTemplate());
    }
  }

  Future<void> _saveReportConfig(ReportConfig config) async {
    setState(() => _reportConfig = config);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('global_report_config', jsonEncode(config.toMap()));

      if (selectedQuizCode != null && selectedQuizCode!.trim().isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('quiz_sessions')
            .doc(selectedQuizCode!.trim())
            .set(
          {'reportConfig': config.toMap()},
          SetOptions(merge: true),
        );
      }
    } catch (e) {
      debugPrint('Error saving report config: $e');
    }
  }

  void _openManageReportSignaturesDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _ManageReportSignaturesDialog(
          initialConfig: _reportConfig,
          quizCode: selectedQuizCode ?? '',
          onSave: (newConfig) async {
            await _saveReportConfig(newConfig);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Report signatures updated successfully!'),
                  backgroundColor: Color(0xFF16A34A),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          onPreview: (previewConfig) async {
            await _generateOfficialReportPdf(
              quizTitle: 'TechNoWiz Championship Quiz',
              quizCode: selectedQuizCode ?? 'SAMPLE',
              quizStatus: 'FINISHED',
              quizDate: _dateText(),
              location: 'Main Auditorium',
              rankings: const [],
              participants: const [],
              section: ReportPrintSection.scoreSummaryOnly,
              customConfig: previewConfig,
            );
          },
        );
      },
    );
  }

  void _openExportReportOptionsDialog({
    required String quizTitle,
    required String quizCode,
    required String quizStatus,
    required String quizDate,
    required String location,
    required List<ReportContestant> rankings,
    required List<ReportContestant> participants,
  }) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _ExportReportOptionsDialog(
          quizTitle: quizTitle,
          quizCode: quizCode,
          reportConfig: _reportConfig,
          onEditSignatures: () {
            Navigator.of(dialogContext).pop();
            _openManageReportSignaturesDialog();
          },
          onExport: (section) async {
            Navigator.of(dialogContext).pop();
            await _generateOfficialReportPdf(
              quizTitle: quizTitle,
              quizCode: quizCode,
              quizStatus: quizStatus,
              quizDate: quizDate,
              location: location,
              rankings: rankings,
              participants: participants,
              section: section,
            );
          },
        );
      },
    );
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
      adminPageRoute(page),
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
    showAdminProfileSidePopup(context);
  }

  // =========================================================
  // CERTIFICATE PDF BUILDER (EXACT TEMPLATE DESIGNS)
  // =========================================================
  // Rank 1: 1ST PLACE (Gold Theme with Trophy & Laurels)
  // Rank 2: 2ND PLACE (Silver / Blue Theme with Trophy & Laurels)
  // Rank 3: 3RD PLACE (Bronze / Orange Theme with Trophy & Laurels)
  // Others: APPRECIATION (Emerald Green Theme with Star & Laurels)
  // =========================================================

  pw.Widget _buildPdfSignaturesRow(CertificateConfig config) {
    final signatories = config.signatories;
    if (signatories.isEmpty) {
      return pw.SizedBox.shrink();
    }

    if (signatories.length == 1) {
      final sig = signatories[0];
      return pw.Center(
        child: pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            if (sig.name.trim().isNotEmpty) ...[
              pw.Text(
                sig.name.trim().toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: const PdfColor.fromInt(0xFF0F172A),
                ),
              ),
              pw.SizedBox(height: 3),
            ] else ...[
              pw.SizedBox(height: 14),
            ],
            if (sig.showLine)
              pw.Container(width: 200, height: 1.5, color: const PdfColor.fromInt(0xFF0F172A))
            else
              pw.SizedBox(width: 200, height: 1.5),
            pw.SizedBox(height: 4),
            pw.Text(
              sig.title.trim().isNotEmpty ? sig.title.trim() : 'Authorized Signatory',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: const PdfColor.fromInt(0xFF0F172A),
              ),
            ),
          ],
        ),
      );
    }

    if (signatories.length == 2) {
      return pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          for (final sig in signatories)
            pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                if (sig.name.trim().isNotEmpty) ...[
                  pw.Text(
                    sig.name.trim().toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 10.5,
                      fontWeight: pw.FontWeight.bold,
                      color: const PdfColor.fromInt(0xFF0F172A),
                    ),
                  ),
                  pw.SizedBox(height: 3),
                ] else ...[
                  pw.SizedBox(height: 14),
                ],
                if (sig.showLine)
                  pw.Container(width: 175, height: 1.5, color: const PdfColor.fromInt(0xFF0F172A))
                else
                  pw.SizedBox(width: 175, height: 1.5),
                pw.SizedBox(height: 4),
                pw.Text(
                  sig.title.trim().isNotEmpty ? sig.title.trim() : 'Authorized Signatory',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: const PdfColor.fromInt(0xFF0F172A),
                  ),
                ),
              ],
            ),
        ],
      );
    }

    // 3 signatories
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        for (final sig in signatories.take(3))
          pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              if (sig.name.trim().isNotEmpty) ...[
                pw.Text(
                  sig.name.trim().toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    fontWeight: pw.FontWeight.bold,
                    color: const PdfColor.fromInt(0xFF0F172A),
                  ),
                ),
                pw.SizedBox(height: 3),
              ] else ...[
                pw.SizedBox(height: 13),
              ],
              if (sig.showLine)
                pw.Container(width: 140, height: 1.5, color: const PdfColor.fromInt(0xFF0F172A))
              else
                pw.SizedBox(width: 140, height: 1.5),
              pw.SizedBox(height: 4),
              pw.Text(
                sig.title.trim().isNotEmpty ? sig.title.trim() : 'Authorized Signatory',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: const PdfColor.fromInt(0xFF0F172A),
                ),
              ),
            ],
          ),
      ],
    );
  }

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
    CertificateConfig? customConfig,
  }) async {
    final pdf = document ?? pw.Document();
    final config = customConfig ?? _certificateConfig;

    final effectiveName = teamName.trim().isNotEmpty
        ? teamName.trim()
        : (contestantName.trim().isNotEmpty ? contestantName.trim() : 'Contestant');

    final String fullQuizTitle = quizTitle.trim().isNotEmpty
        ? quizTitle.trim()
        : 'TechNoWiz Quiz Competition';
    final String dateString = quizDate.trim().isNotEmpty ? quizDate.trim() : _dateText();

    pw.MemoryImage? certLogoImage;
    try {
      final bytes = await rootBundle.load('assets/images/certificate_logo.jpg');
      certLogoImage = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (e) {
      debugPrint('Error loading certificate logo asset: $e');
    }

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
      citation1 = 'In highest recognition of exemplary mastery, critical thinking, and outstanding intellect for securing 1ST PLACE (CHAMPION) in the $fullQuizTitle${totalScore > 0 ? ' with an impressive score of $totalScore points' : ''}.';
      citation2 = 'Awarded on $dateString in commendation of extraordinary competence, dedication, and academic excellence in technology.';
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
      citation1 = 'In meritorious recognition of exemplary skill, teamwork, and superior performance for securing 2ND PLACE (1ST RUNNER-UP) in the $fullQuizTitle${totalScore > 0 ? ' with a total score of $totalScore points' : ''}.';
      citation2 = 'Awarded on $dateString in commendation of outstanding competence, perseverance, and dedication to technical knowledge.';
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
      citation1 = 'In distinguished recognition of remarkable dedication, perseverance, and excellent performance for securing 3RD PLACE (2ND RUNNER-UP) in the $fullQuizTitle${totalScore > 0 ? ' with a total score of $totalScore points' : ''}.';
      citation2 = 'Awarded on $dateString in recognition of commendable achievement, competitive spirit, and passion for excellence.';
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
      citation1 = 'In sincere appreciation of enthusiastic participation, sportsmanship, and commendable effort in the $fullQuizTitle${totalScore > 0 ? ' with a total score of $totalScore points' : ''}.';
      citation2 = 'Awarded on $dateString in recognition of dedication, active engagement, and passion for technology and continuous learning.';
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
                      // Header: TechNoWiz 3D Mascot & Brand Logo (Replaces plain text)
                      if (certLogoImage != null)
                        pw.Container(
                          margin: const pw.EdgeInsets.only(bottom: 2),
                          decoration: pw.BoxDecoration(
                            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                            border: pw.Border.all(color: borderColor, width: 1.2),
                          ),
                          child: pw.ClipRRect(
                            horizontalRadius: 7,
                            verticalRadius: 7,
                            child: pw.Image(
                              certLogoImage,
                              width: 110,
                              height: 75,
                              fit: pw.BoxFit.contain,
                            ),
                          ),
                        )
                      else
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
                            config.certificateTitle.trim().isNotEmpty
                                ? config.certificateTitle.trim()
                                : 'CERTIFICATE OF ACHIEVEMENT',
                            style: pw.TextStyle(
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                              color: const PdfColor.fromInt(0xFF0F172A),
                              letterSpacing: 2,
                            ),
                          ),
                          pw.SizedBox(height: 5),
                          pw.Text(
                            config.certificateSubtitle.trim().isNotEmpty
                                ? config.certificateSubtitle.trim()
                                : 'This certificate is proudly awarded to',
                            style: const pw.TextStyle(
                              fontSize: 11.5,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColor.fromInt(0xFF334155),
                            ),
                          ),
                        ],
                      ),

                      // Contestant / Team Name & Underline
                      pw.Column(
                        children: [
                          pw.Text(
                            effectiveName.toUpperCase(),
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(
                              fontSize: 24,
                              fontWeight: pw.FontWeight.bold,
                              color: const PdfColor.fromInt(0xFF0F172A),
                              letterSpacing: 1.2,
                            ),
                          ),
                          if (teamName.trim().isNotEmpty &&
                              contestantName.trim().isNotEmpty &&
                              contestantName.trim().toLowerCase() != teamName.trim().toLowerCase()) ...[
                            pw.SizedBox(height: 2),
                            pw.Text(
                              'Team Leader / Contestant: ${contestantName.trim()}',
                              textAlign: pw.TextAlign.center,
                              style: const pw.TextStyle(
                                fontSize: 9.5,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColor.fromInt(0xFF475569),
                              ),
                            ),
                          ],
                          if (school.trim().isNotEmpty) ...[
                            pw.SizedBox(height: 2),
                            pw.Text(
                              school.trim(),
                              textAlign: pw.TextAlign.center,
                              style: const pw.TextStyle(
                                fontSize: 10.5,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColor.fromInt(0xFF475569),
                              ),
                            ),
                          ],
                          pw.SizedBox(height: 4),
                          pw.Container(
                            width: 440,
                            height: 1.5,
                            color: const PdfColor.fromInt(0xFF0F172A),
                          ),
                        ],
                      ),

                      // Words & Citations Under Name
                      pw.Container(
                        width: 530,
                        child: pw.Column(
                          children: [
                            pw.Text(
                              citation1,
                              textAlign: pw.TextAlign.center,
                              style: const pw.TextStyle(
                                fontSize: 9.5,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColor.fromInt(0xFF1E293B),
                                lineSpacing: 2,
                              ),
                            ),
                            pw.SizedBox(height: 3),
                            pw.Text(
                              citation2,
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(
                                fontSize: 9,
                                fontWeight: pw.FontWeight.bold,
                                fontStyle: pw.FontStyle.italic,
                                color: const PdfColor.fromInt(0xFF334155),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Signatures: Configured by Admin via Manage Certificate
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 40),
                        child: _buildPdfSignaturesRow(config),
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
      final safeName = effectiveName.replaceAll(' ', '_').replaceAll(RegExp(r'[^\w\.-]'), '');
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
      final displayName = c.teamName.isNotEmpty ? c.teamName : c.name;
      await _printCertificate(
        contestantName: displayName,
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
    ReportPrintSection section = ReportPrintSection.allSeparatePages,
    ReportConfig? customConfig,
  }) async {
    final pdf = pw.Document();
    final cfg = customConfig ?? _reportConfig;

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

    pw.Widget buildPdfHeader(pw.Context context, {required String sectionTitle}) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 12),
        padding: const pw.EdgeInsets.only(bottom: 8),
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
                  cfg.institutionTitle.isNotEmpty
                      ? cfg.institutionTitle
                      : 'TECHNOWIZ COMPETITION SYSTEM',
                  style: pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.deepPurple800,
                    letterSpacing: 0.8,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  cfg.documentSubtitle.isNotEmpty
                      ? cfg.documentSubtitle
                      : 'Official Session Report & Documentation',
                  style: const pw.TextStyle(
                    fontSize: 9.5,
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
    }

    pw.Widget buildPdfEventInfoBox() {
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          borderRadius: pw.BorderRadius.circular(6),
          border: pw.Border.all(color: PdfColors.grey300),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              quizTitle,
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),
            pw.SizedBox(height: 5),
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'Date: ${quizDate.isNotEmpty ? quizDate : _dateText()}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    'Location: ${location.isNotEmpty ? location : "Main Hall"}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    'Status: ${quizStatus.toUpperCase()}',
                    style: pw.TextStyle(
                      fontSize: 9,
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
      );
    }

    pw.Widget buildPdfFooter(pw.Context context) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(top: 12),
        padding: const pw.EdgeInsets.only(top: 6),
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
    }

    pw.Widget buildPdfSignatures() {
      final sigs = cfg.signatories;
      if (sigs.isEmpty) return pw.SizedBox();

      final lineWidth = sigs.length >= 3 ? 140.0 : 170.0;

      return pw.Container(
        margin: const pw.EdgeInsets.only(top: 24),
        child: pw.Row(
          mainAxisAlignment: sigs.length == 1
              ? pw.MainAxisAlignment.center
              : pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: sigs.map((s) {
            final prefix = s.label.trim();
            final name = s.name.trim();
            final displayTitle = s.title.trim();
            final fullLabel = prefix.isNotEmpty && name.isNotEmpty
                ? '$prefix $name'
                : (name.isNotEmpty ? name : prefix);

            return pw.Column(
              crossAxisAlignment: sigs.length == 1
                  ? pw.CrossAxisAlignment.center
                  : pw.CrossAxisAlignment.start,
              children: [
                if (s.showLine)
                  pw.Container(
                    width: lineWidth,
                    height: 1,
                    color: PdfColors.black,
                  ),
                pw.SizedBox(height: 4),
                pw.Container(
                  width: lineWidth,
                  child: pw.Text(
                    fullLabel,
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.black,
                    ),
                    textAlign: sigs.length == 1
                        ? pw.TextAlign.center
                        : pw.TextAlign.start,
                  ),
                ),
                if (displayTitle.isNotEmpty) ...[
                  pw.SizedBox(height: 1),
                  pw.Container(
                    width: lineWidth,
                    child: pw.Text(
                      displayTitle,
                      style: const pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.grey800,
                      ),
                      textAlign: sigs.length == 1
                          ? pw.TextAlign.center
                          : pw.TextAlign.start,
                    ),
                  ),
                ],
              ],
            );
          }).toList(),
        ),
      );
    }

    List<pw.Widget> buildTable1Widgets() {
      final total = rankings.isNotEmpty ? rankings.length : 1;
      final l1Avg = rankings.isNotEmpty
          ? (rankings.map((c) => c.level1Score).reduce((a, b) => a + b) / total).toStringAsFixed(1)
          : '0.0';
      final l2Avg = rankings.isNotEmpty
          ? (rankings.map((c) => c.level2Score).reduce((a, b) => a + b) / total).toStringAsFixed(1)
          : '0.0';
      final l3Avg = rankings.isNotEmpty
          ? (rankings.map((c) => c.level3Score).reduce((a, b) => a + b) / total).toStringAsFixed(1)
          : '0.0';
      final l1Max = rankings.isNotEmpty
          ? rankings.map((c) => c.level1Score).reduce((a, b) => a > b ? a : b)
          : 0;
      final l2Max = rankings.isNotEmpty
          ? rankings.map((c) => c.level2Score).reduce((a, b) => a > b ? a : b)
          : 0;
      final l3Max = rankings.isNotEmpty
          ? rankings.map((c) => c.level3Score).reduce((a, b) => a > b ? a : b)
          : 0;

      return [
        pw.Text(
          '1. SCORE SUMMARY & STATISTICS',
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.deepPurple800,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
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
        pw.Text(
          'COMPETITION LEVEL BREAKDOWN & ANALYSIS',
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.grey800,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headers: [
            'Competition Stage',
            'Average Score',
            'Highest Score',
            'Assessment Type',
          ],
          data: [
            ['Level 1 (Easy / Elimination)', '$l1Avg pts', '$l1Max pts', 'Multiple Choice / Elimination'],
            ['Level 2 (Moderate)', '$l2Avg pts', '$l2Max pts', 'Core Subject Problem Solving'],
            ['Level 3 (Difficult / Final)', '$l3Avg pts', '$l3Max pts', 'Championship & Advanced Level'],
          ],
          headerStyle: pw.TextStyle(
            fontSize: 8.5,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
          headerDecoration: const pw.BoxDecoration(
            color: PdfColors.deepPurple900,
          ),
          cellStyle: const pw.TextStyle(fontSize: 8.5),
          cellAlignment: pw.Alignment.centerLeft,
          headerAlignment: pw.Alignment.centerLeft,
          cellPadding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 6),
        ),
      ];
    }

    List<pw.Widget> buildTable2Widgets() {
      return [
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
          pw.TableHelper.fromTextArray(
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
                          ? '2nd Place'
                          : (rank == 3
                              ? '3rd Place'
                              : 'Finalist')));

              final displayName = c.teamName.isNotEmpty ? c.teamName : c.name;

              return [
                '$rank',
                displayName,
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
      ];
    }

    List<pw.Widget> buildTable3Widgets() {
      return [
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
          pw.TableHelper.fromTextArray(
            headers: ['#', 'Contestant / Team', 'Members', 'School Name', 'Status'],
            data: participants.asMap().entries.map((entry) {
              final p = entry.value;
              final isTeam = p.teamName.isNotEmpty;
              final displayName = isTeam ? p.teamName : p.name;
              final memberList = p.members.isNotEmpty
                  ? p.members
                  : (isTeam && p.name.isNotEmpty && p.name != p.teamName ? [p.name] : <String>[]);
              return [
                '${entry.key + 1}',
                displayName,
                memberList.isNotEmpty ? memberList.join(', ') : '-',
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
      ];
    }

    if (section == ReportPrintSection.allSeparatePages) {
      // Table 1 Page (Score Summary & Statistics)
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (context) => buildPdfHeader(context, sectionTitle: 'Score Summary & Statistics'),
          footer: buildPdfFooter,
          build: (context) => [
            buildPdfEventInfoBox(),
            pw.SizedBox(height: 16),
            ...buildTable1Widgets(),
            pw.SizedBox(height: 24),
            buildPdfSignatures(),
          ],
        ),
      );

      // Table 2 Page (Final Standings & Rankings)
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (context) => buildPdfHeader(context, sectionTitle: 'Final Standings & Rankings'),
          footer: buildPdfFooter,
          build: (context) => [
            buildPdfEventInfoBox(),
            pw.SizedBox(height: 16),
            ...buildTable2Widgets(),
            pw.SizedBox(height: 24),
            buildPdfSignatures(),
          ],
        ),
      );

      // Table 3 Page (Participant Records Directory)
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (context) => buildPdfHeader(context, sectionTitle: 'Participant Records Directory'),
          footer: buildPdfFooter,
          build: (context) => [
            buildPdfEventInfoBox(),
            pw.SizedBox(height: 16),
            ...buildTable3Widgets(),
            pw.SizedBox(height: 24),
            buildPdfSignatures(),
          ],
        ),
      );
    } else if (section == ReportPrintSection.scoreSummaryOnly) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (context) => buildPdfHeader(context, sectionTitle: 'Score Summary & Statistics'),
          footer: buildPdfFooter,
          build: (context) => [
            buildPdfEventInfoBox(),
            pw.SizedBox(height: 16),
            ...buildTable1Widgets(),
            pw.SizedBox(height: 24),
            buildPdfSignatures(),
          ],
        ),
      );
    } else if (section == ReportPrintSection.finalRankingsOnly) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (context) => buildPdfHeader(context, sectionTitle: 'Final Standings & Rankings'),
          footer: buildPdfFooter,
          build: (context) => [
            buildPdfEventInfoBox(),
            pw.SizedBox(height: 16),
            ...buildTable2Widgets(),
            pw.SizedBox(height: 24),
            buildPdfSignatures(),
          ],
        ),
      );
    } else if (section == ReportPrintSection.participantRecordsOnly) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (context) => buildPdfHeader(context, sectionTitle: 'Participant Records Directory'),
          footer: buildPdfFooter,
          build: (context) => [
            buildPdfEventInfoBox(),
            pw.SizedBox(height: 16),
            ...buildTable3Widgets(),
            pw.SizedBox(height: 24),
            buildPdfSignatures(),
          ],
        ),
      );
    }

    final docName = switch (section) {
      ReportPrintSection.allSeparatePages => 'TechNoWiz_Official_Report_$quizCode.pdf',
      ReportPrintSection.scoreSummaryOnly => 'TechNoWiz_Score_Summary_$quizCode.pdf',
      ReportPrintSection.finalRankingsOnly => 'TechNoWiz_Final_Rankings_$quizCode.pdf',
      ReportPrintSection.participantRecordsOnly => 'TechNoWiz_Participant_Records_$quizCode.pdf',
    };

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: docName,
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

  List<String> _teamMembers(dynamic raw) {
    if (raw is List) {
      return raw
          .map((e) => e is Map
              ? (e['name'] ?? '').toString().trim()
              : e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return raw
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return <String>[];
  }

  // =========================================================
  // SYNC & FETCH LEVEL SCORES CACHE
  // =========================================================

  void _syncOrFetchLevelScores(
    String quizCode,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> scoreDocs,
  ) {
    if (quizCode.isEmpty) return;

    if (_lastSyncedQuizCode != quizCode) {
      _lastSyncedQuizCode = quizCode;
      _levelScoresCache.clear();
      _syncingUids.clear();
      _checkedUids.clear();
    }

    for (final doc in scoreDocs) {
      final data = doc.data();
      final uid = (data['uid'] ?? doc.id).toString();

      if (_checkedUids.contains(uid) || _syncingUids.contains(uid)) continue;
      _syncingUids.add(uid);
      _checkedUids.add(uid);

      FirebaseFirestore.instance
          .collection('quiz_sessions')
          .doc(quizCode)
          .collection('answers')
          .doc(uid)
          .collection('responses')
          .get()
          .then((responsesSnap) {
        if (!mounted) return;
        final Map<int, int> userLevelScores = {};
        for (final r in responsesSnap.docs) {
          final rData = r.data();
          final lvl = (rData['level'] as num?)?.toInt() ?? 1;
          final pts = (rData['points'] as num?)?.toInt() ?? 0;
          final isCorrect = rData['isCorrect'] == true ||
              (rData['answerStatus'] ?? '').toString().toLowerCase() ==
                  'correct';
          if (pts > 0 && isCorrect) {
            userLevelScores[lvl] = (userLevelScores[lvl] ?? 0) + pts;
          }
        }

        if (userLevelScores.isNotEmpty) {
          setState(() {
            _levelScoresCache[uid] = userLevelScores;
          });

          final updateData = <String, dynamic>{};
          for (final entry in userLevelScores.entries) {
            updateData['level${entry.key}Score'] = entry.value;
            updateData['levelScores.Level ${entry.key}'] = entry.value;
          }
          doc.reference
              .set(updateData, SetOptions(merge: true))
              .catchError((_) {});
        }
      }).catchError((_) {}).whenComplete(() {
        _syncingUids.remove(uid);
      });
    }
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
      final members = _teamMembers(d['teamMembers'] ?? d['members']);
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
        members: members,
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
      final members = _teamMembers(d['teamMembers'] ?? d['members']);
      final school = (d['school'] ?? d['schoolName'] ?? '').toString().trim();
      final isElim = (d['status'] ?? '').toString().toLowerCase() == 'eliminated' ||
          d['isEliminated'] == true;

      final existing = map[doc.id];
      final mergedMembers = {...existing?.members ?? <String>[], ...members}.toList();
      map[doc.id] = ReportContestant(
        id: doc.id,
        name: name.isNotEmpty ? name : (existing?.name ?? 'Contestant'),
        teamName: team.isNotEmpty ? team : (existing?.teamName ?? ''),
        members: mergedMembers,
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
      final members = _teamMembers(d['teamMembers'] ?? d['members']);
      final school = (d['school'] ?? d['schoolName'] ?? '').toString().trim();
      final isElim = (d['status'] ?? '').toString().toLowerCase() == 'eliminated' ||
          d['isEliminated'] == true ||
          d['eliminated'] == true;

      final total = _toInt(d['score'] ?? d['totalScore'] ?? d['points'] ?? 0);

      // Extract all level scores dynamically (Level 1, 2, 3, 4, 5, etc.)
      final Map<int, int> extractedLevels = {};
      final cached = _levelScoresCache[uid];
      if (cached != null && cached.isNotEmpty) {
        extractedLevels.addAll(cached);
      }

      if (d['levelScores'] is Map) {
        final m = d['levelScores'] as Map;
        for (final entry in m.entries) {
          final k = entry.key.toString();
          final match = RegExp(r'\d+').firstMatch(k);
          if (match != null) {
            final lvlNum = int.tryParse(match.group(0)!);
            if (lvlNum != null) {
              extractedLevels[lvlNum] = _toInt(entry.value);
            }
          }
        }
      }

      for (final entry in d.entries) {
        final k = entry.key;
        final match = RegExp(r'^level[_\s]*(\d+)(?:Score)?$', caseSensitive: false).firstMatch(k);
        if (match != null) {
          final lvlNum = int.tryParse(match.group(1)!);
          if (lvlNum != null && !extractedLevels.containsKey(lvlNum)) {
            extractedLevels[lvlNum] = _toInt(entry.value);
          }
        }
      }

      final l1 = extractedLevels[1] ?? _toInt(d['level1Score'] ?? d['level_1']);
      final l2 = extractedLevels[2] ?? _toInt(d['level2Score'] ?? d['level_2']);
      final l3 = extractedLevels[3] ?? _toInt(d['level3Score'] ?? d['level_3']);
      extractedLevels[1] = l1;
      extractedLevels[2] = l2;
      extractedLevels[3] = l3;

      int finalTotal = total;
      final sumLevels = extractedLevels.values.fold<int>(0, (acc, pts) => acc + pts);
      if (finalTotal == 0 && sumLevels > 0) {
        finalTotal = sumLevels;
      } else if (finalTotal > 0 && sumLevels == 0) {
        extractedLevels[1] = finalTotal;
      }

      int timeMs = 0;
      final rawTime = d['lastSubmissionTime'] ?? d['updatedAt'] ?? d['answeredAt'];
      if (rawTime is Timestamp) timeMs = rawTime.millisecondsSinceEpoch;

      final existing = map[uid];
      final mergedMembers = {...existing?.members ?? <String>[], ...members}.toList();
      map[uid] = ReportContestant(
        id: uid,
        name: name.isNotEmpty ? name : (existing?.name ?? 'Contestant'),
        teamName: team.isNotEmpty ? team : (existing?.teamName ?? ''),
        members: mergedMembers,
        school: school.isNotEmpty ? school : (existing?.school ?? ''),
        totalScore: finalTotal,
        level1Score: l1,
        level2Score: l2,
        level3Score: l3,
        levelScores: extractedLevels,
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
        toolbarHeight: kAdminAppBarHeight,
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
              _loadCertificateConfig(newCode);
              _loadReportConfig(newCode);
              _savePage();
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
            ],
          );
        },
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

                _syncOrFetchLevelScores(quizCode, scoreDocs);

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
                      _buildFinalRankingsSection(
                        contestants: contestants,
                        quizTitle: quizTitle,
                        quizCode: quizCode,
                        quizStatus: status,
                        quizDate: quizDate,
                        location: location,
                        participants: participants,
                      ),
                    ] else if (_selectedReportTab == 'scores') ...[
                      _buildScoreSummariesSection(
                        contestants: contestants,
                        quizTitle: quizTitle,
                        quizCode: quizCode,
                        quizStatus: status,
                        quizDate: quizDate,
                        location: location,
                        participants: participants,
                      ),
                    ] else ...[
                      _buildParticipantRecordsSection(
                        participants: participants,
                        quizTitle: quizTitle,
                        quizCode: quizCode,
                        quizStatus: status,
                        quizDate: quizDate,
                        location: location,
                        contestants: contestants,
                      ),
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
                  onPressed: () => _openExportReportOptionsDialog(
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
                OutlinedButton.icon(
                  onPressed: _openManageCertificateDialog,
                  icon: const Icon(Icons.draw_rounded, size: 16),
                  label: const Text('Manage Certificate'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _openManageReportSignaturesDialog,
                  icon: const Icon(Icons.edit_note_rounded, size: 16),
                  label: const Text('Report Signatures'),
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
              onTap: () {
                setState(() => _selectedReportTab = t['key'] as String);
                _savePage();
              },
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

  Widget _buildFinalRankingsSection({
    required List<ReportContestant> contestants,
    required String quizTitle,
    required String quizCode,
    required String quizStatus,
    required String quizDate,
    required String location,
    required List<ReportContestant> participants,
  }) {
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
                  title: '2nd Place',
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
                  title: '3rd Place',
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
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => _generateOfficialReportPdf(
                quizTitle: quizTitle,
                quizCode: quizCode,
                quizStatus: quizStatus,
                quizDate: quizDate,
                location: location,
                rankings: contestants,
                participants: participants,
                section: ReportPrintSection.finalRankingsOnly,
              ),
              icon: const Icon(Icons.print_rounded, size: 14),
              label: const Text('Print Standings (Table 2)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AdminThemeColors.primary,
                side: const BorderSide(color: AdminThemeColors.primary, width: 1),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
    String? quizTitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
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
              contestant.teamName.isNotEmpty ? contestant.teamName : contestant.name,
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
        ],
      ),
    );
  }

  Widget _buildRankRowCard(int rank, ReportContestant c, String quizTitle) {
    final bool isTop3 = rank <= 3;
    final isTeam = c.teamName.isNotEmpty;
    final displayName = isTeam ? c.teamName : c.name;
    final memberList = c.members.isNotEmpty
        ? c.members
        : (isTeam && c.name.isNotEmpty && c.name != c.teamName ? [c.name] : <String>[]);
    final membersText = memberList.isNotEmpty ? 'Members: ${memberList.join(', ')}' : '';

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
                        displayName,
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
                if (membersText.isNotEmpty)
                  Text(
                    c.school.isNotEmpty ? '$membersText • ${c.school}' : membersText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AdminThemeColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                else if (c.school.isNotEmpty)
                  Text(
                    c.school,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AdminThemeColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                const SizedBox(height: 4),
                // Level scores breakdown: Each level clearly displays the points earned
                Builder(
                  builder: (_) {
                    final Map<int, int> levelsMap = c.levelScores.isNotEmpty
                        ? c.levelScores
                        : {1: c.level1Score, 2: c.level2Score, 3: c.level3Score};
                    final sortedKeys = levelsMap.keys.toList()..sort();
                    final allKeys = {...sortedKeys, 1, 2, 3}.toList()..sort();

                    return Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: allKeys.map((lvl) {
                        final pts = levelsMap[lvl] ??
                            (lvl == 1
                                ? c.level1Score
                                : (lvl == 2
                                    ? c.level2Score
                                    : (lvl == 3 ? c.level3Score : 0)));
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: const Color(0xFFE2E8F0), width: 0.8),
                          ),
                          child: Text(
                            'L$lvl: $pts pts',
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF475569),
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Total Overall Points badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF3E8FF), Color(0xFFEDE9FE)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFDDD6FE), width: 1.2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'TOTAL OVERALL',
                  style: TextStyle(
                    color: Color(0xFF7E22CE),
                    fontSize: 7.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${c.totalScore} pts',
                  style: const TextStyle(
                    color: Color(0xFF581C87),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),

          // Print / Download Certificate icon button
          IconButton(
            tooltip: 'Print / Download Certificate',
            icon: const Icon(Icons.workspace_premium_rounded, size: 20, color: AdminThemeColors.primary),
            onPressed: () => _printCertificate(
              contestantName: displayName,
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

  Widget _buildScoreSummariesSection({
    required List<ReportContestant> contestants,
    required String quizTitle,
    required String quizCode,
    required String quizStatus,
    required String quizDate,
    required String location,
    required List<ReportContestant> participants,
  }) {
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
        // Header with Print Table 1 action
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
              'Performance Statistics & Score Summary',
              style: TextStyle(
                color: AdminThemeColors.textPrimary,
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: () => _generateOfficialReportPdf(
                quizTitle: quizTitle,
                quizCode: quizCode,
                quizStatus: quizStatus,
                quizDate: quizDate,
                location: location,
                rankings: contestants,
                participants: participants,
                section: ReportPrintSection.scoreSummaryOnly,
              ),
              icon: const Icon(Icons.print_rounded, size: 14),
              label: const Text('Print Score Summary (Table 1)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AdminThemeColors.primary,
                side: const BorderSide(color: AdminThemeColors.primary, width: 1),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
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

  Widget _buildParticipantRecordsSection({
    required List<ReportContestant> participants,
    required String quizTitle,
    required String quizCode,
    required String quizStatus,
    required String quizDate,
    required String location,
    required List<ReportContestant> contestants,
  }) {
    final filtered = participants.where((p) {
      if (_participantSearchQuery.isEmpty) return true;
      final q = _participantSearchQuery.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.teamName.toLowerCase().contains(q) ||
          p.school.toLowerCase().contains(q) ||
          p.members.any((m) => m.toLowerCase().contains(q));
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
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => _generateOfficialReportPdf(
                quizTitle: quizTitle,
                quizCode: quizCode,
                quizStatus: quizStatus,
                quizDate: quizDate,
                location: location,
                rankings: contestants,
                participants: participants,
                section: ReportPrintSection.participantRecordsOnly,
              ),
              icon: const Icon(Icons.print_rounded, size: 14),
              label: const Text('Print Records (Table 3)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AdminThemeColors.primary,
                side: const BorderSide(color: AdminThemeColors.primary, width: 1),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
    final isTeam = p.teamName.isNotEmpty;
    final displayName = isTeam ? p.teamName : p.name;
    final memberList = p.members.isNotEmpty
        ? p.members
        : (isTeam && p.name.isNotEmpty && p.name != p.teamName ? [p.name] : <String>[]);
    final membersText = memberList.isNotEmpty ? 'Members: ${memberList.join(', ')}' : '';

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
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AdminThemeColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (membersText.isNotEmpty)
                  Text(
                    p.school.isNotEmpty ? '$membersText • ${p.school}' : membersText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AdminThemeColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                else if (p.school.isNotEmpty)
                  Text(
                    p.school,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AdminThemeColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
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
  final List<String> members;
  final String school;
  final int totalScore;
  final int level1Score;
  final int level2Score;
  final int level3Score;
  final Map<int, int> levelScores;
  final bool isEliminated;
  final int? eliminatedLevel;
  final String status;
  final int submissionTimeMs;
  final DateTime? registeredAt;

  const ReportContestant({
    required this.id,
    required this.name,
    this.teamName = '',
    this.members = const [],
    this.school = '',
    this.totalScore = 0,
    this.level1Score = 0,
    this.level2Score = 0,
    this.level3Score = 0,
    this.levelScores = const {},
    this.isEliminated = false,
    this.eliminatedLevel,
    this.status = 'active',
    this.submissionTimeMs = 0,
    this.registeredAt,
  });
}

// ============================================================================
// CERTIFICATE CONFIGURATION & SIGNATORY MODELS
// ============================================================================

class CertificateSignatory {
  String name;
  String title;
  bool showLine;

  CertificateSignatory({
    required this.name,
    required this.title,
    this.showLine = true,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'title': title,
        'showLine': showLine,
      };

  factory CertificateSignatory.fromMap(Map<String, dynamic> map) =>
      CertificateSignatory(
        name: (map['name'] ?? '').toString(),
        title: (map['title'] ?? '').toString(),
        showLine: map['showLine'] != false,
      );
}

class CertificateConfig {
  String certificateTitle;
  String certificateSubtitle;
  List<CertificateSignatory> signatories;

  CertificateConfig({
    this.certificateTitle = 'CERTIFICATE OF ACHIEVEMENT',
    this.certificateSubtitle = 'This certificate is proudly awarded to',
    required this.signatories,
  });

  static CertificateConfig defaultTemplate() => CertificateConfig(
        certificateTitle: 'CERTIFICATE OF ACHIEVEMENT',
        certificateSubtitle: 'This certificate is proudly awarded to',
        signatories: [
          CertificateSignatory(
            name: '',
            title: 'Event Organizer',
            showLine: true,
          ),
          CertificateSignatory(
            name: '',
            title: 'TechNoWiz Host',
            showLine: true,
          ),
        ],
      );

  Map<String, dynamic> toMap() => {
        'certificateTitle': certificateTitle,
        'certificateSubtitle': certificateSubtitle,
        'signatories': signatories.map((s) => s.toMap()).toList(),
      };

  factory CertificateConfig.fromMap(Map<String, dynamic> map) {
    final rawSigs = map['signatories'];
    final sigs = <CertificateSignatory>[];
    if (rawSigs is List && rawSigs.isNotEmpty) {
      for (final s in rawSigs) {
        if (s is Map<String, dynamic>) {
          sigs.add(CertificateSignatory.fromMap(s));
        } else if (s is Map) {
          sigs.add(CertificateSignatory.fromMap(Map<String, dynamic>.from(s)));
        }
      }
    }
    if (sigs.isEmpty) {
      sigs.addAll(defaultTemplate().signatories);
    }

    return CertificateConfig(
      certificateTitle:
          (map['certificateTitle'] ?? 'CERTIFICATE OF ACHIEVEMENT').toString(),
      certificateSubtitle:
          (map['certificateSubtitle'] ?? 'This certificate is proudly awarded to')
              .toString(),
      signatories: sigs,
    );
  }
}

// ============================================================================
// MANAGE CERTIFICATE DIALOG
// ============================================================================

class _ManageCertificateDialog extends StatefulWidget {
  final CertificateConfig initialConfig;
  final String quizCode;
  final Future<void> Function(CertificateConfig) onSave;
  final Future<void> Function(CertificateConfig) onPreview;

  const _ManageCertificateDialog({
    required this.initialConfig,
    required this.quizCode,
    required this.onSave,
    required this.onPreview,
  });

  @override
  State<_ManageCertificateDialog> createState() =>
      _ManageCertificateDialogState();
}

class _ManageCertificateDialogState extends State<_ManageCertificateDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _subtitleController;

  int _signatoryCount = 2;
  late final List<TextEditingController> _nameControllers;
  late final List<TextEditingController> _titleControllers;
  late final List<bool> _showLines;
  bool _isSaving = false;
  bool _isPreviewing = false;

  @override
  void initState() {
    super.initState();
    _titleController =
        TextEditingController(text: widget.initialConfig.certificateTitle);
    _subtitleController =
        TextEditingController(text: widget.initialConfig.certificateSubtitle);

    final sigs = widget.initialConfig.signatories;
    _signatoryCount = sigs.length.clamp(1, 3);

    _nameControllers = List.generate(3, (i) {
      final text = i < sigs.length ? sigs[i].name : '';
      return TextEditingController(text: text);
    });

    _titleControllers = List.generate(3, (i) {
      if (i < sigs.length) return TextEditingController(text: sigs[i].title);
      if (i == 0) return TextEditingController(text: 'Event Organizer');
      if (i == 1) return TextEditingController(text: 'TechNoWiz Host');
      return TextEditingController(text: 'Campus Director');
    });

    _showLines = List.generate(3, (i) {
      if (i < sigs.length) return sigs[i].showLine;
      return true;
    });

    // Listen to updates for live preview
    _titleController.addListener(_refresh);
    _subtitleController.addListener(_refresh);
    for (final c in _nameControllers) {
      c.addListener(_refresh);
    }
    for (final c in _titleControllers) {
      c.addListener(_refresh);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _titleController.dispose();
    _subtitleController.dispose();
    for (final c in _nameControllers) {
      c.dispose();
    }
    for (final c in _titleControllers) {
      c.dispose();
    }
    super.dispose();
  }

  CertificateConfig _buildConfig() {
    final activeSignatories = <CertificateSignatory>[];
    for (int i = 0; i < _signatoryCount; i++) {
      activeSignatories.add(
        CertificateSignatory(
          name: _nameControllers[i].text.trim(),
          title: _titleControllers[i].text.trim().isNotEmpty
              ? _titleControllers[i].text.trim()
              : (i == 0
                  ? 'Event Organizer'
                  : (i == 1 ? 'TechNoWiz Host' : 'Campus Director')),
          showLine: _showLines[i],
        ),
      );
    }

    return CertificateConfig(
      certificateTitle: _titleController.text.trim().isNotEmpty
          ? _titleController.text.trim()
          : 'CERTIFICATE OF ACHIEVEMENT',
      certificateSubtitle: _subtitleController.text.trim().isNotEmpty
          ? _subtitleController.text.trim()
          : 'This certificate is proudly awarded to',
      signatories: activeSignatories,
    );
  }

  void _resetToDefault() {
    final def = CertificateConfig.defaultTemplate();
    _titleController.text = def.certificateTitle;
    _subtitleController.text = def.certificateSubtitle;
    _signatoryCount = 2;

    _nameControllers[0].text = def.signatories[0].name;
    _titleControllers[0].text = def.signatories[0].title;
    _showLines[0] = def.signatories[0].showLine;

    _nameControllers[1].text = def.signatories[1].name;
    _titleControllers[1].text = def.signatories[1].title;
    _showLines[1] = def.signatories[1].showLine;

    _nameControllers[2].text = '';
    _titleControllers[2].text = 'Campus Director';
    _showLines[2] = true;

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            // Modal Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4338CA), Color(0xFF6366F1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.workspace_premium_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Manage Certificate Signatures',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Edit signatory names, lines, and certificate titles',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Scrollable Settings Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section 1: Number of Signatories
                    Text(
                      'NUMBER OF SIGNATORIES',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: isDark ? Colors.white70 : AdminThemeColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? Colors.white12 : Colors.grey.shade300,
                        ),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          for (int count = 1; count <= 3; count++)
                            Expanded(
                              child: InkWell(
                                onTap: () => setState(() => _signatoryCount = count),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 9),
                                  decoration: BoxDecoration(
                                    color: _signatoryCount == count
                                        ? const Color(0xFF4F46E5)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: _signatoryCount == count
                                        ? [
                                            BoxShadow(
                                              color: const Color(0xFF4F46E5)
                                                  .withValues(alpha: 0.35),
                                              blurRadius: 6,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    count == 1
                                        ? '1 Signatory'
                                        : (count == 2
                                            ? '2 Signatories'
                                            : '3 Signatories'),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: _signatoryCount == count
                                          ? Colors.white
                                          : (isDark ? Colors.white70 : Colors.black87),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Section 2: Signatory Details Cards
                    for (int i = 0; i < _signatoryCount; i++) ...[
                      _buildSignatoryEditorCard(i, isDark),
                      const SizedBox(height: 14),
                    ],

                    const SizedBox(height: 6),

                    // Section 3: Certificate Title & Award Statement
                    Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        initiallyExpanded: false,
                        tilePadding: EdgeInsets.zero,
                        title: Text(
                          'CERTIFICATE TITLES & WORDING (OPTIONAL)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: isDark ? Colors.white70 : AdminThemeColors.textSecondary,
                          ),
                        ),
                        children: [
                          TextField(
                            controller: _titleController,
                            decoration: InputDecoration(
                              labelText: 'Certificate Title',
                              hintText: 'e.g. CERTIFICATE OF ACHIEVEMENT',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              filled: true,
                              fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _subtitleController,
                            decoration: InputDecoration(
                              labelText: 'Award Statement / Subtitle',
                              hintText: 'e.g. This certificate is proudly awarded to',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              filled: true,
                              fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                            style: const TextStyle(fontSize: 13),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Section 4: Real-time In-App Visual Preview
                    Text(
                      'REAL-TIME SIGNATURE PREVIEW',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: isDark ? Colors.white70 : AdminThemeColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFDE68A), width: 1.2),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _titleController.text.trim().isNotEmpty
                                ? _titleController.text.trim().toUpperCase()
                                : 'CERTIFICATE OF ACHIEVEMENT',
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _subtitleController.text.trim().isNotEmpty
                                ? _subtitleController.text.trim()
                                : 'This certificate is proudly awarded to',
                            style: const TextStyle(
                              color: Color(0xFF475569),
                              fontSize: 10,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Live Signatures Row Preview
                          Row(
                            mainAxisAlignment: _signatoryCount == 1
                                ? MainAxisAlignment.center
                                : MainAxisAlignment.spaceBetween,
                            children: [
                              for (int i = 0; i < _signatoryCount; i++) ...[
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _nameControllers[i].text.trim().isNotEmpty
                                            ? _nameControllers[i].text.trim().toUpperCase()
                                            : '(Manual Signature)',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                          color: _nameControllers[i].text.trim().isNotEmpty
                                              ? const Color(0xFF0F172A)
                                              : Colors.grey.shade500,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      if (_showLines[i])
                                        Container(
                                          height: 1.5,
                                          color: const Color(0xFF0F172A),
                                          margin: const EdgeInsets.symmetric(horizontal: 10),
                                        )
                                      else
                                        const SizedBox(height: 1.5),
                                      const SizedBox(height: 3),
                                      Text(
                                        _titleControllers[i].text.trim().isNotEmpty
                                            ? _titleControllers[i].text.trim()
                                            : 'Authorized Signatory',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (i < _signatoryCount - 1)
                                  const SizedBox(width: 12),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Modal Footer Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
                border: Border(
                  top: BorderSide(
                    color: isDark ? Colors.white12 : Colors.grey.shade200,
                  ),
                ),
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _resetToDefault,
                    icon: const Icon(Icons.restart_alt_rounded, size: 16),
                    label: const Text('Reset', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(foregroundColor: Colors.grey.shade600),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: _isPreviewing
                        ? null
                        : () async {
                            setState(() => _isPreviewing = true);
                            try {
                              await widget.onPreview(_buildConfig());
                            } finally {
                              if (mounted) setState(() => _isPreviewing = false);
                            }
                          },
                    icon: _isPreviewing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.visibility_rounded, size: 16),
                    label: const Text('Preview PDF', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _isSaving
                        ? null
                        : () async {
                            setState(() => _isSaving = true);
                            try {
                              await widget.onSave(_buildConfig());
                              if (context.mounted) {
                                Navigator.of(context).pop();
                              }
                            } finally {
                              if (mounted) setState(() => _isSaving = false);
                            }
                          },
                    icon: _isSaving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Save & Apply', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignatoryEditorCard(int index, bool isDark) {
    final positionLabel = index == 0
        ? 'Signatory 1 (Left / Organizer)'
        : (index == 1
            ? 'Signatory 2 (Right / Quiz Master)'
            : 'Signatory 3 (Center / Approver)');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Color(0xFF4F46E5),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  positionLabel,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AdminThemeColors.textPrimary,
                  ),
                ),
              ),
              // Show Line Toggle
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Line',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white70 : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Switch.adaptive(
                    value: _showLines[index],
                    activeTrackColor: const Color(0xFF4F46E5),
                    onChanged: (val) => setState(() => _showLines[index] = val),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _nameControllers[index],
            decoration: InputDecoration(
              labelText: 'Signatory Name',
              hintText: 'e.g. Dr. Arnel Tipdas (Leave empty for blank line)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              filled: true,
              fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _titleControllers[index],
            decoration: InputDecoration(
              labelText: 'Designation / Title',
              hintText: 'e.g. Event Organizer, Dean, Quiz Master',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              filled: true,
              fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// REPORT PRINT & EXPORT CONFIGURATION MODELS
// ============================================================================

enum ReportPrintSection {
  allSeparatePages,
  scoreSummaryOnly,
  finalRankingsOnly,
  participantRecordsOnly,
}

class ReportSignatory {
  String label;
  String name;
  String title;
  bool showLine;

  ReportSignatory({
    required this.label,
    required this.name,
    required this.title,
    this.showLine = true,
  });

  Map<String, dynamic> toMap() => {
        'label': label,
        'name': name,
        'title': title,
        'showLine': showLine,
      };

  factory ReportSignatory.fromMap(Map<String, dynamic> map) => ReportSignatory(
        label: (map['label'] ?? '').toString(),
        name: (map['name'] ?? '').toString(),
        title: (map['title'] ?? '').toString(),
        showLine: map['showLine'] != false,
      );
}

class ReportConfig {
  String institutionTitle;
  String documentSubtitle;
  List<ReportSignatory> signatories;

  ReportConfig({
    this.institutionTitle = 'TECHNOWIZ COMPETITION SYSTEM',
    this.documentSubtitle = 'Official Session Report & Documentation',
    required this.signatories,
  });

  static ReportConfig defaultTemplate() => ReportConfig(
        institutionTitle: 'TECHNOWIZ COMPETITION SYSTEM',
        documentSubtitle: 'Official Session Report & Documentation',
        signatories: [
          ReportSignatory(
            label: 'Prepared By:',
            name: 'Administrator',
            title: 'TechNoWiz Admin',
            showLine: true,
          ),
          ReportSignatory(
            label: 'Verified By:',
            name: 'Quiz Master',
            title: 'Event Head / Coordinator',
            showLine: true,
          ),
        ],
      );

  Map<String, dynamic> toMap() => {
        'institutionTitle': institutionTitle,
        'documentSubtitle': documentSubtitle,
        'signatories': signatories.map((s) => s.toMap()).toList(),
      };

  factory ReportConfig.fromMap(Map<String, dynamic> map) {
    final rawSigs = map['signatories'];
    final sigs = <ReportSignatory>[];
    if (rawSigs is List && rawSigs.isNotEmpty) {
      for (final s in rawSigs) {
        if (s is Map<String, dynamic>) {
          sigs.add(ReportSignatory.fromMap(s));
        } else if (s is Map) {
          sigs.add(ReportSignatory.fromMap(Map<String, dynamic>.from(s)));
        }
      }
    }
    if (sigs.isEmpty) {
      sigs.addAll(defaultTemplate().signatories);
    }

    return ReportConfig(
      institutionTitle:
          (map['institutionTitle'] ?? 'TECHNOWIZ COMPETITION SYSTEM').toString(),
      documentSubtitle:
          (map['documentSubtitle'] ?? 'Official Session Report & Documentation')
              .toString(),
      signatories: sigs,
    );
  }
}

// ============================================================================
// MANAGE REPORT SIGNATURES DIALOG
// ============================================================================

class _ManageReportSignaturesDialog extends StatefulWidget {
  final ReportConfig initialConfig;
  final String quizCode;
  final Future<void> Function(ReportConfig) onSave;
  final Future<void> Function(ReportConfig) onPreview;

  const _ManageReportSignaturesDialog({
    required this.initialConfig,
    required this.quizCode,
    required this.onSave,
    required this.onPreview,
  });

  @override
  State<_ManageReportSignaturesDialog> createState() =>
      _ManageReportSignaturesDialogState();
}

class _ManageReportSignaturesDialogState extends State<_ManageReportSignaturesDialog> {
  int _signatoryCount = 2;
  late final List<TextEditingController> _labelControllers;
  late final List<TextEditingController> _nameControllers;
  late final List<TextEditingController> _titleControllers;
  late final List<bool> _showLines;
  bool _isSaving = false;
  bool _isPreviewing = false;

  @override
  void initState() {
    super.initState();
    _signatoryCount = widget.initialConfig.signatories.length.clamp(1, 3);

    _labelControllers = List.generate(3, (i) {
      if (i < widget.initialConfig.signatories.length) {
        return TextEditingController(text: widget.initialConfig.signatories[i].label);
      }
      return TextEditingController(
        text: i == 0 ? 'Prepared By:' : (i == 1 ? 'Verified By:' : 'Approved By:'),
      );
    });

    _nameControllers = List.generate(3, (i) {
      if (i < widget.initialConfig.signatories.length) {
        return TextEditingController(text: widget.initialConfig.signatories[i].name);
      }
      return TextEditingController(text: '');
    });

    _titleControllers = List.generate(3, (i) {
      if (i < widget.initialConfig.signatories.length) {
        return TextEditingController(text: widget.initialConfig.signatories[i].title);
      }
      return TextEditingController(
        text: i == 0 ? 'TechNoWiz Admin' : (i == 1 ? 'Event Head / Coordinator' : 'Dean / Department Chair'),
      );
    });

    _showLines = List.generate(3, (i) {
      if (i < widget.initialConfig.signatories.length) {
        return widget.initialConfig.signatories[i].showLine;
      }
      return true;
    });

    for (int i = 0; i < 3; i++) {
      _labelControllers[i].addListener(_onFieldChanged);
      _nameControllers[i].addListener(_onFieldChanged);
      _titleControllers[i].addListener(_onFieldChanged);
    }
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (int i = 0; i < 3; i++) {
      _labelControllers[i].dispose();
      _nameControllers[i].dispose();
      _titleControllers[i].dispose();
    }
    super.dispose();
  }

  ReportConfig _buildConfig() {
    final sigs = <ReportSignatory>[];
    for (int i = 0; i < _signatoryCount; i++) {
      sigs.add(
        ReportSignatory(
          label: _labelControllers[i].text.trim(),
          name: _nameControllers[i].text.trim(),
          title: _titleControllers[i].text.trim(),
          showLine: _showLines[i],
        ),
      );
    }
    return ReportConfig(signatories: sigs);
  }

  void _resetToDefault() {
    final def = ReportConfig.defaultTemplate();
    setState(() {
      _signatoryCount = def.signatories.length;
      for (int i = 0; i < 3; i++) {
        if (i < def.signatories.length) {
          _labelControllers[i].text = def.signatories[i].label;
          _nameControllers[i].text = def.signatories[i].name;
          _titleControllers[i].text = def.signatories[i].title;
          _showLines[i] = def.signatories[i].showLine;
        } else {
          _labelControllers[i].text = '';
          _nameControllers[i].text = '';
          _titleControllers[i].text = '';
          _showLines[i] = true;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 760),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 28,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Modal Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 14, 18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AdminThemeColors.primaryDark, AdminThemeColors.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.edit_note_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Manage Report Signatures',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Customize signatory names, designations, and lines for official reports',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Scrollable Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Signatory Count Selector
                    Row(
                      children: [
                        const Icon(Icons.people_alt_rounded, size: 16, color: Color(0xFF4F46E5)),
                        const SizedBox(width: 6),
                        const Text(
                          'Number of Signatories:',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(value: 1, label: Text('1 Sig')),
                            ButtonSegment(value: 2, label: Text('2 Sigs')),
                            ButtonSegment(value: 3, label: Text('3 Sigs')),
                          ],
                          selected: {_signatoryCount},
                          onSelectionChanged: (newVal) {
                            setState(() => _signatoryCount = newVal.first);
                          },
                          style: SegmentedButton.styleFrom(
                            selectedBackgroundColor: const Color(0xFF4F46E5),
                            selectedForegroundColor: Colors.white,
                            textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Signatory Editor Cards
                    for (int i = 0; i < _signatoryCount; i++) ...[
                      _buildSignatoryEditorCard(i, isDark),
                      if (i < _signatoryCount - 1) const SizedBox(height: 12),
                    ],

                    const SizedBox(height: 20),

                    // Live Footer Preview Box
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark ? Colors.white10 : const Color(0xFFCBD5E1),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.visibility_rounded, size: 14, color: Color(0xFF4F46E5)),
                              const SizedBox(width: 6),
                              Text(
                                'LIVE REPORT SIGNATURE PREVIEW',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                  color: isDark ? Colors.white70 : const Color(0xFF475569),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Row(
                            mainAxisAlignment: _signatoryCount == 1
                                ? MainAxisAlignment.center
                                : MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (int i = 0; i < _signatoryCount; i++) ...[
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: _signatoryCount == 1
                                        ? CrossAxisAlignment.center
                                        : CrossAxisAlignment.start,
                                    children: [
                                      if (_showLines[i])
                                        Container(
                                          width: 140,
                                          height: 1.5,
                                          color: isDark ? Colors.white70 : Colors.black87,
                                        ),
                                      const SizedBox(height: 5),
                                      Text(
                                        _labelControllers[i].text.trim().isNotEmpty &&
                                                _nameControllers[i].text.trim().isNotEmpty
                                            ? '${_labelControllers[i].text.trim()} ${_nameControllers[i].text.trim()}'
                                            : (_nameControllers[i].text.trim().isNotEmpty
                                                ? _nameControllers[i].text.trim()
                                                : (_labelControllers[i].text.trim().isNotEmpty
                                                    ? _labelControllers[i].text.trim()
                                                    : 'Signatory Name')),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.white : Colors.black87,
                                        ),
                                      ),
                                      Text(
                                        _titleControllers[i].text.trim().isNotEmpty
                                            ? _titleControllers[i].text.trim()
                                            : 'Title / Designation',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          color: isDark ? Colors.white60 : Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (i < _signatoryCount - 1) const SizedBox(width: 12),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Modal Footer Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
                border: Border(
                  top: BorderSide(
                    color: isDark ? Colors.white12 : Colors.grey.shade200,
                  ),
                ),
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _resetToDefault,
                    icon: const Icon(Icons.restart_alt_rounded, size: 16),
                    label: const Text('Reset', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(foregroundColor: Colors.grey.shade600),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: _isPreviewing
                        ? null
                        : () async {
                            setState(() => _isPreviewing = true);
                            try {
                              await widget.onPreview(_buildConfig());
                            } finally {
                              if (mounted) setState(() => _isPreviewing = false);
                            }
                          },
                    icon: _isPreviewing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.visibility_rounded, size: 16),
                    label: const Text('Preview PDF', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _isSaving
                        ? null
                        : () async {
                            setState(() => _isSaving = true);
                            try {
                              await widget.onSave(_buildConfig());
                              if (context.mounted) {
                                Navigator.of(context).pop();
                              }
                            } finally {
                              if (mounted) setState(() => _isSaving = false);
                            }
                          },
                    icon: _isSaving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Save & Apply', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignatoryEditorCard(int index, bool isDark) {
    final positionLabel = index == 0
        ? 'Signatory 1 (Left / Prepared By)'
        : (index == 1
            ? 'Signatory 2 (Right / Verified By)'
            : 'Signatory 3 (Center / Approved By)');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Color(0xFF4F46E5),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  positionLabel,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AdminThemeColors.textPrimary,
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Line',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white70 : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Switch.adaptive(
                    value: _showLines[index],
                    activeTrackColor: const Color(0xFF4F46E5),
                    onChanged: (val) => setState(() => _showLines[index] = val),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _labelControllers[index],
                  decoration: InputDecoration(
                    labelText: 'Prefix / Label',
                    hintText: 'e.g. Prepared By:',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _nameControllers[index],
                  decoration: InputDecoration(
                    labelText: 'Signatory Name',
                    hintText: 'e.g. Administrator or Prof. Dela Cruz',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _titleControllers[index],
            decoration: InputDecoration(
              labelText: 'Designation / Title',
              hintText: 'e.g. TechNoWiz Admin, Event Head / Coordinator',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              filled: true,
              fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// EXPORT REPORT OPTIONS DIALOG
// ============================================================================

class _ExportReportOptionsDialog extends StatefulWidget {
  final String quizTitle;
  final String quizCode;
  final ReportConfig reportConfig;
  final VoidCallback onEditSignatures;
  final Future<void> Function(ReportPrintSection) onExport;

  const _ExportReportOptionsDialog({
    required this.quizTitle,
    required this.quizCode,
    required this.reportConfig,
    required this.onEditSignatures,
    required this.onExport,
  });

  @override
  State<_ExportReportOptionsDialog> createState() =>
      _ExportReportOptionsDialogState();
}

class _ExportReportOptionsDialogState extends State<_ExportReportOptionsDialog> {
  ReportPrintSection _selectedSection = ReportPrintSection.allSeparatePages;
  bool _isExporting = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final options = [
      {
        'section': ReportPrintSection.allSeparatePages,
        'title': 'Complete Official Report (All Tables on Separate Pages)',
        'subtitle': 'Prints Table 1 (Score Summary), Table 2 (Final Standings), and Table 3 (Participant Directory) each on its own clean, dedicated page with official header and signatures.',
        'icon': Icons.auto_stories_rounded,
        'badge': 'RECOMMENDED',
        'badgeColor': const Color(0xFF10B981),
      },
      {
        'section': ReportPrintSection.scoreSummaryOnly,
        'title': 'Table 1: Score Summary & Statistics',
        'subtitle': 'Prints overall competition statistics, active/eliminated counts, top score, average scores, and level difficulty breakdown on 1 dedicated page.',
        'icon': Icons.bar_chart_rounded,
        'badge': 'PAGE 1',
        'badgeColor': const Color(0xFF4F46E5),
      },
      {
        'section': ReportPrintSection.finalRankingsOnly,
        'title': 'Table 2: Final Standings & Rankings',
        'subtitle': 'Prints official contestant rankings, Level 1/2/3 breakdown, total score points, and Champion / Runner-up finalist honors.',
        'icon': Icons.emoji_events_rounded,
        'badge': 'PAGE 2',
        'badgeColor': const Color(0xFFF59E0B),
      },
      {
        'section': ReportPrintSection.participantRecordsOnly,
        'title': 'Table 3: Participant Records Directory',
        'subtitle': 'Prints full directory of registered participants and teams, student members, school names, and competition status.',
        'icon': Icons.people_alt_rounded,
        'badge': 'PAGE 3',
        'badgeColor': const Color(0xFF0284C7),
      },
    ];

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: 580,
        constraints: const BoxConstraints(maxHeight: 720),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 28,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Modal Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 14, 18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AdminThemeColors.primaryDark, AdminThemeColors.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Export & Print Official Report',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${widget.quizTitle} • Code: ${widget.quizCode}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Options List
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SELECT REPORT PRINT FORMAT:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.7,
                        color: isDark ? Colors.white70 : AdminThemeColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 10),

                    for (final opt in options) ...[
                      InkWell(
                        onTap: () {
                          setState(() => _selectedSection = opt['section'] as ReportPrintSection);
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _selectedSection == opt['section']
                                ? const Color(0xFF4F46E5).withValues(alpha: isDark ? 0.2 : 0.08)
                                : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _selectedSection == opt['section']
                                  ? const Color(0xFF4F46E5)
                                  : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                              width: _selectedSection == opt['section'] ? 1.8 : 1.0,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Radio<ReportPrintSection>(
                                value: opt['section'] as ReportPrintSection,
                                groupValue: _selectedSection,
                                activeColor: const Color(0xFF4F46E5),
                                onChanged: (val) {
                                  if (val != null) setState(() => _selectedSection = val);
                                },
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          opt['icon'] as IconData,
                                          size: 16,
                                          color: const Color(0xFF4F46E5),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            opt['title'] as String,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.bold,
                                              color: isDark ? Colors.white : AdminThemeColors.textPrimary,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: (opt['badgeColor'] as Color).withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            opt['badge'] as String,
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w900,
                                              color: opt['badgeColor'] as Color,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      opt['subtitle'] as String,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark ? Colors.white70 : Colors.grey.shade600,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    const SizedBox(height: 8),

                    // Signatures Preview & Edit Shortcut Card
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? Colors.white10 : const Color(0xFFCBD5E1),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.draw_rounded, size: 18, color: Color(0xFF4F46E5)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Report Signatures:',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.reportConfig.signatories.map((s) {
                                    final p = s.label.trim();
                                    final n = s.name.trim();
                                    return p.isNotEmpty && n.isNotEmpty
                                        ? '$p $n'
                                        : (n.isNotEmpty ? n : (p.isNotEmpty ? p : 'Signatory'));
                                  }).join('  •  '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: isDark ? Colors.white70 : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: widget.onEditSignatures,
                            icon: const Icon(Icons.edit_rounded, size: 14),
                            label: const Text('Edit', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF4F46E5),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Modal Footer Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
                border: Border(
                  top: BorderSide(
                    color: isDark ? Colors.white12 : Colors.grey.shade200,
                  ),
                ),
              ),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel', style: TextStyle(fontSize: 12)),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _isExporting
                        ? null
                        : () async {
                            setState(() => _isExporting = true);
                            try {
                              await widget.onExport(_selectedSection);
                            } finally {
                              if (mounted) setState(() => _isExporting = false);
                            }
                          },
                    icon: _isExporting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.print_rounded, size: 16),
                    label: Text(
                      _selectedSection == ReportPrintSection.allSeparatePages
                          ? 'Print All Pages'
                          : 'Print Selected Table',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

