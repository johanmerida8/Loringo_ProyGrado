import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/create_activity_screen.dart';
import 'package:loringo_app/screens/teacher/task_list_screen.dart';
import 'package:loringo_app/services/database/database.dart';

class PersonalizedActivityListScreen extends StatefulWidget {
  final String groupId;
  final String contentId;
  final String unitId;
  final String lessonId;
  final String lessonTitle;
  final Color groupColor;

  const PersonalizedActivityListScreen({
    super.key,
    required this.groupId,
    required this.contentId,
    required this.unitId,
    required this.lessonId,
    required this.lessonTitle,
    required this.groupColor,
  });

  @override
  State<PersonalizedActivityListScreen> createState() =>
      _PersonalizedActivityListScreenState();
}

class _PersonalizedActivityListScreenState
    extends State<PersonalizedActivityListScreen> {
  final Database db = Database();

  Future<void> _deleteActivity(String activityId, String title) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Activity'),
        content: Text('Delete "$title"?\nThis will also delete all tasks inside it.'),
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
      await db.deletePersonalizedActivity(
        widget.groupId,
        widget.contentId,
        widget.unitId,
        widget.lessonId,
        activityId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Activity deleted'), backgroundColor: Colors.green),
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

  void _editActivity(String activityId, Map<String, dynamic> data) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePersonalizedActivityScreen(
          groupId: widget.groupId,
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: widget.lessonId,
          groupColor: widget.groupColor,
          activityId: activityId,
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
            Text(widget.lessonTitle,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
            const Text('Activities', style: TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
      body: StreamBuilder(
        stream: db.getPersonalizedActivitiesStream(
          widget.groupId,
          widget.contentId,
          widget.unitId,
          widget.lessonId,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: widget.groupColor));
          }
          final activities = snapshot.data?.docs ?? [];

          if (activities.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.task_outlined, size: 80, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text('No Activities Yet',
                      style: TextStyle(fontSize: 18, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text('Tap the + button to create your first activity',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CreatePersonalizedActivityScreen(
                            groupId: widget.groupId,
                            contentId: widget.contentId,
                            unitId: widget.unitId,
                            lessonId: widget.lessonId,
                            groupColor: widget.groupColor,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Create First Activity'),
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
            itemCount: activities.length,
            itemBuilder: (context, i) {
              final doc = activities[i];
              final data = doc.data() as Map<String, dynamic>;
              final title = data['title'] ?? 'Untitled';
              final order = data['order'] ?? 0;
              final xp = data['xpBase'] ?? 0;
              final difficulty = data['difficulty'] ?? 'easy';

              Color difficultyColor = Colors.green;
              if (difficulty == 'medium') difficultyColor = Colors.orange;
              if (difficulty == 'hard') difficultyColor = Colors.red;

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
                  subtitle: Row(
                    children: [
                      Icon(Icons.star, size: 14, color: Colors.amber),
                      const SizedBox(width: 4),
                      Text('$xp XP', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: difficultyColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(difficulty,
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: difficultyColor)),
                      ),
                    ],
                  ),
                  trailing: PopupMenuButton(
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        child: const Row(children: [Icon(Icons.edit, color: Colors.blue), SizedBox(width: 8), Text('Edit')]),
                        onTap: () => _editActivity(doc.id, data),
                      ),
                      PopupMenuItem(
                        child: const Row(children: [Icon(Icons.delete, color: Colors.red), SizedBox(width: 8), Text('Delete')]),
                        onTap: () => _deleteActivity(doc.id, title),
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PersonalizedTaskListScreen(
                          groupId: widget.groupId,
                          contentId: widget.contentId,
                          unitId: widget.unitId,
                          lessonId: widget.lessonId,
                          activityId: doc.id,
                          activityTitle: title,
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
              builder: (_) => CreatePersonalizedActivityScreen(
                groupId: widget.groupId,
                contentId: widget.contentId,
                unitId: widget.unitId,
                lessonId: widget.lessonId,
                groupColor: widget.groupColor,
              ),
            ),
          );
        },
        backgroundColor: widget.groupColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Activity', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}