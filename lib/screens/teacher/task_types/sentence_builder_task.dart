import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/task_types/task_type_editor.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:translator/translator.dart';

class SentenceBuilderTask extends StatefulWidget {
  final Color groupColor;
  final Map<String, dynamic>? existingData;
  final TaskEditorController controller;
  final VoidCallback onChanged;

  const SentenceBuilderTask({
    super.key,
    required this.groupColor,
    this.existingData,
    required this.controller,
    required this.onChanged,
  });

  @override
  State<SentenceBuilderTask> createState() => _SentenceBuilderTaskState();
}

class _SentenceBuilderTaskState extends State<SentenceBuilderTask>
    with TaskTypeEditorMixin
    implements TaskTypeEditor {
  late TextEditingController spanishSentenceController;
  late List<String> correctAnswer;
  late List<TextEditingController> correctWordControllers;
  late List<TextEditingController> distractorControllers;

  bool _expandedAnswerBuilder = true;
  bool _expandedWordBank = true;

  String _direction = 'es_to_en'; // 'es_to_en' or 'en_to_es'

  final GoogleTranslator _translator = GoogleTranslator();
  late FocusNode _sentenceFocusNode;
  bool _isTranslating = false;

  @override
  void initState() {
    super.initState();
    spanishSentenceController = TextEditingController();
    _sentenceFocusNode = FocusNode();
    _sentenceFocusNode.addListener(_onSentenceFocusChange);

    correctAnswer = [];
    correctWordControllers = [];
    distractorControllers = [];

    for (int i = 0; i < 3; i++) {
      correctWordControllers.add(TextEditingController());
    }
    for (int i = 0; i < 2; i++) {
      distractorControllers.add(TextEditingController());
    }

    if (widget.existingData != null) {
      loadData(widget.existingData!);
    }

    widget.controller.registerEditor(this);
  }

  void _onSentenceFocusChange() {
    if (!_sentenceFocusNode.hasFocus) {
      _autoFillFromTranslation();
    }
  }

  /// Only auto-fills if all correct-word slots are currently empty,
  /// so it never silently overwrites a teacher's manual edits.
  Future<void> _autoFillFromTranslation() async {
    final sourceText = spanishSentenceController.text.trim();
    if (sourceText.isEmpty) return;

    final allEmpty = correctWordControllers.every((c) => c.text.trim().isEmpty);
    if (!allEmpty) return;

    final sourceLang = _direction == 'es_to_en' ? 'es' : 'en';
    final targetLang = _direction == 'es_to_en' ? 'en' : 'es';

    setState(() => _isTranslating = true);

    try {
      final translation = await _translator.translate(
        sourceText,
        from: sourceLang,
        to: targetLang,
      );

      final words = translation.text
          .replaceAll(RegExp(r'[¿?¡!.,]'), '')
          .split(' ')
          .where((w) => w.trim().isNotEmpty)
          .toList();

      if (!mounted || words.isEmpty) return;

      setState(() {
        for (var c in correctWordControllers) {
          c.dispose();
        }
        correctWordControllers =
            words.map((w) => TextEditingController(text: w)).toList();
        widget.onChanged();
      });
    } catch (e) {
      debugPrint('Translation error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Translation failed. You can add words manually.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isTranslating = false);
    }
  }

  /// Manual re-translate, always overwrites (used by the refresh button).
  Future<void> _forceRetranslate() async {
    final sourceText = spanishSentenceController.text.trim();
    if (sourceText.isEmpty) return;

    final sourceLang = _direction == 'es_to_en' ? 'es' : 'en';
    final targetLang = _direction == 'es_to_en' ? 'en' : 'es';

    setState(() => _isTranslating = true);

    try {
      final translation = await _translator.translate(
        sourceText,
        from: sourceLang,
        to: targetLang,
      );

      final words = translation.text
          .replaceAll(RegExp(r'[¿?¡!.,]'), '')
          .split(' ')
          .where((w) => w.trim().isNotEmpty)
          .toList();

      if (!mounted || words.isEmpty) return;

      setState(() {
        for (var c in correctWordControllers) {
          c.dispose();
        }
        correctWordControllers =
            words.map((w) => TextEditingController(text: w)).toList();
        widget.onChanged();
      });
    } catch (e) {
      debugPrint('Translation error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Translation failed.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isTranslating = false);
    }
  }

  // TaskTypeEditor implementation
  @override
  String get typeId => 'sentence_builder';

  @override
  String get displayName => 'Sentence Builder';

  @override
  void loadData(Map<String, dynamic> data) {
    _direction = data['direction'] ?? 'es_to_en';
    spanishSentenceController.text =
        data['sentence'] ?? data['spanishSentence'] ?? '';

    final loadedCorrectAnswer = data['correctAnswer'] as List<dynamic>? ?? [];
    correctAnswer.clear();
    for (var c in correctWordControllers) c.dispose();
    correctWordControllers.clear();

    for (var word in loadedCorrectAnswer) {
      correctAnswer.add(word);
      correctWordControllers.add(TextEditingController(text: word));
    }

    final loadedWordBank = data['wordBank'] as List<dynamic>? ?? [];
    for (var c in distractorControllers) c.dispose();
    distractorControllers.clear();

    for (var word in loadedWordBank) {
      if (!correctAnswer.contains(word)) {
        distractorControllers.add(TextEditingController(text: word));
      }
    }

    while (distractorControllers.length < 2) {
      distractorControllers.add(TextEditingController());
    }
  }

  @override
  Map<String, dynamic> collectData() {
    final correctWords =
        correctWordControllers.map((c) => c.text.trim()).toList();
    final distractors =
        distractorControllers.map((c) => c.text.trim()).toList();

    final wordBank = [...correctWords, ...distractors]..shuffle();

    return {
      'direction': _direction,
      'sentence': spanishSentenceController.text.trim(),
      // kept for backward compatibility with older readers of this data
      'spanishSentence': spanishSentenceController.text.trim(),
      'correctAnswer': correctWords,
      'wordBank': wordBank,
    };
  }

  @override
  String? validate() {
    final isEsToEn = _direction == 'es_to_en';

    if (spanishSentenceController.text.trim().isEmpty) {
      return isEsToEn ? 'Spanish sentence is required' : 'English sentence is required';
    }

    final correctWords =
        correctWordControllers.map((c) => c.text.trim()).toList();
    if (correctWords.length < 2) {
      return 'Add at least 2 words to the correct answer';
    }

    for (int i = 0; i < correctWordControllers.length; i++) {
      if (correctWordControllers[i].text.trim().isEmpty) {
        return 'Correct answer word ${i + 1} is empty';
      }
    }

    final distractors =
        distractorControllers.map((c) => c.text.trim()).toList();
    if (distractors.length < 1) {
      return 'Add at least 1 distractor word';
    }

    for (int i = 0; i < distractorControllers.length; i++) {
      if (distractorControllers[i].text.trim().isEmpty) {
        return 'Distractor ${i + 1} is empty';
      }
    }

    for (var distractor in distractors) {
      if (correctWords.contains(distractor) && distractor.isNotEmpty) {
        return 'Distractor "$distractor" is already in the correct answer';
      }
    }

    return null;
  }

  @override
  void dispose() {
    _sentenceFocusNode.removeListener(_onSentenceFocusChange);
    _sentenceFocusNode.dispose();
    spanishSentenceController.dispose();
    for (var c in correctWordControllers) c.dispose();
    for (var c in distractorControllers) c.dispose();
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

  // ── Helper methods ──────────────────────────────────────────────

  void _addCorrectWord() {
    setState(() {
      correctWordControllers.add(TextEditingController());
      widget.onChanged();
    });
  }

  void _removeCorrectWord(int index) {
    setState(() {
      correctWordControllers[index].dispose();
      correctWordControllers.removeAt(index);
      widget.onChanged();
    });
  }

  void _reorderCorrectWord(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final controller = correctWordControllers.removeAt(oldIndex);
      correctWordControllers.insert(newIndex, controller);
      widget.onChanged();
    });
  }

  void _addDistractor() {
    setState(() {
      distractorControllers.add(TextEditingController());
      widget.onChanged();
    });
  }

  void _removeDistractor(int index) {
    setState(() {
      distractorControllers[index].dispose();
      distractorControllers.removeAt(index);
      widget.onChanged();
    });
  }

  void _setDirection(String direction) {
    if (_direction == direction) return;
    setState(() {
      _direction = direction;
      widget.onChanged();
    });
  }

  // ── UI Builders ──────────────────────────────────────────────────

  Widget _buildEditor() {
    final c = widget.groupColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(c),
        const SizedBox(height: AppSpacing.md),
        _buildSpanishSentenceField(c),
        const SizedBox(height: AppSpacing.md),
        _buildCorrectAnswerBuilder(c),
        const SizedBox(height: AppSpacing.md),
        _buildDistractorsBuilder(c),
      ],
    );
  }

  Widget _buildHeader(Color c) {
    final isEsToEn = _direction == 'es_to_en';
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
              Icon(Icons.translate, color: c, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  isEsToEn
                      ? 'Students see a Spanish sentence and build the English translation by tapping words in the correct order.'
                      : 'Students see an English sentence and build the Spanish translation by tapping words in the correct order.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              Expanded(
                child: _buildDirectionOption(
                  label: 'ES → EN',
                  isSelected: isEsToEn,
                  color: c,
                  onTap: () => _setDirection('es_to_en'),
                ),
              ),
              Expanded(
                child: _buildDirectionOption(
                  label: 'EN → ES',
                  isSelected: !isEsToEn,
                  color: c,
                  onTap: () => _setDirection('en_to_es'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDirectionOption({
    required String label,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade400,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isSelected ? color : Colors.grey[700],
          ),
        ),
      ),
    );
  }

  Widget _buildSpanishSentenceField(Color c) {
    final isEsToEn = _direction == 'es_to_en';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              isEsToEn ? 'Spanish Sentence' : 'English Sentence',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            if (_isTranslating) ...[
              const SizedBox(width: 8),
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        TextFormField(
          controller: spanishSentenceController,
          focusNode: _sentenceFocusNode,
          decoration: InputDecoration(
            hintText: isEsToEn ? 'e.g. "¿Cómo estás?"' : 'e.g. "How are you?"',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            filled: true,
            fillColor: Colors.white,
            suffixIcon: IconButton(
              icon: Icon(Icons.auto_awesome, color: c, size: 20),
              tooltip: 'Re-translate',
              onPressed: _isTranslating ? null : _forceRetranslate,
            ),
          ),
          maxLines: 2,
          onChanged: (_) => widget.onChanged(),
          validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
        ),
      ],
    );
  }

  Widget _buildCorrectAnswerBuilder(Color c) {
    final isEsToEn = _direction == 'es_to_en';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expandedAnswerBuilder = !_expandedAnswerBuilder),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                Icon(_expandedAnswerBuilder ? Icons.expand_less : Icons.expand_more, color: c),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  isEsToEn ? 'Correct English Answer' : 'Correct Spanish Answer',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${correctWordControllers.length} words',
                    style: TextStyle(fontSize: 11, color: c),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expandedAnswerBuilder) ...[
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
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.drag_handle, size: 16, color: Colors.blue.shade700),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Drag to reorder words. Students must tap words in this exact order.',
                          style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (correctWordControllers.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(
                      correctWordControllers.length,
                      (index) => _buildAnswerChip(index, c),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: const Center(
                      child: Text('Add words below to build the correct answer'),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _addCorrectWord,
                        icon: Icon(Icons.add, color: c),
                        label: Text('Add Word', style: TextStyle(color: c)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: c.withOpacity(0.5)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAnswerChip(int index, Color c) {
    final controller = correctWordControllers[index];

    return Draggable<int>(
      data: index,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: const Offset(0, 2))],
          ),
          child: Text(controller.text.isEmpty ? '___' : controller.text,
              style: const TextStyle(color: Colors.white)),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: c.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c, width: 1.5),
          ),
          child: Text(controller.text.isEmpty ? '___' : controller.text,
              style: TextStyle(color: c)),
        ),
      ),
      child: DragTarget<int>(
        onAcceptWithDetails: (details) {
          _reorderCorrectWord(details.data, index);
        },
        builder: (context, candidateData, rejectedData) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 60,
                  child: TextField(
                    controller: controller,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (_) => widget.onChanged(),
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => _removeCorrectWord(index),
                  child: const Icon(Icons.close, size: 14, color: Colors.white70),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDistractorsBuilder(Color c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expandedWordBank = !_expandedWordBank),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                Icon(_expandedWordBank ? Icons.expand_less : Icons.expand_more, color: c),
                const SizedBox(width: AppSpacing.sm),
                const Text(
                  'Distractors (Extra Words)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${distractorControllers.length} words',
                    style: const TextStyle(fontSize: 11, color: Colors.orange),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expandedWordBank) ...[
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
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange.shade700),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Distractors are extra words that DO NOT belong in the correct answer.',
                          style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                ...List.generate(
                  distractorControllers.length,
                  (index) => _buildDistractorItem(index, c),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _addDistractor,
                        icon: const Icon(Icons.add, color: Colors.orange),
                        label: const Text('Add Distractor', style: TextStyle(color: Colors.orange)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.orange),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDistractorItem(int index, Color c) {
    final controller = distractorControllers[index];

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: Colors.orange.shade200, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 70,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: Colors.orange,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              '✗ Distractor',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextFormField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'e.g. "blue"',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (_) => widget.onChanged(),
              validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
            onPressed: () => _removeDistractor(index),
          ),
        ],
      ),
    );
  }
}