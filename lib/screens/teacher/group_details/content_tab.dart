import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/create_content_screen.dart';
import 'package:loringo_app/screens/teacher/content_details_screen.dart';
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
      stream: _db.getPendingContentByTeacherStream(teacherId),
      builder: (context, pendingSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: _db.getPersonalizedContentStream(groupId),
          builder: (context, approvedSnapshot) {
            return StreamBuilder<QuerySnapshot>(
              stream: _db.getRejectedContentStream(teacherId),
              builder: (context, rejectedSnapshot) {
                final pending = pendingSnapshot.data?.docs ?? [];
                final approved = approvedSnapshot.data?.docs ?? [];
                final rejected = rejectedSnapshot.data?.docs ?? [];

                if (pending.isEmpty && approved.isEmpty && rejected.isEmpty) {
                  return const _NoContentEmptyState();
                }

                final allDocs = [...pending, ...approved, ...rejected];

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: allDocs.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    indent: 64,
                    color: Colors.grey[100],
                  ),
                  itemBuilder: (context, index) {
                    final doc = allDocs[index];
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
    final status = data['status'] ?? 'pending';
    final isPending = status == 'pending';
    final isMuted = isPending || status == 'rejected';
    final initial = title.isNotEmpty ? title[0].toUpperCase() : '#';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      onTap: isPending
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PersonalizedContentDetailsScreen(
                    groupId: groupId,
                    contentId: contentDoc.id,
                    contentTitle: title,
                    groupColor: groupColor,
                  ),
                ),
              ),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor:
            isMuted ? Colors.grey[100] : groupColor.withOpacity(0.15),
        child: Text(
          initial,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: isMuted ? Colors.grey[400] : groupColor,
          ),
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: isMuted ? Colors.grey[500] : Colors.black87,
        ),
      ),
      subtitle: Text(
        ageGroup,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusBadge(status: status),
          if (!isPending)
            PopupMenuButton<void>(
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
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    switch (status) {
      case 'approved':
        color = Colors.green;
        label = 'Approved';
        break;
      case 'rejected':
        color = Colors.red;
        label = 'Rejected';
        break;
      default:
        color = Colors.orange;
        label = 'Pending';
    }
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
