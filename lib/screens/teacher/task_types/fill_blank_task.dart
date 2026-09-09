import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/task_types/task_type_editor.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';

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

class _FillBlankTaskState extends State<FillBlankTask> with TaskTypeEditorMixin implements TaskTypeEditor {
  final TextEditingController _sentenceController = TextEditingController();
  final FocusNode _sentenceFocusNode = FocusNode();

  List<Map<String, dynamic>> options = [];
  List<TextEditingController> optionControllers = [];

  @override
  void initState() {
    super.initState();
    options = List.generate(3, (_) => {'text': '', 'isCorrect': false, 'blankIndex': null});
    optionControllers = List.generate(3, (_) => TextEditingController());
    if (widget.existingData != null) {
      loadData(widget.existingData!);
    }
    widget.controller.registerEditor(this);
  }

  @override
  String get typeId => 'fill_blank';

  @override
  String get displayName => 'Fill in the Blank';

  @override
  String get defaultQuestion => 'Complete the sentence';

  /// Number of "___" markers currently in the sentence text.
  int get _blankCount => '___'.allMatches(_sentenceController.text).length;

  Set<int> get _assignedBlankIndices => options
      .where((o) => o['isCorrect'] == true && o['blankIndex'] != null)
      .map((o) => o['blankIndex'] as int)
      .toSet();

