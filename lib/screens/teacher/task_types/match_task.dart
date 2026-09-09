import 'package:flutter/material.dart';
import 'package:loringo_app/components/image_dialog.dart';
import 'package:loringo_app/screens/teacher/task_types/task_type_editor.dart';
import 'package:loringo_app/theme/app_theme.dart';
// import 'task_type_interface.dart';
import 'package:translator/translator.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';

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

  final GoogleTranslator _translator = GoogleTranslator();

  int? _translatingIndex;

  static const int _maxPairs = 8;

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
        return 'teacher.match_task.pairEnglishRequired'.tr(namedArgs: {'number': '${i + 1}'});
      }
      if (matchMode == 'text' && pairs[i].translatedCtrl.text.trim().isEmpty) {
        return 'teacher.match_task.pairTranslationRequired'.tr(namedArgs: {'number': '${i + 1}'});
      }
      if (matchMode == 'image' && pairs[i].resolvedImageUrl.isEmpty) {
        return 'teacher.match_task.pairImageRequired'.tr(namedArgs: {'number': '${i + 1}'});
      }
    }
    return null;
  }

  void _addPair() {
    if (pairs.length < _maxPairs) {
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

  Future<void> _translatePair(int index) async {
    final pair = pairs[index];
    final sourceText = pair.englishCtrl.text.trim();
    if (sourceText.isEmpty) return;

    setState(() => _translatingIndex = index);

    try {
      final translation = await _translator.translate(
        sourceText,
        from: 'en',
        to: 'es',
      );
      if (!mounted) return;
      setState(() {
        pair.translatedCtrl.text = translation.text;
        widget.onChanged();
      });
    } catch (e) {
      debugPrint('MatchTask translation error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('teacher.match_task.translateSingleFailed'.tr())),
        );
      }
    } finally {
      if (mounted) setState(() => _translatingIndex = null);
    }
  }

  Future<void> _translateAllPairs() async {
    final indicesToTranslate = <int>[];
    for (int i = 0; i < pairs.length; i++) {
      if (pairs[i].englishCtrl.text.trim().isNotEmpty &&
          pairs[i].translatedCtrl.text.trim().isEmpty) {
        indicesToTranslate.add(i);
      }
    }
    if (indicesToTranslate.isEmpty) return;

    setState(() => _translatingIndex = -1); // -1 signals "all rows" for the loading UI

    try {
      for (final i in indicesToTranslate) {
        final sourceText = pairs[i].englishCtrl.text.trim();
        final translation = await _translator.translate(sourceText, from: 'en', to: 'es');
        if (!mounted) return;
        pairs[i].translatedCtrl.text = translation.text;
      }
      setState(() => widget.onChanged());
    } catch (e) {
      debugPrint('MatchTask translateAll error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('teacher.match_task.translateAllFailed'.tr())),
        );
      }
    } finally {
      if (mounted) setState(() => _translatingIndex = null);
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
    context.watch<LocaleProvider>();
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
                  'teacher.match_task.infoBanner'.tr(namedArgs: {'max': '$_maxPairs'}),
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _buildModeToggle(c),
        const SizedBox(height: AppSpacing.md),
        // NEW: single "Translate All" action, replaces the per-row ✨ icon.
        if (!isImageMode)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _translatingIndex != null ? null : _translateAllPairs,
                icon: _translatingIndex != null
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(Icons.auto_awesome, color: c, size: 18),
                label: Text(
                  _translatingIndex != null
                      ? 'teacher.match_task.translating'.tr()
                      : 'teacher.match_task.translateAll'.tr(),
                  style: TextStyle(color: c, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(side: BorderSide(color: c.withOpacity(0.5))),
              ),
            ),
          ),
        _buildColumnHeaders(isImageMode, c),
        const SizedBox(height: AppSpacing.sm),
        ...List.generate(pairs.length, (index) => _buildPairRow(index, isImageMode, c)),
        if (pairs.length < _maxPairs)
          TextButton.icon(
            onPressed: _addPair,
            icon: Icon(Icons.add, color: c, size: 18),
            label: Text(
              'teacher.match_task.addPair'.tr(namedArgs: {'current': '${pairs.length}', 'max': '$_maxPairs'}),
              style: TextStyle(color: c, fontWeight: FontWeight.w600),
            ),
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
          Expanded(child: _modeToggleBtn('text', 'teacher.match_task.modeText'.tr(), Icons.translate, c)),
          Expanded(child: _modeToggleBtn('image', 'teacher.match_task.modeImage'.tr(), Icons.image_outlined, c)),
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
            decoration: BoxDecoration(color: c.withOpacity(0.08), borderRadius: BorderRadius.circular(AppRadii.sm)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.flag, size: 13, color: c),
              const SizedBox(width: 4),
              Text('teacher.match_task.englishHeader'.tr(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c)),
            ]),
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
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(isImageMode ? Icons.image_outlined : Icons.flag, size: 13, color: isImageMode ? Colors.purple : Colors.orange),
              const SizedBox(width: 4),
              // CHANGED: "Translation" -> "Spanish", matches what this
              // column actually always is (MatchTask has no direction
              // toggle -- it's always English -> Spanish).
              Text(
                isImageMode ? 'teacher.match_task.imageHeader'.tr() : 'teacher.match_task.spanishHeader'.tr(),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isImageMode ? Colors.purple : Colors.orange),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 34),
      ],
    );
  }

  Widget _buildPairRow(int index, bool isImageMode, Color c) {
    final pair = pairs[index];
    final isTranslatingThisRow = _translatingIndex == index;

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
              decoration: _inputDecoration(c, 'teacher.match_task.englishHint'.tr()),
              onChanged: (_) => widget.onChanged(),
              validator: (v) => v?.isEmpty ?? true ? 'teacher.match_task.required'.tr() : null,
            ),
          ),
          // CHANGED: was a static swap_horiz icon. In text mode, this is
          // now a tappable auto-translate button (same GoogleTranslator
          // SentenceBuilderTask uses) -- tapping it fills the Translation
          // field from the current English text. Image mode keeps the
          // plain swap_horiz glyph since there's nothing to translate
          // into an image.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.sm),
            child: isImageMode
                ? Icon(Icons.swap_horiz, color: Colors.grey[400], size: 20)
                : GestureDetector(
                    onTap: isTranslatingThisRow ? null : () => _translatePair(index),
                    child: isTranslatingThisRow
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: Padding(
                              padding: EdgeInsets.all(2),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : Icon(Icons.auto_awesome, color: c, size: 20),
                  ),
          ),
          Expanded(
            child: isImageMode
                ? _buildImagePickerField(pair, c)
                : TextFormField(
                    controller: pair.translatedCtrl,
                    decoration: _inputDecoration(Colors.orange, 'teacher.match_task.spanishHint'.tr()),
                    onChanged: (_) => widget.onChanged(),
                    validator: (v) => v?.isEmpty ?? true ? 'teacher.match_task.required'.tr() : null,
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
              : Center(child: Text('teacher.match_task.noImage'.tr(), style: TextStyle(fontSize: 12, color: Colors.grey[500]))),
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
            label: Text(
              hasImage ? 'teacher.match_task.change'.tr() : 'teacher.match_task.selectImage'.tr(),
              style: const TextStyle(fontSize: 12),
            ),
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