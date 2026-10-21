// teacher_lesson_editor_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/teacher/content/teacher_activity_editor_screen.dart';
import 'package:loringo_app/screens/teacher/content/create_lesson_screen.dart';
import 'package:loringo_app/screens/teacher/content/widgets/hierarchy_list_cards.dart';
import 'package:loringo_app/screens/teacher/content/widgets/quiz_slot_section.dart';
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

// Two tabs, same pattern as TeacherLeagueScreen's Ranking/Rewards split
// (and TeacherUnitEditorScreen's Units/Summative Quiz split): "Lessons"
// (create/reorder/manage lessons, unchanged) and "Formative Quiz" (each
// lesson's Lesson-scope quiz slot, one per row) -- kept apart so authoring
// a lesson and authoring its quiz aren't mixed into one list.
class _TeacherLessonEditorScreenState
    extends State<TeacherLessonEditorScreen> with SingleTickerProviderStateMixin {
  final Database db = Database();

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        // Only the Lessons tab has a FAB (Add Lesson) -- rebuild so it
        // disappears on the Quiz tab, whose own "+ Add" rows already
        // cover quiz creation.
        if (!_tabController.indexIsChanging) setState(() {});
      });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

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
          Container(
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadii.mdAll,
              boxShadow: AppShadows.card,
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: c,
              indicatorWeight: 3,
              dividerColor: Colors.transparent,
              labelColor: c,
              unselectedLabelColor: AppColors.textSecondary,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              tabs: [
                Tab(
                  icon: const Icon(Icons.school_outlined),
                  text: 'teacher.teacher_lesson_editor_screen.lessonsTab'.tr(),
                ),
                Tab(
                  icon: const Icon(Icons.menu_book_outlined),
                  text: 'teacher.teacher_lesson_editor_screen.formativeQuizTab'.tr(),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _LessonsTab(
                  db: db,
                  groupId: widget.groupId,
                  contentId: widget.contentId,
                  unitId: widget.unitId,
                  unitTitle: widget.unitTitle,
                  ancestorTrail: widget.ancestorTrail,
                  color: c,
                  onEditLesson: _editLesson,
                  onDeleteLesson: _deleteLesson,
                ),
                _LessonQuizTab(
                  db: db,
                  groupId: widget.groupId,
                  contentId: widget.contentId,
                  unitId: widget.unitId,
                  color: c,
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _tabController.index != 0
          ? null
          : FloatingActionButton.extended(
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

// ── Lessons tab ──────────────────────────────────────────────────────────

class _LessonsTab extends StatelessWidget {
  const _LessonsTab({
    required this.db,
    required this.groupId,
    required this.contentId,
    required this.unitId,
    required this.unitTitle,
    required this.ancestorTrail,
    required this.color,
    required this.onEditLesson,
    required this.onDeleteLesson,
  });

  final Database db;
  final String groupId;
  final String contentId;
  final String unitId;
  final String unitTitle;
  final List<String> ancestorTrail;
  final Color color;
  final void Function(String lessonId, Map<String, dynamic> data) onEditLesson;
  final void Function(String lessonId, String title) onDeleteLesson;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: db.getPersonalizedLessonsStream(groupId, contentId, unitId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: color));
        }
        final lessons = snapshot.data?.docs ?? [];

        if (lessons.isEmpty) {
          return HierarchyEmptyState(
            icon:        Icons.school_outlined,
            title:       'teacher.teacher_lesson_editor_screen.noLessonsYet'.tr(),
            subtitle:    'teacher.teacher_lesson_editor_screen.tapToCreateFirstLesson'.tr(),
            color:       color,
            actionLabel: 'teacher.teacher_lesson_editor_screen.createFirstLesson'.tr(),
            onAction: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CreatePersonalizedLessonScreen(
                  groupId:   groupId,
                  contentId: contentId,
                  unitId:    unitId,
                  groupColor: color,
                ),
              ),
            ),
          );
        }

        return ListView.builder(
          // Bottom padding leaves room so the FAB doesn't cover the last
          // card in the list.
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
              color:    color,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TeacherActivityEditorScreen(
                    groupId:       groupId,
                    contentId:     contentId,
                    unitId:        unitId,
                    lessonId:      lessonId,
                    lessonTitle:   title,
                    groupColor:    color,
                    ancestorTrail: [...ancestorTrail, unitTitle],
                  ),
                ),
              ),
              onEdit:   () => onEditLesson(lessonId, data),
              onDelete: () => onDeleteLesson(lessonId, title),
            );
          },
        );
      },
    );
  }
}

// ── Formative Quiz tab ───────────────────────────────────────────────────

class _LessonQuizTab extends StatelessWidget {
  const _LessonQuizTab({
    required this.db,
    required this.groupId,
    required this.contentId,
    required this.unitId,
    required this.color,
  });

  final Database db;
  final String groupId;
  final String contentId;
  final String unitId;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: db.getPersonalizedLessonsStream(groupId, contentId, unitId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: color));
        }
        final lessons = snapshot.data?.docs ?? [];

        if (lessons.isEmpty) {
          return HierarchyEmptyState(
            icon:        Icons.menu_book_outlined,
            title:       'teacher.teacher_lesson_editor_screen.noLessonsYet'.tr(),
            subtitle:    'teacher.teacher_lesson_editor_screen.tapToCreateFirstLesson'.tr(),
            color:       color,
            actionLabel: 'teacher.teacher_lesson_editor_screen.createFirstLesson'.tr(),
            onAction: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CreatePersonalizedLessonScreen(
                  groupId:   groupId,
                  contentId: contentId,
                  unitId:    unitId,
                  groupColor: color,
                ),
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          itemCount: lessons.length,
          itemBuilder: (context, i) {
            final doc   = lessons[i];
            final data  = doc.data() as Map<String, dynamic>;
            final title = data['title'] as String? ?? 'common.untitled'.tr();
            final lessonId = doc.id;

            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      left: AppSpacing.md,
                      bottom: AppSpacing.xs,
                    ),
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                  FormativeQuizSlot(
                    contentId: contentId,
                    unitId: unitId,
                    lessonId: lessonId,
                    lessonTitle: title,
                    color: color,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
