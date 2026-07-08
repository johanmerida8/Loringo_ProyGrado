// lib/screens/teacher/widgets/task_type_picker.dart
import 'package:flutter/material.dart';
import 'package:loringo_app/theme/app_theme.dart';

class TaskTypeOption {
  const TaskTypeOption(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;
}

const Map<String, List<TaskTypeOption>> kTaskTypeGroups = {
  'Vocabulary': [
    TaskTypeOption('image_select', 'Image Select', Icons.image_outlined),
    TaskTypeOption('image_select_reverse', 'Image Select Reverse', Icons.image_search),
    TaskTypeOption('match', 'Match', Icons.compare_arrows),
  ],
  'Grammar': [
    TaskTypeOption('fill_blank', 'Fill in the Blank', Icons.edit_note),
    TaskTypeOption('arrange', 'Sentence Arrange', Icons.sort),
    TaskTypeOption('sentence_builder', 'Sentence Builder', Icons.translate),
  ],
  'Reading': [
    TaskTypeOption('reading', 'Reading Comprehension', Icons.menu_book),
  ],
  'Speaking & Listening': [
    TaskTypeOption('repeat_after_me', 'Repeat After Me', Icons.record_voice_over),
    TaskTypeOption('listen_and_speak', 'Listen & Speak', Icons.hearing),
  ],
  'Conversation': [
    TaskTypeOption('complete_the_chat', 'Complete the Chat', Icons.chat_bubble_outline),
  ],
};

TaskTypeOption taskTypeOptionFor(String id) {
  for (final group in kTaskTypeGroups.values) {
    for (final option in group) {
      if (option.id == id) return option;
    }
  }
  return TaskTypeOption(id, id, Icons.help_outline);
}

/// Tappable field that opens a grouped bottom sheet for choosing a task type,
/// instead of a single flat 10-item dropdown.
class TaskTypePickerField extends StatelessWidget {
  const TaskTypePickerField({
    super.key,
    required this.selectedId,
    required this.color,
    required this.onSelected,
  });

  final String selectedId;
  final Color color;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = taskTypeOptionFor(selectedId);
    return InkWell(
      borderRadius: AppRadii.mdAll,
      onTap: () => _openPicker(context),
      child: InputDecorator(
        decoration: AppInput.decoration(accent: color, icon: selected.icon),
        child: Row(children: [
          Icon(selected.icon, color: color, size: 0), // keeps baseline height consistent
          Expanded(
            child: Text(selected.label, style: AppText.body.copyWith(fontWeight: FontWeight.w600)),
          ),
          const Icon(Icons.unfold_more, color: AppColors.muted, size: 20),
        ]),
      ),
    );
  }

  void _openPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TaskTypeSheet(selectedId: selectedId, color: color, onSelected: onSelected),
    );
  }
}

class _TaskTypeSheet extends StatelessWidget {
  const _TaskTypeSheet({required this.selectedId, required this.color, required this.onSelected});
  final String selectedId;
  final Color color;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
          ),
          child: Column(children: [
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
              child: Row(children: [Text('Choose a Task Type', style: AppText.cardTitle)]),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                children: kTaskTypeGroups.entries
                    .map((entry) => _buildGroup(context, entry.key, entry.value))
                    .toList(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ]),
        );
      },
    );
  }

  Widget _buildGroup(BuildContext context, String groupName, List<TaskTypeOption> options) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
          child: Text(groupName.toUpperCase(),
              style: AppText.fieldLabel.copyWith(color: AppColors.textSecondary)),
        ),
        ...options.map((option) {
          final isSelected = option.id == selectedId;
          return Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            decoration: BoxDecoration(
              color: isSelected ? color.withOpacity(0.08) : AppColors.surface,
              borderRadius: AppRadii.mdAll,
              border: Border.all(color: isSelected ? color : AppColors.divider, width: isSelected ? 2 : 1),
            ),
            child: ListTile(
              shape: RoundedRectangleBorder(borderRadius: AppRadii.mdAll),
              leading: Icon(option.icon, color: isSelected ? color : AppColors.muted),
              title: Text(option.label, style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isSelected ? color : AppColors.textPrimary,
              )),
              trailing: isSelected ? Icon(Icons.check_circle, color: color) : null,
              onTap: () {
                onSelected(option.id);
                Navigator.pop(context);
              },
            ),
          );
        }),
      ],
    );
  }
}