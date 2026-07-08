// lib/screens/parent/parent_navigation_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/widget/secured_screen.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/components/app_bottom_nav_bar.dart';
import 'package:loringo_app/components/responsive_scaffold.dart';
import 'package:loringo_app/providers/biometric_provider.dart';
import 'package:loringo_app/providers/notification_provider.dart';
import 'package:loringo_app/screens/parent/parent_children_screen.dart';
import 'package:loringo_app/screens/parent/parent_home_screen.dart';
import 'package:loringo_app/screens/parent/parent_notifications_screen.dart';
import 'package:loringo_app/screens/parent/parent_reports_screen.dart';
import 'package:loringo_app/services/auth/auth_gate.dart';
import 'package:loringo_app/theme/app_theme.dart';

class ParentNavigationScreen extends StatefulWidget {
  const ParentNavigationScreen({super.key});

  @override
  State<ParentNavigationScreen> createState() => _ParentNavigationScreenState();
}

class _ParentNavigationScreenState extends State<ParentNavigationScreen> {
  int _currentIndex = 0;
  List<Map<String, dynamic>> myChildren = [];
  Map<String, String> groupNames = {};
  Map<String, List<Map<String, dynamic>>> childReports = {};
  bool isLoading = true;
  String? parentUserId;
  String parentName = '';
  String parentEmail = '';

  static const _navLabels = ['Home', 'Children', 'Reports'];
  static const _navIcons = [
    Icons.home_rounded,
    Icons.people_alt_rounded,
    Icons.description_rounded,
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('No user logged in');
        return;
      }

      parentUserId = user.uid;
      parentEmail = user.email ?? '';

      try {
        await context.read<BiometricProvider>().initialize(user.uid);
        await context.read<NotificationProvider>().initialize(user.uid);
      } catch (e) {
        debugPrint('Error initializing providers: $e');
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(parentUserId)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        parentName = userData['name'] as String? ?? '';
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

      for (final student in students) {
        final groupId = student['groupId'] as String?;
        if (groupId != null && groupId.isNotEmpty) {
          try {
            final groupDoc = await FirebaseFirestore.instance
                .collection('teacherGroups')
                .doc(groupId)
                .get();

            groupNames[student['id']] = groupDoc.exists
                ? (groupDoc.data() as Map<String, dynamic>)['name'] as String? ?? 'Unknown Group'
                : 'Group Not Found';
          } catch (e) {
            groupNames[student['id']] = 'Error Loading Group';
          }
        } else {
          groupNames[student['id']] = 'No Group Assigned';
        }
      }

      await _loadChildReports(students);

      if (mounted) setState(() {});
    } catch (e, stackTrace) {
      debugPrint('Error loading data: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _loadChildReports(List<Map<String, dynamic>> students) async {
    if (students.isEmpty) return;

    for (final student in students) {
      final studentId = student['id'] as String;
      try {
        final reportsSnap = await FirebaseFirestore.instance
            .collection('students')
            .doc(studentId)
            .collection('reports')
            .orderBy('generatedAt', descending: true)
            .get();

        childReports[studentId] = reportsSnap.docs.map((doc) {
          final data = doc.data();
          data['_docId'] = doc.id;
          return data;
        }).toList();
      } catch (e) {
        debugPrint('Error loading reports for student $studentId: $e');
        childReports[studentId] = [];
      }
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
        title: const Text('Delete Account'),
        content: const Text('This action is permanent and cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final studentsSnap = await FirebaseFirestore.instance
          .collection('students')
          .where('parentId', isEqualTo: user.uid)
          .get();
      for (final doc in studentsSnap.docs) {
        await doc.reference.delete();
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();
      await user.delete();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const AuthGate()),
          (route) => false,
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _navigateToNotifications() async {
    final result = await Navigator.push(
        context, MaterialPageRoute(builder: (context) => const ParentNotificationsScreen()));
    if (result == true) _loadData();
  }

  String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return SecuredScreen(
      child: ResponsiveScaffold(
        headerIcon: Icons.family_restroom_rounded,
        drawerTitle: parentName.isNotEmpty ? parentName : 'Parent',
        drawerSubtitle: parentEmail,
        hideBottomNavOnWide: true,
        parentName: parentName,
        parentEmail: parentEmail,
        onParentLogout: _logout,
        onParentDeleteAccount: _deleteAccount,
        navItemsBuilder: (context, isWide) => [
          for (var i = 0; i < _navLabels.length; i++)
            ListTile(
              leading: Icon(_navIcons[i], color: AppColors.primary),
              title: Text(_navLabels[i]),
              selected: _currentIndex == i,
              selectedTileColor: AppColors.primarySoft(0.08),
              trailing: _currentIndex == i
                  ? const Icon(Icons.check_circle, color: AppColors.primary)
                  : null,
              onTap: () {
                setState(() => _currentIndex = i);
                if (!isWide && Navigator.canPop(context)) Navigator.pop(context);
              },
            ),
        ],
        bottomNavigationBar: AppBottomNavBar(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
          items: const [
            AppNavItem(icon: Icons.home_rounded, label: 'Home'),
            AppNavItem(icon: Icons.people_alt_rounded, label: 'Children'),
            AppNavItem(icon: Icons.description_rounded, label: 'Reports'),
          ],
        ),
        bodyBuilder: (context, isWide) => isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : IndexedStack(
                index: _currentIndex,
                children: [
                  ParentHomeScreen(
                    isWide: isWide,
                    parentName: parentName,
                    parentEmail: parentEmail,
                    parentUserId: parentUserId,
                    myChildren: myChildren,
                    groupNames: groupNames,
                    onSeeAllChildren: () => setState(() => _currentIndex = 1),
                    onNavigateToNotifications: _navigateToNotifications,
                    onLogout: _logout,
                    onDeleteAccount: _deleteAccount,
                  ),
                  ParentChildrenScreen(
                    myChildren: myChildren,
                    groupNames: groupNames,
                    onRefresh: _loadData,
                  ),
                  ParentReportsScreen(
                    myChildren: myChildren,
                    childReports: childReports,
                    formatDate: _formatDate,
                  ),
                ],
              ),
      ),
    );
  }
}