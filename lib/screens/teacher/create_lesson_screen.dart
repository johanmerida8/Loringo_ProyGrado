// create_lesson_screen.dart
import 'package:flutter/material.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CreatePersonalizedLessonScreen extends StatefulWidget {
  final String  groupId;
  final String  contentId;
  final String  unitId;
  final Color   groupColor;
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

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(
        text: widget.existingData?['title'] ?? '');
    orderController = TextEditingController(
        text: widget.existingData?['order']?.toString() ?? '');
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
      final lessonId = widget.lessonId ??
          'lesson_${DateTime.now().millisecondsSinceEpoch}';

      if (_isEditing) {
        final origTitle =
            widget.existingData?['title'] as String? ?? '';
        final origOrder =
            widget.existingData?['order']?.toString() ?? '';
        if (titleController.text.trim() == origTitle &&
            orderController.text.trim() == origOrder) {
          setState(() => isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No changes made'),
            backgroundColor: Colors.grey,
          ));
          return;
        }
        await db.updatePersonalizedLesson(
          groupId:   widget.groupId,
          contentId: widget.contentId,
          unitId:    widget.unitId,
          lessonId:  lessonId,
          title:     titleController.text.trim(),
          order:     int.parse(orderController.text),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Lesson updated'),
            backgroundColor: AppColors.primary,
          ));
        }
      } else {
        await db.createPersonalizedLesson(
          groupId:   widget.groupId,
          contentId: widget.contentId,
          unitId:    widget.unitId,
          lessonId:  lessonId,
          title:     titleController.text.trim(),
          order:     int.parse(orderController.text),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Lesson created'),
            backgroundColor: AppColors.primary,
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
      setState(() => isLoading = false);
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
          _isEditing ? 'Edit Lesson' : 'Create Lesson',
          style: const TextStyle(
              color: AppColors.onPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 20),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Context banner ────────────────────────────────────────
              _ContextBanner(
                color: c,
                icon:  Icons.school_rounded,
                label: _isEditing ? 'Editing Lesson' : 'New Lesson',
                description: 'Create engaging lessons with tasks',
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Title ─────────────────────────────────────────────────
              _FormLabel('Lesson Title'),
              const SizedBox(height: AppSpacing.sm),
              _ThemedTextField(
                controller: titleController,
                color:      c,
                hint:       'e.g. Past Tense Basics',
                icon:       Icons.title_rounded,
                validator:  (v) =>
                    (v == null || v.trim().isEmpty) ? 'Title is required' : null,
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Order ─────────────────────────────────────────────────
              _FormLabel('Display Order'),
              const SizedBox(height: AppSpacing.sm),
              _ThemedTextField(
                controller:   orderController,
                color:        c,
                hint:         '1, 2, 3…',
                icon:         Icons.sort_rounded,
                keyboardType: TextInputType.number,
                helperText:   'Lessons appear in numeric order',
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Order is required';
                  if (int.tryParse(v) == null) return 'Enter a valid number';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.xl),

              // ── Submit ────────────────────────────────────────────────
              _SubmitButton(
                color:     c,
                label:     _isEditing ? 'UPDATE LESSON' : 'CREATE LESSON',
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


// ─────────────────────────────────────────────────────────────────────────────
// Shared form widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Coloured accent banner shown at the top of create / edit screens.
class _ContextBanner extends StatelessWidget {
  final Color   color;
  final IconData icon;
  final String  label;
  final String  description;

  const _ContextBanner({
    required this.color,
    required this.icon,
    required this.label,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md - 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Icon(icon, color: color, size: 26),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              description,
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Section label above a form field.
class _FormLabel extends StatelessWidget {
  final String text;
  const _FormLabel(this.text);

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(Icons.label_outline, size: 14, color: AppColors.primary),
        const SizedBox(width: 6),
        Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
            letterSpacing: 1.1,
          ),
        ),
      ]);
}

/// Consistent styled text form field.
class _ThemedTextField extends StatelessWidget {
  final TextEditingController controller;
  final Color                 color;
  final String                hint;
  final IconData              icon;
  final TextInputType         keyboardType;
  final String?               helperText;
  final FormFieldValidator<String>? validator;
  final int                   maxLines;

  const _ThemedTextField({
    required this.controller,
    required this.color,
    required this.hint,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.helperText,
    this.validator,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller:   controller,
      keyboardType: keyboardType,
      maxLines:     maxLines,
      validator:    validator,
      decoration: InputDecoration(
        hintText:   hint,
        prefixIcon: Icon(icon, color: color),
        helperText: helperText,
        filled:     true,
        fillColor:  Colors.white,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
            borderSide: BorderSide(color: AppColors.divider)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
            borderSide: BorderSide(color: color.withOpacity(0.3))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
            borderSide: BorderSide(color: color, width: 2)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
            borderSide: const BorderSide(color: AppColors.danger)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
            borderSide: const BorderSide(color: AppColors.danger, width: 2)),
      ),
    );
  }
}

/// Full-width submit button.
class _SubmitButton extends StatelessWidget {
  final Color        color;
  final String       label;
  final bool         isLoading;
  final VoidCallback onPressed;

  const _SubmitButton({
    required this.color,
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: AppColors.onPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md)),
        ),
        child: isLoading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  color: AppColors.onPrimary,
                  strokeWidth: 2,
                ))
            : Text(
                label,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5),
              ),
      ),
    );
  }
}