// create_task_screen.dart
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/task_types/listen_and_speak_task.dart';
import 'package:loringo_app/screens/teacher/task_types/repeat_after_me_task.dart';
import 'package:loringo_app/screens/teacher/widgets/create_form_banner.dart';
import 'package:loringo_app/screens/teacher/widgets/task_type_option.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_screen_header.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/screens/teacher/task_types/task_type_editor.dart';
import 'package:loringo_app/screens/teacher/task_types/image_select_task.dart';
import 'package:loringo_app/screens/teacher/task_types/image_select_reverse_task.dart';
import 'package:loringo_app/screens/teacher/task_types/complete_chat_task.dart';
import 'package:loringo_app/screens/teacher/task_types/fill_blank_task.dart';
import 'package:loringo_app/screens/teacher/task_types/arrange_task.dart';
import 'package:loringo_app/screens/teacher/task_types/match_task.dart';
import 'package:loringo_app/screens/teacher/task_types/reading_task.dart';
import 'package:loringo_app/screens/teacher/task_types/sentence_builder_task.dart';
import 'package:loringo_app/screens/teacher/task_types/sound_match_task.dart';
import 'package:loringo_app/screens/teacher/task_types/odd_one_out_task.dart';

/// Deep-equality helper for comparing collectData() maps in the dirty
/// check. Handles nested Maps and Lists (options, pairs, turns, etc.) —
/// a plain `==` on two Maps only checks reference identity, which would
/// make every edit look "changed" even when nothing was.
bool _deepEquals(dynamic a, dynamic b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// Result handed back to the caller when this screen is opened in batch
/// mode. Mirrors exactly what would have been sent to Firestore via
/// db.createPersonalizedTask/updatePersonalizedTask, so the batch review
/// screen can persist it later without knowing anything about task-type
/// internals.
class BatchTaskResult {
  final String type;
  final String title;
  final String question;
  final int order;
  final dynamic data;

  BatchTaskResult({
    required this.type,
    required this.title,
    required this.question,
    required this.order,
    required this.data,
  });
}

class CreatePersonalizedTaskScreen extends StatefulWidget {
  final String groupId;
  final String contentId;
  final String unitId;
  final String lessonId;
  final String activityId;
  final Color groupColor;
  final String? taskId;
  final Map<String, dynamic>? existingData;

  /// When true, submitting does NOT write to Firestore. Instead it pops
  /// this screen with a [BatchTaskResult] via Navigator.pop(context, result)
  /// for the caller (TaskBatchReviewScreen) to hold in memory until the
  /// whole batch is created at once.
  final bool batchMode;

  /// Locks the task type picker to a single type and hides it, since in
  /// batch mode the type was already decided by the teacher on the
  /// generator dialog for this specific slot.
  final String? fixedType;

  const CreatePersonalizedTaskScreen({
    super.key,
    required this.groupId,
    required this.contentId,
    required this.unitId,
    required this.lessonId,
    required this.activityId,
    required this.groupColor,
    this.taskId,
    this.existingData,
    this.batchMode = false,
    this.fixedType,
  });

  @override
  State<CreatePersonalizedTaskScreen> createState() =>
      _CreatePersonalizedTaskScreenState();
}

class _CreatePersonalizedTaskScreenState
    extends State<CreatePersonalizedTaskScreen> {
  final Database db = Database();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // 'order' is a positional/technical field, not something a teacher
  // should type by hand — see create_activity_screen.dart for the same
  // pattern and rationale. There is no visible field bound to this
  // controller in either mode:
  // - Non-batch, creating: resolved to (existing tasks in this activity)
  //   + 1 by _prefillNextOrder(), same as before but now always applied
  //   (previously only filled in "if empty", which no longer applies
  //   since there's no field left for a teacher to have typed into).
  // - Non-batch, editing: preserved as-is from existingData.
  // - Batch mode: TaskBatchReviewScreen owns ordering (each slot's
  //   position in the generated/added list) and stamps the real order
  //   when it writes to Firestore; this controller just needs *a* numeric
  //   value for the collectData/submit plumbing to work, so it's kept at
  //   '1' as a placeholder that's never actually used downstream.
  late TextEditingController orderController;
  late TextEditingController questionController;
  late TextEditingController titleController;

  String selectedType = 'image_select';
  bool isLoading = false;
  bool _orderResolved = false;
  bool get _isEditing => widget.taskId != null;
  Color get _c => widget.groupColor;

  late Map<String, TaskEditorController> taskControllers;
  late TaskEditorController currentController;

  // ── Dirty-check snapshot ───────────────────────────────────────────────
  // Captured once, right after the initial editor for the existing type
  // has had a chance to load its data (see _captureOriginalSnapshotAfterBuild).
  // Skipped entirely in batch mode — a freshly generated slot has nothing
  // to diff against and should always be savable once valid.
  String? _originalTitle;
  String? _originalQuestion;
  String? _originalOrder;
  String? _originalType;
  Map<String, dynamic>? _originalCollectedData;
  bool _snapshotCaptured = false;

  @override
  void initState() {
    super.initState();
    orderController = TextEditingController(
        text: widget.existingData?['order']?.toString() ?? '');
    questionController = TextEditingController(
        text: widget.existingData?['question'] as String? ?? '');
    titleController = TextEditingController(
        text: widget.existingData?['title'] as String? ?? '');

    taskControllers = {
      'image_select': TaskEditorController(
          typeId: 'image_select', defaultDisplayName: 'Image Select'),
      'image_select_reverse': TaskEditorController(
          typeId: 'image_select_reverse',
          defaultDisplayName: 'Image Select Reverse'),
      'complete_the_chat': TaskEditorController(
          typeId: 'complete_the_chat', defaultDisplayName: 'Complete the Chat'),
      'fill_blank': TaskEditorController(
          typeId: 'fill_blank', defaultDisplayName: 'Fill in the Blank'),
      'arrange': TaskEditorController(
          typeId: 'arrange', defaultDisplayName: 'Sentence Arrange'),
      'match': TaskEditorController(typeId: 'match', defaultDisplayName: 'Match'),
      'reading': TaskEditorController(
          typeId: 'reading', defaultDisplayName: 'Reading Comprehension'),
      'sentence_builder': TaskEditorController(
          typeId: 'sentence_builder', defaultDisplayName: 'Sentence Builder'),
      'repeat_after_me': TaskEditorController(
          typeId: 'repeat_after_me', defaultDisplayName: 'Repeat after me'),
      'listen_and_speak': TaskEditorController(
          typeId: 'listen_and_speak', defaultDisplayName: 'Listen & Speak'),
      'sound_match': TaskEditorController(
          typeId: 'sound_match', defaultDisplayName: 'Sound Match'),
      'odd_one_out': TaskEditorController(
          typeId: 'odd_one_out', defaultDisplayName: 'Odd One Out'),
    };

    final existingType = widget.fixedType ?? widget.existingData?['type'] as String?;
    if (existingType != null && taskControllers.containsKey(existingType)) {
      selectedType = existingType;
    }
    currentController = taskControllers[selectedType]!;

    if (!_isEditing) {
      if (widget.batchMode) {
        // Placeholder value only — TaskBatchReviewScreen stamps the real
        // order when it writes to Firestore. No fetch needed.
        orderController.text = '1';
        _orderResolved = true;
      } else {
        _prefillNextOrder();
      }
      // Nothing to diff against in create mode — dirty-check always passes.
      _snapshotCaptured = true;
    } else {
      _orderResolved = true;
      // The child editor widget (e.g. ArrangeTask) registers itself with
      // currentController inside its own initState/build, which runs
      // after this initState. Capture the snapshot one frame later so
      // collectData() reflects the data it just loaded from
      // widget.existingData, not an empty/default editor state.
      WidgetsBinding.instance.addPostFrameCallback((_) => _captureSnapshot());
    }
  }

  void _captureSnapshot() {
    if (_snapshotCaptured || !currentController.hasEditor) return;
    _originalTitle = titleController.text.trim();
    _originalQuestion = questionController.text.trim();
    _originalOrder = orderController.text.trim();
    _originalType = selectedType;
    _originalCollectedData = currentController.collectData();
    _snapshotCaptured = true;
  }

  Future<void> _prefillNextOrder() async {
    try {
      final snap = await db.getPersonalizedTasks(
        widget.groupId,
        widget.contentId,
        widget.unitId,
        widget.lessonId,
        widget.activityId,
      );
      if (mounted) {
        setState(() {
          orderController.text = (snap.docs.length + 1).toString();
          _orderResolved = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          orderController.text = '1';
          _orderResolved = true;
        });
      }
    }
  }

  /// True when nothing has changed since the task was loaded. In create
  /// mode this is always false (there's nothing to compare against, and
  /// creating is always a "change"). Covers title, question, the selected
  /// type itself, and the type-specific collectData() payload — changing
  /// type alone counts as a change even if the new editor's collected
  /// data happens to be shaped similarly. Order is intentionally NOT part
  /// of this comparison anymore — it's no longer teacher-editable, so it
  /// can't be the source of a "change".
  bool get _hasChanges {
    if (!_isEditing) return true;
    if (!_snapshotCaptured) return true; // haven't captured yet — be safe, allow save
    if (titleController.text.trim() != (_originalTitle ?? '')) return true;
    if (questionController.text.trim() != (_originalQuestion ?? '')) return true;
    if (selectedType != _originalType) return true;
    final currentData = currentController.collectData();
    return !_deepEquals(currentData, _originalCollectedData ?? {});
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final validationError = currentController.validate();
    if (validationError != null) {
      _showSnackBar(validationError, AppColors.danger);
      return;
    }

    if (_isEditing && !widget.batchMode && !_hasChanges) {
      _showSnackBar('No changes made', AppColors.info);
      return;
    }

    setState(() => isLoading = true);

    try {
      final questionText =
          _hasQuestionField() ? questionController.text.trim() : '';

      // ── Upload any pending local assets before saving ──────────────────
      // For reading tasks in Voice mode, this uploads locally-recorded audio
      // to Cloudinary. For all other task types this is a no-op. Still
      // needed in batch mode — the asset has to exist before the batch
      // review screen later writes the task doc to Firestore.
      await currentController.prepareForSubmit();

      final collectedData = currentController.collectData();
      final orderValue = int.parse(orderController.text.trim());

      // ── Batch mode: hand the data back, never touch Firestore here ─────
      if (widget.batchMode) {
        if (mounted) {
          Navigator.pop(
            context,
            BatchTaskResult(
              type: selectedType,
              title: titleController.text.trim(),
              question: questionText,
              order: orderValue,
              data: collectedData,
            ),
          );
        }
        return;
      }

      final taskId =
          widget.taskId ?? 'task_${DateTime.now().millisecondsSinceEpoch}';

      if (_isEditing) {
        await db.updatePersonalizedTask(
          groupId: widget.groupId,
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: widget.lessonId,
          activityId: widget.activityId,
          taskId: taskId,
          type: selectedType,
          title: titleController.text.trim(),
          question: questionText,
          order: orderValue,
          data: collectedData,
        );
        _showSnackBar('Task updated successfully!', AppColors.success);
      } else {
        await db.createPersonalizedTask(
          groupId: widget.groupId,
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: widget.lessonId,
          activityId: widget.activityId,
          taskId: taskId,
          type: selectedType,
          title: titleController.text.trim(),
          question: questionText,
          order: orderValue,
          data: collectedData,
        );
        _showSnackBar('Task created successfully!', AppColors.success);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showSnackBar('Error: $e', AppColors.danger);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  bool _hasQuestionField() {
    return selectedType == 'image_select' ||
        selectedType == 'image_select_reverse' ||
        selectedType == 'complete_the_chat';
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating),
    );
  }

  @override
  void dispose() {
    orderController.dispose();
    questionController.dispose();
    titleController.dispose();
    super.dispose();
  }

  Widget _buildCurrentEditor() {
    final existingData = widget.existingData?['data'];

    switch (selectedType) {
      case 'image_select':
        return ImageSelectTask(
            groupColor: _c,
            existingData: existingData,
            controller: taskControllers['image_select']!,
            onChanged: () => setState(() {}));
      case 'image_select_reverse':
        return ImageSelectReverseTask(
            groupColor: _c,
            existingData: existingData,
            controller: taskControllers['image_select_reverse']!,
            onChanged: () => setState(() {}));
      case 'complete_the_chat':
        return CompleteChatTask(
            groupColor: _c,
            existingData: existingData,
            controller: taskControllers['complete_the_chat']!,
            onChanged: () => setState(() {}));
      case 'fill_blank':
        return FillBlankTask(
            groupColor: _c,
            existingData: existingData,
            controller: taskControllers['fill_blank']!,
            onChanged: () => setState(() {}));
      case 'arrange':
        return ArrangeTask(
            groupColor: _c,
            existingData: existingData,
            controller: taskControllers['arrange']!,
            onChanged: () => setState(() {}));
      case 'match':
        return MatchTask(
            groupColor: _c,
            existingData: existingData,
            controller: taskControllers['match']!,
            onChanged: () => setState(() {}));
      case 'reading':
        return ReadingTask(
            groupColor: _c,
            existingData: existingData,
            controller: taskControllers['reading']!,
            onChanged: () => setState(() {}));
      case 'sentence_builder':
        return SentenceBuilderTask(
            groupColor: _c,
            existingData: existingData,
            controller: taskControllers['sentence_builder']!,
            onChanged: () => setState(() {}));
      case 'repeat_after_me':
        return RepeatAfterMeTask(
            groupColor: _c,
            existingData: existingData,
            controller: taskControllers['repeat_after_me']!,
            onChanged: () => setState(() {}));
      case 'listen_and_speak':
        return ListenAndSpeakTask(
            groupColor: _c,
            existingData: existingData,
            controller: taskControllers['listen_and_speak']!,
            onChanged: () => setState(() {}));
      case 'sound_match':
        return SoundMatchTask(
            groupColor: _c,
            existingData: existingData,
            controller: taskControllers['sound_match']!,
            onChanged: () => setState(() {}));
      case 'odd_one_out':
        return OddOneOutTask(
            groupColor: _c,
            existingData: existingData,
            controller: taskControllers['odd_one_out']!,
            onChanged: () => setState(() {}));
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    // If the snapshot hasn't been captured yet on this build (e.g. the
    // child editor just registered itself for the first time), try again
    // post-frame. Harmless if already captured — _captureSnapshot() is a
    // no-op in that case.
    if (_isEditing && !_snapshotCaptured) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _captureSnapshot());
    }

    final lockType = widget.batchMode && widget.fixedType != null;

    return Scaffold(
      // NOTE: no Scaffold.appBar — replaced with TeacherScreenHeader.
      backgroundColor: AppColors.scaffoldBackground,
      body: Column(
        children: [
          TeacherScreenHeader(
            title: widget.batchMode
                ? 'Define Task'
                : (_isEditing ? 'Edit Task' : 'Create Task'),
            color: _c,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Task Type ─────────────────────────────────────────
                    // Hidden in batch mode: the type was already fixed by
                    // the teacher's selection on the generator dialog for
                    // this slot.
                    if (!lockType) ...[
                      const CreateFormLabel('Task Type'),
                      const SizedBox(height: AppSpacing.sm),
                      TaskTypePickerField(
                        selectedId: selectedType,
                        color: _c,
                        onSelected: (value) {
                          if (!taskControllers.containsKey(value)) return;
                          setState(() {
                            selectedType = value;
                            currentController = taskControllers[value]!;
                            if (!_hasQuestionField()) questionController.clear();
                          });
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    // ── Title (mandatory, every type) ────────────────────
                    // This is what identifies the task in the list screen —
                    // kept separate from 'question' because several types
                    // (sentence builder, arrange, fill blank, match, listen
                    // & speak, repeat after me) have no natural short label
                    // of their own, and reusing hint/content text there was
                    // producing duplicate or "Untitled" entries in the task
                    // list.
                    const CreateFormLabel('Task Title'),
                    const SizedBox(height: AppSpacing.xs),
                    CreateFormField(
                      controller: titleController,
                      color: _c,
                      hint: 'Enter a short name for this task…',
                      maxLines: 1,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: AppSpacing.md),

                    if (_hasQuestionField()) ...[
                      const CreateFormLabel('Question'),
                      const SizedBox(height: AppSpacing.xs),
                      CreateFormField(
                        controller: questionController,
                        color: _c,
                        hint: 'Enter the word or question...',
                        maxLines: selectedType == 'complete_the_chat' ? 1 : 3,
                        validator: (v) =>
                            _hasQuestionField() && (v?.isEmpty ?? true)
                                ? 'Required'
                                : null,
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    // 'order' has no visible field in either mode anymore
                    // — see the orderController doc comment above for how
                    // it's resolved in each case. This Offstage keeps the
                    // controller wired into the widget tree so nothing
                    // downstream needs to change.
                    Offstage(
                      child: TextFormField(controller: orderController),
                    ),

                    const Divider(height: 1, color: AppColors.divider),
                    const SizedBox(height: AppSpacing.md),

                    _buildCurrentEditor(),

                    const SizedBox(height: AppSpacing.lg),

                    CreateFormSubmitButton(
                      color: _c,
                      label: widget.batchMode
                          ? 'SAVE TASK'
                          : (_isEditing ? 'UPDATE' : 'CREATE'),
                      isLoading: isLoading || !_orderResolved,
                      onPressed: _submit,
                    ),
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