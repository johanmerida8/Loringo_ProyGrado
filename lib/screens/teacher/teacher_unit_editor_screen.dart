// teacher_unit_editor_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/create_quiz_screen.dart';
import 'package:loringo_app/screens/teacher/create_unit_screen.dart';
import 'package:loringo_app/screens/teacher/teacher_lesson_editor_screen.dart';
import 'package:loringo_app/screens/teacher/widgets/hierarchy_list_cards.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_screen_header.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

class TeacherUnitEditorScreen extends StatefulWidget {
  final String groupId;
  final String contentId;
  final String contentTitle;
  final Color  groupColor;

  const TeacherUnitEditorScreen({
    super.key,
    required this.groupId,
    required this.contentId,
    required this.contentTitle,
    required this.groupColor,
  });

  @override
  State<TeacherUnitEditorScreen> createState() =>
      _TeacherUnitEditorScreenState();
}

class _TeacherUnitEditorScreenState
    extends State<TeacherUnitEditorScreen> {
  final Database _db = Database();
  Color get _c => widget.groupColor;

  Future<void> _deleteUnit(String id, String title) async {
    final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.md)),
            title: const Text('Delete Unit'),
            content: Text(
                'Delete "$title"?\nThis will also delete all lessons, activities and tasks inside it.'),
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
      await _db.deletePersonalizedUnit(widget.groupId, widget.contentId, id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Unit deleted'),
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

  void _editUnit(String id, Map<String, dynamic> data) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePersonalizedUnitScreen(
          groupId:      widget.groupId,
          contentId:    widget.contentId,
          groupColor:   _c,
          unitId:       id,
          existingData: data,
        ),
      ),
    );
  }

  // ── Unit Quiz ────────────────────────────────────────────────────────────
  // Lives here — not on the Lessons screen one level down — because a Unit
  // Quiz belongs to a specific unit, and units are represented as rows
  // *on this screen*. It is deliberately NOT inside that row's "⋮" menu
  // together with Edit/Delete: Edit/Delete act on the unit's own identity
  // (rename/remove this unit), while a Quiz is a separate piece of
  // educational content that happens to belong to it — mixing the two
  // made "Quiz" read as just another housekeeping action on the unit
  // instead of a distinct thing a teacher builds. Instead it gets its own
  // always-visible chip on the row (see _buildQuizChip / trailingChip
  // below): a quick glance down the unit list already shows which units
  // have a Quiz and which don't, no menu needs to be opened at all.

  void _openUnitQuiz(String unitId, String unitTitle,
      QueryDocumentSnapshot? existingQuiz) {
    final data = existingQuiz?.data() as Map<String, dynamic>?;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateQuizScreen(
          groupId:          widget.groupId,
          contentId:        widget.contentId,
          unitId:           unitId,
          groupColor:       _c,
          scope:            'unit',
          destinationTitle: unitTitle,
          quizId:           existingQuiz?.id,
          existingData:     data,
        ),
      ),
    );
  }

  Future<void> _deleteUnitQuiz(String quizId) async {
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
      await _db.deleteQuiz(quizId: quizId);
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

  /// The Quiz status chip for one unit row — outline "+ Quiz" when none
  /// exists yet for this unit, filled "Quiz ✓" when one does (one-per-unit,
  /// enforced by Database._assertNoExistingQuiz — this chip only mirrors
  /// that rule so the teacher never has to guess). Tap always opens
  /// create-or-edit; long-press deletes, but only once a Quiz exists —
  /// there's nothing to delete otherwise.
  Widget _buildQuizChip({
    required bool hasQuiz,
    required VoidCallback onTap,
    required VoidCallback? onLongPress,
  }) {
    return Tooltip(
      message: hasQuiz ? 'Tap to edit • hold to delete' : 'Create Unit Quiz',
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            color: hasQuiz ? _c : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(color: _c, width: hasQuiz ? 0 : 1.4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(hasQuiz ? Icons.check_circle : Icons.add,
                  size: 14, color: hasQuiz ? AppColors.onPrimary : _c),
              const SizedBox(width: 3),
              Text('Quiz',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: hasQuiz ? AppColors.onPrimary : _c)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // NOTE: no Scaffold.appBar — replaced with TeacherScreenHeader as the
      // first item in the body below, per the flat "My Groups"-style look.
      // The old breadcrumb strip (Content > Unit) is removed entirely.
      backgroundColor: AppColors.scaffoldBackground,
      body: Column(
        children: [
          TeacherScreenHeader(
            title: widget.contentTitle,
            subtitle: 'Units',
            color: _c,
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db.getPersonalizedUnitsStream(
                  widget.groupId, widget.contentId),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: _c));
                }
                final units = snap.data?.docs ?? [];

                if (units.isEmpty) {
                  return HierarchyEmptyState(
                    icon:        Icons.layers_outlined,
                    title:       'No Units Yet',
                    subtitle:    'Tap + to create your first unit',
                    color:       _c,
                    actionLabel: 'Create First Unit',
                    onAction: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CreatePersonalizedUnitScreen(
                          groupId:   widget.groupId,
                          contentId: widget.contentId,
                          groupColor: _c,
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
                  itemCount: units.length,
                  itemBuilder: (context, i) {
                    final doc   = units[i];
                    final data  = doc.data() as Map<String, dynamic>;
                    final title = data['title'] ?? 'Untitled';
                    final order = data['order']  ?? 0;
                    final unitId = doc.id;

                    // Per-row quiz lookup — scoped to this one unit, so
                    // each card's menu only ever reflects that unit's own
                    // Quiz, never another row's.
                    return StreamBuilder<QuerySnapshot>(
                      stream: _db.getQuizzesStream(widget.contentId, unitId),
                      builder: (context, quizSnap) {
                        final quizDoc = quizSnap.data?.docs.isNotEmpty == true
                            ? quizSnap.data!.docs.first
                            : null;

                        return HierarchyListCard(
                          order:    order,
                          title:    title,
                          subtitle: 'Tap to view lessons',
                          color:    _c,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TeacherLessonEditorScreen(
                                groupId:       widget.groupId,
                                contentId:     widget.contentId,
                                unitId:        unitId,
                                unitTitle:     title,
                                groupColor:    _c,
                                ancestorTrail: [widget.contentTitle],
                              ),
                            ),
                          ),
                          onEdit:   () => _editUnit(unitId, data),
                          onDelete: () => _deleteUnit(unitId, title),
                          trailingChip: _buildQuizChip(
                            hasQuiz: quizDoc != null,
                            onTap: () => _openUnitQuiz(unitId, title, quizDoc),
                            onLongPress: quizDoc != null
                                ? () => _deleteUnitQuiz(quizDoc.id)
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
            builder: (_) => CreatePersonalizedUnitScreen(
              groupId:   widget.groupId,
              contentId: widget.contentId,
              groupColor: _c,
            ),
          ),
        ),
        backgroundColor: _c,
        elevation: 3,
        icon: const Icon(Icons.add, color: AppColors.onPrimary),
        label: const Text('Add Unit',
            style: TextStyle(
                color: AppColors.onPrimary, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
