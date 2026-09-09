// group_card.dart
// Shared by teacher_home_screen.dart ("My Groups") and
// archived_groups_screen.dart ("Archived Groups") — extracted from
// teacher_home_screen.dart so both lists render groups identically instead
// of drifting into two slightly different card designs over time.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/group_navigation_screen.dart';
import 'package:loringo_app/theme/app_theme.dart';

/// Produces a readable fallback label from the old int-based 'period' field
/// (1 or 2) for groups created before 'classroom' existed. Returns an empty
/// string if there's nothing to fall back to, so the UI can decide how to
/// display "no classroom set" rather than showing a confusing "Period null".
String legacyPeriodLabel(dynamic period) {
  if (period == 1) return 'teacher.group_card.period1'.tr();
  if (period == 2) return 'teacher.group_card.period2'.tr();
  return '';
}

class GroupCard extends StatelessWidget {
  final String groupId;
  final String name;
  final String colorHex;
  final int    academicYear;
  final String classroom;

  /// Shows a small "Archived" badge in the corner — used only by
  /// archived_groups_screen.dart. Tapping the card still opens
  /// TeacherGroupDetailsScreen either way; archiving never blocks access
  /// to a group, it only hides it from the main "My Groups" list.
  final bool isArchived;

  const GroupCard({
    super.key,
    required this.groupId,
    required this.name,
    required this.colorHex,
    required this.academicYear,
    required this.classroom,
    this.isArchived = false,
  });

  Color get _cardColor {
    try {
      return Color(
          int.parse('FF${colorHex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  void _openGroup(BuildContext context, Color color, {int initialTabIndex = 0}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TeacherGroupDetailsScreen(
          groupId:   groupId,
          groupName: name,
          groupColor: color,
          initialTabIndex: initialTabIndex,
        ),
      ),
    );
  }

  /// Toggles 'archived' directly on the group doc — same confirm-then-
  /// write shape used everywhere else in this app for a status change
  /// (see HierarchyListCard's onEdit/onDelete callers). Kept here rather
  /// than pushed up to a callback since both callers (My Groups, Archived
  /// Groups) would otherwise duplicate identical dialog copy and Firestore
  /// code — GroupCard already owns its own Firestore read for the content
  /// count, so owning this write too keeps the pattern consistent.
  Future<void> _toggleArchive(BuildContext context) async {
    final archiving = !isArchived;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md)),
        title: Text(archiving
            ? 'teacher.group_card.archiveGroupTitle'.tr()
            : 'teacher.group_card.unarchiveGroupTitle'.tr()),
        content: Text(archiving
            ? 'teacher.group_card.archiveGroupMsg'.tr(namedArgs: {'name': name})
            : 'teacher.group_card.unarchiveGroupMsg'.tr(namedArgs: {'name': name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: AppColors.onPrimary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.sm)),
            ),
            child: Text(archiving
                ? 'teacher.group_card.archive'.tr()
                : 'teacher.group_card.unarchive'.tr()),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    try {
      await FirebaseFirestore.instance
          .collection('teacherGroups')
          .doc(groupId)
          .update({'archived': archiving});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(archiving
              ? 'teacher.group_card.groupArchived'.tr()
              : 'teacher.group_card.groupUnarchived'.tr()),
          backgroundColor: AppColors.primary,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('common.errorWithMessage'.tr(namedArgs: {'error': '$e'})),
          backgroundColor: AppColors.danger,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _cardColor;
    return FutureBuilder<int>(
      future: _getAssignedUnitsCount(groupId),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;

        return GestureDetector(
          onTap: () => _openGroup(context, color),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md + 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, color.withOpacity(0.72)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppRadii.lg),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.28),
                  offset: const Offset(0, 6),
                  blurRadius: 14,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.onPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            classroom.isNotEmpty
                                ? '$academicYear · $classroom'
                                : '$academicYear',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.82),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isArchived) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.22),
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.archive_rounded,
                                color: AppColors.onPrimary, size: 13),
                            const SizedBox(width: AppSpacing.xs),
                            Text('teacher.group_card.archived'.tr(),
                                style: const TextStyle(
                                  color: AppColors.onPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                )),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    // The group code is never shown on the card, and this
                    // widget never even holds it (it's no longer stored in
                    // plaintext at all — see functions/src/groupCode.ts).
                    // Wherever a teacher deliberately views/shares it (e.g.
                    // the invite flow), it's fetched on demand via
                    // Database.revealGroupCode(groupId).
                    // "⋮" — Edit / Archive-Unarchive. A PopupMenuButton
                    // claims its own tap in the gesture arena, so this
                    // doesn't also trigger the card's onTap above (same
                    // nesting HierarchyPopupActions relies on elsewhere in
                    // the app).
                    PopupMenuButton<String>(
                      tooltip: 'teacher.group_card.groupOptions'.tr(),
                      icon: const Icon(Icons.more_vert_rounded,
                          color: AppColors.onPrimary, size: 20),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.md)),
                      onSelected: (value) {
                        if (value == 'edit') {
                          _openGroup(context, color, initialTabIndex: 4);
                        } else if (value == 'archive') {
                          _toggleArchive(context);
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(children: [
                            const Icon(Icons.edit_outlined, color: Colors.blue, size: 18),
                            const SizedBox(width: AppSpacing.sm),
                            Text('common.edit'.tr()),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'archive',
                          child: Row(children: [
                            Icon(
                                isArchived
                                    ? Icons.unarchive_outlined
                                    : Icons.archive_outlined,
                                color: AppColors.warning, size: 18),
                            const SizedBox(width: AppSpacing.sm),
                            Text(isArchived
                                ? 'teacher.group_card.unarchive'.tr()
                                : 'teacher.group_card.archive'.tr()),
                          ]),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    const Icon(Icons.folder_rounded,
                        color: AppColors.onPrimary, size: 18),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'teacher.group_card.contentCount'.plural(count),
                      style: const TextStyle(
                        color: AppColors.onPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.arrow_forward_ios_rounded,
                        color: AppColors.onPrimary, size: 16),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<int> _getAssignedUnitsCount(String groupId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('content')
          .where('assignedTo', arrayContains: groupId)
          .get();
      return snap.docs.length;
    } catch (_) {
      return 0;
    }
  }
}
