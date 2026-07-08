// create_lesson_screen.dart
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/widgets/create_form_banner.dart';
// import 'package:loringo_app/screens/teacher/widgets/create_form_widgets.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

class CreatePersonalizedLessonScreen extends StatefulWidget {
  final String groupId;
  final String contentId;
  final String unitId;
  final Color groupColor;
  final String? lessonId;
  final Map<String, dynamic>? existingData;

  const CreatePersonalizedLessonScreen({
    super.key,
    required this.groupId,
    required this.contentId,
    required this.unitId,
    required this.groupColor,
    this.lessonId,
    this.existingData,
  });

  @override
  State<CreatePersonalizedLessonScreen> createState() =>
      _CreatePersonalizedLessonScreenState();
}

class _CreatePersonalizedLessonScreenState
    extends State<CreatePersonalizedLessonScreen> {
  final _formKey = GlobalKey<FormState>();
  final Database db = Database();

  late TextEditingController titleController;
  late TextEditingController orderController;
  bool isLoading = false;
  bool get _isEditing => widget.lessonId != null;
  Color get _c => widget.groupColor;

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(text: widget.existingData?['title'] ?? '');
    orderController = TextEditingController(text: widget.existingData?['order']?.toString() ?? '');
    if (!_isEditing) _prefillNextOrder();
  }

  Future<void> _prefillNextOrder() async {
    try {
      final snap = await db.getPersonalizedLessons(widget.groupId, widget.contentId, widget.unitId);
      if (mounted && orderController.text.isEmpty) {
        orderController.text = (snap.docs.length + 1).toString();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    titleController.dispose();
    orderController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => isLoading = true);

    try {
      final lessonId = widget.lessonId ?? 'lesson_${DateTime.now().millisecondsSinceEpoch}';

      if (_isEditing) {
        final origTitle = widget.existingData?['title'] as String? ?? '';
        final origOrder = widget.existingData?['order']?.toString() ?? '';
        if (titleController.text.trim() == origTitle && orderController.text.trim() == origOrder) {
          setState(() => isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No changes made'), backgroundColor: AppColors.muted),
          );
          return;
        }
        await db.updatePersonalizedLesson(
          groupId: widget.groupId,
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: lessonId,
          title: titleController.text.trim(),
          order: int.parse(orderController.text),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Lesson updated'),
            backgroundColor: AppColors.success,
          ));
        }
      } else {
        await db.createPersonalizedLesson(
          groupId: widget.groupId,
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: lessonId,
          title: titleController.text.trim(),
          order: int.parse(orderController.text),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Lesson created'),
            backgroundColor: AppColors.success,
          ));
        }
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.danger,
        ));
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
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
        title: Text(_isEditing ? 'Edit Lesson' : 'Create Lesson', style: AppText.appBarTitle),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CreateFormBanner(
                color: _c,
                icon: Icons.school_rounded,
                label: _isEditing ? 'Editing Lesson' : 'New Lesson',
                description: 'Create engaging lessons with tasks',
              ),
              const SizedBox(height: AppSpacing.lg),

              const CreateFormLabel('Lesson Title'),
              const SizedBox(height: AppSpacing.sm),
              CreateFormField(
                controller: titleController,
                color: _c,
                icon: Icons.title_rounded,
                hint: 'e.g. Past Tense Basics',
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Title is required' : null,
              ),
              const SizedBox(height: AppSpacing.lg),

              const CreateFormLabel('Display Order'),
              const SizedBox(height: AppSpacing.sm),
              CreateFormField(
                controller: orderController,
                color: _c,
                icon: Icons.sort_rounded,
                hint: '1, 2, 3…',
                helperText: 'Lessons appear in numeric order',
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Order is required';
                  if (int.tryParse(v) == null) return 'Enter a valid number';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.xl),

              CreateFormSubmitButton(
                color: _c,
                label: _isEditing ? 'UPDATE LESSON' : 'CREATE LESSON',
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