import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'admin_sidebar.dart';
import '../login_screen.dart';

/// ============================================================================
/// TECHNOWIZ ADMIN COMMAND CENTER - LIGHT PURPLE THEME & REUSABLE DESIGN SYSTEM
/// ============================================================================
/// Provides a consistent, authoritative, high-tech Light Purple UI across all
/// Admin screens with zero design discrepancies and 100% responsiveness on any device.

class AdminThemeColors {
  // Primary Royal & Electric Purples
  static const Color primary = Color(0xFF7C3AED); // Electric Purple
  static const Color primaryDark = Color(0xFF4C1D95); // Deep Royal Purple
  static const Color primaryLight = Color(0xFF8B5CF6); // Radiant Violet
  static const Color accentLavender = Color(0xFFA855F7); // Lavender Glow
  static const Color glow = Color(0xFFC084FC); // Soft Glow

  // Backgrounds & Surfaces (Light Purple Aesthetic)
  static const Color background = Color(0xFFFAF7FF); // Clean Light Purple Canvas
  static const Color backgroundSecondary = Color(0xFFF3E8FF); // Soft Violet Surface
  static const Color surface = Colors.white; // Card Surface
  static const Color surfaceSubtle = Color(0xFFF8F5FF);

  // Borders & Dividers
  static const Color border = Color(0xFFE9D5FF); // Light Purple Border
  static const Color borderSubtle = Color(0xFFF3E8FF);
  static const Color borderFocus = Color(0xFF7C3AED);

  // Pill & Chip Colors
  static const Color pillBg = Color(0xFFF5EEFF);
  static const Color pillBorder = Color(0xFFDDD6FE);
  static const Color pillText = Color(0xFF6D28D9);

  // Typography
  static const Color textPrimary = Color(0xFF1E1B4B); // Deep Navy-Purple
  static const Color textSecondary = Color(0xFF4C1D95); // Royal Violet
  static const Color textMuted = Color(0xFF6B7280); // Cool Grey
  static const Color textSubtle = Color(0xFF9CA3AF);

  // Status Indicators
  static const Color success = Color(0xFF10B981);
  static const Color successBg = Color(0xFFECFDF5);
  static const Color successBorder = Color(0xFFA7F3D0);

  static const Color warning = Color(0xFFF59E0B);
  static const Color warningBg = Color(0xFFFFFBEB);
  static const Color warningBorder = Color(0xFFFDE68A);

  static const Color danger = Color(0xFFEF4444);
  static const Color dangerBg = Color(0xFFFEF2F2);
  static const Color dangerBorder = Color(0xFFFECACA);

  static const Color info = Color(0xFF8B5CF6);
  static const Color infoBg = Color(0xFFF5F3FF);
  static const Color infoBorder = Color(0xFFDDD6FE);
}

/// ============================================================================
/// 1. LIGHT PURPLE TECH CIRCUIT BACKGROUND
/// ============================================================================
class AdminCircuitBackground extends StatelessWidget {
  final Widget child;

