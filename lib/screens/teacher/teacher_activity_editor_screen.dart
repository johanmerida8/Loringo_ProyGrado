// teacher_activity_editor_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
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
  final Color groupColor;
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

  // Local working copy of the activity list, used only while a
  // drag-reorder is in flight (see _handleReorder) so the dragged item's
  // new position stays put during the confirm dialog instead of snapping
  // back to the stream's still-unwritten order. Reset to null once the
  // reorder resolves (confirmed and written, or cancelled) so the next
  // build picks the stream's docs straight up again.
  List<QueryDocumentSnapshot>? _reorderingItems;

  Future<void> _handleReorder(
    List<QueryDocumentSnapshot> current,
    int oldIndex,
    int newIndex,
  ) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final reordered = List<QueryDocumentSnapshot>.from(current);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    setState(() => _reorderingItems = reordered);

    final movedTitle =
        (moved.data() as Map<String, dynamic>)['title'] as String? ??
        'teacher.teacher_activity_editor_screen.thisActivity'.tr();
    final confirm =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            title: Text('teacher.teacher_activity_editor_screen.reorderActivitiesTitle'.tr()),
            content: Text(
              'teacher.teacher_activity_editor_screen.reorderActivitiesMsg'.tr(
                namedArgs: {
                  'title': movedTitle,
                  'position': '${newIndex + 1}',
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('common.cancel'.tr()),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.groupColor,
                  foregroundColor: AppColors.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                ),
                child: Text('common.confirm'.tr()),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) {
      if (mounted) setState(() => _reorderingItems = null);
      return;
    }

    try {
      await db.reorderPersonalizedActivities(
        contentId: widget.contentId,
        unitId: widget.unitId,
        lessonId: widget.lessonId,
        orderedActivityIds: reordered.map((d) => d.id).toList(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('common.errorWithMessage'.tr(namedArgs: {'error': '$e'})),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      // Cleared regardless of success/failure -- the next StreamBuilder
      // snapshot reflects whatever Firestore actually ended up with, which
      // is the correct thing to show either way.
      if (mounted) setState(() => _reorderingItems = null);
    }
  }

  Future<void> _deleteActivity(String activityId, String title) async {
    final confirm =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            title: Text('teacher.teacher_activity_editor_screen.deleteActivityTitle'.tr()),
            content: Text(
              'teacher.teacher_activity_editor_screen.deleteActivityMsg'
                  .tr(namedArgs: {'title': title}),
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
    if (!confirm) return;
    try {
      await db.deletePersonalizedActivity(
        widget.groupId,
        widget.contentId,
        widget.unitId,
        widget.lessonId,
        activityId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('teacher.teacher_activity_editor_screen.activityDeleted'.tr()),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('common.errorWithMessage'.tr(namedArgs: {'error': '$e'})),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  void _editActivity(String activityId, Map<String, dynamic> data) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePersonalizedActivityScreen(
          groupId: widget.groupId,
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: widget.lessonId,
          groupColor: widget.groupColor,
          activityId: activityId,
          existingData: data,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    final c = widget.groupColor;

    return Scaffold(
      // NOTE: no Scaffold.appBar — replaced with TeacherScreenHeader.
      backgroundColor: AppColors.scaffoldBackground,
      body: Column(
        children: [
          TeacherScreenHeader(
            title: widget.lessonTitle,
            subtitle: 'teacher.teacher_activity_editor_screen.activities'.tr(),
            color: c,
          ),
          Expanded(
            child: StreamBuilder(
              stream: db.getPersonalizedActivitiesStream(
                widget.groupId,
                widget.contentId,
                widget.unitId,
                widget.lessonId,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: c));
                }
                final streamActivities = snapshot.data?.docs ?? [];
                // While a reorder is in flight, keep showing the local
                // optimistic order instead of the stream's (still stale
                // or now-being-written) order -- see _handleReorder.
                final activities = _reorderingItems ?? streamActivities;

                if (activities.isEmpty) {
                  return HierarchyEmptyState(
                    icon: Icons.task_outlined,
                    title: 'teacher.teacher_activity_editor_screen.noActivitiesYet'.tr(),
                    subtitle: 'teacher.teacher_activity_editor_screen.tapToCreateFirstActivity'.tr(),
                    color: c,
                    actionLabel: 'teacher.teacher_activity_editor_screen.createFirstActivity'.tr(),
                    onAction: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CreatePersonalizedActivityScreen(
                          groupId: widget.groupId,
                          contentId: widget.contentId,
                          unitId: widget.unitId,
                          lessonId: widget.lessonId,
                          groupColor: c,
                        ),
                      ),
                    ),
                  );
                }

                return ReorderableListView.builder(
                  // Bottom padding leaves room so the FAB doesn't cover
                  // the last card in the list.
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    100,
                  ),
                  itemCount: activities.length,
                  // Off: its automatic web/desktop handle appends at the
                  // TRAILING edge of every item, landing right on top of
                  // HierarchyListCard's own "⋮" popup menu. We provide our
                  // own handle placement instead -- see below.
                  buildDefaultDragHandles: false,
                  onReorder: (oldIndex, newIndex) =>
                      _handleReorder(activities, oldIndex, newIndex),
                  itemBuilder: (context, i) {
                    final doc = activities[i];
                    final data = doc.data() as Map<String, dynamic>;
                    final title = data['title'] ?? 'common.untitled'.tr();
                    final order = data['order'] ?? 0;
                    final xp = data['xpBase'] ?? 0;
                    final difficulty = data['difficulty'] ?? 'easy';
                    final isFirst = i == 0;

                    final diffColor = AppColors.difficulty(difficulty);

                    final card = HierarchyListCard(
                      order: order,
                      title: title,
                      color: c,
                      // Web/mouse: no long-press gesture exists, so give
                      // it an explicit handle rendered as part of the
                      // card itself instead. Mobile/touch: null here --
                      // unchanged long-press-anywhere, via the delayed-
                      // drag listener wrapping the whole card below.
                      dragHandle: kIsWeb
                          ? ReorderableDragStartListener(
                              index: i,
                              child: Icon(
                                Icons.drag_indicator_rounded,
                                color: Colors.grey[400],
                              ),
                            )
                          : null,
                      badge: Row(
                        children: [
                          if (isFirst) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm - 2,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: c.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(
                                  AppRadii.sm,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.flag_rounded, size: 11, color: c),
                                  const SizedBox(width: 3),
                                  Text(
                                    'teacher.teacher_activity_editor_screen.startHere'.tr(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: c,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                          ],
                          Icon(
                            Icons.star_rounded,
                            size: 14,
                            color: Colors.amber[700],
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '$xp XP',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm - 2,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: diffColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(AppRadii.sm),
                            ),
                            child: Text(
                              switch (difficulty) {
                                'medium' => 'common.medium'.tr(),
                                'hard' => 'common.hard'.tr(),
                                _ => 'common.easy'.tr(),
                              },
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: diffColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          settings: const RouteSettings(
                            name: kTeacherTaskEditorRoute,
                          ),
                          builder: (_) => TeacherTaskEditorScreen(
                            groupId: widget.groupId,
                            contentId: widget.contentId,
                            unitId: widget.unitId,
                            lessonId: widget.lessonId,
                            activityId: doc.id,
                            activityTitle: title,
                            groupColor: c,
                            ancestorTrail: [
                              ...widget.ancestorTrail,
                              widget.lessonTitle,
                            ],
                          ),
                        ),
                      ),
                      onEdit: () => _editActivity(doc.id, data),
                      onDelete: () => _deleteActivity(doc.id, title),
                    );

                    // Web: the card's own dragHandle (above) already
                    // registers the drag start, so just key it. Mobile:
                    // wrap the whole card so long-press-anywhere works,
                    // same delayed-drag listener buildDefaultDragHandles
                    // uses internally for touch platforms.
                    if (kIsWeb) {
                      return KeyedSubtree(key: ValueKey(doc.id), child: card);
                    }
                    return ReorderableDelayedDragStartListener(
                      key: ValueKey(doc.id),
                      index: i,
                      child: card,
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
              groupId: widget.groupId,
              contentId: widget.contentId,
              unitId: widget.unitId,
              lessonId: widget.lessonId,
              groupColor: c,
            ),
          ),
        ),
        backgroundColor: c,
        elevation: 3,
        icon: const Icon(Icons.add, color: AppColors.onPrimary),
        label: Text(
          'teacher.teacher_activity_editor_screen.addActivity'.tr(),
          style: const TextStyle(
            color: AppColors.onPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
