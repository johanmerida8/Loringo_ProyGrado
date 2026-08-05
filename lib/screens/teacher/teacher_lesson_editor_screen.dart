// teacher_lesson_editor_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/create_quiz_screen.dart';
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

  // ── Lesson Quiz ──────────────────────────────────────────────────────────
  // Lives here — not on the Activities screen one level down — because a
  // Lesson Quiz belongs to a specific lesson, and lessons are represented
  // as rows *on this screen*. It is deliberately NOT inside that row's "⋮"
  // menu together with Edit/Delete: Edit/Delete act on the lesson's own
  // identity (rename/remove this lesson), while a Quiz is a separate piece
  // of educational content that happens to belong to it — mixing the two
  // made "Quiz" read as just another housekeeping action on the lesson
  // instead of a distinct thing a teacher builds. Instead it gets its own
  // always-visible chip on the row (see _buildQuizChip / trailingChip
  // below): a quick glance down the lesson list already shows which
  // lessons have a Quiz and which don't, no menu needs to be opened at
  // all. (Mirrors exactly how Unit Quiz sits on the unit's own row in
  // teacher_unit_editor_screen.dart, one level up.)

  void _openLessonQuiz(String lessonId, String lessonTitle,
      QueryDocumentSnapshot? existingQuiz) {
    final data = existingQuiz?.data() as Map<String, dynamic>?;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateQuizScreen(
          groupId:          widget.groupId,
          contentId:        widget.contentId,
          unitId:           widget.unitId,
          groupColor:       widget.groupColor,
          scope:            'lesson',
          lessonId:         lessonId,
          destinationTitle: lessonTitle,
          quizId:           existingQuiz?.id,
          existingData:     data,
        ),
      ),
    );
  }

  Future<void> _deleteLessonQuiz(String quizId) async {
    final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.md)),
            title: const Text('Delete Quiz'),
            content: const Text(
                'This quiz will be permanently deleted. This cannot be undone.'),
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
      await db.deleteQuiz(quizId: quizId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Quiz deleted'),
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

  /// The Quiz status chip for one lesson row — outline "+ Quiz" when none
  /// exists yet for this lesson, filled "Quiz ✓" when one does
  /// (one-per-lesson, enforced by Database._assertNoExistingQuiz — this
  /// chip only mirrors that rule so the teacher never has to guess). Tap
  /// always opens create-or-edit; long-press deletes, but only once a
  /// Quiz exists — there's nothing to delete otherwise.
  Widget _buildQuizChip({
    required bool hasQuiz,
    required VoidCallback onTap,
    required VoidCallback? onLongPress,
  }) {
    final c = widget.groupColor;
    return Tooltip(
      message: hasQuiz ? 'Tap to edit • hold to delete' : 'Create Lesson Quiz',
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            color: hasQuiz ? c : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(color: c, width: hasQuiz ? 0 : 1.4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(hasQuiz ? Icons.check_circle : Icons.add,
                  size: 14, color: hasQuiz ? AppColors.onPrimary : c),
              const SizedBox(width: 3),
              Text('Quiz',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: hasQuiz ? AppColors.onPrimary : c)),
            ],
          ),
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
                    final lessonId = doc.id;

                    // Per-row quiz lookup — scoped to this one lesson, so
                    // each card's menu only ever reflects that lesson's
                    // own Quiz, never another row's.
                    return StreamBuilder<QuerySnapshot>(
                      stream: db.getLessonQuizzesStream(
                          widget.contentId, widget.unitId, lessonId),
                      builder: (context, quizSnap) {
                        final quizDoc = quizSnap.data?.docs.isNotEmpty == true
                            ? quizSnap.data!.docs.first
                            : null;

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
                                lessonId:      lessonId,
                                lessonTitle:   title,
                                groupColor:    c,
                                ancestorTrail: [...widget.ancestorTrail, widget.unitTitle],
                              ),
                            ),
                          ),
                          onEdit:   () => _editLesson(lessonId, data),
                          onDelete: () => _deleteLesson(lessonId, title),
                          trailingChip: _buildQuizChip(
                            hasQuiz: quizDoc != null,
                            onTap: () => _openLessonQuiz(lessonId, title, quizDoc),
                            onLongPress: quizDoc != null
                                ? () => _deleteLessonQuiz(quizDoc.id)
                                : null,
                          ),
                        );
                      },
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
