// lib/screens/parent/parent_navigation_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/widget/secured_screen.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/components/app_bottom_nav_bar.dart';
import 'package:loringo_app/components/app_loading_indicator.dart';
import 'package:loringo_app/components/responsive_scaffold.dart';
import 'package:loringo_app/providers/biometric_provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/providers/notification_provider.dart';
import 'package:loringo_app/screens/parent/parent_children_screen.dart';
import 'package:loringo_app/screens/parent/parent_home_screen.dart';
import 'package:loringo_app/screens/shared/notifications_screen.dart';
import 'package:loringo_app/screens/parent/parent_reports_screen.dart';
import 'package:loringo_app/services/auth/auth_gate.dart';
import 'package:loringo_app/services/auth/identity_confirmation.dart';
import 'package:loringo_app/services/database/database.dart';
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

  List<String> get _navLabels =>
      ['common.home'.tr(), 'common.children'.tr(), 'common.reports'.tr()];
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
                ? (groupDoc.data() as Map<String, dynamic>)['name'] as String? ?? 'common.unknownGroup'.tr()
                : 'parent.parent_navigation_screen.groupNotFound'.tr();
          } catch (e) {
            groupNames[student['id']] = 'parent.parent_navigation_screen.errorLoadingGroup'.tr();
          }
        } else {
          groupNames[student['id']] = 'common.noGroupAssigned'.tr();
        }
      }

      await _loadChildReports(students);

      if (mounted) setState(() {});
    } catch (e, stackTrace) {
      debugPrint('Error loading data: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('parent.parent_navigation_screen.errorLoadingData'
                  .tr(namedArgs: {'error': '$e'})),
              backgroundColor: Colors.red),
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
        // Full lifetime history, not just the current group's live
        // reports — walks every group this child has ever been in (see
        // Database.getAllReportsEver) so a parent never loses visibility
        // into a report just because their child switched groups since it
        // was generated.
        final allReports = await Database().getAllReportsEver(studentId);
        allReports.sort((a, b) {
          final at = a['generatedAt'] as Timestamp?;
          final bt = b['generatedAt'] as Timestamp?;
          if (at == null || bt == null) return 0;
          return bt.compareTo(at);
        });

        childReports[studentId] = allReports.map((data) {
          final copy = Map<String, dynamic>.from(data);
          copy['_docId'] = copy['id'];
          return copy;
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
        title: Text('common.deleteAccount'.tr()),
        content: Text('common.deleteAccMsg'.tr()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('common.cancel'.tr())),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('common.delete'.tr(), style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;

    // Confirm a genuinely fresh sign-in BEFORE touching any data —
    // user.delete() below requires one (throws requires-recent-login
    // otherwise), and that check must never fire after the irreversible
    // cascade has already run. See identity_confirmation.dart's
    // reauthenticateWithPassword doc comment for why this can't just
    // reuse confirmIdentity()'s biometric path.
    if (!mounted) return;
    final reauthenticated = await reauthenticateWithPassword(context);
    if (!reauthenticated || !mounted) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final studentsSnap = await FirebaseFirestore.instance
          .collection('students')
          .where('parentId', isEqualTo: user.uid)
          .get();
      for (final doc in studentsSnap.docs) {
        // Full cascade — deletes progress/reports across every group the
        // child was ever in, not just their root profile.
        await Database().deleteStudentCascade(doc.id);
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();
      await user.delete();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const AuthGate()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.code == 'requires-recent-login'
                  ? 'common.requiresRecentLogin'.tr()
                  : 'common.errorWithMessage'.tr(namedArgs: {'error': e.message ?? e.code})),
              backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('common.errorWithMessage'.tr(namedArgs: {'error': '$e'})),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _navigateToNotifications() async {
    final result = await Navigator.push(
        context, MaterialPageRoute(builder: (context) => const NotificationsScreen()));
    if (result == true) _loadData();
  }

  String _formatDate(DateTime date) {
    final months = [
      'common.monthJan'.tr(), 'common.monthFeb'.tr(), 'common.monthMar'.tr(),
      'common.monthApr'.tr(), 'common.monthMay'.tr(), 'common.monthJun'.tr(),
      'common.monthJul'.tr(), 'common.monthAug'.tr(), 'common.monthSep'.tr(),
      'common.monthOct'.tr(), 'common.monthNov'.tr(), 'common.monthDec'.tr(),
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return SecuredScreen(
      child: ResponsiveScaffold(
        headerIcon: Icons.family_restroom_rounded,
        drawerTitle: 'parent.parent_navigation_screen.drawerTitle'.tr(),
        drawerSubtitle: parentName,
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
          showLabels: false,
          items: [
            AppNavItem(icon: Icons.home_rounded, label: _navLabels[0]),
            AppNavItem(icon: Icons.people_alt_rounded, label: _navLabels[1]),
            AppNavItem(icon: Icons.description_rounded, label: _navLabels[2]),
          ],
        ),
        bodyBuilder: (context, isWide) => isLoading
            ? const AppLoadingIndicator()
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
                    childReports: childReports,
                    formatDate: _formatDate,
                    onSeeAllChildren: () => setState(() => _currentIndex = 1),
                    onNavigateToNotifications: _navigateToNotifications,
                    onLogout: _logout,
                    onDeleteAccount: _deleteAccount,
                    onRefresh: _loadData,
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