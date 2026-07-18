// create_activity_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/widgets/create_form_banner.dart';
// import 'package:loringo_app/screens/teacher/widgets/create_form_widgets.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_screen_header.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

class CreatePersonalizedActivityScreen extends StatefulWidget {
  final String groupId;
  final String contentId;
  final String unitId;
  final String lessonId;
  final Color groupColor;
  final String? activityId;
  final Map<String, dynamic>? existingData;

  const CreatePersonalizedActivityScreen({
    super.key,
    required this.groupId,
    required this.contentId,
    required this.unitId,
    required this.lessonId,
    required this.groupColor,
    this.activityId,
    this.existingData,
  });

  @override
  State<CreatePersonalizedActivityScreen> createState() =>
      _CreatePersonalizedActivityScreenState();
}

class _CreatePersonalizedActivityScreenState
    extends State<CreatePersonalizedActivityScreen> {
  final _formKey = GlobalKey<FormState>();
  final Database db = Database();

  late TextEditingController titleController;
  // 'order' is a positional/technical field, not something a teacher
  // should type by hand — a free-text order let the sequence get gaps or
  // duplicates (e.g. 1, 3 with nothing as 2). It's kept as a controller
  // internally only because the rest of this screen's save logic already
  // reads its .text; there is no visible field bound to it anymore.
  // - Creating: always set to existingActivities.length + 1 (append to
  //   the end of the lesson's activity list).
  // - Editing: preserved as-is from existingData — this screen never
  //   changes an existing activity's position. Reordering belongs to a
  //   future drag-and-drop affordance on the list screen, not here.
  late TextEditingController orderController;
  late TextEditingController xpBaseController;

  bool isLoading = false;
  bool _activitiesLoaded = false;
  String? requiredActivityId;
  String difficulty = 'easy';
  List<Map<String, dynamic>> existingActivities = [];

  bool get _isEditing => widget.activityId != null;
  Color get _c => widget.groupColor;

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(text: widget.existingData?['title'] ?? '');
    orderController = TextEditingController(text: widget.existingData?['order']?.toString() ?? '');
    xpBaseController = TextEditingController(text: widget.existingData?['xpBase']?.toString() ?? '10');
    requiredActivityId = widget.existingData?['requiredActivityId'];

    final initialXp = int.tryParse(xpBaseController.text) ?? 10;
    difficulty = _getDifficultyFromXP(initialXp);

    xpBaseController.addListener(() {
      final xp = int.tryParse(xpBaseController.text);
      if (xp != null) setState(() => difficulty = _getDifficultyFromXP(xp));
    });

    _loadExistingActivities();
  }

  Future<void> _loadExistingActivities() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('content')
          .doc(widget.contentId)
          .collection('units')
          .doc(widget.unitId)
          .collection('lessons')
          .doc(widget.lessonId)
          .collection('activities')
          .orderBy('order')
          .get();

      setState(() {
        existingActivities = snapshot.docs
            .where((doc) => doc.id != widget.activityId)
            .map((doc) => {
                  'id': doc.id,
                  'title': doc.data()['title'] ?? 'Untitled',
                  'order': doc.data()['order'] ?? 0,
                  'requiredActivityId': doc.data()['requiredActivityId'],
                })
            .toList();
        _activitiesLoaded = true;
      });

      if (!_isEditing) {
        orderController.text = (snapshot.docs.length + 1).toString();
      }
    } catch (e) {
      debugPrint('Error loading activities: $e');
      if (mounted) setState(() => _activitiesLoaded = true);
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    orderController.dispose();
    xpBaseController.dispose();
    super.dispose();
  }

  String _getDifficultyFromXP(int xp) {
    if (xp >= 0 && xp <= 15) return 'easy';
    if (xp >= 16 && xp <= 30) return 'medium';
    if (xp >= 31 && xp <= 50) return 'hard';
    return 'easy';
  }

  Color _getDifficultyColor(String diff) {
    switch (diff) {
      case 'medium':
        return AppColors.warning;
      case 'hard':
        return AppColors.danger;
      default:
        return AppColors.success;
    }
  }

  String _getDifficultyLabel(String diff) {
    switch (diff) {
      case 'easy':
        return '🟢 Easy (0–15 XP)';
      case 'medium':
        return '🟡 Medium (16–30 XP)';
      case 'hard':
        return '🔴 Hard (31–50 XP)';
      default:
        return 'Unknown';
    }
  }

  /// Validates the one remaining invariant that keeps the activity unlock
  /// chain coherent within a lesson, before anything is written to
  /// Firestore: only one activity per lesson may be the entry point
  /// (requiredActivityId == null / "Always Unlocked"). Two entry points
  /// would mean two activities both start immediately unlocked with no
  /// way to tell which one the teacher meant to be first.
  ///
  /// The previous 'order' duplicate check was removed along with the
  /// Display Order field itself — order is now always derived (append-
  /// on-create, preserved-on-edit), so a duplicate can no longer occur
  /// from this screen.
  ///
  /// Returns a user-facing error string naming the conflicting activity,
  /// or null if the check passes. existingActivities already excludes
  /// the activity currently being edited (see _loadExistingActivities),
  /// so a direct comparison is safe — no need to skip self-matches here.
  String? _validateChainIntegrity() {
    if (requiredActivityId == null) {
      final otherEntryPoint = existingActivities.cast<Map<String, dynamic>?>().firstWhere(
            (a) => a!['requiredActivityId'] == null,
            orElse: () => null,
          );
      if (otherEntryPoint != null) {
        return '"${otherEntryPoint['title']}" is already set to Always '
            'Unlocked. Only one activity per lesson can be the starting '
            'point — pick it as this activity\'s prerequisite instead, or '
            'change "${otherEntryPoint['title']}" first.';
      }
    }

    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final chainError = _validateChainIntegrity();
    if (chainError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(chainError), backgroundColor: AppColors.danger),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final activityId = widget.activityId ?? 'activity_${DateTime.now().millisecondsSinceEpoch}';

      if (!_isEditing) {
        await db.createPersonalizedActivity(
          groupId: widget.groupId,
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: widget.lessonId,
          activityId: activityId,
          title: titleController.text.trim(),
          order: int.parse(orderController.text.trim()),
          requiredActivityId: requiredActivityId,
          xpBase: int.parse(xpBaseController.text.trim()),
          difficulty: difficulty,
        );
      } else {
        final origTitle = widget.existingData?['title'] as String? ?? '';
        final origXp = widget.existingData?['xpBase']?.toString() ?? '10';
        final origRequired = widget.existingData?['requiredActivityId'] as String?;
        final noChanges =
            titleController.text.trim() == origTitle &&
            xpBaseController.text.trim() == origXp &&
            requiredActivityId == origRequired;
        if (noChanges) {
          setState(() => isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No changes made'), backgroundColor: AppColors.muted),
          );
          return;
        }
        await db.updatePersonalizedActivity(
          groupId: widget.groupId,
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: widget.lessonId,
          activityId: activityId,
          title: titleController.text.trim(),
          order: int.parse(orderController.text.trim()),
          requiredActivityId: requiredActivityId,
          xpBase: int.parse(xpBaseController.text.trim()),
          difficulty: difficulty,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Activity updated successfully!' : 'Activity created successfully!'),
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
    final diffColor = _getDifficultyColor(difficulty);
    final safeValue = requiredActivityId != null &&
            existingActivities.any((a) => a['id'] == requiredActivityId)
        ? requiredActivityId
        : null;

    return Scaffold(
      // NOTE: no Scaffold.appBar — replaced with TeacherScreenHeader.
      backgroundColor: AppColors.scaffoldBackground,
      body: Column(
        children: [
          TeacherScreenHeader(
            title: _isEditing ? 'Edit Activity' : 'Create Activity',
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
                      icon: Icons.movie_creation_outlined,
                      label: _isEditing ? 'Editing Activity' : 'New Activity',
                      description: 'Groups multiple tasks together',
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    const CreateFormLabel('Activity Title'),
                    const SizedBox(height: AppSpacing.sm),
                    CreateFormField(
                      controller: titleController,
                      color: _c,
                      icon: Icons.title,
                      hint: 'e.g. Listening Exercise',
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a title' : null,
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    const CreateFormLabel('Base XP Reward'),
                    const SizedBox(height: AppSpacing.sm),
                    CreateFormField(
                      controller: xpBaseController,
                      color: _c,
                      icon: Icons.stars,
                      hint: 'e.g. 25',
                      helperText: 'Points earned upon completion (0–50)',
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Please enter base XP';
                        final xp = int.tryParse(v.trim());
                        if (xp == null) return 'Please enter a valid number';
                        if (xp < 0 || xp > 50) return 'XP must be between 0 and 50';
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),

                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: diffColor.withOpacity(0.1),
                        borderRadius: AppRadii.mdAll,
                        border: Border.all(color: diffColor.withOpacity(0.3)),
                      ),
                      child: Row(children: [
                        Icon(
                          difficulty == 'easy'
                              ? Icons.trending_down
                              : difficulty == 'medium'
                                  ? Icons.trending_flat
                                  : Icons.trending_up,
                          color: diffColor,
                          size: 20,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Difficulty Level', style: AppText.caption),
                            const SizedBox(height: 2),
                            Text(_getDifficultyLabel(difficulty),
                                style: TextStyle(fontSize: 14, color: diffColor, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ]),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    const CreateFormLabel('Prerequisites'),
                    const SizedBox(height: AppSpacing.sm),
                    DropdownButtonFormField<String>(
                      value: safeValue,
                      isExpanded: true,
                      decoration: AppInput.decoration(
                        accent: _c,
                        hint: 'Select activity to unlock this one',
                        icon: Icons.lock_outline,
                        helper: 'Leave empty if this is the first activity',
                      ),
                      items: [
                        const DropdownMenuItem<String>(value: null, child: Text('None (Always Unlocked)')),
                        ...existingActivities.map((activity) => DropdownMenuItem<String>(
                              value: activity['id'],
                              child: Text('${activity['order']}. ${activity['title']}', overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (value) => setState(() => requiredActivityId = value),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    CreateFormSubmitButton(
                      color: _c,
                      label: _isEditing ? 'UPDATE ACTIVITY' : 'CREATE ACTIVITY',
                      isLoading: isLoading || !_activitiesLoaded,
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