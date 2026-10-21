// teacher_content_structure_screen.dart
//
// Content -> Unit -> Lesson, as one screen replacing the old per-level push
// chain. Stays hierarchy-only (no quizzes) -- the header's quiz icon opens
// the Evaluaciones content (each Unit's Summative Quiz, each Lesson's
// Formative Quiz) as its own screen instead, so the two don't compete for
// space in one list. Each Lesson row's "Actividades ›" action hands off to
// the unchanged Activity/Task screens -- this screen never goes deeper than
// Lessons.
//
// Reuses everything the old per-level screens already had: the same
// Database CRUD calls, the same create/edit form screens
// (CreatePersonalizedUnitScreen / CreatePersonalizedLessonScreen), the same
// HierarchyPopupActions/HierarchyEmptyState primitives, and the same quiz
// slot widgets (SummativeQuizSlot / FormativeQuizSlot) -- including their
// existing "needs 3 lesson quizzes" unlock rule for a Unit's Summative
// Quiz, unchanged. Nothing about Firestore structure or business logic
// changes here -- this file is presentation only.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/teacher/content/create_lesson_screen.dart';
import 'package:loringo_app/screens/teacher/content/create_unit_screen.dart';
import 'package:loringo_app/screens/teacher/content/teacher_activity_editor_screen.dart';
import 'package:loringo_app/screens/teacher/content/widgets/hierarchy_list_cards.dart';
import 'package:loringo_app/screens/teacher/content/widgets/quiz_slot_section.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_screen_header.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

class TeacherContentStructureScreen extends StatelessWidget {
  final String groupId;
  final String contentId;
  final String contentTitle;
  final Color groupColor;

  const TeacherContentStructureScreen({
    super.key,
    required this.groupId,
    required this.contentId,
    required this.contentTitle,
    required this.groupColor,
  });

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    final db = Database();
    final c = groupColor;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: Column(
        children: [
          TeacherScreenHeader(
            title: contentTitle,
            subtitle: 'teacher.teacher_unit_editor_screen.units'.tr(),
            color: c,
            trailing: TeacherHeaderIconButton(
              icon: Icons.quiz_outlined,
              color: c,
              tooltip: 'teacher.teacher_content_structure_screen.evaluationsTab'.tr(),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _ContentEvaluationsScreen(
                    db: db,
                    groupId: groupId,
                    contentId: contentId,
                    contentTitle: contentTitle,
                    color: c,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _StructureTab(
              db: db,
              groupId: groupId,
              contentId: contentId,
              contentTitle: contentTitle,
              color: c,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addUnit(context, groupId, contentId, c),
        backgroundColor: c,
        elevation: 3,
        icon: const Icon(Icons.add, color: AppColors.onPrimary),
        label: Text('teacher.teacher_unit_editor_screen.addUnit'.tr(),
            style: const TextStyle(
                color: AppColors.onPrimary, fontWeight: FontWeight.bold)),
      ),
    );
  }

  static void _addUnit(
    BuildContext context,
    String groupId,
    String contentId,
    Color c,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePersonalizedUnitScreen(
          groupId: groupId,
          contentId: contentId,
          groupColor: c,
        ),
      ),
    );
  }
}

// Standalone Evaluaciones screen, opened from the header's quiz icon.
// Reuses _EvaluationsTab (and everything it reuses: SummativeQuizSlot,
// FormativeQuizSlot, the "3 lesson quizzes" unlock rule) completely
// unmodified -- just given its own screen instead of a TabBarView page.
class _ContentEvaluationsScreen extends StatelessWidget {
  const _ContentEvaluationsScreen({
    required this.db,
    required this.groupId,
    required this.contentId,
    required this.contentTitle,
    required this.color,
  });

