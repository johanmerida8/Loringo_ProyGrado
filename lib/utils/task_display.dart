// task_display.dart
//
// Shared task-row display helpers (title resolution, type label/icon),
// extracted from teacher_task_editor_screen.dart so the same logic can be
// reused by teacher_content_structure_screen.dart without duplicating it.
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

// 'title' is a mandatory top-level field on every task, entered by the
// teacher when creating/editing (see create_task_screen.dart). Legacy
// fallback: tasks created before 'title' existed won't have it, so fall
// back to the old per-type guessing logic so they don't show blank.
String taskDisplayTitle(Map<String, dynamic> data) {
  final title = data['title'] as String?;
  if (title != null && title.trim().isNotEmpty) return title;

  final type = data['type'] as String? ?? '';
  if (type == 'reading') {
    final inner = data['data'] as Map<String, dynamic>?;
    final innerTitle = inner?['title'] as String?;
    if (innerTitle != null && innerTitle.trim().isNotEmpty) return innerTitle;
  }
  final legacyQuestion = data['question'] as String?;
  if (legacyQuestion != null && legacyQuestion.trim().isNotEmpty) {
    return legacyQuestion;
  }
  return 'teacher.teacher_task_editor_screen.untitledOpenToAddTitle'.tr();
}

String taskTypeDisplayLabel(String type) {
  final map = {
    'image_select': 'teacher.teacher_task_editor_screen.typeImageSelect'.tr(),
    'image_select_reverse':
        'teacher.teacher_task_editor_screen.typeImageSelectReverse'.tr(),
    'fill_blank': 'teacher.teacher_task_editor_screen.typeFillBlank'.tr(),
    'arrange': 'teacher.teacher_task_editor_screen.typeArrange'.tr(),
    'complete_the_chat':
        'teacher.teacher_task_editor_screen.typeCompleteTheChat'.tr(),
    'word_match': 'teacher.teacher_task_editor_screen.typeWordMatch'.tr(),
    'match': 'teacher.teacher_task_editor_screen.typeMatch'.tr(),
    'reading': 'teacher.teacher_task_editor_screen.typeReading'.tr(),
    'sentence_builder':
        'teacher.teacher_task_editor_screen.typeSentenceBuilder'.tr(),
    'repeat_after_me':
        'teacher.teacher_task_editor_screen.typeRepeatAfterMe'.tr(),
    'listen_and_speak':
        'teacher.teacher_task_editor_screen.typeListenAndSpeak'.tr(),
    'sound_match': 'teacher.teacher_task_editor_screen.typeSoundMatch'.tr(),
    'odd_one_out': 'teacher.teacher_task_editor_screen.typeOddOneOut'.tr(),
  };
  return map[type] ?? type;
}

IconData taskTypeIcon(String type) {
  const map = {
    'image_select': Icons.image,
    'image_select_reverse': Icons.image_search,
    'fill_blank': Icons.edit_note,
    'arrange': Icons.sort,
    'complete_the_chat': Icons.chat,
    'word_match': Icons.shuffle,
    'match': Icons.compare_arrows,
    'reading': Icons.menu_book,
    'sentence_builder': Icons.translate,
    'repeat_after_me': Icons.record_voice_over,
    'listen_and_speak': Icons.hearing,
    'sound_match': Icons.volume_up,
    'odd_one_out': Icons.category_outlined,
  };
  return map[type] ?? Icons.help_outline;
}
