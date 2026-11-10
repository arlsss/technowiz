import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Unified TechNoWiz Quiz Master Blue Cyber-Circuit Theme & Brand Components
/// Provides a cohesive, high-tech command center aesthetic across all
/// Quiz Master screens.

class QuizMasterColors {
  // Primary brand blues
  static const Color primaryBlue = Color(0xFF1E88E5);
  static const Color electricBlue = Color(0xFF2563EB);
  static const Color darkBlue = Color(0xFF0D47A1);
  static const Color deepNavy = Color(0xFF0F172A);
  static const Color accentCyan = Color(0xFF00E5FF);
  static const Color cyanGlow = Color(0xFF38BDF8);

  // Backgrounds & Surfaces
  static const Color lightBlueBackground = Color(0xFFF1F7FF);
  static const Color lightSurface = Color(0xFFF8FAFC);
  static const Color cardWhite = Colors.white;

  // Borders & Dividers
  static const Color cardBorder = Color(0xFFD6E8F7);
  static const Color cardBorderFocused = Color(0xFF90CAF9);
  static const Color borderBlue = Color(0xFFD6E8F7);

  // Text
  static const Color textDark = Color(0xFF0F172A);
  static const Color textMuted = Color(0xFF64748B);
  static const Color textSubtle = Color(0xFF94A3B8);

  // Status Accents
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
}

/// Shared TechNoWiz Blue Cyber-Circuit Background for all Quiz Master screens.
class QuizMasterCircuitBackground extends StatelessWidget {
  final Widget child;
  final Color baseColor;
  final bool darkTheme;

  const QuizMasterCircuitBackground({
    super.key,
    required this.child,
    this.baseColor = QuizMasterColors.lightBlueBackground,
    this.darkTheme = false,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: darkTheme ? null : baseColor,
        gradient: darkTheme
            ? const LinearGradient(
                colors: [
                  Color(0xFF0B132B),
                  Color(0xFF0F172A),
                  Color(0xFF1E293B),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : LinearGradient(
                colors: [
                  const Color(0xFFEFF6FF),
                  baseColor,
                  const Color(0xFFE0EFFF),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: CustomPaint(
              painter: QuizMasterCircuitPainter(darkTheme: darkTheme),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Custom painter rendering the authentic TechNoWiz cyber-circuit traces,
/// glowing dual-ring tech nodes, micro-bus terminals, and subtle ambient glows.
class QuizMasterCircuitPainter extends CustomPainter {
  final bool darkTheme;

  const QuizMasterCircuitPainter({this.darkTheme = false});

  @override
  void paint(Canvas canvas, Size size) {
    final lineColor = darkTheme
        ? const Color(0x2838BDF8)
        : const Color(0x1E1E88E5);
    final nodeColor = darkTheme
        ? const Color(0x6000E5FF)
        : const Color(0x301E88E5);
    final glowColor = darkTheme
        ? const Color(0x1800E5FF)
        : const Color(0x141E88E5);

    // Subtle corner command glows
    final glowPaint = Paint()
      ..color = glowColor
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(size.width * 0.92, size.height * 0.08),
      size.shortestSide * 0.35,
      glowPaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.08, size.height * 0.90),
      size.shortestSide * 0.30,
      glowPaint,
    );

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final nodePaint = Paint()
      ..color = nodeColor
      ..style = PaintingStyle.fill;

    final nodeRingPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke;

    void drawTrace(List<Offset> points) {
      if (points.length < 2) return;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(path, linePaint);

      final first = points.first;
      final last = points.last;
      canvas.drawCircle(first, 3.2, nodePaint);
      canvas.drawCircle(last, 3.8, nodePaint);
      canvas.drawCircle(last, 7.0, nodeRingPaint);
    }

    final w = size.width;
    final h = size.height;

    // Top-left circuit traces
    drawTrace([
      Offset(0, h * 0.10),
      Offset(w * 0.15, h * 0.10),
      Offset(w * 0.20, h * 0.15),
      Offset(w * 0.32, h * 0.15),
    ]);
    drawTrace([
      Offset(w * 0.07, 0),
      Offset(w * 0.07, h * 0.06),
      Offset(w * 0.13, h * 0.09),
    ]);

    // Top-right circuit traces
    drawTrace([
      Offset(w, h * 0.14),
      Offset(w * 0.85, h * 0.14),
      Offset(w * 0.80, h * 0.19),
      Offset(w * 0.68, h * 0.19),
    ]);
    drawTrace([
      Offset(w * 0.89, 0),
      Offset(w * 0.89, h * 0.08),
      Offset(w * 0.82, h * 0.12),
    ]);

    // Mid-side subtle command traces
    drawTrace([
      Offset(0, h * 0.48),
      Offset(w * 0.09, h * 0.48),
      Offset(w * 0.14, h * 0.43),
      Offset(w * 0.22, h * 0.43),
    ]);
    drawTrace([
      Offset(w, h * 0.54),
      Offset(w * 0.90, h * 0.54),
      Offset(w * 0.85, h * 0.59),
      Offset(w * 0.77, h * 0.59),
    ]);

    // Bottom-left circuit traces
    drawTrace([
      Offset(0, h * 0.82),
      Offset(w * 0.14, h * 0.82),
      Offset(w * 0.20, h * 0.77),
      Offset(w * 0.30, h * 0.77),
    ]);

    // Bottom-right circuit traces
    drawTrace([
      Offset(w, h * 0.86),
      Offset(w * 0.84, h * 0.86),
      Offset(w * 0.78, h * 0.81),
      Offset(w * 0.66, h * 0.81),
    ]);
  }

  @override
  bool shouldRepaint(covariant QuizMasterCircuitPainter oldDelegate) {
    return oldDelegate.darkTheme != darkTheme;
  }
}

/// Unified TechNoWiz Quiz Master Badge / Pill (e.g. TECHNOWIZ • QUIZMASTER COMMAND)
class QuizMasterBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool darkTheme;

  const QuizMasterBadge({
    super.key,
    required this.label,
    this.icon = Icons.terminal_rounded,
    this.darkTheme = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: darkTheme
            ? Colors.white.withValues(alpha: 0.12)
            : const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: darkTheme
              ? Colors.white.withValues(alpha: 0.25)
              : const Color(0xFFBBDEFB),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: darkTheme ? const Color(0xFF38BDF8) : QuizMasterColors.primaryBlue,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: darkTheme ? Colors.white : QuizMasterColors.darkBlue,
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Unified Tech Card with subtle tech border and soft elevation.
class QuizMasterCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final bool hasTopAccentBar;
  final Color? accentColor;
  final double borderRadius;
  final VoidCallback? onTap;

  const QuizMasterCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin,
    this.hasTopAccentBar = false,
    this.accentColor,
    this.borderRadius = 18,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveAccent = accentColor ?? QuizMasterColors.primaryBlue;

    Widget content = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: QuizMasterColors.cardBorder, width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C1E88E5),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: hasTopAccentBar
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(height: 3.5, color: effectiveAccent),
                  Padding(padding: padding, child: child),
                ],
              )
            : Padding(padding: padding, child: child),
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: content,
      );
    }
    return content;
  }
}

/// Unified Header / App Bar for Quiz Master screens.
class QuizMasterAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final String badgeText;
  final IconData badgeIcon;
  final bool showBackButton;
  final VoidCallback? onBack;
  final List<Widget>? actions;

