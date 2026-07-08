// create_task_screen.dart
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/task_types/listen_and_speak_task.dart';
import 'package:loringo_app/screens/teacher/task_types/repeat_after_me_task.dart';
import 'package:loringo_app/screens/teacher/widgets/create_form_banner.dart';
import 'package:loringo_app/screens/teacher/widgets/task_type_option.dart';
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

class CreatePersonalizedTaskScreen extends StatefulWidget {
  final String groupId;
  final String contentId;
  final String unitId;
  final String lessonId;
  final String activityId;
  final Color groupColor;
  final String? taskId;
  final Map<String, dynamic>? existingData;

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
  });

  @override
  State<CreatePersonalizedTaskScreen> createState() =>
      _CreatePersonalizedTaskScreenState();
}

class _CreatePersonalizedTaskScreenState
    extends State<CreatePersonalizedTaskScreen> {
  final Database db = Database();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late TextEditingController orderController;
  late TextEditingController questionController;

  String selectedType = 'image_select';
  bool isLoading = false;
  bool get _isEditing => widget.taskId != null;
  Color get _c => widget.groupColor;

  late Map<String, TaskEditorController> taskControllers;
  late TaskEditorController currentController;

  @override
  void initState() {
    super.initState();
    orderController = TextEditingController(
        text: widget.existingData?['order']?.toString() ?? '');
    questionController = TextEditingController(
        text: widget.existingData?['question'] as String? ?? '');

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
    };

    final existingType = widget.existingData?['type'] as String?;
    if (existingType != null && taskControllers.containsKey(existingType)) {
      selectedType = existingType;
    }
    currentController = taskControllers[selectedType]!;

    if (!_isEditing) _prefillNextOrder();
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
      if (mounted && orderController.text.isEmpty) {
        orderController.text = (snap.docs.length + 1).toString();
      }
    } catch (_) {}
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final validationError = currentController.validate();
    if (validationError != null) {
      _showSnackBar(validationError, AppColors.danger);
      return;
    }

    setState(() => isLoading = true);

    try {
      final taskId =
          widget.taskId ?? 'task_${DateTime.now().millisecondsSinceEpoch}';
      final questionText =
          _hasQuestionField() ? questionController.text.trim() : '';

      // ── Upload any pending local assets before saving to Firestore ─────────
      // For reading tasks in Voice mode, this uploads locally-recorded audio
      // to Cloudinary. For all other task types this is a no-op.
      await currentController.prepareForSubmit();

      final collectedData = currentController.collectData();

      if (_isEditing) {
        await db.updatePersonalizedTask(
          groupId: widget.groupId,
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: widget.lessonId,
          activityId: widget.activityId,
          taskId: taskId,
          type: selectedType,
          question: questionText,
          order: int.parse(orderController.text.trim()),
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
          question: questionText,
          order: int.parse(orderController.text.trim()),
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
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: _c,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.onPrimary),
        title: Text(_isEditing ? 'Edit Task' : 'Create Task',
            style: AppText.appBarTitle),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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

              const CreateFormLabel('Order'),
              const SizedBox(height: AppSpacing.xs),
              CreateFormField(
                controller: orderController,
                color: _c,
                hint: '1, 2, 3…',
                keyboardType: TextInputType.number,
                validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: AppSpacing.md),

              const Divider(height: 1, color: AppColors.divider),
              const SizedBox(height: AppSpacing.md),

              _buildCurrentEditor(),

              const SizedBox(height: AppSpacing.lg),

              CreateFormSubmitButton(
                color: _c,
                label: _isEditing ? 'UPDATE' : 'CREATE',
                isLoading: isLoading,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}