// group_quizzes_screen.dart
// Shows one group's quizzes organized as Content -> Unit -> Lesson, each
// Unit showing its Summative (unit-scope) quiz slot and each of its
// Lessons showing their Formative (lesson-scope) quiz slot. An empty slot
// is a "+ Add" row that pushes CreateQuizScreen directly, pre-filled with
// the destination already known from context -- no picker wizard needed,
// unlike the old cross-group flat list this replaced
// (teacher_quizzes_screen.dart). Database._assertNoExistingQuiz still
// enforces one quiz per unit(summative)/lesson(formative), unchanged. A
// Unit Quiz's empty slot additionally locks (see _AddQuizRow's subtitle)
// until the unit has Database.kMinLessonQuizzesForUnitQuiz Lesson
// Quizzes -- Database.createQuiz enforces the same rule server-side.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/teacher/create_quiz_screen.dart';
import 'package:loringo_app/screens/teacher/widgets/hierarchy_list_cards.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_screen_header.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

class GroupQuizzesScreen extends StatefulWidget {
  const GroupQuizzesScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.groupColor,
    this.embedded = false,
  });

  final String groupId;
  final String groupName;
  final Color groupColor;

  /// When true, renders without its own Scaffold/TeacherScreenHeader --
  /// used when this screen is embedded as a tab inside
  /// TeacherGroupDetailsScreen (group_navigation_screen.dart), which
  /// already shows the group name and a drawer/back affordance in its own
  /// header. Mirrors TeacherActivityScreen's `embedded` flag.
  final bool embedded;

  @override
  State<GroupQuizzesScreen> createState() => _GroupQuizzesScreenState();
}

class _GroupQuizzesScreenState extends State<GroupQuizzesScreen> {
  final Database _db = Database();

  // 'all' | 'unit' (Summative) | 'lesson' (Formative)
  String _selectedScope = 'all';

  Color get _c => widget.groupColor;

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    final body = Column(
      children: [
        if (!widget.embedded)
          TeacherScreenHeader(title: widget.groupName, color: _c),
        _buildFilterChips(),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _db.getPersonalizedContentStream(widget.groupId),
            builder: (context, contentSnap) {
              if (contentSnap.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator(color: _c));
              }
              final contentDocs = contentSnap.data?.docs ?? const [];
              if (contentDocs.isEmpty) {
                return _EmptyState(
                  icon: Icons.quiz_outlined,
                  title: 'teacher.group_quizzes_screen.noContentTitle'.tr(),
                  subtitle:
                      'teacher.group_quizzes_screen.noContentSubtitle'.tr(),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  100,
                ),
                itemCount: contentDocs.length,
                itemBuilder: (context, i) {
                  final doc = contentDocs[i];
                  final data = doc.data() as Map<String, dynamic>;
                  return _ContentSection(
                    groupId: widget.groupId,
                    contentId: doc.id,
                    contentTitle: data['title'] as String? ??
                        'teacher.group_quizzes_screen.untitledContent'.tr(),
                    color: _c,
                    selectedScope: _selectedScope,
                    db: _db,
                  );
                },
              );
            },
          ),
        ),
      ],
    );

    if (widget.embedded) return body;
    return Scaffold(backgroundColor: AppColors.scaffoldBackground, body: body);
  }

  // Single segmented control, tinted to the group's own accent color, so
  // it reads as one cohesive piece of the group's section instead of three
  // independent floating chips.
  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.subtleFill,
          borderRadius: AppRadii.pillAll,
        ),
        child: Row(
          children: [
            _scopeSegment('teacher.group_quizzes_screen.all'.tr(), 'all',
                Icons.apps_rounded),
            _scopeSegment('teacher.group_quizzes_screen.summative'.tr(),
                'unit', Icons.emoji_events_outlined),
            _scopeSegment('teacher.group_quizzes_screen.formative'.tr(),
                'lesson', Icons.menu_book_outlined),
          ],
        ),
      ),
    );
  }

  Widget _scopeSegment(String label, String scope, IconData icon) {
    final isSelected = _selectedScope == scope;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedScope = scope),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? _c : Colors.transparent,
            borderRadius: AppRadii.pillAll,
            boxShadow: isSelected ? AppShadows.floating(_c) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected
                    ? AppColors.onPrimary
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected
                        ? AppColors.onPrimary
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Content section ──────────────────────────────────────────────────────

