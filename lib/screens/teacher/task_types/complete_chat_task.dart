import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/task_types/task_type_editor.dart';
import 'package:loringo_app/theme/app_theme.dart';
// import 'task_type_interface.dart';

class ChatTurn {
  TextEditingController bubbleCtrl;
  List<Map<String, dynamic>> options;
  List<TextEditingController> optionCtrls;
  bool expanded;

  ChatTurn({
    String bubble = '',
    List<Map<String, dynamic>>? options,
    this.expanded = true,
  })  : bubbleCtrl = TextEditingController(text: bubble),
        options = options ??
            List.generate(3, (_) => {'text': '', 'isCorrect': false}),
        optionCtrls = List.generate(3, (_) => TextEditingController());

  void dispose() {
    bubbleCtrl.dispose();
    for (var c in optionCtrls) c.dispose();
  }
}

class CompleteChatTask extends StatefulWidget {
  final Color groupColor;
  final Map<String, dynamic>? existingData;
  final TaskEditorController controller;
  final VoidCallback onChanged;

  const CompleteChatTask({
    super.key,
    required this.groupColor,
    this.existingData,
    required this.controller,
    required this.onChanged,
  });

  @override
  State<CompleteChatTask> createState() => _CompleteChatTaskState();
}

class _CompleteChatTaskState extends State<CompleteChatTask> with TaskTypeEditorMixin implements TaskTypeEditor {
  List<ChatTurn> turns = [];

  @override
  void initState() {
    super.initState();
    turns = [ChatTurn()];
    if (widget.existingData != null) {
      loadData(widget.existingData!);
    }

    widget.controller.registerEditor(this);
  }

  // TaskTypeEditor implementation
  @override
  String get typeId => 'complete_the_chat';
  
  @override
  String get displayName => 'Complete the Chat';
  
  @override
  String get defaultQuestion => 'Complete the conversation';

  @override
  void loadData(Map<String, dynamic> data) {
    final turnsData = data['turns'] as List<dynamic>?;
    if (turnsData != null && turnsData.isNotEmpty) {
      for (var t in turns) t.dispose();
      turns.clear();
      for (var turnData in turnsData) {
        final t = turnData as Map<String, dynamic>;
        final bubble = t['bubble'] as String? ?? '';
        final rawOpts = List<Map<String, dynamic>>.from(t['options'] ?? []);
        final turn = ChatTurn(bubble: bubble, expanded: false);
        for (int i = 0; i < rawOpts.length && i < turn.options.length; i++) {
          turn.options[i] = {
            'text': rawOpts[i]['text'] ?? '',
            'isCorrect': rawOpts[i]['isCorrect'] ?? false,
          };
          turn.optionCtrls[i].text = rawOpts[i]['text'] ?? '';
        }
        turns.add(turn);
      }
    }
  }

  @override
  Map<String, dynamic> collectData() {
    return {
      'turns': turns.map((turn) {
        for (int i = 0; i < turn.options.length; i++) {
          turn.options[i]['text'] = turn.optionCtrls[i].text.trim();
        }
        return {
          'bubble': turn.bubbleCtrl.text.trim(),
          'options': List<Map<String, dynamic>>.from(turn.options),
        };
      }).toList(),
    };
  }

  @override
  String? validate() {
    for (int i = 0; i < turns.length; i++) {
      final turn = turns[i];
      if (turn.bubbleCtrl.text.trim().isEmpty) {
        return 'Turn ${i + 1}: chat message cannot be empty';
      }
      bool hasCorrect = false;
      int filled = 0;
      for (int j = 0; j < turn.options.length; j++) {
        if (turn.optionCtrls[j].text.trim().isNotEmpty) filled++;
        if (turn.options[j]['isCorrect'] == true) hasCorrect = true;
      }
      if (filled < 3) {
        return 'Turn ${i + 1}: provide at least 3 reply options';
      }
      if (!hasCorrect) {
        return 'Turn ${i + 1}: mark one reply as correct';
      }
    }
    return null;
  }

