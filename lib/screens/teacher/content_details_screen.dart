// content_details_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/create_unit_screen.dart';
import 'package:loringo_app/screens/teacher/lesson_list_screen.dart';
import 'package:loringo_app/screens/teacher/widgets/hierarchy_list_cards.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

class PersonalizedContentDetailsScreen extends StatefulWidget {
  final String groupId;
  final String contentId;
  final String contentTitle;
  final Color  groupColor;

  const PersonalizedContentDetailsScreen({
    super.key,
    required this.groupId,
    required this.contentId,
    required this.contentTitle,
    required this.groupColor,
  });

  @override
  State<PersonalizedContentDetailsScreen> createState() =>
      _PersonalizedContentDetailsScreenState();
}

class _PersonalizedContentDetailsScreenState
    extends State<PersonalizedContentDetailsScreen> {
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
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: _c,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.onPrimary),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.contentTitle,
                style: const TextStyle(
                    color: AppColors.onPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 17)),
            const Text('Units',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
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
            padding: const EdgeInsets.all(AppSpacing.md),
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
                    builder: (_) => PersonalizedLessonListScreen(
                      groupId:    widget.groupId,
                      contentId:  widget.contentId,
                      unitId:     doc.id,
                      unitTitle:  title,
                      groupColor: _c,
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