  const QuizMasterAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.badgeText = 'TECHNOWIZ • QUIZMASTER',
    this.badgeIcon = Icons.memory_rounded,
    this.showBackButton = true,
    this.onBack,
    this.actions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(84);

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final shouldShowBack = showBackButton && (canPop || onBack != null);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: QuizMasterColors.cardBorder, width: 1.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x061E88E5),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (shouldShowBack) ...[
                Material(
                  color: const Color(0xFFF0F7FF),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: onBack ?? () => Navigator.of(context).pop(),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFD6E8F7),
                          width: 1.1,
                        ),
                      ),
                      child: const Icon(
                        Icons.arrow_back_rounded,
                        color: QuizMasterColors.darkBlue,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: QuizMasterBadge(label: badgeText, icon: badgeIcon),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: QuizMasterColors.textMuted,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: QuizMasterColors.textDark,
                        letterSpacing: -0.3,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
              ...?actions,
            ],
          ),
        ),
      ),
    );
  }
}

/// Unified Quiz Master Command Button
class QuizMasterButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isSecondary;
  final bool isDanger;
  final double height;
  final bool isLoading;

  const QuizMasterButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isSecondary = false,
    this.isDanger = false,
    this.height = 50,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color bgColor = isDanger
        ? QuizMasterColors.danger
        : (isSecondary ? Colors.white : QuizMasterColors.primaryBlue);
    final Color fgColor = isSecondary ? QuizMasterColors.primaryBlue : Colors.white;
    final BorderSide borderSide = isSecondary
        ? const BorderSide(color: QuizMasterColors.primaryBlue, width: 1.5)
        : BorderSide.none;

    return SizedBox(
      height: height,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: fgColor,
          elevation: isSecondary ? 0 : 2,
          shadowColor: const Color(0x331E88E5),
          side: borderSide,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: fgColor,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 19, color: fgColor),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: fgColor,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Reusable TechNoWiz Brand Header for Quiz Master AppBars & Screens.
/// Matches the Quiz Master Dashboard top bar aesthetic: school icon in a blue
/// container, bold "TechNoWiz" title, and dynamic active quiz stream or page subtitle.
class QuizMasterBrandTitle extends StatelessWidget {
  final String? subtitle;

