import 'package:flutter/material.dart';
import 'package:loringo_app/screens/initials/activity_complete_screen.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

class QuizPlayScreen extends StatefulWidget {
  final String contentId;
  final String unitId;
  final String quizId;
  final String quizTitle;
  final String? studentId;
  final String studentName;
  final bool isPreview;

  const QuizPlayScreen({
    super.key,
    required this.contentId,
    required this.unitId,
    required this.quizId,
    required this.quizTitle,
    this.studentId,
    this.studentName = '',
    this.isPreview = false,
  });

  @override
  State<QuizPlayScreen> createState() => _QuizPlayScreenState();
}

class _QuizPlayScreenState extends State<QuizPlayScreen> {
  final Database _db = Database();

  late Future<Map<String, dynamic>> _quizDataFuture;
  final Map<String, int?> _selectedAnswers = {};
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isSubmitting = false;

  // Cached data after loading
  int _totalQuestions = 0;
  List<Map<String, dynamic>> _questions = [];
  int _xpReward = 0;
  int _passingScore = 0;

  /// True when this quiz's scope is 'lesson' — read from the quiz doc in
  /// _loadQuizData. Drives every branch that skips the graded-Unit-Quiz
  /// UI/gating: no Passing Score display, no attempts cap, always
  /// retakeable, neutral "Complete!" result copy.
  bool _isLessonScope = false;

  // Attempts tracking — only meaningful for scope: 'unit'. For scope:
  // 'lesson' these are loaded/displayed but never gate anything (see
  // _canRetake and _buildQuestionChip).
  int _maxAttempts = 0;
  int _attemptsUsed = 0;
  int _attemptsRemaining = 0;
  bool _isLoadingAttempts = true;

  @override
  void initState() {
    super.initState();
    _quizDataFuture = _loadQuizData().then((data) {
      setState(() {
        _totalQuestions = data['totalQuestions'];
        _questions = List<Map<String, dynamic>>.from(data['questions']);
        _xpReward = data['xpReward'];
        _passingScore = data['passingScore'];
        _maxAttempts = data['maxAttempts'];
        _isLessonScope = data['isLessonScope'] as bool? ?? false;
      });

      // Load attempts info if not in preview mode
      if (!widget.isPreview && widget.studentId != null) {
        _loadAttemptsInfo();
      } else {
        _isLoadingAttempts = false;
      }

      return data;
    });
  }

  Future<void> _loadAttemptsInfo() async {
    try {
      final progressDoc = await _db.studentProgress(widget.studentId!).doc(widget.quizId).get();

      debugPrint('_loadAttemptsInfo - _maxAttempts: $_maxAttempts');

      if (progressDoc.exists) {
        final data = progressDoc.data() as Map<String, dynamic>;
        _attemptsUsed = data['totalAttempts'] as int? ?? 1;
        debugPrint('   attempts from Firestore: ${data['totalAttempts']}');
      } else {
        _attemptsUsed = 0;
        debugPrint('   No progress document');
      }

      // Calculate remaining attempts using the current _maxAttempts.
      // Meaningless for scope: 'lesson' (maxAttempts is the fixed 99
      // sentinel there) but harmless to compute either way — the UI
      // simply never displays it for that scope (see
      // _buildQuestionChip).
      _attemptsRemaining = _maxAttempts - _attemptsUsed;
      if (_attemptsRemaining < 0) _attemptsRemaining = 0;

      debugPrint('   _attemptsUsed: $_attemptsUsed');
      debugPrint('   _attemptsRemaining: $_attemptsRemaining');

      setState(() => _isLoadingAttempts = false);
    } catch (e) {
      debugPrint('Error loading attempts info: $e');
      setState(() => _isLoadingAttempts = false);
    }
  }

