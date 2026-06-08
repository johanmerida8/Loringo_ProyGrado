// parent_home_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:loringo_app/components/app_bottom_nav_bar.dart';
import 'package:loringo_app/components/notifications_badge.dart';
import 'package:loringo_app/screens/parent/parent_children_screen.dart';
import 'package:loringo_app/screens/parent/parent_notifications_screen.dart';
import 'package:loringo_app/screens/parent/parent_profile_screen.dart';
import 'package:loringo_app/screens/parent/parent_reports_screen.dart';
import 'package:loringo_app/services/auth/auth_gate.dart';
import 'package:loringo_app/services/auth/biometric_service.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/widget/secured_screen.dart';

class ParentHomeScreen extends StatefulWidget {
  const ParentHomeScreen({super.key});

  @override
  State<ParentHomeScreen> createState() => _ParentHomeScreenState();
}

class _ParentHomeScreenState extends State<ParentHomeScreen> {
  int _currentIndex = 0;

  List<Map<String, dynamic>> myChildren = [];
  Map<String, String> groupNames = {};
  Map<String, List<Map<String, dynamic>>> childReports = {};
  bool isLoading = true;
  String? parentUserId;
  String parentName = '';
  String parentEmail = '';

  // Biometric state
  bool isBiometricSupported = false;
  bool isBiometricEnabled = false;
  bool isBioLoading = true;
  List<BiometricType> availableBiometrics = [];
  String biometricTypeName = 'Biometrics';