  final Database db;
  final String groupId;
  final String contentId;
  final String contentTitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: Column(
        children: [
          TeacherScreenHeader(
            title: contentTitle,
            subtitle: 'teacher.teacher_content_structure_screen.evaluationsTab'.tr(),
            color: color,
          ),
          Expanded(
            child: _EvaluationsTab(
              db: db,
              groupId: groupId,
              contentId: contentId,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared node chrome (order badge + title + optional action + "⋮" menu) ──

Widget _nodeHeader({
  required String title,
  required Color color,
  required IconData icon,
  required VoidCallback onEdit,
  required VoidCallback onDelete,
  Widget? action,
}) {
  return Row(
    children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      if (action != null) ...[action, const SizedBox(width: AppSpacing.xs)],
      HierarchyPopupActions(onEdit: onEdit, onDelete: onDelete),
    ],
  );
}

Widget _addRow({
  required String label,
  required Color color,
  required VoidCallback onTap,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        alignment: Alignment.centerLeft,
      ),
      icon: const Icon(Icons.add, size: 18),
      label: Text(label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
    ),
  );
}

Future<bool> _confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('common.cancel'.tr())),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: AppColors.onPrimary,
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
              ),
              child: Text('common.delete'.tr()),
            ),
          ],
        ),
      ) ??
      false;
}

void _showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text('common.errorWithMessage'.tr(namedArgs: {'error': '$e'})),
    backgroundColor: AppColors.danger,
  ));
}

// Plain, non-animated expand/collapse header (not Flutter's ExpansionTile).
Widget _expandHeader({
  required Widget content,
  required bool expanded,
  required VoidCallback onToggle,
}) {
  return InkWell(
    onTap: onToggle,
    borderRadius: BorderRadius.circular(AppRadii.sm),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: content),
          Icon(
            expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            color: Colors.grey[400],
          ),
        ],
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════
// TAB 1 — Estructura (hierarchy only, no quizzes)
// ═══════════════════════════════════════════════════════════════════════

class _StructureTab extends StatelessWidget {
  const _StructureTab({
    required this.db,
    required this.groupId,
    required this.contentId,
    required this.contentTitle,
    required this.color,
  });

  final Database db;
  final String groupId;
  final String contentId;
  final String contentTitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: db.getPersonalizedUnitsStream(groupId, contentId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: color));
        }
        final units = snap.data?.docs ?? const [];

        if (units.isEmpty) {
          return HierarchyEmptyState(
            icon: Icons.layers_outlined,
            title: 'teacher.teacher_unit_editor_screen.noUnitsYet'.tr(),
            subtitle: 'teacher.teacher_unit_editor_screen.tapToCreateFirstUnit'.tr(),
            color: color,
            actionLabel: 'teacher.teacher_unit_editor_screen.createFirstUnit'.tr(),
            onAction: () => TeacherContentStructureScreen._addUnit(
                context, groupId, contentId, color),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, 100),
          itemCount: units.length,
          itemBuilder: (context, i) {
            final doc = units[i];
            final data = doc.data() as Map<String, dynamic>;
            return _UnitNode(
              key: ValueKey(doc.id),
              db: db,
              groupId: groupId,
              contentId: contentId,
              contentTitle: contentTitle,
              unitId: doc.id,
              title: data['title'] as String? ?? 'common.untitled'.tr(),
              data: data,
              color: color,
            );
          },
        );
      },
    );
  }
}

class _UnitNode extends StatefulWidget {
  const _UnitNode({
    super.key,
    required this.db,
    required this.groupId,
    required this.contentId,
    required this.contentTitle,
    required this.unitId,
    required this.title,
    required this.data,
    required this.color,
  });

  final Database db;
  final String groupId;
  final String contentId;
  final String contentTitle;
  final String unitId;
  final String title;
  final Map<String, dynamic> data;
  final Color color;

  @override
  State<_UnitNode> createState() => _UnitNodeState();
}

class _UnitNodeState extends State<_UnitNode> {
  bool _expanded = false;

