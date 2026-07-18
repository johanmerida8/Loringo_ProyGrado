// teacher_activity_editor_screen.dart
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/create_activity_screen.dart';
import 'package:loringo_app/screens/teacher/teacher_task_editor_screen.dart';
import 'package:loringo_app/screens/teacher/widgets/hierarchy_list_cards.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_screen_header.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

class TeacherActivityEditorScreen extends StatefulWidget {
  final String groupId;
  final String contentId;
  final String unitId;
  final String lessonId;
  final String lessonTitle;
  final Color  groupColor;
  final List<String> ancestorTrail;

  const TeacherActivityEditorScreen({
    super.key,
    required this.groupId,
    required this.contentId,
    required this.unitId,
    required this.lessonId,
    required this.lessonTitle,
    required this.groupColor,
    required this.ancestorTrail,
  });

  @override
  State<TeacherActivityEditorScreen> createState() =>
      _TeacherActivityEditorScreenState();
}

class _TeacherActivityEditorScreenState
    extends State<TeacherActivityEditorScreen> {
  final Database db = Database();

  Future<void> _deleteActivity(String activityId, String title) async {
    final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.md)),
            title: const Text('Delete Activity'),
            content: Text(
                'Delete "$title"?\nThis will also delete all tasks inside it.'),
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
      await db.deletePersonalizedActivity(widget.groupId, widget.contentId,
          widget.unitId, widget.lessonId, activityId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Activity deleted'),
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

  void _editActivity(String activityId, Map<String, dynamic> data) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePersonalizedActivityScreen(
          groupId:      widget.groupId,
          contentId:    widget.contentId,
          unitId:       widget.unitId,
          lessonId:     widget.lessonId,
          groupColor:   widget.groupColor,
          activityId:   activityId,
          existingData: data,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.groupColor;

    return Scaffold(
      // NOTE: no Scaffold.appBar — replaced with TeacherScreenHeader.
      backgroundColor: AppColors.scaffoldBackground,
      body: Column(
        children: [
          TeacherScreenHeader(
            title: widget.lessonTitle,
            subtitle: 'Activities',
            color: c,
          ),
          Expanded(
            child: StreamBuilder(
              stream: db.getPersonalizedActivitiesStream(
                widget.groupId, widget.contentId,
                widget.unitId,  widget.lessonId,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: c));
                }
                final activities = snapshot.data?.docs ?? [];

                if (activities.isEmpty) {
                  return HierarchyEmptyState(
                    icon:        Icons.task_outlined,
                    title:       'No Activities Yet',
                    subtitle:    'Tap + to create your first activity',
                    color:       c,
                    actionLabel: 'Create First Activity',
                    onAction: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CreatePersonalizedActivityScreen(
                          groupId:   widget.groupId,
                          contentId: widget.contentId,
                          unitId:    widget.unitId,
                          lessonId:  widget.lessonId,
                          groupColor: c,
                        ),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  // Bottom padding leaves room so the FAB doesn't cover
                  // the last card in the list.
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md, AppSpacing.md, AppSpacing.md, 100),
                  itemCount: activities.length,
                  itemBuilder: (context, i) {
                    final doc        = activities[i];
                    final data       = doc.data() as Map<String, dynamic>;
                    final title      = data['title']     ?? 'Untitled';
                    final order      = data['order']      ?? 0;
                    final xp         = data['xpBase']     ?? 0;
                    final difficulty = data['difficulty'] ?? 'easy';

                    final diffColor = AppColors.difficulty(difficulty);

                    return HierarchyListCard(
                      order: order,
                      title: title,
                      color: c,
                      badge: Row(children: [
                        Icon(Icons.star_rounded, size: 14, color: Colors.amber[700]),
                        const SizedBox(width: 3),
                        Text('$xp XP',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500)),
                        const SizedBox(width: AppSpacing.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm - 2, vertical: 2),
                          decoration: BoxDecoration(
                            color: diffColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                          ),
                          child: Text(difficulty,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: diffColor)),
                        ),
                      ]),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TeacherTaskEditorScreen(
                            groupId:       widget.groupId,
                            contentId:     widget.contentId,
                            unitId:        widget.unitId,
                            lessonId:      widget.lessonId,
                            activityId:    doc.id,
                            activityTitle: title,
                            groupColor:    c,
                            ancestorTrail: [...widget.ancestorTrail, widget.lessonTitle],
                          ),
                        ),
                      ),
                      onEdit:   () => _editActivity(doc.id, data),
                      onDelete: () => _deleteActivity(doc.id, title),
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
            builder: (_) => CreatePersonalizedActivityScreen(
              groupId:   widget.groupId,
              contentId: widget.contentId,
              unitId:    widget.unitId,
              lessonId:  widget.lessonId,
              groupColor: c,
            ),
          ),
        ),
        backgroundColor: c,
        elevation: 3,
        icon: const Icon(Icons.add, color: AppColors.onPrimary),
        label: const Text('Add Activity',
            style: TextStyle(
                color: AppColors.onPrimary, fontWeight: FontWeight.bold)),
      ),
    );
  }
}