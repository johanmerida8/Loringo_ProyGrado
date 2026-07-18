// teacher_lesson_editor_screen.dart
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/teacher_activity_editor_screen.dart';
import 'package:loringo_app/screens/teacher/create_lesson_screen.dart';
import 'package:loringo_app/screens/teacher/widgets/hierarchy_list_cards.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_screen_header.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

class TeacherLessonEditorScreen extends StatefulWidget {
  final String groupId;
  final String contentId;
  final String unitId;
  final String unitTitle;
  final Color  groupColor;
  final List<String> ancestorTrail;

  const TeacherLessonEditorScreen({
    super.key,
    required this.groupId,
    required this.contentId,
    required this.unitId,
    required this.unitTitle,
    required this.groupColor,
    required this.ancestorTrail,
  });

  @override
  State<TeacherLessonEditorScreen> createState() =>
      _TeacherLessonEditorScreenState();
}

class _TeacherLessonEditorScreenState
    extends State<TeacherLessonEditorScreen> {
  final Database db = Database();

  Future<void> _deleteLesson(String lessonId, String title) async {
    final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.md)),
            title: const Text('Delete Lesson'),
            content: Text(
                'Delete "$title"?\nThis will also delete all activities and tasks inside it.'),
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
      await db.deletePersonalizedLesson(
          widget.groupId, widget.contentId, widget.unitId, lessonId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Lesson deleted'),
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

  void _editLesson(String lessonId, Map<String, dynamic> data) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePersonalizedLessonScreen(
          groupId:      widget.groupId,
          contentId:    widget.contentId,
          unitId:       widget.unitId,
          groupColor:   widget.groupColor,
          lessonId:     lessonId,
          existingData: data,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.groupColor;

    // NOTE: ancestorTrail is still accepted and threaded through to the
    // activity editor screen below (so the chain isn't broken for callers
    // that pass it), but it's no longer rendered here — the breadcrumb UI
    // was removed. If nothing downstream ends up reading it, it can be
    // dropped from the constructor in a follow-up pass; left in for now to
    // keep this change scoped to header/breadcrumb removal and the rename.

    return Scaffold(
      // NOTE: no Scaffold.appBar — replaced with TeacherScreenHeader.
      backgroundColor: AppColors.scaffoldBackground,
      body: Column(
        children: [
          TeacherScreenHeader(
            title: widget.unitTitle,
            subtitle: 'Lessons',
            color: c,
          ),
          Expanded(
            child: StreamBuilder(
              stream: db.getPersonalizedLessonsStream(
                  widget.groupId, widget.contentId, widget.unitId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: c));
                }
                final lessons = snapshot.data?.docs ?? [];

                if (lessons.isEmpty) {
                  return HierarchyEmptyState(
                    icon:        Icons.school_outlined,
                    title:       'No Lessons Yet',
                    subtitle:    'Tap + to create your first lesson',
                    color:       c,
                    actionLabel: 'Create First Lesson',
                    onAction: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CreatePersonalizedLessonScreen(
                          groupId:   widget.groupId,
                          contentId: widget.contentId,
                          unitId:    widget.unitId,
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
                  itemCount: lessons.length,
                  itemBuilder: (context, i) {
                    final doc   = lessons[i];
                    final data  = doc.data() as Map<String, dynamic>;
                    final title = data['title'] ?? 'Untitled';
                    final order = data['order']  ?? 0;

                    return HierarchyListCard(
                      order:    order,
                      title:    title,
                      subtitle: 'Tap to view activities',
                      color:    c,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TeacherActivityEditorScreen(
                            groupId:       widget.groupId,
                            contentId:     widget.contentId,
                            unitId:        widget.unitId,
                            lessonId:      doc.id,
                            lessonTitle:   title,
                            groupColor:    c,
                            ancestorTrail: [...widget.ancestorTrail, widget.unitTitle],
                          ),
                        ),
                      ),
                      onEdit:   () => _editLesson(doc.id, data),
                      onDelete: () => _deleteLesson(doc.id, title),
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
            builder: (_) => CreatePersonalizedLessonScreen(
              groupId:   widget.groupId,
              contentId: widget.contentId,
              unitId:    widget.unitId,
              groupColor: c,
            ),
          ),
        ),
        backgroundColor: c,
        elevation: 3,
        icon: const Icon(Icons.add, color: AppColors.onPrimary),
        label: const Text('Add Lesson',
            style: TextStyle(
                color: AppColors.onPrimary, fontWeight: FontWeight.bold)),
      ),
    );
  }
}