class _ContentSection extends StatelessWidget {
  const _ContentSection({
    required this.groupId,
    required this.contentId,
    required this.contentTitle,
    required this.color,
    required this.selectedScope,
    required this.db,
  });

  final String groupId;
  final String contentId;
  final String contentTitle;
  final Color color;
  final String selectedScope;
  final Database db;

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return StreamBuilder<QuerySnapshot>(
      stream: db.getPersonalizedUnitsStream(groupId, contentId),
      builder: (context, unitSnap) {
        final unitDocs = unitSnap.data?.docs ?? const [];
        if (unitDocs.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.md,
                bottom: AppSpacing.xs,
              ),
              child: Text(
                contentTitle,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
            ...unitDocs.map(
              (unitDoc) => _UnitSection(
                groupId: groupId,
                contentId: contentId,
                unitId: unitDoc.id,
                unitTitle:
                    (unitDoc.data() as Map)['title'] as String? ??
                    'teacher.group_quizzes_screen.untitledUnit'.tr(),
                color: color,
                selectedScope: selectedScope,
                db: db,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Unit section ─────────────────────────────────────────────────────────

class _UnitSection extends StatelessWidget {
  const _UnitSection({
    required this.groupId,
    required this.contentId,
    required this.unitId,
    required this.unitTitle,
    required this.color,
    required this.selectedScope,
    required this.db,
  });

  final String groupId;
  final String contentId;
  final String unitId;
  final String unitTitle;
  final Color color;
  final String selectedScope;
  final Database db;

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              unitTitle,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          if (selectedScope == 'all' || selectedScope == 'unit')
            StreamBuilder<QuerySnapshot>(
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
                          lessonQuizCount >=
                          Database.kMinLessonQuizzesForUnitQuiz;
                      return _AddQuizRow(
                        label: 'teacher.group_quizzes_screen.addSummativeQuiz'
                            .tr(),
                        color: color,
                        subtitle: ready
                            ? null
                            : 'teacher.group_quizzes_screen.addLessonQuizzesFirst'
                                .tr(namedArgs: {
                                'count': '$lessonQuizCount',
                                'min':
                                    '${Database.kMinLessonQuizzesForUnitQuiz}',
                              }),
                        onTap: ready
                            ? () => _openCreate(context, scope: 'unit')
                            : null,
                      );
                    },
                  );
                }
                final doc = docs.first;
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
          if (selectedScope == 'all' || selectedScope == 'lesson')
            StreamBuilder<QuerySnapshot>(
              stream: db.getPersonalizedLessonsStream(
                groupId,
                contentId,
                unitId,
              ),
              builder: (context, lessonSnap) {
                final lessonDocs = lessonSnap.data?.docs ?? const [];
                if (lessonDocs.isEmpty) return const SizedBox.shrink();
                return Column(
                  children: lessonDocs
                      .map(
                        (lessonDoc) => _LessonQuizRow(
                          groupId: groupId,
                          contentId: contentId,
                          unitId: unitId,
                          lessonId: lessonDoc.id,
                          lessonTitle:
                              (lessonDoc.data() as Map)['title'] as String? ??
                              'teacher.group_quizzes_screen.untitledLesson'
                                  .tr(),
                          color: color,
                          db: db,
                        ),
                      )
                      .toList(),
                );
              },
            ),
        ],
      ),
    );
  }

  void _openCreate(
    BuildContext context, {
    required String scope,
    String? lessonId,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateQuizScreen(
          groupId: groupId,
          contentId: contentId,
          unitId: unitId,
          groupColor: color,
          scope: scope,
          lessonId: lessonId,
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
          groupId: groupId,
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

// ── Lesson row (Formative) ───────────────────────────────────────────────

class _LessonQuizRow extends StatelessWidget {
  const _LessonQuizRow({
    required this.groupId,
    required this.contentId,
    required this.unitId,
    required this.lessonId,
    required this.lessonTitle,
    required this.color,
    required this.db,
  });

  final String groupId;
  final String contentId;
  final String unitId;
  final String lessonId;
  final String lessonTitle;
  final Color color;
  final Database db;

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return StreamBuilder<QuerySnapshot>(
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
                  groupId: groupId,
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
                groupId: groupId,
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
      order: 1,
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

// ── Empty state ──────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 72, color: Colors.grey[300]),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }
}
