// turn_in_widget.dart
//
// One combined "Turn-in Schedule" control for an activity's three
// dates, modeled on Canvas/Teams' Available-From / Due / Until pattern.
// Due is the primary field — always shown, no checkbox, listed first.
// Schedule Activity and Close/Until are both optional and independently
// checkable (not mutually exclusive — a teacher can check both at once
// for a "opens later, has a hard cutoff" hybrid schedule):
//  - Due — the target deadline. Work is still accepted after it, but
//    is tagged overdue/late (student overdue badge, teacher/parent
//    notifications). Never blocks submission by itself. Always
//    editable; every other date validates against it.
//  - Schedule Activity (scheduledDate) — when the activity unlocks.
//    Before this, the task is hidden/locked. Checking it opens the
//    picker immediately; a Due date must already exist and be after
//    it, since scheduling only makes sense relative to a deadline.
//  - Closed / Until (closeDate) — the final cutoff. Once it passes the
//    activity locks and can no longer be submitted, for every student.
//    Its relationship to Due is what determines "late turn-ins":
//      * unchecked        -> no cutoff, always open (today's default —
//                             every activity created before this field
//                             existed behaves exactly as before).
//      * after Due        -> grace window: late submissions accepted
//                             (tagged overdue) until Close, then locked.
//      * equal to Due      -> no late submissions at all.
//    No separate "allow late turn-ins" toggle exists — the grace
//    window (or lack of one) is just the gap between Due and Close.
//
// All three used to be three separate full-width pickers stacked in
// create_activity_screen.dart's form. Combined here into one tappable
// summary field that opens a bottom sheet with all three — one button,
// not three — since they're one cohesive "when is this open" concept.
// All time pickers/labels in this widget are forced to 24-hour time
// (15:30, never 3:30 PM) regardless of device locale, so the three
// dates read unambiguously side by side.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/teacher/widgets/create_form_banner.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:provider/provider.dart';

/// Immutable snapshot of everything this widget manages. Passed in as
/// the starting point and handed back via [TurnInSettingsWidget.onChanged]
/// on every edit — the parent screen owns persistence, this widget only
/// owns picking + cross-field validation.
class TurnInSettings {
  final DateTime? scheduledDate;
  final DateTime? dueDate;
  final DateTime? closeDate;

  const TurnInSettings({this.scheduledDate, this.dueDate, this.closeDate});

  factory TurnInSettings.fromFirestore(Map<String, dynamic>? data) {
    DateTime? asDate(dynamic v) => v is Timestamp ? v.toDate() : null;
    return TurnInSettings(
      scheduledDate: asDate(data?['scheduledDate']),
      dueDate: asDate(data?['dueDate']),
      closeDate: asDate(data?['closeDate']),
    );
  }

  bool get hasAnyDate => scheduledDate != null || dueDate != null || closeDate != null;

  /// Whether Close creates a grace window after Due (late submissions
  /// accepted but tagged overdue in the meantime) vs. cutting off
  /// exactly at Due (no late submissions at all).
  bool get allowsLateWindow =>
      closeDate != null && dueDate != null && closeDate!.isAfter(dueDate!);

