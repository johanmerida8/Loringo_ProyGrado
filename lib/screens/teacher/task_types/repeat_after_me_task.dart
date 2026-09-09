import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/teacher/task_types/task_type_editor.dart';
import 'package:loringo_app/theme/app_theme.dart';

class RepeatAfterMeTask extends StatefulWidget {
  final Color groupColor;
  final Map<String, dynamic>? existingData;
  final TaskEditorController controller;
  final VoidCallback onChanged;

  const RepeatAfterMeTask({
    super.key,
    required this.groupColor,
    this.existingData,
    required this.controller,
    required this.onChanged,
  });

  @override
  State<RepeatAfterMeTask> createState() => _RepeatAfterMeTaskState();
}

class _RepeatAfterMeTaskState extends State<RepeatAfterMeTask> with TaskTypeEditorMixin implements TaskTypeEditor {
  late TextEditingController phraseController;

  // CHANGE: replaces the old free-text hint field. The reveal/hidden
  // mechanic on screen_nine.dart made a free-text hint risky — a
  // teacher writing something like "it means stand up" defeats the
  // purpose of hiding the phrase, and there's no way to validate that
  // server-side. A boolean toggle is the safer surface: it's the
  // teacher explicitly deciding the exercise's difficulty mode, not
  // wording that can accidentally leak the answer.
  //
  // Default false (phrase hidden) matches the pedagogical intent: the
  // student listens and recalls, rather than reading along. Teachers
  // creating easier tasks (e.g. very young students, first lessons)
  // can flip this on per-task.
  bool showPhrase = false;

  @override
  void initState() {
    super.initState();
    phraseController = TextEditingController();

    if (widget.existingData != null) {
      loadData(widget.existingData!);
    }

    widget.controller.registerEditor(this);
  }

  // TaskTypeEditor implementation
  @override
  String get typeId => 'repeat_after_me';

  @override
  String get displayName => 'teacher.repeat_after_me_task.displayName'.tr();

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
    // Backward compatible with existing tasks created before this
    // toggle existed: absent field defaults to false (hidden), which
    // is the new default behavior going forward anyway, so old tasks
    // adopt the new reveal-based UX automatically rather than needing
    // a data migration.
    showPhrase = data['showPhrase'] as bool? ?? false;
  }

  @override
  Map<String, dynamic> collectData() {
    return {
      'phrase': phraseController.text.trim(),
      'showPhrase': showPhrase,
    };
  }

  @override
  String? validate() {
    if (phraseController.text.trim().isEmpty) {
      return 'teacher.repeat_after_me_task.phraseRequiredError'.tr();
    }
    return null;
  }

  @override
  void dispose() {
    phraseController.dispose();
    super.dispose();
  }

  Widget _buildEditor() {
    final c = widget.groupColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Info Banner ────────────────────────────────────────────────
        _buildInfoBanner(c),
        const SizedBox(height: AppSpacing.md),

        // ── Phrase Field ──────────────────────────────────────────────
        _buildPhraseField(c),
        const SizedBox(height: AppSpacing.md),

        // ── Show Phrase Toggle ───────────────────────────────────────
        _buildShowPhraseToggle(c),
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
          Icon(Icons.record_voice_over, color: c, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'teacher.repeat_after_me_task.infoBanner'.tr(),
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
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
        Text(
          'teacher.repeat_after_me_task.phraseLabel'.tr(),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextFormField(
          controller: phraseController,
          decoration: InputDecoration(
            hintText: 'teacher.repeat_after_me_task.phraseHint'.tr(),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            filled: true,
            fillColor: Colors.white,
          ),
          maxLines: 3,
          onChanged: (_) => widget.onChanged(),
          validator: (v) => v?.trim().isEmpty ?? true ? 'teacher.repeat_after_me_task.requiredError'.tr() : null,
        ),
        const SizedBox(height: 8),
        Text(
          'teacher.repeat_after_me_task.phraseHelperText'.tr(),
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildShowPhraseToggle(Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'teacher.repeat_after_me_task.showPhraseLabel'.tr(),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  showPhrase
                      ? 'teacher.repeat_after_me_task.showPhraseOnDescription'.tr()
                      : 'teacher.repeat_after_me_task.showPhraseOffDescription'.tr(),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Switch(
            value: showPhrase,
            activeColor: c,
            onChanged: (v) {
              setState(() => showPhrase = v);
              widget.onChanged();
            },
          ),
        ],
      ),
    );
  }
}