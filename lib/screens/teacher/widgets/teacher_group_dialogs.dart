import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/teacher_theme.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_confirm_dialog.dart';

void showCreateGroupDialog({
  required BuildContext context,
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
            groupId == null ? 'Create Group' : 'Edit Group',
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RoundedTextField(
            controller: nameController,
            labelText: 'Group Name',
            icon: Icons.group,
          ),
          const SizedBox(height: TeacherSpacing.md),
          _RoundedTextField(
            controller: descriptionController,
            labelText: 'Description',
            icon: Icons.description,
            maxLines: 3,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => _saveGroup(
            dialogContext: dialogContext,
            groupId: groupId,
            name: nameController.text.trim(),
            description: descriptionController.text.trim(),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: TeacherColors.primary,
          ),
          child: Text(
            groupId == null ? 'Create' : 'Save',
            style: const TextStyle(color: TeacherColors.onPrimary),
          ),
        ),
      ],
    ),
  );
}

Future<void> _saveGroup({
  required BuildContext dialogContext,
  required String? groupId,
  required String name,
  required String description,
}) async {
  if (name.isEmpty) {
    ScaffoldMessenger.of(dialogContext).showSnackBar(
      SnackBar(
        content: const Text('Group name is required'),
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
        groupId == null ? 'Group created successfully' : 'Group updated successfully',
      ),
      backgroundColor: TeacherColors.success,
    ),
  );
}

void showManageStudentsDialog({
  required BuildContext context,
  required String groupId,
  required Map<String, dynamic> groupData,
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
              'Manage Students - ${groupData['name']}',
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
            const Text(
              'Add students to this group with their parent email. They will receive a notification and can join the group from their app.',
              style: TextStyle(color: TeacherColors.muted),
            ),
            const SizedBox(height: TeacherSpacing.md),
            _StudentList(groupId: groupId),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(dialogContext);
            showAddStudentDialog(
              context: context,
              groupId: groupId,
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: TeacherColors.primary,
          ),
          child: const Text(
            'Add Student',
            style: TextStyle(color: TeacherColors.onPrimary),
          ),
        ),
      ],
    ),
  );
}

void showAddStudentDialog({
  required BuildContext context,
  required String groupId,
}) {
  final emailController = TextEditingController();

  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.person_add, color: TeacherColors.primary),
          const SizedBox(width: TeacherSpacing.sm),
          const Text('Add Student'),
        ],
      ),
      content: _RoundedTextField(
        controller: emailController,
        labelText: 'Student Email',
        icon: Icons.email,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => _addStudentByEmail(
            dialogContext: dialogContext,
            groupId: groupId,
            email: emailController.text.trim(),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: TeacherColors.primary,
          ),
          child: const Text(
            'Add',
            style: TextStyle(color: TeacherColors.onPrimary),
          ),
        ),
      ],
    ),
  );
}

Future<void> _addStudentByEmail({
  required BuildContext dialogContext,
  required String groupId,
  required String email,
}) async {
  if (email.isEmpty) {
    ScaffoldMessenger.of(dialogContext).showSnackBar(
      SnackBar(
        content: const Text('Email is required'),
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
        content: const Text('No student found'),
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
      content: const Text('Student added successfully'),
      backgroundColor: TeacherColors.success,
    ),
  );
}

Future<void> confirmAndDeleteGroup({
  required BuildContext context,
  required String groupId,
}) async {
  final confirmed = await showTeacherConfirmDialog(
    context: context,
    title: 'Delete Group',
    message: 'Are you sure you want to delete this group? This action cannot be undone.',
    confirmLabel: 'Delete',
    cancelLabel: 'Cancel',
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
  const _StudentList({required this.groupId});

  final String groupId;

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
          return const Text(
            'No students added yet',
            style: TextStyle(color: TeacherColors.muted),
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
    required this.labelText,
    required this.icon,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String labelText;
  final IconData icon;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: labelText,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TeacherRadii.md),
        ),
      ),
    );
  }
}