// import 'package:flutter/material.dart';
// import 'package:loringo_app/screens/teacher/teacher_theme.dart';

// class TeacherEmptyState extends StatelessWidget {
//   const TeacherEmptyState({
//     super.key,
//     required this.icon,
//     required this.title,
//     required this.subtitle,
//     this.iconSize = 100,
//   });

//   final IconData icon;
//   final String title;
//   final String subtitle;
//   final double iconSize;

//   @override
//   Widget build(BuildContext context) {
//     return Center(
//       child: Padding(
//         padding: const EdgeInsets.all(TeacherSpacing.xl),
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             Icon(icon, size: iconSize, color: TeacherColors.primary),
//             const SizedBox(height: TeacherSpacing.lg),
//             Text(title, style: TeacherText.h1, textAlign: TextAlign.center),
//             const SizedBox(height: TeacherSpacing.md - 4),
//             Text(
//               subtitle,
//               textAlign: TextAlign.center,
//               style: TeacherText.subtitle,
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }