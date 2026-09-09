// screens/teacher/lesson_quiz_review_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_screen_header.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

// ── LessonQuizReviewScreen ───────────────────────────────────────────────
//
// Teacher-facing detail view for a student's Lesson Quiz attempt.
// Deliberately a simplified sibling of UnitQuizReviewScreen (the Unit
// Quiz review screen), NOT that screen reused with a flag — the two
// diverge in a way that's easier to keep as separate files than to
// branch inside one:
//
//   Unit Quiz (UnitQuizReviewScreen): generates a graded parent
//   report via Database.saveReportOnly + a push notification, with an
//   "already sent" one-shot gate since a report can't be un-sent.
//
//   Lesson Quiz (this screen): purely a formative, ungraded check-in —
//   same per-question answers[] array shape saved by QuizPlayScreen, but
//   NO report, NO push, NO one-shot gate. The teacher's feedback here is
//   an internal note (Database.saveLessonQuizFeedback) they can revise
//   any time, exactly like ActivityReviewScreen's feedback box.
//
// Both screens read the same students/{studentId}/progress/{quizId}
// document shape (score, answers: List<{selectedIndex, ...}>) because
// QuizPlayScreen's _saveStudentAnswers() writes that shape for every
// quiz regardless of scope — only what happens AFTER loading it differs
// between scope: 'unit' and scope: 'lesson'.
class LessonQuizReviewScreen extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String groupId;
  final String contentId;
  final String unitId;
  final String lessonId;
  final String quizId;
  final String quizTitle;

  const LessonQuizReviewScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.groupId,
    required this.contentId,
    required this.unitId,
    required this.lessonId,
    required this.quizId,
    required this.quizTitle,
  });

  @override
  State<LessonQuizReviewScreen> createState() => _LessonQuizReviewScreenState();
}

class _LessonQuizReviewScreenState extends State<LessonQuizReviewScreen> {
  List<Map<String, dynamic>> _questions = [];
  List<Map<String, dynamic>> _answers = [];
  bool _isLoading = true;
  bool _isSaving = false;
  int _score = 0;
  int _totalQuestions = 0;
  String _feedback = '';

  // Same one-shot lock as ActivityReviewScreen's _feedbackConfirmed —
  // once saved with real text, this note can't be edited again.
  bool _feedbackConfirmed = false;

  final TextEditingController _feedbackController = TextEditingController();

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
      final questionsSnapshot = await Database().getQuizQuestions(
        widget.contentId,
        widget.unitId,
        widget.quizId,
        lessonId: widget.lessonId,
      );

