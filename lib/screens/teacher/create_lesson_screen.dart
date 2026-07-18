// create_lesson_screen.dart
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/widgets/create_form_banner.dart';
// import 'package:loringo_app/screens/teacher/widgets/create_form_widgets.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_screen_header.dart';
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
  // 'order' is a positional/technical field, not something a teacher
  // should type by hand — see create_activity_screen.dart for the same
  // pattern and rationale. Kept as a controller only because the save
  // logic below already reads its .text; there is no visible field
  // bound to it.
  // - Creating: always set to (existing lessons in this unit) + 1 once
  //   _prefillNextOrder() resolves — always appended to the end.
  // - Editing: preserved as-is from existingData; never changed here.
  late TextEditingController orderController;
  bool isLoading = false;
  bool _orderResolved = false;
  bool get _isEditing => widget.lessonId != null;
  Color get _c => widget.groupColor;

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(text: widget.existingData?['title'] ?? '');
    orderController = TextEditingController(text: widget.existingData?['order']?.toString() ?? '');
    if (_isEditing) {
      _orderResolved = true;
    } else {
      _prefillNextOrder();
    }
  }

  Future<void> _prefillNextOrder() async {
    try {
      final snap = await db.getPersonalizedLessons(widget.groupId, widget.contentId, widget.unitId);
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
        if (titleController.text.trim() == origTitle) {
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
      // NOTE: no Scaffold.appBar — replaced with TeacherScreenHeader.
      backgroundColor: AppColors.scaffoldBackground,
      body: Column(
        children: [
          TeacherScreenHeader(
            title: _isEditing ? 'Edit Lesson' : 'Create Lesson',
            color: _c,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
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

                    CreateFormSubmitButton(
                      color: _c,
                      label: _isEditing ? 'UPDATE LESSON' : 'CREATE LESSON',
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