  Future<Map<String, dynamic>> _loadQuizData() async {
    final quizDoc = await _db.getQuiz(widget.quizId);

    if (!quizDoc.exists) throw Exception('Quiz not found');

    final quizData = quizDoc.data() as Map<String, dynamic>;
    final isLessonScope = (quizData['scope'] as String? ?? 'unit') == 'lesson';

    // Get max attempts from quiz data (default to 0). For scope:
    // 'lesson' this is the fixed 99 sentinel create_quiz_screen.dart
    // writes — not read as a real cap anywhere in this file anymore.
    final maxAttempts = (quizData['maxAttempts'] as num?)?.toInt() ?? 0;

    _maxAttempts = maxAttempts;

    final questionsSnapshot = await _db.getQuizQuestions(widget.quizId);

    final questions = questionsSnapshot.docs.map((doc) {
      final d = doc.data() as Map<String, dynamic>;
      return {
        'id': doc.id,
        'question': d['question'] ?? '',
        'options': List<String>.from(d['options'] ?? []),
        'correctIndex': (d['correctIndex'] as num?)?.toInt() ?? 0,
      };
    }).toList();

    return {
      'title': quizData['title'] ?? widget.quizTitle,
      'passingScore': (quizData['passingScore'] as num?)?.toInt() ?? 1,
      'xpReward': (quizData['xpReward'] as num?)?.toInt() ?? 0,
      'totalQuestions': questions.length,
      'questions': questions,
      'maxAttempts': maxAttempts,
      'isLessonScope': isLessonScope,
    };
  }

  void _selectAnswer(int questionIndex, int optionIndex) {
    setState(() => _selectedAnswers[questionIndex.toString()] = optionIndex);
  }

