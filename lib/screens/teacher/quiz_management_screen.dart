import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/create_lesson_quiz_screen.dart';
import 'package:loringo_app/screens/teacher/create_unit_quiz_screen.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_screen_header.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

// ── QuizManagementScreen ────────────────────────────────────────────────────
//
// NOTE: previously had a Scaffold.appBar (solid `groupColor` bar) plus a
// mix of hardcoded Colors.red/blue/amber/purple scattered across the type
// banner, badges and stat chips — inconsistent with the rest of the
// content hierarchy (which uses TeacherScreenHeader, no AppBar) and with
// the "use AppColors tokens exclusively" rule. Both are fixed here:
//   • AppBar removed → TeacherScreenHeader, matching Unit/Lesson/Activity/
//     Task editor screens and the flat "My Groups" look.
//   • Every hardcoded color replaced with an AppColors token, card shadow
//     replaced with AppShadows.card. The two semantic states this screen
//     needs (graded/unit-test vs practice/lesson-quiz) are expressed with
//     AppColors.danger and AppColors.info respectively — danger for
//     "graded, counts toward reports" carries the right visual weight
//     without introducing a new ad-hoc color, and info is already the
//     palette's designated "informational/practice" hue.

enum QuizManagementType { lesson, unit }

class QuizManagementScreen extends StatelessWidget {
  final QuizManagementType type;
  final String groupId;
  final String contentId;
  final String unitId;
  final String? lessonId;
  final String title;
  final Color groupColor;

  const QuizManagementScreen({
    super.key,
    required this.type,
    required this.groupId,
    required this.contentId,
    required this.unitId,
    this.lessonId,
    required this.title,
    required this.groupColor,
  }) : assert(
          type == QuizManagementType.unit || lessonId != null,
          'lessonId is required for lesson quiz management',
        );

  bool get _isLesson => type == QuizManagementType.lesson;

  String get _screenTitle =>
      _isLesson ? 'Lesson Quizzes' : 'Unit Tests';

  String get _emptyLabel =>
      _isLesson ? 'No quizzes yet for this lesson' : 'No unit tests yet';

  String get _emptySubtitle =>
      _isLesson
          ? 'Create a reinforcement quiz using your lesson activities'
          : 'Create a graded multiple-choice test for this unit';

  @override
  Widget build(BuildContext context) {
    final db = Database();
    final stream = _isLesson
        ? db.getLessonQuizzesStream(contentId, unitId, lessonId!)
        : db.getUnitQuizzesStream(contentId, unitId);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: Column(
        children: [
          TeacherScreenHeader(
            title: _screenTitle,
            subtitle: title,
            color: groupColor,
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: stream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final quizzes = snapshot.data!.docs;

                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md, AppSpacing.sm, AppSpacing.md, 100),
                  children: [
                    // ── Type explanation banner ──────────────────────────
                    _TypeBanner(isLesson: _isLesson, color: groupColor),
                    const SizedBox(height: AppSpacing.lg),

                    if (quizzes.isEmpty)
                      _EmptyState(
                        label: _emptyLabel,
                        subtitle: _emptySubtitle,
                        icon: _isLesson ? Icons.quiz_outlined : Icons.assignment_outlined,
                        color: groupColor,
                      )
                    else ...[
                      Text(
                        '${quizzes.length} ${quizzes.length == 1 ? 'quiz' : 'quizzes'} created',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ...quizzes.map((doc) => _QuizCard(
                        doc: doc,
                        type: type,
                        groupId: groupId,
                        contentId: contentId,
                        unitId: unitId,
                        lessonId: lessonId,
                        groupColor: groupColor,
                        db: db,
                      )),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: groupColor,
        elevation: 3,
        icon: const Icon(Icons.add, color: AppColors.onPrimary),
        label: Text(
          _isLesson ? 'New Lesson Quiz' : 'New Unit Test',
          style: const TextStyle(color: AppColors.onPrimary, fontWeight: FontWeight.bold),
        ),
        onPressed: () => _navigateToCreate(context, db),
      ),
    );
  }

  void _navigateToCreate(BuildContext context, Database db) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _isLesson
            ? CreatePersonalizedLessonQuizScreen(
                groupId: groupId, contentId: contentId,
                unitId: unitId, lessonId: lessonId!,
                groupColor: groupColor,
              )
            : CreatePersonalizedUnitQuizScreen(
                groupId: groupId, contentId: contentId,
                unitId: unitId, groupColor: groupColor,
              ),
      ),
    );
  }
}

// ── Type banner ──────────────────────────────────────────────────────────────

