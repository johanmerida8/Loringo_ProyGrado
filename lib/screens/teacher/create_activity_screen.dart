// create_activity_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/teacher/create_task_screen.dart';
import 'package:loringo_app/screens/teacher/teacher_task_editor_screen.dart';
import 'package:loringo_app/screens/teacher/widgets/continue_bookmark_button.dart';
import 'package:loringo_app/screens/teacher/widgets/create_form_banner.dart';
// import 'package:loringo_app/screens/teacher/widgets/create_form_widgets.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_screen_header.dart';
import 'package:loringo_app/screens/teacher/widgets/turn_in_widget.dart';
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
  late TextEditingController orderController;
  late TextEditingController xpBaseController;

  bool isLoading = false;
  bool _activitiesLoaded = false;
  String difficulty = 'easy';

  // FEATURE: scheduled availability / due date / close date, extracted
  // into TurnInSettingsWidget (see turn_in_widget.dart) since it grew
  // into a cohesive three-date concept rather than three unrelated
  // fields. scheduledDate is still the unlock gate compared against the
  // STUDENT DEVICE's local clock in student_activities_screen.dart,
  // alongside — not instead of — the existing requiredActivityId
  // prerequisite check. dueDate/closeDate/allowLateTurnIns are
  // display/notification/lock signals, not unlock gates.
  TurnInSettings _turnIn = const TurnInSettings();

  // ── Deferred-create staging (creating path only) ───────────────────────
  // Set once the teacher finishes defining a batch of tasks in the task
  // flow (TeacherTaskEditorScreen -> TaskTypeSelectorScreen/
  // TaskGeneratorDialog -> TaskBatchReviewScreen, which bubbles the
  // defined batch back here instead of writing it). While null, the
  // submit button reads "CONTINUE" and just pushes into that flow. Once
  // set, the button reads "CREATE ACTIVITY", and tapping it is the one
  // moment the activity + all these tasks are actually written together.
  List<BatchTaskResult>? _stagedTasks;

  // Generated once (on the first "CONTINUE" tap) and reused for both the
  // trip into the task flow and the eventual real write, so the activity
  // and its tasks land under the same Firestore doc id.
  String? _draftActivityId;

  bool get _isEditing => widget.activityId != null;
  Color get _c => widget.groupColor;

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(
      text: widget.existingData?['title'] ?? '',
    );
    orderController = TextEditingController(
      text: widget.existingData?['order']?.toString() ?? '',
    );
    xpBaseController = TextEditingController(
      text: widget.existingData?['xpBase']?.toString() ?? '10',
    );

    _turnIn = TurnInSettings.fromFirestore(widget.existingData);

    final initialXp = int.tryParse(xpBaseController.text) ?? 10;
    difficulty = _getDifficultyFromXP(initialXp);

    xpBaseController.addListener(() {
      final xp = int.tryParse(xpBaseController.text);
      if (xp != null) setState(() => difficulty = _getDifficultyFromXP(xp));
    });

    _loadExistingActivities();
  }

  // Order/prerequisite are no longer teacher-editable here -- a new
  // activity is always appended to the end of the lesson (order = current
  // count + 1), and its prerequisite is derived automatically from that
  // position (see Database._relinkActivityChain). This fetch only exists
  // to know how many activities already exist, for that append-at-end
  // order number.
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
          .get();

      if (!_isEditing) {
        orderController.text = (snapshot.docs.length + 1).toString();
      }
    } catch (e) {
      debugPrint('Error loading activities: $e');
    } finally {
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
        return '🟢 ${'teacher.create_activity_screen.easyXp'.tr()}';
      case 'medium':
        return '🟡 ${'teacher.create_activity_screen.mediumXp'.tr()}';
      case 'hard':
        return '🔴 ${'teacher.create_activity_screen.hardXp'.tr()}';
      default:
        return 'common.unknown'.tr();
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Belt-and-suspenders re-check: covers the case where a picked date
    // has since slipped stale purely because the teacher sat on the
    // form for a while before submitting — same validation the widget
    // runs per-pick, re-run here against the final state.
    final turnInError = validateTurnInSettings(_turnIn);
    if (turnInError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(turnInError), backgroundColor: AppColors.danger),
      );
      return;
    }

    // The turn-in schedule used to be entirely optional. It no longer is:
    // every activity needs a due date so the tasks created inside it (via
    // task_generator_dialog/task_type_selector_screen) have something
    // meaningful to be "overdue" or "late" against. Schedule Activity and
    // Close/Until stay optional — only Due is mandatory.
    if (_turnIn.dueDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('teacher.create_activity_screen.dueDateRequired'.tr()),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    if (_isEditing) {
      await _submitEdit();
      return;
    }
    await _submitCreate();
  }

  Future<void> _submitEdit() async {
    setState(() => isLoading = true);
    try {
      final activityId = widget.activityId!;
      final origTitle = widget.existingData?['title'] as String? ?? '';
      final origXp = widget.existingData?['xpBase']?.toString() ?? '10';
      final origTurnIn = TurnInSettings.fromFirestore(widget.existingData);
      final noChanges =
          titleController.text.trim() == origTitle &&
          xpBaseController.text.trim() == origXp &&
          _turnIn == origTurnIn;
      if (noChanges) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('common.noChangesMade'.tr()),
            backgroundColor: AppColors.muted,
          ),
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
        xpBase: int.parse(xpBaseController.text.trim()),
        difficulty: difficulty,
        scheduledDate: _turnIn.scheduledDate,
        dueDate: _turnIn.dueDate,
        closeDate: _turnIn.closeDate,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('teacher.create_activity_screen.activityUpdated'.tr()),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('common.errorWithMessage'.tr(namedArgs: {'error': '$e'})),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  /// Two very different things happen here depending on _stagedTasks:
  ///  - Still null (first tap, button reads "CONTINUE"): nothing is
  ///    written to Firestore. Pushes into the task flow and waits for it
  ///    to bubble back a fully-defined batch, which just gets stored —
  ///    the teacher lands right back on this same filled-in form.
  ///  - Already set (second tap, button reads "CREATE ACTIVITY"): this IS
  ///    the write — the activity itself plus every staged task, using
  ///    whatever's currently in the form fields (the teacher may have
  ///    tweaked title/XP/turn-in dates after staging; that's fine, this
  ///    reads live values, not a stale snapshot from the first tap).
  Future<void> _submitCreate() async {
    if (_stagedTasks == null) {
      setState(() => isLoading = true);
      _draftActivityId ??= 'activity_${DateTime.now().millisecondsSinceEpoch}';

      // Plain push, not pushReplacement: this form's State (title, XP,
      // difficulty, prerequisite, turn-in dates) is never written
      // anywhere until "CREATE ACTIVITY" below runs, so it has to stay
      // alive on the stack underneath. Pressing back anywhere in the
      // task flow lands the teacher right back on this exact filled-in
      // form instead of losing everything.
      final result = await Navigator.push<List<BatchTaskResult>>(
        context,
        MaterialPageRoute(
          settings: const RouteSettings(name: kTeacherTaskEditorRoute),
          builder: (_) => TeacherTaskEditorScreen(
            groupId: widget.groupId,
            contentId: widget.contentId,
            unitId: widget.unitId,
            lessonId: widget.lessonId,
            activityId: _draftActivityId!,
            activityTitle: titleController.text.trim(),
            groupColor: _c,
            ancestorTrail: const [],
            isPendingActivity: true,
          ),
        ),
      );

      if (mounted) {
        setState(() {
          isLoading = false;
          if (result != null && result.isNotEmpty) _stagedTasks = result;
        });
      }
      return;
    }

    setState(() => isLoading = true);
    try {
      await db.createPersonalizedActivity(
        groupId: widget.groupId,
        contentId: widget.contentId,
        unitId: widget.unitId,
        lessonId: widget.lessonId,
        activityId: _draftActivityId!,
        title: titleController.text.trim(),
        order: int.parse(orderController.text.trim()),
        xpBase: int.parse(xpBaseController.text.trim()),
        difficulty: difficulty,
        scheduledDate: _turnIn.scheduledDate,
        dueDate: _turnIn.dueDate,
        closeDate: _turnIn.closeDate,
      );
      for (final r in _stagedTasks!) {
        final taskId =
            'task_${DateTime.now().millisecondsSinceEpoch}_${r.order}';
        await db.createPersonalizedTask(
          groupId: widget.groupId,
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: widget.lessonId,
          activityId: _draftActivityId!,
          taskId: taskId,
          type: r.type,
          title: r.title,
          question: r.question,
          order: r.order,
          data: r.data,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'teacher.create_activity_screen.activityAndTasksCreated'
                  .plural(_stagedTasks!.length),
            ),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('common.errorWithMessage'.tr(namedArgs: {'error': '$e'})),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    final diffColor = _getDifficultyColor(difficulty);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: Column(
        children: [
          TeacherScreenHeader(
            title: _isEditing
                ? 'teacher.create_activity_screen.editActivity'.tr()
                : 'teacher.create_activity_screen.createActivity'.tr(),
            color: _c,
            trailing: ContinueBookmarkButton(
              level: 'activity',
              contentId: widget.contentId,
              unitId: widget.unitId,
              lessonId: widget.lessonId,
              getFormData: () => {
                'title': titleController.text.trim(),
                'xpBase': int.tryParse(xpBaseController.text.trim()),
                if (_turnIn.scheduledDate != null)
                  'scheduledDate': Timestamp.fromDate(_turnIn.scheduledDate!),
                if (_turnIn.dueDate != null)
                  'dueDate': Timestamp.fromDate(_turnIn.dueDate!),
                if (_turnIn.closeDate != null)
                  'closeDate': Timestamp.fromDate(_turnIn.closeDate!),
              },
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CreateFormBanner(
                      color: _c,
                      icon: Icons.movie_creation_outlined,
                      label: _isEditing
                          ? 'teacher.create_activity_screen.editingActivity'.tr()
                          : 'teacher.create_activity_screen.newActivity'.tr(),
                      description:
                          'teacher.create_activity_screen.groupsTasksTogether'.tr(),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    CreateFormLabel('teacher.create_activity_screen.activityTitle'.tr()),
                    const SizedBox(height: AppSpacing.sm),
                    CreateFormField(
                      controller: titleController,
                      color: _c,
                      icon: Icons.title,
                      hint: 'teacher.create_activity_screen.titleHint'.tr(),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'teacher.create_activity_screen.enterTitle'.tr()
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    CreateFormLabel('teacher.create_activity_screen.baseXpReward'.tr()),
                    const SizedBox(height: AppSpacing.sm),
                    CreateFormField(
                      controller: xpBaseController,
                      color: _c,
                      icon: Icons.stars,
                      hint: 'teacher.create_activity_screen.xpHint'.tr(),
                      helperText:
                          'teacher.create_activity_screen.xpHelperText'.tr(),
                      keyboardType: TextInputType.number,
                      // Max valid value is 50 -- two digits -- so typing a
                      // third digit is blocked outright instead of only
                      // being caught by the validator after Continue/Save
                      // is tapped (previously the field happily accepted
                      // "10000" and only rejected it on submit).
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty)
                          return 'teacher.create_activity_screen.enterBaseXp'.tr();
                        final xp = int.tryParse(v.trim());
                        if (xp == null)
                          return 'teacher.create_activity_screen.enterValidNumber'.tr();
                        if (xp < 0 || xp > 50)
                          return 'teacher.create_activity_screen.xpRange'.tr();
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
                      child: Row(
                        children: [
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
                              Text(
                                'teacher.create_activity_screen.difficultyLevel'.tr(),
                                style: AppText.caption,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _getDifficultyLabel(difficulty),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: diffColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // ── Turn-in settings (availability / due / close) ──────
                    TurnInSettingsWidget(
                      initial: _turnIn,
                      accentColor: _c,
                      onChanged: (next) => setState(() => _turnIn = next),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    if (_stagedTasks != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.1),
                          borderRadius: AppRadii.mdAll,
                          border: Border.all(
                            color: AppColors.success.withOpacity(0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle_outline,
                              color: AppColors.success,
                              size: 16,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                'teacher.create_activity_screen.tasksReady'
                                    .plural(_stagedTasks!.length),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.success,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    CreateFormSubmitButton(
                      color: _c,
                      // Creating isn't the end of the road until tasks are
                      // staged — the first tap ("CONTINUE") just carries
                      // the form into the task flow without writing
                      // anything. Once that flow bubbles a defined batch
                      // back (_stagedTasks set), THIS tap is the one that
                      // actually creates the activity and its tasks
                      // together, so the label switches to say that.
                      label: _isEditing
                          ? 'teacher.create_activity_screen.updateActivityCap'.tr()
                          : (_stagedTasks != null
                                ? 'teacher.create_activity_screen.createActivityCap'.tr()
                                : 'teacher.create_activity_screen.continueCap'.tr()),
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
