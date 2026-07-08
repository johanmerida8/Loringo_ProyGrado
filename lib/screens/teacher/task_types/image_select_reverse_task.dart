import 'package:flutter/material.dart';
import 'package:loringo_app/components/image_dialog.dart';
import 'package:loringo_app/screens/teacher/task_types/task_type_editor.dart';
import 'package:loringo_app/theme/app_theme.dart';
// import 'task_type_interface.dart';

class ImageSelectReverseTask extends StatefulWidget {
  final Color groupColor;
  final Map<String, dynamic>? existingData;
  final TaskEditorController controller;
  final VoidCallback onChanged;

  const ImageSelectReverseTask({
    super.key,
    required this.groupColor,
    this.existingData,
    required this.controller,
    required this.onChanged,
  });

  @override
  State<ImageSelectReverseTask> createState() => _ImageSelectReverseTaskState();
}

class _ImageSelectReverseTaskState extends State<ImageSelectReverseTask> with TaskTypeEditorMixin implements TaskTypeEditor {
  Map<String, dynamic>? pickedImage;
  late TextEditingController imageUrlController;
  late List<Map<String, dynamic>> options;
  late List<TextEditingController> optionControllers;

  @override
  void initState() {
    super.initState();
    imageUrlController = TextEditingController();
    options = List.generate(3, (_) => {'text': '', 'isCorrect': false});
    optionControllers = List.generate(3, (_) => TextEditingController());
    if (widget.existingData != null) {
      loadData(widget.existingData!);
    }

    widget.controller.registerEditor(this);
  }

  // TaskTypeEditor implementation
  @override
  String get typeId => 'image_select_reverse';
  
  @override
  String get displayName => 'Image Select Reverse';
  
  @override
  String get defaultQuestion => 'Select the correct phrase';

  @override
  void loadData(Map<String, dynamic> data) {
    imageUrlController.text = data['image'] ?? '';
    final opts = data['options'] as List<dynamic>? ?? [];
    for (int i = 0; i < opts.length && i < options.length; i++) {
      final opt = opts[i] as Map<String, dynamic>;
      options[i] = {
        'text': opt['text'] ?? '',
        'isCorrect': opt['isCorrect'] ?? false,
      };
      optionControllers[i].text = opt['text'] ?? '';
    }
  }

  @override
  Map<String, dynamic> collectData() {
    return {
      'image': pickedImage != null
          ? (pickedImage!['imageUrl'] as String? ?? '')
          : imageUrlController.text.trim(),
      'options': List.generate(options.length, (i) => {
        'text': optionControllers[i].text.trim(),
        'isCorrect': options[i]['isCorrect'] ?? false,
      }),
    };
  }

  @override
  String? validate() {
    final hasImage = pickedImage != null || imageUrlController.text.trim().isNotEmpty;
    if (!hasImage) return 'Image is required';
    
    bool hasCorrect = false;
    int filled = 0;
    for (int i = 0; i < options.length; i++) {
      if (optionControllers[i].text.trim().isNotEmpty) filled++;
      if (options[i]['isCorrect'] == true) hasCorrect = true;
    }
    if (filled < 3) return 'Provide at least 3 options';
    if (!hasCorrect) return 'Mark at least one option as correct';
    return null;
  }

  void _addOption() {
    if (options.length < 4) {
      setState(() {
        options.add({'text': '', 'isCorrect': false});
        optionControllers.add(TextEditingController());
        widget.onChanged();
      });
    }
  }

  void _removeOption(int index) {
    if (options.length > 3) {
      setState(() {
        options.removeAt(index);
        optionControllers[index].dispose();
        optionControllers.removeAt(index);
        widget.onChanged();
      });
    }
  }

  @override
  void dispose() {
    imageUrlController.dispose();
    for (var c in optionControllers) c.dispose();
    super.dispose();
  }

  @override
  Widget buildEditor(BuildContext context) {
    return build(context);
  }

  @override
  Widget build(BuildContext context) {
    return _buildEditor();
  }

  Widget _buildEditor() {
    final c = widget.groupColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildImageSection(c),
        const SizedBox(height: AppSpacing.md),
        _buildOptionsHeader(c),
        const SizedBox(height: AppSpacing.md),
        ...List.generate(options.length, (i) => _buildOptionCard(i, c)),
        if (options.length < 4)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: TextButton.icon(
              onPressed: _addOption,
              icon: Icon(Icons.add_circle_outline, color: c),
              label: Text('Add option (${options.length}/4)', style: TextStyle(color: c)),
            ),
          ),
      ],
    );
  }

  Widget _buildImageSection(Color c) {
    final hasImage = pickedImage != null || imageUrlController.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Image', style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: Border.all(color: AppColors.divider),
                ),
                child: hasImage
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadii.md),
                        child: Image.network(
                          pickedImage != null
                              ? (pickedImage!['displayUrl'] ?? pickedImage!['imageUrl'])
                              : imageUrlController.text.trim(),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 40),
                        ),
                      )
                    : Center(child: Text('No image', style: TextStyle(color: Colors.grey[500]))),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            ElevatedButton.icon(
              onPressed: () async {
                final selected = await showDialog(
                  context: context,
                  builder: (_) => const SelectImageDialog(singleSelect: true),
                );
                if (selected != null) {
                  setState(() {
                    pickedImage = selected as Map<String, dynamic>;
                    imageUrlController.text = selected['name'] ?? 'Selected';
                    widget.onChanged();
                  });
                }
              },
              icon: const Icon(Icons.image, size: 20),
              label: const Text('Select Image'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[200],
                foregroundColor: Colors.black87,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOptionsHeader(Color c) {
    return Row(
      children: [
        Text('Text Options (3–4)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const Spacer(),
      ],
    );
  }

  Widget _buildOptionCard(int index, Color c) {
    final isCorrect = options[index]['isCorrect'] as bool;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: isCorrect ? c : AppColors.divider, width: isCorrect ? 2 : 1),
        borderRadius: BorderRadius.circular(AppRadii.md),
        color: isCorrect ? c.withOpacity(0.04) : Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Option ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const Spacer(),
              Row(
                children: [
                  Checkbox(
                    value: isCorrect,
                    activeColor: c,
                    onChanged: (v) => setState(() {
                      options[index]['isCorrect'] = v ?? false;
                      widget.onChanged();
                    }),
                  ),
                  const Text('Correct', style: TextStyle(fontSize: 13)),
                ],
              ),
              if (options.length > 3)
                IconButton(
                  icon: Icon(Icons.remove_circle_outline, color: AppColors.danger),
                  onPressed: () => _removeOption(index),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: optionControllers[index],
            decoration: _inputDecoration(c, 'e.g. "Stand up"'),
            onChanged: (_) => widget.onChanged(),
            validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
          ),
        ],
      ),
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