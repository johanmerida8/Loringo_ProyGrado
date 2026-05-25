import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/teacher_theme.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_confirm_dialog.dart';
import 'package:loringo_app/services/translation/teacher_ui_translations.dart';

void showCreateGroupDialog({
  required BuildContext context,
  required String language,
  String? groupId,
  Map<String, dynamic>? existingData,
}) {
  final nameController = TextEditingController(text: existingData?['name']);
  final descriptionController = TextEditingController(
    text: existingData?['description'],
  );

  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.group, color: TeacherColors.primary),
          const SizedBox(width: TeacherSpacing.sm),
          Text(
            groupId == null
                ? TeacherUITranslations.get('createGroup', language)
                : TeacherUITranslations.get('edit', language),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RoundedTextField(
            controller: nameController,
            labelKey: 'groupName',
            language: language,
            icon: Icons.group,
          ),
          const SizedBox(height: TeacherSpacing.md),
          _RoundedTextField(
            controller: descriptionController,
            labelKey: 'description',
            language: language,
            icon: Icons.description,
            maxLines: 3,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(TeacherUITranslations.get('cancel', language)),
        ),
        ElevatedButton(
          onPressed: () => _saveGroup(
            dialogContext: dialogContext,
            language: language,
            groupId: groupId,
            name: nameController.text.trim(),
            description: descriptionController.text.trim(),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: TeacherColors.primary,
          ),
          child: Text(
            groupId == null
                ? TeacherUITranslations.get('createEdit', language)
                : TeacherUITranslations.get('update', language),
            style: const TextStyle(color: TeacherColors.onPrimary),
          ),
        ),
      ],
    ),
  );
}

Future<void> _saveGroup({
  required BuildContext dialogContext,
  required String language,
  required String? groupId,
  required String name,
  required String description,
}) async {
  if (name.isEmpty) {
    ScaffoldMessenger.of(dialogContext).showSnackBar(
      SnackBar(
        content: Text(
          TeacherUITranslations.get('groupNameRequired', language),
        ),
        backgroundColor: TeacherColors.danger,
      ),
    );
    return;
  }

  final teacherId = FirebaseAuth.instance.currentUser?.uid;
  final groups = FirebaseFirestore.instance.collection('groups');

  if (groupId == null) {
    await groups.add({
      'name': name,
      'description': description,
      'teacherId': teacherId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  } else {
    await groups.doc(groupId).update({
      'name': name,
      'description': description,
    });
  }

  if (!dialogContext.mounted) return;
  Navigator.pop(dialogContext);
  ScaffoldMessenger.of(dialogContext).showSnackBar(
    SnackBar(
      content: Text(
        groupId == null
            ? 'Group created successfully'
            : 'Group updated successfully',
      ),
      backgroundColor: TeacherColors.success,
    ),
  );
}

void showManageStudentsDialog({
  required BuildContext context,
  required String groupId,
  required Map<String, dynamic> groupData,
  required String language,
}) {
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.person_add, color: TeacherColors.primary),
          const SizedBox(width: TeacherSpacing.sm),
          Expanded(
            child: Text(
              '${TeacherUITranslations.get('manageStudents', language)} - ${groupData['name']}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              TeacherUITranslations.get('addStudentsHint', language),
              style: const TextStyle(color: TeacherColors.muted),
            ),
            const SizedBox(height: TeacherSpacing.md),
            _StudentList(groupId: groupId, language: language),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(TeacherUITranslations.get('close', language)),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(dialogContext);
            showAddStudentDialog(
              context: context,
              groupId: groupId,
              language: language,
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: TeacherColors.primary,
          ),
          child: Text(
            TeacherUITranslations.get('addStudent', language),
            style: const TextStyle(color: TeacherColors.onPrimary),
          ),
        ),
      ],
    ),
  );
}

