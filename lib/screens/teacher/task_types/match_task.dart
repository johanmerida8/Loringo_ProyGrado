import 'package:flutter/material.dart';
import 'package:loringo_app/components/image_dialog.dart';
import 'package:loringo_app/screens/teacher/task_types/task_type_editor.dart';
import 'package:loringo_app/theme/app_theme.dart';
// import 'task_type_interface.dart';

class MatchPair {
  TextEditingController englishCtrl;
  TextEditingController translatedCtrl;
  TextEditingController imageUrlCtrl;
  Map<String, dynamic>? pickedImage;

  MatchPair({
    String english = '',
    String translated = '',
    String imageUrl = '',
  })  : englishCtrl = TextEditingController(text: english),
        translatedCtrl = TextEditingController(text: translated),
        imageUrlCtrl = TextEditingController(text: imageUrl);

  void dispose() {
    englishCtrl.dispose();
    translatedCtrl.dispose();
    imageUrlCtrl.dispose();
  }

  String get resolvedImageUrl => pickedImage != null
      ? (pickedImage!['imageUrl'] as String? ?? '')
      : imageUrlCtrl.text.trim();
}

class MatchTask extends StatefulWidget {
  final Color groupColor;
  final Map<String, dynamic>? existingData;
  final TaskEditorController controller;
  final VoidCallback onChanged;

  const MatchTask({
    super.key,
    required this.groupColor,
    this.existingData,
    required this.controller,
    required this.onChanged,
  });

  @override
  State<MatchTask> createState() => _MatchTaskState();
}

class _MatchTaskState extends State<MatchTask> with TaskTypeEditorMixin implements TaskTypeEditor {
  late List<MatchPair> pairs;
  late String matchMode;

  @override
  void initState() {
    super.initState();
    matchMode = 'text';
    pairs = List.generate(3, (_) => MatchPair());
    if (widget.existingData != null) {
      loadData(widget.existingData!);
    }

    widget.controller.registerEditor(this);
  }

  // TaskTypeEditor implementation
  @override
  String get typeId => 'match';
  
  @override
  String get displayName => 'Match';
  
  @override
  String get defaultQuestion => 'Match the words';

  @override
  void loadData(Map<String, dynamic> data) {
    matchMode = data['mode'] as String? ?? 'text';
    final rawPairs = data['pairs'] as List<dynamic>?;
    if (rawPairs != null && rawPairs.isNotEmpty) {
      for (final p in pairs) p.dispose();
      pairs.clear();
      for (final pair in rawPairs) {
        final p = pair as Map<String, dynamic>;
        pairs.add(MatchPair(
          english: p['english'] as String? ?? '',
          translated: p['translated'] as String? ?? '',
          imageUrl: p['image'] as String? ?? '',
        ));
      }
    }
  }

  @override
  Map<String, dynamic> collectData() {
    return {
      'mode': matchMode,
      'pairs': pairs.map((p) => {
        'english': p.englishCtrl.text.trim(),
        'translated': matchMode == 'text' ? p.translatedCtrl.text.trim() : '',
        'image': matchMode == 'image' ? p.resolvedImageUrl : '',
      }).toList(),
    };
  }

  @override
  String? validate() {
    for (int i = 0; i < pairs.length; i++) {
      if (pairs[i].englishCtrl.text.trim().isEmpty) {
        return 'Pair ${i + 1}: English word is required';
      }
      if (matchMode == 'text' && pairs[i].translatedCtrl.text.trim().isEmpty) {
        return 'Pair ${i + 1}: translation is required';
      }
      if (matchMode == 'image' && pairs[i].resolvedImageUrl.isEmpty) {
        return 'Pair ${i + 1}: image is required';
      }
    }
    return null;
  }

  void _addPair() {
    if (pairs.length < 5) {
      setState(() {
        pairs.add(MatchPair());
        widget.onChanged();
      });
    }
  }

  void _removePair(int index) {
    if (pairs.length > 3) {
      setState(() {
        pairs[index].dispose();
        pairs.removeAt(index);
        widget.onChanged();
      });
    }
  }

