import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/task_types/task_type_editor.dart';
import 'package:loringo_app/theme/app_theme.dart';
// import 'task_type_interface.dart';

class FillBlankTask extends StatefulWidget {
  final Color groupColor;
  final Map<String, dynamic>? existingData;
  final TaskEditorController controller;
  final VoidCallback onChanged;

  const FillBlankTask({
    super.key,
    required this.groupColor,
    this.existingData,
    required this.controller,
    required this.onChanged,
  });

  @override
  State<FillBlankTask> createState() => _FillBlankTaskState();
}

class _FillBlankTaskState extends State<FillBlankTask> implements TaskTypeEditor {
  List<Map<String, dynamic>> questionSegments = [];
  List<Map<String, dynamic>> options = [];
  List<TextEditingController> optionControllers = [];

  @override
  void initState() {
    super.initState();
    _initSegments();
    options = List.generate(3, (_) => {'text': '', 'isCorrect': false, 'blankIndex': null});
    optionControllers = List.generate(3, (_) => TextEditingController());
    if (widget.existingData != null) {
      loadData(widget.existingData!);
    }

    widget.controller.registerEditor(this);
  }

  // TaskTypeEditor implementation
  @override
  String get typeId => 'fill_blank';
  
  @override
  String get displayName => 'Fill in the Blank';
  
  @override
  String get defaultQuestion => 'Complete the sentence';

  void _initSegments() {
    questionSegments = [
      {'type': 'text', 'value': '', 'controller': TextEditingController()},
    ];
  }

  @override
  void loadData(Map<String, dynamic> data) {
    _loadSegmentsFromString(data['question'] as String? ?? '');
    final opts = data['options'] as List<dynamic>?;
    if (opts != null) {
      options.clear();
      for (var c in optionControllers) c.dispose();
      optionControllers.clear();
      for (final opt in opts) {
        final o = opt as Map<String, dynamic>;
        int? blankIdx = o['blankIndex'] as int?;
        final isCorrect = o['isCorrect'] as bool? ?? false;
        if (isCorrect && blankIdx == null) blankIdx = 0;
        options.add({
          'text': o['text'] ?? '',
          'isCorrect': isCorrect,
          'blankIndex': blankIdx,
        });
        optionControllers.add(TextEditingController(text: o['text'] ?? ''));
      }
    }
  }

  void _loadSegmentsFromString(String q) {
    final parts = q.split('___');
    for (final s in questionSegments) {
      if (s['type'] == 'text') (s['controller'] as TextEditingController).dispose();
    }
    questionSegments = [];
    for (int i = 0; i < parts.length; i++) {
      final ctrl = TextEditingController(text: parts[i]);
      questionSegments.add({'type': 'text', 'value': parts[i], 'controller': ctrl});
      if (i < parts.length - 1) {
        questionSegments.add({'type': 'blank', 'value': null, 'controller': null});
      }
    }
  }

  @override
  Map<String, dynamic> collectData() {
    return {
      'question': _buildQuestionString(),
      'options': List.generate(options.length, (i) => {
        'text': optionControllers[i].text.trim(),
        'isCorrect': options[i]['isCorrect'] ?? false,
        'blankIndex': options[i]['blankIndex'],
      }),
    };
  }

  String _buildQuestionString() {
    final buf = StringBuffer();
    for (final seg in questionSegments) {
      if (seg['type'] == 'text') {
        buf.write((seg['controller'] as TextEditingController).text.trim());
      } else {
        buf.write('___');
      }
    }
    return buf.toString();
  }

  @override
  String? validate() {
    final blanks = _blankCount;
    if (blanks == 0) return 'Add at least one blank';
    
    for (int b = 0; b < blanks; b++) {
      if (options.where((o) => o['isCorrect'] == true && o['blankIndex'] == b).isEmpty) {
        return 'Blank ${b + 1} has no correct answer';
      }
    }
    
    if (options.where((o) => o['isCorrect'] == false && optionControllers[options.indexOf(o)].text.isNotEmpty).isEmpty) {
      return 'Add at least one distractor';
    }
    return null;
  }

  int get _blankCount => questionSegments.where((s) => s['type'] == 'blank').length;
  Set<int> get _assignedBlankIndices => options
      .where((o) => o['isCorrect'] == true && o['blankIndex'] != null)
      .map((o) => o['blankIndex'] as int)
      .toSet();

