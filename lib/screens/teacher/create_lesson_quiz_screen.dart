import 'package:flutter/material.dart';
import 'package:loringo_app/services/database/database.dart';

class CreatePersonalizedLessonQuizScreen extends StatefulWidget {
  final String groupId;
  final String contentId;
  final String unitId;
  final String lessonId;
  final Color groupColor;
  // Edit mode — both required together
  final String? quizId;
  final Map<String, dynamic>? existingData;

  const CreatePersonalizedLessonQuizScreen({
    super.key,
    required this.groupId,
    required this.contentId,
    required this.unitId,
    required this.lessonId,
    required this.groupColor,
    this.quizId,
    this.existingData,
  });

  bool get isEditing => quizId != null;

  @override
  State<CreatePersonalizedLessonQuizScreen> createState() =>
      _CreatePersonalizedLessonQuizScreenState();
}

class _CreatePersonalizedLessonQuizScreenState
    extends State<CreatePersonalizedLessonQuizScreen> {
  final Database _db = Database();
  final TextEditingController _titleController = TextEditingController();
  int _xpReward = 5;

  List<Map<String, dynamic>> activities = [];
  Map<String, List<Map<String, dynamic>>> activityTasks = {};
  Set<String> selectedQuestionIds = {};
  bool isLoading = true;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill title and XP if editing
    if (widget.isEditing && widget.existingData != null) {
      _titleController.text = widget.existingData!['title'] as String? ?? '';
      _xpReward = (widget.existingData!['xpReward'] as num?)?.toInt() ?? 5;
      // Pre-populate selected question IDs
      final existing = widget.existingData!['questionIds'] as List?;
      if (existing != null) {
        selectedQuestionIds = Set<String>.from(existing.map((e) => e.toString()));
      }
    }
    _loadActivitiesAndTasks();
  }

  Future<void> _loadActivitiesAndTasks() async {
    try {
      setState(() => isLoading = true);

      final activitiesSnapshot = await _db.getPersonalizedActivities(
        widget.groupId, widget.contentId, widget.unitId, widget.lessonId,
      );

      final List<Map<String, dynamic>> loadedActivities = [];

      for (final activityDoc in activitiesSnapshot.docs) {
        final activityId   = activityDoc.id;
        final activityData = activityDoc.data() as Map<String, dynamic>;

        loadedActivities.add({
          'id':    activityId,
          'title': activityData['title'] ?? 'Untitled',
          'order': activityData['order'] ?? 0,
        });

        final tasksSnapshot = await _db.getPersonalizedTasks(
          widget.groupId, widget.contentId, widget.unitId, widget.lessonId, activityId,
        );

        final tasks = <Map<String, dynamic>>[];
        for (final taskDoc in tasksSnapshot.docs) {
          final taskData = taskDoc.data() as Map<String, dynamic>;
          tasks.add({
            'id':       taskDoc.id,
            'question': taskData['question'] ?? 'Untitled Task',
            'type':     taskData['type'] ?? '',
          });
        }
        activityTasks[activityId] = tasks;
      }

      setState(() {
        activities = loadedActivities;
        isLoading  = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading activities: $e')));
      }
    }
  }

  // ── Selection helpers ──────────────────────────────────────────────────────

  String _questionId(String activityId, String taskId) => '${activityId}_task_$taskId';

  void _toggleTask(String activityId, String taskId) {
    final id = _questionId(activityId, taskId);
    setState(() {
      if (selectedQuestionIds.contains(id)) selectedQuestionIds.remove(id);
      else selectedQuestionIds.add(id);
    });
  }

  void _toggleActivity(String activityId) {
    final tasks = activityTasks[activityId] ?? [];
    final allSelected = _isActivityFullySelected(activityId);
    setState(() {
      for (final task in tasks) {
        final id = _questionId(activityId, task['id'] as String);
        if (allSelected) selectedQuestionIds.remove(id);
        else selectedQuestionIds.add(id);
      }
    });
  }

  bool _isActivityFullySelected(String activityId) {
    final tasks = activityTasks[activityId] ?? [];
    if (tasks.isEmpty) return false;
    return tasks.every((t) => selectedQuestionIds.contains(_questionId(activityId, t['id'] as String)));
  }

  bool _isActivityPartiallySelected(String activityId) {
    final tasks = activityTasks[activityId] ?? [];
    if (tasks.isEmpty) return false;
    final selected = tasks.where((t) => selectedQuestionIds.contains(_questionId(activityId, t['id'] as String))).length;
    return selected > 0 && selected < tasks.length;
  }

  // ── Save / Update ──────────────────────────────────────────────────────────

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a quiz title')));
      return;
    }
    if (selectedQuestionIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select at least one task')));
      return;
    }

    setState(() => isSaving = true);
    try {
      if (widget.isEditing) {
        // Update existing quiz
        await _db.updatePersonalizedLessonQuiz(
          quizId:   widget.quizId!,
          title:    title,
          xpReward: _xpReward,
          questionIds: selectedQuestionIds.toList(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Quiz updated successfully'), backgroundColor: Colors.green),
          );
          Navigator.pop(context);
        }
      } else {
        // Create new quiz
        final quizId = 'lesson_quiz_${DateTime.now().millisecondsSinceEpoch}';
        await _db.createPersonalizedLessonQuiz(
          contentId:   widget.contentId,
          unitId:      widget.unitId,
          lessonId:    widget.lessonId,
          quizId:      quizId,
          title:       title,
          questionIds: selectedQuestionIds.toList(),
          xpReward:    _xpReward,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✅ Quiz "$title" created successfully'), backgroundColor: Colors.green),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

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
          widget.isEditing ? 'Edit Lesson Quiz' : 'Create Lesson Quiz',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
              child: Text(
                '${selectedQuestionIds.length} selected',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Title ────────────────────────────────────────────────
                  TextFormField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      labelText: 'Quiz Title',
                      hintText: 'e.g., Lesson 1 Reinforcement Quiz',
                      prefixIcon: Icon(Icons.quiz_outlined, color: c),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c, width: 2)),
                      filled: true, fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── XP Reward ─────────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(color: Colors.amber.withOpacity(0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber.withOpacity(0.35))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                        const SizedBox(width: 8),
                        const Text('XP Reward (practice)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        const Spacer(),
                        Text('$_xpReward XP', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.amber)),
                      ]),
                      Slider(value: _xpReward.toDouble(), min: 0, max: 10, divisions: 10, activeColor: Colors.amber, label: '$_xpReward XP', onChanged: (v) => setState(() => _xpReward = v.round())),
                      const Text('Not graded — awarded on completion as practice bonus (max 10 XP)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ]),
                  ),
                  const SizedBox(height: 16),

                  // ── Info banner ───────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: c.withOpacity(0.07), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.withOpacity(0.2))),
                    child: Row(children: [
                      Icon(Icons.info_outline, color: c, size: 18),
                      const SizedBox(width: 12),
                      Expanded(child: Text('Select tasks from your activities to include as reinforcement questions.', style: TextStyle(fontSize: 13, color: Colors.grey.shade700))),
                    ]),
                  ),
                  const SizedBox(height: 20),

                  // ── Activities list header ────────────────────────────────
                  Row(children: [
                    Text('Select Tasks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                      child: Text('${selectedQuestionIds.length} selected', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c)),
                    ),
                  ]),
                  const SizedBox(height: 12),

                  if (activities.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(children: [
                        Icon(Icons.folder_open_outlined, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text('No activities found', style: TextStyle(fontSize: 15, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Text('Create activities in this lesson first', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                      ]),
                    )
                  else
                    ...activities.map((activity) => _buildActivityCard(activity, c)),

                  const SizedBox(height: 32),

                  // ── Save button ───────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c,
                        disabledBackgroundColor: Colors.grey.shade400,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: isSaving
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text(
                              widget.isEditing ? 'Save Changes' : 'Create Lesson Quiz',
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }

  Widget _buildActivityCard(Map<String, dynamic> activity, Color c) {
    final activityId     = activity['id'] as String;
    final tasks          = activityTasks[activityId] ?? [];
    final fullySelected  = _isActivityFullySelected(activityId);
    final partialSelected = _isActivityPartiallySelected(activityId);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: fullySelected ? c : (partialSelected ? c.withOpacity(0.4) : Colors.grey.shade200),
          width: fullySelected ? 2 : 1.5,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          // ── Activity header with checkbox ─────────────────────────────
          InkWell(
            onTap: () => _toggleActivity(activityId),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              decoration: BoxDecoration(
                color: fullySelected ? c.withOpacity(0.06) : Colors.grey.shade50,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
              ),
              child: Row(children: [
                // Custom checkbox indicator
                Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: fullySelected ? c : (partialSelected ? c.withOpacity(0.3) : Colors.white),
                    border: Border.all(color: fullySelected ? c : Colors.grey.shade400, width: 2),
                  ),
                  child: fullySelected
                      ? const Icon(Icons.check, size: 13, color: Colors.white)
                      : partialSelected
                          ? Icon(Icons.remove, size: 13, color: c)
                          : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(activity['title'] as String, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: fullySelected ? c : Colors.black87)),
                    Text('${tasks.length} task${tasks.length != 1 ? 's' : ''}', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  ]),
                ),
                Icon(Icons.expand_more, color: Colors.grey.shade400, size: 18),
              ]),
            ),
          ),

          // ── Task list ─────────────────────────────────────────────────
          if (tasks.isNotEmpty) ...[
            Divider(height: 0, color: Colors.grey.shade100),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                children: tasks.map((task) {
                  final taskId    = task['id'] as String;
                  final qId       = _questionId(activityId, taskId);
                  final isSelected = selectedQuestionIds.contains(qId);
                  final taskType  = task['type'] as String? ?? '';

                  return InkWell(
                    onTap: () => _toggleTask(activityId, taskId),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? c.withOpacity(0.05) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isSelected ? c.withOpacity(0.3) : Colors.grey.shade100),
                      ),
                      child: Row(children: [
                        Container(
                          width: 20, height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected ? c : Colors.white,
                            border: Border.all(color: isSelected ? c : Colors.grey.shade400, width: 2),
                          ),
                          child: isSelected ? const Icon(Icons.check, size: 11, color: Colors.white) : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(task['question'] as String, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: isSelected ? Colors.black87 : Colors.grey.shade700)),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
                              child: Text(taskType, style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                            ),
                          ]),
                        ),
                      ]),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}