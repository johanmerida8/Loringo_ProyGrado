// teacher_lesson_editor_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
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
            title: Text('teacher.teacher_lesson_editor_screen.deleteLessonTitle'.tr()),
            content: Text(
                'teacher.teacher_lesson_editor_screen.deleteLessonMsg'
                    .tr(namedArgs: {'title': title})),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('common.cancel'.tr())),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: AppColors.onPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.sm)),
                ),
                child: Text('common.delete'.tr()),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('teacher.teacher_lesson_editor_screen.lessonDeleted'.tr()),
          backgroundColor: AppColors.primary,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('common.errorWithMessage'.tr(namedArgs: {'error': '$e'})),
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
    context.watch<LocaleProvider>();
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
            subtitle: 'teacher.teacher_lesson_editor_screen.lessons'.tr(),
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
                    title:       'teacher.teacher_lesson_editor_screen.noLessonsYet'.tr(),
                    subtitle:    'teacher.teacher_lesson_editor_screen.tapToCreateFirstLesson'.tr(),
                    color:       c,
                    actionLabel: 'teacher.teacher_lesson_editor_screen.createFirstLesson'.tr(),
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
                    final title = data['title'] ?? 'common.untitled'.tr();
                    final order = data['order']  ?? 0;
                    final lessonId = doc.id;

                    return HierarchyListCard(
                      order:    order,
                      title:    title,
                      subtitle: 'teacher.teacher_lesson_editor_screen.tapToViewActivities'.tr(),
                      color:    c,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TeacherActivityEditorScreen(
                            groupId:       widget.groupId,
                            contentId:     widget.contentId,
                            unitId:        widget.unitId,
                            lessonId:      lessonId,
                            lessonTitle:   title,
                            groupColor:    c,
                            ancestorTrail: [...widget.ancestorTrail, widget.unitTitle],
                          ),
                        ),
                      ),
                      onEdit:   () => _editLesson(lessonId, data),
                      onDelete: () => _deleteLesson(lessonId, title),
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
        label: Text('teacher.teacher_lesson_editor_screen.addLesson'.tr(),
            style: const TextStyle(
                color: AppColors.onPrimary, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
