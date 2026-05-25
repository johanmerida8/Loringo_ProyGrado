import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/group_details/quizzes_tab.dart';
import 'package:loringo_app/theme/app_theme.dart';

/// Full-screen wrapper for the group quizzes creation screen.
class GroupQuizzesScreen extends StatelessWidget {
  final String groupId;
  final Color groupColor;

  const GroupQuizzesScreen({
    super.key,
    required this.groupId,
    required this.groupColor,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        title: const Text(
          'Quizzes',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: QuizzesTab(groupId: groupId, groupColor: groupColor),
    );
  }
}
