import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/create_lesson_quiz_screen.dart';
import 'package:loringo_app/screens/teacher/create_unit_quiz_screen.dart';
import 'package:loringo_app/services/database/database.dart';

enum QuizManagementType { lesson, unit }

class QuizManagementScreen extends StatelessWidget {
  final QuizManagementType type;
  final String groupId;
  final String contentId;
  final String unitId;
  final String? lessonId;
  final String title;
  final Color groupColor;

  const QuizManagementScreen({
    super.key,
    required this.type,
    required this.groupId,
    required this.contentId,
    required this.unitId,
    this.lessonId,
    required this.title,
    required this.groupColor,
  }) : assert(
          type == QuizManagementType.unit || lessonId != null,
          'lessonId is required for lesson quiz management',
        );

  String get _screenTitle =>
      type == QuizManagementType.lesson ? 'Lesson Quizzes' : 'Unit Tests';

  String get _emptyLabel => type == QuizManagementType.lesson
      ? 'No quizzes yet for this lesson'
      : 'No unit tests yet';

  @override
  Widget build(BuildContext context) {
    final db = Database();
    final stream = type == QuizManagementType.lesson
        ? db.getPersonalizedLessonQuizzesStream(contentId, unitId, lessonId!)
        : db.getPersonalizedUnitQuizzesStream(contentId, unitId);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: groupColor,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _screenTitle,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              title,
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontSize: 13,
              ),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: stream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final quizzes = snapshot.data!.docs;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (quizzes.isEmpty)
                _EmptyState(
                  label: _emptyLabel,
                  icon: type == QuizManagementType.lesson
                      ? Icons.quiz
                      : Icons.assignment,
                  color: groupColor,
                )
              else
                ...quizzes.map(
                  (doc) => _QuizCard(
                    doc: doc,
                    type: type,
                    groupId: groupId,
                    contentId: contentId,
                    unitId: unitId,
                    lessonId: lessonId,
                    groupColor: groupColor,
                    db: db,
                  ),
                ),
              const SizedBox(height: 80),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: groupColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(
          type == QuizManagementType.lesson
              ? 'New Lesson Quiz'
              : 'New Unit Test',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        onPressed: () => _navigateToCreate(context),
      ),
    );
  }

  void _navigateToCreate(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => type == QuizManagementType.lesson
            ? CreatePersonalizedLessonQuizScreen(
                groupId: groupId,
                contentId: contentId,
                unitId: unitId,
                lessonId: lessonId!,
                groupColor: groupColor,
              )
            : CreatePersonalizedUnitQuizScreen(
                groupId: groupId,
                contentId: contentId,
                unitId: unitId,
                groupColor: groupColor,
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[500],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the button below to create one',
            style: TextStyle(fontSize: 13, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _QuizCard extends StatelessWidget {
  const _QuizCard({
    required this.doc,
    required this.type,
    required this.groupId,
    required this.contentId,
    required this.unitId,
    required this.lessonId,
    required this.groupColor,
    required this.db,
  });

  final QueryDocumentSnapshot doc;
  final QuizManagementType type;
  final String groupId;
  final String contentId;
  final String unitId;
  final String? lessonId;
  final Color groupColor;
  final Database db;

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final quizTitle = data['title'] ?? 'Untitled';
    final questionIds = (data['questionIds'] as List?)?.length ?? 0;
    final xp = data['xpReward'] ?? 0;
    final isGraded = data['isGraded'] == true;
    final passingScore = data['passingScore'] ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: groupColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isGraded ? Icons.assignment : Icons.quiz,
                    color: groupColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    quizTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _Chip(
                        icon: Icons.help_outline,
                        label: '$questionIds questions',
                        color: groupColor,
                      ),
                      _Chip(
                        icon: Icons.star,
                        label: '$xp XP',
                        color: Colors.amber[700]!,
                      ),
                      if (isGraded)
                        _Chip(
                          icon: Icons.check_circle_outline,
                          label: 'Pass: $passingScore',
                          color: Colors.green,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.edit_outlined, color: groupColor),
                  tooltip: 'Edit',
                  onPressed: () => _showEditSheet(context, data),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: 'Delete',
                  onPressed: () => _confirmDelete(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showEditSheet(BuildContext context, Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditQuizSheet(
        doc: doc,
        type: type,
        contentId: contentId,
        unitId: unitId,
        lessonId: lessonId,
        groupColor: groupColor,
        db: db,
        initialTitle: data['title'] ?? '',
        initialXp: (data['xpReward'] as num?)?.toInt() ?? 0,
        initialPassingScore: (data['passingScore'] as num?)?.toInt() ?? 1,
        questionCount: (data['questionIds'] as List?)?.length ?? 1,
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Quiz'),
        content: const Text(
          'This quiz will be permanently deleted. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true || !context.mounted) return;

    try {
      if (type == QuizManagementType.lesson) {
        await db.deletePersonalizedLessonQuiz(
          contentId: contentId,
          unitId: unitId,
          lessonId: lessonId!,
          quizId: doc.id,
        );
      } else {
        await db.deletePersonalizedUnitQuiz(
          contentId: contentId,
          unitId: unitId,
          quizId: doc.id,
        );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Quiz deleted'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting quiz: $e')),
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _EditQuizSheet extends StatefulWidget {
  const _EditQuizSheet({
    required this.doc,
    required this.type,
    required this.contentId,
    required this.unitId,
    required this.lessonId,
    required this.groupColor,
    required this.db,
    required this.initialTitle,
    required this.initialXp,
    required this.initialPassingScore,
    required this.questionCount,
  });

  final QueryDocumentSnapshot doc;
  final QuizManagementType type;
  final String contentId;
  final String unitId;
  final String? lessonId;
  final Color groupColor;
  final Database db;
  final String initialTitle;
  final int initialXp;
  final int initialPassingScore;
  final int questionCount;

  @override
  State<_EditQuizSheet> createState() => _EditQuizSheetState();
}

class _EditQuizSheetState extends State<_EditQuizSheet> {
  late final TextEditingController _titleCtrl;
  late int _xp;
  late int _passing;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.initialTitle);
    _xp = widget.initialXp;
    _passing = widget.initialPassingScore.clamp(
      1,
      widget.questionCount > 0 ? widget.questionCount : 1,
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a title')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.type == QuizManagementType.lesson) {
        await widget.db.updatePersonalizedLessonQuiz(
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: widget.lessonId!,
          quizId: widget.doc.id,
          title: title,
          xpReward: _xp,
        );
      } else {
        await widget.db.updatePersonalizedUnitQuiz(
          contentId: widget.contentId,
          unitId: widget.unitId,
          quizId: widget.doc.id,
          title: title,
          passingScore: _passing,
          xpReward: _xp,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLesson = widget.type == QuizManagementType.lesson;
    final maxXp = isLesson ? 10 : 100;
    final n = widget.questionCount > 0 ? widget.questionCount : 1;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Edit ${isLesson ? 'Lesson Quiz' : 'Unit Test'}',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: widget.groupColor,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                labelText: 'Title',
                prefixIcon: const Icon(Icons.title),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
            ),
            const SizedBox(height: 20),
            // XP Reward
            _sliderSection(
              label: 'XP Reward',
              value: _xp.toDouble(),
              min: 0,
              max: maxXp.toDouble(),
              divisions: maxXp,
              color: Colors.amber,
              display: '$_xp XP',
              hint: isLesson
                  ? 'Practice bonus (max 10 XP)'
                  : 'Awarded on passing (max 100 XP)',
              onChanged: (v) => setState(() => _xp = v.round()),
            ),
            if (!isLesson) ...[
              const SizedBox(height: 12),
              _sliderSection(
                label: 'Passing Score',
                value: _passing.toDouble(),
                min: 1,
                max: n.toDouble(),
                divisions: n > 1 ? n - 1 : 1,
                color: Colors.green,
                display: '$_passing / $n correct',
                hint: 'Minimum correct answers to pass',
                onChanged: (v) => setState(() => _passing = v.round()),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.groupColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Save Changes',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sliderSection({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required Color color,
    required String display,
    required String hint,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  display,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: color,
            label: display,
            onChanged: onChanged,
          ),
          Text(hint, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}
