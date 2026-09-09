// screens/teacher/activity_review_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_screen_header.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

// ── ActivityReviewScreen ─────────────────────────────────────────────────
//
// Teacher-facing detail view for a single student's completed activity.
// Mirrors UnitQuizReviewScreen's structure (load data -> show per-item
// detail -> editable feedback box) but adapted for Activities, which are
// fundamentally different from a Unit Quiz in two ways this screen has to
// account for:
//
// 1. NO SINGLE QUESTION FORMAT. A Unit Quiz is N multiple-choice
//    questions, so one review widget covers every question. An Activity
//    is N tasks of up to ~10 DIFFERENT interactive types (image_select,
//    arrange, match, reading, repeat_after_me...), each with its own
//    notion of "what did the student answer." So instead of one render
//    path, this screen switches on each stored task's 'type' field and
//    picks a small type-specific widget — see _buildTaskDetail below.
//
// 2. NO PARENT REPORT / NO PUSH. Unlike the Unit Quiz flow (which ends in
//    saveReportOnly + a push notification to the parent), Activities and
//    Lesson Quizzes only get an internal teacher note — see
//    Database.saveActivityFeedback. There's no "already sent" gating here
//    because there's nothing irreversible being sent; the teacher can
//    revise this note any time.
//
// Data source: students/{studentId}/progress/{activityId}.taskAnswers —
// written by ActivityPlayScreen via Database.saveActivityCompletion, and
// only ever reflecting the student's CURRENT BEST-SCORING attempt (see
// that method's doc comment for why no per-attempt history is kept).
class ActivityReviewScreen extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String groupId;
  final String activityId;
  final String activityTitle;

  const ActivityReviewScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.groupId,
    required this.activityId,
    required this.activityTitle,
  });

  @override
  State<ActivityReviewScreen> createState() => _ActivityReviewScreenState();
}

class _ActivityReviewScreenState extends State<ActivityReviewScreen> {
  bool _isLoading = true;
  bool _isSaving = false;

  int _bestScore = 0;
  int _totalAttempts = 0;
  int _stars = 0;
  List<Map<String, dynamic>> _taskEntries = [];
  // Attempt history — read from the attempts subcollection purely for
  // display (attempt N: score%), separate from taskAnswers which only
  // ever holds the best attempt's detail. Not clickable/expandable by
  // design: showing "which attempt" a score belongs to is enough context
  // for the teacher without re-deriving per-task detail for every past
  // attempt, which was deliberately not stored (see database.dart).
  List<Map<String, dynamic>> _attemptHistory = [];

  String _feedback = '';
  final TextEditingController _feedbackController = TextEditingController();

  // Once feedback has been written and saved, it's locked — same
  // one-shot pattern UnitQuizReviewScreen already uses for its
  // parent-facing report feedback (_reportAlreadySent), just derived
  // from whether feedback text already exists rather than a separate
  // "report sent" doc, since this note has no equivalent send step.
  // Determined right after _loadData() reads the existing feedback, so
  // typing in this session doesn't retroactively unlock/lock anything.
  bool _feedbackConfirmed = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final progressDoc = await FirebaseFirestore.instance
          .collection('teacherGroups')
          .doc(widget.groupId)
          .collection('students')
          .doc(widget.studentId)
          .collection('progress')
          .doc(widget.activityId)
          .get();

      if (progressDoc.exists) {
        final data = progressDoc.data() as Map<String, dynamic>;
        _bestScore = (data['bestScore'] as num?)?.toInt() ?? 0;
        _totalAttempts = (data['totalAttempts'] as num?)?.toInt() ?? 0;
        _stars = (data['stars'] as num?)?.toInt() ?? 0;
        _feedback = data['feedback'] as String? ?? '';

        // taskAnswers is stored as {taskId: answerDetailMap}. Order isn't
        // preserved by a Firestore map, so we sort by each entry's
        // 'order' field when present (task screens don't currently write
        // one, so this is a forward-compatible no-op today, falling back
        // to insertion order which is fine for a first pass at this
        // feature).
        final rawTaskAnswers =
            data['taskAnswers'] as Map<String, dynamic>? ?? {};
        _taskEntries = rawTaskAnswers.entries
            .map(
              (e) => {
                'taskId': e.key,
                ...Map<String, dynamic>.from(e.value as Map),
              },
            )
            .toList();
      }

