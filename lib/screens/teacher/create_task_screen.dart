import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/task_types/repeat_after_me_task.dart';
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
  State<CreatePersonalizedTaskScreen> createState() => _CreatePersonalizedTaskScreenState();
}

class _CreatePersonalizedTaskScreenState extends State<CreatePersonalizedTaskScreen> {
  final Database db = Database();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  
  late TextEditingController orderController;
  late TextEditingController questionController;
  
  String selectedType = 'image_select';
  bool isLoading = false;
  
  // Controllers for each task type
  late Map<String, TaskEditorController> taskControllers;
  late TaskEditorController currentController;

  @override
  void initState() {
    super.initState();
    orderController = TextEditingController(text: widget.existingData?['order']?.toString() ?? '');
    questionController = TextEditingController(text: widget.existingData?['question'] as String? ?? '');
    
    // Initialize controllers for each task type with display names
    taskControllers = {
      'image_select': TaskEditorController(
        typeId: 'image_select',
        defaultDisplayName: 'Image Select',
      ),
      'image_select_reverse': TaskEditorController(
        typeId: 'image_select_reverse', 
        defaultDisplayName: 'Image Select Reverse',
      ),
      'complete_the_chat': TaskEditorController(
        typeId: 'complete_the_chat',
        defaultDisplayName: 'Complete the Chat',
      ),
      'fill_blank': TaskEditorController(
        typeId: 'fill_blank',
        defaultDisplayName: 'Fill in the Blank',
      ),
      'arrange': TaskEditorController(
        typeId: 'arrange',
        defaultDisplayName: 'Sentence Arrange',
      ),
      'match': TaskEditorController(
        typeId: 'match',
        defaultDisplayName: 'Match',
      ),
      'reading': TaskEditorController(
        typeId: 'reading',
        defaultDisplayName: 'Reading Comprehension',
      ),
      'sentence_builder': TaskEditorController(
        typeId: 'sentence_builder',
        defaultDisplayName: 'Sentence Builder',
      ),
      'repeat_after_me': TaskEditorController(
        typeId: 'repeat_after_me',
        defaultDisplayName: 'Repeat after me'
      ),
    };
    
    // Set current controller based on existing data
    final existingType = widget.existingData?['type'] as String?;
    if (existingType != null && taskControllers.containsKey(existingType)) {
      selectedType = existingType;
    }
    currentController = taskControllers[selectedType]!;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Validate current editor through controller
    final validationError = currentController.validate();
    if (validationError != null) {
      _showSnackBar(validationError, AppColors.danger);
      return;
    }
    
    setState(() => isLoading = true);
    
    try {
      final taskId = widget.taskId ?? 'task_${DateTime.now().millisecondsSinceEpoch}';
      
      // ✅ CORREGIDO: Solo usar questionController si tiene campo de pregunta
      final questionText = _hasQuestionField() 
          ? questionController.text.trim() 
          : ''; // Los tipos sin campo de pregunta no necesitan question text
      
      // Collect data through controller
      final collectedData = currentController.collectData();
      
      if (widget.taskId != null) {
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
        _showSnackBar('Task updated successfully!', AppColors.primary);
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
        _showSnackBar('Task created successfully!', AppColors.primary);
      }
      
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showSnackBar('Error: $e', AppColors.danger);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ✅ Solo usar UNA función: _hasQuestionField
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
        behavior: SnackBarBehavior.floating,
      ),
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
          groupColor: widget.groupColor,
          existingData: existingData,
          controller: taskControllers['image_select']!,
          onChanged: () => setState(() {}),
        );
      case 'image_select_reverse':
        return ImageSelectReverseTask(
          groupColor: widget.groupColor,
          existingData: existingData,
          controller: taskControllers['image_select_reverse']!,
          onChanged: () => setState(() {}),
        );
      case 'complete_the_chat':
        return CompleteChatTask(
          groupColor: widget.groupColor,
          existingData: existingData,
          controller: taskControllers['complete_the_chat']!,
          onChanged: () => setState(() {}),
        );
      case 'fill_blank':
        return FillBlankTask(
          groupColor: widget.groupColor,
          existingData: existingData,
          controller: taskControllers['fill_blank']!,
          onChanged: () => setState(() {}),
        );
      case 'arrange':
        return ArrangeTask(
          groupColor: widget.groupColor,
          existingData: existingData,
          controller: taskControllers['arrange']!,
          onChanged: () => setState(() {}),
        );
      case 'match':
        return MatchTask(
          groupColor: widget.groupColor,
          existingData: existingData,
          controller: taskControllers['match']!,
          onChanged: () => setState(() {}),
        );
      case 'reading':
        return ReadingTask(
          groupColor: widget.groupColor,
          existingData: existingData,
          controller: taskControllers['reading']!,
          onChanged: () => setState(() {}),
        );
      case 'sentence_builder':
        return SentenceBuilderTask(
          groupColor: widget.groupColor,
          existingData: existingData,
          controller: taskControllers['sentence_builder']!,
          onChanged: () => setState(() {}),
        );

