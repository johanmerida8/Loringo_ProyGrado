import 'package:flutter/material.dart';
import 'package:loringo_app/services/database/database.dart';

class CreatePersonalizedLessonQuizScreen extends StatefulWidget {
  final String groupId;
  final String contentId;
  final String unitId;
  final String lessonId;
  final Color groupColor;

  const CreatePersonalizedLessonQuizScreen({
    super.key,
    required this.groupId,
    required this.contentId,
    required this.unitId,
    required this.lessonId,
    required this.groupColor,
  });

  @override
  State<CreatePersonalizedLessonQuizScreen> createState() =>
      _CreatePersonalizedLessonQuizScreenState();
}

class _CreatePersonalizedLessonQuizScreenState
    extends State<CreatePersonalizedLessonQuizScreen> {
  final Database _db = Database();
  final TextEditingController _titleController = TextEditingController();
  int _xpReward = 5; // 0–10, clamped in database layer

  List<Map<String, dynamic>> activities = [];
  Map<String, List<Map<String, dynamic>>> activityTasks = {};
  Set<String> selectedQuestionIds = {};
  bool isLoading = true;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadActivitiesAndTasks();
  }

  Future<void> _loadActivitiesAndTasks() async {
    try {
      setState(() => isLoading = true);

      // Load activities in this lesson
      final activitiesSnapshot = await _db.getPersonalizedActivities(
        widget.groupId,
        widget.contentId,
        widget.unitId,
        widget.lessonId,
      );

      List<Map<String, dynamic>> loadedActivities = [];

      for (var activityDoc in activitiesSnapshot.docs) {
        final activityId = activityDoc.id;
        final activityData = activityDoc.data() as Map<String, dynamic>;

        loadedActivities.add({
          'id': activityId,
          'title': activityData['title'] ?? 'Untitled',
          'order': activityData['order'] ?? 0,
        });

        // Load tasks for this activity
        final tasksSnapshot = await _db.getPersonalizedTasks(
          widget.groupId,
          widget.contentId,
          widget.unitId,
          widget.lessonId,
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

        activityTasks[activityId] = tasks;
      }

      setState(() {
        activities = loadedActivities;
        isLoading = false;
      });
    } catch (e) {
      print('Error loading activities: $e');
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading activities: $e')),
        );
      }
    }
  }

  void _toggleTaskSelection(String activityId, String taskId) {
    final questionId = '${activityId}_task_$taskId';
    setState(() {
      if (selectedQuestionIds.contains(questionId)) {
        selectedQuestionIds.remove(questionId);
      } else {
        selectedQuestionIds.add(questionId);
      }
    });
  }

  void _toggleActivitySelection(String activityId) {
    final tasks = activityTasks[activityId] ?? [];
    setState(() {
      for (var task in tasks) {
        final questionId = '${activityId}_task_${task['id']}';
        if (selectedQuestionIds.contains(questionId)) {
          selectedQuestionIds.remove(questionId);
        } else {
          selectedQuestionIds.add(questionId);
        }
      }
    });
  }

  bool _isActivityFullySelected(String activityId) {
    final tasks = activityTasks[activityId] ?? [];
    if (tasks.isEmpty) return false;
    return tasks.every((task) {
      final questionId = '${activityId}_task_${task['id']}';
      return selectedQuestionIds.contains(questionId);
    });
  }

  Future<void> _createQuiz() async {
    final title = _titleController.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a quiz title')),
      );
      return;
    }

    if (selectedQuestionIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one task')),
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      final quizId = 'lesson_quiz_${DateTime.now().millisecondsSinceEpoch}';

      await _db.createPersonalizedLessonQuiz(
        contentId: widget.contentId,
        unitId: widget.unitId,
        lessonId: widget.lessonId,
        quizId: quizId,
        title: title,
        questionIds: selectedQuestionIds.toList(),
        xpReward: _xpReward,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Quiz "$title" created successfully'),
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
        title: const Text('Create Lesson Quiz'),
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
                      labelText: 'Quiz Title',
                      hintText: 'e.g., Lesson 1 Reinforcement Quiz',
                      prefixIcon: const Icon(Icons.quiz),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // XP Reward Slider (max 10 — practice only)
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.withOpacity(0.35)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 18),
                            const SizedBox(width: 8),
                            const Text(
                              'XP Reward (practice)',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
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
                          max: 10,
                          divisions: 10,
                          activeColor: Colors.amber,
                          label: '$_xpReward XP',
                          onChanged: (v) => setState(() => _xpReward = v.round()),
                        ),
                        const Text(
                          'Not graded — awarded on completion as practice bonus (max 10 XP)',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Info Banner
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: widget.groupColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: widget.groupColor.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: widget.groupColor),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Select tasks from your activities to include in this reinforcement quiz',
                            style: TextStyle(fontSize: 14),
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

                  if (activities.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          children: [
                            Icon(Icons.folder_open, size: 80, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'No activities found',
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
                    ...List.generate(activities.length, (index) {
                      final activity = activities[index];
                      final activityId = activity['id'];
                      final tasks = activityTasks[activityId] ?? [];
                      final isFullySelected = _isActivityFullySelected(activityId);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            // Activity Header
                            CheckboxListTile(
                              value: isFullySelected,
                              onChanged: (_) =>
                                  _toggleActivitySelection(activityId),
                              title: Text(
                                activity['title'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              subtitle: Text('${tasks.length} tasks'),
                              activeColor: widget.groupColor,
                            ),
                            const Divider(height: 0),
                            // Tasks List
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              child: Column(
                                children: List.generate(tasks.length, (taskIndex) {
                                  final task = tasks[taskIndex];
                                  final taskId = task['id'];
                                  final questionId =
                                      '${activityId}_task_$taskId';
                                  final isSelected =
                                      selectedQuestionIds.contains(questionId);

                                  return CheckboxListTile(
                                    value: isSelected,
                                    onChanged: (_) => _toggleTaskSelection(
                                      activityId,
                                      taskId,
                                    ),
                                    title: Text(
                                      task['question'],
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                    subtitle: Text(
                                      'Type: ${task['type']}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    activeColor: widget.groupColor,
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                  );
                                }),
                              ),
                            ),
                          ],
                        ),
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
                        isSaving ? 'Creating...' : 'Create Lesson Quiz',
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
