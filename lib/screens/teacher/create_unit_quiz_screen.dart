import 'package:flutter/material.dart';
import 'package:loringo_app/services/database/database.dart';

// ── Question model ────────────────────────────────────────────────────────────
class _QuizQuestion {
  TextEditingController questionCtrl;
  List<TextEditingController> optionCtrls;
  int correctIndex;

  _QuizQuestion({
    String question = '',
    List<String> options = const ['', '', '', ''],
    this.correctIndex = 0,
  })  : questionCtrl = TextEditingController(text: question),
        optionCtrls  = options.map((o) => TextEditingController(text: o)).toList();

  void dispose() {
    questionCtrl.dispose();
    for (final c in optionCtrls) c.dispose();
  }
}

class CreatePersonalizedUnitQuizScreen extends StatefulWidget {
  final String groupId;
  final String contentId;
  final String unitId;
  final Color groupColor;
  // Edit mode
  final String? quizId;
  final Map<String, dynamic>? existingData;

  const CreatePersonalizedUnitQuizScreen({
    super.key,
    required this.groupId,
    required this.contentId,
    required this.unitId,
    required this.groupColor,
    this.quizId,
    this.existingData,
  });

  bool get isEditing => quizId != null;

  @override
  State<CreatePersonalizedUnitQuizScreen> createState() =>
      _CreatePersonalizedUnitQuizScreenState();
}

