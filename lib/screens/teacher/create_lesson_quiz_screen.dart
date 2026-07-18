import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_screen_header.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

// NOTE: previously had a Scaffold.appBar (solid `groupColor` bar with a
// "N selected" pill in actions:). Replaced with TeacherScreenHeader to
// match the rest of the hierarchy. The "N selected" counter that used to
// live in the AppBar's actions now sits as a small chip directly under
// the header — same information, no colored bar needed to hold it.

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

  // ─── Type label resolver ────────────────────────────────────────────────
  // Mirrors task_list_screen.dart's _typeLabel() — without this, the raw
  // 'type' string (image_select, arrange, etc.) was printed straight to
  // the badge under each task, underscores and all.
  //
  // FLAG PARA CJ: este mapa ya le faltaban 'sound_match' y 'odd_one_out'
  // desde antes de que empezara a tocar este archivo — no los agregué
  // porque no formaba parte de lo pedido en su momento, pero un task de
  // esos tipos va a mostrar el id crudo en vez de un label legible en
  // este quiz. 'compare' y 'flashcard' fueron evaluados y descartados —
  // ya no existen en el sistema, así que se quitaron de este mapa.
  String _typeLabel(String type) {
    const map = {
      'image_select':         'Image Selection',
      'image_select_reverse': 'Image Select Reverse',
      'fill_blank':           'Fill the Blank',
      'arrange':              'Arrange Words',
      'complete_the_chat':    'Complete Chat',
      'match':                'Match',
      'reading':              'Reading',
      'sentence_builder':     'Sentence Builder',
      'repeat_after_me':      'Repeat After Me',
      'listen_and_speak':     'Listen & Speak',
    };
    return map[type] ?? type;
  }

  // ─── Task display-text resolver ────────────────────────────────────────
  // Mirrors task_list_screen.dart's _displayTitle(): 'title' is the
  // mandatory field a teacher fills in per task and is what should
  // identify it here. Falls back to 'question' (still valid for
  // image_select / image_select_reverse / complete_the_chat, which use
  // question as their natural label) and reading's nested data.title for
  // tasks created before 'title' existed. Without this, every task type
  // that never had a 'question' field (sentence_builder, arrange,
  // fill_blank, match, listen_and_speak, repeat_after_me) always fell
  // through to the literal string 'Untitled Task' here.
  String _taskDisplayText(Map<String, dynamic> taskData) {
    final title = taskData['title'] as String?;
    if (title != null && title.trim().isNotEmpty) return title;

    final type = taskData['type'] as String? ?? '';
    if (type == 'reading') {
      final inner = taskData['data'] as Map<String, dynamic>?;
      final innerTitle = inner?['title'] as String?;
      if (innerTitle != null && innerTitle.trim().isNotEmpty) return innerTitle;
    }

    final question = taskData['question'] as String?;
    if (question != null && question.trim().isNotEmpty) return question;

    return 'Untitled Task';
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
            'id':          taskDoc.id,
            // Kept the key name 'question' so the rest of this file (and
            // _buildActivityCard's task['question'] read below) doesn't
            // need to change — but the VALUE now comes from the resolver
            // above instead of only ever reading taskData['question'].
            'question':    _taskDisplayText(taskData),
            'type':        taskData['type'] ?? '',
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
            const SnackBar(content: Text('Quiz updated successfully'), backgroundColor: AppColors.success),
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
            SnackBar(content: Text('Quiz "$title" created successfully'), backgroundColor: AppColors.success),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger));
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
      backgroundColor: AppColors.scaffoldBackground,
      body: Column(
        children: [
          TeacherScreenHeader(
            title: widget.isEditing ? 'Edit Lesson Quiz' : 'Create Lesson Quiz',
            color: c,
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Selection counter chip ───────────────────────────────
                  // Replaces the AppBar's "N selected" pill.
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                      child: Text(
                        '${selectedQuestionIds.length} selected',
                        style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // ── Title ────────────────────────────────────────────────
                  TextFormField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      labelText: 'Quiz Title',
                      hintText: 'e.g., Lesson 1 Reinforcement Quiz',
                      prefixIcon: Icon(Icons.quiz_outlined, color: c),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md), borderSide: BorderSide(color: AppColors.divider)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md), borderSide: BorderSide(color: c, width: 2)),
                      filled: true, fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // ── XP Reward ─────────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                    decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.06), borderRadius: BorderRadius.circular(AppRadii.md), border: Border.all(color: AppColors.warning.withOpacity(0.35))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Icon(Icons.star_rounded, color: AppColors.warning, size: 18),
                        const SizedBox(width: 8),
                        const Text('XP Reward (practice)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        const Spacer(),
                        Text('$_xpReward XP', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.warning)),
                      ]),
                      Slider(value: _xpReward.toDouble(), min: 0, max: 10, divisions: 10, activeColor: AppColors.warning, label: '$_xpReward XP', onChanged: (v) => setState(() => _xpReward = v.round())),
                      const Text('Not graded — awarded on completion as practice bonus (max 10 XP)', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                    ]),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // ── Info banner ───────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(color: c.withOpacity(0.07), borderRadius: BorderRadius.circular(AppRadii.md), border: Border.all(color: c.withOpacity(0.2))),
                    child: Row(children: [
                      Icon(Icons.info_outline, color: c, size: 18),
                      const SizedBox(width: AppSpacing.sm),
                      const Expanded(child: Text('Select tasks from your activities to include as reinforcement questions.', style: TextStyle(fontSize: 13, color: Colors.black87))),
                    ]),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // ── Activities list header ────────────────────────────────
                  Row(children: [
                    const Text('Select Tasks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                      child: Text('${selectedQuestionIds.length} selected', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c)),
                    ),
                  ]),
                  const SizedBox(height: AppSpacing.sm),

                  if (activities.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(children: [
                        Icon(Icons.folder_open_outlined, size: 64, color: AppColors.divider),
                        const SizedBox(height: AppSpacing.md),
                        const Text('No activities found', style: TextStyle(fontSize: 15, color: AppColors.muted, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        const Text('Create activities in this lesson first', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                      ]),
                    )
                  else
                    ...activities.map((activity) => _buildActivityCard(activity, c)),

                  const SizedBox(height: AppSpacing.xl),

                  // ── Save button ───────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c,
                        disabledBackgroundColor: AppColors.divider,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
                        elevation: 0,
                      ),
                      child: isSaving
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: AppColors.onPrimary, strokeWidth: 2))
                          : Text(
                              widget.isEditing ? 'Save Changes' : 'Create Lesson Quiz',
                              style: const TextStyle(color: AppColors.onPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityCard(Map<String, dynamic> activity, Color c) {
    final activityId     = activity['id'] as String;
    final tasks          = activityTasks[activityId] ?? [];
    final fullySelected  = _isActivityFullySelected(activityId);
    final partialSelected = _isActivityPartiallySelected(activityId);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(
          color: fullySelected ? c : (partialSelected ? c.withOpacity(0.4) : AppColors.divider),
          width: fullySelected ? 2 : 1.5,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          // ── Activity header with checkbox ─────────────────────────────
          InkWell(
            onTap: () => _toggleActivity(activityId),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.md)),
            child: Container(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
              decoration: BoxDecoration(
                color: fullySelected ? c.withOpacity(0.06) : Colors.grey.shade50,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.md)),
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
                      ? const Icon(Icons.check, size: 13, color: AppColors.onPrimary)
                      : partialSelected
                          ? Icon(Icons.remove, size: 13, color: c)
                          : null,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(activity['title'] as String, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: fullySelected ? c : Colors.black87)),
                    Text('${tasks.length} task${tasks.length != 1 ? 's' : ''}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  ]),
                ),
                const Icon(Icons.expand_more, color: AppColors.muted, size: 18),
              ]),
            ),
          ),

          // ── Task list ─────────────────────────────────────────────────
          if (tasks.isNotEmpty) ...[
            Divider(height: 0, color: Colors.grey.shade100),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 8),
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
                          child: isSelected ? const Icon(Icons.check, size: 11, color: AppColors.onPrimary) : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(task['question'] as String, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: isSelected ? Colors.black87 : Colors.grey.shade700)),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
                              child: Text(_typeLabel(taskType), style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
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