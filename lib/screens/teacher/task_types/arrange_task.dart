import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/teacher/task_types/task_type_editor.dart';
import 'package:loringo_app/theme/app_theme.dart';
// import 'task_type_interface.dart';

class ArrangeTask extends StatefulWidget {
  final Color groupColor;
  final Map<String, dynamic>? existingData;
  final TaskEditorController controller;
  final VoidCallback onChanged;

  const ArrangeTask({
    super.key,
    required this.groupColor,
    this.existingData,
    required this.controller,
    required this.onChanged,
  });

  @override
  State<ArrangeTask> createState() => _ArrangeTaskState();
}

class _ArrangeTaskState extends State<ArrangeTask> with TaskTypeEditorMixin implements TaskTypeEditor {
  late TextEditingController sentenceController;

  @override
  void initState() {
    super.initState();
    sentenceController = TextEditingController();
    if (widget.existingData != null) {
      loadData(widget.existingData!);
    }

    widget.controller.registerEditor(this);
  }

  // TaskTypeEditor implementation
  @override
  String get typeId => 'arrange';
  
  @override
  String get displayName => 'teacher.arrange_task.displayName'.tr();

  @override
  String get defaultQuestion => 'teacher.arrange_task.defaultQuestion'.tr();

  @override
  void loadData(Map<String, dynamic> data) {
    final answer = data['answer'] as List<dynamic>?;
    if (answer != null) {
      sentenceController.text = answer.join(' ');
    }
  }

  @override
  Map<String, dynamic> collectData() {
    return {
      'answer': _getWords(),
    };
  }

  List<String> _getWords() {
    return sentenceController.text.trim().split(' ').where((w) => w.isNotEmpty).toList();
  }

  @override
  String? validate() {
    final words = _getWords();
    if (words.length < 3) return 'teacher.arrange_task.minWordsError'.tr();
    return null;
  }

  @override
  void dispose() {
    sentenceController.dispose();
    super.dispose();
  }

  @override
  Widget buildEditor(BuildContext context) {
    return build(context);
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return _buildEditor();
  }

  Widget _buildEditor() {
    final c = widget.groupColor;
    final words = _getWords();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: c.withOpacity(0.07),
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Row(
            children: [
              Icon(Icons.title_outlined, color: c, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'teacher.arrange_task.infoBanner'.tr(),
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.text_fields, size: 18, color: c),
                  const SizedBox(width: AppSpacing.sm),
                  Text('teacher.arrange_task.sentenceLabel'.tr(), style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: sentenceController,
                decoration: InputDecoration(
                  hintText: 'teacher.arrange_task.sentenceHint'.tr(),
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                maxLines: 2,
                onChanged: (_) => widget.onChanged(),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'teacher.arrange_task.requiredError'.tr();
                  if (v.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length < 3) {
                    return 'teacher.arrange_task.atLeastThreeWordsError'.tr();
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        if (words.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text('teacher.arrange_task.tilePreviewLabel'.tr(), style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: words.map((word) => Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: c, width: 2),
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              child: Text(word, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            )).toList(),
          ),
        ],
      ],
    );
  }
}