  @override
  void dispose() {
    for (final p in pairs) p.dispose();
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
    final isImageMode = matchMode == 'image';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: c.withOpacity(0.07),
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: c.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: c),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Student taps one from each column to form a match. Min 3, max 5 pairs.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _buildModeToggle(c),
        const SizedBox(height: AppSpacing.md),
        _buildColumnHeaders(isImageMode, c),
        const SizedBox(height: AppSpacing.sm),
        ...List.generate(pairs.length, (index) => _buildPairRow(index, isImageMode, c)),
        if (pairs.length < 5)
          TextButton.icon(
            onPressed: _addPair,
            icon: Icon(Icons.add, color: c, size: 18),
            label: Text('Add pair (${pairs.length}/5)', style: TextStyle(color: c, fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }

  Widget _buildModeToggle(Color c) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(child: _modeToggleBtn('text', 'Text ↔ Translation', Icons.translate, c)),
          Expanded(child: _modeToggleBtn('image', 'Text ↔ Image', Icons.image_outlined, c)),
        ],
      ),
    );
  }

  Widget _modeToggleBtn(String mode, String label, IconData icon, Color c) {
    final isActive = matchMode == mode;
    return GestureDetector(
      onTap: () => setState(() {
        matchMode = mode;
        widget.onChanged();
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.all(AppSpacing.xs),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: isActive ? c : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: isActive ? AppColors.onPrimary : Colors.grey[500]),
            const SizedBox(width: AppSpacing.xs),
            Text(label, style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isActive ? AppColors.onPrimary : Colors.grey[600],
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildColumnHeaders(bool isImageMode, Color c) {
    return Row(
      children: [
        const SizedBox(width: 32),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: c.withOpacity(0.08),
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.flag, size: 13, color: c),
                const SizedBox(width: 4),
                Text('English', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c)),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: (isImageMode ? Colors.purple : Colors.orange).withOpacity(0.08),
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(isImageMode ? Icons.image_outlined : Icons.flag, size: 13, color: isImageMode ? Colors.purple : Colors.orange),
                const SizedBox(width: 4),
                Text(isImageMode ? 'Image' : 'Translation', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isImageMode ? Colors.purple : Colors.orange)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 34),
      ],
    );
  }

  Widget _buildPairRow(int index, bool isImageMode, Color c) {
    final pair = pairs[index];
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24, height: 24,
            margin: const EdgeInsets.only(right: AppSpacing.sm, top: AppSpacing.sm),
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            child: Center(child: Text('${index + 1}', style: const TextStyle(color: AppColors.onPrimary, fontSize: 11, fontWeight: FontWeight.bold))),
          ),
          Expanded(
            child: TextFormField(
              controller: pair.englishCtrl,
              decoration: _inputDecoration(c, 'e.g. "Red"'),
              onChanged: (_) => widget.onChanged(),
              validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.sm),
            child: Icon(Icons.swap_horiz, color: Colors.grey[400], size: 20),
          ),
          Expanded(
            child: isImageMode
                ? _buildImagePickerField(pair, c)
                : TextFormField(
                    controller: pair.translatedCtrl,
                    decoration: _inputDecoration(Colors.orange, 'e.g. "Rojo"'),
                    onChanged: (_) => widget.onChanged(),
                    validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                  ),
          ),
          if (pairs.length > 3)
            GestureDetector(
              onTap: () => _removePair(index),
              child: Container(
                margin: const EdgeInsets.only(left: AppSpacing.xs, top: AppSpacing.sm),
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(color: AppColors.danger.withOpacity(0.08), shape: BoxShape.circle),
                child: Icon(Icons.close, size: 14, color: AppColors.danger),
              ),
            )
          else
            const SizedBox(width: 34),
        ],
      ),
    );
  }

  Widget _buildImagePickerField(MatchPair pair, Color c) {
    final hasImage = pair.pickedImage != null || pair.imageUrlCtrl.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 80,
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border: Border.all(color: AppColors.divider),
          ),
          child: hasImage
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  child: Image.network(
                    pair.resolvedImageUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 28),
                  ),
                )
              : Center(child: Text('No image', style: TextStyle(fontSize: 12, color: Colors.grey[500]))),
        ),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () async {
              final selected = await showDialog(
                context: context,
                builder: (_) => const SelectImageDialog(singleSelect: true),
              );
              if (selected != null) {
                setState(() {
                  pair.pickedImage = selected as Map<String, dynamic>;
                  pair.imageUrlCtrl.text = selected['name'] ?? 'Selected';
                  widget.onChanged();
                });
              }
            },
            icon: const Icon(Icons.image, size: 16),
            label: Text(hasImage ? 'Change' : 'Select Image', style: const TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey[200],
              foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(Color c, String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: BorderSide(color: AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: BorderSide(color: c, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      filled: true,
      fillColor: Colors.white,
    );
  }
}