      // Attempt history — informational only, see class doc comment.
      final attemptsSnap = await FirebaseFirestore.instance
          .collection('teacherGroups')
          .doc(widget.groupId)
          .collection('students')
          .doc(widget.studentId)
          .collection('progress')
          .doc(widget.activityId)
          .collection('attempts')
          .orderBy('attemptNumber')
          .get();
      _attemptHistory = attemptsSnap.docs.map((d) => d.data()).toList();

      _feedbackController.text = _feedback;
      _feedbackConfirmed = _feedback.trim().isNotEmpty;
    } catch (e) {
      debugPrint('Error loading activity review: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveFeedback() async {
    if (_feedback.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'teacher.activity_review_screen.pleaseWriteFeedback'.tr())),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final db = Database();
      await db.saveActivityFeedback(
        groupId: widget.groupId,
        studentId: widget.studentId,
        activityId: widget.activityId,
        feedback: _feedback,
      );
      if (mounted) {
        setState(() => _feedbackConfirmed = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('teacher.activity_review_screen.feedbackSaved'.tr()),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('teacher.activity_review_screen.errorSavingFeedback'
                .tr(namedArgs: {'error': '$e'})),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Color get _scoreColor {
    if (_bestScore >= 90) return Colors.green;
    if (_bestScore >= 70) return const Color(0xFFFFA000);
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          TeacherScreenHeader(
            title: 'teacher.activity_review_screen.reviewTitle'
                .tr(namedArgs: {'title': widget.activityTitle}),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildStudentSummaryCard(),
                        if (_attemptHistory.length > 1) ...[
                          const SizedBox(height: 16),
                          _buildAttemptHistoryCard(),
                        ],
                        const SizedBox(height: 24),
                        Text(
                          'teacher.activity_review_screen.taskByTaskReview'.tr(),
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        if (_taskEntries.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Center(
                              child: Text(
                                'teacher.activity_review_screen.noPerTaskDetail'
                                    .tr(),
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ),
                          )
                        else
                          ..._taskEntries.asMap().entries.map(
                            (e) => _buildTaskDetail(e.key, e.value),
                          ),
                        const SizedBox(height: 24),
                        Text(
                          'teacher.activity_review_screen.teacherFeedback'.tr(),
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _feedbackController,
                          onChanged: (v) => _feedback = v,
                          maxLines: 5,
                          // Once confirmed (saved with real text), this note is
                          // locked — same read-only-after-send treatment
                          // UnitQuizReviewScreen already applies to its feedback.
                          enabled: !_feedbackConfirmed,
                          decoration: InputDecoration(
                            hintText:
                                'teacher.activity_review_screen.feedbackHint'
                                    .tr(),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: _feedbackConfirmed
                                ? Colors.grey.shade100
                                : Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _feedbackConfirmed
                              ? 'teacher.activity_review_screen.feedbackConfirmedNote'
                                  .tr()
                              : 'teacher.activity_review_screen.feedbackVisibleNote'
                                  .tr(),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: (_isSaving || _feedbackConfirmed)
                                ? null
                                : _saveFeedback,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _feedbackConfirmed
                                  ? Colors.grey.shade400
                                  : AppColors.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isSaving
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    _feedbackConfirmed
                                        ? 'teacher.activity_review_screen.feedbackConfirmedButton'
                                            .tr()
                                        : 'teacher.activity_review_screen.saveFeedback'
                                            .tr(),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.primary.withOpacity(0.1),
            child: Text(
              widget.studentName.isNotEmpty
                  ? widget.studentName[0].toUpperCase()
                  : '?',
              style: TextStyle(
                fontSize: 22,
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.studentName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'teacher.activity_review_screen.bestScore'
                          .tr(namedArgs: {'score': '$_bestScore'}),
                      style: TextStyle(
                        fontSize: 14,
                        color: _scoreColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('•', style: TextStyle(color: Colors.grey.shade400)),
                    const SizedBox(width: 10),
                    Text(
                      (_totalAttempts == 1
                              ? 'teacher.activity_review_screen.attemptSingular'
                              : 'teacher.activity_review_screen.attemptPlural')
                          .tr(namedArgs: {'count': '$_totalAttempts'}),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Row(
            children: List.generate(
              3,
              (i) => Icon(
                i < _stars ? Icons.star_rounded : Icons.star_outline_rounded,
                color: i < _stars ? Colors.amber : Colors.grey.shade300,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttemptHistoryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'teacher.activity_review_screen.attemptHistory'.tr(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _attemptHistory.map((a) {
              final attemptNumber = (a['attemptNumber'] as num?)?.toInt() ?? 0;
              final score = (a['score'] as num?)?.toInt() ?? 0;
              final isBest = score == _bestScore;
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isBest
                      ? AppColors.primary.withOpacity(0.1)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                  border: isBest
                      ? Border.all(color: AppColors.primary.withOpacity(0.4))
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '#$attemptNumber: $score%',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isBest ? FontWeight.bold : FontWeight.w500,
                        color: isBest ? AppColors.primary : Colors.black87,
                      ),
                    ),
                    if (isBest) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.star_rounded,
                        size: 14,
                        color: AppColors.primary,
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Per-task-type detail rendering ──────────────────────────────────
  // Mirrors ActivityPlayScreen._buildTaskScreen's switch-on-type pattern,
  // just producing a small review card instead of an interactive
  // exercise. Each branch reads the specific keys that screen_*.dart's
  // _checkAnswer wrote for that type — see each screen's answerDetail
  // shape comment for the exact contract.
  Widget _buildTaskDetail(int index, Map<String, dynamic> entry) {
    final type = entry['type'] as String? ?? 'unknown';

    Widget content;
    switch (type) {
      case 'image_select':
      case 'image_select_reverse':
      case 'sound_match':
        content = _buildSimpleChoiceDetail(entry);
        break;
      case 'odd_one_out':
        content = _buildOddOneOutDetail(entry);
        break;
      case 'arrange':
        content = _buildArrangeDetail(entry);
        break;
      case 'fill_blank':
        content = _buildFillBlankDetail(entry);
        break;
      case 'match':
        content = _buildMatchDetail(entry);
        break;
      case 'complete_the_chat':
        content = _buildChatDetail(entry);
        break;
      case 'sentence_builder':
        content = _buildSentenceBuilderDetail(entry);
        break;
      case 'repeat_after_me':
      case 'listen_and_speak':
        content = _buildSpeechDetail(entry);
        break;
      case 'reading':
        content = _buildReadingDetail(entry);
        break;
      default:
        content = Text(
          'teacher.activity_review_screen.unsupportedTaskType'
              .tr(namedArgs: {'type': type}),
          style: TextStyle(color: Colors.grey.shade500),
        );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _typeLabel(type),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          content,
        ],
      ),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'image_select':
        return 'teacher.activity_review_screen.typeImageSelect'.tr();
      case 'image_select_reverse':
        return 'teacher.activity_review_screen.typeSelectPhrase'.tr();
      case 'sound_match':
        return 'teacher.activity_review_screen.typeSoundMatch'.tr();
      case 'odd_one_out':
        return 'teacher.activity_review_screen.typeOddOneOut'.tr();
      case 'arrange':
        return 'teacher.activity_review_screen.typeArrangeWords'.tr();
      case 'fill_blank':
        return 'teacher.activity_review_screen.typeFillBlank'.tr();
      case 'match':
        return 'teacher.activity_review_screen.typeMatchPairs'.tr();
      case 'complete_the_chat':
        return 'teacher.activity_review_screen.typeConversation'.tr();
      case 'sentence_builder':
        return 'teacher.activity_review_screen.typeSentenceBuilder'.tr();
      case 'repeat_after_me':
        return 'teacher.activity_review_screen.typeRepeatAfterMe'.tr();
      case 'listen_and_speak':
        return 'teacher.activity_review_screen.typeListenAndSpeak'.tr();
      case 'reading':
        return 'teacher.activity_review_screen.typeReadingComprehension'.tr();
      default:
        return type.toUpperCase();
    }
  }

  // image_select / image_select_reverse / sound_match all share the same
  // {selected, correct} shape (plus a type-specific prompt key).
  Widget _buildSimpleChoiceDetail(Map<String, dynamic> entry) {
    final selected = entry['selected'] as String? ?? '';
    final correct = entry['correct'] as String? ?? '';
    final isCorrect = selected == correct;
    final prompt =
        (entry['word'] ?? entry['question'] ?? entry['audioText']) as String? ??
        '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (prompt.isNotEmpty) ...[
          Text(prompt, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
        ],
        _answerRow(
            'teacher.activity_review_screen.studentAnswered'.tr(), selected, isCorrect),
        // If 'correct' is empty despite a wrong answer, the task's own
        // Firestore data has no option marked isCorrect: true — a
        // content-authoring gap, not something the student got wrong.
        // Showing "Correct answer: (no answer)" in green would misread
        // as a valid correct answer, so this surfaces the real issue
        // instead.
        if (!isCorrect && correct.isNotEmpty)
          _answerRow(
              'teacher.activity_review_screen.correctAnswer'.tr(), correct, true)
        else if (!isCorrect)
          _buildMissingAnswerKeyWarning(),
      ],
    );
  }

  Widget _buildMissingAnswerKeyWarning() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 15,
            color: Colors.orange.shade700,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'teacher.activity_review_screen.noCorrectAnswerConfigured'.tr(),
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange.shade700,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOddOneOutDetail(Map<String, dynamic> entry) {
    final category = entry['category'] as String? ?? '';
    final selectedIdx = (entry['selectedIndex'] as num?)?.toInt() ?? -1;
    final correctIdx = (entry['correctIndex'] as num?)?.toInt() ?? -1;
    final isCorrect = selectedIdx == correctIdx;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (category.isNotEmpty)
          Text(
            'teacher.activity_review_screen.category'
                .tr(namedArgs: {'category': category}),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        const SizedBox(height: 8),
        _answerRow('teacher.activity_review_screen.studentPickedOption'.tr(),
            '#${selectedIdx + 1}', isCorrect),
        if (!isCorrect)
          _answerRow('teacher.activity_review_screen.correctOption'.tr(),
              '#${correctIdx + 1}', true),
      ],
    );
  }

  Widget _buildArrangeDetail(Map<String, dynamic> entry) {
    final studentOrder = (entry['studentOrder'] as List?)?.cast<String>() ?? [];
    final correctOrder = (entry['correctOrder'] as List?)?.cast<String>() ?? [];
    final isCorrect = studentOrder.join(' ') == correctOrder.join(' ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _answerRow('teacher.activity_review_screen.studentBuilt'.tr(),
            studentOrder.join(' '), isCorrect),
        if (!isCorrect)
          _answerRow('teacher.activity_review_screen.correctSentence'.tr(),
              correctOrder.join(' '), true),
      ],
    );
  }

  Widget _buildFillBlankDetail(Map<String, dynamic> entry) {
    final sentence = entry['sentence'] as String? ?? '';
    final blanks = (entry['blanks'] as List?)?.cast<Map>() ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sentence.isNotEmpty)
          Text(
            sentence.replaceAll('___', '_____'),
            style: const TextStyle(
              fontStyle: FontStyle.italic,
              color: Colors.black54,
            ),
          ),
        const SizedBox(height: 8),
        ...blanks.asMap().entries.map((e) {
          final given = e.value['given'] as String? ?? '';
          final correct = e.value['correct'] as String? ?? '';
          final isCorrect = given == correct;
          final label = blanks.length > 1
              ? 'teacher.activity_review_screen.blankNumber'
                  .tr(namedArgs: {'number': '${e.key + 1}'})
              : 'teacher.activity_review_screen.studentAnswered'.tr();
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _answerRow(label, given, isCorrect),
                if (!isCorrect)
                  _answerRow(
                      'teacher.activity_review_screen.correct'.tr(), correct, true),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildMatchDetail(Map<String, dynamic> entry) {
    // No per-pair right/wrong to show — see ScreenSix's class doc
    // comment on why 'match' has nothing to grade at completion time.
    final pairs = (entry['pairs'] as List?)?.cast<Map>() ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle, size: 16, color: Colors.green.shade600),
            const SizedBox(width: 6),
            Text(
              'teacher.activity_review_screen.allPairsMatched'
                  .tr(namedArgs: {'count': '${pairs.length}'}),
              style: TextStyle(
                color: Colors.green.shade700,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: pairs.map((p) {
            final en = p['english'] as String? ?? '';
            final tr = p['translated'] as String? ?? '';
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                tr.isNotEmpty ? '$en → $tr' : en,
                style: const TextStyle(fontSize: 13),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildChatDetail(Map<String, dynamic> entry) {
    final turns = (entry['turns'] as List?)?.cast<Map>() ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: turns.map((t) {
        final bubble = t['bubbleEn'] as String? ?? '';
        final reply = t['chosenReply'] as String? ?? '';
        final correct = t['correct'] as bool? ?? false;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                bubble,
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),
              _answerRow(
                  'teacher.activity_review_screen.studentReplied'.tr(), reply, correct),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSentenceBuilderDetail(Map<String, dynamic> entry) {
    final prompt = entry['prompt'] as String? ?? '';
    final studentSentence = entry['studentSentence'] as String? ?? '';
    final correctSentence = entry['correctSentence'] as String? ?? '';
    final isCorrect = studentSentence == correctSentence;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (prompt.isNotEmpty)
          Text(prompt, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _answerRow('teacher.activity_review_screen.studentWrote'.tr(),
            studentSentence, isCorrect),
        if (!isCorrect)
          _answerRow('teacher.activity_review_screen.correctAnswer'.tr(),
              correctSentence, true),
      ],
    );
  }

  // repeat_after_me / listen_and_speak — no right/wrong option to
  // compare against, just the two strings side by side so the teacher
  // can judge pronunciation quality themselves.
  Widget _buildSpeechDetail(Map<String, dynamic> entry) {
    final target = entry['targetPhrase'] as String? ?? '';
    final recognized = entry['recognizedText'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.record_voice_over,
              size: 16,
              color: Colors.grey.shade500,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'teacher.activity_review_screen.target'
                    .tr(namedArgs: {'target': target}),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(Icons.hearing, size: 16, color: Colors.blueGrey),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'teacher.activity_review_screen.systemHeard'
                    .tr(namedArgs: {'text': recognized}),
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReadingDetail(Map<String, dynamic> entry) {
    final questions = (entry['questions'] as List?)?.cast<Map>() ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: questions.asMap().entries.map((e) {
        final q = e.value;
        final questionText = q['question'] as String? ?? '';
        final options = (q['options'] as List?)?.cast<String>() ?? [];
        final selectedIdx = (q['selectedIdx'] as num?)?.toInt() ?? -1;
        final correctIdx = (q['correctIdx'] as num?)?.toInt() ?? -1;
        final isCorrect = selectedIdx == correctIdx;
        final selectedText = (selectedIdx >= 0 && selectedIdx < options.length)
            ? options[selectedIdx]
            : '';
        final correctText = (correctIdx >= 0 && correctIdx < options.length)
            ? options[correctIdx]
            : '';

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'teacher.activity_review_screen.question'.tr(namedArgs: {
                  'number': '${e.key + 1}',
                  'text': questionText,
                }),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              _answerRow('teacher.activity_review_screen.studentAnswered'.tr(),
                  selectedText, isCorrect),
              if (!isCorrect)
                _answerRow('teacher.activity_review_screen.correctAnswer'.tr(),
                    correctText, true),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _answerRow(String label, String value, bool isCorrect) {
    final color = isCorrect ? Colors.green.shade700 : Colors.red.shade700;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isCorrect ? Icons.check_circle : Icons.cancel,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: RichText(
              text: TextSpan(
                // Explicit style root instead of DefaultTextStyle.of(context).style
                // — inheriting the ambient default here was picking up a
                // TextDecoration (the stray yellow underline seen in review),
                // the same root cause as the "Practice Round" banner fix in
                // activity_play_screen.dart. Setting decoration: TextDecoration.none
                // explicitly on both spans below removes it regardless of what
                // the ambient default style happens to be.
                style: const TextStyle(decoration: TextDecoration.none),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  TextSpan(
                    text: value.isEmpty
                        ? 'teacher.activity_review_screen.noAnswer'.tr()
                        : value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