  void _insertBlankAfter(int afterIndex) {
    setState(() {
      questionSegments.insert(afterIndex + 1, {'type': 'blank', 'value': null, 'controller': null});
      questionSegments.insert(afterIndex + 2, {'type': 'text', 'value': '', 'controller': TextEditingController()});
      widget.onChanged();
    });
  }

  void _removeBlank(int segIndex) {
    setState(() {
      final blankOrdinal = _blankOrdinalAt(segIndex);
      for (int i = 0; i < options.length; i++) {
        final idx = options[i]['blankIndex'] as int?;
        if (idx == blankOrdinal) {
          options[i]['isCorrect'] = false;
          options[i]['blankIndex'] = null;
        } else if (idx != null && idx > blankOrdinal) {
          options[i]['blankIndex'] = idx - 1;
        }
      }
      questionSegments.removeAt(segIndex);
      if (segIndex > 0 && segIndex < questionSegments.length &&
          questionSegments[segIndex - 1]['type'] == 'text' &&
          questionSegments[segIndex]['type'] == 'text') {
        final l = questionSegments[segIndex - 1]['controller'] as TextEditingController;
        final r = questionSegments[segIndex]['controller'] as TextEditingController;
        l.text = l.text + r.text;
        r.dispose();
        questionSegments.removeAt(segIndex);
      }
      widget.onChanged();
    });
  }

  int _blankOrdinalAt(int segIndex) {
    int count = 0;
    for (int i = 0; i < segIndex; i++) {
      if (questionSegments[i]['type'] == 'blank') count++;
    }
    return count;
  }

  void _addOption() {
    // Allow adding options even when no blanks exist
    final maxOptions = (_blankCount + 4).clamp(4, 8);
    if (options.length < maxOptions) {
      setState(() {
        options.add({'text': '', 'isCorrect': false, 'blankIndex': null});
        optionControllers.add(TextEditingController());
        widget.onChanged();
      });
    }
  }

  void _removeOption(int i) {
    if (options.length > (_blankCount + 1).clamp(3, 99)) {
      setState(() {
        options.removeAt(i);
        optionControllers[i].dispose();
        optionControllers.removeAt(i);
        widget.onChanged();
      });
    }
  }

