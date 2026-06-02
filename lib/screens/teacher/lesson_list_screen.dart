import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/create_lesson_screen.dart';
import 'package:loringo_app/screens/teacher/activity_list_screen.dart';
import 'package:loringo_app/services/database/database.dart';

class PersonalizedLessonListScreen extends StatefulWidget {
  final String groupId;
  final String contentId;
  final String unitId;
  final String unitTitle;
  final Color groupColor;

  const PersonalizedLessonListScreen({
    super.key,
    required this.groupId,
    required this.contentId,
    required this.unitId,
    required this.unitTitle,
    required this.groupColor,
  });

  @override
  State<PersonalizedLessonListScreen> createState() =>
      _PersonalizedLessonListScreenState();
}

class _PersonalizedLessonListScreenState
    extends State<PersonalizedLessonListScreen> {
  final Database db = Database();

  Future<void> _deleteLesson(String lessonId, String title) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Lesson'),
        content: Text('Delete "$title"?\nThis will also delete all activities and tasks inside it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    ) ?? false;
    if (!confirm) return;
    try {
      await db.deletePersonalizedLesson(
        widget.groupId,
        widget.contentId,
        widget.unitId,
        lessonId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lesson deleted'), backgroundColor: Colors.green),
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

  void _editLesson(String lessonId, Map<String, dynamic> data) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePersonalizedLessonScreen(
          groupId: widget.groupId,
          contentId: widget.contentId,
          unitId: widget.unitId,
          groupColor: widget.groupColor,
          lessonId: lessonId,
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
        backgroundColor: widget.groupColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.unitTitle,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
            const Text('Lessons', style: TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
      body: StreamBuilder(
        stream: db.getPersonalizedLessonsStream(
          widget.groupId,
          widget.contentId,
          widget.unitId,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: widget.groupColor));
          }
          final lessons = snapshot.data?.docs ?? [];

          if (lessons.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.school_outlined, size: 80, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text('No Lessons Yet',
                      style: TextStyle(fontSize: 18, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text('Tap the + button to create your first lesson',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CreatePersonalizedLessonScreen(
                            groupId: widget.groupId,
                            contentId: widget.contentId,
                            unitId: widget.unitId,
                            groupColor: widget.groupColor,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Create First Lesson'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.groupColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: lessons.length,
            itemBuilder: (context, i) {
              final doc = lessons[i];
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
                      color: widget.groupColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text('$order',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: widget.groupColor)),
                    ),
                  ),
                  title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  subtitle: Text('Tap to view activities', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                  trailing: PopupMenuButton(
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        child: const Row(children: [Icon(Icons.edit, color: Colors.blue), SizedBox(width: 8), Text('Edit')]),
                        onTap: () => _editLesson(doc.id, data),
                      ),
                      PopupMenuItem(
                        child: const Row(children: [Icon(Icons.delete, color: Colors.red), SizedBox(width: 8), Text('Delete')]),
                        onTap: () => _deleteLesson(doc.id, title),
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PersonalizedActivityListScreen(
                          groupId: widget.groupId,
                          contentId: widget.contentId,
                          unitId: widget.unitId,
                          lessonId: doc.id,
                          lessonTitle: title,
                          groupColor: widget.groupColor,
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
              builder: (_) => CreatePersonalizedLessonScreen(
                groupId: widget.groupId,
                contentId: widget.contentId,
                unitId: widget.unitId,
                groupColor: widget.groupColor,
              ),
            ),
          );
        },
        backgroundColor: widget.groupColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Lesson', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}