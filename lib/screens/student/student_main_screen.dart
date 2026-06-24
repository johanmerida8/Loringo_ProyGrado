import 'package:flutter/material.dart';
import 'package:loringo_app/components/app_bottom_nav_bar.dart';
import 'package:loringo_app/screens/student/student_activities_screen.dart';
// import 'package:loringo_app/screens/student/student_group_screen.dart';
import 'package:loringo_app/screens/student/student_league_screen.dart';
import 'package:loringo_app/screens/student/student_settings_screen.dart';
import 'package:loringo_app/widget/secured_screen.dart';

class StudentMainScreen extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String? studentAvatar;

  const StudentMainScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    this.studentAvatar,
  });

  @override
  State<StudentMainScreen> createState() => _StudentMainScreenState();
}

class _StudentMainScreenState extends State<StudentMainScreen> {
  int _currentIndex = 0;

  late final List<Widget> _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = [
      StudentActivitiesTab(
        studentId: widget.studentId,
        studentName: widget.studentName,
        studentAvatar: widget.studentAvatar,
      ),
      // StudentGroupTab(
      //   studentId: widget.studentId,
      //   studentName: widget.studentName,
      //   studentAvatar: widget.studentAvatar,
      // ),
      StudentLeagueTab(
        studentId: widget.studentId,
        studentName: widget.studentName,
      ),
      StudentSettingsTab(
        studentId: widget.studentId,
        studentName: widget.studentName,
        studentAvatar: widget.studentAvatar!,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return SecuredScreen(
      isStudent: true,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFE8F5E9), Colors.white],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: IndexedStack(
            index: _currentIndex,
            children: _tabs,
          ),
        ),
        bottomNavigationBar: AppBottomNavBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          items: const [
            AppNavItem(icon: Icons.home_rounded, label: 'Home'),
            // AppNavItem(icon: Icons.groups_rounded, label: 'Group'),
            AppNavItem(icon: Icons.emoji_events_rounded, label: 'League'),
            AppNavItem(icon: Icons.settings_rounded, label: 'Settings'),
          ],
        ),
      ),
    );
  }
}