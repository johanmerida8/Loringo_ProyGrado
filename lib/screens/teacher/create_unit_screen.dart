// create_unit_screen.dart
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/widgets/create_form_banner.dart';
// import 'package:loringo_app/screens/teacher/widgets/create_form_widgets.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

class CreatePersonalizedUnitScreen extends StatefulWidget {
  final String groupId;
  final String contentId;
  final String? unitId;
  final Map<String, dynamic>? existingData;
  final Color groupColor;

  const CreatePersonalizedUnitScreen({
    super.key,
    required this.groupId,
    required this.contentId,
    required this.groupColor,
    this.unitId,
    this.existingData,
  });

  @override
  State<CreatePersonalizedUnitScreen> createState() => _CreatePersonalizedUnitScreenState();
}

class _CreatePersonalizedUnitScreenState extends State<CreatePersonalizedUnitScreen> {
  final _formKey = GlobalKey<FormState>();
  final Database db = Database();

  late TextEditingController titleController;
  late TextEditingController orderController;
  bool isLoading = false;
  bool get _isEditing => widget.unitId != null;
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
      final snap = await db.getPersonalizedUnits(widget.groupId, widget.contentId);
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
      final unitId = widget.unitId ?? 'unit_${DateTime.now().millisecondsSinceEpoch}';

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
        await db.updatePersonalizedUnit(
          groupId: widget.groupId,
          contentId: widget.contentId,
          unitId: unitId,
          title: titleController.text.trim(),
          order: int.parse(orderController.text.trim()),
        );
      } else {
        await db.createPersonalizedUnit(
          groupId: widget.groupId,
          contentId: widget.contentId,
          unitId: unitId,
          title: titleController.text.trim(),
          order: int.parse(orderController.text.trim()),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Unit updated successfully!' : 'Unit created successfully!'),
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
        title: Text(_isEditing ? 'Edit Unit' : 'Create Unit', style: AppText.appBarTitle),
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
                icon: Icons.layers_rounded,
                label: _isEditing ? 'Editing Unit' : 'New Unit',
                description: 'Groups several lessons under one theme',
              ),
              const SizedBox(height: AppSpacing.lg),

              const CreateFormLabel('Unit Title'),
              const SizedBox(height: AppSpacing.sm),
              CreateFormField(
                controller: titleController,
                color: _c,
                icon: Icons.title_rounded,
                hint: 'e.g. Introduction to Numbers',
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
                helperText: 'Units appear in numeric order',
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
                label: _isEditing ? 'UPDATE UNIT' : 'CREATE UNIT',
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