  void _nextPage() {
    if (_currentPage < _totalQuestions - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  /// Check if student can retake. For scope: 'lesson' this is
  /// unconditionally true outside preview mode — Lesson Quiz is
  /// ungraded, so there is no "already passed" or "attempts exhausted"
  /// state to check for. scope: 'unit' logic is unchanged.
  Future<bool> _canRetake() async {
    if (widget.isPreview) return false;
    if (widget.studentId == null) return false;

    if (_isLessonScope) return true;

    final progressDoc = await _db.studentProgress(widget.studentId!).doc(widget.quizId).get();
    if (!progressDoc.exists) return true; // first attempt

    final data = progressDoc.data() as Map<String, dynamic>?;
    final attemptsUsed = data?['totalAttempts'] as int? ?? 1;
    final passed = data?['passed'] as bool? ?? false;
    final reportGenerated = data?['reportGenerated'] as bool? ?? false;

    // If report has been generated, student cannot retake
    if (reportGenerated) return false;

    // If already passed, no need to retake
    if (passed) return false;

    // BUGFIX: this used to also check `if (isCompleted) return false;`
    // here, reading Database.saveQuizCompletion's 'isCompleted' field.
    // That field is set to true on EVERY submitted attempt — passed or
    // failed, first try or a later one — it only means "an attempt has
    // been recorded," not "no attempts remain." So after a first FAILED
    // attempt (isCompleted: true, passed: false), this check fired
    // before the actual attempts-remaining check below ever ran,
    // permanently blocking retakes for a student who still had budget
    // left — exactly the "You have already completed this quiz" message
    // seen after a legitimate second try with 2/3 attempts still
    // available.
    //
    // The real "have attempts run out" check is the attemptsUsed <
    // _maxAttempts comparison below — that's the only thing this method
    // needs to gate on once passed/reportGenerated are ruled out.

    // Only allow retake if attempts remaining
    return attemptsUsed < _maxAttempts;
  }

  Future<void> _submitQuiz() async {
    final totalQ = _totalQuestions;
    final passingScore = _passingScore;
    final maxXpReward = _xpReward;

    if (_selectedAnswers.length < totalQ) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please answer all $totalQ questions'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Check if student can take this quiz. For scope: 'lesson',
    // _canRetake always returns true outside preview, so this branch is
    // effectively unreachable for Lesson Quiz — kept as-is since it's
    // still the correct gate for scope: 'unit'.
    final canRetake = await _canRetake();
    if (!canRetake && !widget.isPreview) {
      // Get more details about why they can't retake
      final progressDoc = await _db.studentProgress(widget.studentId!).doc(widget.quizId).get();
      String message = 'You cannot take this quiz.';

      if (progressDoc.exists) {
        final data = progressDoc.data() as Map<String, dynamic>;
        final passed = data['passed'] as bool? ?? false;
        final attemptsUsed = data['totalAttempts'] as int? ?? 0;
        final reportGenerated = data['reportGenerated'] as bool? ?? false;

        // BUGFIX: dropped the standalone `isCompleted` branch that used
        // to sit here — see _canRetake's doc comment above for why
        // 'isCompleted' (true on every submitted attempt, pass or fail)
        // was never a valid signal for "no attempts left." The real
        // reasons _canRetake can return false are, in order: a report
        // was already generated, the student already passed, or
        // attempts are exhausted — this message now mirrors exactly
        // those three checks.
        if (reportGenerated) {
          message = 'This quiz has already been reviewed and reported.';
        } else if (passed) {
          message = 'You have already passed this quiz.';
        } else if (attemptsUsed >= _maxAttempts) {
          message = 'You have used all $_maxAttempts attempts for this quiz.';
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    int correctCount = 0;
    for (int i = 0; i < _questions.length; i++) {
      if (_selectedAnswers[i.toString()] == _questions[i]['correctIndex'] as int) {
        correctCount++;
      }
    }

    final scorePercent = (correctCount / totalQ * 100).round();
    // scope: 'lesson' has no passing threshold — always counts as
    // passed client-side too, mirroring the server-side force in
    // database.dart's saveQuizCompletion. This keeps showRetake/result
    // copy below consistent with what actually gets persisted instead
    // of computing a "passed" value that's about to be overridden.
    final passed = _isLessonScope ? true : correctCount >= passingScore;

    int xpEarned = 0;

    // Declare these variables outside the try block
    int currentAttemptCount = 0;
    int remainingAttempts = 0;

    if (!widget.isPreview && widget.studentId != null) {
      try {
        final progressDoc = await _db.studentProgress(widget.studentId!).doc(widget.quizId).get();

        final wasCompleted = progressDoc.exists &&
            (progressDoc.data() as Map<String, dynamic>?)?['isCompleted'] == true;

        // Get previous score and attempts
        int previousScore = -1;
        if (progressDoc.exists) {
          final data = progressDoc.data() as Map<String, dynamic>;
          previousScore = data['correctAnswers'] as int? ?? -1;
          currentAttemptCount = data['totalAttempts'] as int? ?? 0;
        }

        // ============================================================
        // XP CALCULATION (informational only for scope: 'lesson' — see
        // below; saveQuizCompletion recomputes the real value there
        // from the quiz's configured xpReward vs first-attempt-or-retry,
        // ignoring whatever is calculated here for that scope).
        // ============================================================
        if (!wasCompleted && passed) {
          // First time passing: award XP based on percentage correct
          xpEarned = (correctCount * maxXpReward / totalQ).round();
          if (xpEarned < 5 && correctCount > 0) {
            xpEarned = 5;
          }
          debugPrint('First time passing: $correctCount/$totalQ = $scorePercent% → $xpEarned XP');
        } else if (wasCompleted && correctCount > previousScore) {
          // Improvement bonus
          final previousPercent = (previousScore / totalQ * 100).round();
          final newPercent = (correctCount / totalQ * 100).round();
          final improvement = newPercent - previousPercent;
          xpEarned = (improvement / 5).round().clamp(3, 10);
          debugPrint('Improvement: ${previousScore}→${correctCount} ($improvement% improvement) → $xpEarned XP');
        } else {
          debugPrint('No XP earned - wasCompleted: $wasCompleted, passed: $passed, correctCount: $correctCount, previousScore: $previousScore');
        }

        debugPrint('Saving quiz completion with xpEarned: $xpEarned (informational for lesson scope — server recomputes)');

        // isClosedAfterAttempts: for scope: 'lesson' this is irrelevant
        // to gating (there's no cap to exhaust and _canRetake always
        // returns true), but still computed the same way for scope:
        // 'unit', which is what actually uses it.
        final newAttemptsUsedForClose = currentAttemptCount + 1;
        final bool shouldCloseAfterThisAttempt =
            _isLessonScope || passed || newAttemptsUsedForClose >= _maxAttempts;

        final answers = <Map<String, dynamic>>[
          for (int i = 0; i < _questions.length; i++)
            {
              'questionIndex': i,
              'selectedIndex': _selectedAnswers[i.toString()],
              'correctIndex': _questions[i]['correctIndex'],
              'isCorrect': _selectedAnswers[i.toString()] == _questions[i]['correctIndex'],
            },
        ];

        await _db.saveQuizCompletion(
          studentId: widget.studentId!,
          quizId: widget.quizId,
          contentId: widget.contentId,
          unitId: widget.unitId,
          correctAnswers: correctCount,
          totalQuestions: totalQ,
          answers: answers,
          xpEarned: xpEarned,
          passed: passed,
          isClosedAfterAttempts: shouldCloseAfterThisAttempt,
        );

        // Update attempts remaining after save
        await _loadAttemptsInfo();
      } catch (e) {
        debugPrint('Error saving quiz progress: $e');
      }
    }

    setState(() => _isSubmitting = false);
    if (!mounted) return;

    // Calculate remaining attempts — meaningless for scope: 'lesson'
    // (retries are unconditionally allowed regardless of this number),
    // still used for scope: 'unit' below.
    final newAttemptsUsed = currentAttemptCount + 1;
    remainingAttempts = _maxAttempts - newAttemptsUsed;

    debugPrint('   Submit Quiz - Attempts Calculation:');
    debugPrint('   currentAttemptCount: $currentAttemptCount');
    debugPrint('   newAttemptsUsed: $newAttemptsUsed');
    debugPrint('   _maxAttempts: $_maxAttempts');
    debugPrint('   remainingAttempts: $remainingAttempts');
    debugPrint('   Final xpEarned being passed to ActivityCompleteScreen: $xpEarned');

    // scope: 'lesson' always offers retake (ungraded, no attempts cap).
    // scope: 'unit' keeps the original rule: only if not passed AND
    // attempts remain.
    final bool showRetake = _isLessonScope || (!passed && remainingAttempts > 0);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ActivityCompleteScreen(
          // scope: 'lesson' always shows a neutral "Complete!" — there
          // is no passing/failing state to celebrate or soften.
          screenTitle: _isLessonScope
              ? 'Complete! 🎉'
              : (passed ? 'Quiz Passed! 🎉' : 'Quiz Complete'),
          activityTitle: widget.quizTitle,
          scorePercent: scorePercent,
          correctAnswers: correctCount,
          wrongAnswers: totalQ - correctCount,
          xpEarned: xpEarned,
          isGraded: !_isLessonScope,
          onRetake: showRetake ? (ctx) => _onRetakeQuiz(ctx) : null,
          attemptsRemaining: _isLessonScope ? 0 : (remainingAttempts > 0 ? remainingAttempts : 0),
          maxAttempts: _isLessonScope ? 0 : _maxAttempts,
        ),
      ),
    );
  }

  // BUGFIX (part 2): this method used to navigate via its OWN
  // `context` (Navigator.of(context) with no argument, implicitly using
  // _QuizPlayScreenState's context). That context belongs to the OLD
  // QuizPlayScreen instance — the one ActivityCompleteScreen replaced
  // via pushReplacement when the quiz was submitted. Flutter's State
  // object survives for a moment after its widget leaves the tree
  // (that's why this method could still be *called* at all, as a
  // stored callback on ActivityCompleteScreen), but its BuildContext is
  // already unmounted by the time the "Try Again" button is tapped —
  // State.context throws "This widget has been unmounted" the instant
  // anything reads it, which is exactly the assertion in the trace.
  //
  // Part 1 of this bugfix (removing the stray jumpToPage call) fixed
  // the crash that happened on the FIRST line of this method; this is
  // the crash that was waiting on the NEXT line once that one was
  // cleared — same root cause (using a dead instance's context),
  // different statement.
  //
  // Fix: take the caller's BuildContext as a parameter instead of
  // reading `this.context`. The caller is
  // ActivityCompleteScreen._onRetake(), which passes ITS OWN context —
  // that screen is the one actually mounted and visible when the
  // button is tapped, so navigating from there is always valid.
  void _onRetakeQuiz(BuildContext callerContext) {
    _selectedAnswers.clear();
    _currentPage = 0;

    // Use pushReplacement to replace the completion screen with a fresh quiz screen
    Navigator.of(callerContext).pushReplacement(
      MaterialPageRoute(
        builder: (context) => QuizPlayScreen(
          contentId: widget.contentId,
          unitId: widget.unitId,
          quizId: widget.quizId,
          quizTitle: widget.quizTitle,
          studentId: widget.studentId,
          studentName: widget.studentName,
          isPreview: widget.isPreview,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primary;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        title: Text(widget.quizTitle, style: AppText.appBarTitle),
        backgroundColor: primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 0,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _quizDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: AppColors.danger),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(() => _quizDataFuture = _loadQuizData()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final allAnswered = _selectedAnswers.length == _totalQuestions;

          return Column(
            children: [
              // Header bar - SIMPLIFIED (no scroll)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: Colors.white,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Question and attempts combined
                    _buildQuestionChip(),

                    // XP reward
                    _buildInfoChip(
                      text: '$_xpReward XP',
                      icon: Icons.star_rounded,
                      color: Colors.amber,
                    ),

                    // Passing score — Unit Quiz only. Lesson Quiz has no
                    // threshold to show.
                    if (!_isLessonScope)
                      _buildInfoChip(
                        text: 'Pass: $_passingScore/$_totalQuestions',
                        icon: Icons.check_circle_outline,
                        color: AppColors.success,
                      ),
                  ],
                ),
              ),
              Divider(height: 0, color: AppColors.divider),

              // PageView with questions
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _totalQuestions,
                  onPageChanged: (index) => setState(() => _currentPage = index),
                  itemBuilder: (context, index) {
                    final q = _questions[index];
                    final options = List<String>.from(q['options'] as List);
                    final selected = _selectedAnswers[index.toString()];
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: _QuestionCard(
                        index: index,
                        question: q['question'] as String,
                        options: options,
                        selectedOption: selected,
                        onSelected: (oi) => _selectAnswer(index, oi),
                      ),
                    );
                  },
                ),
              ),

              // Navigation buttons (keep as is)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, -2))],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (_currentPage > 0)
                      OutlinedButton.icon(
                        onPressed: _previousPage,
                        icon: const Icon(Icons.arrow_back, size: 18),
                        label: const Text('Previous'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primary,
                          side: BorderSide(color: primary.withOpacity(0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                        ),
                      )
                    else
                      const SizedBox(width: 100),

                    if (_currentPage < _totalQuestions - 1)
                      ElevatedButton.icon(
                        onPressed: _selectedAnswers[_currentPage.toString()] != null ? _nextPage : null,
                        icon: const Icon(Icons.arrow_forward, size: 18, color: Colors.white),
                        label: const Text('Next'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primary,
                          disabledBackgroundColor: Colors.grey.shade300,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                        ),
                      )
                    else
                      SizedBox(
                        width: 160,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: (allAnswered && !_isSubmitting) ? _submitQuiz : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            disabledBackgroundColor: Colors.grey.shade300,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                          ),
                          child: _isSubmitting
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Text('Submit Quiz', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildQuestionChip() {
    final primary = AppColors.primary;

    // Attempts pip only makes sense for scope: 'unit' — Lesson Quiz has
    // no real cap to show (maxAttempts is the fixed 99 sentinel there).
    final showAttempts = !widget.isPreview &&
        !_isLoadingAttempts &&
        !_isLessonScope &&
        _maxAttempts > 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Text(
            '${_currentPage + 1}/$_totalQuestions',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primary),
          ),
          // Optional: Show attempts remaining (only for graded quizzes)
          if (showAttempts) ...[
            const SizedBox(width: 8),
            Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: Colors.grey,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Row(
              children: [
                Icon(
                  Icons.refresh_rounded,
                  size: 12,
                  color: _attemptsRemaining > 0 ? Colors.blue : Colors.red,
                ),
                const SizedBox(width: 2),
                Text(
                  '${_attemptsRemaining}/$_maxAttempts',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _attemptsRemaining > 0 ? Colors.blue : Colors.red,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}


Widget _buildInfoChip({
  required String text,
  IconData? icon,
  required Color color,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
        ],
        Text(
          text,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
        ),
      ],
    ),
  );
}

// _QuestionCard remains unchanged
class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.index,
    required this.question,
    required this.options,
    required this.selectedOption,
    required this.onSelected,
  });

  final int index;
  final String question;
  final List<String> options;
  final int? selectedOption;
  final void Function(int) onSelected;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primary;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(
          color: selectedOption != null ? primary.withOpacity(0.25) : AppColors.divider,
          width: selectedOption != null ? 1.5 : 1,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: primary.withOpacity(0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
              border: Border(bottom: BorderSide(color: primary.withOpacity(0.08))),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: selectedOption != null ? primary : AppColors.muted.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: selectedOption != null ? AppColors.onPrimary : AppColors.muted,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(question, style: AppText.body.copyWith(fontWeight: FontWeight.w600)),
                ),
                if (selectedOption != null)
                  Icon(Icons.check_circle, color: primary.withOpacity(0.6), size: 18),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: List.generate(options.length, (oi) {
                final letter = String.fromCharCode(65 + oi);
                final isSelected = selectedOption == oi;
                return GestureDetector(
                  onTap: () => onSelected(oi),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? primary.withOpacity(0.07) : AppColors.scaffoldBackground,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      border: Border.all(
                        color: isSelected ? primary : AppColors.divider,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected ? primary : Colors.white,
                            border: Border.all(color: isSelected ? primary : AppColors.divider, width: 2),
                          ),
                          child: Center(
                            child: isSelected
                                ? const Icon(Icons.check, size: 14, color: Colors.white)
                                : Text(letter, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.muted)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            options[oi],
                            style: TextStyle(
                              fontSize: 14,
                              color: isSelected ? primary : Colors.black87,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}