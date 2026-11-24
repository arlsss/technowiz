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
              quizTitle: previewConfig.eventName,
              rank: 1,
              teamName: 'TECHNOWIZ CHAMPIONS',
              members: ['Juan Dela Cruz', 'Maria Santos'],
              school: previewConfig.departmentName,
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

  // =========================================================
  // CERTIFICATE SVG ASSET & VECTOR GENERATORS
  // =========================================================

  String _getCertCornerTopLeftSvg(String navy, String accent) =>
      '''<svg viewBox="0 0 80 80" width="70" height="70">
  <polyline points="3,76 3,3 76,3" fill="none" stroke="$navy" stroke-width="2.5" />
  <polyline points="9,76 9,9 76,9" fill="none" stroke="$accent" stroke-width="1.2" />
  <polyline points="14,76 14,14 76,14" fill="none" stroke="$navy" stroke-width="0.8" />
  <line x1="3" y1="26" x2="26" y2="3" stroke="$accent" stroke-width="1.2" />
  <polygon points="21,13 29,21 21,29 13,21" fill="$accent" stroke="$navy" stroke-width="0.8" />
  <circle cx="21" cy="21" r="2" fill="$navy" />
  <rect x="1.5" y="1.5" width="4.5" height="4.5" fill="$accent" />
</svg>''';

  String _getCertCornerTopRightSvg(String navy, String accent) =>
      '''<svg viewBox="0 0 80 80" width="70" height="70">
  <polyline points="77,76 77,3 4,3" fill="none" stroke="$navy" stroke-width="2.5" />
  <polyline points="71,76 71,9 4,9" fill="none" stroke="$accent" stroke-width="1.2" />
  <polyline points="66,76 66,14 4,14" fill="none" stroke="$navy" stroke-width="0.8" />
  <line x1="77" y1="26" x2="54" y2="3" stroke="$accent" stroke-width="1.2" />
  <polygon points="59,13 67,21 59,29 51,21" fill="$accent" stroke="$navy" stroke-width="0.8" />
  <circle cx="59" cy="21" r="2" fill="$navy" />
  <rect x="74" y="1.5" width="4.5" height="4.5" fill="$accent" />
</svg>''';

  String _getCertCornerBottomLeftSvg(String navy, String accent) =>
      '''<svg viewBox="0 0 80 80" width="70" height="70">
  <polyline points="3,4 3,77 76,77" fill="none" stroke="$navy" stroke-width="2.5" />
  <polyline points="9,4 9,71 76,71" fill="none" stroke="$accent" stroke-width="1.2" />
  <polyline points="14,4 14,66 76,66" fill="none" stroke="$navy" stroke-width="0.8" />
  <line x1="3" y1="54" x2="26" y2="77" stroke="$accent" stroke-width="1.2" />
  <polygon points="21,51 29,59 21,67 13,59" fill="$accent" stroke="$navy" stroke-width="0.8" />
  <circle cx="21" cy="59" r="2" fill="$navy" />
  <rect x="1.5" y="74" width="4.5" height="4.5" fill="$accent" />
</svg>''';

  String _getCertCornerBottomRightSvg(String navy, String accent) =>
      '''<svg viewBox="0 0 80 80" width="70" height="70">
  <polyline points="77,4 77,77 4,77" fill="none" stroke="$navy" stroke-width="2.5" />
  <polyline points="71,4 71,71 4,71" fill="none" stroke="$accent" stroke-width="1.2" />
  <polyline points="66,4 66,66 4,66" fill="none" stroke="$navy" stroke-width="0.8" />
  <line x1="77" y1="54" x2="54" y2="77" stroke="$accent" stroke-width="1.2" />
  <polygon points="59,51 67,59 59,67 51,59" fill="$accent" stroke="$navy" stroke-width="0.8" />
  <circle cx="59" cy="59" r="2" fill="$navy" />
  <rect x="74" y="74" width="4.5" height="4.5" fill="$accent" />
</svg>''';

  String _getCertEdgeTopBottomSvg(String navy, String accent) =>
      '''<svg viewBox="0 0 140 16" width="120" height="14">
  <line x1="0" y1="8" x2="48" y2="8" stroke="$accent" stroke-width="1.2" />
  <circle cx="52" cy="8" r="2" fill="$navy" />
  <polygon points="70,1 78,8 70,15 62,8" fill="$accent" stroke="$navy" stroke-width="0.8" />
  <circle cx="70" cy="8" r="1.5" fill="$navy" />
  <circle cx="88" cy="8" r="2" fill="$navy" />
  <line x1="92" y1="8" x2="140" y2="8" stroke="$accent" stroke-width="1.2" />
</svg>''';

  String _getCertEdgeLeftRightSvg(String navy, String accent) =>
      '''<svg viewBox="0 0 16 140" width="14" height="120">
  <line x1="8" y1="0" x2="8" y2="48" stroke="$accent" stroke-width="1.2" />
  <circle cx="8" cy="52" r="2" fill="$navy" />
  <polygon points="1,70 8,62 15,70 8,78" fill="$accent" stroke="$navy" stroke-width="0.8" />
  <circle cx="8" cy="70" r="1.5" fill="$navy" />
  <circle cx="8" cy="88" r="2" fill="$navy" />
  <line x1="8" y1="92" x2="8" y2="140" stroke="$accent" stroke-width="1.2" />
</svg>''';

  String _getSignatureScribbleSvg(int index, String colorHex) {
    if (index == 0) {
      return '''<svg viewBox="0 0 130 32" width="105" height="26">
        <path d="M 8,24 C 14,10 24,4 30,7 C 36,10 28,26 22,28 C 16,30 32,18 42,16 C 52,14 48,24 58,20 C 68,16 75,10 82,15 C 90,20 98,14 110,18 C 114,20 124,14 126,17" stroke="$colorHex" stroke-width="1.6" fill="none" stroke-linecap="round" stroke-linejoin="round" />
      </svg>''';
    } else if (index == 1) {
      return '''<svg viewBox="0 0 130 32" width="105" height="26">
        <path d="M 16,26 C 18,10 26,5 34,5 C 42,5 38,22 30,24 C 22,26 40,16 52,14 C 64,12 60,26 74,20 C 84,15 82,7 94,12 C 104,17 112,13 124,18" stroke="$colorHex" stroke-width="1.6" fill="none" stroke-linecap="round" stroke-linejoin="round" />
      </svg>''';
    } else {
      return '''<svg viewBox="0 0 130 32" width="105" height="26">
        <path d="M 12,18 C 16,6 28,3 36,10 C 44,17 34,28 26,26 C 18,24 38,16 50,16 C 62,16 68,8 78,15 C 88,22 94,10 106,16 C 116,22 122,14 127,19" stroke="$colorHex" stroke-width="1.6" fill="none" stroke-linecap="round" stroke-linejoin="round" />
      </svg>''';
    }
  }

  pw.Widget _buildPdfSignaturesRow(CertificateConfig config, PdfColor navyColor, String colorHex) {
    final signatories = config.signatories;
    if (signatories.isEmpty) {
      return pw.SizedBox.shrink();
    }

    final int count = signatories.length.clamp(1, 3);
    final double lineWidth = count == 1 ? 220 : (count == 2 ? 180 : 145);

    return pw.Row(
      mainAxisAlignment: count == 1 ? pw.MainAxisAlignment.center : pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        for (int i = 0; i < count; i++) ...[
          pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.SvgImage(
                svg: _getSignatureScribbleSvg(i, colorHex),
                width: lineWidth * 0.72,
                height: 22,
              ),
              pw.SizedBox(height: 2),
              if (signatories[i].name.trim().isNotEmpty) ...[
                pw.Text(
                  signatories[i].name.trim().toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: count == 3 ? 9.5 : 10.5,
                    fontWeight: pw.FontWeight.bold,
                    color: navyColor,
                  ),
                ),
                pw.SizedBox(height: 2),
              ] else ...[
                pw.SizedBox(height: 12),
              ],
              if (signatories[i].showLine)
                pw.Container(width: lineWidth, height: 1.2, color: navyColor)
              else
                pw.SizedBox(width: lineWidth, height: 1.2),
              pw.SizedBox(height: 3),
              pw.Text(
                signatories[i].title.trim().isNotEmpty
                    ? signatories[i].title.trim()
                    : 'Authorized Signatory',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: count == 3 ? 8.5 : 9.5,
                  fontWeight: pw.FontWeight.bold,
                  color: const PdfColor.fromInt(0xFF334155),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _printCertificate({
    required String contestantName,
    required String quizTitle,
    required int rank,
    String teamName = '',
    List<String> members = const [],
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

    final String dateString = quizDate.trim().isNotEmpty ? quizDate.trim() : _dateText();

    pw.MemoryImage? bsitLogoImage;
    try {
      final bytes = await rootBundle.load('assets/images/bsit_logo.png');
      bsitLogoImage = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (e) {
      debugPrint('Error loading bsit_logo asset: $e');
    }

    pw.MemoryImage? robotMascotImage;
    try {
      final bytes = await rootBundle.load('assets/images/technowiz_cert_robot.png');
      robotMascotImage = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (e) {
      debugPrint('Error loading technowiz_cert_robot asset: $e');
    }

    // Rank-based color themes and titles
    final String primaryColorHex;
    final String frameNavyHex;
    final PdfColor navyPdfColor;
    final PdfColor primaryPdfColor;
    final PdfColor topTitlePdfColor;
    final String rankCitationText;
    final String winVerbPhrase;

    if (rank == 1 && !eliminated) {
      // 1ST PLACE - GOLD EDITION
      primaryColorHex = '#D4AF37';
      frameNavyHex = '#0B192C';
      navyPdfColor = const PdfColor.fromInt(0xFF0B192C);
      primaryPdfColor = const PdfColor.fromInt(0xFFB45309);
      topTitlePdfColor = const PdfColor.fromInt(0xFFC59B27);
      rankCitationText = 'RANK 1 (CHAMPION)';
      winVerbPhrase = 'having successfully emerged and won as ';
    } else if (rank == 2 && !eliminated) {
      // 2ND PLACE - SILVER EDITION
      primaryColorHex = '#94A3B8';
      frameNavyHex = '#0F172A';
      navyPdfColor = const PdfColor.fromInt(0xFF0F172A);
      primaryPdfColor = const PdfColor.fromInt(0xFF475569);
      topTitlePdfColor = const PdfColor.fromInt(0xFF64748B);
      rankCitationText = 'RANK 2 (1ST RUNNER-UP)';
      winVerbPhrase = 'having successfully emerged and won as ';
    } else if (rank == 3 && !eliminated) {
      // 3RD PLACE - BRONZE EDITION
      primaryColorHex = '#CD7F32';
      frameNavyHex = '#1E1B18';
      navyPdfColor = const PdfColor.fromInt(0xFF1E1B18);
      primaryPdfColor = const PdfColor.fromInt(0xFF9A3412);
      topTitlePdfColor = const PdfColor.fromInt(0xFFC2410C);
      rankCitationText = 'RANK 3 (2ND RUNNER-UP)';
      winVerbPhrase = 'having successfully emerged and won as ';
    } else {
      // RANK 4+ & PARTICIPANTS - GREEN EDITION
      primaryColorHex = '#10B981';
      frameNavyHex = '#064E3B';
      navyPdfColor = const PdfColor.fromInt(0xFF064E3B);
      primaryPdfColor = const PdfColor.fromInt(0xFF047857);
      topTitlePdfColor = const PdfColor.fromInt(0xFF059669);
      rankCitationText = rank > 0 ? 'RANK $rank' : 'CONTESTANT';
      winVerbPhrase = rank > 0
          ? 'having successfully competed and achieved '
          : 'having actively participated and competed as an official ';
    }

    final cornerTopLeftSvg = _getCertCornerTopLeftSvg(frameNavyHex, primaryColorHex);
    final cornerTopRightSvg = _getCertCornerTopRightSvg(frameNavyHex, primaryColorHex);
    final cornerBottomLeftSvg = _getCertCornerBottomLeftSvg(frameNavyHex, primaryColorHex);
    final cornerBottomRightSvg = _getCertCornerBottomRightSvg(frameNavyHex, primaryColorHex);
    final edgeTopBottomSvg = _getCertEdgeTopBottomSvg(frameNavyHex, primaryColorHex);
    final edgeLeftRightSvg = _getCertEdgeLeftRightSvg(frameNavyHex, primaryColorHex);

    // Build list of recipients:
    // If team with members, each member receives their own personalized certificate with the team name!
    final List<Map<String, String>> recipients = [];
    if (members.isNotEmpty) {
      for (final m in members) {
        if (m.trim().isNotEmpty) {
          recipients.add({
            'name': m.trim(),
            'team': teamName.trim().isNotEmpty ? teamName.trim() : '',
          });
        }
      }
    }
    if (recipients.isEmpty) {
      final effective = teamName.trim().isNotEmpty
          ? teamName.trim()
          : (contestantName.trim().isNotEmpty ? contestantName.trim() : 'Contestant');
      recipients.add({
        'name': effective,
        'team': '',
      });
    }

    for (final r in recipients) {
      final recipientName = r['name']!;
      final teamSubtitle = r['team']!.isNotEmpty ? 'Member of Team: ${r['team']!}' : '';

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
                border: pw.Border.all(color: navyPdfColor, width: 2.2),
              ),
              child: pw.Stack(
                children: [
                  // Inner decorative border
                  pw.Positioned.fill(
                    child: pw.Container(
                      margin: const pw.EdgeInsets.all(6),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: primaryPdfColor, width: 1.2),
                      ),
                    ),
                  ),

                  // 4 Corner Ornaments
                  pw.Positioned(
                    top: 0,
                    left: 0,
                    child: pw.SvgImage(svg: cornerTopLeftSvg, width: 70, height: 70),
                  ),
                  pw.Positioned(
                    top: 0,
                    right: 0,
                    child: pw.SvgImage(svg: cornerTopRightSvg, width: 70, height: 70),
                  ),
                  pw.Positioned(
                    bottom: 0,
                    left: 0,
                    child: pw.SvgImage(svg: cornerBottomLeftSvg, width: 70, height: 70),
                  ),
                  pw.Positioned(
                    bottom: 0,
                    right: 0,
                    child: pw.SvgImage(svg: cornerBottomRightSvg, width: 70, height: 70),
                  ),

                  // Center Edge Ornaments
                  pw.Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: pw.Center(child: pw.SvgImage(svg: edgeTopBottomSvg, width: 120, height: 14)),
                  ),
                  pw.Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: pw.Center(child: pw.SvgImage(svg: edgeTopBottomSvg, width: 120, height: 14)),
                  ),
                  pw.Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: pw.Center(child: pw.SvgImage(svg: edgeLeftRightSvg, width: 14, height: 120)),
                  ),
                  pw.Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: pw.Center(child: pw.SvgImage(svg: edgeLeftRightSvg, width: 14, height: 120)),
                  ),

                  // Center Certificate Content Body
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 20, horizontal: 36),
                    child: pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        // Header Row: BSIT Logo + University Info + TechNoWiz Robot Mascot
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            // Left: BSIT Program Logo (Enlarged & Transparent)
                            pw.Container(
                              width: 92,
                              child: pw.Column(
                                mainAxisSize: pw.MainAxisSize.min,
                                crossAxisAlignment: pw.CrossAxisAlignment.center,
                                children: [
                                  if (bsitLogoImage != null)
                                    pw.Image(bsitLogoImage, width: 75, height: 75, fit: pw.BoxFit.contain)
                                  else
                                    pw.Container(width: 75, height: 75),
                                  pw.SizedBox(height: 2),
                                  pw.Text(
                                    'BSIT Program Logo',
                                    style: const pw.TextStyle(
                                      fontSize: 7.5,
                                      color: PdfColor.fromInt(0xFF475569),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Center: University, Campus, Department
                            pw.Expanded(
                              child: pw.Column(
                                mainAxisSize: pw.MainAxisSize.min,
                                crossAxisAlignment: pw.CrossAxisAlignment.center,
                                children: [
                                  pw.Text(
                                    config.universityName.trim().isNotEmpty
                                        ? config.universityName.trim().toUpperCase()
                                        : 'CEBU TECHNOLOGICAL UNIVERSITY',
                                    textAlign: pw.TextAlign.center,
                                    style: pw.TextStyle(
                                      fontSize: 15,
                                      fontWeight: pw.FontWeight.bold,
                                      letterSpacing: 1.5,
                                      color: navyPdfColor,
                                    ),
                                  ),
                                  pw.SizedBox(height: 2),
                                  pw.Text(
                                    config.campusName.trim().isNotEmpty
                                        ? config.campusName.trim().toUpperCase()
                                        : 'TUBURAN & TABUELAN CAMPUSES',
                                    textAlign: pw.TextAlign.center,
                                    style: const pw.TextStyle(
                                      fontSize: 9,
                                      fontWeight: pw.FontWeight.bold,
                                      letterSpacing: 1.2,
                                      color: PdfColor.fromInt(0xFF334155),
                                    ),
                                  ),
                                  pw.SizedBox(height: 2),
                                  pw.Text(
                                    config.departmentName.trim().isNotEmpty
                                        ? config.departmentName.trim().toUpperCase()
                                        : 'BACHELOR OF SCIENCE IN INFORMATION TECHNOLOGY',
                                    textAlign: pw.TextAlign.center,
                                    style: pw.TextStyle(
                                      fontSize: 10,
                                      fontWeight: pw.FontWeight.bold,
                                      letterSpacing: 1.2,
                                      color: primaryPdfColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Right: TechNoWiz Mascot Robot with Trophy (Enlarged & Transparent)
                            pw.Container(
                              width: 92,
                              child: pw.Column(
                                mainAxisSize: pw.MainAxisSize.min,
                                crossAxisAlignment: pw.CrossAxisAlignment.center,
                                children: [
                                  if (robotMascotImage != null)
                                    pw.Image(robotMascotImage, width: 78, height: 75, fit: pw.BoxFit.contain)
                                  else
                                    pw.Container(width: 78, height: 75),
                                  pw.SizedBox(height: 2),
                                  pw.Text(
                                    'TechNoWiz',
                                    style: pw.TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: pw.FontWeight.bold,
                                      color: const PdfColor.fromInt(0xFF0284C7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        // Title Section: Top Yellow/Accent text + Bottom Black/Navy text + Subtitle (Separated vertically, no overlap)
                        pw.Column(
                          mainAxisSize: pw.MainAxisSize.min,
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            pw.Text(
                              config.certificateWatermark.trim().isNotEmpty
                                  ? config.certificateWatermark.trim().toUpperCase()
                                  : 'CERTIFICATE',
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(
                                fontSize: 26,
                                fontWeight: pw.FontWeight.bold,
                                letterSpacing: 5.0,
                                color: topTitlePdfColor,
                              ),
                            ),
                            pw.SizedBox(height: 3),
                            pw.Text(
                              config.certificateTitle.trim().isNotEmpty
                                  ? config.certificateTitle.trim().toUpperCase()
                                  : 'CERTIFICATE OF RECOGNITION',
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(
                                fontSize: 18,
                                fontWeight: pw.FontWeight.bold,
                                letterSpacing: 2.0,
                                color: navyPdfColor,
                              ),
                            ),
                            pw.SizedBox(height: 5),
                            pw.Text(
                              config.certificateSubtitle.trim().isNotEmpty
                                  ? config.certificateSubtitle.trim()
                                  : 'This certificate is proudly presented to',
                              style: const pw.TextStyle(
                                fontSize: 10.5,
                                fontStyle: pw.FontStyle.italic,
                                color: PdfColor.fromInt(0xFF334155),
                              ),
                            ),
                          ],
                        ),

                        // Contestant / Member Name & Details
                        pw.Column(
                          mainAxisSize: pw.MainAxisSize.min,
                          children: [
                            pw.Text(
                              recipientName.toUpperCase(),
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(
                                fontSize: 23,
                                fontWeight: pw.FontWeight.bold,
                                letterSpacing: 1.5,
                                color: navyPdfColor,
                              ),
                            ),
                            if (teamSubtitle.isNotEmpty) ...[
                              pw.SizedBox(height: 2),
                              pw.Text(
                                teamSubtitle,
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: pw.FontWeight.bold,
                                  color: primaryPdfColor,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                            if (school.trim().isNotEmpty) ...[
                              pw.SizedBox(height: 2),
                              pw.Text(
                                school.trim().toUpperCase(),
                                textAlign: pw.TextAlign.center,
                                style: const pw.TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColor.fromInt(0xFF64748B),
                                ),
                              ),
                            ],
                            pw.SizedBox(height: 4),
                            pw.Container(
                              width: 400,
                              height: 1.2,
                              color: navyPdfColor,
                            ),
                          ],
                        ),

                        // Citation Statement (Full, formal academic citation)
                        pw.Container(
                          width: 610,
                          child: pw.RichText(
                            textAlign: pw.TextAlign.center,
                            text: pw.TextSpan(
                              style: const pw.TextStyle(
                                fontSize: 10,
                                color: PdfColor.fromInt(0xFF1E293B),
                                lineSpacing: 2.6,
                              ),
                              children: [
                                const pw.TextSpan(
                                  text:
                                      'in high recognition of their exemplary brilliance, intellectual competence, and outstanding competitive performance, ',
                                ),
                                pw.TextSpan(text: winVerbPhrase),
                                pw.TextSpan(
                                  text: rankCitationText,
                                  style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold,
                                    color: navyPdfColor,
                                  ),
                                ),
                                pw.TextSpan(
                                  text:
                                      ' in the ${config.eventName.trim()} during the ${config.occasionName.trim()}, held on $dateString, at ${config.venue.trim().isNotEmpty ? config.venue.trim() : "BSIT Building"}.',
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Signatures: 3 Signatories with Scribbles & Lines
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 20),
                          child: _buildPdfSignaturesRow(config, navyPdfColor, frameNavyHex),
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
    }

    if (printAfter) {
      final safeName = (teamName.isNotEmpty ? teamName : contestantName)
          .replaceAll(' ', '_')
          .replaceAll(RegExp(r'[^\w\.-]'), '');
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
        members: c.members,
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
          '3. CONTESTANT RECORDS DIRECTORY',
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
              'No contestant records found for this quiz.',
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

      // Table 3 Page (Contestant Records Directory)
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (context) => buildPdfHeader(context, sectionTitle: 'Contestant Records Directory'),
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
          header: (context) => buildPdfHeader(context, sectionTitle: 'Contestant Records Directory'),
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
      ReportPrintSection.participantRecordsOnly => 'TechNoWiz_Contestant_Records_$quizCode.pdf',
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
                    'Contestant records, score summaries & final rankings.',
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
      {'key': 'participants', 'label': 'Contestant Records', 'icon': Icons.people_alt_rounded, 'count': participantCount},
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
              members: c.members,
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
                    hintText: 'Search contestant by name or school...',
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
            title: 'No Contestant Records Found',
            subtitle: 'No contestants match the search query.',
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
            'Please pick a quiz competition session above to inspect contestant records, score summaries, and final rankings.',
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
  String universityName;
  String campusName;
  String departmentName;
  String certificateWatermark;
  String certificateTitle;
  String certificateSubtitle;
  String eventName;
  String occasionName;
  String venue;
  List<CertificateSignatory> signatories;

  CertificateConfig({
    this.universityName = 'CEBU TECHNOLOGICAL UNIVERSITY',
    this.campusName = 'TUBURAN & TABUELAN CAMPUSES',
    this.departmentName = 'BACHELOR OF SCIENCE IN INFORMATION TECHNOLOGY',
    this.certificateWatermark = 'CERTIFICATE',
    this.certificateTitle = 'CERTIFICATE OF RECOGNITION',
    this.certificateSubtitle = 'This certificate is proudly presented to',
    this.eventName = 'TechNoWiz Quiz Competition',
    this.occasionName = 'Information Technology Days',
    this.venue = 'BSIT Building',
    required this.signatories,
  });

  static CertificateConfig defaultTemplate() => CertificateConfig(
        universityName: 'CEBU TECHNOLOGICAL UNIVERSITY',
        campusName: 'TUBURAN & TABUELAN CAMPUSES',
        departmentName: 'BACHELOR OF SCIENCE IN INFORMATION TECHNOLOGY',
        certificateWatermark: 'CERTIFICATE',
        certificateTitle: 'CERTIFICATE OF RECOGNITION',
        certificateSubtitle: 'This certificate is proudly presented to',
        eventName: 'TechNoWiz Quiz Competition',
        occasionName: 'Information Technology Days',
        venue: 'BSIT Building',
        signatories: [
          CertificateSignatory(
            name: '',
            title: 'Quiz Master / Event Facilitator',
            showLine: true,
          ),
          CertificateSignatory(
            name: '',
            title: 'Department Chairperson',
            showLine: true,
          ),
          CertificateSignatory(
            name: '',
            title: 'College Dean / Campus Director',
            showLine: true,
          ),
        ],
      );

  Map<String, dynamic> toMap() => {
        'universityName': universityName,
        'campusName': campusName,
        'departmentName': departmentName,
        'certificateWatermark': certificateWatermark,
        'certificateTitle': certificateTitle,
        'certificateSubtitle': certificateSubtitle,
        'eventName': eventName,
        'occasionName': occasionName,
        'venue': venue,
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
      universityName:
          (map['universityName'] ?? 'CEBU TECHNOLOGICAL UNIVERSITY').toString(),
      campusName:
          (map['campusName'] ?? 'TUBURAN & TABUELAN CAMPUSES').toString(),
      departmentName:
          (map['departmentName'] ?? 'BACHELOR OF SCIENCE IN INFORMATION TECHNOLOGY')
              .toString(),
      certificateWatermark:
          (map['certificateWatermark'] ?? 'CERTIFICATE').toString(),
      certificateTitle:
          (map['certificateTitle'] ?? 'CERTIFICATE OF RECOGNITION').toString(),
      certificateSubtitle:
          (map['certificateSubtitle'] ?? 'This certificate is proudly presented to')
              .toString(),
      eventName:
          (map['eventName'] ?? 'TechNoWiz Quiz Competition').toString(),
      occasionName:
          (map['occasionName'] ?? 'Information Technology Days').toString(),
      venue: (map['venue'] ?? 'BSIT Building').toString(),
      signatories: sigs,
    );
  }
}

// ============================================================================
// CERTIFICATE PREVIEW CUSTOM PAINTERS (CORNER ORNAMENTS & SIGNATURE SCRIBBLES)
// ============================================================================

class _CertificateCornerPainter extends CustomPainter {
  final Color navy;
  final Color gold;
  const _CertificateCornerPainter({required this.navy, required this.gold});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final navyPaint = Paint()
      ..color = navy
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    final goldPaint = Paint()
      ..color = gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final goldFill = Paint()
      ..color = gold
      ..style = PaintingStyle.fill;

    // Corner 1: Top-Left
    _drawCorner(canvas, 0, 0, 1, 1, navyPaint, goldPaint, goldFill);
    // Corner 2: Top-Right
    _drawCorner(canvas, w, 0, -1, 1, navyPaint, goldPaint, goldFill);
    // Corner 3: Bottom-Left
    _drawCorner(canvas, 0, h, 1, -1, navyPaint, goldPaint, goldFill);
    // Corner 4: Bottom-Right
    _drawCorner(canvas, w, h, -1, -1, navyPaint, goldPaint, goldFill);
  }

  void _drawCorner(
    Canvas canvas,
    double x,
    double y,
    double sx,
    double sy,
    Paint navy,
    Paint gold,
    Paint goldFill,
  ) {
    // Outer Corner L-line
    final p1 = Path()
      ..moveTo(x + 3 * sx, y + 26 * sy)
      ..lineTo(x + 3 * sx, y + 3 * sy)
      ..lineTo(x + 26 * sx, y + 3 * sy);
    canvas.drawPath(p1, navy);

    // Inner Corner L-line
    final p2 = Path()
      ..moveTo(x + 7 * sx, y + 20 * sy)
      ..lineTo(x + 7 * sx, y + 7 * sy)
      ..lineTo(x + 20 * sx, y + 7 * sy);
    canvas.drawPath(p2, gold);

    // Diagonal geometric connector
    final p3 = Path()
      ..moveTo(x + 7 * sx, y + 7 * sy)
      ..lineTo(x + 16 * sx, y + 16 * sy);
    canvas.drawPath(p3, gold);

    // Corner accent diamond
    final diamond = Path()
      ..moveTo(x + 12 * sx, y + 9 * sy)
      ..lineTo(x + 15 * sx, y + 12 * sy)
      ..lineTo(x + 12 * sx, y + 15 * sy)
      ..lineTo(x + 9 * sx, y + 12 * sy)
      ..close();
    canvas.drawPath(diamond, goldFill);
  }

  @override
  bool shouldRepaint(covariant _CertificateCornerPainter oldDelegate) => false;
}

class _SignatureScribblePainter extends CustomPainter {
  final int index;
  final Color color;
  const _SignatureScribblePainter({required this.index, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    if (index == 0) {
      path.moveTo(size.width * 0.1, size.height * 0.7);
      path.cubicTo(size.width * 0.2, size.height * 0.2, size.width * 0.3, size.height * 0.1, size.width * 0.38, size.height * 0.3);
      path.cubicTo(size.width * 0.45, size.height * 0.5, size.width * 0.35, size.height * 0.8, size.width * 0.28, size.height * 0.85);
      path.cubicTo(size.width * 0.4, size.height * 0.5, size.width * 0.6, size.height * 0.4, size.width * 0.7, size.height * 0.6);
      path.cubicTo(size.width * 0.8, size.height * 0.3, size.width * 0.9, size.height * 0.5, size.width * 0.95, size.height * 0.55);
    } else if (index == 1) {
      path.moveTo(size.width * 0.15, size.height * 0.8);
      path.cubicTo(size.width * 0.2, size.height * 0.2, size.width * 0.35, size.height * 0.1, size.width * 0.45, size.height * 0.2);
      path.cubicTo(size.width * 0.5, size.height * 0.3, size.width * 0.4, size.height * 0.8, size.width * 0.35, size.height * 0.8);
      path.cubicTo(size.width * 0.5, size.height * 0.4, size.width * 0.65, size.height * 0.5, size.width * 0.8, size.height * 0.3);
      path.cubicTo(size.width * 0.88, size.height * 0.6, size.width * 0.92, size.height * 0.4, size.width * 0.96, size.height * 0.6);
    } else {
      path.moveTo(size.width * 0.1, size.height * 0.6);
      path.cubicTo(size.width * 0.25, size.height * 0.1, size.width * 0.35, size.height * 0.2, size.width * 0.4, size.height * 0.7);
      path.cubicTo(size.width * 0.35, size.height * 0.9, size.width * 0.5, size.height * 0.5, size.width * 0.6, size.height * 0.4);
      path.cubicTo(size.width * 0.7, size.height * 0.3, size.width * 0.75, size.height * 0.7, size.width * 0.85, size.height * 0.5);
      path.cubicTo(size.width * 0.9, size.height * 0.4, size.width * 0.95, size.height * 0.6, size.width * 0.98, size.height * 0.5);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SignatureScribblePainter oldDelegate) =>
      oldDelegate.index != index || oldDelegate.color != color;
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
  late final TextEditingController _univController;
  late final TextEditingController _campusController;
  late final TextEditingController _deptController;
  late final TextEditingController _watermarkController;
  late final TextEditingController _titleController;
  late final TextEditingController _subtitleController;
  late final TextEditingController _eventController;
  late final TextEditingController _occasionController;
  late final TextEditingController _venueController;

  int _signatoryCount = 3;
  late final List<TextEditingController> _nameControllers;
  late final List<TextEditingController> _titleControllers;
  late final List<bool> _showLines;
  bool _isSaving = false;
  bool _isPreviewing = false;

  @override
  void initState() {
    super.initState();
    final c = widget.initialConfig;
    _univController = TextEditingController(text: c.universityName);
    _campusController = TextEditingController(text: c.campusName);
    _deptController = TextEditingController(text: c.departmentName);
    _watermarkController = TextEditingController(text: c.certificateWatermark);
    _titleController = TextEditingController(text: c.certificateTitle);
    _subtitleController = TextEditingController(text: c.certificateSubtitle);
    _eventController = TextEditingController(text: c.eventName);
    _occasionController = TextEditingController(text: c.occasionName);
    _venueController = TextEditingController(text: c.venue);

    final sigs = c.signatories;
    _signatoryCount = sigs.length.clamp(1, 3);

    _nameControllers = List.generate(3, (i) {
      final text = i < sigs.length ? sigs[i].name : '';
      return TextEditingController(text: text);
    });

    _titleControllers = List.generate(3, (i) {
      if (i < sigs.length) return TextEditingController(text: sigs[i].title);
      if (i == 0) return TextEditingController(text: 'Quiz Master / Event Facilitator');
      if (i == 1) return TextEditingController(text: 'Department Chairperson');
      return TextEditingController(text: 'College Dean / Campus Director');
    });

    _showLines = List.generate(3, (i) {
      if (i < sigs.length) return sigs[i].showLine;
      return true;
    });

    _univController.addListener(_refresh);
    _campusController.addListener(_refresh);
    _deptController.addListener(_refresh);
    _watermarkController.addListener(_refresh);
    _titleController.addListener(_refresh);
    _subtitleController.addListener(_refresh);
    _eventController.addListener(_refresh);
    _occasionController.addListener(_refresh);
    _venueController.addListener(_refresh);
    for (final ctrl in _nameControllers) {
      ctrl.addListener(_refresh);
    }
    for (final ctrl in _titleControllers) {
      ctrl.addListener(_refresh);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _univController.dispose();
    _campusController.dispose();
    _deptController.dispose();
    _watermarkController.dispose();
    _titleController.dispose();
    _subtitleController.dispose();
    _eventController.dispose();
    _occasionController.dispose();
    _venueController.dispose();
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
                  ? 'Quiz Master / Event Facilitator'
                  : (i == 1 ? 'Department Chairperson' : 'College Dean / Campus Director')),
          showLine: _showLines[i],
        ),
      );
    }

    return CertificateConfig(
      universityName: _univController.text.trim().isNotEmpty
          ? _univController.text.trim()
          : 'CEBU TECHNOLOGICAL UNIVERSITY',
      campusName: _campusController.text.trim().isNotEmpty
          ? _campusController.text.trim()
          : 'TUBURAN & TABUELAN CAMPUSES',
      departmentName: _deptController.text.trim().isNotEmpty
          ? _deptController.text.trim()
          : 'BACHELOR OF SCIENCE IN INFORMATION TECHNOLOGY',
      certificateWatermark: _watermarkController.text.trim().isNotEmpty
          ? _watermarkController.text.trim()
          : 'CERTIFICATE',
      certificateTitle: _titleController.text.trim().isNotEmpty
          ? _titleController.text.trim()
          : 'CERTIFICATE OF RECOGNITION',
      certificateSubtitle: _subtitleController.text.trim().isNotEmpty
          ? _subtitleController.text.trim()
          : 'This certificate is proudly presented to',
      eventName: _eventController.text.trim().isNotEmpty
          ? _eventController.text.trim()
          : 'TechNoWiz Quiz Competition',
      occasionName: _occasionController.text.trim().isNotEmpty
          ? _occasionController.text.trim()
          : 'Information Technology Days',
      venue: _venueController.text.trim().isNotEmpty
          ? _venueController.text.trim()
          : 'BSIT Building',
      signatories: activeSignatories,
    );
  }

  void _resetToDefault() {
    final def = CertificateConfig.defaultTemplate();
    _univController.text = def.universityName;
    _campusController.text = def.campusName;
    _deptController.text = def.departmentName;
    _watermarkController.text = def.certificateWatermark;
    _titleController.text = def.certificateTitle;
    _subtitleController.text = def.certificateSubtitle;
    _eventController.text = def.eventName;
    _occasionController.text = def.occasionName;
    _venueController.text = def.venue;
    _signatoryCount = 3;

    for (int i = 0; i < 3; i++) {
      _nameControllers[i].text = def.signatories[i].name;
      _titleControllers[i].text = def.signatories[i].title;
      _showLines[i] = def.signatories[i].showLine;
    }

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
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
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
                          'Manage Certificate & Layout',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Customize institutional header, titles, event info, and signatures',
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
                    // Section 1: Institutional Header
                    _buildSectionHeader('INSTITUTIONAL HEADER & DEPARTMENT', isDark),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _univController,
                      decoration: InputDecoration(
                        labelText: 'University / Institution Name',
                        hintText: 'e.g. CEBU TECHNOLOGICAL UNIVERSITY',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _campusController,
                      decoration: InputDecoration(
                        labelText: 'Campuses',
                        hintText: 'e.g. TUBURAN & TABUELAN CAMPUSES',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _deptController,
                      decoration: InputDecoration(
                        labelText: 'Program / Department',
                        hintText: 'e.g. BACHELOR OF SCIENCE IN INFORMATION TECHNOLOGY',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 18),

                    // Section 2: Certificate Titles
                    _buildSectionHeader('CERTIFICATE TITLES & PRESENTATION', isDark),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _watermarkController,
                      decoration: InputDecoration(
                        labelText: 'Top Title Text (Yellow / Gold Accent)',
                        hintText: 'e.g. CERTIFICATE',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        labelText: 'Main Certificate Title (Black / Navy)',
                        hintText: 'e.g. CERTIFICATE OF RECOGNITION',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _subtitleController,
                      decoration: InputDecoration(
                        labelText: 'Presentation Subtitle',
                        hintText: 'e.g. This certificate is proudly presented to',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 18),

                    // Section 3: Event & Citation Details
                    _buildSectionHeader('EVENT & OCCASION DETAILS (CITATION)', isDark),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _eventController,
                      decoration: InputDecoration(
                        labelText: 'Event / Competition Name',
                        hintText: 'e.g. TechNoWiz Quiz Competition',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _occasionController,
                      decoration: InputDecoration(
                        labelText: 'Occasion / Celebration',
                        hintText: 'e.g. Information Technology Days',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _venueController,
                      decoration: InputDecoration(
                        labelText: 'Venue / School Location',
                        hintText: 'e.g. BSIT Building',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 18),

                    // Section 4: Number of Signatories & Signatory Cards
                    _buildSectionHeader('AUTHORIZED SIGNATORIES', isDark),
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
                    const SizedBox(height: 14),

                    for (int i = 0; i < _signatoryCount; i++) ...[
                      _buildSignatoryEditorCard(i, isDark),
                      const SizedBox(height: 12),
                    ],

                    const SizedBox(height: 10),

                    // Section 5: Real-time In-App Visual Preview (Exact replica of printed certificate)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildSectionHeader('REAL-TIME CERTIFICATE PREVIEW', isDark),
                        ElevatedButton.icon(
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
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.print_rounded, size: 15),
                          label: const Text(
                            'Open Full Print PDF',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Exact Certificate Replica Container with authentic triple border & corners
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: const Color(0xFF0B192C), width: 3.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Container(
                        margin: const EdgeInsets.all(3.5),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFD4AF37), width: 1.5),
                        ),
                        child: Container(
                          margin: const EdgeInsets.all(2.5),
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFF0B192C), width: 0.8),
                          ),
                          child: CustomPaint(
                            foregroundPainter: const _CertificateCornerPainter(
                              navy: Color(0xFF0B192C),
                              gold: Color(0xFFD4AF37),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                              child: Column(
                                children: [
                                  // Header Row: BSIT Logo + University Info + TechNoWiz Robot Mascot
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      // Left: BSIT Program Logo
                                      SizedBox(
                                        width: 72,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Image.asset(
                                              'assets/images/bsit_logo.png',
                                              width: 52,
                                              height: 52,
                                              fit: BoxFit.contain,
                                              errorBuilder: (_, __, ___) => const SizedBox(width: 52, height: 52),
                                            ),
                                            const SizedBox(height: 2),
                                            const Text(
                                              'BSIT Program Logo',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 7,
                                                color: Color(0xFF475569),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Center: University, Campus, Department
                                      Expanded(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Text(
                                              _univController.text.trim().isNotEmpty
                                                  ? _univController.text.trim().toUpperCase()
                                                  : 'CEBU TECHNOLOGICAL UNIVERSITY',
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                color: Color(0xFF0B192C),
                                                fontWeight: FontWeight.w900,
                                                fontSize: 12.5,
                                                letterSpacing: 1.3,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              _campusController.text.trim().isNotEmpty
                                                  ? _campusController.text.trim().toUpperCase()
                                                  : 'TUBURAN & TABUELAN CAMPUSES',
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                color: Color(0xFF475569),
                                                fontWeight: FontWeight.w700,
                                                fontSize: 8,
                                                letterSpacing: 1.0,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              _deptController.text.trim().isNotEmpty
                                                  ? _deptController.text.trim().toUpperCase()
                                                  : 'BACHELOR OF SCIENCE IN INFORMATION TECHNOLOGY',
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                color: Color(0xFFB45309),
                                                fontWeight: FontWeight.w800,
                                                fontSize: 8.8,
                                                letterSpacing: 0.8,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Right: TechNoWiz Mascot Robot
                                      SizedBox(
                                        width: 72,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Image.asset(
                                              'assets/images/technowiz_cert_robot.png',
                                              width: 55,
                                              height: 52,
                                              fit: BoxFit.contain,
                                              errorBuilder: (_, __, ___) => const SizedBox(width: 55, height: 52),
                                            ),
                                            const SizedBox(height: 2),
                                            const Text(
                                              'TechNoWiz',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 8,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF0284C7),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),

                                  // Title Section: Top Yellow/Gold text + Bottom Black/Navy text (Separated vertically)
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        _watermarkController.text.trim().isNotEmpty
                                            ? _watermarkController.text.trim().toUpperCase()
                                            : 'CERTIFICATE',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Color(0xFFC59B27),
                                          fontWeight: FontWeight.w900,
                                          fontSize: 19,
                                          letterSpacing: 4.5,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        _titleController.text.trim().isNotEmpty
                                            ? _titleController.text.trim().toUpperCase()
                                            : 'CERTIFICATE OF RECOGNITION',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Color(0xFF0B192C),
                                          fontWeight: FontWeight.w900,
                                          fontSize: 13.5,
                                          letterSpacing: 1.8,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    _subtitleController.text.trim().isNotEmpty
                                        ? _subtitleController.text.trim()
                                        : 'This certificate is proudly presented to',
                                    style: const TextStyle(
                                      color: Color(0xFF475569),
                                      fontSize: 9.5,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  // Sample Contestant Name
                                  const Text(
                                    'CONTESTANT / TEAM MEMBER NAME',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF0B192C),
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Container(width: 260, height: 1.2, color: const Color(0xFF0B192C)),
                                  const SizedBox(height: 14),

                                  // Citation preview (Full academic sentence with bold rank)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 14),
                                    child: RichText(
                                      textAlign: TextAlign.center,
                                      text: TextSpan(
                                        style: const TextStyle(
                                          fontSize: 9,
                                          color: Color(0xFF1E293B),
                                          height: 1.4,
                                        ),
                                        children: [
                                          const TextSpan(
                                            text:
                                                'in high recognition of their exemplary brilliance, intellectual competence, and outstanding competitive performance, having successfully emerged and won as ',
                                          ),
                                          const TextSpan(
                                            text: 'RANK 1 (CHAMPION)',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              color: Color(0xFF0F172A),
                                            ),
                                          ),
                                          TextSpan(
                                            text:
                                                ' in the ${_eventController.text.trim()} during the ${_occasionController.text.trim()}, held on [Date of Event], at ${_venueController.text.trim()}.',
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 18),

                                  // Live Signatures Row Preview with Scribble Signatures
                                  Row(
                                    mainAxisAlignment: _signatoryCount == 1
                                        ? MainAxisAlignment.center
                                        : MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      for (int i = 0; i < _signatoryCount; i++) ...[
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 6),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                // Authentic signature cursive scribble
                                                SizedBox(
                                                  height: 22,
                                                  width: 80,
                                                  child: CustomPaint(
                                                    painter: _SignatureScribblePainter(
                                                      index: i,
                                                      color: const Color(0xFF0B192C),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                if (_showLines[i])
                                                  Container(
                                                    height: 1.2,
                                                    color: const Color(0xFF0B192C),
                                                    margin: const EdgeInsets.symmetric(horizontal: 4),
                                                  )
                                                else
                                                  const SizedBox(height: 1.2),
                                                const SizedBox(height: 3),
                                                Text(
                                                  _nameControllers[i].text.trim().isNotEmpty
                                                      ? _nameControllers[i].text.trim().toUpperCase()
                                                      : 'AUTHORIZED SIGNATORY',
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    fontSize: 8.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: Color(0xFF0B192C),
                                                  ),
                                                ),
                                                const SizedBox(height: 1),
                                                Text(
                                                  _titleControllers[i].text.trim().isNotEmpty
                                                      ? _titleControllers[i].text.trim()
                                                      : 'Designation',
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    fontSize: 7.5,
                                                    color: Color(0xFF64748B),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
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

  Widget _buildSectionHeader(String title, bool isDark) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        color: isDark ? Colors.white70 : AdminThemeColors.textSecondary,
      ),
    );
  }

  Widget _buildSignatoryEditorCard(int index, bool isDark) {
    final positionLabel = index == 0
        ? 'Signatory 1 (Left / Quiz Master)'
        : (index == 1
            ? 'Signatory 2 (Center / Chairperson)'
            : 'Signatory 3 (Right / Dean & Director)');

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
              hintText: 'e.g. Quiz Master / Chairperson / Dean',
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

                    // Real-time Report Document Preview
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.description_rounded, size: 16, color: Color(0xFF4F46E5)),
                            SizedBox(width: 6),
                            Text(
                              'REAL-TIME REPORT DOCUMENT PREVIEW',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Live Page Replica',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF4F46E5),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Realistic Official Report Sheet Container
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 1. Official Report Document Header
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text(
                                    'TECHNOWIZ COMPETITION SYSTEM',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF581C87),
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Official Session Report & Documentation',
                                    style: TextStyle(
                                      fontSize: 8.5,
                                      color: Color(0xFF64748B),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'Generated: ${_todayDateText()}',
                                    style: const TextStyle(
                                      fontSize: 8,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    'Quiz Code: ${widget.quizCode}',
                                    style: const TextStyle(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF581C87),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            height: 2,
                            color: const Color(0xFF6B21A8),
                          ),
                          const SizedBox(height: 10),

                          // 2. Event Info Box
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'QUIZ TIME!!',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Date: ${_todayDateText()}',
                                        style: const TextStyle(fontSize: 8, color: Color(0xFF475569)),
                                      ),
                                    ),
                                    const Expanded(
                                      child: Text(
                                        'Location: BSIT BUILDING',
                                        style: TextStyle(fontSize: 8, color: Color(0xFF475569)),
                                      ),
                                    ),
                                    Expanded(
                                      child: Row(
                                        children: const [
                                          Text(
                                            'Status: ',
                                            style: TextStyle(fontSize: 8, color: Color(0xFF475569)),
                                          ),
                                          Text(
                                            'FINISHED',
                                            style: TextStyle(
                                              fontSize: 8,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF15803D),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 3. Score Summary Mini Table
                          const Text(
                            '1. SCORE SUMMARY & STATISTICS',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF581C87),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                                  color: const Color(0xFF4C1D95),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                                    children: const [
                                      Text('Total Contestants', style: TextStyle(fontSize: 7.5, color: Colors.white, fontWeight: FontWeight.bold)),
                                      Text('Active / Completed', style: TextStyle(fontSize: 7.5, color: Colors.white, fontWeight: FontWeight.bold)),
                                      Text('Eliminated', style: TextStyle(fontSize: 7.5, color: Colors.white, fontWeight: FontWeight.bold)),
                                      Text('Top Score', style: TextStyle(fontSize: 7.5, color: Colors.white, fontWeight: FontWeight.bold)),
                                      Text('Average Score', style: TextStyle(fontSize: 7.5, color: Colors.white, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                                  color: Colors.white,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                                    children: const [
                                      Text('3', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                                      Text('3', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                                      Text('0', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                                      Text('12 pts', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                                      Text('9.7 pts', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 4. Final Standings Mini Table
                          const Text(
                            '2. FINAL STANDINGS & RANKINGS',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF581C87),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                  color: const Color(0xFF4C1D95),
                                  child: Row(
                                    children: const [
                                      SizedBox(width: 32, child: Text('Rank', style: TextStyle(fontSize: 7.5, color: Colors.white, fontWeight: FontWeight.bold))),
                                      Expanded(child: Text('Contestant Name', style: TextStyle(fontSize: 7.5, color: Colors.white, fontWeight: FontWeight.bold))),
                                      SizedBox(width: 50, child: Text('Score', style: TextStyle(fontSize: 7.5, color: Colors.white, fontWeight: FontWeight.bold))),
                                      SizedBox(width: 70, child: Text('Award / Status', style: TextStyle(fontSize: 7.5, color: Colors.white, fontWeight: FontWeight.bold))),
                                    ],
                                  ),
                                ),
                                _buildPreviewStandingRow('1', 'TECHNOWIZ BABIES', '12 pts', 'Champion', true),
                                _buildPreviewStandingRow('2', 'KULAFU BOYS', '10 pts', '1st Runner-Up', false),
                                _buildPreviewStandingRow('3', 'Rhealyn Legaspino', '7 pts', '2nd Runner-Up', true),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),

                          // 5. Official Signatures Section (Live updating with form fields)
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
                                          width: _signatoryCount == 1 ? 180 : 130,
                                          height: 1.2,
                                          color: const Color(0xFF0F172A),
                                        )
                                      else
                                        const SizedBox(height: 1.2),
                                      const SizedBox(height: 4),
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
                                        style: const TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      Text(
                                        _titleControllers[i].text.trim().isNotEmpty
                                            ? _titleControllers[i].text.trim()
                                            : 'Title / Designation',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 8,
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (i < _signatoryCount - 1) const SizedBox(width: 14),
                              ],
                            ],
                          ),
                          const SizedBox(height: 16),

                          // 6. Report Footer
                          Container(
                            padding: const EdgeInsets.only(top: 6),
                            decoration: const BoxDecoration(
                              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: const [
                                Text(
                                  'TechNoWiz - System Generated Official Document',
                                  style: TextStyle(fontSize: 7, color: Color(0xFF94A3B8)),
                                ),
                                Text(
                                  'Page 1 of 1',
                                  style: TextStyle(fontSize: 7, color: Color(0xFF94A3B8)),
                                ),
                              ],
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

  String _todayDateText() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
  }

  Widget _buildPreviewStandingRow(String rank, String name, String score, String award, bool isStripe) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 3.5, horizontal: 8),
      color: isStripe ? const Color(0xFFF8FAFC) : Colors.white,
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              rank,
              style: const TextStyle(fontSize: 7.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            ),
          ),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontSize: 7.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              score,
              style: const TextStyle(fontSize: 7.5, fontWeight: FontWeight.bold, color: Color(0xFF581C87)),
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              award,
              style: TextStyle(
                fontSize: 7.5,
                fontWeight: FontWeight.bold,
                color: rank == '1' ? const Color(0xFFB45309) : const Color(0xFF475569),
              ),
            ),
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
        'subtitle': 'Prints Table 1 (Score Summary), Table 2 (Final Standings), and Table 3 (Contestant Directory) each on its own clean, dedicated page with official header and signatures.',
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
        'title': 'Table 3: Contestant Records Directory',
        'subtitle': 'Prints full directory of registered contestants and teams, student members, school names, and competition status.',
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
                              Container(
                                width: 20,
                                height: 20,
                                margin: const EdgeInsets.only(top: 2, right: 8),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _selectedSection == opt['section']
                                        ? const Color(0xFF4F46E5)
                                        : (isDark ? Colors.white38 : Colors.grey.shade400),
                                    width: 2,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: _selectedSection == opt['section']
                                    ? Container(
                                        width: 10,
                                        height: 10,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Color(0xFF4F46E5),
                                        ),
                                      )
                                    : null,
                              ),
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

