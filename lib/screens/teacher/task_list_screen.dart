import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/create_task_screen.dart';
import 'package:loringo_app/services/database/database.dart';

class PersonalizedTaskListScreen extends StatefulWidget {
  final String groupId;
  final String contentId;
  final String unitId;
  final String lessonId;
  final String activityId;
  final String activityTitle;
  final Color groupColor;

  const PersonalizedTaskListScreen({
    super.key,
    required this.groupId,
    required this.contentId,
    required this.unitId,
    required this.lessonId,
    required this.activityId,
    required this.activityTitle,
    required this.groupColor,
  });

  @override
  State<PersonalizedTaskListScreen> createState() =>
      _PersonalizedTaskListScreenState();
}

class _PersonalizedTaskListScreenState
    extends State<PersonalizedTaskListScreen> {
  final Database db = Database();

  Future<void> _deleteTask(String taskId, String question) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Task'),
        content: Text('Delete this task?'),
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
      await db.deletePersonalizedTask(
        widget.groupId,
        widget.contentId,
        widget.unitId,
        widget.lessonId,
        widget.activityId,
        taskId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task deleted'), backgroundColor: Colors.green),
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

  void _editTask(String taskId, Map<String, dynamic> data) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePersonalizedTaskScreen(
          groupId: widget.groupId,
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: widget.lessonId,
          activityId: widget.activityId,
          groupColor: widget.groupColor,
          taskId: taskId,
          existingData: {
            'question': data['question'],
            'order': data['order'],
            'type': data['type'],
            'data': data['data'],
          },
        ),
      ),
    );
  }

  String _getTaskTypeLabel(String type) {
    switch (type) {
      case 'image_select': return 'Image Selection';
      case 'fill_blank': return 'Fill the Blank';
      case 'arrange': return 'Arrange Words';
      case 'complete_the_chat': return 'Complete Chat';
      case 'word_match': return 'Word Match';
      case 'reading': return 'Reading';
      default: return type;
    }
  }

  IconData _getTaskTypeIcon(String type) {
    switch (type) {
      case 'image_select': return Icons.image;
      case 'fill_blank': return Icons.edit_note;
      case 'arrange': return Icons.sort;
      case 'complete_the_chat': return Icons.chat;
      case 'word_match': return Icons.shuffle;
      case 'reading': return Icons.menu_book;
      default: return Icons.help;
    }
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
            Text(widget.activityTitle,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
            const Text('Tasks', style: TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
      body: StreamBuilder(
        stream: db.getPersonalizedTasksStream(
          widget.groupId,
          widget.contentId,
          widget.unitId,
          widget.lessonId,
          widget.activityId,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: widget.groupColor));
          }
          final tasks = snapshot.data?.docs ?? [];

          if (tasks.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.help_outline, size: 80, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text('No Tasks Yet',
                      style: TextStyle(fontSize: 18, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text('Tap the + button to create your first task',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CreatePersonalizedTaskScreen(
                            groupId: widget.groupId,
                            contentId: widget.contentId,
                            unitId: widget.unitId,
                            lessonId: widget.lessonId,
                            activityId: widget.activityId,
                            groupColor: widget.groupColor,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Create First Task'),
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
            itemCount: tasks.length,
            itemBuilder: (context, i) {
              final doc = tasks[i];
              final data = doc.data() as Map<String, dynamic>;
              final question = data['question'] ?? 'Untitled';
              final type = data['type'] ?? 'unknown';
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
                      child: Icon(_getTaskTypeIcon(type),
                          color: widget.groupColor, size: 24),
                    ),
                  ),
                  title: Text('$order. $question',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_getTaskTypeLabel(type),
                      style: TextStyle(fontSize: 12, color: widget.groupColor, fontWeight: FontWeight.w600)),
                  trailing: PopupMenuButton(
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        child: const Row(children: [Icon(Icons.edit, color: Colors.blue), SizedBox(width: 8), Text('Edit')]),
                        onTap: () => _editTask(doc.id, {
                          'question': question,
                          'order': order,
                          'type': type,
                          'data': data['data'],
                        }),
                      ),
                      PopupMenuItem(
                        child: const Row(children: [Icon(Icons.delete, color: Colors.red), SizedBox(width: 8), Text('Delete')]),
                        onTap: () => _deleteTask(doc.id, question),
                      ),
                    ],
                  ),
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
              builder: (_) => CreatePersonalizedTaskScreen(
                groupId: widget.groupId,
                contentId: widget.contentId,
                unitId: widget.unitId,
                lessonId: widget.lessonId,
                activityId: widget.activityId,
                groupColor: widget.groupColor,
              ),
            ),
          );
        },
        backgroundColor: widget.groupColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Task', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}