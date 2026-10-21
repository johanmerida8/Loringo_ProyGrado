import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/theme/app_theme.dart';

class TeacherFeedbackDialog extends StatefulWidget {
  final String studentId;
  final String groupId;
  final String reportId;
  final String currentFeedback;
  final String studentName;
  final String unitTitle;

  const TeacherFeedbackDialog({
    super.key,
    required this.studentId,
    required this.groupId,
    required this.reportId,
    required this.currentFeedback,
    required this.studentName,
    required this.unitTitle,
  });

  @override
  State<TeacherFeedbackDialog> createState() => _TeacherFeedbackDialogState();
}

class _TeacherFeedbackDialogState extends State<TeacherFeedbackDialog> {
  late TextEditingController _feedbackController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _feedbackController = TextEditingController(text: widget.currentFeedback);
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _saveFeedback() async {
    final feedback = _feedbackController.text.trim();
    setState(() => _isSaving = true);

    try {
      await FirebaseFirestore.instance
        .collection('teacherGroups')
        .doc(widget.groupId)
        .collection('students')
        .doc(widget.studentId)
        .collection('reports')
        .doc(widget.reportId)
        .update({
      'feedback': feedback,
    });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('teacher.feedback_dialog.feedbackSaved'.tr()),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('teacher.feedback_dialog.errorSavingFeedback'
                .tr(namedArgs: {'error': '$e'})),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.comment_rounded, color: AppColors.primary),
          const SizedBox(width: 12),
          Text('teacher.feedback_dialog.title'.tr()),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'teacher.feedback_dialog.studentLabel'
                .tr(namedArgs: {'name': widget.studentName}),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          Text(
            'teacher.feedback_dialog.unitLabel'
                .tr(namedArgs: {'unit': widget.unitTitle}),
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          Text(
            'teacher.feedback_dialog.writeFeedbackPrompt'.tr(),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _feedbackController,
            maxLines: 5,
            decoration: InputDecoration(
              hintText: 'teacher.feedback_dialog.feedbackHint'.tr(),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey[50],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'teacher.feedback_dialog.feedbackDisclaimer'.tr(),
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('common.cancel'.tr()),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _saveFeedback,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text('teacher.feedback_dialog.saveFeedback'.tr()),
        ),
      ],
    );
  }
}