import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/widget/secured_screen.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/components/app_bottom_nav_bar.dart';
import 'package:loringo_app/components/notification_permission_card.dart';
import 'package:loringo_app/components/notifications_badge.dart';
import 'package:loringo_app/providers/biometric_provider.dart';
import 'package:loringo_app/providers/notification_provider.dart';
import 'package:loringo_app/screens/parent/parent_children_screen.dart';
import 'package:loringo_app/screens/parent/parent_notifications_screen.dart';
import 'package:loringo_app/screens/parent/parent_profile_screen.dart';
import 'package:loringo_app/screens/parent/parent_reports_screen.dart';
import 'package:loringo_app/services/auth/auth_gate.dart';
// import 'package:loringo_app/services/notifications/one_signal_service.dart';
import 'package:loringo_app/theme/app_theme.dart';

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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    super.dispose();
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
      
      // Initialize providers
      try {
        await context.read<BiometricProvider>().initialize(user.uid);
        await context.read<NotificationProvider>().initialize(user.uid);
        debugPrint('Providers initialized for user: $parentUserId');
      } catch (e) {
        debugPrint('Error initializing providers: $e');
      }

      // Fetch user document
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(parentUserId)
          .get();
      
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        parentName = userData['name'] as String? ?? '';
        debugPrint('Parent name loaded: $parentName');
      } else {
        debugPrint('User document not found for UID: $parentUserId');
      }

      // Fetch students
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
      debugPrint('Loaded ${students.length} children');

      // Fetch group names for each student
      for (final student in students) {
        final groupId = student['groupId'] as String?;
        if (groupId != null && groupId.isNotEmpty) {
          try {
            final groupDoc = await FirebaseFirestore.instance
                .collection('teacherGroups')
                .doc(groupId)
                .get();
            
            if (groupDoc.exists) {
              final groupData = groupDoc.data() as Map<String, dynamic>;
              groupNames[student['id']] = groupData['name'] as String? ?? 'Unknown Group';
            } else {
              groupNames[student['id']] = 'Group Not Found';
            }
          } catch (e) {
            debugPrint('Error loading group $groupId for student ${student['id']}: $e');
            groupNames[student['id']] = 'Error Loading Group';
          }
        } else {
          groupNames[student['id']] = 'No Group Assigned';
        }
      }

      // Load child reports
      await _loadChildReports(students);
      
      // Final state update
      if (mounted) {
        setState(() {});
      }
      
    } catch (e, stackTrace) {
      debugPrint('Error loading data: $e');
      debugPrint('Stack trace: $stackTrace');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _loadChildReports(List<Map<String, dynamic>> students) async {
    if (students.isEmpty) {
      debugPrint('No students to load reports for');
      return;
    }
    
    for (final student in students) {
      final studentId = student['id'] as String;
      
      try {
        final reportsSnap = await FirebaseFirestore.instance
            .collection('students')
            .doc(studentId)
            .collection('reports')
            .orderBy('generatedAt', descending: true)
            .get();
        
        final reports = reportsSnap.docs.map((doc) {
          final data = doc.data();
          data['_docId'] = doc.id;
          return data;
        }).toList();
        
        childReports[studentId] = reports;
        debugPrint('Loaded ${reports.length} reports for student: $studentId');
        
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
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red)
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SecuredScreen(
      child: Scaffold(
        backgroundColor: const Color(0xFFEFF6EE),
        body: isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
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
                    formatDate: _formatDate,
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

  Widget _buildHomeTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 56, 20, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Home', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.primary)),
                Row(
                  children: [
                    NotificationBadge(userId: parentUserId ?? '', onTap: _navigateToNotifications),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ParentProfileScreen(
                            parentName: parentName,
                            parentEmail: parentEmail,
                            parentId: parentUserId,
                            onLogout: _logout,
                            onDeleteAccount: _deleteAccount,
                          ),
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.person_rounded, color: AppColors.primary, size: 24),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
              child: Text('Hello, $parentName!', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(child: _summaryCard(icon: Icons.people_alt_rounded, label: 'Children', value: '${myChildren.length}')),
                const SizedBox(width: 12),
                Expanded(child: _summaryCard(icon: Icons.groups_rounded, label: 'In Groups', value: '${myChildren.where((c) => (c['groupId'] as String?)?.isNotEmpty == true).length}')),
              ],
            ),
          ),
          // Notification Permission Card using Provider
          if (!kIsWeb)
            Consumer<NotificationProvider>(
              builder: (context, notificationProvider, child) {
                if (notificationProvider.isLoading) {
                  return const SizedBox.shrink();
                }
                
                if (!notificationProvider.isEnabled && !notificationProvider.isPermanentlyDenied) {
                  return NotificationPermissionCard(
                    onRequestPermission: () async {
                      await notificationProvider.enableNotifications(context);
                    },
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('My Children', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                TextButton.icon(onPressed: () => setState(() => _currentIndex = 1), icon: const Icon(Icons.arrow_forward, size: 16), label: const Text('See all')),
              ],
            ),
          ),
          if (myChildren.isEmpty)
            _emptyPlaceholder()
          else
            ...myChildren.take(3).map((child) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: _buildChildSummaryCard(child),
            )),
        ],
      ),
    );
  }

  Widget _buildChildSummaryCard(Map<String, dynamic> child) {
    final hasGroup = (child['groupId'] as String?)?.isNotEmpty == true;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.primarySoft(0.15),
            child: Text((child['names'] as String? ?? 'S')[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(child['names'] ?? 'No name', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                Text(hasGroup ? groupNames[child['id']] ?? 'Unknown Group' : 'No group assigned', style: TextStyle(fontSize: 12, color: hasGroup ? AppColors.primary : Colors.orange)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard({required IconData icon, required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: AppColors.primary, size: 22)),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _emptyPlaceholder() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.child_care_rounded, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 10),
            Text('No children registered yet', style: TextStyle(color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }

  Future<void> _navigateToNotifications() async {
    final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => const ParentNotificationsScreen()));
    if (result == true) _loadData();
  }

  String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}