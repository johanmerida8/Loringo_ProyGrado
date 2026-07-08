// // teacher_group_card.dart
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:flutter/material.dart';
// import 'package:loringo_app/theme/app_theme.dart';

// class TeacherGroupCard extends StatelessWidget {
//   const TeacherGroupCard({
//     super.key,
//     required this.groupId,
//     required this.groupData,
//     required this.language,
//     required this.onManageStudents,
//     required this.onEdit,
//     required this.onDelete,
//   });

//   final String groupId;
//   final Map<String, dynamic> groupData;
//   final String language;
//   final VoidCallback onManageStudents;
//   final VoidCallback onEdit;
//   final VoidCallback onDelete;

//   @override
//   Widget build(BuildContext context) {
//     return Card(
//       margin: const EdgeInsets.only(bottom: AppSpacing.md - 4),
//       elevation: 2,
//       shape: RoundedRectangleBorder(
//         borderRadius: BorderRadius.circular(AppRadii.md),
//       ),
//       child: ListTile(
//         contentPadding: const EdgeInsets.all(AppSpacing.md),
//         leading: Container(
//           padding: const EdgeInsets.all(AppSpacing.md - 4),
//           decoration: BoxDecoration(
//             color: AppColors.primarySoft(0.1),
//             borderRadius: BorderRadius.circular(AppRadii.md),
//           ),
//           child: const Icon(
//             Icons.group,
//             color: AppColors.primary,
//             size: 28,
//           ),
//         ),
//         title: Text(
//           groupData['name'] ?? 'Untitled Group',
//           style: AppText.cardTitle,
//         ),
//         subtitle: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             const SizedBox(height: AppSpacing.sm),
//             Text(
//               groupData['description'] ?? 'No description',
//               style: const TextStyle(color: AppColors.muted),
//             ),
//             const SizedBox(height: AppSpacing.xs),
//             _StudentCountRow(groupId: groupId, language: language),
//           ],
//         ),
//         trailing: _GroupActionsMenu(
//           language: language,
//           onManageStudents: onManageStudents,
//           onEdit: onEdit,
//           onDelete: onDelete,
//         ),
//       ),
//     );
//   }
// }

// class _StudentCountRow extends StatelessWidget {
//   const _StudentCountRow({required this.groupId, required this.language});

//   final String groupId;
//   final String language;

//   @override
//   Widget build(BuildContext context) {
//     return StreamBuilder<QuerySnapshot>(
//       stream: FirebaseFirestore.instance
//           .collection('groups')
//           .doc(groupId)
//           .collection('students')
//           .snapshots(),
//       builder: (context, snapshot) {
//         final count = snapshot.data?.docs.length ?? 0;
//         final label = count == 1 ? '1 student' : '$count students';
//         return Row(
//           children: [
//             const Icon(Icons.person, size: 14, color: AppColors.muted),
//             const SizedBox(width: AppSpacing.xs),
//             Text(label, style: AppText.caption),
//           ],
//         );
//       },
//     );
//   }
// }

// class _GroupActionsMenu extends StatelessWidget {
//   const _GroupActionsMenu({
//     required this.language,
//     required this.onManageStudents,
//     required this.onEdit,
//     required this.onDelete,
//   });

//   final String language;
//   final VoidCallback onManageStudents;
//   final VoidCallback onEdit;
//   final VoidCallback onDelete;

//   @override
//   Widget build(BuildContext context) {
//     return PopupMenuButton<String>(
//       icon: const Icon(Icons.more_vert),
//       itemBuilder: (context) => [
//         PopupMenuItem(
//           value: 'students',
//           child: Row(
//             children: [
//               const Icon(Icons.person_add, color: AppColors.primary),
//               const SizedBox(width: AppSpacing.sm),
//               const Text('Manage Students'),
//             ],
//           ),
//         ),
//         PopupMenuItem(
//           value: 'edit',
//           child: Row(
//             children: [
//               const Icon(Icons.edit, color: AppColors.info),
//               const SizedBox(width: AppSpacing.sm),
//               const Text('Edit Group'),
//             ],
//           ),
//         ),
//         PopupMenuItem(
//           value: 'delete',
//           child: Row(
//             children: [
//               const Icon(Icons.delete, color: AppColors.danger),
//               const SizedBox(width: AppSpacing.sm),
//               const Text('Delete Group'),
//             ],
//           ),
//         ),
//       ],
//       onSelected: (value) {
//         switch (value) {
//           case 'students':
//             onManageStudents();
//             break;
//           case 'edit':
//             onEdit();
//             break;
//           case 'delete':
//             onDelete();
//             break;
//         }
//       },
//     );
//   }
// }