void showAddStudentDialog({
  required BuildContext context,
  required String groupId,
  required String language,
}) {
  final emailController = TextEditingController();

  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.person_add, color: TeacherColors.primary),
          const SizedBox(width: TeacherSpacing.sm),
          Text(TeacherUITranslations.get('addStudent', language)),
        ],
      ),
      content: _RoundedTextField(
        controller: emailController,
        labelKey: 'studentEmail',
        language: language,
        icon: Icons.email,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(TeacherUITranslations.get('cancel', language)),
        ),
        ElevatedButton(
          onPressed: () => _addStudentByEmail(
            dialogContext: dialogContext,
            groupId: groupId,
            language: language,
            email: emailController.text.trim(),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: TeacherColors.primary,
          ),
          child: Text(
            TeacherUITranslations.get('add', language),
            style: const TextStyle(color: TeacherColors.onPrimary),
          ),
        ),
      ],
    ),
  );
}

Future<void> _addStudentByEmail({
  required BuildContext dialogContext,
  required String groupId,
  required String language,
  required String email,
}) async {
  if (email.isEmpty) {
    ScaffoldMessenger.of(dialogContext).showSnackBar(
      SnackBar(
        content: Text(TeacherUITranslations.get('emailRequired', language)),
        backgroundColor: TeacherColors.danger,
      ),
    );
    return;
  }

  final userQuery = await FirebaseFirestore.instance
      .collection('users')
      .where('email', isEqualTo: email)
      .where('role', isEqualTo: 'student')
      .get();

  if (userQuery.docs.isEmpty) {
    if (!dialogContext.mounted) return;
    ScaffoldMessenger.of(dialogContext).showSnackBar(
      SnackBar(
        content: Text(
          TeacherUITranslations.get('studentNotFound', language),
        ),
        backgroundColor: TeacherColors.danger,
      ),
    );
    return;
  }

  final studentDoc = userQuery.docs.first;
  final studentData = studentDoc.data();

  await FirebaseFirestore.instance
      .collection('groups')
      .doc(groupId)
      .collection('students')
      .doc(studentDoc.id)
      .set({
        'name': studentData['name'],
        'email': studentData['email'],
        'addedAt': FieldValue.serverTimestamp(),
      });

  if (!dialogContext.mounted) return;
  Navigator.pop(dialogContext);
  ScaffoldMessenger.of(dialogContext).showSnackBar(
    SnackBar(
      content: Text(TeacherUITranslations.get('studentAdded', language)),
      backgroundColor: TeacherColors.success,
    ),
  );
}

Future<void> confirmAndDeleteGroup({
  required BuildContext context,
  required String groupId,
  required String language,
}) async {
  final confirmed = await showTeacherConfirmDialog(
    context: context,
    title: TeacherUITranslations.get('deleteGroup', language),
    message: TeacherUITranslations.get('deleteGroupConfirm', language),
    confirmLabel: TeacherUITranslations.get('delete', language),
    cancelLabel: TeacherUITranslations.get('cancel', language),
  );

  if (!confirmed) return;

  await FirebaseFirestore.instance
      .collection('groups')
      .doc(groupId)
      .delete();

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Group deleted successfully'),
      backgroundColor: TeacherColors.success,
    ),
  );
}

class _StudentList extends StatelessWidget {
  const _StudentList({required this.groupId, required this.language});

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
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Text(
            TeacherUITranslations.get('noStudentsYet', language),
            style: const TextStyle(color: TeacherColors.muted),
          );
        }

        return SizedBox(
          height: 200,
          child: ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(data['name'] ?? 'Unknown'),
                subtitle: Text(data['email'] ?? ''),
                trailing: IconButton(
                  icon: const Icon(
                    Icons.remove_circle,
                    color: TeacherColors.danger,
                  ),
                  onPressed: () => FirebaseFirestore.instance
                      .collection('groups')
                      .doc(groupId)
                      .collection('students')
                      .doc(doc.id)
                      .delete(),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _RoundedTextField extends StatelessWidget {
  const _RoundedTextField({
    required this.controller,
    required this.labelKey,
    required this.language,
    required this.icon,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String labelKey;
  final String language;
  final IconData icon;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: TeacherUITranslations.get(labelKey, language),
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TeacherRadii.md),
        ),
      ),
    );
  }
}