  @override
  void dispose() {
    for (final seg in questionSegments) {
      if (seg['type'] == 'text') (seg['controller'] as TextEditingController).dispose();
    }
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
        _buildQuestionEditor(c),
        const SizedBox(height: AppSpacing.md),
        _buildOptionsHeader(c),
        const SizedBox(height: AppSpacing.md),
        ...List.generate(options.length, (i) => _buildOptionCard(i, c)),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: TextButton.icon(
            onPressed: _addOption,
            icon: Icon(Icons.add_circle_outline, color: c),
            label: Text('Add option (${options.length})', style: TextStyle(color: c)),
          ),
        ),
      ],
    );
  }

  Widget _buildQuestionEditor(Color c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Question', style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
        const SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.divider, width: 1.5),
          ),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < questionSegments.length; i++) ...[
                if (questionSegments[i]['type'] == 'text')
                  _buildTextSegment(i, c)
                else
                  _buildBlankChip(i, c),
              ],
              const SizedBox(height: AppSpacing.sm),
              if (questionSegments.isEmpty || questionSegments.last['type'] != 'blank')
                TextButton.icon(
                  onPressed: () => _insertBlankAfter(questionSegments.length - 1),
                  icon: Icon(Icons.add_box_outlined, color: c, size: 20),
                  label: Text('Add blank here', style: TextStyle(color: c, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
        if (_blankCount > 0) ...[
          const SizedBox(height: AppSpacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: c.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Text(
              '$_blankCount blank${_blankCount > 1 ? 's' : ''} added — assign each one below',
              style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTextSegment(int segIndex, Color c) {
    final ctrl = questionSegments[segIndex]['controller'] as TextEditingController;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(
          hintText: segIndex == 0 ? 'e.g. "Roses are"' : 'e.g. "and Violets are"',
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          filled: true,
          fillColor: Colors.grey[50],
          suffixIcon: _canInsertBlankAfter(segIndex)
              ? IconButton(
                  icon: Icon(Icons.add_box_outlined, color: c, size: 20),
                  onPressed: () => _insertBlankAfter(segIndex),
                )
              : null,
        ),
        style: const TextStyle(fontSize: 16),
        onChanged: (_) => widget.onChanged(),
      ),
    );
  }

  bool _canInsertBlankAfter(int segIndex) {
    if (segIndex + 1 >= questionSegments.length) return false;
    return questionSegments[segIndex + 1]['type'] != 'blank';
  }

  Widget _buildBlankChip(int segIndex, Color c) {
    final blankOrdinal = _blankOrdinalAt(segIndex);
    final isAssigned = _assignedBlankIndices.contains(blankOrdinal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: isAssigned ? c.withOpacity(0.1) : Colors.grey[200],
              borderRadius: BorderRadius.circular(AppRadii.sm),
              border: Border.all(color: isAssigned ? c : Colors.grey[400]!, width: isAssigned ? 2 : 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isAssigned ? Icons.check_circle : Icons.help_outline, size: 16, color: isAssigned ? c : Colors.grey[500]),
                const SizedBox(width: AppSpacing.xs),
                Text('Blank ${blankOrdinal + 1}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: isAssigned ? c : Colors.grey[600])),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          GestureDetector(
            onTap: () => _removeBlank(segIndex),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xs),
              decoration: BoxDecoration(color: AppColors.danger.withOpacity(0.08), shape: BoxShape.circle),
              child: Icon(Icons.close, size: 14, color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionsHeader(Color c) {
    return Row(
      children: [
        Text('Options', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(width: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
          decoration: BoxDecoration(
            color: c.withOpacity(0.1),
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Text(
            '${_assignedBlankIndices.length} correct · ${options.where((o) => !o['isCorrect']).length} distractors',
            style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  Widget _buildOptionCard(int index, Color c) {
    final blanks = _blankCount;
    final opt = options[index];
    final isCorrect = opt['isCorrect'] as bool;
    final assignedIndices = _assignedBlankIndices;

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
              // Only show dropdown if there are blanks
              if (blanks > 0)
                DropdownButton<int?>(
                  value: isCorrect ? opt['blankIndex'] as int? : null,
                  hint: Text('Distractor', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Distractor')),
                    for (int b = 0; b < blanks; b++)
                      DropdownMenuItem<int?>(
                        value: b,
                        enabled: !(assignedIndices.contains(b) && !(isCorrect && opt['blankIndex'] == b)),
                        child: Text(
                          'Blank ${b + 1} answer',
                          style: TextStyle(
                            fontSize: 13,
                            color: (assignedIndices.contains(b) && !(isCorrect && opt['blankIndex'] == b))
                                ? Colors.grey[400]
                                : c,
                          ),
                        ),
                      ),
                  ],
                  onChanged: (selected) => setState(() {
                    if (selected == null) {
                      options[index]['isCorrect'] = false;
                      options[index]['blankIndex'] = null;
                    } else {
                      // Reset all other options that might have this blank index
                      for (int i = 0; i < options.length; i++) {
                        if (i != index && options[i]['blankIndex'] == selected) {
                          options[i]['isCorrect'] = false;
                          options[i]['blankIndex'] = null;
                        }
                      }
                      options[index]['isCorrect'] = true;
                      options[index]['blankIndex'] = selected;
                    }
                    widget.onChanged();
                  }),
                )
              else
                // Show a disabled hint when no blanks exist
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Add blanks first',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
              if (options.length > (_blankCount + 1).clamp(3, 99))
                IconButton(
                  icon: Icon(Icons.remove_circle_outline, color: AppColors.danger, size: 20),
                  onPressed: () => _removeOption(index),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: optionControllers[index],
            decoration: InputDecoration(
              labelText: isCorrect && blanks > 0 && opt['blankIndex'] != null 
                  ? 'Answer for Blank ${(opt['blankIndex'] as int) + 1}' 
                  : (blanks > 0 ? 'Distractor word' : 'Option text'),
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: Colors.grey[50],
            ),
            onChanged: (_) => widget.onChanged(),
            validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
          ),
        ],
      ),
    );
    }
}