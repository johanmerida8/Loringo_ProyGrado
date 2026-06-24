import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/task_types/task_type_editor.dart';
import 'package:loringo_app/theme/app_theme.dart';
// import 'task_type_interface.dart';

class ReadingQuestion {
  TextEditingController questionCtrl;
  List<Map<String, dynamic>> options;
  List<TextEditingController> optionCtrls;

  ReadingQuestion({
    String question = '',
    List<Map<String, dynamic>>? options,
    List<TextEditingController>? optionCtrls,
  })  : questionCtrl = TextEditingController(text: question),
        options = options ??
            List.generate(3, (_) => {'text': '', 'isCorrect': false}),
        optionCtrls = optionCtrls ??
            List.generate(3, (_) => TextEditingController());

  void dispose() {
    questionCtrl.dispose();
    for (final c in optionCtrls) c.dispose();
  }
}

class ReadingTask extends StatefulWidget {
  final Color groupColor;
  final Map<String, dynamic>? existingData;
  final TaskEditorController controller;
  final VoidCallback onChanged;

  const ReadingTask({
    super.key,
    required this.groupColor,
    this.existingData,
    required this.controller,
    required this.onChanged,
  });

  @override
  State<ReadingTask> createState() => _ReadingTaskState();
}

class _ReadingTaskState extends State<ReadingTask> implements TaskTypeEditor {
  static const int _warnWordsPerPage = 300;
  
  late List<TextEditingController> pageControllers;
  late List<ReadingQuestion> questions;
  late int currentPageIndex;

  @override
  void initState() {
    super.initState();
    pageControllers = [TextEditingController()];
    questions = List.generate(2, (_) => ReadingQuestion());
    currentPageIndex = 0;
    if (widget.existingData != null) {
      loadData(widget.existingData!);
    }

    widget.controller.registerEditor(this);
  }

  // TaskTypeEditor implementation
  @override
  String get typeId => 'reading';
  
  @override
  String get displayName => 'Reading Comprehension';
  
  @override
  String get defaultQuestion => 'Reading Comprehension';

  @override
  void loadData(Map<String, dynamic> data) {
    final pages = data['pages'] as List<dynamic>?;
    if (pages != null && pages.isNotEmpty) {
      for (final c in pageControllers) c.dispose();
      pageControllers.clear();
      for (final pageText in pages) {
        pageControllers.add(TextEditingController(text: pageText as String? ?? ''));
      }
    }
    
    final rawQs = data['questions'] as List<dynamic>?;
    if (rawQs != null && rawQs.isNotEmpty) {
      for (final q in questions) q.dispose();
      questions.clear();
      for (final rq in rawQs) {
        final q = rq as Map<String, dynamic>;
        final rawOpts = List<Map<String, dynamic>>.from(q['options'] ?? []);
        questions.add(ReadingQuestion(
          question: q['text'] as String? ?? '',
          options: rawOpts.map((o) => {'text': o['text'] ?? '', 'isCorrect': o['isCorrect'] ?? false}).toList(),
          optionCtrls: rawOpts.map((o) => TextEditingController(text: o['text'] ?? '')).toList(),
        ));
      }
    }
  }

  @override
  Map<String, dynamic> collectData() {
    return {
      'pages': pageControllers.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList(),
      'questions': questions.map((rq) {
        for (int i = 0; i < rq.options.length; i++) {
          rq.options[i]['text'] = rq.optionCtrls[i].text.trim();
        }
        return {
          'text': rq.questionCtrl.text.trim(),
          'options': List<Map<String, dynamic>>.from(rq.options),
        };
      }).toList(),
    };
  }

  @override
  String? validate() {
    final pages = pageControllers.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
    if (pages.isEmpty) return 'Reading passage cannot be empty';
    if (questions.isEmpty) return 'Add at least one comprehension question';
    
    for (int i = 0; i < questions.length; i++) {
      final rq = questions[i];
      if (rq.questionCtrl.text.trim().isEmpty) {
        return 'Question ${i + 1}: text cannot be empty';
      }
      if (!rq.options.any((o) => o['isCorrect'] == true)) {
        return 'Question ${i + 1}: mark at least one correct answer';
      }
      if (rq.optionCtrls.where((c) => c.text.isNotEmpty).length < 3) {
        return 'Question ${i + 1}: provide at least 3 options';
      }
    }
    return null;
  }