  void _edit() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePersonalizedUnitScreen(
          groupId: widget.groupId,
          contentId: widget.contentId,
          groupColor: widget.color,
          unitId: widget.unitId,
          existingData: widget.data,
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final confirm = await _confirmDelete(
      context,
      title: 'teacher.teacher_unit_editor_screen.deleteUnitTitle'.tr(),
      message: 'teacher.teacher_unit_editor_screen.deleteUnitMsg'
          .tr(namedArgs: {'title': widget.title}),
    );
    if (!confirm) return;
    try {
      await widget.db
          .deletePersonalizedUnit(widget.groupId, widget.contentId, widget.unitId);
    } catch (e) {
      if (mounted) _showError(context, e);
    }
  }

  void _addLesson() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePersonalizedLessonScreen(
          groupId: widget.groupId,
          contentId: widget.contentId,
          unitId: widget.unitId,
          groupColor: widget.color,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    return Card(
      key: PageStorageKey(widget.unitId),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _expandHeader(
            expanded: _expanded,
            onToggle: () => setState(() => _expanded = !_expanded),
            content: _nodeHeader(
              title: widget.title,
              color: c,
              icon: Icons.folder_outlined,
              onEdit: _edit,
              onDelete: _delete,
            ),
          ),
          if (_expanded) ...[
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.lg),
              child: _LessonsList(
                db: widget.db,
                groupId: widget.groupId,
                contentId: widget.contentId,
                contentTitle: widget.contentTitle,
                unitId: widget.unitId,
                unitTitle: widget.title,
                color: c,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, 0, AppSpacing.sm, AppSpacing.sm),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _addRow(
                  label: 'teacher.teacher_lesson_editor_screen.addLesson'.tr(),
                  color: c,
                  onTap: _addLesson,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LessonsList extends StatelessWidget {
  const _LessonsList({
    required this.db,
    required this.groupId,
    required this.contentId,
    required this.contentTitle,
    required this.unitId,
    required this.unitTitle,
    required this.color,
  });

  final Database db;
  final String groupId;
  final String contentId;
  final String contentTitle;
  final String unitId;
  final String unitTitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: db.getPersonalizedLessonsStream(groupId, contentId, unitId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Center(child: CircularProgressIndicator(color: color)),
          );
        }
        final lessons = snap.data?.docs ?? const [];
        if (lessons.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Text(
              'teacher.teacher_lesson_editor_screen.noLessonsYet'.tr(),
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          );
        }
        return Column(
          children: [
            for (final doc in lessons)
              _LessonRow(
                key: ValueKey(doc.id),
                db: db,
                groupId: groupId,
                contentId: contentId,
                contentTitle: contentTitle,
                unitId: unitId,
                unitTitle: unitTitle,
                lessonId: doc.id,
                title: (doc.data() as Map<String, dynamic>)['title'] as String? ??
                    'common.untitled'.tr(),
                data: doc.data() as Map<String, dynamic>,
                color: color,
              ),
          ],
        );
      },
    );
  }
}

// Flat row -- no expand/collapse, since with quizzes moved to their own tab
// a Lesson has nothing left to expand into here. "Ver actividades" hands
// off to the existing, unchanged TeacherActivityEditorScreen (which itself
// still leads to TeacherTaskEditorScreen exactly as before).
class _LessonRow extends StatelessWidget {
  const _LessonRow({
    super.key,
    required this.db,
    required this.groupId,
    required this.contentId,
    required this.contentTitle,
    required this.unitId,
    required this.unitTitle,
    required this.lessonId,
    required this.title,
    required this.data,
    required this.color,
  });

  final Database db;
  final String groupId;
  final String contentId;
  final String contentTitle;
  final String unitId;
  final String unitTitle;
  final String lessonId;
  final String title;
  final Map<String, dynamic> data;
  final Color color;

