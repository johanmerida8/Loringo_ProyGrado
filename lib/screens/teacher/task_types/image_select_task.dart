import 'package:flutter/material.dart';
import 'package:loringo_app/components/image_dialog.dart';
import 'package:loringo_app/screens/teacher/task_types/task_type_editor.dart';
import 'package:loringo_app/theme/app_theme.dart';

class ImageSelectTask extends StatefulWidget {
  final Color groupColor;
  final Map<String, dynamic>? existingData;
  final TaskEditorController controller;
  final VoidCallback onChanged;

  const ImageSelectTask({
    super.key,
    required this.groupColor,
    this.existingData,
    required this.controller,
    required this.onChanged,
  });

  @override
  State<ImageSelectTask> createState() => _ImageSelectTaskState();
}

class _ImageSelectTaskState extends State<ImageSelectTask> implements TaskTypeEditor {
  late List<Map<String, dynamic>> options;
  late List<TextEditingController> textControllers;
  late List<TextEditingController> imageControllers;
  late List<Map<String, dynamic>?> pickedImages;

  @override
  void initState() {
    super.initState();
    _initializeOptions();
    if (widget.existingData != null) {
      loadData(widget.existingData!);
    }
    // Register this state with the controller
    widget.controller.registerEditor(this);
  }

  // TaskTypeEditor implementation
  @override
  String get typeId => 'image_select';
  
  @override
  String get displayName => 'Image Select';
  
  @override
  // String get defaultQuestion => 'Which of these is ___?';

  void _initializeOptions() {
    options = List.generate(3, (_) => {'text': '', 'image': '', 'isCorrect': false});
    textControllers = List.generate(3, (_) => TextEditingController());
    imageControllers = List.generate(3, (_) => TextEditingController());
    pickedImages = List.generate(3, (_) => null);
  }

  @override
  void loadData(Map<String, dynamic> data) {
    final opts = data['options'] as List<dynamic>? ?? [];
    for (int i = 0; i < opts.length && i < options.length; i++) {
      final opt = opts[i] as Map<String, dynamic>;
      options[i] = {
        'text': opt['text'] ?? '',
        'image': opt['image'] ?? '',
        'isCorrect': opt['isCorrect'] ?? false,
      };
      textControllers[i].text = opt['text'] ?? '';
      imageControllers[i].text = opt['image'] ?? '';
    }
  }

  @override
  Map<String, dynamic> collectData() {
    return {
      'options': List.generate(options.length, (i) => {
        'text': textControllers[i].text.trim(),
        'image': pickedImages[i] != null 
            ? (pickedImages[i]!['imageUrl'] as String? ?? '') 
            : imageControllers[i].text.trim(),
        'isCorrect': options[i]['isCorrect'] ?? false,
      }),
    };
  }

  @override
  String? validate() {
    bool hasCorrect = false;
    for (int i = 0; i < options.length; i++) {
      final hasImage = pickedImages[i] != null || imageControllers[i].text.trim().isNotEmpty;
      if (textControllers[i].text.trim().isEmpty || !hasImage) {
        return 'Option ${i + 1} must have text and image';
      }
      if (options[i]['isCorrect'] == true) hasCorrect = true;
    }
    if (!hasCorrect) return 'Mark at least one option as correct';
    return null;
  }

  void _addOption() {
    if (options.length < 4) {
      setState(() {
        options.add({'text': '', 'image': '', 'isCorrect': false});
        textControllers.add(TextEditingController());
        imageControllers.add(TextEditingController());
        pickedImages.add(null);
        widget.onChanged();
      });
    }
  }

  void _removeOption(int index) {
    if (options.length > 3) {
      setState(() {
        options.removeAt(index);
        textControllers[index].dispose();
        textControllers.removeAt(index);
        imageControllers[index].dispose();
        imageControllers.removeAt(index);
        pickedImages.removeAt(index);
        widget.onChanged();
      });
    }
  }

  @override
  void dispose() {
    for (var c in textControllers) c.dispose();
    for (var c in imageControllers) c.dispose();
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
        _buildHeader(c),
        const SizedBox(height: AppSpacing.md),
        ...List.generate(options.length, (index) => _buildOptionCard(index, c)),
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

  Widget _buildHeader(Color c) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: c.withOpacity(0.07),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        children: [
          Icon(Icons.image_outlined, color: c, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Students select the correct image based on the word shown.',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ),
        ],
      ),
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
            controller: textControllers[index],
            decoration: _inputDecoration(c, 'e.g. "Apple"'),
            onChanged: (_) => widget.onChanged(),
            validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
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
                : Center(child: Text('No image', style: TextStyle(color: Colors.grey[500]))),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        ElevatedButton.icon(
          onPressed: () async {
            final selected = await showDialog(
              context: context,
              builder: (_) => const SelectImageDialog(singleSelect: false),
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
          label: const Text('Select'),
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