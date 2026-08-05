import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_screen_header.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

class CreateQuizScreen extends StatefulWidget {
  final String groupId;
  final String contentId;
  final String unitId;
  final Color groupColor;

  /// 'unit' or 'lesson'. Defaults to 'unit' to preserve every existing
  /// call site's behavior without requiring changes at the call site.
  final String scope;

  /// Required when scope == 'lesson' — which Lesson this quiz evaluates.
  /// Ignored (and should be left null) when scope == 'unit'.
  final String? lessonId;

  /// Unit or Lesson title, passed through so the Quiz Title field can be
  /// pre-filled with "<name> Quiz" on create. Purely a starting
  /// suggestion — the field stays editable and this has no effect once
  /// isEditing is true (existingData's saved title wins).
  final String? destinationTitle;

  // Edit mode
  final String? quizId;
  final Map<String, dynamic>? existingData;

  const CreateQuizScreen({
    super.key,
    required this.groupId,
    required this.contentId,
    required this.unitId,
    required this.groupColor,
    this.scope = 'unit',
    this.lessonId,
    this.destinationTitle,
    this.quizId,
    this.existingData,
  }) : assert(
          scope != 'lesson' || lessonId != null,
          'lessonId is required when scope is lesson',
        );

  bool get isEditing => quizId != null;
  bool get isLessonScope => scope == 'lesson';

  @override
  State<CreateQuizScreen> createState() =>
      _CreateQuizScreenState();
}

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

