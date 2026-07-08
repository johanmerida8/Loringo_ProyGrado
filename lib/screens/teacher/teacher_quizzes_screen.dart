// teacher_quizzes_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/group_details/quizzes_tab.dart';
import 'package:loringo_app/theme/app_theme.dart';

class TeacherQuizzesScreen extends StatelessWidget {
  const TeacherQuizzesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final teacherId = FirebaseAuth.instance.currentUser?.uid;
    if (teacherId == null) {
      return const Scaffold(
        body: Center(child: Text('Not authenticated')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: QuizzesTab(
        groupId: '',
        groupColor: AppColors.primary,
        showBackButton: true,
      ),
    );
  }
}