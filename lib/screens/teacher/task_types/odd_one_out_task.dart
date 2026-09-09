import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/components/image_dialog.dart';
import 'package:loringo_app/screens/teacher/task_types/task_type_editor.dart';
import 'package:loringo_app/theme/app_theme.dart';

/// ODD ONE OUT
/// Exactly 4 image+label options. Three belong to the same category, one
/// doesn't — the student taps the one that doesn't belong. Fixed at 4
/// options (no add/remove) since the exercise loses its shape with more
/// or fewer than that.
class OddOneOutTask extends StatefulWidget {
  final Color groupColor;
  final Map<String, dynamic>? existingData;
  final TaskEditorController controller;
  final VoidCallback onChanged;

  const OddOneOutTask({
    super.key,
    required this.groupColor,
    this.existingData,
    required this.controller,
    required this.onChanged,
  });

  @override
  State<OddOneOutTask> createState() => _OddOneOutTaskState();
}

class _OddOneOutTaskState extends State<OddOneOutTask>
    with TaskTypeEditorMixin
    implements TaskTypeEditor {
  static const int _optionCount = 4;

  late TextEditingController categoryController;
  late List<TextEditingController> labelControllers;
  late List<TextEditingController> imageControllers;
  late List<Map<String, dynamic>?> pickedImages;
  int oddIndex = -1;

  @override
  void initState() {
    super.initState();
    categoryController = TextEditingController();
    labelControllers = List.generate(_optionCount, (_) => TextEditingController());
    imageControllers = List.generate(_optionCount, (_) => TextEditingController());
    pickedImages = List.generate(_optionCount, (_) => null);
    if (widget.existingData != null) {
      loadData(widget.existingData!);
    }
    widget.controller.registerEditor(this);
  }

  @override
  String get typeId => 'odd_one_out';

  @override
  String get displayName => 'teacher.odd_one_out_task.displayName'.tr();

  @override
  void loadData(Map<String, dynamic> data) {
    categoryController.text = data['category'] as String? ?? '';
    final opts = data['options'] as List<dynamic>? ?? [];
    for (int i = 0; i < opts.length && i < _optionCount; i++) {
      final opt = opts[i] as Map<String, dynamic>;
      labelControllers[i].text = opt['label'] ?? '';
      imageControllers[i].text = opt['image'] ?? '';
    }
    oddIndex = data['oddIndex'] as int? ?? -1;
  }

  @override
  Map<String, dynamic> collectData() {
    return {
      'category': categoryController.text.trim(),
      'options': List.generate(_optionCount, (i) => {
        'label': labelControllers[i].text.trim(),
        'image': pickedImages[i] != null
            ? (pickedImages[i]!['imageUrl'] as String? ?? '')
            : imageControllers[i].text.trim(),
      }),
      'oddIndex': oddIndex,
    };
  }

  @override
  String? validate() {
    if (categoryController.text.trim().isEmpty) {
      return 'teacher.odd_one_out_task.categoryRequiredError'.tr();
    }
    for (int i = 0; i < _optionCount; i++) {
      final hasImage = pickedImages[i] != null || imageControllers[i].text.trim().isNotEmpty;
      if (labelControllers[i].text.trim().isEmpty || !hasImage) {
        return 'teacher.odd_one_out_task.optionMissingLabelOrImage'.tr(namedArgs: {'number': '${i + 1}'});
      }
    }
    if (oddIndex < 0 || oddIndex >= _optionCount) {
      return 'teacher.odd_one_out_task.markOddOneOutError'.tr();
    }
    return null;
  }

  void _setOdd(int index) {
    setState(() {
      oddIndex = index;
      widget.onChanged();
    });
  }

  @override
  void dispose() {
    categoryController.dispose();
    for (final c in labelControllers) c.dispose();
    for (final c in imageControllers) c.dispose();
    super.dispose();
  }

  @override
  Widget buildEditor(BuildContext context) => build(context);

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    final c = widget.groupColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(c),
        const SizedBox(height: AppSpacing.md),
        Text('teacher.odd_one_out_task.categoryLabel'.tr(),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: AppSpacing.xs),
        TextFormField(
          controller: categoryController,
          decoration: _inputDecoration(c, 'teacher.odd_one_out_task.categoryHint'.tr()),
          onChanged: (_) => widget.onChanged(),
          validator: (v) => v?.trim().isEmpty ?? true ? 'teacher.odd_one_out_task.requiredError'.tr() : null,
        ),
        const SizedBox(height: AppSpacing.md),
        Text('teacher.odd_one_out_task.optionsSectionLabel'.tr(),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: AppSpacing.sm),
        ...List.generate(_optionCount, (index) => _buildOptionCard(index, c)),
      ],
    );
  }

  Widget _buildHeader(Color c) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: c.withOpacity(0.07),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        children: [
          Icon(Icons.category_outlined, color: c, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'teacher.odd_one_out_task.infoBanner'.tr(),
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionCard(int index, Color c) {
    final isOdd = oddIndex == index;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(
          color: isOdd ? AppColors.danger : AppColors.divider,
          width: isOdd ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(AppRadii.md),
        color: isOdd ? AppColors.danger.withOpacity(0.04) : Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('teacher.odd_one_out_task.optionLabel'.tr(namedArgs: {'number': '${index + 1}'}), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const Spacer(),
              GestureDetector(
                onTap: () => _setOdd(index),
                child: Row(
                  children: [
                    Icon(
                      isOdd ? Icons.cancel : Icons.radio_button_unchecked,
                      color: isOdd ? AppColors.danger : Colors.grey[400],
                      size: 20,
                    ),
                    const SizedBox(width: 4),
                    Text('teacher.odd_one_out_task.oddOneOutLabel'.tr(), style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: labelControllers[index],
            decoration: _inputDecoration(c, 'teacher.odd_one_out_task.labelHint'.tr()),
            onChanged: (_) => widget.onChanged(),
            validator: (v) => v?.isEmpty ?? true ? 'teacher.odd_one_out_task.requiredError'.tr() : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildImagePicker(index, c),
        ],
      ),
    );
  }

  Widget _buildImagePicker(int index, Color c) {
    final hasImage = pickedImages[index] != null || imageControllers[index].text.trim().isNotEmpty;
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 100,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(AppRadii.sm),
              border: Border.all(color: AppColors.divider),
            ),
            child: hasImage
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    child: Image.network(
                      pickedImages[index] != null
                          ? (pickedImages[index]!['displayUrl'] ?? pickedImages[index]!['imageUrl'])
                          : imageControllers[index].text.trim(),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 40),
                    ),
                  )
                : Center(child: Text('teacher.odd_one_out_task.noImagePlaceholder'.tr(), style: TextStyle(color: Colors.grey[500]))),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        ElevatedButton.icon(
          onPressed: () async {
            final selected = await showDialog(
              context: context,
              builder: (_) => const SelectImageDialog(singleSelect: true),
            );
            if (selected != null) {
              setState(() {
                pickedImages[index] = selected as Map<String, dynamic>;
                imageControllers[index].text = selected['name'] ?? 'Selected';
                widget.onChanged();
              });
            }
          },
          icon: const Icon(Icons.image, size: 18),
          label: Text('teacher.odd_one_out_task.selectButton'.tr()),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey[200],
            foregroundColor: Colors.black87,
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(Color c, String hint) {
    return InputDecoration(
      hintText: hint,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: BorderSide(color: c.withOpacity(0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: BorderSide(color: c, width: 2),
      ),
      filled: true,
      fillColor: Colors.white,
    );
  }
}