class _CreateQuizScreenState
    extends State<CreateQuizScreen> {
  final _formKey = GlobalKey<FormState>();
  final Database _db = Database();

  int _passingScore = 1;
  late int _xpReward;

  List<_QuizQuestion> _questions = [];
  bool _isLoadingQuestions = false;
  bool _isSaving = false;

  int _maxAttempts = 0;

  /// Snapshot of the questions exactly as they came from Firestore, taken
  /// once in _loadExistingQuestions before the user can touch anything —
  /// used only by _hasChanges to tell a real edit apart from "opened the
  /// screen and tapped Save without changing anything". Stays null for a
  /// brand-new Quiz (isEditing == false), where every save is by
  /// definition a change.
  List<Map<String, dynamic>>? _originalQuestions;

  /// Name of the Unit or Lesson this quiz is tied to, for display in
  /// the read-only identity chip. On create this starts from
  /// widget.destinationTitle (already known, no fetch needed); on edit
  /// it's null until _loadDestinationName fills it in, since
  /// destinationTitle is only ever passed by the picker flow, not by
  /// the edit entry point in _QuizCard.
  String? _destinationName;

  /// 100 for scope: unit, 50 for scope: lesson. See class-level comment.
  int get _maxXp => widget.isLessonScope ? 50 : 100;

  @override
  void initState() {
    super.initState();

    // Default XP reward scales with scope so a fresh Lesson Quiz doesn't
    // start pre-filled with a value only valid for Unit Quiz.
    _xpReward = widget.isLessonScope ? 25 : 50;
    _destinationName = widget.destinationTitle;

    if (widget.isEditing && widget.existingData != null) {
      // Pre-fill header fields — title intentionally NOT pre-filled here
      // anymore; it's re-derived fresh at save time (see _resolveTitle),
      // so whatever was stored before is irrelevant to this form.
      // For lesson scope, passingScore/maxAttempts aren't shown or
      // editable, so they're not read back from existingData here — the
      // fixed sentinels in _save() are what get written on next save
      // regardless of what an older graded Lesson Quiz doc had stored.
      if (!widget.isLessonScope) {
        _passingScore = (widget.existingData!['passingScore'] as num?)?.toInt() ?? 1;
        _maxAttempts  = (widget.existingData!['maxAttempts'] as num?)?.toInt() ?? 0;
      }
      _xpReward = (widget.existingData!['xpReward'] as num?)?.toInt() ?? _xpReward;

      // Load questions from the subcollection
      _isLoadingQuestions = true;
      _loadExistingQuestions();

      // Edit entry point (_QuizCard) doesn't pass destinationTitle —
      // fetch it directly so the identity chip has something to show.
      if (_destinationName == null) _loadDestinationName();
    } else {
      // New quiz — start with 2 blank questions.
      _questions = [_QuizQuestion(), _QuizQuestion()];
    }
  }

  /// Fetches the Unit/Lesson name for display only (the identity chip).
  /// Only called when destinationTitle wasn't already provided (i.e. the
  /// edit entry point). Separate from _resolveTitle because this sets
  /// UI state via setState; _resolveTitle runs at save time and returns
  /// its result directly instead.
  Future<void> _loadDestinationName() async {
    try {
      String name;
      if (widget.isLessonScope) {
        final lessonDoc = await _db
            .personalizedLessons(widget.contentId, widget.unitId)
            .doc(widget.lessonId)
            .get();
        name = (lessonDoc.data() as Map<String, dynamic>?)?['title'] as String? ?? 'this lesson';
      } else {
        final unitDoc = await _db.personalizedUnits(widget.contentId).doc(widget.unitId).get();
        name = (unitDoc.data() as Map<String, dynamic>?)?['title'] as String? ?? 'this unit';
      }
      if (mounted) setState(() => _destinationName = name);
    } catch (_) {
      // Silent — the chip falls back to the generic "this unit/lesson"
      // wording already baked into _buildSettingsCard's null-coalesce.
    }
  }

  /// Derives the Quiz's stored title from the CURRENT Unit/Lesson name —
  /// never typed by the teacher. Called at save time (both create and
  /// edit) so the stored title stays in sync with whatever the Unit or
  /// Lesson is named right now, even if it was renamed since this Quiz
  /// was created. Falls back to a generic label if the Unit/Lesson doc
  /// is missing (shouldn't happen in practice, but avoids a crash).
  Future<String> _resolveTitle() async {
    if (widget.isLessonScope) {
      final lessonDoc = await _db
          .personalizedLessons(widget.contentId, widget.unitId)
          .doc(widget.lessonId)
          .get();
      final lessonName = (lessonDoc.data() as Map<String, dynamic>?)?['title'] as String? ?? 'Lesson';
      return '$lessonName — Lesson Quiz';
    } else {
      final unitDoc = await _db.personalizedUnits(widget.contentId).doc(widget.unitId).get();
      final unitName = (unitDoc.data() as Map<String, dynamic>?)?['title'] as String? ?? 'Unit';
      return '$unitName — Unit Test';
    }
  }

  Future<void> _loadExistingQuestions() async {
    try {
      final snap = await _db.getQuizQuestions(widget.quizId!);

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

      // Snapshot BEFORE the empty-fallback below — that fallback exists
      // purely so the form has something to edit, it must not count as
      // part of the original saved state.
      _originalQuestions = loaded
          .map((q) => {
                'question': q.questionCtrl.text.trim(),
                'options': q.optionCtrls.map((c) => c.text.trim()).toList(),
                'correctIndex': q.correctIndex,
              })
          .toList();

      if (loaded.isEmpty) loaded.add(_QuizQuestion());

      setState(() {
        _questions          = loaded;
        _isLoadingQuestions = false;
        // Re-clamp passing score now that we know question count —
        // only meaningful for unit scope, where the field is shown.
        if (!widget.isLessonScope) {
          _passingScore = _passingScore.clamp(1, _questions.length);
        }
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
        if (!widget.isLessonScope) {
          _passingScore = _passingScore.clamp(1, _questions.length);
        }
      });
    }
  }

  // ── Validation ─────────────────────────────────────────────────────────────

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

  /// True if the form's current values differ from what was actually
  /// loaded from Firestore for this Quiz. Always true when creating (there
  /// is nothing to compare against). Compares every field updateQuiz would
  /// otherwise unconditionally overwrite — title (re-derived from the
  /// Unit/Lesson's current name, so a rename since this Quiz was last
  /// saved counts as a change even if nothing in the form itself was
  /// touched), passing score / XP / max attempts, and every question's
  /// text, 4 options and correct answer, in order.
  bool _hasChanges({
    required String resolvedTitle,
    required int effectivePassingScore,
    required int effectiveMaxAttempts,
    required List<Map<String, dynamic>> questionsList,
  }) {
    if (!widget.isEditing || widget.existingData == null) return true;
    final original = widget.existingData!;

    if (resolvedTitle != (original['title'] as String? ?? '')) return true;
    if (effectivePassingScore != ((original['passingScore'] as num?)?.toInt() ?? 0)) {
      return true;
    }
    if (_xpReward != ((original['xpReward'] as num?)?.toInt() ?? 0)) return true;
    if (effectiveMaxAttempts != ((original['maxAttempts'] as num?)?.toInt() ?? 0)) {
      return true;
    }

    final origQuestions = _originalQuestions ?? const [];
    if (origQuestions.length != questionsList.length) return true;
    for (var i = 0; i < origQuestions.length; i++) {
      final a = origQuestions[i];
      final b = questionsList[i];
      if (a['question'] != b['question']) return true;
      if (a['correctIndex'] != b['correctIndex']) return true;
      final aOpts = List<String>.from(a['options'] as List);
      final bOpts = List<String>.from(b['options'] as List);
      if (aOpts.length != bOpts.length) return true;
      for (var o = 0; o < aOpts.length; o++) {
        if (aOpts[o] != bOpts[o]) return true;
      }
    }
    return false;
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_validateQuestions()) return;

    // Attempts validation only applies to Unit Quiz — Lesson Quiz never
    // shows this field and always sends the fixed unlimited sentinel.
    if (!widget.isLessonScope && (_maxAttempts < 1 || _maxAttempts > 5)) {
      _showSnack('Please set maximum attempts (1-5)', color: AppColors.warning);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final resolvedTitle = await _resolveTitle();

      final questionsList = _questions.asMap().entries.map((e) => {
        'question':     e.value.questionCtrl.text.trim(),
        'options':      e.value.optionCtrls.map((c) => c.text.trim()).toList(),
        'correctIndex': e.value.correctIndex,
        'order':        e.key + 1,
      }).toList();

      // Lesson Quiz is ungraded: passingScore is sent as "all questions"
      // (irrelevant in practice — saveQuizCompletion no longer branches
      // on it for lesson scope) and maxAttempts as a large fixed value
      // since retries are unlimited by design. See class-level comment.
      final effectivePassingScore = widget.isLessonScope ? questionsList.length : _passingScore;
      final effectiveMaxAttempts  = widget.isLessonScope ? 99 : _maxAttempts;

      if (widget.isEditing) {
        // Nothing to write if the form matches what's already saved —
        // updateQuiz would otherwise unconditionally overwrite the
        // top-level fields AND delete+recreate every question doc even
        // when nothing actually changed.
        if (!_hasChanges(
          resolvedTitle: resolvedTitle,
          effectivePassingScore: effectivePassingScore,
          effectiveMaxAttempts: effectiveMaxAttempts,
          questionsList: questionsList,
        )) {
          if (mounted) {
            _showSnack('No changes made', color: AppColors.muted);
            Navigator.pop(context);
          }
          return;
        }

        // scope/lessonId intentionally not passed — immutable post-creation.
        // title re-derived above so editing an existing Quiz refreshes it
        // to match the Unit/Lesson's current name.
        await _db.updateQuiz(
          quizId: widget.quizId!,
          title: resolvedTitle,
          questions: questionsList,
          passingScore: effectivePassingScore,
          xpReward: _xpReward,
          maxAttempts: effectiveMaxAttempts,
        );
        if (mounted) {
          _showSnack(
            widget.isLessonScope ? 'Lesson Quiz updated successfully' : 'Quiz updated successfully',
            color: AppColors.success,
          );
          Navigator.pop(context);
        }
      } else {
        final quizId = 'quiz_${DateTime.now().millisecondsSinceEpoch}';
        await _db.createQuiz(
          contentId:    widget.contentId,
          unitId:       widget.unitId,
          quizId:       quizId,
          title:        resolvedTitle,
          questions:    questionsList,
          passingScore: effectivePassingScore,
          xpReward:     _xpReward,
          maxAttempts:  effectiveMaxAttempts,
          scope:        widget.scope,
          lessonId:     widget.lessonId,
        );
        if (mounted) {
          _showSnack(
            widget.isLessonScope ? 'Lesson Quiz created successfully' : 'Quiz created successfully',
            color: AppColors.success,
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      // Surfaces the one-per-target message from
      // database.dart's _assertNoExistingQuiz as-is — it's already
      // written to be teacher-readable ("This unit/lesson already has a
      // Quiz...").
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
      // Identity indicator — read-only, replaces the old free-text
      // title field. The Quiz's title is derived automatically from
      // the Unit/Lesson name (see _resolveTitle); showing it here as a
      // non-editable chip confirms to the teacher what this Quiz is
      // tied to without inviting them to type a name for it.
      Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
        decoration: BoxDecoration(
          color: c.withOpacity(0.06),
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: c.withOpacity(0.2)),
        ),
        child: Row(children: [
          Icon(widget.isLessonScope ? Icons.bookmark_outline : Icons.layers_outlined, color: c, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              widget.isLessonScope
                  ? 'Lesson Quiz for: ${_destinationName ?? "this lesson"}'
                  : 'Unit Test for: ${_destinationName ?? "this unit"}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c),
            ),
          ),
        ]),
      ),
      const SizedBox(height: AppSpacing.md),

      // Passing score — Unit Quiz only. Lesson Quiz is ungraded, so this
      // whole card is skipped for scope: lesson.
      if (!widget.isLessonScope) ...[
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
            const Text(
              'Students must answer at least this many questions correctly to pass',
              style: TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ]),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],

      // XP reward — max and default now derive from scope via _maxXp.
      // For Lesson Quiz this is the ONLY setting shown besides the
      // identity chip: no passing threshold, no attempts cap — just how
      // much XP a first-time completion is worth (retries drop to a
      // flat 5 XP, enforced in database.dart's saveQuizCompletion, same
      // pattern as saveActivityCompletion already uses).
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
          Slider(
            value: _xpReward.toDouble().clamp(0, _maxXp.toDouble()),
            min: 0,
            max: _maxXp.toDouble(),
            divisions: _maxXp ~/ 5,
            activeColor: AppColors.warning,
            label: '$_xpReward XP',
            onChanged: (v) => setState(() => _xpReward = v.round()),
          ),
          Text(
            widget.isLessonScope
                ? 'Awarded on first completion (max $_maxXp XP). Retries after that earn a flat 5 XP only — no threshold to pass, just complete it.'
                : 'Awarded on passing this graded test (max $_maxXp XP)',
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ]),
      ),
    ]);
  }

  Widget _buildAttemptsCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.accent.withOpacity(0.05),
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
                    color: AppColors.accent,
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
                    color: AppColors.accent,
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
            title: widget.isEditing
                ? (widget.isLessonScope ? 'Edit Lesson Quiz' : 'Edit Quiz')
                : (widget.isLessonScope ? 'Create Lesson Quiz' : 'Create Quiz'),
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

                          // Maximum Attempts card — Unit Quiz only.
                          // Lesson Quiz retries are unconditionally
                          // unlimited (see class-level comment), so this
                          // entire card is skipped for scope: lesson.
                          if (!widget.isLessonScope) ...[
                            const SizedBox(height: AppSpacing.md),
                            _buildAttemptsCard(),
                          ],
                          const SizedBox(height: AppSpacing.xl),

                          // Scope-dependent banner. Unit Quiz keeps the
                          // original "graded exam, reported to parents"
                          // wording. Lesson Quiz copy now reflects that
                          // it's fully ungraded — no pass/fail, XP-only,
                          // unlimited attempts with reduced XP after the
                          // first completion.
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: (widget.isLessonScope ? AppColors.info : AppColors.danger).withOpacity(0.07),
                              borderRadius: BorderRadius.circular(AppRadii.md),
                              border: Border.all(color: (widget.isLessonScope ? AppColors.info : AppColors.danger).withOpacity(0.25)),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  widget.isLessonScope ? Icons.school_outlined : Icons.info_outline,
                                  color: (widget.isLessonScope ? AppColors.info : AppColors.danger).withOpacity(0.85),
                                  size: 20,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    widget.isLessonScope
                                        ? 'Ungraded check-in for this lesson. No pass/fail, doesn\'t block progress, not reported to parents — just XP for completing it. Students can retry anytime, but only the first completion earns full XP.'
                                        : 'This is a graded exam. Scores will be reported to parents.',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
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
                                      widget.isEditing
                                          ? 'Save Changes'
                                          : (widget.isLessonScope ? 'Create Lesson Quiz' : 'Create Quiz'),
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