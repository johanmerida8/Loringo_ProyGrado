import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/theme/app_theme.dart';

class TeacherFeedbackDialog extends StatefulWidget {
  final String studentId;
  final String reportId;
  final String currentFeedback;
  final String studentName;
  final String unitTitle;

  const TeacherFeedbackDialog({
    super.key,
    required this.studentId,
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
        .collection('students')
        .doc(widget.studentId)
        .collection('reports')
        .doc(widget.reportId)
        .update({
      'feedback': feedback,
    });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Feedback saved successfully'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving feedback: $e'),
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
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.comment_rounded, color: AppColors.primary),
          const SizedBox(width: 12),
          const Text('Teacher Feedback'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Student: ${widget.studentName}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          Text(
            'Unit: ${widget.unitTitle}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          const Text(
            'Write personalized feedback for the parent:',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _feedbackController,
            maxLines: 5,
            decoration: InputDecoration(
              hintText: 'E.g., "Great improvement! Keep practicing vocabulary."\n'
                  'Or: "Needs extra help with verb conjugations. Please review Unit 2."',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey[50],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This feedback will appear on the parent\'s PDF report.',
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
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
              : const Text('Save Feedback'),
        ),
      ],
    );
  }
}