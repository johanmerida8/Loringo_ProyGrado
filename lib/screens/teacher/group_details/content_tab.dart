// content_tab.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/create_content_screen.dart';
import 'package:loringo_app/screens/teacher/teacher_unit_editor_screen.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_confirm_dialog.dart';
import 'package:loringo_app/services/database/database.dart';

class ContentTab extends StatelessWidget {
  ContentTab({
    super.key,
    required this.groupId,
    required this.groupColor,
  });

  final String groupId;
  final Color groupColor;
  final Database _db = Database();

  @override
  Widget build(BuildContext context) {
    final teacherId = FirebaseAuth.instance.currentUser?.uid;
    if (teacherId == null) {
      return const Center(child: Text('Error: Not authenticated'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _db.getTeacherContentStream(teacherId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final contentDocs = snapshot.data?.docs ?? [];

        if (contentDocs.isEmpty) {
          return const _NoContentEmptyState();
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: contentDocs.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            indent: 64,
            color: Colors.grey[100],
          ),
          itemBuilder: (context, index) {
            final doc = contentDocs[index];
            return _ChannelTile(
              contentDoc: doc,
              groupId: groupId,
              groupColor: groupColor,
              onDelete: (id, title) => _confirmAndDelete(
                context: context,
                contentId: id,
                title: title,
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmAndDelete({
    required BuildContext context,
    required String contentId,
    required String title,
  }) async {
    final confirmed = await showTeacherConfirmDialog(
      context: context,
      title: 'Delete Content',
      message:
          'Are you sure you want to delete "$title"? This action cannot be undone.',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
    );
    if (!confirmed) return;

    try {
      await _db.deletePersonalizedContent(contentId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Content deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting content: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class _NoContentEmptyState extends StatelessWidget {
  const _NoContentEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.edit_note, size: 100, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text(
            'No Content Yet',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            'Create custom content for your class',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.contentDoc,
    required this.groupId,
    required this.groupColor,
    required this.onDelete,
  });

  final QueryDocumentSnapshot contentDoc;
  final String groupId;
  final Color groupColor;
  final void Function(String id, String title) onDelete;

  @override
  Widget build(BuildContext context) {
    final data = contentDoc.data() as Map<String, dynamic>;
    final title = data['title'] ?? 'Untitled';
    final ageGroup = data['ageGroup'] ?? '5-6 years';
    final initial = title.isNotEmpty ? title[0].toUpperCase() : '#';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TeacherUnitEditorScreen(
            groupId: groupId,
            contentId: contentDoc.id,
            contentTitle: title,
            groupColor: groupColor,
          ),
        ),
      ),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: groupColor.withOpacity(0.15),
        child: Text(
          initial,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: groupColor,
          ),
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: Colors.black87,
        ),
      ),
      subtitle: Text(
        ageGroup,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      trailing: PopupMenuButton<void>(
        itemBuilder: (context) => [
          PopupMenuItem(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CreatePersonalizedContentScreen(
                  groupColor: groupColor,
                  contentId: contentDoc.id,
                  existingData: data,
                ),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.edit, color: Colors.blue),
                SizedBox(width: 8),
                Text('Edit'),
              ],
            ),
          ),
          PopupMenuItem(
            onTap: () => onDelete(contentDoc.id, title),
            child: const Row(
              children: [
                Icon(Icons.delete, color: Colors.red),
                SizedBox(width: 8),
                Text('Delete'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}