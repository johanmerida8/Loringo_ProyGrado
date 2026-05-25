import 'package:flutter/material.dart';
import 'package:loringo_app/services/database/database.dart';

class CreatePersonalizedUnitQuizScreen extends StatefulWidget {
  final String groupId;
  final String contentId;
  final String unitId;
  final Color groupColor;

  const CreatePersonalizedUnitQuizScreen({
    super.key,
    required this.groupId,
    required this.contentId,
    required this.unitId,
    required this.groupColor,
  });

  @override
  State<CreatePersonalizedUnitQuizScreen> createState() =>
      _CreatePersonalizedUnitQuizScreenState();
}

class _CreatePersonalizedUnitQuizScreenState
    extends State<CreatePersonalizedUnitQuizScreen> {
  final Database _db = Database();
  final TextEditingController _titleController = TextEditingController();

  // Passing score = number of questions that must be correct (dynamic, based on selection)
  int _passingScore = 1;
  // XP Reward: 0–100, hard-clamped in db layer, starts at 15
  int _xpReward = 15;

  List<Map<String, dynamic>> lessons = [];
  Map<String, List<Map<String, dynamic>>> lessonActivities = {};
  Map<String, Map<String, List<Map<String, dynamic>>>> activityTasks = {};
  Set<String> selectedQuestionIds = {};
  bool isLoading = true;
  bool isSaving = false;

  void _clampPassingScore() {
    final n = selectedQuestionIds.length;
    _passingScore = n == 0 ? 1 : _passingScore.clamp(1, n);
  }

  @override
  void initState() {
    super.initState();
    _loadLessonsAndActivities();
  }

  Future<void> _loadLessonsAndActivities() async {
    try {
      setState(() => isLoading = true);

      // Load lessons in this unit
      final lessonsSnapshot = await _db.getPersonalizedLessons(
        widget.groupId,
        widget.contentId,
        widget.unitId,
      );

      List<Map<String, dynamic>> loadedLessons = [];
      Map<String, Map<String, List<Map<String, dynamic>>>> allActivityTasks = {};

      for (var lessonDoc in lessonsSnapshot.docs) {
        final lessonId = lessonDoc.id;
        final lessonData = lessonDoc.data() as Map<String, dynamic>;

        loadedLessons.add({
          'id': lessonId,
          'title': lessonData['title'] ?? 'Untitled',
          'order': lessonData['order'] ?? 0,
        });

        // Load activities for this lesson
        final activitiesSnapshot = await _db.getPersonalizedActivities(
          widget.groupId,
          widget.contentId,
          widget.unitId,
          lessonId,
        );

        List<Map<String, dynamic>> activities = [];
        allActivityTasks[lessonId] = {};

        for (var activityDoc in activitiesSnapshot.docs) {
          final activityId = activityDoc.id;
          final activityData = activityDoc.data() as Map<String, dynamic>;

          activities.add({
            'id': activityId,
            'title': activityData['title'] ?? 'Untitled',
            'order': activityData['order'] ?? 0,
          });

          // Load tasks for this activity
          final tasksSnapshot = await _db.getPersonalizedTasks(
            widget.groupId,
            widget.contentId,
            widget.unitId,
            lessonId,
            activityId,
          );

          List<Map<String, dynamic>> tasks = [];
          for (var taskDoc in tasksSnapshot.docs) {
            final taskId = taskDoc.id;
            final taskData = taskDoc.data() as Map<String, dynamic>;
            tasks.add({
              'id': taskId,
              'question': taskData['question'] ?? 'Untitled Task',
              'type': taskData['type'] ?? '',
            });
          }

          allActivityTasks[lessonId]![activityId] = tasks;
        }

        lessonActivities[lessonId] = activities;
      }

      setState(() {
        lessons = loadedLessons;
        activityTasks = allActivityTasks;
        isLoading = false;
      });
    } catch (e) {
      print('Error loading lessons: $e');
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading lessons: $e')),
        );
      }
    }
  }

  void _toggleTaskSelection(String taskId) {
    setState(() {
      if (selectedQuestionIds.contains(taskId)) {
        selectedQuestionIds.remove(taskId);
      } else {
        selectedQuestionIds.add(taskId);
      }
      _clampPassingScore();
    });
  }

  void _toggleActivitySelection(String lessonId, String activityId) {
    final tasks = activityTasks[lessonId]?[activityId] ?? [];
    setState(() {
      for (var task in tasks) {
        final questionId = '${activityId}_task_${task['id']}';
        if (selectedQuestionIds.contains(questionId)) {
          selectedQuestionIds.remove(questionId);
        } else {
          selectedQuestionIds.add(questionId);
        }
      }
      _clampPassingScore();
    });
  }

  bool _isActivityFullySelected(String lessonId, String activityId) {
    final tasks = activityTasks[lessonId]?[activityId] ?? [];
    if (tasks.isEmpty) return false;
    return tasks.every((task) {
      final questionId = '${activityId}_task_${task['id']}';
      return selectedQuestionIds.contains(questionId);
    });
  }

  String? _validateTitle(String title) {
    if (title.isEmpty) return 'Please enter a test title';
    if (title.length < 3) return 'Title must be at least 3 characters';
    if (title.length > 80) return 'Title must be 80 characters or fewer';
    final validName = RegExp(r"^[\w\s\-'\.áéíóúÁÉÍÓÚñÑüÜ]+$");
    if (!validName.hasMatch(title)) return 'Title contains invalid characters';
    return null;
  }

  Future<void> _createQuiz() async {
    final title = _titleController.text.trim();

    final titleError = _validateTitle(title);
    if (titleError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(titleError)),
      );
      return;
    }

    if (selectedQuestionIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must select at least one task before creating the test'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      final quizId = 'unit_test_${DateTime.now().millisecondsSinceEpoch}';

      await _db.createPersonalizedUnitQuiz(
        contentId: widget.contentId,
        unitId: widget.unitId,
        quizId: quizId,
        title: title,
        questionIds: selectedQuestionIds.toList(),
        passingScore: _passingScore,
        xpReward: _xpReward,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Unit Test "$title" created successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      print('Error creating quiz: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating quiz: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => isSaving = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: widget.groupColor,
        title: const Text('Create Unit Test'),
        elevation: 0,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title Input
                  TextFormField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      labelText: 'Test Title',
                      hintText: 'e.g., Unit 1 Final Exam',
                      prefixIcon: const Icon(Icons.assignment),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Passing Score — X out of N questions
                  Builder(builder: (context) {
                    final n = selectedQuestionIds.length;
                    final hasQuestions = n > 0;
                    final pct = hasQuestions
                        ? ((_passingScore / n) * 100).round()
                        : 0;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.blue.withOpacity(
                                hasQuestions ? 0.35 : 0.15)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.trending_up,
                                  color: Colors.blue, size: 18),
                              const SizedBox(width: 8),
                              const Text(
                                'Passing score',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14),
                              ),
                              const Spacer(),
                              hasQuestions
                                  ? RichText(
                                      text: TextSpan(
                                        children: [
                                          TextSpan(
                                            text:
                                                '$_passingScore / $n',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: Colors.blue,
                                            ),
                                          ),
                                          TextSpan(
                                            text: '  ($pct%)',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : Text(
                                      'Select tasks first',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[400]),
                                    ),
                            ],
                          ),
                          Slider(
                            value: hasQuestions
                                ? _passingScore.toDouble()
                                : 1,
                            min: 1,
                            max: hasQuestions ? n.toDouble() : 1,
                            divisions: hasQuestions ? (n > 1 ? n - 1 : 1) : 1,
                            activeColor: Colors.blue,
                            label:
                                hasQuestions ? '$_passingScore / $n' : '—',
                            onChanged: hasQuestions
                                ? (v) => setState(
                                    () => _passingScore = v.round())
                                : null,
                          ),
                          Text(
                            hasQuestions
                                ? 'Students must answer at least $_passingScore out of $n questions correctly'
                                : 'Select tasks below — the slider will activate automatically',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 16),

                  // XP Reward Slider (0–100, default 15)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: Colors.amber.withOpacity(0.35)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.star,
                                color: Colors.amber, size: 18),
                            const SizedBox(width: 8),
                            const Text(
                              'XP Reward',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            const Spacer(),
                            Text(
                              '$_xpReward XP',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.amber,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _xpReward.toDouble(),
                          min: 0,
                          max: 100,
                          divisions: 20,
                          activeColor: Colors.amber,
                          label: '$_xpReward XP',
                          onChanged: (v) =>
                              setState(() => _xpReward = v.round()),
                        ),
                        const Text(
                          'Awarded on passing this graded test (max 100 XP)',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Info Banner
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.red.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.red[700]),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'This is a graded exam. Scores will be reported to parents.',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Activities List
                  Text(
                    'Select Tasks (${selectedQuestionIds.length} selected)',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (lessons.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          children: [
                            Icon(Icons.folder_open, size: 80, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'No lessons found',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ...List.generate(lessons.length, (lessonIndex) {
                      final lesson = lessons[lessonIndex];
                      final lessonId = lesson['id'];
                      final activities = lessonActivities[lessonId] ?? [];

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Lesson Header
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              lesson['title'],
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: widget.groupColor,
                              ),
                            ),
                          ),

                          // Activities in Lesson
                          ...List.generate(activities.length, (activityIndex) {
                            final activity = activities[activityIndex];
                            final activityId = activity['id'];
                            final tasks =
                                activityTasks[lessonId]?[activityId] ?? [];
                            final isFullySelected =
                                _isActivityFullySelected(lessonId, activityId);

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: 1,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  // Activity Header
                                  CheckboxListTile(
                                    value: isFullySelected,
                                    onChanged: (_) => _toggleActivitySelection(
                                      lessonId,
                                      activityId,
                                    ),
                                    title: Text(
                                      activity['title'],
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                    subtitle: Text('${tasks.length} tasks'),
                                    activeColor: widget.groupColor,
                                  ),
                                  if (tasks.isNotEmpty)
                                    Column(
                                      children: [
                                        const Divider(height: 0),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 8,
                                          ),
                                          child: Column(
                                            children: List.generate(
                                              tasks.length,
                                              (taskIndex) {
                                                final task = tasks[taskIndex];
                                                final taskId = task['id'];
                                                final questionId =
                                                    '${activityId}_task_$taskId';
                                                final isSelected =
                                                    selectedQuestionIds
                                                        .contains(questionId);

                                                return CheckboxListTile(
                                                  value: isSelected,
                                                  onChanged: (_) =>
                                                      _toggleTaskSelection(
                                                    questionId,
                                                  ),
                                                  title: Text(
                                                    task['question'],
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                  subtitle: Text(
                                                    'Type: ${task['type']}',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  activeColor:
                                                      widget.groupColor,
                                                  contentPadding: EdgeInsets.zero,
                                                  dense: true,
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 8),
                        ],
                      );
                    }),

                  const SizedBox(height: 32),

                  // Create Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: isSaving ? null : _createQuiz,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.groupColor,
                        disabledBackgroundColor: Colors.grey[400],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: isSaving
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white.withOpacity(0.7),
                                ),
                              ),
                            )
                          : const Icon(Icons.check_circle),
                      label: Text(
                        isSaving ? 'Creating...' : 'Create Unit Test',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }
}
