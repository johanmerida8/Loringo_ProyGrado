import 'package:flutter/material.dart';
import 'package:loringo_app/components/image_dialog.dart';
import 'package:loringo_app/screens/teacher/task_types/task_type_editor.dart';
import 'package:loringo_app/theme/app_theme.dart';

/// SOUND MATCH
/// The student hears a word spoken aloud (TTS reads `audioText`) and taps
/// the matching image out of 3–4 options. No text is shown to the student
/// on the option cards themselves — this is a listening exercise, not a
/// reading one, which is why it's distinct from `image_select` (where the
/// prompt word IS shown as text).
class SoundMatchTask extends StatefulWidget {
  final Color groupColor;
  final Map<String, dynamic>? existingData;
  final TaskEditorController controller;
  final VoidCallback onChanged;

  const SoundMatchTask({
    super.key,
    required this.groupColor,
    this.existingData,
    required this.controller,
    required this.onChanged,
  });

  @override
  State<SoundMatchTask> createState() => _SoundMatchTaskState();
}

class _SoundMatchTaskState extends State<SoundMatchTask>
    with TaskTypeEditorMixin
    implements TaskTypeEditor {
  late TextEditingController audioTextController;
  late List<Map<String, dynamic>> options;
  late List<TextEditingController> labelControllers;
  late List<TextEditingController> imageControllers;
  late List<Map<String, dynamic>?> pickedImages;

  @override
  void initState() {
    super.initState();
    audioTextController = TextEditingController();
    _initializeOptions();
    if (widget.existingData != null) {
      loadData(widget.existingData!);
    }
    widget.controller.registerEditor(this);
  }

  @override
  String get typeId => 'sound_match';

  @override
  String get displayName => 'Sound Match';

  void _initializeOptions() {
    options = List.generate(3, (_) => {'label': '', 'image': '', 'isCorrect': false});
    labelControllers = List.generate(3, (_) => TextEditingController());
    imageControllers = List.generate(3, (_) => TextEditingController());
    pickedImages = List.generate(3, (_) => null);
  }

  @override
  void loadData(Map<String, dynamic> data) {
    audioTextController.text = data['audioText'] as String? ?? '';
    final opts = data['options'] as List<dynamic>? ?? [];
    if (opts.isNotEmpty) {
      for (final c in labelControllers) c.dispose();
      for (final c in imageControllers) c.dispose();
      options = [];
      labelControllers = [];
      imageControllers = [];
      pickedImages = [];
      for (final raw in opts) {
        final opt = raw as Map<String, dynamic>;
        options.add({
          'label': opt['label'] ?? '',
          'image': opt['image'] ?? '',
          'isCorrect': opt['isCorrect'] ?? false,
        });
        labelControllers.add(TextEditingController(text: opt['label'] ?? ''));
        imageControllers.add(TextEditingController(text: opt['image'] ?? ''));
        pickedImages.add(null);
      }
    }
  }

  @override
  Map<String, dynamic> collectData() {
    return {
      'audioText': audioTextController.text.trim(),
      'options': List.generate(options.length, (i) => {
        'label': labelControllers[i].text.trim(),
        'image': pickedImages[i] != null
            ? (pickedImages[i]!['imageUrl'] as String? ?? '')
            : imageControllers[i].text.trim(),
        'isCorrect': options[i]['isCorrect'] ?? false,
      }),
    };
  }

  @override
  String? validate() {
    if (audioTextController.text.trim().isEmpty) {
      return 'Enter the word or phrase that will be spoken aloud';
    }
    bool hasCorrect = false;
    for (int i = 0; i < options.length; i++) {
      final hasImage = pickedImages[i] != null || imageControllers[i].text.trim().isNotEmpty;
      if (labelControllers[i].text.trim().isEmpty || !hasImage) {
        return 'Option ${i + 1} must have a label and an image';
      }
      if (options[i]['isCorrect'] == true) hasCorrect = true;
    }
    if (!hasCorrect) return 'Mark exactly one option as correct';
    return null;
  }

  void _addOption() {
    if (options.length < 4) {
      setState(() {
        options.add({'label': '', 'image': '', 'isCorrect': false});
        labelControllers.add(TextEditingController());
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
        labelControllers[index].dispose();
        labelControllers.removeAt(index);
        imageControllers[index].dispose();
        imageControllers.removeAt(index);
        pickedImages.removeAt(index);
        widget.onChanged();
      });
    }
  }

  void _setCorrect(int index) {
    // Sound match has exactly one right answer — selecting one option
    // unchecks the rest, unlike image_select which allows several.
    setState(() {
      for (int i = 0; i < options.length; i++) {
        options[i]['isCorrect'] = i == index;
      }
      widget.onChanged();
    });
  }

  @override
  void dispose() {
    audioTextController.dispose();
    for (final c in labelControllers) c.dispose();
    for (final c in imageControllers) c.dispose();
    super.dispose();
  }

  @override
  Widget buildEditor(BuildContext context) => build(context);

  @override
  Widget build(BuildContext context) {
    final c = widget.groupColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(c),
        const SizedBox(height: AppSpacing.md),
        const Text('Word or phrase to speak',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: AppSpacing.xs),
        TextFormField(
          controller: audioTextController,
          decoration: _inputDecoration(c, 'e.g. "apple"'),
          onChanged: (_) => widget.onChanged(),
          validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
        ),
        const SizedBox(height: AppSpacing.md),
        const Text('Answer options', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: AppSpacing.sm),
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
          Icon(Icons.hearing, color: c, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Students hear the word spoken aloud and tap the matching image. No text is shown to them.',
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
              GestureDetector(
                onTap: () => _setCorrect(index),
                child: Row(
                  children: [
                    Icon(
                      isCorrect ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: isCorrect ? c : Colors.grey[400],
                      size: 20,
                    ),
                    const SizedBox(width: 4),
                    const Text('Correct', style: TextStyle(fontSize: 13)),
                  ],
                ),
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
            controller: labelControllers[index],
            decoration: _inputDecoration(c, 'Label for teacher reference, e.g. "Apple"'),
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