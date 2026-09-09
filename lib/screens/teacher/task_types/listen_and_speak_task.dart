import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/teacher/task_types/task_type_editor.dart';
import 'package:loringo_app/theme/app_theme.dart';

class ListenAndSpeakTask extends StatefulWidget {
  final Color groupColor;
  final Map<String, dynamic>? existingData;
  final TaskEditorController controller;
  final VoidCallback onChanged;

  const ListenAndSpeakTask({
    super.key,
    required this.groupColor,
    this.existingData,
    required this.controller,
    required this.onChanged,
  });

  @override
  State<ListenAndSpeakTask> createState() => _ListenAndSpeakTaskState();
}

class _ListenAndSpeakTaskState extends State<ListenAndSpeakTask> with TaskTypeEditorMixin implements TaskTypeEditor {
  late TextEditingController phraseController;
  late TextEditingController hintController;
  
  @override
  void initState() {
    super.initState();
    phraseController = TextEditingController();
    hintController = TextEditingController();
    
    if (widget.existingData != null) {
      loadData(widget.existingData!);
    }
    
    widget.controller.registerEditor(this);
  }

  @override
  String get typeId => 'listen_and_speak';
  
  @override
  String get displayName => 'teacher.listen_and_speak_task.displayName'.tr();
  
  @override
  Widget buildEditor(BuildContext context) {
    return build(context);
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return _buildEditor();
  }

  @override
  void loadData(Map<String, dynamic> data) {
    phraseController.text = data['phrase'] ?? '';
    hintController.text = data['hint'] ?? '';
  }

  @override
  Map<String, dynamic> collectData() {
    return {
      'phrase': phraseController.text.trim(),
      'hint': hintController.text.trim(),
      'hide_text_from_student': true,
    };
  }

  @override
  String? validate() {
    if (phraseController.text.trim().isEmpty) {
      return 'teacher.listen_and_speak_task.phraseRequiredError'.tr();
    }
    return null;
  }

  @override
  void dispose() {
    phraseController.dispose();
    hintController.dispose();
    super.dispose();
  }

  Widget _buildEditor() {
    final c = widget.groupColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoBanner(c),
        const SizedBox(height: AppSpacing.md),
        _buildPhraseField(c),
        const SizedBox(height: AppSpacing.md),
        _buildHintField(c),
      ],
    );
  }

  Widget _buildInfoBanner(Color c) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: c.withOpacity(0.07),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: c.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.hearing_rounded, color: c, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'teacher.listen_and_speak_task.infoBanner'.tr(),
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhraseField(Color c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'teacher.listen_and_speak_task.phraseLabel'.tr(),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'teacher.listen_and_speak_task.requiredBadge'.tr(),
                style: const TextStyle(fontSize: 10, color: Colors.red),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        TextFormField(
          controller: phraseController,
          decoration: InputDecoration(
            hintText: 'teacher.listen_and_speak_task.phraseHint'.tr(),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            filled: true,
            fillColor: Colors.white,
          ),
          maxLines: 3,
          onChanged: (_) => widget.onChanged(),
          validator: (v) => v?.trim().isEmpty ?? true ? 'teacher.listen_and_speak_task.requiredError'.tr() : null,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.visibility_off, size: 14, color: Colors.grey.shade600),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                'teacher.listen_and_speak_task.phraseHiddenNote'.tr(),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHintField(Color c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'teacher.listen_and_speak_task.hintLabel'.tr(),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextFormField(
          controller: hintController,
          decoration: InputDecoration(
            hintText: 'teacher.listen_and_speak_task.hintFieldHint'.tr(),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            filled: true,
            fillColor: Colors.white,
          ),
          maxLines: 2,
          onChanged: (_) => widget.onChanged(),
        ),
        const SizedBox(height: 8),
        Text(
          'teacher.listen_and_speak_task.hintHelperText'.tr(),
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}