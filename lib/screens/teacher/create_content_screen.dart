// create_content_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/widgets/create_form_banner.dart';
// import 'package:loringo_app/screens/teacher/widgets/create_form_widgets.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

class CreatePersonalizedContentScreen extends StatefulWidget {
  final String? contentId;
  final Map<String, dynamic>? existingData;
  final Color groupColor;

  const CreatePersonalizedContentScreen({
    super.key,
    this.contentId,
    this.existingData,
    this.groupColor = AppColors.primary,
  });

  @override
  State<CreatePersonalizedContentScreen> createState() =>
      _CreatePersonalizedContentScreenState();
}

class _CreatePersonalizedContentScreenState
    extends State<CreatePersonalizedContentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _db = Database();

  late TextEditingController titleController;
  late TextEditingController descriptionController;
  late TextEditingController orderController;
  String selectedAgeGroup = '5-6 years';
  bool isLoading = false;
  bool get _isEditing => widget.contentId != null;
  Color get _c => widget.groupColor;

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(text: widget.existingData?['title'] ?? '');
    descriptionController = TextEditingController(text: widget.existingData?['description'] ?? '');
    orderController = TextEditingController(text: widget.existingData?['order']?.toString() ?? '');
    selectedAgeGroup = widget.existingData?['ageGroup'] ?? '5-6 years';
    if (!_isEditing) _prefillNextOrder();
  }

  Future<void> _prefillNextOrder() async {
    final teacherId = FirebaseAuth.instance.currentUser?.uid;
    if (teacherId == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('content')
          .where('teacherId', isEqualTo: teacherId)
          .get();
      if (mounted && orderController.text.isEmpty) {
        orderController.text = (snap.docs.length + 1).toString();
      }
    } catch (_) {
      // Non-critical — teacher can still type the order manually.
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    orderController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => isLoading = true);

    try {
      final teacherId = FirebaseAuth.instance.currentUser?.uid;
      if (teacherId == null) throw Exception('No user authenticated');

      final contentId = widget.contentId ?? 'personal_content_${DateTime.now().millisecondsSinceEpoch}';

      if (_isEditing) {
        final origTitle = widget.existingData?['title'] as String? ?? '';
        final origDesc = widget.existingData?['description'] as String? ?? '';
        final origAge = widget.existingData?['ageGroup'] as String? ?? '5-6 years';
        final origOrder = widget.existingData?['order']?.toString() ?? '';
        final noChanges =
            titleController.text.trim() == origTitle &&
            descriptionController.text.trim() == origDesc &&
            selectedAgeGroup == origAge &&
            orderController.text.trim() == origOrder;
        if (noChanges) {
          setState(() => isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No changes made'), backgroundColor: AppColors.muted),
          );
          return;
        }
        await _db.updatePersonalizedContent(
          contentId: contentId,
          title: titleController.text.trim(),
          description: descriptionController.text.trim(),
          ageGroup: selectedAgeGroup,
          order: int.parse(orderController.text.trim()),
        );
      } else {
        await _db.createPersonalizedContent(
          contentId: contentId,
          title: titleController.text.trim(),
          description: descriptionController.text.trim(),
          ageGroup: selectedAgeGroup,
          order: int.parse(orderController.text.trim()),
          teacherId: teacherId,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Content updated successfully!' : 'Content created successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger),
        );
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
        title: Text(_isEditing ? 'Edit Content' : 'Create New Content', style: AppText.appBarTitle),
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
                icon: Icons.folder_open_rounded,
                label: _isEditing ? 'Editing Content' : 'New Content',
                description: 'A top-level subject area, like "English Essentials I"',
              ),
              const SizedBox(height: AppSpacing.lg),

              const CreateFormLabel('Title'),
              const SizedBox(height: AppSpacing.sm),
              CreateFormField(
                controller: titleController,
                color: _c,
                icon: Icons.title,
                hint: 'e.g. Present Tense Verbs, Numbers 1-100',
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Title is required' : null,
              ),
              const SizedBox(height: AppSpacing.lg),

              const CreateFormLabel('Description'),
              const SizedBox(height: AppSpacing.sm),
              CreateFormField(
                controller: descriptionController,
                color: _c,
                icon: Icons.description,
                hint: 'Brief description of the content',
                maxLines: 3,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Description is required' : null,
              ),
              const SizedBox(height: AppSpacing.lg),

              const CreateFormLabel('Age Group'),
              const SizedBox(height: AppSpacing.sm),
              ...['5-6 years', '7-8 years', '9+ years'].map((age) => RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(age),
                    value: age,
                    groupValue: selectedAgeGroup,
                    activeColor: _c,
                    onChanged: (value) => setState(() => selectedAgeGroup = value!),
                  )),
              const SizedBox(height: AppSpacing.md),

              const CreateFormLabel('Display Order'),
              const SizedBox(height: AppSpacing.sm),
              CreateFormField(
                controller: orderController,
                color: _c,
                icon: Icons.sort,
                hint: '1, 2, 3…',
                helperText: 'Content appears in numeric order',
                keyboardType: TextInputType.number,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Order is required' : null,
              ),
              const SizedBox(height: AppSpacing.xl),

              CreateFormSubmitButton(
                color: _c,
                label: _isEditing ? 'UPDATE CONTENT' : 'CREATE CONTENT',
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