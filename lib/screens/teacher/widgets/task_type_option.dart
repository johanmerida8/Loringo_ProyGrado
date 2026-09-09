// lib/screens/teacher/widgets/task_type_option.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/theme/app_theme.dart';

class TaskTypeOption {
  const TaskTypeOption(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;
}

/// Hard ceiling on how many tasks a single Activity may ever contain in
/// total, across every batch (Generate or Add Task) plus any tasks added
/// individually via Edit over time. Shared by teacher_task_editor_screen.dart
/// (the running-total gate) and task_batch_review_screen.dart (computing
/// how much room is left when a teacher chains multiple "Add more tasks"
/// batches back to back).
const int kMaxTasksPerActivity = 15;

// NOTE: 'compare' and 'flashcard' added to Vocabulary — new task types.
// 'compare' has the student pick which of two images answers a
// comparative question (e.g. "Which is bigger?"). 'flashcard' is a
// sequence of 3-8 image cards, each flipped and answered with a
// multiple-choice word pick — see compare_task.dart and
// flashcard_task.dart for the editors and rationale.
//
// 'slow_reveal' REMOVED — discontinued entirely, including its student
// screen (former screen_thirteen.dart content, now replaced by 'compare').
const Map<String, List<TaskTypeOption>> kTaskTypeGroups = {
  'Vocabulary': [
    TaskTypeOption('image_select', 'Image Select', Icons.image_outlined),
    TaskTypeOption('image_select_reverse', 'Image Select Reverse', Icons.image_search),
    TaskTypeOption('match', 'Match', Icons.compare_arrows),
    TaskTypeOption('sound_match', 'Sound Match', Icons.volume_up),
    TaskTypeOption('odd_one_out', 'Odd One Out', Icons.category_outlined),
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

/// Which kTaskTypeGroups skill category a task type belongs to (e.g.
/// 'match' -> 'Vocabulary'). Used by parent_home_screen.dart's Skill
/// Insights section to aggregate at the category level -- a parent
/// doesn't author tasks, so "Image Select" means nothing to them, but
/// "Vocabulary" does.
String taskCategoryFor(String id) {
  for (final entry in kTaskTypeGroups.entries) {
    if (entry.value.any((option) => option.id == id)) return entry.key;
  }
  return 'Other';
}

// ── Display-label lookups ─────────────────────────────────────────────────
// kTaskTypeGroups above stays untranslated on purpose: its String keys and
// TaskTypeOption.id/.label values are consumed as identifiers elsewhere
// (e.g. taskCategoryFor's return value drives parent_home_screen.dart's
// Skill Insights aggregation), so changing them here would ripple into
// files outside this widget's scope. These maps translate ONLY what this
// file actually renders on screen, keyed off the same stable ids/names.
const Map<String, String> _kTaskTypeLabelKeys = {
  'image_select': 'taskImageSelect',
  'image_select_reverse': 'taskImageSelectReverse',
  'match': 'taskMatch',
  'sound_match': 'taskSoundMatch',
  'odd_one_out': 'taskOddOneOut',
  'fill_blank': 'taskFillBlank',
  'arrange': 'taskArrange',
  'sentence_builder': 'taskSentenceBuilder',
  'reading': 'taskReading',
  'repeat_after_me': 'taskRepeatAfterMe',
  'listen_and_speak': 'taskListenAndSpeak',
  'complete_the_chat': 'taskCompleteTheChat',
};

const Map<String, String> _kTaskGroupLabelKeys = {
  'Vocabulary': 'groupVocabulary',
  'Grammar': 'groupGrammar',
  'Reading': 'groupReading',
  'Speaking & Listening': 'groupSpeakingListening',
  'Conversation': 'groupConversation',
};

String taskTypeLabel(TaskTypeOption option) =>
    'teacher.task_type_option.${_kTaskTypeLabelKeys[option.id] ?? option.id}'
        .tr();

String taskGroupLabel(String groupName) =>
    'teacher.task_type_option.${_kTaskGroupLabelKeys[groupName] ?? groupName}'
        .tr();

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
    context.watch<LocaleProvider>();
    final selected = taskTypeOptionFor(selectedId);
    return InkWell(
      borderRadius: AppRadii.mdAll,
      onTap: () => _openPicker(context),
      child: InputDecorator(
        decoration: AppInput.decoration(accent: color, icon: selected.icon),
        child: Row(children: [
          Icon(selected.icon, color: color, size: 0), // keeps baseline height consistent
          Expanded(
            child: Text(taskTypeLabel(selected), style: AppText.body.copyWith(fontWeight: FontWeight.w600)),
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
    context.watch<LocaleProvider>();
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
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
              child: Row(children: [Text('teacher.task_type_option.chooseTaskType'.tr(), style: AppText.cardTitle)]),
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
          child: Text(taskGroupLabel(groupName).toUpperCase(),
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
              title: Text(taskTypeLabel(option), style: TextStyle(
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