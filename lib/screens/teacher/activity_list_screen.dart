import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/create_activity_screen.dart';
import 'package:loringo_app/screens/teacher/task_list_screen.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

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
              widget.lessonTitle,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const Text(
              'Activities',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
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
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.task_outlined, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    'No Activities Yet',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create the first activity to get started',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.push(
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
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Create First Activity'),
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

          final activities = snapshot.data!.docs;

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: activities.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              indent: 64,
              color: Colors.grey[100],
            ),
            itemBuilder: (context, index) {
              final activityDoc = activities[index];
              final activityData = activityDoc.data() as Map<String, dynamic>;
              final title = activityData['title'] ?? 'Untitled';
              final order = activityData['order'] ?? 0;

              return ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                leading: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: widget.groupColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    order.toString(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: widget.groupColor,
                      fontSize: 15,
                    ),
                  ),
                ),
                title: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
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
                        activityId: activityDoc.id,
                        activityTitle: title,
                        groupColor: widget.groupColor,
                      ),
                    ),
                  );
                },
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
                            builder: (_) => CreatePersonalizedActivityScreen(
                              groupId: widget.groupId,
                              contentId: widget.contentId,
                              unitId: widget.unitId,
                              lessonId: widget.lessonId,
                              groupColor: widget.groupColor,
                              activityId: activityDoc.id,
                              existingData: activityData,
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
                      onTap: () => _deleteActivity(activityDoc.id, title),
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
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Future<void> _deleteActivity(String activityId, String title) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Activity'),
        content: Text('Are you sure you want to delete "$title"?'),
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
        await db.deletePersonalizedActivity(
          widget.groupId,
          widget.contentId,
          widget.unitId,
          widget.lessonId,
          activityId,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Activity deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting activity: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}