  TurnInSettings copyWith({
    DateTime? scheduledDate,
    bool clearScheduledDate = false,
    DateTime? dueDate,
    bool clearDueDate = false,
    DateTime? closeDate,
    bool clearCloseDate = false,
  }) {
    return TurnInSettings(
      scheduledDate: clearScheduledDate ? null : (scheduledDate ?? this.scheduledDate),
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      closeDate: clearCloseDate ? null : (closeDate ?? this.closeDate),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TurnInSettings &&
      other.scheduledDate == scheduledDate &&
      other.dueDate == dueDate &&
      other.closeDate == closeDate;

  @override
  int get hashCode => Object.hash(scheduledDate, dueDate, closeDate);
}

/// Cross-field validation shared between the widget's own pickers (so a
/// bad pick is rejected immediately) and the parent screen's submit-time
/// belt-and-suspenders re-check (dates can go stale while a teacher sits
/// on the form). Returns a user-facing error message, or null if valid.
String? validateTurnInSettings(TurnInSettings s) {
  final now = DateTime.now();

  if (s.scheduledDate != null && s.scheduledDate!.isBefore(now)) {
    return 'teacher.turn_in_widget.scheduledTimePassed'.tr();
  }
  if (s.scheduledDate != null && s.dueDate == null) {
    return 'teacher.turn_in_widget.needsDueDateForSchedule'.tr();
  }
  if (s.scheduledDate != null && s.dueDate != null && !s.dueDate!.isAfter(s.scheduledDate!)) {
    return 'teacher.turn_in_widget.dueMustBeAfterScheduled'.tr();
  }
  if (s.closeDate != null && s.dueDate == null) {
    return 'teacher.turn_in_widget.needsDueDateForClose'.tr();
  }
  if (s.closeDate != null && s.dueDate != null && s.closeDate!.isBefore(s.dueDate!)) {
    return 'teacher.turn_in_widget.closeMustBeAfterDue'.tr();
  }
  return null;
}

/// One tappable "Turn-in Schedule" field that opens a bottom sheet
/// holding all three date pickers. Owns picking + immediate per-pick
/// validation; reports every change upward via [onChanged] rather than
/// writing to Firestore itself — the parent screen stays the single
/// place that calls Database.createPersonalizedActivity/
/// updatePersonalizedActivity.
class TurnInSettingsWidget extends StatefulWidget {
  final TurnInSettings initial;
  final Color accentColor;
  final ValueChanged<TurnInSettings> onChanged;

  const TurnInSettingsWidget({
    super.key,
    required this.initial,
    required this.accentColor,
    required this.onChanged,
  });

  @override
  State<TurnInSettingsWidget> createState() => TurnInSettingsWidgetState();
}

class TurnInSettingsWidgetState extends State<TurnInSettingsWidget> {
  late TurnInSettings _settings;

  /// Whether the Schedule Activity / Close-Until sections are checked
  /// open in the sheet. Deliberately separate from whether their date is
  /// actually set: checking the box just reveals the date field to tap —
  /// it no longer jumps straight into the date picker — so a section can
  /// be "checked but no date chosen yet" while the teacher is mid-edit.
  bool _scheduleEnabled = false;
  bool _closeEnabled = false;

  /// Inline validation message shown as a tag inside the bottom sheet.
  /// A SnackBar anchored to the page behind a modal bottom sheet doesn't
  /// reliably surface, so cross-field errors from the pickers render here
  /// instead.
  String? _sheetError;

  Color get _c => widget.accentColor;

  @override
  void initState() {
    super.initState();
    _settings = widget.initial;
    _scheduleEnabled = _settings.scheduledDate != null;
    _closeEnabled = _settings.closeDate != null;
  }

  void _update(TurnInSettings next) {
    setState(() => _settings = next);
    widget.onChanged(next);
  }

  Future<DateTime?> _pickDateTime(DateTime? current, DateTime? initialFallback) async {
    final now = DateTime.now();

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: current ?? initialFallback ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, now.month, now.day),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(primary: _c),
        ),
        child: child!,
      ),
    );
    if (pickedDate == null) return null;

    if (!mounted) return null;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: current != null ? TimeOfDay.fromDateTime(current) : TimeOfDay.fromDateTime(now),
      // Loringo always shows 24-hour time in this widget (15:30, not 3:30 PM)
      // regardless of the device locale/settings, so schedule/due/close read
      // unambiguously next to each other.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(primary: _c),
          ),
          child: child!,
        ),
      ),
    );
    if (pickedTime == null) return null;

    return DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
  }

  void _setSheetError(String? message, VoidCallback refreshSheet) {
    _sheetError = message;
    refreshSheet();
  }

  Future<void> _pickScheduledDate(VoidCallback refreshSheet) async {
    final combined = await _pickDateTime(_settings.scheduledDate, null);
    if (combined == null) return;
    final next = _settings.copyWith(scheduledDate: combined);
    final error = validateTurnInSettings(next);
    if (error != null) {
      // Defensive backstop: the checkbox is normally gated off while Due
      // is unset (see enabled: _settings.dueDate != null above), but if
      // Due gets cleared out from under an already-checked Schedule
      // section this pick can still fail here — un-check it so it never
      // shows "checked" next to a date that's actually still null.
      if (_settings.scheduledDate == null) _scheduleEnabled = false;
      return _setSheetError(error, refreshSheet);
    }
    _update(next);
    _setSheetError(null, refreshSheet);
  }

  Future<void> _pickDueDate(VoidCallback refreshSheet) async {
    final combined = await _pickDateTime(_settings.dueDate, _settings.scheduledDate);
    if (combined == null) return;
    final next = _settings.copyWith(dueDate: combined);
    final error = validateTurnInSettings(next);
    if (error != null) return _setSheetError(error, refreshSheet);
    _update(next);
    _setSheetError(null, refreshSheet);
  }

  Future<void> _pickCloseDate(VoidCallback refreshSheet) async {
    final combined = await _pickDateTime(_settings.closeDate, _settings.dueDate ?? _settings.scheduledDate);
    if (combined == null) return;
    final next = _settings.copyWith(closeDate: combined);
    final error = validateTurnInSettings(next);
    if (error != null) {
      // Same defensive backstop as _pickScheduledDate above.
      if (_settings.closeDate == null) _closeEnabled = false;
      return _setSheetError(error, refreshSheet);
    }
    _update(next);
    _setSheetError(null, refreshSheet);
  }

  /// "Jul 22, 2026 at 15:30" — always 24-hour time, independent of device
  /// locale, so 15:30 never round-trips through this widget as "3:30 PM".
  String _formatDate(DateTime d) {
    final months = [
      'teacher.turn_in_widget.monthJan'.tr(),
      'teacher.turn_in_widget.monthFeb'.tr(),
      'teacher.turn_in_widget.monthMar'.tr(),
      'teacher.turn_in_widget.monthApr'.tr(),
      'teacher.turn_in_widget.monthMay'.tr(),
      'teacher.turn_in_widget.monthJun'.tr(),
      'teacher.turn_in_widget.monthJul'.tr(),
      'teacher.turn_in_widget.monthAug'.tr(),
      'teacher.turn_in_widget.monthSep'.tr(),
      'teacher.turn_in_widget.monthOct'.tr(),
      'teacher.turn_in_widget.monthNov'.tr(),
      'teacher.turn_in_widget.monthDec'.tr(),
    ];
    final datePart = '${months[d.month - 1]} ${d.day}, ${d.year}';
    final hour = d.hour.toString().padLeft(2, '0');
    final minute = d.minute.toString().padLeft(2, '0');
    return '$datePart at $hour:$minute';
  }

  Widget _dateField({
    required IconData icon,
    required Color accent,
    required bool isSet,
    required String label,
    required VoidCallback onTap,
    required VoidCallback onClear,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.mdAll,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppRadii.mdAll,
          border: Border.all(color: isSet ? accent.withOpacity(0.4) : AppColors.divider),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSet ? accent : Colors.grey, size: 20),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSet ? FontWeight.w600 : FontWeight.normal,
                  color: isSet ? Colors.black87 : Colors.grey[600],
                ),
              ),
            ),
            if (isSet)
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                color: Colors.grey,
                onPressed: onClear,
                tooltip: 'teacher.turn_in_widget.clearDate'.tr(),
              ),
          ],
        ),
      ),
    );
  }

  /// Checkbox + label pair for the two optional turn-in dates (Schedule
  /// Activity, Close/Until). Checking it just reveals the date field —
  /// picking the actual date/time still has to succeed validation (e.g.
  /// Schedule needs a Due date to exist first) before the checkbox's
  /// "checked" state means anything real. Both checkboxes are always
  /// checkable regardless of Due's state; a pick attempted before Due
  /// exists surfaces the validation error inline instead of saving.
  Widget _toggleSectionHeader({
    required String title,
    required Color accent,
    required bool checked,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!checked),
      borderRadius: AppRadii.mdAll,
      child: Row(
        children: [
          Checkbox(
            value: checked,
            activeColor: accent,
            onChanged: (v) => onChanged(v ?? false),
          ),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String get _summaryLabel {
    if (!_settings.hasAnyDate) return 'teacher.turn_in_widget.setTurnInSchedule'.tr();
    final parts = <String>[];
    if (_settings.scheduledDate != null) {
      parts.add('teacher.turn_in_widget.opensDate'.tr(namedArgs: {'date': _formatDate(_settings.scheduledDate!)}));
    }
    if (_settings.dueDate != null) {
      parts.add('teacher.turn_in_widget.dueDateSummary'.tr(namedArgs: {'date': _formatDate(_settings.dueDate!)}));
    }
    if (_settings.closeDate != null) {
      parts.add('teacher.turn_in_widget.closesDate'.tr(namedArgs: {'date': _formatDate(_settings.closeDate!)}));
    }
    return parts.join(' · ');
  }

  Future<void> _openSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            sheetContext.watch<LocaleProvider>();
            void refresh() => setSheetState(() {});

            return Container(
              padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg + 6)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.divider,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('teacher.turn_in_widget.turnInSchedule'.tr(), style: AppText.h1),
                        IconButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close_rounded),
                          color: AppColors.muted,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    if (_sheetError != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withOpacity(0.08),
                          borderRadius: AppRadii.mdAll,
                          border: Border.all(color: AppColors.danger.withOpacity(0.4)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 16),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                _sheetError!,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.danger),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    // Due is the primary field — always on, no toggle, and
                    // shown first per how this widget's turn-in rules work:
                    // Schedule Activity and Close/Until both validate
                    // against it, so it has to exist before either can. It's
                    // also mandatory: create_activity_screen.dart blocks
                    // submission without it, since the activity's tasks
                    // need a due date to ever be "overdue" or "late"
                    // against.
                    Row(
                      children: [
                        CreateFormLabel('teacher.turn_in_widget.due'.tr()),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          'common.required'.tr().toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppColors.danger,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _dateField(
                      icon: Icons.event_busy_outlined,
                      accent: AppColors.warning,
                      isSet: _settings.dueDate != null,
                      label: _settings.dueDate != null ? _formatDate(_settings.dueDate!) : 'teacher.turn_in_widget.noDueDate'.tr(),
                      onTap: () => _pickDueDate(refresh),
                      onClear: () {
                        _update(_settings.copyWith(clearDueDate: true));
                        refresh();
                      },
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'teacher.turn_in_widget.dueDateHelperText'.tr(),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // Optional — the checkbox only reveals the date field;
                    // it doesn't jump into a picker by itself. Once checked,
                    // tap the field below to schedule the activity to
                    // unlock in the future. Always checkable regardless of
                    // whether Due is set yet — the teacher may want to check
                    // it first and fill in dates in whatever order suits
                    // them. Actually picking a date still validates against
                    // Due (see validateTurnInSettings), surfacing the error
                    // inline in the sheet if Due isn't set yet.
                    _toggleSectionHeader(
                      title: 'teacher.turn_in_widget.scheduleActivity'.tr(),
                      accent: _c,
                      checked: _scheduleEnabled,
                      onChanged: (checked) {
                        _scheduleEnabled = checked;
                        if (!checked) {
                          _update(_settings.copyWith(clearScheduledDate: true));
                        }
                        _sheetError = null;
                        refresh();
                      },
                    ),
                    if (_scheduleEnabled) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _dateField(
                        icon: Icons.event_available_outlined,
                        accent: _c,
                        isSet: _settings.scheduledDate != null,
                        label: _settings.scheduledDate != null
                            ? _formatDate(_settings.scheduledDate!)
                            : 'teacher.turn_in_widget.tapToChooseScheduleDate'.tr(),
                        onTap: () => _pickScheduledDate(refresh),
                        onClear: () {
                          _scheduleEnabled = false;
                          _update(_settings.copyWith(clearScheduledDate: true));
                          refresh();
                        },
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'teacher.turn_in_widget.scheduleHelperText'.tr(),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ] else ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'teacher.turn_in_widget.scheduleUncheckedText'.tr(),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),

                    // Optional — same pattern: check to reveal the field,
                    // tap the field to pick. At Due, no late submissions;
                    // after Due, a late grace window. Always checkable
                    // regardless of whether Due is set yet, same as Schedule
                    // Activity above — the pick itself still validates
                    // against Due.
                    _toggleSectionHeader(
                      title: 'teacher.turn_in_widget.closeUntil'.tr(),
                      accent: AppColors.danger,
                      checked: _closeEnabled,
                      onChanged: (checked) {
                        _closeEnabled = checked;
                        if (!checked) {
                          _update(_settings.copyWith(clearCloseDate: true));
                        }
                        _sheetError = null;
                        refresh();
                      },
                    ),
                    if (_closeEnabled) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _dateField(
                        icon: Icons.lock_clock_outlined,
                        accent: AppColors.danger,
                        isSet: _settings.closeDate != null,
                        label: _settings.closeDate != null
                            ? _formatDate(_settings.closeDate!)
                            : 'teacher.turn_in_widget.tapToChooseCloseDate'.tr(),
                        onTap: () => _pickCloseDate(refresh),
                        onClear: () {
                          _closeEnabled = false;
                          _update(_settings.copyWith(clearCloseDate: true));
                          refresh();
                        },
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _settings.closeDate == null
                            ? 'teacher.turn_in_widget.closeHelperTextUnset'.tr()
                            : (_settings.allowsLateWindow
                                ? 'teacher.turn_in_widget.closeHelperTextGrace'.tr()
                                : 'teacher.turn_in_widget.closeHelperTextNoLate'.tr()),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ] else ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'teacher.turn_in_widget.closeUncheckedText'.tr(),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _c,
                          foregroundColor: AppColors.onPrimary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                          elevation: 0,
                        ),
                        child: Text('teacher.turn_in_widget.done'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CreateFormLabel('teacher.turn_in_widget.turnInSchedule'.tr()),
        const SizedBox(height: AppSpacing.sm),
        InkWell(
          onTap: _openSheet,
          borderRadius: AppRadii.mdAll,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: AppRadii.mdAll,
              border: Border.all(
                color: _settings.hasAnyDate ? _c.withOpacity(0.4) : AppColors.divider,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.event_note_outlined, color: _settings.hasAnyDate ? _c : Colors.grey, size: 20),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    _summaryLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: _settings.hasAnyDate ? FontWeight.w600 : FontWeight.normal,
                      color: _settings.hasAnyDate ? Colors.black87 : Colors.grey[600],
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _settings.dueDate == null
              ? 'teacher.turn_in_widget.summaryHelperRequired'.tr()
              : 'teacher.turn_in_widget.summaryHelperSet'.tr(),
          style: TextStyle(
            fontSize: 12,
            color: _settings.dueDate == null ? AppColors.danger : Colors.grey.shade600,
            fontWeight: _settings.dueDate == null ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