      case 'repeat_after_me':
        return RepeatAfterMeTask(
          groupColor: widget.groupColor, 
          existingData: existingData,
          controller: taskControllers['repeat_after_me']!, 
          onChanged: () => setState(() {}),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.groupColor;
    
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: c,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.onPrimary),
        title: Text(
          widget.taskId != null ? 'Edit Task' : 'Create Task',
          style: const TextStyle(color: AppColors.onPrimary, fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Task Type Dropdown
              DropdownButtonFormField<String>(
                value: selectedType,
                decoration: InputDecoration(
                  labelText: 'Task Type',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    borderSide: BorderSide(color: c, width: 2),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                items: taskControllers.entries.map((entry) {
                  return DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value.displayName),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null && taskControllers.containsKey(value)) {
                    setState(() {
                      selectedType = value;
                      currentController = taskControllers[value]!;
                      
                      // ✅ Limpiar el campo de pregunta si el nuevo tipo NO lo usa
                      if (!_hasQuestionField()) {
                        questionController.clear();
                      }
                    });
                  }
                },
              ),
              const SizedBox(height: AppSpacing.md),
              
              // ✅ Question Field (solo para tipos que lo necesitan)
              if (_hasQuestionField()) ...[
                _buildLabelRow('Question'),
                const SizedBox(height: AppSpacing.xs),
                TextFormField(
                  controller: questionController,
                  decoration: _inputDecoration(c, 'Enter the word or question...'), // ✅ hint text fijo
                  maxLines: selectedType == 'complete_the_chat' ? 1 : 3,
                  validator: (v) => _hasQuestionField() && (v?.isEmpty ?? true) ? 'Required' : null,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              
              // Order Field
              _buildLabelRow('Order'),
              const SizedBox(height: AppSpacing.xs),
              TextFormField(
                controller: orderController,
                decoration: _inputDecoration(c, '1, 2, 3…'),
                keyboardType: TextInputType.number,
                validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.md),
              
              // Type-specific Editor
              _buildCurrentEditor(),
              
              const SizedBox(height: AppSpacing.lg),
              
              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c,
                    foregroundColor: AppColors.onPrimary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                  ),
                  child: isLoading
                      ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: AppColors.onPrimary, strokeWidth: 2))
                      : Text(widget.taskId != null ? 'Update' : 'Create', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabelRow(String text) {
    return Row(
      children: [
        Icon(Icons.label_outline, size: 14, color: widget.groupColor),
        const SizedBox(width: AppSpacing.xs),
        Text(
          text.toUpperCase(),
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: widget.groupColor, letterSpacing: 1.1),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(Color c, String hint) {
    return InputDecoration(
      hintText: hint,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: BorderSide(color: c.withOpacity(0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: BorderSide(color: c, width: 2),
      ),
      filled: true,
      fillColor: Colors.white,
    );
  }
}