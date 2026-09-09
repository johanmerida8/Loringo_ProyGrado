// create_content_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/teacher/widgets/create_form_banner.dart';
// import 'package:loringo_app/screens/teacher/widgets/create_form_widgets.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_screen_header.dart';
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
  // 'order' is a positional/technical field, not something a teacher
  // should type by hand — see create_activity_screen.dart for the same
  // pattern and rationale. Kept as a controller only because the save
  // logic below already reads its .text; there is no visible field
  // bound to it.
  // - Creating: always set to (this teacher's existing content count) + 1
  //   once _prefillNextOrder() resolves — i.e. always appended to the end.
  // - Editing: preserved as-is from existingData; never changed here.
  late TextEditingController orderController;
  String selectedAgeGroup = '5-6 years';
  bool isLoading = false;
  bool _orderResolved = false;
  bool get _isEditing => widget.contentId != null;
  Color get _c => widget.groupColor;

  // Content is now owned by exactly one group, fixed at creation -- picked
  // here since this screen is reached from "My Content" (teacher-wide, not
  // already inside a specific group's context). Not editable afterward:
  // editing an existing content item never touches ownership.
  String? _selectedGroupId;

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(text: widget.existingData?['title'] ?? '');
    descriptionController = TextEditingController(text: widget.existingData?['description'] ?? '');
    orderController = TextEditingController(text: widget.existingData?['order']?.toString() ?? '');
    selectedAgeGroup = widget.existingData?['ageGroup'] ?? '5-6 years';
    if (_isEditing) {
      _orderResolved = true;
    } else {
      _prefillNextOrder();
    }
  }

  Future<void> _prefillNextOrder() async {
    final teacherId = FirebaseAuth.instance.currentUser?.uid;
    if (teacherId == null) {
      if (mounted) setState(() => _orderResolved = true);
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('content')
          .where('teacherId', isEqualTo: teacherId)
          .get();
      if (mounted) {
        setState(() {
          orderController.text = (snap.docs.length + 1).toString();
          _orderResolved = true;
        });
      }
    } catch (_) {
      // Non-critical for the save flow itself, but the submit button
      // stays disabled without a resolved order — fall back to 1 rather
      // than leaving the teacher stuck if this ever fails.
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
    descriptionController.dispose();
    orderController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_isEditing && _selectedGroupId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('teacher.create_content_screen.pickGroup'.tr()), backgroundColor: AppColors.danger),
      );
      return;
    }
    setState(() => isLoading = true);

    try {
      final teacherId = FirebaseAuth.instance.currentUser?.uid;
      if (teacherId == null) throw Exception('No user authenticated');

      final contentId = widget.contentId ?? 'personal_content_${DateTime.now().millisecondsSinceEpoch}';

      if (_isEditing) {
        final origTitle = widget.existingData?['title'] as String? ?? '';
        final origDesc = widget.existingData?['description'] as String? ?? '';
        final origAge = widget.existingData?['ageGroup'] as String? ?? '5-6 years';
        final noChanges =
            titleController.text.trim() == origTitle &&
            descriptionController.text.trim() == origDesc &&
            selectedAgeGroup == origAge;
        if (noChanges) {
          setState(() => isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('common.noChangesMade'.tr()), backgroundColor: AppColors.muted),
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
          groupId: _selectedGroupId!,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing
                ? 'teacher.create_content_screen.contentUpdatedSuccess'.tr()
                : 'teacher.create_content_screen.contentCreatedSuccess'.tr()),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('common.errorWithMessage'.tr(namedArgs: {'error': '$e'})), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return Scaffold(
      // NOTE: no Scaffold.appBar — replaced with TeacherScreenHeader, same
      // as the rest of the content hierarchy (list/editor screens). This
      // screen previously had its own solid-color AppBar; removed for
      // consistency.
      backgroundColor: AppColors.scaffoldBackground,
      body: Column(
        children: [
          TeacherScreenHeader(
            title: _isEditing
                ? 'teacher.create_content_screen.editContent'.tr()
                : 'teacher.create_content_screen.createNewContent'.tr(),
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
                      icon: Icons.folder_open_rounded,
                      label: _isEditing
                          ? 'teacher.create_content_screen.editingContent'.tr()
                          : 'teacher.create_content_screen.newContent'.tr(),
                      description: 'teacher.create_content_screen.bannerDescription'.tr(),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    if (!_isEditing) ...[
                      CreateFormLabel('teacher.create_content_screen.group'.tr()),
                      const SizedBox(height: AppSpacing.sm),
                      _GroupPicker(
                        color: _c,
                        selectedGroupId: _selectedGroupId,
                        onSelected: (id) => setState(() => _selectedGroupId = id),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],

                    CreateFormLabel('teacher.create_content_screen.titleLabel'.tr()),
                    const SizedBox(height: AppSpacing.sm),
                    CreateFormField(
                      controller: titleController,
                      color: _c,
                      icon: Icons.title,
                      hint: 'teacher.create_content_screen.titleHint'.tr(),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'teacher.create_content_screen.titleRequired'.tr()
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    CreateFormLabel('teacher.create_content_screen.descriptionLabel'.tr()),
                    const SizedBox(height: AppSpacing.sm),
                    CreateFormField(
                      controller: descriptionController,
                      color: _c,
                      icon: Icons.description,
                      hint: 'teacher.create_content_screen.descriptionHint'.tr(),
                      maxLines: 3,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'teacher.create_content_screen.descriptionRequired'.tr()
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    CreateFormLabel('teacher.create_content_screen.ageGroupLabel'.tr()),
                    const SizedBox(height: AppSpacing.sm),
                    ...['5-6 years', '7-8 years', '9+ years'].map((age) => RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          title: Text(age),
                          value: age,
                          groupValue: selectedAgeGroup,
                          activeColor: _c,
                          onChanged: (value) => setState(() => selectedAgeGroup = value!),
                        )),
                    const SizedBox(height: AppSpacing.lg),

                    CreateFormSubmitButton(
                      color: _c,
                      label: _isEditing
                          ? 'teacher.create_content_screen.updateContent'.tr()
                          : 'teacher.create_content_screen.createContent'.tr(),
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

// ── Group picker ─────────────────────────────────────────────────────────
// Lists the teacher's active (non-archived) groups as selectable chips --
// content needs exactly one owning group decided up front now that
// `assignedTo` (many-to-many) is gone.
class _GroupPicker extends StatelessWidget {
  const _GroupPicker({
    required this.color,
    required this.selectedGroupId,
    required this.onSelected,
  });

  final Color color;
  final String? selectedGroupId;
  final void Function(String groupId) onSelected;

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    final teacherId = FirebaseAuth.instance.currentUser?.uid;
    if (teacherId == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: Database().getTeacherGroupsStream(teacherId),
      builder: (context, snap) {
        final groups = (snap.data?.docs ?? const <QueryDocumentSnapshot>[])
            .where((d) => (d.data() as Map)['archived'] != true)
            .toList();

        if (groups.isEmpty) {
          return Text(
            'teacher.create_content_screen.createGroupFirst'.tr(),
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          );
        }

        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: groups.map((d) {
            final id = d.id;
            final name = (d.data() as Map)['name'] as String? ??
                'teacher.teacher_content_editor_screen.group'.tr();
            final isSelected = id == selectedGroupId;
            return GestureDetector(
              onTap: () => onSelected(id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: isSelected ? color : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  border: Border.all(color: isSelected ? color : Colors.grey.shade300),
                ),
                child: Text(name,
                    style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}