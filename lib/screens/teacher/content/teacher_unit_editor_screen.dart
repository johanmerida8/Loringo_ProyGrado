// teacher_unit_editor_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/teacher/content/create_unit_screen.dart';
import 'package:loringo_app/screens/teacher/content/teacher_lesson_editor_screen.dart';
import 'package:loringo_app/screens/teacher/content/widgets/hierarchy_list_cards.dart';
import 'package:loringo_app/screens/teacher/content/widgets/quiz_slot_section.dart';
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

// Two tabs, same pattern as TeacherLeagueScreen's Ranking/Rewards split:
// "Units" (create/reorder/manage units, unchanged) and "Summative Quiz"
// (each unit's Unit-scope quiz slot, one per row) -- kept apart so
// authoring a unit and authoring its quiz aren't mixed into one list.
class _TeacherUnitEditorScreenState
    extends State<TeacherUnitEditorScreen> with SingleTickerProviderStateMixin {
  final Database _db = Database();
  Color get _c => widget.groupColor;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        // Only the Units tab has a FAB (Add Unit) -- rebuild so it
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

  Future<void> _deleteUnit(String id, String title) async {
    final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.md)),
            title: Text('teacher.teacher_unit_editor_screen.deleteUnitTitle'.tr()),
            content: Text(
                'teacher.teacher_unit_editor_screen.deleteUnitMsg'
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
      await _db.deletePersonalizedUnit(widget.groupId, widget.contentId, id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('teacher.teacher_unit_editor_screen.unitDeleted'.tr()),
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

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return Scaffold(
      // NOTE: no Scaffold.appBar — replaced with TeacherScreenHeader as the
      // first item in the body below, per the flat "My Groups"-style look.
      // The old breadcrumb strip (Content > Unit) is removed entirely.
      backgroundColor: AppColors.scaffoldBackground,
      body: Column(
        children: [
          TeacherScreenHeader(
            title: widget.contentTitle,
            subtitle: 'teacher.teacher_unit_editor_screen.units'.tr(),
            color: _c,
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
              indicatorColor: _c,
              indicatorWeight: 3,
              dividerColor: Colors.transparent,
              labelColor: _c,
              unselectedLabelColor: AppColors.textSecondary,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              tabs: [
                Tab(
                  icon: const Icon(Icons.layers_outlined),
                  text: 'teacher.teacher_unit_editor_screen.unitsTab'.tr(),
                ),
                Tab(
                  icon: const Icon(Icons.emoji_events_outlined),
                  text: 'teacher.teacher_unit_editor_screen.summativeQuizTab'.tr(),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _UnitsTab(
                  db: _db,
                  groupId: widget.groupId,
                  contentId: widget.contentId,
                  contentTitle: widget.contentTitle,
                  color: _c,
                  onEditUnit: _editUnit,
                  onDeleteUnit: _deleteUnit,
                ),
                _UnitQuizTab(
                  db: _db,
                  groupId: widget.groupId,
                  contentId: widget.contentId,
                  color: _c,
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
              label: Text('teacher.teacher_unit_editor_screen.addUnit'.tr(),
                  style: const TextStyle(
                      color: AppColors.onPrimary, fontWeight: FontWeight.bold)),
            ),
    );
  }
}

// ── Units tab ────────────────────────────────────────────────────────────

class _UnitsTab extends StatelessWidget {
  const _UnitsTab({
    required this.db,
    required this.groupId,
    required this.contentId,
    required this.contentTitle,
    required this.color,
    required this.onEditUnit,
    required this.onDeleteUnit,
  });

  final Database db;
  final String groupId;
  final String contentId;
  final String contentTitle;
  final Color color;
  final void Function(String id, Map<String, dynamic> data) onEditUnit;
  final void Function(String id, String title) onDeleteUnit;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: db.getPersonalizedUnitsStream(groupId, contentId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: color));
        }
        final units = snap.data?.docs ?? [];

        if (units.isEmpty) {
          return HierarchyEmptyState(
            icon:        Icons.layers_outlined,
            title:       'teacher.teacher_unit_editor_screen.noUnitsYet'.tr(),
            subtitle:    'teacher.teacher_unit_editor_screen.tapToCreateFirstUnit'.tr(),
            color:       color,
            actionLabel: 'teacher.teacher_unit_editor_screen.createFirstUnit'.tr(),
            onAction: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CreatePersonalizedUnitScreen(
                  groupId:   groupId,
                  contentId: contentId,
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
          itemCount: units.length,
          itemBuilder: (context, i) {
            final doc   = units[i];
            final data  = doc.data() as Map<String, dynamic>;
            final title = data['title'] ?? 'common.untitled'.tr();
            final order = data['order']  ?? 0;
            final unitId = doc.id;

            return HierarchyListCard(
              order:    order,
              title:    title,
              subtitle: 'teacher.teacher_unit_editor_screen.tapToViewLessons'.tr(),
              color:    color,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TeacherLessonEditorScreen(
                    groupId:       groupId,
                    contentId:     contentId,
                    unitId:        unitId,
                    unitTitle:     title,
                    groupColor:    color,
                    ancestorTrail: [contentTitle],
                  ),
                ),
              ),
              onEdit:   () => onEditUnit(unitId, data),
              onDelete: () => onDeleteUnit(unitId, title),
            );
          },
        );
      },
    );
  }
}

// ── Summative Quiz tab ──────────────────────────────────────────────────

class _UnitQuizTab extends StatelessWidget {
  const _UnitQuizTab({
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
        final units = snap.data?.docs ?? [];

        if (units.isEmpty) {
          return HierarchyEmptyState(
            icon:        Icons.emoji_events_outlined,
            title:       'teacher.teacher_unit_editor_screen.noUnitsYet'.tr(),
            subtitle:    'teacher.teacher_unit_editor_screen.tapToCreateFirstUnit'.tr(),
            color:       color,
            actionLabel: 'teacher.teacher_unit_editor_screen.createFirstUnit'.tr(),
            onAction: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CreatePersonalizedUnitScreen(
                  groupId:   groupId,
                  contentId: contentId,
                  groupColor: color,
                ),
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          itemCount: units.length,
          itemBuilder: (context, i) {
            final doc   = units[i];
            final data  = doc.data() as Map<String, dynamic>;
            final title = data['title'] as String? ?? 'common.untitled'.tr();
            final unitId = doc.id;

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
                  SummativeQuizSlot(
                    contentId: contentId,
                    unitId: unitId,
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