class _CreatePersonalizedUnitQuizScreenState
    extends State<CreatePersonalizedUnitQuizScreen> {
  final _formKey = GlobalKey<FormState>();
  final Database _db = Database();
  final TextEditingController _titleCtrl = TextEditingController();

  int _passingScore = 1;
  int _xpReward     = 50;

  List<_QuizQuestion> _questions = [];
  bool _isLoadingQuestions = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    if (widget.isEditing && widget.existingData != null) {
      // Pre-fill header fields
      _titleCtrl.text  = widget.existingData!['title'] as String? ?? '';
      _passingScore    = (widget.existingData!['passingScore'] as num?)?.toInt() ?? 1;
      _xpReward        = (widget.existingData!['xpReward'] as num?)?.toInt() ?? 50;
      // Load questions from the subcollection
      _isLoadingQuestions = true;
      _loadExistingQuestions();
    } else {
      // New quiz — start with 2 blank questions
      _questions = [_QuizQuestion(), _QuizQuestion()];
    }
  }

  Future<void> _loadExistingQuestions() async {
    try {
      final snap = await _db.getUnitQuizQuestions(widget.quizId!);

      final loaded = snap.docs.map((doc) {
        final d = doc.data() as Map<String, dynamic>;
        final opts = List<String>.from((d['options'] as List? ?? []).map((e) => e.toString()));
        // Pad to 4 if needed (safety)
        while (opts.length < 4) opts.add('');
        return _QuizQuestion(
          question:     d['question'] as String? ?? '',
          options:      opts,
          correctIndex: (d['correctIndex'] as num?)?.toInt() ?? 0,
        );
      }).toList();

      if (loaded.isEmpty) loaded.add(_QuizQuestion());

      setState(() {
        _questions          = loaded;
        _isLoadingQuestions = false;
        // Re-clamp passing score now that we know question count
        _passingScore = _passingScore.clamp(1, _questions.length);
      });
    } catch (e) {
      setState(() {
        _questions          = [_QuizQuestion(), _QuizQuestion()];
        _isLoadingQuestions = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load existing questions: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    for (final q in _questions) q.dispose();
    super.dispose();
  }

  // ── Question operations ────────────────────────────────────────────────────

  void _addQuestion() {
    if (_questions.length < 20) setState(() => _questions.add(_QuizQuestion()));
  }

  void _removeQuestion(int index) {
    if (_questions.length > 1) {
      setState(() {
        _questions[index].dispose();
        _questions.removeAt(index);
        _passingScore = _passingScore.clamp(1, _questions.length);
      });
    }
  }

  // ── Validation ─────────────────────────────────────────────────────────────

  String? _validateTitle(String? v) {
    if (v == null || v.trim().isEmpty) return 'Title is required';
    if (v.trim().length < 3) return 'Title must be at least 3 characters';
    if (v.trim().length > 80) return 'Title must be 80 characters or fewer';
    return null;
  }

  bool _validateQuestions() {
    for (int i = 0; i < _questions.length; i++) {
      final q = _questions[i];
      if (q.questionCtrl.text.trim().isEmpty) {
        _showSnack('Question ${i + 1}: question text is required');
        return false;
      }
      for (int o = 0; o < 4; o++) {
        if (q.optionCtrls[o].text.trim().isEmpty) {
          _showSnack('Question ${i + 1}: option ${String.fromCharCode(65 + o)} is required');
          return false;
        }
      }
    }
    return true;
  }

  void _showSnack(String msg, {Color color = Colors.red}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_validateQuestions()) return;

    setState(() => _isSaving = true);
    try {
      final questionsList = _questions.asMap().entries.map((e) => {
        'question':     e.value.questionCtrl.text.trim(),
        'options':      e.value.optionCtrls.map((c) => c.text.trim()).toList(),
        'correctIndex': e.value.correctIndex,
        'order':        e.key + 1,
      }).toList();

      if (widget.isEditing) {
        // Update: rewrite the whole quiz (header + questions subcollection)
        await _db.createPersonalizedUnitQuiz(
          contentId:    widget.contentId,
          unitId:       widget.unitId,
          quizId:       widget.quizId!,   // same ID — overwrites header doc
          title:        _titleCtrl.text.trim(),
          questions:    questionsList,
          passingScore: _passingScore,
          xpReward:     _xpReward,
        );
        if (mounted) {
          _showSnack('✅ Unit quiz updated successfully', color: Colors.green);
          Navigator.pop(context);
        }
      } else {
        final quizId = 'unit_quiz_${DateTime.now().millisecondsSinceEpoch}';
        await _db.createPersonalizedUnitQuiz(
          contentId:    widget.contentId,
          unitId:       widget.unitId,
          quizId:       quizId,
          title:        _titleCtrl.text.trim(),
          questions:    questionsList,
          passingScore: _passingScore,
          xpReward:     _xpReward,
        );
        if (mounted) {
          _showSnack('✅ Unit quiz created successfully', color: Colors.green);
          Navigator.pop(context);
        }
      }
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── UI builders ────────────────────────────────────────────────────────────

  Widget _buildSettingsCard() {
    final c = widget.groupColor;
    final n = _questions.isEmpty ? 1 : _questions.length;

    return Column(children: [
      // Title
      TextFormField(
        controller: _titleCtrl,
        decoration: InputDecoration(
          labelText: 'Quiz Title',
          hintText: 'e.g., Unit 1 Final Test',
          prefixIcon: Icon(Icons.assignment_outlined, color: c),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c, width: 2)),
          filled: true, fillColor: Colors.white,
        ),
        validator: _validateTitle,
      ),
      const SizedBox(height: 16),

      // Passing score
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.withOpacity(0.3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.trending_up, color: Colors.blue, size: 18),
            const SizedBox(width: 8),
            const Text('Passing Score', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const Spacer(),
            RichText(text: TextSpan(children: [
              TextSpan(text: '$_passingScore / $n', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue)),
              TextSpan(text: '  (${((_passingScore / n) * 100).round()}%)', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ])),
          ]),
          Slider(value: _passingScore.toDouble(), min: 1, max: n.toDouble(), divisions: n > 1 ? n - 1 : 1, activeColor: Colors.blue, label: '$_passingScore / $n', onChanged: (v) => setState(() => _passingScore = v.round())),
          Text('Students must answer at least $_passingScore out of $n questions correctly to pass', style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
      ),
      const SizedBox(height: 12),

      // XP reward
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: Colors.amber.withOpacity(0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber.withOpacity(0.35))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
            const SizedBox(width: 8),
            const Text('XP Reward', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const Spacer(),
            Text('$_xpReward XP', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.amber)),
          ]),
          Slider(value: _xpReward.toDouble(), min: 0, max: 100, divisions: 20, activeColor: Colors.amber, label: '$_xpReward XP', onChanged: (v) => setState(() => _xpReward = v.round())),
          const Text('Awarded on passing this graded test (max 100 XP)', style: TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
      ),
      const SizedBox(height: 12),

      // Info banner
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.red.withOpacity(0.07), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.withOpacity(0.25))),
        child: Row(children: [
          Icon(Icons.info_outline, color: Colors.red.shade700, size: 20),
          const SizedBox(width: 12),
          const Expanded(child: Text('This is a graded exam. Scores will be reported to parents.', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ]),
      ),
    ]);
  }

  Widget _buildQuestionCard(int index) {
    final q = _questions[index];
    final c = widget.groupColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.withOpacity(0.2), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: c.withOpacity(0.06),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            border: Border(bottom: BorderSide(color: c.withOpacity(0.1))),
          ),
          child: Row(children: [
            Container(width: 28, height: 28, decoration: BoxDecoration(color: c, shape: BoxShape.circle), child: Center(child: Text('${index + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)))),
            const SizedBox(width: 10),
            Text('Question ${index + 1}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: c)),
            const Spacer(),
            if (_questions.length > 1)
              GestureDetector(
                onTap: () => _removeQuestion(index),
                child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle), child: Icon(Icons.close, size: 16, color: Colors.red.shade400)),
              ),
          ]),
        ),

        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Question text
            TextFormField(
              controller: q.questionCtrl,
              decoration: InputDecoration(
                hintText: 'e.g. "What does \'Stand up\' mean?"',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c, width: 2)),
                filled: true, fillColor: Colors.grey.shade50,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                prefixIcon: Icon(Icons.help_outline_rounded, color: Colors.grey.shade400, size: 18),
              ),
              maxLines: 2,
              validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
            ),
            const SizedBox(height: 14),

            Text('Options', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
            const SizedBox(height: 8),

            // Options A–D
            ...List.generate(4, (oi) {
              final label     = String.fromCharCode(65 + oi);
              final isCorrect = q.correctIndex == oi;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isCorrect ? Colors.green.shade50 : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isCorrect ? Colors.green : Colors.grey.shade200, width: isCorrect ? 2 : 1),
                ),
                child: Row(children: [
                  GestureDetector(
                    onTap: () => setState(() => q.correctIndex = oi),
                    child: Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: isCorrect ? Colors.green : Colors.white, border: Border.all(color: isCorrect ? Colors.green : Colors.grey.shade400, width: 2)),
                      child: Center(child: isCorrect ? const Icon(Icons.check, size: 15, color: Colors.white) : Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade500))),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: q.optionCtrls[oi],
                      decoration: InputDecoration(
                        hintText: isCorrect ? 'Correct answer...' : 'Wrong option...',
                        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                        border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero,
                      ),
                      style: TextStyle(fontSize: 14, color: isCorrect ? Colors.green.shade800 : Colors.black87),
                    ),
                  ),
                ]),
              );
            }),

            // Hint
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.green.withOpacity(0.06), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                const Icon(Icons.check_circle_outline, size: 14, color: Colors.green),
                const SizedBox(width: 6),
                Flexible(child: Text('Tap a letter to mark it as the correct answer (currently: ${String.fromCharCode(65 + q.correctIndex)})', style: const TextStyle(fontSize: 11, color: Colors.green))),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = widget.groupColor;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: c,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.isEditing ? 'Edit Unit Quiz' : 'Create Unit Quiz',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
              child: Text('${_questions.length} Q', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: _isLoadingQuestions
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              CircularProgressIndicator(color: c),
              const SizedBox(height: 16),
              Text('Loading questions...', style: TextStyle(color: Colors.grey.shade500)),
            ]))
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _buildSettingsCard(),
                  const SizedBox(height: 28),

                  // Questions header
                  Row(children: [
                    Text('Questions', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                      child: Text('${_questions.length}/20', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c)),
                    ),
                    const Spacer(),
                    if (_questions.length < 20)
                      TextButton.icon(
                        onPressed: _addQuestion,
                        icon: Icon(Icons.add, size: 18, color: c),
                        label: Text('Add', style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 13)),
                        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                      ),
                  ]),
                  const SizedBox(height: 4),
                  Text('Each question has 4 options (A–D). Tap a letter to mark the correct answer.', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  const SizedBox(height: 16),

                  // Question cards
                  ...List.generate(_questions.length, (i) => _buildQuestionCard(i)),

                  // Add question button (bottom)
                  if (_questions.length < 20)
                    GestureDetector(
                      onTap: _addQuestion,
                      child: Container(
                        width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16),
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.withOpacity(0.3), width: 1.5)),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.add_circle_outline, color: c, size: 20),
                          const SizedBox(width: 8),
                          Text('Add Question (${_questions.length}/20)', style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 14)),
                        ]),
                      ),
                    ),

                  // Save button
                  SizedBox(
                    width: double.infinity, height: 56,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c, disabledBackgroundColor: Colors.grey.shade400,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0,
                      ),
                      child: _isSaving
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text(widget.isEditing ? 'Save Changes' : 'Create Quiz', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 24),
                ]),
              ),
            ),
    );
  }
}