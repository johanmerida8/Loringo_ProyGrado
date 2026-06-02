// content_details_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/create_unit_screen.dart';
import 'package:loringo_app/screens/teacher/lesson_list_screen.dart';
import 'package:loringo_app/services/database/database.dart';

class PersonalizedContentDetailsScreen extends StatefulWidget {
  final String groupId;
  final String contentId;
  final String contentTitle;
  final Color groupColor;

  const PersonalizedContentDetailsScreen({
    super.key,
    required this.groupId,
    required this.contentId,
    required this.contentTitle,
    required this.groupColor,
  });

  @override
  State<PersonalizedContentDetailsScreen> createState() =>
      _PersonalizedContentDetailsScreenState();
}

class _PersonalizedContentDetailsScreenState
    extends State<PersonalizedContentDetailsScreen> {
  final Database _db = Database();
  Color get _c => widget.groupColor;

  Future<void> _deleteUnit(String id, String title) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Unit'),
        content: Text('Delete "$title"?\nThis will also delete all lessons, activities and tasks inside it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    ) ?? false;
    if (!confirm) return;
    try {
      await _db.deletePersonalizedUnit(widget.groupId, widget.contentId, id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unit deleted'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _editUnit(String id, Map<String, dynamic> data) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePersonalizedUnitScreen(
          groupId: widget.groupId,
          contentId: widget.contentId,
          groupColor: _c,
          unitId: id,
          existingData: data,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: _c,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.contentTitle,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
            const Text('Units', style: TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _db.getPersonalizedUnitsStream(widget.groupId, widget.contentId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: _c));
          }
          final units = snap.data?.docs ?? [];

          if (units.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.layers_outlined, size: 80, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text('No Units Yet',
                      style: TextStyle(fontSize: 18, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text('Tap the + button to create your first unit',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: units.length,
            itemBuilder: (context, i) {
              final doc = units[i];
              final data = doc.data() as Map<String, dynamic>;
              final title = data['title'] ?? 'Untitled';
              final order = data['order'] ?? 0;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _c.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text('$order',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: _c)),
                    ),
                  ),
                  title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  subtitle: Text('Tap to view lessons', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                  trailing: PopupMenuButton(
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        child: const Row(children: [Icon(Icons.edit, color: Colors.blue), SizedBox(width: 8), Text('Edit')]),
                        onTap: () => _editUnit(doc.id, data),
                      ),
                      PopupMenuItem(
                        child: const Row(children: [Icon(Icons.delete, color: Colors.red), SizedBox(width: 8), Text('Delete')]),
                        onTap: () => _deleteUnit(doc.id, title),
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PersonalizedLessonListScreen(
                          groupId: widget.groupId,
                          contentId: widget.contentId,
                          unitId: doc.id,
                          unitTitle: title,
                          groupColor: _c,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CreatePersonalizedUnitScreen(
                groupId: widget.groupId,
                contentId: widget.contentId,
                groupColor: _c,
              ),
            ),
          );
        },
        backgroundColor: _c,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Unit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}