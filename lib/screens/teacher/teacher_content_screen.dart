import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/content_details_screen.dart';
import 'package:loringo_app/screens/teacher/create_content_screen.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_confirm_dialog.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

class TeacherContentScreen extends StatelessWidget {
  const TeacherContentScreen({super.key});

  static const Color _green = AppColors.primary;

  @override
  Widget build(BuildContext context) {
    final teacherId = FirebaseAuth.instance.currentUser?.uid;
    if (teacherId == null) {
      return const Scaffold(
        body: Center(child: Text('Not authenticated')),
      );
    }
    return _TeacherContentBody(teacherId: teacherId);
  }
}

class _TeacherContentBody extends StatelessWidget {
  const _TeacherContentBody({required this.teacherId});

  final String teacherId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: TeacherContentScreen._green,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'My Content',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: TeacherContentScreen._green,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Content'),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const CreatePersonalizedContentScreen(),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: Database().getTeacherContentStream(teacherId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                  color: TeacherContentScreen._green),
            );
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return _EmptyState(
              onCreateTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CreatePersonalizedContentScreen(),
                ),
              ),
            );
          }

          // Split by status
          final approved =
              docs.where((d) => (d['status'] ?? '') == 'approved').toList();
          final pending =
              docs.where((d) => (d['status'] ?? '') == 'pending').toList();
          final rejected =
              docs.where((d) => (d['status'] ?? '') == 'rejected').toList();

          return ListView(
            padding: const EdgeInsets.only(bottom: 100),
            children: [
              if (approved.isNotEmpty) ...[
                _SectionHeader(
                  label: 'Approved',
                  count: approved.length,
                  color: Colors.green,
                ),
                ...approved.map(
                  (doc) => _ContentRow(
                    doc: doc,
                    teacherId: teacherId,
                    onDelete: () => _delete(context, doc.id, doc['title']),
                  ),
                ),
              ],
              if (pending.isNotEmpty) ...[
                _SectionHeader(
                  label: 'Pending Review',
                  count: pending.length,
                  color: Colors.orange,
                ),
                ...pending.map(
                  (doc) => _ContentRow(
                    doc: doc,
                    teacherId: teacherId,
                    onDelete: () => _delete(context, doc.id, doc['title']),
                  ),
                ),
              ],
              if (rejected.isNotEmpty) ...[
                _SectionHeader(
                  label: 'Rejected',
                  count: rejected.length,
                  color: Colors.red,
                ),
                ...rejected.map(
                  (doc) => _ContentRow(
                    doc: doc,
                    teacherId: teacherId,
                    onDelete: () => _delete(context, doc.id, doc['title']),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _delete(
      BuildContext context, String contentId, String title) async {
    final confirmed = await showTeacherConfirmDialog(
      context: context,
      title: 'Delete Content',
      message: 'Delete "$title"? This cannot be undone.',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
    );
    if (!confirmed) return;
    try {
      await Database().deletePersonalizedContent(contentId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Content deleted'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }
}

// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.grey[700],
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ContentRow extends StatelessWidget {
  const _ContentRow({
    required this.doc,
    required this.teacherId,
    required this.onDelete,
  });

  final QueryDocumentSnapshot doc;
  final String teacherId;
  final VoidCallback onDelete;

  static const Color _green = TeacherContentScreen._green;

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final title = data['title'] as String? ?? 'Untitled';
    final ageGroup = data['ageGroup'] as String? ?? '';
    final status = data['status'] as String? ?? 'pending';
    final assignedTo = (data['assignedTo'] as List<dynamic>?)?.cast<String>() ?? [];
    final isApproved = status == 'approved';
    final initial = title.isNotEmpty ? title[0].toUpperCase() : '#';

    return Column(
      children: [
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          onTap: isApproved
              ? () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PersonalizedContentDetailsScreen(
                        groupId: '', // not group-bound at this level
                        contentId: doc.id,
                        contentTitle: title,
                        groupColor: _green,
                      ),
                    ),
                  )
              : status == 'rejected'
                  ? () => _editContent(context, doc, data)
                  : null,
          leading: CircleAvatar(
            radius: 22,
            backgroundColor: isApproved
                ? _green.withOpacity(0.15)
                : Colors.grey[100],
            child: Text(
              initial,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isApproved ? _green : Colors.grey[400],
              ),
            ),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: isApproved ? Colors.black87 : Colors.grey[500],
            ),
          ),
          subtitle: Text(
            ageGroup,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isApproved)
                _AssignBadge(
                  count: assignedTo.length,
                  onTap: () => _showAssignSheet(context, doc.id, assignedTo),
                ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.grey),
                onSelected: (value) {
                  if (value == 'edit') _editContent(context, doc, data);
                  if (value == 'delete') onDelete();
                  if (value == 'assign') {
                    _showAssignSheet(context, doc.id, assignedTo);
                  }
                },
                itemBuilder: (_) => [
                  if (isApproved)
                    const PopupMenuItem(
                      value: 'assign',
                      child: Row(children: [
                        Icon(Icons.group_add, size: 18),
                        SizedBox(width: 8),
                        Text('Assign to Groups'),
                      ]),
                    ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(children: [
                      Icon(Icons.edit, size: 18),
                      SizedBox(width: 8),
                      Text('Edit'),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete',
                          style: TextStyle(color: Colors.red)),
                    ]),
                  ),
                ],
              ),
            ],
          ),
        ),
        Divider(height: 1, indent: 64, color: Colors.grey[100]),
      ],
    );
  }

  void _editContent(BuildContext context, QueryDocumentSnapshot doc,
      Map<String, dynamic> data) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePersonalizedContentScreen(
          contentId: doc.id,
          existingData: data,
          groupColor: _green,
        ),
      ),
    );
  }

  void _showAssignSheet(
      BuildContext context, String contentId, List<String> currentAssigned) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AssignGroupSheet(
        contentId: contentId,
        currentAssigned: currentAssigned,
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _AssignBadge extends StatelessWidget {
  const _AssignBadge({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: count > 0
              ? const Color(0xFF4CAF50).withOpacity(0.1)
              : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: count > 0
                ? const Color(0xFF4CAF50).withOpacity(0.3)
                : Colors.grey[300]!,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.group,
              size: 14,
              color: count > 0
                  ? const Color(0xFF4CAF50)
                  : Colors.grey[400],
            ),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: count > 0
                    ? const Color(0xFF4CAF50)
                    : Colors.grey[400],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _AssignGroupSheet extends StatefulWidget {
  const _AssignGroupSheet({
    required this.contentId,
    required this.currentAssigned,
  });

  final String contentId;
  final List<String> currentAssigned;

  @override
  State<_AssignGroupSheet> createState() => _AssignGroupSheetState();
}

class _AssignGroupSheetState extends State<_AssignGroupSheet> {
  late Set<String> _selected;
  List<Map<String, dynamic>> _groups = [];
  bool _loading = true;
  bool _saving = false;
  final _db = Database();

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.currentAssigned);
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    final teacherId = FirebaseAuth.instance.currentUser?.uid;
    if (teacherId == null) return;
    final snap = await FirebaseFirestore.instance
        .collection('teacherGroups')
        .where('teacherId', isEqualTo: teacherId)
        .get();
    setState(() {
      _groups = snap.docs
          .map((d) => {'id': d.id, ...d.data() as Map<String, dynamic>})
          .toList();
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      // Determine added and removed groups
      final added = _selected.difference(Set<String>.from(widget.currentAssigned));
      final removed = Set<String>.from(widget.currentAssigned).difference(_selected);
      for (final gId in added) {
        await _db.assignContentToGroup(
            contentId: widget.contentId, groupId: gId);
      }
      for (final gId in removed) {
        await _db.removeContentFromGroup(
            contentId: widget.contentId, groupId: gId);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Assign to Groups',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Select which groups can access this content',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(
                    color: TeacherContentScreen._green),
              ),
            )
          else if (_groups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No groups found. Create a group first.',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            )
          else
            ...(_groups.map((g) {
              final id = g['id'] as String;
              final name = g['name'] as String? ?? 'Group';
              // color is stored as hex string e.g. "#4CAF50"
              final colorRaw = g['color'];
              Color color;
              if (colorRaw is int) {
                color = Color(colorRaw);
              } else if (colorRaw is String) {
                final hex = colorRaw.replaceFirst('#', '');
                color = Color(int.parse('FF$hex', radix: 16));
              } else {
                color = const Color(0xFF4CAF50);
              }
              return CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(g['groupCode'] as String? ?? '',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.grey)),
                secondary: CircleAvatar(
                  radius: 18,
                  backgroundColor: color.withOpacity(0.15),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'G',
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.bold),
                  ),
                ),
                activeColor: TeacherContentScreen._green,
                value: _selected.contains(id),
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _selected.add(id);
                    } else {
                      _selected.remove(id);
                    }
                  });
                },
              );
            })),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: TeacherContentScreen._green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreateTap});
  final VoidCallback onCreateTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open_rounded, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            const Text(
              'No Content Yet',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Create content here. Once approved by an admin, you can assign it to your groups.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: TeacherContentScreen._green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: onCreateTap,
              icon: const Icon(Icons.add),
              label: const Text('Create First Content'),
            ),
          ],
        ),
      ),
    );
  }
}
