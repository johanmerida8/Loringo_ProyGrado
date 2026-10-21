// quiz_slot_section.dart
//
// Quiz authoring, as part of Content: a Unit's Summative Quiz slot and a
// Lesson's Formative Quiz slot. Extracted from the old Group "Quizzes" tab
// (group_quizzes_screen.dart, now removed) -- this is the same _QuizRow/
// _AddQuizRow rendering, just mounted directly inside the Content
// authoring screens (TeacherLessonEditorScreen for Summative,
// TeacherActivityEditorScreen for Formative) instead of a separate
// cross-content Group tab. Database._assertNoExistingQuiz still enforces
// one quiz per unit(summative)/lesson(formative), unchanged. A Unit Quiz's
// empty slot still locks (see _AddQuizRow's subtitle) until the unit has
// Database.kMinLessonQuizzesForUnitQuiz Lesson Quizzes -- Database
// .createQuiz enforces the same rule server-side.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/teacher/content/create_quiz_screen.dart';
import 'package:loringo_app/screens/teacher/content/widgets/hierarchy_list_cards.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

// Quiz docs whose title was already checked against their Unit/Lesson name
// this session -- keeps the self-healing title sync (see
// Database.syncQuizTitleFromParent) to one extra read per quiz instead of
// one per rebuild. If the stored title was stale, the fix lands in
// Firestore and the slot's stream re-emits with the corrected title.
final Set<String> _titleCheckedQuizPaths = {};

void _ensureQuizTitleSynced(
  Database db, {
  required String contentId,
  required String unitId,
  String? lessonId,
  required DocumentSnapshot quizDoc,
}) {
  if (!_titleCheckedQuizPaths.add(quizDoc.reference.path)) return;
  db.syncQuizTitleFromParent(
    contentId: contentId,
    unitId: unitId,
    lessonId: lessonId,
    quizDoc: quizDoc,
  );
}

// ── Summative Quiz slot (Unit-scope) ────────────────────────────────────

class SummativeQuizSlot extends StatelessWidget {
  const SummativeQuizSlot({
    super.key,
    required this.contentId,
    required this.unitId,
    required this.color,
  });

  final String contentId;
  final String unitId;
  final Color color;

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    final db = Database();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      child: StreamBuilder<QuerySnapshot>(
        stream: db.getQuizzesStream(contentId, unitId),
        builder: (context, quizSnap) {
          final docs = quizSnap.data?.docs ?? const [];
          if (docs.isEmpty) {
            return FutureBuilder<int>(
              future: db.countLessonQuizzesForUnit(
                contentId: contentId,
                unitId: unitId,
              ),
              builder: (context, countSnap) {
                final lessonQuizCount = countSnap.data ?? 0;
                final ready =
                    lessonQuizCount >= Database.kMinLessonQuizzesForUnitQuiz;
                return _AddQuizRow(
                  label: 'teacher.group_quizzes_screen.addSummativeQuiz'.tr(),
                  color: color,
                  subtitle: ready
                      ? null
                      : 'teacher.group_quizzes_screen.addLessonQuizzesFirst'
                          .tr(namedArgs: {
                          'count': '$lessonQuizCount',
                          'min': '${Database.kMinLessonQuizzesForUnitQuiz}',
                        }),
                  onTap: ready
                      ? () => _openCreate(context)
                      : null,
                );
              },
            );
          }
          final doc = docs.first;
          _ensureQuizTitleSynced(
            db,
            contentId: contentId,
            unitId: unitId,
            quizDoc: doc,
          );
          return _QuizRow(
            contentId: contentId,
            unitId: unitId,
            quizId: doc.id,
            data: doc.data() as Map<String, dynamic>,
            color: color,
            db: db,
            onOpen: () => _openEdit(
              context,
              doc.id,
              doc.data() as Map<String, dynamic>,
            ),
          );
        },
      ),
    );
  }

  void _openCreate(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateQuizScreen(
          contentId: contentId,
          unitId: unitId,
          groupColor: color,
          scope: 'unit',
        ),
      ),
    );
  }

  void _openEdit(
    BuildContext context,
    String quizId,
    Map<String, dynamic> data,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateQuizScreen(
          contentId: contentId,
          unitId: unitId,
          groupColor: color,
          quizId: quizId,
          existingData: data,
        ),
      ),
    );
  }
}

// ── Formative Quiz slot (Lesson-scope) ──────────────────────────────────

class FormativeQuizSlot extends StatelessWidget {
  const FormativeQuizSlot({
    super.key,
    required this.contentId,
    required this.unitId,
    required this.lessonId,
    required this.lessonTitle,
    required this.color,
  });