  const QuizMasterBrandTitle({super.key, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFFE4F2FF),
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(
            Icons.school_rounded,
            color: Color(0xFF1689E8),
            size: 22,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'TechNoWiz',
                style: TextStyle(
                  color: Color(0xFF17245A),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.2,
                ),
              ),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('quiz_sessions')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    const activeStatuses = <String>{
                      'active',
                      'live',
                      'started',
                      'ongoing',
                      'in_progress',
                      'inprogress',
                      'waiting',
                      'countdown',
                      'paused',
                      'level_pause',
                    };
                    for (final doc in snapshot.data!.docs) {
                      final data = doc.data() as Map<String, dynamic>;
                      final isPublished = data['published'] == true ||
                          data['isPublished'] == true ||
                          data['is_published'] == true ||
                          data['published'] == 1 ||
                          data['isPublished'] == 1 ||
                          data['published']?.toString().trim().toLowerCase() ==
                              'true' ||
                          data['isPublished']
                                  ?.toString()
                                  .trim()
                                  .toLowerCase() ==
                              'true' ||
                          (data['status'] ?? '').toString().toLowerCase() ==
                              'published';
                      if (!isPublished) continue;

                      final status = (data['status']?.toString() ?? '')
                          .trim()
                          .toLowerCase()
                          .replaceAll('-', '_')
                          .replaceAll(' ', '_');
                      final isFinished = data['isFinished'] == true ||
                          data['isCompleted'] == true ||
                          data['completed'] == true ||
                          data['finished'] == true ||
                          status == 'finished' ||
                          status == 'completed' ||
                          status == 'closed' ||
                          status == 'archived';
                      if (isFinished) continue;
                      if (!activeStatuses.contains(status)) continue;
                      final quizName = (data['title'] ??
                              data['quizTitle'] ??
                              data['name'] ??
                              '')
                          .toString()
                          .trim();
                      if (quizName.isNotEmpty) {
                        return Text(
                          quizName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF1689E8),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }
                    }
                  }
                  if (subtitle != null && subtitle!.isNotEmpty) {
                    return Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF71849E),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// TECHNOWIZ QUIZ MASTER TOP NOTIFICATION POP-UP (SA BABAW MO-POP UP)
// ============================================================================

OverlayEntry? _activeQuizMasterTopNotification;

/// Displays a sleek, high-tech top-sliding notification pop up (sa babaw mo-pop up).
/// Automatically replaces any existing top notification and slides down smoothly
/// from the top, staying for [duration] before sliding back up.
void showQuizMasterTopNotification(
  BuildContext context,
  String message, {
  bool isError = false,
  bool isSuccess = false,
  bool isWarning = false,
  IconData? icon,
  Duration duration = const Duration(milliseconds: 2800),
}) {
  if (message.trim().isEmpty) return;

  try {
    final overlayState = Overlay.of(context, rootOverlay: true);

    // Dismiss any previously showing top notification immediately
    _activeQuizMasterTopNotification?.remove();
    _activeQuizMasterTopNotification = null;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _QuizMasterTopNotificationWidget(
        message: message,
        isError: isError,
        isSuccess: isSuccess,
        isWarning: isWarning,
        icon: icon,
        duration: duration,
        onDismiss: () {
          if (_activeQuizMasterTopNotification == entry) {
            _activeQuizMasterTopNotification?.remove();
            _activeQuizMasterTopNotification = null;
          }
        },
      ),
    );

    _activeQuizMasterTopNotification = entry;
    overlayState.insert(entry);
  } catch (e) {
    debugPrint('Error showing top notification: $e');
  }
}

class _QuizMasterTopNotificationWidget extends StatefulWidget {
  final String message;
  final bool isError;
  final bool isSuccess;
  final bool isWarning;
  final IconData? icon;
  final Duration duration;
  final VoidCallback onDismiss;

  const _QuizMasterTopNotificationWidget({
    required this.message,
    required this.isError,
    required this.isSuccess,
    required this.isWarning,
    this.icon,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_QuizMasterTopNotificationWidget> createState() =>
      _QuizMasterTopNotificationWidgetState();
}

class _QuizMasterTopNotificationWidgetState
    extends State<_QuizMasterTopNotificationWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 220),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );

    _controller.forward();

    // Auto-dismiss after duration
    Future.delayed(widget.duration, () {
      if (mounted) _dismiss();
    });
  }

  void _dismiss() {
    if (_dismissing || !mounted) return;
    _dismissing = true;
    _controller.reverse().then((_) {
      if (mounted) {
        widget.onDismiss();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final Color accentColor = widget.isError
        ? const Color(0xFFEF4444)
        : widget.isSuccess
            ? const Color(0xFF10B981)
            : widget.isWarning
                ? const Color(0xFFF59E0B)
                : const Color(0xFF38BDF8);

    final IconData displayIcon = widget.icon ??
        (widget.isError
            ? Icons.error_outline_rounded
            : widget.isSuccess
                ? Icons.check_circle_outline_rounded
                : widget.isWarning
                    ? Icons.warning_amber_rounded
                    : Icons.info_outline_rounded);

    return Positioned(
      top: topPadding + 10,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: GestureDetector(
                onTap: _dismiss,
                onVerticalDragUpdate: (details) {
                  if (details.primaryDelta != null && details.primaryDelta! < -4) {
                    _dismiss();
                  }
                },
                child: Material(
                  color: Colors.transparent,
                  elevation: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.85),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                        BoxShadow(
                          color: accentColor.withValues(alpha: 0.15),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            displayIcon,
                            color: accentColor,
                            size: 19,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            widget.message,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: _dismiss,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.close_rounded,
                              color: Colors.white.withValues(alpha: 0.6),
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}