class _TypeBanner extends StatelessWidget {
  const _TypeBanner({required this.isLesson, required this.color});
  final bool isLesson;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
          child: Icon(isLesson ? Icons.quiz_outlined : Icons.assignment_outlined, color: color, size: 22),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              isLesson ? 'Lesson Quiz (Practice)' : 'Unit Test (Graded)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 3),
            Text(
              isLesson
                  ? 'Not graded — reuses your activity tasks as reinforcement. Awards up to 10 XP on completion.'
                  : 'Graded exam — teacher-written multiple choice questions. Score reported to parents. Awards up to 100 XP on passing.',
              style: const TextStyle(fontSize: 12, color: AppColors.muted, height: 1.4),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.label, required this.subtitle, required this.icon, required this.color});
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: color.withOpacity(0.08), shape: BoxShape.circle),
            child: Icon(icon, size: 52, color: color.withOpacity(0.5)),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(label, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, color: Colors.black87, fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(subtitle, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.muted, height: 1.4)),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text('Tap the button below to create one',
              style: TextStyle(fontSize: 12, color: AppColors.muted)),
        ],
      ),
    );
  }
}

// ── Quiz card ─────────────────────────────────────────────────────────────────

class _QuizCard extends StatelessWidget {
  const _QuizCard({
    required this.doc, required this.type, required this.groupId,
    required this.contentId, required this.unitId, required this.lessonId,
    required this.groupColor, required this.db,
  });

  final QueryDocumentSnapshot doc;
  final QuizManagementType type;
  final String groupId;
  final String contentId;
  final String unitId;
  final String? lessonId;
  final Color groupColor;
  final Database db;

  bool get _isLesson => type == QuizManagementType.lesson;

  @override
  Widget build(BuildContext context) {
    final data    = doc.data() as Map<String, dynamic>;
    final title   = data['title'] as String? ?? 'Untitled';
    final xp      = (data['xpReward'] as num?)?.toInt() ?? 0;
    final isGraded = data['isGraded'] == true;
    final passing  = (data['passingScore'] as num?)?.toInt() ?? 0;
    // Question count — lesson uses questionIds list, unit uses totalQuestions int
    final qCount  = _isLesson
        ? (data['questionIds'] as List?)?.length ?? 0
        : (data['totalQuestions'] as num?)?.toInt() ?? 0;

    // Semantic color for graded vs practice — danger carries the visual
    // weight of "counts toward a report", info marks "practice only".
    final typeColor = isGraded ? AppColors.danger : AppColors.info;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: groupColor.withOpacity(0.15), width: 1.5),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          // ── Header ─────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, 10, AppSpacing.sm),
            decoration: BoxDecoration(
              color: groupColor.withOpacity(0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.md)),
              border: Border(bottom: BorderSide(color: groupColor.withOpacity(0.1))),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: groupColor.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(isGraded ? Icons.assignment_outlined : Icons.quiz_outlined, color: groupColor, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: typeColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isGraded ? 'Graded · Unit Test' : 'Practice · Lesson Quiz',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: typeColor),
                    ),
                  ),
                ]),
              ),
              // Edit button
              IconButton(
                icon: Icon(Icons.edit_outlined, color: groupColor, size: 20),
                tooltip: 'Edit',
                onPressed: () => _navigateToEdit(context, data),
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 4),
              // Delete button
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
                tooltip: 'Delete',
                onPressed: () => _confirmDelete(context),
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(),
              ),
            ]),
          ),

          // ── Stats row ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
            child: Row(children: [
              _StatChip(icon: Icons.help_outline, label: '$qCount questions', color: groupColor),
              const SizedBox(width: 8),
              _StatChip(icon: Icons.star_rounded, label: '$xp XP', color: AppColors.warning),
              if (isGraded) ...[
                const SizedBox(width: 8),
                _StatChip(icon: Icons.check_circle_outline, label: 'Pass: $passing/$qCount', color: AppColors.success),
              ],
            ]),
          ),
        ],
      ),
    );
  }

  // Navigate to the CREATE screen in edit mode by passing existing data
  void _navigateToEdit(BuildContext context, Map<String, dynamic> data) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _isLesson
            ? CreatePersonalizedLessonQuizScreen(
                groupId: groupId, contentId: contentId,
                unitId: unitId, lessonId: lessonId!,
                groupColor: groupColor,
                quizId: doc.id,
                existingData: data,
              )
            : CreatePersonalizedUnitQuizScreen(
                groupId: groupId, contentId: contentId,
                unitId: unitId, groupColor: groupColor,
                quizId: doc.id,
                existingData: data,
              ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
        title: const Text('Delete Quiz', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('This quiz will be permanently deleted. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true || !context.mounted) return;

    try {
      if (_isLesson) {
        await db.deletePersonalizedLessonQuiz(quizId: doc.id);
      } else {
        await db.deletePersonalizedUnitQuiz(quizId: doc.id);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Quiz deleted'), backgroundColor: AppColors.danger),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}

// ── Stat chip ─────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}