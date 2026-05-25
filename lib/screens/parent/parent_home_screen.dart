import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:loringo_app/components/app_bottom_nav_bar.dart';
import 'package:loringo_app/screens/parent/parent_join_group_screen.dart';
import 'package:loringo_app/screens/parent/parent_notifications_screen.dart';
import 'package:loringo_app/screens/parent/parent_register_child_screen.dart';
import 'package:loringo_app/services/auth/auth_gate.dart';
import 'package:loringo_app/services/auth/biometric_service.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ParentHomeScreen extends StatefulWidget {
  const ParentHomeScreen({super.key});

  @override
  State<ParentHomeScreen> createState() => _ParentHomeScreenState();
}

class _ParentHomeScreenState extends State<ParentHomeScreen> {
  int _currentIndex = 0;
  static const _tabTitles = ['Parent Panel', 'My Children', 'Reports', 'Profile'];

  List<Map<String, dynamic>> myChildren = [];
  Map<String, String> groupNames = {};
  Map<String, List<Map<String, dynamic>>> childReports = {};
  bool isLoading = true;
  int unreadNotifications = 0;
  String? parentUserId;

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

      final notifSnap = await FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: parentUserId)
          .where('isRead', isEqualTo: false)
          .get();
      setState(() => unreadNotifications = notifSnap.docs.length);

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
              setState(() => groupNames[s['id']] = gDoc.data()?['name'] ?? 'Unknown Group');
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
        biometricTypeName = BiometricService.getBiometricTypeName(available);
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
        await BiometricService.setBiometricEnabled(userId: userId, enabled: true);
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
      await BiometricService.setBiometricEnabled(userId: userId, enabled: false);
      setState(() => isBiometricEnabled = false);
    }
  }

  void _showAccessCodeDialog(Map<String, dynamic> child) {
    final accessCode = child['accessCode'] as String?;
    if (accessCode == null || accessCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Access code not available'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primarySoft(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.key_rounded, color: AppColors.primary, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text("${child['names']}'s Code",
                  style: const TextStyle(fontSize: 18)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Share this code with your child to log in:',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              decoration: BoxDecoration(
                color: AppColors.primarySoft(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary, width: 2),
              ),
              child: Text(
                accessCode,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 6,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: accessCode));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Code copied'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 2),
                ));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy Code'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _navigateToJoinGroup(Map<String, dynamic> child) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ParentJoinGroupScreen(child: child)),
    );
    if (result == true) _loadData();
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
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

      final notifSnap = await FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: uid)
          .get();
      for (final doc in notifSnap.docs) {
        await doc.reference.delete();
      }

      await FirebaseFirestore.instance.collection('users').doc(uid).delete();
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
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAEDCA),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        title: Text(
          _tabTitles[_currentIndex],
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_rounded, color: Colors.white),
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ParentNotificationsScreen(),
                    ),
                  );
                  if (result == true) _loadData();
                },
              ),
              if (unreadNotifications > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    child: Text(
                      unreadNotifications > 99 ? '99+' : '$unreadNotifications',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : IndexedStack(
              index: _currentIndex,
              children: [
                _buildHomeTab(),
                _buildChildrenTab(),
                _buildReportsTab(),
                _buildProfileTab(),
              ],
            ),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          AppNavItem(icon: Icons.home_rounded, label: 'Home'),
          AppNavItem(icon: Icons.people_alt_rounded, label: 'Children'),
          AppNavItem(icon: Icons.description_rounded, label: 'Reports'),
          AppNavItem(icon: Icons.person_rounded, label: 'Profile'),
        ],
      ),
    );
  }

  Widget _buildHomeTab() {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    final inGroup = myChildren
        .where((c) {
          final gid = c['groupId'] as String?;
          return gid != null && gid.isNotEmpty;
        })
        .length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppDecorations.primaryGradient,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primarySoft(0.3),
                  offset: const Offset(0, 4),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Hello, Parent',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(email,
                    style: const TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Summary row
          Row(
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

          const SizedBox(height: 24),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'My Children',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _currentIndex = 1),
                icon: const Icon(Icons.arrow_forward,
                    size: 16, color: AppColors.primary),
                label: const Text('See all',
                    style: TextStyle(color: AppColors.primary)),
              ),
            ],
          ),

          const SizedBox(height: 8),

          if (myChildren.isEmpty)
            _emptyPlaceholder()
          else
            ...myChildren.map((child) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildChildCard(child, showActions: false),
                )),
        ],
      ),
    );
  }

  Widget _buildChildrenTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const ParentRegisterChildScreen()),
                );
                if (result == true) _loadData();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add Child',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),

          const SizedBox(height: 20),

          if (myChildren.isEmpty)
            _emptyPlaceholder()
          else
            ...myChildren.map((child) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _buildChildCard(child, showActions: true),
                )),
        ],
      ),
    );
  }

  Widget _buildReportsTab() {
    if (myChildren.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.description_rounded, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('No children registered yet',
                style: TextStyle(fontSize: 16, color: Colors.grey[500])),
          ],
        ),
      );
    }

    final totalReports =
        childReports.values.fold<int>(0, (s, l) => s + l.length);

    final List<Widget> content = [];

    if (totalReports == 0) {
      content.add(
        Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
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
              Icon(Icons.description_outlined,
                  size: 64, color: Colors.grey[300]),
              const SizedBox(height: 12),
              const Text('No reports yet',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey)),
              const SizedBox(height: 6),
              Text(
                'Reports appear here once your child\ncompletes a unit quiz',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      );
    } else {
      for (final child in myChildren) {
        final childId = child['id'] as String;
        final reports = childReports[childId] ?? [];
        if (reports.isEmpty) continue;

        content.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                _childAvatar(child, radius: 18),
                const SizedBox(width: 10),
                Text(
                  child['names'] ?? 'Child',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${reports.length} report${reports.length != 1 ? 's' : ''}',
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );

        for (final report in reports) {
          content.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _buildReportCard(child: child, report: report),
            ),
          );
        }
        content.add(const SizedBox(height: 6));
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: content,
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Widget _buildProfileTab() {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Account info
          _sectionCard(
            title: 'Account',
            icon: Icons.person_rounded,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: AppColors.primarySoft(0.15),
                child: const Icon(Icons.email_rounded, color: AppColors.primary),
              ),
              title: const Text('Email',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(email),
            ),
          ),

          const SizedBox(height: 16),

          // Security / biometrics
          _sectionCard(
            title: 'Security',
            icon: Icons.fingerprint_rounded,
            child: isBioLoading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : isBiometricSupported
                    ? SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(biometricTypeName,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: const Text('Use biometrics to sign in'),
                        value: isBiometricEnabled,
                        activeColor: AppColors.primary,
                        onChanged: _toggleBiometric,
                      )
                    : const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Biometrics not available on this device',
                            style: TextStyle(color: Colors.grey)),
                      ),
          ),

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _logout,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Log Out',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),

          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _deleteAccount,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.delete_forever_rounded),
              label: const Text('Delete Account',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChildCard(Map<String, dynamic> child,
      {required bool showActions}) {
    final hasGroup = (child['groupId'] as String?)?.isNotEmpty == true;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _childAvatar(child, radius: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(child['names'] ?? 'No name',
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        hasGroup
                            ? '${groupNames[child['id']] ?? 'Loading...'}'
                            : 'No group assigned',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: hasGroup ? AppColors.primary : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (showActions) ...[
              const SizedBox(height: 14),
              if (!hasGroup)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _navigateToJoinGroup(child),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Join Group',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showAccessCodeDialog(child),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.key_rounded),
                  label: const Text('View Access Code',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReportCard({
    required Map<String, dynamic> child,
    required Map<String, dynamic> report,
  }) {
    final reportType = report['reportType'] as String? ?? 'unit';
    final unitTitle = report['unitTitle'] as String? ?? 'Unknown Unit';
    final quizPercent = (report['quizPercent'] as num?)?.toInt() ?? 0;
    final quizCorrect = (report['quizCorrect'] as num?)?.toInt() ?? 0;
    final quizIncorrect = (report['quizIncorrect'] as num?)?.toInt() ?? 0;
    final quizTotal = (report['quizTotalQuestions'] as num?)?.toInt() ?? 0;
    final activitiesCompleted =
        (report['activitiesCompleted'] as num?)?.toInt() ?? 0;
    final totalActivities =
        (report['totalActivities'] as num?)?.toInt() ?? 0;
    final activitiesPercent =
        (report['activitiesPercent'] as num?)?.toInt() ?? 0;
    final previousScores = List<int>.from(
        ((report['previousUnitScores'] as List?) ?? [])
            .map((e) => (e as num).toInt()));
    final generatedAt = report['generatedAt'] as Timestamp?;
    final dateStr =
        generatedAt != null ? _formatDate(generatedAt.toDate()) : 'Recently';

    final isContent = reportType == 'content';
    final typeColor =
        isContent ? const Color(0xFF7C3AED) : AppColors.primary;
    final typeLabel = isContent ? 'Final' : 'Unit';

    final scoreColor = quizPercent >= 80
        ? const Color(0xFF4CAF50)
        : quizPercent >= 60
            ? const Color(0xFFFFC107)
            : const Color(0xFFFF7043);

    return Card(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: type badge + unit title + date
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    typeLabel,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: typeColor),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    unitTitle,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
                Text(dateStr,
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ),

            const SizedBox(height: 14),
            const Divider(
                height: 1, thickness: 1, color: Color(0xFFF0F0F0)),
            const SizedBox(height: 14),

            // Metrics: quiz | activities
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.quiz_rounded,
                            size: 13, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text('Quiz',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500],
                                fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 6),
                      Text(
                        '$quizPercent%',
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: scoreColor),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$quizCorrect✓  $quizIncorrect✗  / $quizTotal',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Container(
                    width: 1,
                    height: 64,
                    color: const Color(0xFFF0F0F0)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.task_alt_rounded,
                            size: 13, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text('Activities',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500],
                                fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 6),
                      Text(
                        '$activitiesPercent%',
                        style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF4CAF50)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$activitiesCompleted / $totalActivities done',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Trend
            if (previousScores.isNotEmpty) ...[  
              const SizedBox(height: 12),
              const Divider(
                  height: 1, thickness: 1, color: Color(0xFFF0F0F0)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.trending_up_rounded,
                      size: 14, color: Colors.blueGrey[400]),
                  const SizedBox(width: 6),
                  Text('Trend: ',
                      style: TextStyle(
                          fontSize: 12, color: Colors.blueGrey[400])),
                  Expanded(
                    child: Wrap(
                      spacing: 4,
                      children: [
                        ...previousScores.map((s) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text('$s%',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.blueGrey)),
                            )),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: scoreColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('$quizPercent%',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: scoreColor)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 14),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () =>
                    _exportReportPdf(child: child, report: report),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(
                      color: AppColors.primary, width: 1.2),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                label: const Text('Export PDF',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportReportPdf({
    required Map<String, dynamic> child,
    required Map<String, dynamic> report,
  }) async {
    final pdf = pw.Document();
    final childName = (child['names'] as String?) ?? 'Student';
    final reportType =
        (report['reportType'] as String?) == 'content' ? 'Final' : 'Unit';
    final unitTitle = (report['unitTitle'] as String?) ?? 'Unit';
    final quizPercent = (report['quizPercent'] as num?)?.toInt() ?? 0;
    final quizCorrect = (report['quizCorrect'] as num?)?.toInt() ?? 0;
    final quizIncorrect = (report['quizIncorrect'] as num?)?.toInt() ?? 0;
    final quizTotal = (report['quizTotalQuestions'] as num?)?.toInt() ?? 0;
    final activitiesCompleted =
        (report['activitiesCompleted'] as num?)?.toInt() ?? 0;
    final totalActivities =
        (report['totalActivities'] as num?)?.toInt() ?? 0;
    final activitiesPercent =
        (report['activitiesPercent'] as num?)?.toInt() ?? 0;
    final previousScores = List<int>.from(
        ((report['previousUnitScores'] as List?) ?? [])
            .map((e) => (e as num).toInt()));
    final generatedAt = report['generatedAt'] as Timestamp?;
    final dateStr =
        generatedAt != null ? _formatDate(generatedAt.toDate()) : 'N/A';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Loringo — $reportType Report',
                style: pw.TextStyle(
                    fontSize: 22, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Student: $childName',
                    style: const pw.TextStyle(fontSize: 13)),
                pw.Text('Date: $dateStr',
                    style: const pw.TextStyle(fontSize: 13)),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Text('Unit: $unitTitle',
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 20),
            pw.Text('Quiz Results',
                style: pw.TextStyle(
                    fontSize: 15, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headers: ['Metric', 'Value'],
              data: [
                ['Score', '$quizPercent%'],
                ['Correct answers', '$quizCorrect / $quizTotal'],
                ['Incorrect answers', '$quizIncorrect'],
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Text('Activity Progress',
                style: pw.TextStyle(
                    fontSize: 15, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headers: ['Metric', 'Value'],
              data: [
                [
                  'Activities completed',
                  '$activitiesCompleted / $totalActivities'
                ],
                ['Completion rate', '$activitiesPercent%'],
              ],
            ),
            if (previousScores.isNotEmpty) ...[  
              pw.SizedBox(height: 16),
              pw.Text('Progress Trend',
                  style: pw.TextStyle(
                      fontSize: 15, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Text(
                '${previousScores.map((s) => '$s%').join(' \u2192 ')}  \u2192  $quizPercent% (this unit)',
              ),
            ],
            pw.Spacer(),
            pw.Divider(),
            pw.Text(
                'Generated by Loringo \u00b7 ${DateTime.now().year}',
                style: const pw.TextStyle(
                    fontSize: 10, color: PdfColors.grey)),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name:
          '${childName.replaceAll(' ', '_')}_${unitTitle.replaceAll(' ', '_')}_report.pdf',
    );
  }


  Widget _childAvatar(Map<String, dynamic> child, {required double radius}) {
    final avatar = child['avatar'] as String?;
    if (avatar != null && avatar.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: AssetImage(avatar),
        backgroundColor: AppColors.primarySoft(0.15),
      );
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

  Widget _summaryCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primarySoft(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
              Text(label,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
            ],
          ),
          const Divider(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _emptyPlaceholder() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(Icons.child_care_rounded, size: 72, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('No children registered yet',
                style: TextStyle(fontSize: 15, color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }
}
