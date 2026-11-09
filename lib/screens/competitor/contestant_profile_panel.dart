import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'technowiz_theme.dart';

/// Modern TechNoWiz Arena Contestant Profile Panel.
class ContestantProfilePanel extends StatelessWidget {
  final Map<String, dynamic> profileData;
  final ImageProvider<Object>? profileImageProvider;
  final VoidCallback onClose;
  final VoidCallback onEdit;
  final VoidCallback onLogout;

  const ContestantProfilePanel({
    super.key,
    required this.profileData,
    required this.profileImageProvider,
    required this.onClose,
    required this.onEdit,
    required this.onLogout,
  });

  static const Color primaryGreen = Color(0xFF16A34A);
  static const Color darkGreen = Color(0xFF14532D);
  static const Color lightGreen = Color(0xFFE8FBEF);
  static const Color backgroundColor = Color(0xFFF5FBF6);
  static const Color softBorder = Color(0xFFD5F0DE);

  String getParticipationType() {
    final registeredType = profileData['contestantType']?.toString().trim();
    if (registeredType != null && registeredType.isNotEmpty) {
      return registeredType.toLowerCase() == 'team' ? 'Team' : 'Solo';
    }
    final legacyType =
        profileData['participationType'] ??
        profileData['participation'] ??
        profileData['type'];
    final result = legacyType?.toString().trim();
    if (result != null && result.isNotEmpty && result.toLowerCase() == 'team') {
      return 'Team';
    }
    return 'Solo';
  }

  List<String> getTeamMembers() {
    final rawMembers = profileData['teamMembers'] ?? profileData['members'];
    if (rawMembers is! List) return [];
    final names = <String>[];
    for (final m in rawMembers) {
      if (m is String && m.trim().isNotEmpty) {
        names.add(m.trim());
      } else if (m is Map) {
        final val = (m['name'] ?? m['displayName'] ?? m['fullName'])
            ?.toString()
            .trim();
        if (val != null && val.isNotEmpty) names.add(val);
      }
    }
    return names;
  }

  String getSchoolName() {
    final school = profileData['schoolName']?.toString().trim();
    if (school != null && school.isNotEmpty) return school;
    final oldAddress = profileData['address']?.toString().trim();
    if (oldAddress != null && oldAddress.isNotEmpty) return oldAddress;
    return "Not yet set";
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    final name = profileData['name']?.toString().trim().isNotEmpty == true
        ? profileData['name'].toString().trim()
        : user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!.trim()
        : "Contestant";

    final email = profileData['email']?.toString().trim().isNotEmpty == true
        ? profileData['email'].toString().trim()
        : user?.email ?? "";

    final participation = getParticipationType();

    final education =
        profileData['educationLevel']?.toString().trim().isNotEmpty == true
        ? profileData['educationLevel'].toString().trim()
        : "Not yet set";

    final grade =
        profileData['gradeLevel']?.toString().trim().isNotEmpty == true
        ? profileData['gradeLevel'].toString().trim()
        : "Not yet set";

    final schoolName = getSchoolName();
    final teamMembers = getTeamMembers();
    final isCompactScreen = MediaQuery.of(context).size.height < 700;
    final avatarSize = isCompactScreen ? 74.0 : 92.0;

    return TechCircuitBackground(
      child: Column(
        children: [
          // =====================================================
          // TECH HEADER
          // =====================================================
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(20, isCompactScreen ? 10 : 16, 16, isCompactScreen ? 16 : 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF064E3B),
                  Color(0xFF047857),
                  Color(0xFF16A34A),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0x33064E3B),
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      onPressed: onClose,
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const Expanded(
                      child: Text(
                        "Profile",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Edit Profile',
                      onPressed: onEdit,
                      icon: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                          ),
                        ),
                        child: const Icon(
                          Icons.edit_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isCompactScreen ? 6 : 10),
                const TechArenaBadge(
                  label: 'TECHNOWIZ • CONTESTANT PROFILE',
                  icon: Icons.shield_rounded,
                  darkTheme: true,
                ),
                SizedBox(height: isCompactScreen ? 10 : 16),
                Container(
                  width: avatarSize,
                  height: avatarSize,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4),
                      width: 1.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF34D399).withValues(alpha: 0.35),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.8),
                        width: 2.2,
                      ),
                      image: profileImageProvider == null
                          ? null
                          : DecorationImage(
                              image: profileImageProvider!,
                              fit: BoxFit.cover,
                            ),
                    ),
                    child: profileImageProvider == null
                        ? Icon(
                            Icons.person_rounded,
                            color: Colors.white,
                            size: isCompactScreen ? 38 : 48,
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFD1FAE5),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // =====================================================
          // DETAILS TILES
          // =====================================================
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 24),
              child: Column(
                children: [
                  _infoCard(
                    icon: Icons.location_on_outlined,
                    title: "School Name",
                    value: schoolName,
                  ),
                  _infoCard(
                    icon: Icons.groups_outlined,
                    title: "Participation",
                    value: participation,
                  ),
                  if (participation == "Team") ...[
                    _infoCard(
                      icon: Icons.badge_outlined,
                      title: "Team Name",
                      value: profileData['teamName']
                                  ?.toString()
                                  .trim()
                                  .isNotEmpty ==
                              true
                          ? profileData['teamName'].toString()
                          : "Not yet set",
                    ),
                    _teamMembersCard(teamMembers),
                  ],
                  _infoCard(
                    icon: Icons.school_outlined,
                    title: "Education",
                    value: education,
                  ),
                  _infoCard(
                    icon: Icons.menu_book_outlined,
                    title: "Grade / Year",
                    value: grade,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: onLogout,
                      icon: const Icon(
                        Icons.logout_rounded,
                        color: Colors.red,
                        size: 20,
                      ),
                      label: const Text(
                        "LOGOUT",
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          letterSpacing: 0.5,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFF1F2),
                        foregroundColor: Colors.red,
                        elevation: 0,
                        side: BorderSide(
                          color: Colors.red.shade200,
                          width: 1.3,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Center(
                    child: TechArenaBadge(
                      label: 'TECHNOWIZ • CONTESTANT PORTAL',
                      icon: Icons.school_rounded,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: softBorder, width: 1.3),
        boxShadow: [
          BoxShadow(
            color: primaryGreen.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFDCFCE7), Color(0xFFBBF7D0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF86EFAC)),
            ),
            child: Icon(icon, color: primaryGreen, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF059669),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    color: darkGreen,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _teamMembersCard(List<String> teamMembers) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: softBorder, width: 1.3),
        boxShadow: [
          BoxShadow(
            color: primaryGreen.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFDCFCE7), Color(0xFFBBF7D0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF86EFAC)),
                ),
                child: const Icon(
                  Icons.groups_rounded,
                  color: primaryGreen,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                "TEAM MEMBERS",
                style: TextStyle(
                  color: Color(0xFF059669),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (teamMembers.isEmpty)
            const Text(
              "Team members not yet set",
              style: TextStyle(
                color: darkGreen,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            ...teamMembers.asMap().entries.map((entry) {
              final index = entry.key;
              final member = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: const BoxDecoration(
                        color: lightGreen,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        "${index + 1}",
                        style: const TextStyle(
                          color: primaryGreen,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        member,
                        style: const TextStyle(
                          color: darkGreen,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