  final String contentId;
  final String unitId;
  final String lessonId;
  final String lessonTitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    final db = Database();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      child: StreamBuilder<QuerySnapshot>(
        stream: db.getLessonQuizzesStream(contentId, unitId, lessonId),
        builder: (context, snap) {
          final docs = snap.data?.docs ?? const [];
          if (docs.isEmpty) {
            return _AddQuizRow(
              label: 'teacher.group_quizzes_screen.addFormativeQuiz'
                  .tr(namedArgs: {'lessonTitle': lessonTitle}),
              color: AppColors.primaryLight,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CreateQuizScreen(
                    contentId: contentId,
                    unitId: unitId,
                    groupColor: color,
                    scope: 'lesson',
                    lessonId: lessonId,
                    destinationTitle: lessonTitle,
                  ),
                ),
              ),
            );
          }
          final doc = docs.first;
          final data = doc.data() as Map<String, dynamic>;
          _ensureQuizTitleSynced(
            db,
            contentId: contentId,
            unitId: unitId,
            lessonId: lessonId,
            quizDoc: doc,
          );
          return _QuizRow(
            contentId: contentId,
            unitId: unitId,
            lessonId: lessonId,
            quizId: doc.id,
            data: data,
            color: color,
            db: db,
            onOpen: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CreateQuizScreen(
                  contentId: contentId,
                  unitId: unitId,
                  groupColor: color,
                  scope: 'lesson',
                  lessonId: lessonId,
                  quizId: doc.id,
                  existingData: data,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Existing-quiz row ────────────────────────────────────────────────────

class _QuizRow extends StatelessWidget {
  const _QuizRow({
    required this.contentId,
    required this.unitId,
    this.lessonId,
    required this.quizId,
    required this.data,
    required this.color,
    required this.db,
    required this.onOpen,
  });

  final String contentId;
  final String unitId;
  final String? lessonId;
  final String quizId;
  final Map<String, dynamic> data;
  final Color color;
  final Database db;
  final VoidCallback onOpen;

  bool get _isLesson => lessonId != null;

  Future<void> _delete(BuildContext context) async {
    final confirm =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            title: Text('teacher.group_quizzes_screen.deleteQuizTitle'.tr()),
            content: Text(
              'teacher.group_quizzes_screen.deleteQuizMsg'.tr(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('common.cancel'.tr()),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: AppColors.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                ),
                child: Text('common.delete'.tr()),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirm || !context.mounted) return;
    try {
      await db.deleteQuiz(
        contentId: contentId,
        unitId: unitId,
        lessonId: lessonId,
        quizId: quizId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('teacher.group_quizzes_screen.quizDeleted'.tr()),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('common.errorWithMessage'.tr(namedArgs: {'error': '$e'})),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return HierarchyListCard(
      title: data['title'] as String? ??
          'teacher.group_quizzes_screen.untitledQuiz'.tr(),
      color: color,
      onTap: onOpen,
      onEdit: onOpen,
      onDelete: () => _delete(context),
      trailingChip: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: (_isLesson ? AppColors.primaryLight : color).withOpacity(0.12),
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Text(
          _isLesson
              ? 'teacher.group_quizzes_screen.formative'.tr()
              : 'teacher.group_quizzes_screen.summative'.tr(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: _isLesson ? AppColors.primaryLight : color,
          ),
        ),
      ),
    );
  }
}

// ── Empty-slot "+ Add" row ───────────────────────────────────────────────

class _AddQuizRow extends StatelessWidget {
  const _AddQuizRow({
    required this.label,
    required this.color,
    required this.onTap,
    this.subtitle,
  });
  final String label;
  final Color color;
  // Null onTap = locked: same visual language as the locked-group rows in
  // TeacherContentEditorScreen's _AssignSheet (dimmed, lock icon, an
  // explanatory subtitle) -- used when a Unit Quiz can't be created yet
  // because its unit doesn't have enough Lesson Quizzes.
  final VoidCallback? onTap;
  final String? subtitle;

  bool get _locked => onTap == null;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: _locked ? 0.6 : 1.0,
      child: GestureDetector(
        onTap:
            onTap ??
            (subtitle == null
                ? null
                : () => ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(subtitle!)))),
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.md - 2),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: color.withOpacity(0.3), width: 1.5),
          ),
          child: Row(
            children: [
              Icon(
                _locked ? Icons.lock_outline : Icons.add_circle_outline,
                size: 18,
                color: color,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.warning,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