  @override
  void initState() {
    super.initState();
    _loadData();
    _initBiometrics();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      parentUserId = user.uid;
      parentEmail = user.email ?? '';

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(parentUserId)
          .get();
      if (userDoc.exists) {
        parentName =
            (userDoc.data() as Map<String, dynamic>)['name'] as String? ?? '';
      }

      final studentsSnap = await FirebaseFirestore.instance
          .collection('students')
          .where('parentId', isEqualTo: parentUserId)
          .get();

      final students = studentsSnap.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      setState(() => myChildren = students);

      for (final s in students) {
        final gid = s['groupId'] as String?;
        if (gid != null && gid.isNotEmpty) {
          try {
            final gDoc = await FirebaseFirestore.instance
                .collection('teacherGroups')
                .doc(gid)
                .get();
            if (gDoc.exists) {
              setState(() => groupNames[s['id']] =
                  gDoc.data()?['name'] ?? 'Unknown Group');
            }
          } catch (_) {}
        }
      }

      await _loadChildReports(students);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _loadChildReports(
      List<Map<String, dynamic>> students) async {
    final reportsMap = <String, List<Map<String, dynamic>>>{};
    for (final child in students) {
      final childId = child['id'] as String;
      try {
        final snap = await FirebaseFirestore.instance
            .collection('students')
            .doc(childId)
            .collection('reports')
            .orderBy('generatedAt', descending: true)
            .get();
        reportsMap[childId] = snap.docs.map((d) {
          final data = d.data();
          data['_docId'] = d.id;
          return data;
        }).toList();
      } catch (_) {
        reportsMap[childId] = [];
      }
    }
    if (mounted) setState(() => childReports = reportsMap);
  }

  Future<void> _initBiometrics() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    try {
      final isSupported = await BiometricService.isDeviceSupported();
      final canCheck = await BiometricService.canCheckBiometrics();
      final available = await BiometricService.getAvailableBiometrics();
      final isEnabled = await BiometricService.isBiometricEnabled(userId);
      setState(() {
        isBiometricSupported = isSupported && canCheck;
        availableBiometrics = available;
        biometricTypeName =
            BiometricService.getBiometricTypeName(available);
        isBiometricEnabled = isEnabled;
        isBioLoading = false;
      });
    } catch (_) {
      setState(() => isBioLoading = false);
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    if (value) {
      final ok = await BiometricService.authenticate(
        reason: 'Verify your identity to enable biometric login',
      );
      if (ok) {
        await BiometricService.setBiometricEnabled(
            userId: userId, enabled: true);
        setState(() => isBiometricEnabled = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$biometricTypeName login enabled'),
            backgroundColor: AppColors.primary,
          ));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Authentication failed'),
            backgroundColor: Colors.red,
          ));
        }
      }
    } else {
      await BiometricService.setBiometricEnabled(
          userId: userId, enabled: false);
      setState(() => isBiometricEnabled = false);
    }
  }

  void _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const AuthGate()),
        (route) => false,
      );
    }
  }

  void _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Account'),
        content: const Text(
          'This will permanently delete your account and all associated children registrations. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final uid = user.uid;

      final studentsSnap = await FirebaseFirestore.instance
          .collection('students')
          .where('parentId', isEqualTo: uid)
          .get();
      for (final doc in studentsSnap.docs) {
        await doc.reference.delete();
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .delete();
      await user.delete();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const AuthGate()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  // ─── Tab labels ────────────────────────────────────────────────────────────
  // static const _tabTitles = ['Home', 'My Children', 'Reports'];

  @override
  Widget build(BuildContext context) {
    return SecuredScreen(
      child: Scaffold(
        // Soft mint background — matches student Settings screen
        backgroundColor: const Color(0xFFEFF6EE),
        // ── No AppBar — header is rendered inline inside each tab ──
        body: isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary))
            : IndexedStack(
                index: _currentIndex,
                children: [
                  _buildHomeTab(),
                  ParentChildrenScreen(
                    myChildren: myChildren,
                    groupNames: groupNames,
                    onRefresh: _loadData,
                  ),
                  ParentReportsScreen(
                    myChildren: myChildren,
                    childReports: childReports,
                    formatDate: formatDate,
                  ),
                ],
              ),
        bottomNavigationBar: AppBottomNavBar(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
          items: const [
            AppNavItem(icon: Icons.home_rounded, label: 'Home'),
            AppNavItem(icon: Icons.people_alt_rounded, label: 'Children'),
            AppNavItem(icon: Icons.description_rounded, label: 'Reports'),
          ],
        ),
      ),
    );
  }

  // ─── Inline page header (replaces AppBar) ──────────────────────────────────
  Widget _buildPageHeader({required String title, List<Widget>? actions}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          if (actions != null) Row(children: actions),
        ],
      ),
    );
  }

  Future<void> _navigateToProfile() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ParentProfileScreen(
          parentName: parentName,
          parentEmail: parentEmail,
          isBiometricSupported: isBiometricSupported,
          isBiometricEnabled: isBiometricEnabled,
          isBioLoading: isBioLoading,
          availableBiometrics: availableBiometrics,
          biometricTypeName: biometricTypeName,
          onToggleBiometric: _toggleBiometric,
          onLogout: _logout,
          onDeleteAccount: _deleteAccount,
        ),
      ),
    );
    if (result == true) _loadData();
  }

 // ─── Home tab ──────────────────────────────────────────────────────────────
  Widget _buildHomeTab() {
    final inGroup = myChildren.where((c) {
      final gid = c['groupId'] as String?;
      return gid != null && gid.isNotEmpty;
    }).length;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Inline header row with title on left, icons on right ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 56, 20, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Home',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                Row(
                  children: [
                    // Notification Badge - Using the reusable widget
                    NotificationBadge(
                      userId: parentUserId ?? '',
                      onTap: _navigateToNotifications,
                    ),
                    const SizedBox(width: 8),
                    // Profile Icon
                    GestureDetector(
                      onTap: _navigateToProfile,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.person_rounded,
                          color: AppColors.primary,
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Welcome card ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 22, vertical: 20),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.25),
                    offset: const Offset(0, 6),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: Text(
                'Hello, $parentName! 👋',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Stats row ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: _summaryCard(
                    icon: Icons.people_alt_rounded,
                    label: 'Children',
                    value: '${myChildren.length}',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _summaryCard(
                    icon: Icons.groups_rounded,
                    label: 'In Groups',
                    value: '$inGroup',
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Section header ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'My Children',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D2D2D),
                  ),
                ),
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _currentIndex = 1),
                  icon: const Icon(Icons.arrow_forward,
                      size: 16, color: AppColors.primary),
                  label: const Text('See all',
                      style: TextStyle(color: AppColors.primary)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          if (myChildren.isEmpty)
            _emptyPlaceholder()
          else
            ...myChildren.take(3).map(
                  (child) => Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: _buildChildSummaryCard(child),
                  ),
                ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // Add navigation method to notifications screen
  Future<void> _navigateToNotifications() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ParentNotificationsScreen(),
      ),
    );
    // Refresh data if coming back from notifications (e.g., after joining a group)
    if (result == true) {
      _loadData();
    }
  }

  // ─── Child summary card (home tab) ────────────────────────────────────────
  Widget _buildChildSummaryCard(Map<String, dynamic> child) {
    final hasGroup =
        (child['groupId'] as String?)?.isNotEmpty == true;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          _childAvatar(child, radius: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  child['names'] ?? 'No name',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 3),
                Text(
                  hasGroup
                      ? groupNames[child['id']] ?? 'Unknown Group'
                      : 'No group assigned',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: hasGroup
                        ? AppColors.primary
                        : Colors.orange,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Avatar ───────────────────────────────────────────────────────────────
  Widget _childAvatar(Map<String, dynamic> child,
      {required double radius}) {
    final avatar = child['avatar'] as String?;
    if (avatar != null && avatar.isNotEmpty) {
      return CircleAvatar(
          radius: radius, backgroundImage: AssetImage(avatar));
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primarySoft(0.15),
      child: Text(
        (child['names'] as String? ?? 'S')[0].toUpperCase(),
        style: TextStyle(
            fontSize: radius * 0.8,
            fontWeight: FontWeight.bold,
            color: AppColors.primary),
      ),
    );
  }

  // ─── Summary card ─────────────────────────────────────────────────────────
  Widget _summaryCard(
      {required IconData icon,
      required String label,
      required String value}) {
    return Container(
      padding:
          const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D2D2D))),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  // ─── Empty state ──────────────────────────────────────────────────────────
  Widget _emptyPlaceholder() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.child_care_rounded,
                size: 64, color: Colors.grey[300]),
            const SizedBox(height: 10),
            Text('No children registered yet',
                style:
                    TextStyle(fontSize: 14, color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }
}