  @override
  void dispose() {
    for (var turn in turns) turn.dispose();
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
        ...List.generate(turns.length, (i) => _buildTurnCard(i, c)),
        if (turns.length < 6)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: TextButton.icon(
              onPressed: _addTurn,
              icon: Icon(Icons.add_comment_outlined, color: c),
              label: Text('Add turn (${turns.length}/6)', style: TextStyle(color: c)),
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
          Icon(Icons.chat_bubble_outline, color: c, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Each turn = one chat bubble the student must reply to. Turns play in order.',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTurnCard(int index, Color c) {
    final turn = turns[index];
    final hasCorrect = turn.options.any((o) => o['isCorrect'] == true);
    
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: turn.expanded ? c : AppColors.divider, width: turn.expanded ? 2 : 1),
        borderRadius: BorderRadius.circular(AppRadii.md),
        color: Colors.white,
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() {
              turn.expanded = !turn.expanded;
              widget.onChanged();
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
              decoration: BoxDecoration(
                color: turn.expanded ? c.withOpacity(0.05) : Colors.grey[50],
                borderRadius: BorderRadius.circular(turn.expanded ? AppRadii.sm : AppRadii.md),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                    child: Center(
                      child: Text('${index + 1}', style: const TextStyle(color: AppColors.onPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      turn.bubbleCtrl.text.isNotEmpty ? turn.bubbleCtrl.text : 'Turn ${index + 1} — tap to edit',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: turn.bubbleCtrl.text.isNotEmpty ? Colors.black87 : Colors.grey,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!turn.expanded) ...[
                    _statusChip(hasCorrect ? '✓ ready' : 'needs reply', hasCorrect ? c : Colors.orange),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Icon(turn.expanded ? Icons.expand_less : Icons.expand_more, color: Colors.grey),
                  if (turns.length > 1)
                    GestureDetector(
                      onTap: () => _removeTurn(index),
                      child: Container(
                        margin: const EdgeInsets.only(left: AppSpacing.sm),
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: AppColors.danger.withOpacity(0.08), shape: BoxShape.circle),
                        child: Icon(Icons.close, size: 14, color: AppColors.danger),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (turn.expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 20),
                  Text('Chat bubble message', style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                  const SizedBox(height: AppSpacing.xs),
                  TextFormField(
                    controller: turn.bubbleCtrl,
                    decoration: InputDecoration(
                      hintText: 'e.g. "Good morning, Leo! How are you?"',
                      prefixIcon: Icon(Icons.chat_bubble_outline, color: c, size: 20),
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    maxLines: 2,
                    onChanged: (_) => widget.onChanged(),
                    validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Text('Reply options (3–4)', style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                      const Spacer(),
                      if (turn.options.length < 4)
                        GestureDetector(
                          onTap: () => _addOption(index),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                            decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(AppRadii.sm)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add, size: 14, color: c),
                                const SizedBox(width: AppSpacing.xs),
                                Text('Add reply', style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ...List.generate(turn.options.length, (oi) {
                    final isCorrect = turn.options[oi]['isCorrect'] as bool;
                    return Container(
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: isCorrect ? c.withOpacity(0.04) : Colors.grey[50],
                        border: Border.all(color: isCorrect ? c : AppColors.divider, width: isCorrect ? 1.5 : 1),
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                      ),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => setState(() {
                              for (int i = 0; i < turn.options.length; i++) {
                                turn.options[i]['isCorrect'] = false;
                              }
                              turn.options[oi]['isCorrect'] = !isCorrect;
                              widget.onChanged();
                            }),
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isCorrect ? c : Colors.white,
                                border: Border.all(color: isCorrect ? c : Colors.grey[400]!, width: 2),
                              ),
                              child: isCorrect
                                  ? Icon(Icons.check, size: 13, color: AppColors.onPrimary)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: TextField(
                              controller: turn.optionCtrls[oi],
                              decoration: InputDecoration(
                                hintText: isCorrect ? 'Correct reply…' : 'Wrong reply…',
                                hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              style: const TextStyle(fontSize: 14),
                              onChanged: (_) => widget.onChanged(),
                            ),
                          ),
                          if (turn.options.length > 3)
                            GestureDetector(
                              onTap: () => _removeOption(index, oi),
                              child: Icon(Icons.remove_circle_outline, size: 18, color: Colors.red[300]),
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

  void _addTurn() {
    if (turns.length < 6) {
      setState(() {
        for (var t in turns) t.expanded = false;
        turns.add(ChatTurn());
        widget.onChanged();
      });
    }
  }

  void _removeTurn(int index) {
    if (turns.length > 1) {
      setState(() {
        turns[index].dispose();
        turns.removeAt(index);
        widget.onChanged();
      });
    }
  }

  void _addOption(int turnIndex) {
    if (turns[turnIndex].options.length < 4) {
      setState(() {
        turns[turnIndex].options.add({'text': '', 'isCorrect': false});
        turns[turnIndex].optionCtrls.add(TextEditingController());
        widget.onChanged();
      });
    }
  }

  void _removeOption(int turnIndex, int optionIndex) {
    if (turns[turnIndex].options.length > 3) {
      setState(() {
        turns[turnIndex].options.removeAt(optionIndex);
        turns[turnIndex].optionCtrls[optionIndex].dispose();
        turns[turnIndex].optionCtrls.removeAt(optionIndex);
        widget.onChanged();
      });
    }
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