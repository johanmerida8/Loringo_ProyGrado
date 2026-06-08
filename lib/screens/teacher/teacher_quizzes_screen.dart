// teacher_quizzes_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/group_details/quizzes_tab.dart';
import 'package:loringo_app/services/database/database.dart';
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
    final db = Database();

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.onPrimary),
        title: const Text('Quizzes', style: AppText.appBarTitle),
      ),
      body: QuizzesTab(
        groupId:       '',
        groupColor:    AppColors.primary,
        contentStream: db.getTeacherApprovedContentStream(teacherId),
      ),
    );
  }
}