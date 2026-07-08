// task_list_screen.dart
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/create_task_screen.dart';
import 'package:loringo_app/screens/teacher/widgets/hierarchy_list_cards.dart';
import 'package:loringo_app/screens/teacher/widgets/hierarchy_breadcrumb.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

class PersonalizedTaskListScreen extends StatefulWidget {
  final String groupId;
  final String contentId;
  final String unitId;
  final String lessonId;
  final String activityId;
  final String activityTitle;
  final Color  groupColor;
  final List<String> ancestorTrail;

  const PersonalizedTaskListScreen({
    super.key,
    required this.groupId,
    required this.contentId,
    required this.unitId,
    required this.lessonId,
    required this.activityId,
    required this.activityTitle,
    required this.groupColor,
    required this.ancestorTrail,
  });

  @override
  State<PersonalizedTaskListScreen> createState() =>
      _PersonalizedTaskListScreenState();
}

class _PersonalizedTaskListScreenState
    extends State<PersonalizedTaskListScreen> {
  final Database db = Database();

  // ─── Display title resolver ─────────────────────────────────────────────
  // Different task types store their "headline" text in different places:
  // most types write it to the top-level 'question' field, but 'reading'
  // tasks store their story title inside data.title (owned entirely by
  // reading_task.dart's editor). This picks the right source per type so
  // the list never shows a blank "Untitled" for reading tasks.
  String _displayTitle(Map<String, dynamic> data) {
    final type = data['type'] as String? ?? '';
    if (type == 'reading') {
      final inner = data['data'] as Map<String, dynamic>?;
      final title = inner?['title'] as String?;
      if (title != null && title.trim().isNotEmpty) return title;
      // Legacy fallback: some old reading tasks stored their title in the
      // top-level 'question' field before data.title existed.
      final legacy = data['question'] as String?;
      if (legacy != null && legacy.trim().isNotEmpty) return legacy;
      return 'Untitled Story';
    }
    final question = data['question'] as String?;
    return (question != null && question.trim().isNotEmpty)
        ? question
        : 'Untitled';
  }

  Future<void> _deleteTask(String taskId, String displayTitle) async {
    final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.md)),
            title: const Text('Delete Task'),
            content: const Text('Delete this task?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: AppColors.onPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.sm)),
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirm) return;
    try {
      await db.deletePersonalizedTask(
        widget.groupId, widget.contentId, widget.unitId,
        widget.lessonId, widget.activityId, taskId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Task deleted'),
          backgroundColor: AppColors.primary,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.danger,
        ));
      }
    }
  }

  void _editTask(String taskId, Map<String, dynamic> data) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePersonalizedTaskScreen(
          groupId:    widget.groupId,
          contentId:  widget.contentId,
          unitId:     widget.unitId,
          lessonId:   widget.lessonId,
          activityId: widget.activityId,
          groupColor: widget.groupColor,
          taskId:     taskId,
          existingData: {
            'question': data['question'],
            'order':    data['order'],
            'type':     data['type'],
            'data':     data['data'],
          },
        ),
      ),
    );
  }

  String _typeLabel(String type) {
    const map = {
      'image_select':         'Image Selection',
      'image_select_reverse': 'Image Select Reverse',
      'fill_blank':           'Fill the Blank',
      'arrange':              'Arrange Words',
      'complete_the_chat':    'Complete Chat',
      'word_match':           'Word Match',
      'match':                'Match',
      'reading':              'Reading',
    };
    return map[type] ?? type;
  }

  IconData _typeIcon(String type) {
    const map = {
      'image_select':         Icons.image,
      'image_select_reverse': Icons.image_search,
      'fill_blank':           Icons.edit_note,
      'arrange':              Icons.sort,
      'complete_the_chat':    Icons.chat,
      'word_match':           Icons.shuffle,
      'match':                Icons.compare_arrows,
      'reading':              Icons.menu_book,
    };
    return map[type] ?? Icons.help_outline;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.groupColor;
    final breadcrumb = [...widget.ancestorTrail, widget.activityTitle];

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: c,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.onPrimary),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.activityTitle,
                style: const TextStyle(
                    color: AppColors.onPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 17)),
            const Text('Tasks',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
      body: Column(
        children: [
          HierarchyBreadcrumb(items: breadcrumb, color: c),
          Expanded(
            child: StreamBuilder(
              stream: db.getPersonalizedTasksStream(
                widget.groupId, widget.contentId, widget.unitId,
                widget.lessonId, widget.activityId,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: c));
                }
                final tasks = snapshot.data?.docs ?? [];

                if (tasks.isEmpty) {
                  return HierarchyEmptyState(
                    icon:        Icons.help_outline,
                    title:       'No Tasks Yet',
                    subtitle:    'Tap + to create your first task',
                    color:       c,
                    actionLabel: 'Create First Task',
                    onAction: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CreatePersonalizedTaskScreen(
                          groupId:    widget.groupId,
                          contentId:  widget.contentId,
                          unitId:     widget.unitId,
                          lessonId:   widget.lessonId,
                          activityId: widget.activityId,
                          groupColor: c,
                        ),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: tasks.length,
                  itemBuilder: (context, i) {
                    final doc      = tasks[i];
                    final data     = doc.data() as Map<String, dynamic>;
                    final displayTitle = _displayTitle(data);
                    final type     = data['type']     ?? 'unknown';
                    final order    = data['order']    ?? 0;

                    return Container(
                      margin: const EdgeInsets.only(bottom: AppSpacing.md - 2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 3))
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm - 2),
                        leading: Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: c.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(AppRadii.md),
                          ),
                          child: Center(
                              child: Icon(_typeIcon(type), color: c, size: 22)),
                        ),
                        title: Text(
                          '$order. $displayTitle',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm, vertical: 2),
                              decoration: BoxDecoration(
                                color: c.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(AppRadii.sm),
                              ),
                              child: Text(_typeLabel(type),
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: c)),
                            ),
                          ),
                        ),
                        trailing: HierarchyPopupActions(
                          onEdit: () => _editTask(doc.id, {
                            'question': data['question'],
                            'order':    order,
                            'type':     type,
                            'data':     data['data'],
                          }),
                          onDelete: () => _deleteTask(doc.id, displayTitle),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CreatePersonalizedTaskScreen(
              groupId:    widget.groupId,
              contentId:  widget.contentId,
              unitId:     widget.unitId,
              lessonId:   widget.lessonId,
              activityId: widget.activityId,
              groupColor: c,
            ),
          ),
        ),
        backgroundColor: c,
        elevation: 3,
        icon: const Icon(Icons.add, color: AppColors.onPrimary),
        label: const Text('Add Task',
            style: TextStyle(
                color: AppColors.onPrimary, fontWeight: FontWeight.bold)),
      ),
    );
  }
}