  const AdminCircuitBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFFFAF7FF),
            Color(0xFFF5EEFF),
            Color(0xFFF3E8FF),
            Color(0xFFF8F2FF),
            Color(0xFFFAF7FF),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.0, 0.25, 0.55, 0.85, 1.0],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: CustomPaint(
              painter: _AdminCircuitPainter(),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _AdminCircuitPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    final tracePaint = Paint()
      ..color = const Color(0xFF7C3AED).withValues(alpha: 0.12)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final glowPaint = Paint()
      ..color = const Color(0xFFA855F7).withValues(alpha: 0.06)
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;

    final nodeFillPaint = Paint()
      ..color = const Color(0xFF7C3AED).withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;

    final nodeRingPaint = Paint()
      ..color = const Color(0xFF8B5CF6).withValues(alpha: 0.25)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    void drawTrace(List<Offset> points, {bool endRing = true}) {
      if (points.isEmpty) return;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, tracePaint);
      canvas.drawCircle(points.first, 3.0, nodeFillPaint);
      canvas.drawCircle(points.last, 3.5, nodeFillPaint);
      if (endRing) {
        canvas.drawCircle(points.last, 7.0, nodeRingPaint);
      }
    }

    // Top-Left Cyber Traces
    drawTrace([
      Offset(0, h * 0.08),
      Offset(w * 0.14, h * 0.08),
      Offset(w * 0.22, h * 0.15),
      Offset(w * 0.35, h * 0.15),
    ]);
    drawTrace([
      Offset(w * 0.08, 0),
      Offset(w * 0.08, h * 0.05),
      Offset(w * 0.14, h * 0.11),
    ]);

    // Top-Right Cyber Traces
    drawTrace([
      Offset(w, h * 0.09),
      Offset(w * 0.86, h * 0.09),
      Offset(w * 0.78, h * 0.17),
      Offset(w * 0.65, h * 0.17),
    ]);
    drawTrace([
      Offset(w * 0.92, 0),
      Offset(w * 0.92, h * 0.06),
      Offset(w * 0.86, h * 0.12),
    ]);

    // Mid-Left & Mid-Right Traces
    drawTrace([
      Offset(0, h * 0.42),
      Offset(w * 0.07, h * 0.42),
      Offset(w * 0.13, h * 0.48),
      Offset(w * 0.20, h * 0.48),
    ]);
    drawTrace([
      Offset(w, h * 0.45),
      Offset(w * 0.93, h * 0.45),
      Offset(w * 0.87, h * 0.51),
      Offset(w * 0.80, h * 0.51),
    ]);

    // Bottom Cyber Traces
    drawTrace([
      Offset(0, h * 0.88),
      Offset(w * 0.15, h * 0.88),
      Offset(w * 0.22, h * 0.82),
      Offset(w * 0.35, h * 0.82),
    ]);
    drawTrace([
      Offset(w, h * 0.86),
      Offset(w * 0.84, h * 0.86),
      Offset(w * 0.77, h * 0.80),
      Offset(w * 0.65, h * 0.80),
    ]);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// ============================================================================