      _questions = questionsSnapshot.docs.map((doc) {
        final d = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          'question': d['question'] ?? '',
          'options': List<String>.from(d['options'] ?? []),
          'correctIndex': d['correctIndex'] as int? ?? 0,
        };
      }).toList();
      _totalQuestions = _questions.length;

      final progressDoc = await FirebaseFirestore.instance
          .collection('teacherGroups')
          .doc(widget.groupId)
          .collection('students')
          .doc(widget.studentId)
          .collection('progress')
          .doc(widget.quizId)
          .get();

      if (progressDoc.exists) {
        final data = progressDoc.data() as Map<String, dynamic>;
        _score = data['correctAnswers'] as int? ?? 0;
        _answers = List<Map<String, dynamic>>.from(data['answers'] ?? []);
        _feedback = data['feedback'] as String? ?? '';
      }

      _feedbackController.text = _feedback;
      _feedbackConfirmed = _feedback.trim().isNotEmpty;
    } catch (e) {
      debugPrint('Error loading lesson quiz review: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveFeedback() async {
    if (_feedback.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'teacher.lesson_quiz_review_screen.pleaseWriteFeedback'.tr())),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final db = Database();
      await db.saveLessonQuizFeedback(
        groupId: widget.groupId,
        studentId: widget.studentId,
        quizId: widget.quizId,
        feedback: _feedback,
      );
      if (mounted) {
        setState(() => _feedbackConfirmed = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('teacher.lesson_quiz_review_screen.feedbackSaved'.tr()),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('teacher.lesson_quiz_review_screen.errorWithMessage'
                  .tr(namedArgs: {'error': '$e'})),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          TeacherScreenHeader(
            title: 'teacher.lesson_quiz_review_screen.reviewTitle'
                .tr(namedArgs: {'title': widget.quizTitle}),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                  // Student info card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: AppColors.info.withOpacity(0.1),
                          child: Text(
                            widget.studentName.isNotEmpty
                                ? widget.studentName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontSize: 22,
                              color: AppColors.info,
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
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                _totalQuestions == 0
                                    ? 'teacher.lesson_quiz_review_screen.noScoreRecorded'
                                        .tr()
                                    : 'teacher.lesson_quiz_review_screen.scoreLabel'
                                        .tr(namedArgs: {
                                        'score': '$_score',
                                        'total': '$_totalQuestions',
                                        'percent':
                                            '${(_score / _totalQuestions * 100).round()}',
                                      }),
                                style: TextStyle(
                                  fontSize: 14,
                                  color:
                                      _totalQuestions > 0 &&
                                          _score >= (_totalQuestions * 0.7)
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.info.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'teacher.lesson_quiz_review_screen.lessonQuiz'.tr(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.info,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  Text(
                    'teacher.lesson_quiz_review_screen.questionsReview'.tr(),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  if (_questions.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Center(
                        child: Text(
                          'teacher.lesson_quiz_review_screen.noQuestionsFound'
                              .tr(),
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),
                    )
                  else
                    ..._questions.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final q = entry.value;
                      final studentAnswer = idx < _answers.length
                          ? _answers[idx]['selectedIndex'] as int?
                          : null;
                      final isCorrect = studentAnswer == q['correctIndex'];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isCorrect
                                ? Colors.green.shade200
                                : Colors.red.shade200,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    isCorrect
                                        ? Icons.check_circle
                                        : Icons.cancel,
                                    color: isCorrect
                                        ? Colors.green
                                        : Colors.red,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'teacher.lesson_quiz_review_screen.questionLabel'
                                          .tr(namedArgs: {
                                        'number': '${idx + 1}',
                                        'text': '${q['question']}',
                                      }),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ...List.generate((q['options'] as List).length, (
                                optIdx,
                              ) {
                                final isStudentChoice = studentAnswer == optIdx;
                                final isCorrectChoice =
                                    q['correctIndex'] == optIdx;
                                Color? bgColor;
                                if (isCorrectChoice)
                                  bgColor = Colors.green.shade50;
                                else if (isStudentChoice && !isCorrectChoice)
                                  bgColor = Colors.red.shade50;
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 4),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: bgColor,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isCorrectChoice
                                          ? Colors.green
                                          : (isStudentChoice
                                                ? Colors.red
                                                : Colors.grey.shade200),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        '${String.fromCharCode(65 + optIdx)}.',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(q['options'][optIdx]),
                                      ),
                                      if (isCorrectChoice)
                                        const Icon(
                                          Icons.check_circle,
                                          color: Colors.green,
                                          size: 16,
                                        ),
                                      if (isStudentChoice && !isCorrectChoice)
                                        const Icon(
                                          Icons.cancel,
                                          color: Colors.red,
                                          size: 16,
                                        ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      );
                    }),

                  const SizedBox(height: 24),
                  Text(
                    'teacher.lesson_quiz_review_screen.teacherFeedback'.tr(),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _feedbackController,
                    onChanged: (v) => _feedback = v,
                    maxLines: 5,
                    enabled: !_feedbackConfirmed,
                    decoration: InputDecoration(
                      hintText: 'teacher.lesson_quiz_review_screen.feedbackHint'
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
                        ? 'teacher.lesson_quiz_review_screen.feedbackConfirmedNote'
                            .tr()
                        : 'teacher.lesson_quiz_review_screen.feedbackVisibleNote'
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
                                  ? 'teacher.lesson_quiz_review_screen.feedbackConfirmedButton'
                                      .tr()
                                  : 'teacher.lesson_quiz_review_screen.saveFeedback'
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
}