  void _edit(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePersonalizedLessonScreen(
          groupId: groupId,
          contentId: contentId,
          unitId: unitId,
          groupColor: color,
          lessonId: lessonId,
          existingData: data,
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final confirm = await _confirmDelete(
      context,
      title: 'teacher.teacher_lesson_editor_screen.deleteLessonTitle'.tr(),
      message: 'teacher.teacher_lesson_editor_screen.deleteLessonMsg'
          .tr(namedArgs: {'title': title}),
    );
    if (!confirm) return;
    try {
      await db.deletePersonalizedLesson(groupId, contentId, unitId, lessonId);
    } catch (e) {
      if (context.mounted) _showError(context, e);
    }
  }

  void _openActivities(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TeacherActivityEditorScreen(
          groupId: groupId,
          contentId: contentId,
          unitId: unitId,
          lessonId: lessonId,
          lessonTitle: title,
          groupColor: color,
          ancestorTrail: [contentTitle, unitTitle],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: color.withOpacity(0.25), width: 2)),
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      child: _nodeHeader(
        title: title,
        color: color,
        icon: Icons.menu_book_outlined,
        onEdit: () => _edit(context),
        onDelete: () => _delete(context),
        // Compact, secondary to the Lesson title -- a text action with a
        // trailing chevron rather than an icon-led button, so it doesn't
        // visually compete with the row's own title.
        action: TextButton(
          onPressed: () => _openActivities(context),
          style: TextButton.styleFrom(
            foregroundColor: color,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'teacher.teacher_content_structure_screen.viewActivities'.tr(),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
              const Icon(Icons.chevron_right, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// TAB 2 — Evaluaciones (quizzes only, organized by Unit/Lesson, flat)
// ═══════════════════════════════════════════════════════════════════════

class _EvaluationsTab extends StatelessWidget {
  const _EvaluationsTab({
    required this.db,
    required this.groupId,
    required this.contentId,
    required this.color,
  });

  final Database db;
  final String groupId;
  final String contentId;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: db.getPersonalizedUnitsStream(groupId, contentId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: color));
        }
        final units = snap.data?.docs ?? const [];

        if (units.isEmpty) {
          return HierarchyEmptyState(
            icon: Icons.emoji_events_outlined,
            title: 'teacher.teacher_unit_editor_screen.noUnitsYet'.tr(),
            subtitle: 'teacher.teacher_content_structure_screen.noQuizzesYet'.tr(),
            color: color,
            actionLabel: 'teacher.teacher_unit_editor_screen.createFirstUnit'.tr(),
            onAction: () => TeacherContentStructureScreen._addUnit(
                context, groupId, contentId, color),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, 100),
          itemCount: units.length,
          itemBuilder: (context, i) {
            final doc = units[i];
            final data = doc.data() as Map<String, dynamic>;
            final unitOrder = data['order'] as int? ?? (i + 1);

            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'teacher.teacher_content_structure_screen.unitHeader'
                        .tr(namedArgs: {'order': '$unitOrder'}),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  SummativeQuizSlot(
                    contentId: contentId,
                    unitId: doc.id,
                    color: color,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.md),
                    child: _LessonQuizzes(
                      db: db,
                      groupId: groupId,
                      contentId: contentId,
                      unitId: doc.id,
                      color: color,
                    ),
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

class _LessonQuizzes extends StatelessWidget {
  const _LessonQuizzes({
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
    return StreamBuilder<QuerySnapshot>(
      stream: db.getPersonalizedLessonsStream(groupId, contentId, unitId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Center(child: CircularProgressIndicator(color: color)),
          );
        }
        final lessons = snap.data?.docs ?? const [];
        if (lessons.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Text(
              'teacher.teacher_lesson_editor_screen.noLessonsYet'.tr(),
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < lessons.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'teacher.teacher_content_structure_screen.lessonHeader'.tr(
                        namedArgs: {
                          'order':
                              '${(lessons[i].data() as Map<String, dynamic>)['order'] ?? i + 1}',
                        },
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FormativeQuizSlot(
                      contentId: contentId,
                      unitId: unitId,
                      lessonId: lessons[i].id,
                      lessonTitle: (lessons[i].data() as Map<String, dynamic>)['title']
                              as String? ??
                          'common.untitled'.tr(),
                      color: color,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