/// 2. UNIFIED ADMIN TOP BAR
/// ============================================================================
class AdminTopBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final List<Widget>? actions;
  final VoidCallback? onMenuPressed;
  final bool showMenuButton;

  const AdminTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.admin_panel_settings_rounded,
    this.actions,
    this.onMenuPressed,
    this.showMenuButton = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        border: const Border(
          bottom: BorderSide(color: AdminThemeColors.border, width: 1.2),
        ),
        boxShadow: [
          BoxShadow(
            color: AdminThemeColors.primary.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (showMenuButton) ...[
              IconButton(
                icon: const Icon(
                  Icons.menu_rounded,
                  color: AdminThemeColors.primary,
                  size: 24,
                ),
                onPressed: onMenuPressed ??
                    () {
                      Scaffold.of(context).openDrawer();
                    },
                tooltip: 'Open Menu',
              ),
              const SizedBox(width: 6),
            ],

            // Screen Icon & Title Badge
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    AdminThemeColors.primary,
                    AdminThemeColors.primaryDark,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AdminThemeColors.primary.withValues(alpha: 0.30),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),

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
                        Text(
                          title,
                          style: const TextStyle(
                            color: AdminThemeColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: AdminThemeColors.pillBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AdminThemeColors.pillBorder,
                              width: 1,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.verified_user_rounded,
                                size: 11,
                                color: AdminThemeColors.primary,
                              ),
                              SizedBox(width: 4),
                              Text(
                                "ADMIN CONSOLE",
                                style: TextStyle(
                                  color: AdminThemeColors.primaryDark,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AdminThemeColors.textMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            ...?actions,

            const SizedBox(width: 8),

            // Profile Popup Menu
            _buildProfileMenu(context),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileMenu(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final String initial = (user?.email?.isNotEmpty ?? false)
        ? user!.email![0].toUpperCase()
        : 'A';

    return PopupMenuButton<String>(
      tooltip: 'Admin Profile',
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AdminThemeColors.border, width: 1.2),
      ),
      color: Colors.white,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AdminThemeColors.pillBg,
          shape: BoxShape.circle,
          border: Border.all(color: AdminThemeColors.pillBorder, width: 1.5),
        ),
        child: Center(
          child: Text(
            initial,
            style: const TextStyle(
              color: AdminThemeColors.primaryDark,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
      itemBuilder: (ctx) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user?.displayName ?? 'Administrator',
                style: const TextStyle(
                  color: AdminThemeColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              Text(
                user?.email ?? 'admin@technowiz.com',
                style: const TextStyle(
                  color: AdminThemeColors.textMuted,
                  fontSize: 11,
                ),
              ),
              const Divider(height: 16),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'logout',
          child: const Row(
            children: [
              Icon(Icons.logout_rounded, color: AdminThemeColors.danger, size: 18),
              SizedBox(width: 10),
              Text(
                'Log Out',
                style: TextStyle(
                  color: AdminThemeColors.danger,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
      onSelected: (value) async {
        if (value == 'logout') {
          await LoginScreen.clearSavedCredentials();
          await FirebaseAuth.instance.signOut();
          if (context.mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (_) => const LoginScreen(clearCredentials: true),
              ),
              (route) => false,
            );
          }
        }
      },
    );
  }
}

/// ============================================================================
/// 3. UNIFIED ADMIN CARD CONTAINER
/// ============================================================================
class AdminCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderRadius;

  const AdminCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius = 20,
  });

  @override
  Widget build(BuildContext context) {
    final cardContent = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: borderColor ?? AdminThemeColors.border,
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: AdminThemeColors.primary.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: AdminThemeColors.primaryDark.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );

    if (onTap == null) return cardContent;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(borderRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: cardContent,
      ),
    );
  }
}

/// ============================================================================
/// 4. UNIFIED ADMIN STAT CARD
/// ============================================================================
class AdminStatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color? iconColor;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const AdminStatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.iconColor,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveIconColor = iconColor ?? AdminThemeColors.primary;

    return AdminCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: effectiveIconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: effectiveIconColor.withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
                child: Icon(icon, color: effectiveIconColor, size: 22),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                color: AdminThemeColors.textPrimary,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AdminThemeColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AdminThemeColors.textMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// ============================================================================
/// 5. UNIFIED ADMIN PRIMARY BUTTON
/// ============================================================================
class AdminPrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final double? width;
  final double height;

  const AdminPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.isLoading = false,
    this.width,
    this.height = 46,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: onPressed == null || isLoading
              ? [const Color(0xFFC4B5FD), const Color(0xFFA78BFA)]
              : [AdminThemeColors.primary, AdminThemeColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDDD6FE), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AdminThemeColors.primary.withValues(alpha: 0.30),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: isLoading ? null : onPressed,
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icon != null) ...[
                            Icon(icon, color: Colors.white, size: 18),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// ============================================================================
/// 6. UNIFIED ADMIN SECONDARY BUTTON
/// ============================================================================
class AdminSecondaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double? width;
  final double height;

  const AdminSecondaryButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.width,
    this.height = 46,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminThemeColors.border, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: AdminThemeColors.primary.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, color: AdminThemeColors.primary, size: 18),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      label,
                      style: const TextStyle(
                        color: AdminThemeColors.primaryDark,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ============================================================================
/// 7. UNIFIED ADMIN INPUT FIELD
/// ============================================================================
class AdminInputField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final String? labelText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType keyboardType;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  const AdminInputField({
    super.key,
    required this.controller,
    required this.hintText,
    this.labelText,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (labelText != null && labelText!.isNotEmpty) ...[
          Text(
            labelText!,
            style: const TextStyle(
              color: AdminThemeColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Container(
          decoration: BoxDecoration(
            color: AdminThemeColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AdminThemeColors.border, width: 1.2),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            maxLines: maxLines,
            onChanged: onChanged,
            style: const TextStyle(
              color: AdminThemeColors.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: const TextStyle(
                color: AdminThemeColors.textSubtle,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              prefixIcon: prefixIcon != null
                  ? Icon(prefixIcon, color: AdminThemeColors.primary, size: 20)
                  : null,
              suffixIcon: suffixIcon,
            ),
          ),
        ),
      ],
    );
  }
}

/// ============================================================================
/// 8. UNIFIED ADMIN STATUS BADGE
/// ============================================================================
class AdminBadge extends StatelessWidget {
  final String label;
  final Color? color;
  final Color? backgroundColor;
  final IconData? icon;

  const AdminBadge({
    super.key,
    required this.label,
    this.color,
    this.backgroundColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = color ?? AdminThemeColors.primaryDark;
    final bgColor = backgroundColor ?? AdminThemeColors.pillBg;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: textColor.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: textColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// ============================================================================
/// 9. RESPONSIVE MASTER SCAFFOLD FOR ALL ADMIN SCREENS
/// ============================================================================
class AdminScaffold extends StatelessWidget {
  final String currentPage;
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  const AdminScaffold({
    super.key,
    required this.currentPage,
    required this.title,
    this.subtitle,
    this.icon = Icons.admin_panel_settings_rounded,
    required this.body,
    this.actions,
    this.floatingActionButton,
  });

  void _handleNavigation(BuildContext context, String destination) {
    if (destination == currentPage) return;

    // Use root navigator or normal replacement
    Widget nextScreen;
    switch (destination) {
      case 'dashboard':
        Navigator.popUntil(context, (route) => route.isFirst);
        return;
      case 'manage_users':
        nextScreen = const _LazyPageWrapper(destination: 'manage_users');
        break;
      case 'add_question':
        nextScreen = const _LazyPageWrapper(destination: 'add_question');
        break;
      case 'question_list':
        nextScreen = const _LazyPageWrapper(destination: 'question_list');
        break;
      case 'quiz_sessions':
        nextScreen = const _LazyPageWrapper(destination: 'quiz_sessions');
        break;
      case 'leaderboard':
        nextScreen = const _LazyPageWrapper(destination: 'leaderboard');
        break;
      case 'reports':
        nextScreen = const _LazyPageWrapper(destination: 'reports');
        break;
      default:
        return;
    }

    Navigator.pushReplacement(
      context,
      adminPageRoute(nextScreen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double screenWidth = constraints.maxWidth;
        final bool isDesktop = screenWidth >= 960;

        return Scaffold(
          backgroundColor: AdminThemeColors.background,
          drawer: isDesktop
              ? null
              : AdminSidebar(
                  currentPage: currentPage,
                  onDestinationSelected: (dest) =>
                      _handleNavigation(context, dest),
                ),
          floatingActionButton: floatingActionButton,
          body: AdminCircuitBackground(
            child: isDesktop
                ? Row(
                    children: [
                      // Desktop Persistent Left Sidebar
                      SizedBox(
                        width: 245,
                        child: AdminSidebar(
                          currentPage: currentPage,
                          onDestinationSelected: (dest) =>
                              _handleNavigation(context, dest),
                        ),
                      ),
                      // Desktop Main Content Pane
                      Expanded(
                        child: Column(
                          children: [
                            AdminTopBar(
                              title: title,
                              subtitle: subtitle,
                              icon: icon,
                              actions: actions,
                              showMenuButton: false,
                            ),
                            Expanded(child: body),
                          ],
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      // Mobile / Tablet Top Bar with Hamburger Menu
                      AdminTopBar(
                        title: title,
                        subtitle: subtitle,
                        icon: icon,
                        actions: actions,
                        showMenuButton: true,
                      ),
                      Expanded(child: body),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

/// Fallback lazy loader for circular navigation imports
class _LazyPageWrapper extends StatelessWidget {
  final String destination;
  const _LazyPageWrapper({required this.destination});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminThemeColors.background,
      body: Center(
        child: CircularProgressIndicator(color: AdminThemeColors.primary),
      ),
    );
  }
}

/// ============================================================================
/// 8. TECHNOWIZ ADMIN TOP NOTIFICATION BANNER
/// ============================================================================
/// A unified, top-positioned toast banner that slides in from the top with the
/// official TechNoWiz Admin Theme electric-purple gradient (or error/warning).
class AdminNotification {
  static OverlayEntry? _currentEntry;

  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
    bool isWarning = false,
    IconData? icon,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!context.mounted) return;

    try {
      ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
      ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    } catch (_) {}

    if (_currentEntry != null) {
      if (_currentEntry!.mounted) {
        _currentEntry!.remove();
      }
      _currentEntry = null;
    }

    final overlay = Overlay.maybeOf(context, rootOverlay: true) ??
        Overlay.maybeOf(context);

    if (overlay == null) return;

    late final OverlayEntry entry;

    entry = OverlayEntry(
      builder: (overlayContext) {
        final topInset = MediaQuery.paddingOf(overlayContext).top;
        final screenWidth = MediaQuery.sizeOf(overlayContext).width;
        final isMobile = screenWidth < 600;

        // Official TechNoWiz Admin Electric Purple Theme for ALL notifications (unified, no other colors)
        const Color bgStart = AdminThemeColors.primary;
        const Color bgEnd = AdminThemeColors.primaryDark;
        final Color shadowColor =
            AdminThemeColors.primary.withValues(alpha: 0.38);
        final IconData defaultIcon = icon ?? Icons.check_circle_rounded;

        return Positioned(
          top: topInset + 14,
          left: 16,
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  tween: Tween<double>(begin: 0.0, end: 1.0),
                  builder: (context, value, child) {
                    return Transform.translate(
                      offset: Offset(0, -22 * (1.0 - value)),
                      child: Opacity(
                        opacity: value.clamp(0.0, 1.0),
                        child: child,
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [bgStart, bgEnd],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.28),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: shadowColor,
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: isMobile ? MainAxisSize.max : MainAxisSize.min,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            icon ?? defaultIcon,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            message,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.1,
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
        );
      },
    );

    _currentEntry = entry;
    overlay.insert(entry);

    Timer(duration, () {
      if (entry.mounted && _currentEntry == entry) {
        entry.remove();
        _currentEntry = null;
      }
    });
  }

  static void success(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    show(context, message, isError: false, duration: duration);
  }

  static void error(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    show(context, message, isError: true, duration: duration);
  }

  static void warning(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    show(context, message, isWarning: true, duration: duration);
  }
}

/// Standardized admin app bar height across ALL admin screens so the top bar
/// is completely steady and does not shift or jump by even 1 pixel during navigation.
const double kAdminAppBarHeight = 64.0;

/// Route builder that swaps admin pages with zero transition animation,
/// completely preventing layout jumping, sliding, and glitching when switching pages.
PageRouteBuilder<T> adminPageRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
  );
}

/// Unified Admin AppBar builder to ensure 100% identical geometry, alignment,
/// and appearance on every Admin screen without visual stutter or layout shifts.
PreferredSizeWidget buildAdminStandardAppBar({
  required BuildContext context,
  required String badgeText,
  required String subtitle,
  VoidCallback? onMenuPressed,
  List<Widget>? additionalActions,
  Widget? leading,
  double toolbarHeight = kAdminAppBarHeight,
}) {
  return AppBar(
    backgroundColor: Colors.white,
    elevation: 0,
    scrolledUnderElevation: 0,
    surfaceTintColor: Colors.transparent,
    automaticallyImplyLeading: false,
    titleSpacing: leading != null ? 0 : 16,
    toolbarHeight: toolbarHeight,
    leading: leading,
    title: Row(
      children: [
        // Purple TechNoWiz Brand Icon Badge (Shield)
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
        // TechNoWiz Brand & Badge
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
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
                        color: AdminThemeColors.primary.withValues(alpha: 0.22),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      badgeText,
                      style: const TextStyle(
                        color: AdminThemeColors.primary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
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
      if (additionalActions != null) ...additionalActions,
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
              onPressed: onMenuPressed ??
                  () {
                    FocusScope.of(context).unfocus();
                    Scaffold.maybeOf(drawerContext)?.openEndDrawer();
                  },
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
        color: Color(0xFFF3E8FF),
      ),
    ),
  );
}