  int _wordCount(String text) => text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  void _addPage() {
    if (pageControllers.length < 5) {
      setState(() {
        pageControllers.add(TextEditingController());
        currentPageIndex = pageControllers.length - 1;
        widget.onChanged();
      });
    }
  }

  void _removePage() {
    if (pageControllers.length > 1) {
      setState(() {
        pageControllers[currentPageIndex].dispose();
        pageControllers.removeAt(currentPageIndex);
        if (currentPageIndex >= pageControllers.length) {
          currentPageIndex = pageControllers.length - 1;
        }
        widget.onChanged();
      });
    }
  }

  void _addQuestion() {
    if (questions.length < 5) {
      setState(() {
        questions.add(ReadingQuestion());
        widget.onChanged();
      });
    }
  }

  void _removeQuestion(int index) {
    if (questions.length > 1) {
      setState(() {
        questions[index].dispose();
        questions.removeAt(index);
        widget.onChanged();
      });
    }
  }

  @override
  void dispose() {
    for (final c in pageControllers) c.dispose();
    for (final q in questions) q.dispose();
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
        const SizedBox(height: AppSpacing.lg),
        _buildPagesSection(c),
        const SizedBox(height: AppSpacing.lg),
        _buildQuestionsSection(c),
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
          Icon(Icons.menu_book_rounded, color: c, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Write a short passage split across pages. Aim for 200–300 words per page.',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPagesSection(Color c) {
    final currentCtrl = pageControllers[currentPageIndex];
    final words = _wordCount(currentCtrl.text);
    final isOverLimit = words > _warnWordsPerPage;
    final totalPages = pageControllers.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Pages', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(width: AppSpacing.sm),
            _statusChip('$totalPages/5', c),
            const Spacer(),
            if (totalPages < 5)
              TextButton.icon(
                onPressed: _addPage,
                icon: Icon(Icons.add, size: 16, color: c),
                label: Text('Add Page', style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs)),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (totalPages > 1)
          SizedBox(
            height: 36,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: totalPages,
              itemBuilder: (_, i) {
                final isActive = i == currentPageIndex;
                final pw = _wordCount(pageControllers[i].text);
                final tooLong = pw > _warnWordsPerPage;
                return GestureDetector(
                  onTap: () => setState(() => currentPageIndex = i),
                  child: Container(
                    margin: const EdgeInsets.only(right: AppSpacing.xs),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: isActive ? c : Colors.white,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      border: Border.all(color: tooLong ? Colors.orange : (isActive ? c : AppColors.divider), width: isActive ? 0 : 1.5),
                      boxShadow: isActive ? [BoxShadow(color: c.withOpacity(0.25), blurRadius: 6)] : null,
                    ),
                    child: Text(
                      'Page ${i + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isActive ? AppColors.onPrimary : (tooLong ? Colors.orange : Colors.grey[700]),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: isOverLimit ? Colors.orange : c.withOpacity(0.25), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: isOverLimit ? Colors.orange.withOpacity(0.06) : c.withOpacity(0.05),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.md - 1)),
                  border: Border(bottom: BorderSide(color: isOverLimit ? Colors.orange.withOpacity(0.2) : c.withOpacity(0.1))),
                ),
                child: Row(
                  children: [
                    Icon(Icons.article_rounded, size: 16, color: isOverLimit ? Colors.orange : c),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Page ${currentPageIndex + 1} of $totalPages', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isOverLimit ? Colors.orange : c)),
                    const Spacer(),
                    _statusChip('$words / $_warnWordsPerPage words', isOverLimit ? Colors.orange : c),
                    if (totalPages > 1) ...[
                      const SizedBox(width: AppSpacing.sm),
                      GestureDetector(
                        onTap: _removePage,
                        child: Container(
                          padding: const EdgeInsets.all(AppSpacing.xs),
                          decoration: BoxDecoration(color: AppColors.danger.withOpacity(0.08), shape: BoxShape.circle),
                          child: Icon(Icons.close, size: 14, color: AppColors.danger),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              TextFormField(
                controller: currentCtrl,
                maxLines: 10,
                onChanged: (_) => widget.onChanged(),
                decoration: InputDecoration(
                  hintText: 'Write page ${currentPageIndex + 1} content here…',
                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(AppSpacing.md),
                ),
                style: const TextStyle(fontSize: 15, height: 1.6),
                validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuestionsSection(Color c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Questions', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(width: AppSpacing.sm),
            _statusChip('${questions.length}/5', c),
            const Spacer(),
            if (questions.length < 5)
              TextButton.icon(
                onPressed: _addQuestion,
                icon: Icon(Icons.add, size: 16, color: c),
                label: Text('Add Question', style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs)),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ...List.generate(questions.length, (qi) => _buildQuestionCard(qi, c)),
      ],
    );
  }

  Widget _buildQuestionCard(int index, Color c) {
    final rq = questions[index];
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.divider),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: c.withOpacity(0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.md - 1)),
              border: Border(bottom: BorderSide(color: c.withOpacity(0.1))),
            ),
            child: Row(
              children: [
                Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                  child: Center(child: Text('${index + 1}', style: const TextStyle(color: AppColors.onPrimary, fontSize: 12, fontWeight: FontWeight.bold))),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text('Question ${index + 1}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: c)),
                const Spacer(),
                if (questions.length > 1)
                  GestureDetector(
                    onTap: () => _removeQuestion(index),
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      decoration: BoxDecoration(color: AppColors.danger.withOpacity(0.08), shape: BoxShape.circle),
                      child: Icon(Icons.close, size: 14, color: AppColors.danger),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: rq.questionCtrl,
                  decoration: InputDecoration(
                    hintText: 'e.g. "What does Tom do first?"',
                    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      borderSide: BorderSide(color: c, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                    contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  ),
                  onChanged: (_) => widget.onChanged(),
                  validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Text('Options', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[600])),
                    const Spacer(),
                    if (rq.options.length < 4)
                      GestureDetector(
                        onTap: () => setState(() {
                          rq.options.add({'text': '', 'isCorrect': false});
                          rq.optionCtrls.add(TextEditingController());
                          widget.onChanged();
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                          decoration: BoxDecoration(color: c.withOpacity(0.08), borderRadius: BorderRadius.circular(AppRadii.sm)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add, size: 13, color: c),
                              const SizedBox(width: 3),
                              Text('Add', style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                ...List.generate(rq.options.length, (oi) {
                  final isCorrect = rq.options[oi]['isCorrect'] as bool;
                  final label = String.fromCharCode(65 + oi);
                  return Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: isCorrect ? Colors.green.shade50 : Colors.grey[50],
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                      border: Border.all(color: isCorrect ? AppColors.primary : AppColors.divider, width: isCorrect ? 2 : 1),
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => setState(() {
                            rq.options[oi]['isCorrect'] = !isCorrect;
                            widget.onChanged();
                          }),
                          child: Container(
                            width: 26, height: 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isCorrect ? AppColors.primary : Colors.white,
                              border: Border.all(color: isCorrect ? AppColors.primary : Colors.grey[400]!, width: 2),
                            ),
                            child: Center(
                              child: isCorrect
                                  ? const Icon(Icons.check, size: 14, color: AppColors.onPrimary)
                                  : Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[500])),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: TextField(
                            controller: rq.optionCtrls[oi],
                            decoration: InputDecoration(
                              hintText: isCorrect ? 'Correct answer…' : 'Wrong answer…',
                              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 12),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            style: TextStyle(fontSize: 13, color: isCorrect ? Colors.green.shade800 : Colors.black87),
                            onChanged: (_) => widget.onChanged(),
                          ),
                        ),
                        if (rq.options.length > 3)
                          GestureDetector(
                            onTap: () => setState(() {
                              rq.options.removeAt(oi);
                              rq.optionCtrls[oi].dispose();
                              rq.optionCtrls.removeAt(oi);
                              widget.onChanged();
                            }),
                            child: Icon(Icons.remove_circle_outline, size: 16, color: Colors.red[300]),
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}