  @override
  void loadData(Map<String, dynamic> data) {
    _sentenceController.text = data['question'] as String? ?? '';

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

  @override
  Map<String, dynamic> collectData() {
    return {
      'question': _sentenceController.text.trim(),
      'options': List.generate(options.length, (i) => {
        'text': optionControllers[i].text.trim(),
        'isCorrect': options[i]['isCorrect'] ?? false,
        'blankIndex': options[i]['blankIndex'],
      }),
    };
  }

  @override
  String? validate() {
    if (_sentenceController.text.trim().isEmpty) return 'teacher.fill_blank_task.writeSentenceFirst'.tr();
    final blanks = _blankCount;
    if (blanks == 0) return 'teacher.fill_blank_task.addAtLeastOneBlank'.tr();

    for (int b = 0; b < blanks; b++) {
      if (options.where((o) => o['isCorrect'] == true && o['blankIndex'] == b).isEmpty) {
        return 'teacher.fill_blank_task.blankHasNoCorrectAnswer'.tr(namedArgs: {'number': '${b + 1}'});
      }
    }

    if (options.where((o) => o['isCorrect'] == false && optionControllers[options.indexOf(o)].text.isNotEmpty).isEmpty) {
      return 'teacher.fill_blank_task.addAtLeastOneDistractor'.tr();
    }
    return null;
  }

  /// Inserts "___" at the current cursor position in the sentence
  /// field. If nothing has been focused/selected yet (selection is
  /// invalid, e.g. right after the field first renders), falls back to
  /// appending at the end -- same simple, predictable behavior a
  /// teacher would expect from "just type here".
  void _insertBlankAtCursor() {
    final text = _sentenceController.text;
    final selection = _sentenceController.selection;

    final insertAt = selection.isValid ? selection.start : text.length;
    final before = text.substring(0, insertAt);
    final after = text.substring(insertAt);

    // Pad with a space on either side if the insertion point doesn't
    // already have whitespace there, so "___" never gets glued directly
    // onto an adjacent word (e.g. typing "Good" then inserting right
    // after it should give "Good ___", not "Good___").
    final needsSpaceBefore = before.isNotEmpty && !before.endsWith(' ');
    final needsSpaceAfter = after.isNotEmpty && !after.startsWith(' ');

    final insertion = '${needsSpaceBefore ? ' ' : ''}___${needsSpaceAfter ? ' ' : ''}';
    final newText = before + insertion + after;
    final newCursorPos = insertAt + insertion.length;

    setState(() {
      _sentenceController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newCursorPos),
      );
    });
    widget.onChanged();
    _sentenceFocusNode.requestFocus();
  }

  void _addOption() {
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
    _sentenceController.dispose();
    _sentenceFocusNode.dispose();
    for (var c in optionControllers) c.dispose();
    super.dispose();
  }

  @override
  Widget buildEditor(BuildContext context) => build(context);

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return _buildEditor();
  }

  Widget _buildEditor() {
    final c = widget.groupColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSentenceEditor(c),
        const SizedBox(height: AppSpacing.md),
        _buildOptionsHeader(c),
        const SizedBox(height: AppSpacing.md),
        ...List.generate(options.length, (i) => _buildOptionCard(i, c)),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: TextButton.icon(
            onPressed: _addOption,
            icon: Icon(Icons.add_circle_outline, color: c),
            label: Text(
              'teacher.fill_blank_task.addOption'.tr(namedArgs: {'count': '${options.length}'}),
              style: TextStyle(color: c),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSentenceEditor(Color c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('teacher.fill_blank_task.question'.tr(), style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
        const SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.divider, width: 1.5),
          ),
          child: TextField(
            controller: _sentenceController,
            focusNode: _sentenceFocusNode,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'teacher.fill_blank_task.sentenceHint'.tr(),
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(AppSpacing.md),
            ),
            style: const TextStyle(fontSize: 16, height: 1.5),
            onChanged: (_) {
              setState(() {});
              widget.onChanged();
            },
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton.icon(
          onPressed: _insertBlankAtCursor,
          icon: Icon(Icons.add_box_outlined, color: c, size: 20),
          label: Text('teacher.fill_blank_task.addBlank'.tr(), style: TextStyle(color: c, fontWeight: FontWeight.w600)),
          style: TextButton.styleFrom(
            backgroundColor: c.withOpacity(0.08),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.pill)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'teacher.fill_blank_task.addBlankHint'.tr(),
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
        ),
        // NEW: read-only preview showing how the sentence will actually
        // look, with each "___" rendered as a real "Blank N" bubble
        // instead of raw underscores -- this is purely visual, the
        // underlying _sentenceController.text (and what gets saved) is
        // unchanged. Only shown once there's something to preview.
        if (_sentenceController.text.trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text('teacher.fill_blank_task.preview'.tr(), style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: c.withOpacity(0.04),
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(color: c.withOpacity(0.2)),
            ),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              runSpacing: 8,
              children: _buildPreviewChunks(c),
            ),
          ),
        ],
        if (_blankCount > 0) ...[
          const SizedBox(height: AppSpacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: c.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Text(
              'teacher.fill_blank_task.blanksAddedBanner'.plural(_blankCount),
              style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildPreviewChunks(Color c) {
    final text = _sentenceController.text;
    final parts = text.split('___');
    final chunks = <Widget>[];

    for (int i = 0; i < parts.length; i++) {
      final chunk = parts[i].trim();
      if (chunk.isNotEmpty) {
        chunks.add(Text(chunk, style: const TextStyle(fontSize: 15, color: Colors.black87)));
      }
      if (i < parts.length - 1) {
        final blankOrdinal = i;
        final isAssigned = _assignedBlankIndices.contains(blankOrdinal);
        chunks.add(_previewBlankBubble(blankOrdinal, isAssigned, c));
      }
    }
    return chunks;
  }

  Widget _previewBlankBubble(int ordinal, bool isAssigned, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isAssigned ? c.withOpacity(0.15) : Colors.grey[200],
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: isAssigned ? c : Colors.grey[400]!, width: isAssigned ? 2 : 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isAssigned ? Icons.check_circle : Icons.help_outline, size: 14, color: isAssigned ? c : Colors.grey[500]),
          const SizedBox(width: 4),
          Text('teacher.fill_blank_task.blankOrdinal'.tr(namedArgs: {'number': '${ordinal + 1}'}),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isAssigned ? c : Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildOptionsHeader(Color c) {
    return Row(
      children: [
        Text('teacher.fill_blank_task.options'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(width: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
          decoration: BoxDecoration(
            color: c.withOpacity(0.1),
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Text(
            'teacher.fill_blank_task.correctDistractorsCount'.tr(namedArgs: {
              'correct': '${_assignedBlankIndices.length}',
              'distractors': '${options.where((o) => !o['isCorrect']).length}',
            }),
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
              Text('teacher.fill_blank_task.optionOrdinal'.tr(namedArgs: {'number': '${index + 1}'}), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const Spacer(),
              if (blanks > 0)
                DropdownButton<int?>(
                  value: isCorrect ? opt['blankIndex'] as int? : null,
                  hint: Text('teacher.fill_blank_task.distractor'.tr(), style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  items: [
                    DropdownMenuItem<int?>(value: null, child: Text('teacher.fill_blank_task.distractor'.tr())),
                    for (int b = 0; b < blanks; b++)
                      DropdownMenuItem<int?>(
                        value: b,
                        enabled: !(assignedIndices.contains(b) && !(isCorrect && opt['blankIndex'] == b)),
                        child: Text(
                          'teacher.fill_blank_task.blankAnswerOrdinal'.tr(namedArgs: {'number': '${b + 1}'}),
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(4)),
                  child: Text('teacher.fill_blank_task.addBlanksFirst'.tr(), style: TextStyle(fontSize: 12, color: Colors.grey[600])),
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
                  ? 'teacher.fill_blank_task.answerForBlank'.tr(namedArgs: {'number': '${(opt['blankIndex'] as int) + 1}'})
                  : (blanks > 0 ? 'teacher.fill_blank_task.distractorWord'.tr() : 'teacher.fill_blank_task.optionText'.tr()),
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: Colors.grey[50],
            ),
            onChanged: (_) => widget.onChanged(),
            validator: (v) => v?.isEmpty ?? true ? 'teacher.fill_blank_task.required'.tr() : null,
          ),
        ],
      ),
    );
  }
}