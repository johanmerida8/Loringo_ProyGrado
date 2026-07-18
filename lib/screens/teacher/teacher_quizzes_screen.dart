// teacher_quizzes_screen.dart
//
// Sin cambios respecto a tu versión original: ya delega correctamente a
// QuizzesTab sin AppBar propio. Se incluye aquí solo para que el set de
// archivos de esta entrega quede completo y no haya que ir a buscarlo por
// separado.

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