import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/teacher_theme.dart';
import 'package:loringo_app/services/translation/teacher_ui_translations.dart';

class TeacherGroupCard extends StatelessWidget {
  const TeacherGroupCard({
    super.key,
    required this.groupId,
    required this.groupData,
    required this.language,
    required this.onManageStudents,
    required this.onEdit,
    required this.onDelete,
  });

  final String groupId;
  final Map<String, dynamic> groupData;
  final String language;
  final VoidCallback onManageStudents;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: TeacherSpacing.md - 4),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TeacherRadii.md),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(TeacherSpacing.md),
        leading: Container(
          padding: const EdgeInsets.all(TeacherSpacing.md - 4),
          decoration: BoxDecoration(
            color: TeacherColors.primarySoft(0.1),
            borderRadius: BorderRadius.circular(TeacherRadii.md),
          ),
          child: const Icon(
            Icons.group,
            color: TeacherColors.primary,
            size: 28,
          ),
        ),
        title: Text(
          groupData['name'] ?? 'Untitled Group',
          style: TeacherText.cardTitle,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: TeacherSpacing.sm),
            Text(
              groupData['description'] ?? 'No description',
              style: const TextStyle(color: TeacherColors.muted),
            ),
            const SizedBox(height: TeacherSpacing.xs),
            _StudentCountRow(groupId: groupId, language: language),
          ],
        ),
        trailing: _GroupActionsMenu(
          language: language,
          onManageStudents: onManageStudents,
          onEdit: onEdit,
          onDelete: onDelete,
        ),
      ),
    );
  }
}

class _StudentCountRow extends StatelessWidget {
  const _StudentCountRow({required this.groupId, required this.language});

  final String groupId;
  final String language;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('students')
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        final label = TeacherUITranslations.get('studentsLabel', language);
        return Row(
          children: [
            const Icon(Icons.person, size: 14, color: TeacherColors.muted),
            const SizedBox(width: TeacherSpacing.xs),
            Text('$count $label', style: TeacherText.caption),
          ],
        );
      },
    );
  }
}

class _GroupActionsMenu extends StatelessWidget {
  const _GroupActionsMenu({
    required this.language,
    required this.onManageStudents,
    required this.onEdit,
    required this.onDelete,
  });

  final String language;
  final VoidCallback onManageStudents;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  String _t(String key) => TeacherUITranslations.get(key, language);

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'students',
          child: Row(
            children: [
              const Icon(Icons.person_add, color: TeacherColors.primary),
              const SizedBox(width: TeacherSpacing.sm),
              Text(_t('manageStudents')),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              const Icon(Icons.edit, color: Colors.blue),
              const SizedBox(width: TeacherSpacing.sm),
              Text(_t('edit')),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete, color: TeacherColors.danger),
              const SizedBox(width: TeacherSpacing.sm),
              Text(_t('delete')),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        switch (value) {
          case 'students':
            onManageStudents();
            break;
          case 'edit':
            onEdit();
            break;
          case 'delete':
            onDelete();
            break;
        }
      },
    );
  }
}