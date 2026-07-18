import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_screen_header.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

// NOTE: previously had a Scaffold.appBar (solid `groupColor` bar with a
// "N Q" pill in actions:). Replaced with TeacherScreenHeader to match the
// rest of the hierarchy. Also replaced every hardcoded Colors.* with
// AppColors tokens (blue → AppColors.info, purple → left as a deliberate
// distinct accent for the Attempts card since neither AppColors.info nor
// AppColors.warning read correctly there — FLAGGED below for CJ to confirm
// or pick a token).

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

  int _maxAttempts = 0;

  @override
  void initState() {
    super.initState();

    if (widget.isEditing && widget.existingData != null) {
      // Pre-fill header fields
      _titleCtrl.text  = widget.existingData!['title'] as String? ?? '';
      _passingScore    = (widget.existingData!['passingScore'] as num?)?.toInt() ?? 1;
      _xpReward        = (widget.existingData!['xpReward'] as num?)?.toInt() ?? 50;

      // load attempts configuration
      _maxAttempts = (widget.existingData!['maxAttempts'] as num?)?.toInt() ?? 0;

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

  void _showSnack(String msg, {Color color = AppColors.danger}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_validateQuestions()) return;

    if (_maxAttempts < 1 || _maxAttempts > 5) {
      _showSnack('Please set maximum attempts (1-5)', color: AppColors.warning);
      return;
    }

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
        await _db.updatePersonalizedUnitQuiz(
          quizId: widget.quizId!, 
          title: _titleCtrl.text.trim(), 
          questions: questionsList,
          passingScore: _passingScore, 
          xpReward: _xpReward, 
          maxAttempts: _maxAttempts,
        );
        if (mounted) {
          _showSnack('Unit quiz updated successfully', color: AppColors.success);
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
          maxAttempts: _maxAttempts,
        );
        if (mounted) {
          _showSnack('Unit quiz created successfully', color: AppColors.success);
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
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md), borderSide: const BorderSide(color: AppColors.divider)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md), borderSide: BorderSide(color: c, width: 2)),
          filled: true, fillColor: Colors.white,
        ),
        validator: _validateTitle,
      ),
      const SizedBox(height: AppSpacing.md),

      // Passing score
      Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(color: AppColors.info.withOpacity(0.05), borderRadius: BorderRadius.circular(AppRadii.md), border: Border.all(color: AppColors.info.withOpacity(0.3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.trending_up, color: AppColors.info, size: 18),
            const SizedBox(width: 8),
            const Text('Passing Score', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const Spacer(),
            RichText(text: TextSpan(children: [
              TextSpan(text: '$_passingScore / $n', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.info)),
              TextSpan(text: '  (${((_passingScore / n) * 100).round()}%)', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ])),
          ]),
          Slider(value: _passingScore.toDouble(), min: 1, max: n.toDouble(), divisions: n > 1 ? n - 1 : 1, activeColor: AppColors.info, label: '$_passingScore / $n', onChanged: (v) => setState(() => _passingScore = v.round())),
          Text('Students must answer at least $_passingScore out of $n questions correctly to pass', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
        ]),
      ),
      const SizedBox(height: AppSpacing.sm),

      // XP reward
      Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.06), borderRadius: BorderRadius.circular(AppRadii.md), border: Border.all(color: AppColors.warning.withOpacity(0.35))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.star_rounded, color: AppColors.warning, size: 18),
            const SizedBox(width: 8),
            const Text('XP Reward', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const Spacer(),
            Text('$_xpReward XP', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.warning)),
          ]),
          Slider(value: _xpReward.toDouble(), min: 0, max: 100, divisions: 20, activeColor: AppColors.warning, label: '$_xpReward XP', onChanged: (v) => setState(() => _xpReward = v.round())),
          const Text('Awarded on passing this graded test (max 100 XP)', style: TextStyle(fontSize: 11, color: AppColors.muted)),
        ]),
      ),
    ]);
  }

  // FLAG PARA CJ: el card de "Maximum Attempts" usaba Colors.purple como
  // acento propio, distinto de info/warning/danger/success. No hay un
  // token morado en el set de AppColors que rescaté de tu historial
  // (primary/primaryLight/primaryDark/success/warning/danger/info). Lo
  // dejé como Colors.purple literal por ahora — decime si querés que use
  // AppColors.info en su lugar (quedaría igual al color de "Passing
  // Score" arriba) o si preferís agregar un token nuevo tipo
  // AppColors.accent a tu design system.
  Widget _buildAttemptsCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.purple.withOpacity(0.05),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Maximum Attempts',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),

          Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => setState(() {
                      if (_maxAttempts > 1) _maxAttempts--;
                    }),
                    icon: const Icon(Icons.remove_circle_outline),
                    color: Colors.purple,
                  ),
                  Container(
                    width: 60,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: _maxAttempts == 0
                          ? Border.all(color: AppColors.warning, width: 2)
                          : null,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _maxAttempts == 0 ? '?' : '$_maxAttempts',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: _maxAttempts == 0 ? AppColors.warning : Colors.black,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() {
                      if (_maxAttempts < 5) _maxAttempts++;
                    }),
                    icon: const Icon(Icons.add_circle_outline),
                    color: Colors.purple,
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Warning if not set
              if (_maxAttempts == 0)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.info_outline, size: 14, color: AppColors.warning),
                      const SizedBox(width: 4),
                      Text(
                        'Select 1-5 attempts',
                        style: TextStyle(fontSize: 12, color: AppColors.warning.withOpacity(0.9)),
                      ),
                    ],
                  ),
                )
              else
                Text(
                  _maxAttempts == 1
                      ? 'Students can take this quiz once (no retakes)'
                      : 'Students can take this quiz up to $_maxAttempts times',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
            ],
          ),

          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.psychology, size: 20, color: AppColors.success),
                const SizedBox(width: AppSpacing.sm),
                const Expanded(
                  child: Text(
                    'Set attempts to 1 for no retakes, or 2-5 to allow retakes.',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(int index) {
    final q = _questions[index];
    final c = widget.groupColor;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: c.withOpacity(0.2), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
          decoration: BoxDecoration(
            color: c.withOpacity(0.06),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.md)),
            border: Border(bottom: BorderSide(color: c.withOpacity(0.1))),
          ),
          child: Row(children: [
            Container(width: 28, height: 28, decoration: BoxDecoration(color: c, shape: BoxShape.circle), child: Center(child: Text('${index + 1}', style: const TextStyle(color: AppColors.onPrimary, fontWeight: FontWeight.bold, fontSize: 13)))),
            const SizedBox(width: 10),
            Text('Question ${index + 1}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: c)),
            const Spacer(),
            if (_questions.length > 1)
              GestureDetector(
                onTap: () => _removeQuestion(index),
                child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: AppColors.danger.withOpacity(0.08), shape: BoxShape.circle), child: Icon(Icons.close, size: 16, color: AppColors.danger.withOpacity(0.7))),
              ),
          ]),
        ),

        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Question text
            TextFormField(
              controller: q.questionCtrl,
              decoration: InputDecoration(
                hintText: 'e.g. "What does \'Stand up\' mean?"',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.sm), borderSide: const BorderSide(color: AppColors.divider)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.sm), borderSide: BorderSide(color: c, width: 2)),
                filled: true, fillColor: Colors.grey.shade50,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                prefixIcon: Icon(Icons.help_outline_rounded, color: Colors.grey.shade400, size: 18),
              ),
              maxLines: 2,
              validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
            ),
            const SizedBox(height: AppSpacing.md),

            const Text('Options', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted)),
            const SizedBox(height: 8),

            // Options A–D
            ...List.generate(4, (oi) {
              final label     = String.fromCharCode(65 + oi);
              final isCorrect = q.correctIndex == oi;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isCorrect ? AppColors.success.withOpacity(0.08) : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  border: Border.all(color: isCorrect ? AppColors.success : Colors.grey.shade200, width: isCorrect ? 2 : 1),
                ),
                child: Row(children: [
                  GestureDetector(
                    onTap: () => setState(() => q.correctIndex = oi),
                    child: Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: isCorrect ? AppColors.success : Colors.white, border: Border.all(color: isCorrect ? AppColors.success : Colors.grey.shade400, width: 2)),
                      child: Center(child: isCorrect ? const Icon(Icons.check, size: 15, color: AppColors.onPrimary) : Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade500))),
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
                      style: TextStyle(fontSize: 14, color: isCorrect ? AppColors.success : Colors.black87),
                    ),
                  ),
                ]),
              );
            }),

            // Hint
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: AppColors.success.withOpacity(0.06), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                const Icon(Icons.check_circle_outline, size: 14, color: AppColors.success),
                const SizedBox(width: 6),
                Flexible(child: Text('Tap a letter to mark it as the correct answer (currently: ${String.fromCharCode(65 + q.correctIndex)})', style: const TextStyle(fontSize: 11, color: AppColors.success))),
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
      backgroundColor: AppColors.scaffoldBackground,
      body: Column(
        children: [
          TeacherScreenHeader(
            title: widget.isEditing ? 'Edit Unit Quiz' : 'Create Unit Quiz',
            color: c,
          ),
          Expanded(
            child: _isLoadingQuestions
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    CircularProgressIndicator(color: c),
                    const SizedBox(height: AppSpacing.md),
                    const Text('Loading questions...', style: TextStyle(color: AppColors.muted)),
                  ]))
                : Form(
                    key: _formKey,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Question count chip ─────────────────────────
                          // Replaces the AppBar's "N Q" pill.
                          Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                              child: Text('${_questions.length} Q', style: TextStyle(color: c, fontSize: 13, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),

                          _buildSettingsCard(),
                          const SizedBox(height: AppSpacing.md),
                          _buildAttemptsCard(),
                          const SizedBox(height: AppSpacing.xl),

                          // Graded exam warning banner
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: AppColors.danger.withOpacity(0.07),
                              borderRadius: BorderRadius.circular(AppRadii.md),
                              border: Border.all(color: AppColors.danger.withOpacity(0.25)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline, color: AppColors.danger.withOpacity(0.85), size: 20),
                                const SizedBox(width: AppSpacing.sm),
                                const Expanded(
                                  child: Text(
                                    'This is a graded exam. Scores will be reported to parents.',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),

                          // Questions header
                          Row(children: [
                            const Text('Questions', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
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
                          const Text('Each question has 4 options (A–D). Tap a letter to mark the correct answer.', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                          const SizedBox(height: AppSpacing.md),

                          // Question cards
                          ...List.generate(_questions.length, (i) => _buildQuestionCard(i)),

                          // Add question button (bottom)
                          if (_questions.length < 20)
                            GestureDetector(
                              onTap: _addQuestion,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(AppRadii.lg),
                                  border: Border.all(color: c.withOpacity(0.3), width: 1.5),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_circle_outline, color: c, size: 20),
                                    const SizedBox(width: 8),
                                    Text('Add Question (${_questions.length}/20)', style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 14)),
                                  ],
                                ),
                              ),
                            ),

                          // Save button
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              onPressed: _isSaving ? null : _save,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: c,
                                disabledBackgroundColor: AppColors.divider,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
                                elevation: 0,
                              ),
                              child: _isSaving
                                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: AppColors.onPrimary, strokeWidth: 2))
                                  : Text(
                                      widget.isEditing ? 'Save Changes' : 'Create Quiz',
                                      style: const TextStyle(color: AppColors.onPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}