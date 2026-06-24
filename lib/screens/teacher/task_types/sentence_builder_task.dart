import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/task_types/task_type_editor.dart';
import 'package:loringo_app/theme/app_theme.dart';

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

class _SentenceBuilderTaskState extends State<SentenceBuilderTask> implements TaskTypeEditor {
  // Core data - SIMPLE!
  late TextEditingController spanishSentenceController;
  late List<String> correctAnswer;        // Just strings in correct order
  late List<TextEditingController> correctWordControllers;  // For editing correct words
  late List<TextEditingController> distractorControllers;   // For editing distractors
  
  // UI state
  bool _expandedAnswerBuilder = true;
  bool _expandedWordBank = true;

  @override
  void initState() {
    super.initState();
    spanishSentenceController = TextEditingController();
    correctAnswer = [];
    correctWordControllers = [];
    distractorControllers = [];
    
    // Initialize with 3 empty correct words and 2 distractors
    // ✅ Direct addition without widget.onChanged()
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

  // TaskTypeEditor implementation
  @override
  String get typeId => 'sentence_builder';
  
  @override
  String get displayName => 'Sentence Builder';
  
  // @override
  // String get defaultQuestion => 'Translate this sentence';

  @override
  void loadData(Map<String, dynamic> data) {
    spanishSentenceController.text = data['spanishSentence'] ?? '';
    
    // Load correct answer
    final loadedCorrectAnswer = data['correctAnswer'] as List<dynamic>? ?? [];
    correctAnswer.clear();
    for (var c in correctWordControllers) c.dispose();
    correctWordControllers.clear();
    
    for (var word in loadedCorrectAnswer) {
      correctAnswer.add(word);
      correctWordControllers.add(TextEditingController(text: word));
    }
    
    // Load word bank - we only store distractors because correct words are in correctAnswer
    final loadedWordBank = data['wordBank'] as List<dynamic>? ?? [];
    for (var c in distractorControllers) c.dispose();
    distractorControllers.clear();
    
    // Filter out words that are in correctAnswer (they're not distractors)
    for (var word in loadedWordBank) {
      if (!correctAnswer.contains(word)) {
        distractorControllers.add(TextEditingController(text: word));
      }
    }
    
    // Ensure we have at least 2 distractors
    while (distractorControllers.length < 2) {
      distractorControllers.add(TextEditingController());
    }
    
    // ✅ REMOVED setState() - no longer needed
  }

  @override
  Map<String, dynamic> collectData() {
    // Get current correct words
    final correctWords = correctWordControllers.map((c) => c.text.trim()).toList();
    
    // Get all distractors
    final distractors = distractorControllers.map((c) => c.text.trim()).toList();
    
    // Word bank = correct words + distractors (shuffled for storage)
    final wordBank = [
      ...correctWords,
      ...distractors,
    ]..shuffle();
    
    return {
      'spanishSentence': spanishSentenceController.text.trim(),
      'correctAnswer': correctWords,
      'wordBank': wordBank,
    };
  }

  @override
  String? validate() {
    if (spanishSentenceController.text.trim().isEmpty) {
      return 'Spanish sentence is required';
    }
    
    // Check correct answer
    final correctWords = correctWordControllers.map((c) => c.text.trim()).toList();
    if (correctWords.length < 2) {
      return 'Add at least 2 words to the correct answer';
    }
    
    for (int i = 0; i < correctWordControllers.length; i++) {
      if (correctWordControllers[i].text.trim().isEmpty) {
        return 'Correct answer word ${i + 1} is empty';
      }
    }
    
    // Check distractors
    final distractors = distractorControllers.map((c) => c.text.trim()).toList();
    if (distractors.length < 1) {
      return 'Add at least 1 distractor word';
    }
    
    for (int i = 0; i < distractorControllers.length; i++) {
      if (distractorControllers[i].text.trim().isEmpty) {
        return 'Distractor ${i + 1} is empty';
      }
    }
    
    // Check that no distractor duplicates a correct word
    for (var distractor in distractors) {
      if (correctWords.contains(distractor) && distractor.isNotEmpty) {
        return 'Distractor "$distractor" is already in the correct answer';
      }
    }
    
    return null;
  }

  @override
  void dispose() {
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

  // ── Helper methods ─────────────────────────────────────────────────────────
  
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

  // ── UI Builders ────────────────────────────────────────────────────────────
  
  Widget _buildEditor() {
    final c = widget.groupColor;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(c),
        const SizedBox(height: AppSpacing.md),
        
        // Spanish Sentence Field
        _buildSpanishSentenceField(c),
        const SizedBox(height: AppSpacing.md),
        
        // Correct Answer Builder
        _buildCorrectAnswerBuilder(c),
        const SizedBox(height: AppSpacing.md),
        
        // Word Bank (Distractors only)
        _buildDistractorsBuilder(c),
      ],
    );
  }
  
  Widget _buildHeader(Color c) {
    return Container(
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
              'Students see a Spanish sentence and build the English translation by tapping words in the correct order.',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSpanishSentenceField(Color c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Spanish Sentence (what students read)',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextFormField(
          controller: spanishSentenceController,
          decoration: InputDecoration(
            hintText: 'e.g. "¿Hay una camisa roja?"',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            filled: true,
            fillColor: Colors.white,
          ),
          maxLines: 2,
          onChanged: (_) => widget.onChanged(),
          validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
        ),
      ],
    );
  }
  
  Widget _buildCorrectAnswerBuilder(Color c) {
    final correctWords = correctWordControllers.map((ctrl) => ctrl.text.trim()).toList();
    
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
                const Text(
                  'Correct English Answer',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                // Instructions
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
                
                // Correct answer chips (reorderable)
                if (correctWordControllers.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(correctWordControllers.length, (index) {
                      return _buildAnswerChip(index, c);
                    }),
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
                
                // Add word button
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
                    style: TextStyle(fontSize: 11, color: Colors.orange),
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
                // Instructions
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
                
                // Distractor items
                ...List.generate(distractorControllers.length, (index) {
                  return _buildDistractorItem(index, c);
                }),
                
                const SizedBox(height: AppSpacing.md),
                
                // Add distractor button
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
          
          // Word text field
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
          
          // Remove button
          IconButton(
            icon: Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
            onPressed: () => _removeDistractor(index),
          ),
        ],
      ),
    );
  }
}