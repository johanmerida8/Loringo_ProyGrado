// teacher_unit_editor_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
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
                            unitId:        doc.id,
                            unitTitle:     title,
                            groupColor:    _c,
                            ancestorTrail: [widget.contentTitle],
                          ),
                        ),
                      ),
                      onEdit:   () => _editUnit(doc.id, data),
                      onDelete: () => _deleteUnit(doc.id, title),
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