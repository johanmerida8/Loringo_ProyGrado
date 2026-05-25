import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/create_task_screen.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.activityTitle,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const Text(
              'Tasks',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
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
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.help_outline, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    'No Tasks Yet',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create the first task to get started',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.push(
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
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Create First Task'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.groupColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          final tasks = snapshot.data!.docs;

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: tasks.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              indent: 64,
              color: Colors.grey[100],
            ),
            itemBuilder: (context, index) {
              final taskDoc = tasks[index];
              final taskData = taskDoc.data() as Map<String, dynamic>;
              final question = taskData['question'] ?? 'Untitled';
              final type = taskData['type'] ?? 'unknown';
              final order = taskData['order'] ?? 0;

              final String typeLabel = _getTaskTypeLabel(type);
              final IconData typeIcon = _getTaskTypeIcon(type);

              return ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: widget.groupColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    typeIcon,
                    color: widget.groupColor,
                    size: 20,
                  ),
                ),
                title: Text(
                  '$order. $question',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  typeLabel,
                  style: TextStyle(
                    color: widget.groupColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                trailing: PopupMenuButton(
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      child: const Row(
                        children: [
                          Icon(Icons.edit, color: Colors.blue),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                      onTap: () {
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
                              taskId: taskDoc.id,
                              existingData: {
                                'question': question,
                                'order': order,
                                'type': type,
                                'data': taskData['data'],
                              },
                            ),
                          ),
                        );
                      },
                    ),
                    PopupMenuItem(
                      child: const Row(
                        children: [
                          Icon(Icons.delete, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete'),
                        ],
                      ),
                      onTap: () => _deleteTask(taskDoc.id, question),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
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
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  String _getTaskTypeLabel(String type) {
    switch (type) {
      case 'image_select':
        return 'Image Selection';
      case 'fill_blank':
        return 'Fill the Blank';
      case 'arrange':
        return 'Arrange Words';
      case 'complete_the_chat':
        return 'Complete Chat';
      default:
        return type;
    }
  }

  IconData _getTaskTypeIcon(String type) {
    switch (type) {
      case 'image_select':
        return Icons.image;
      case 'fill_blank':
        return Icons.edit_note;
      case 'arrange':
        return Icons.sort;
      case 'complete_the_chat':
        return Icons.chat;
      default:
        return Icons.help;
    }
  }

  Future<void> _deleteTask(String taskId, String question) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Task'),
        content: Text('Are you sure you want to delete this task?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
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
            const SnackBar(
              content: Text('✅ Task deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting task: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}
