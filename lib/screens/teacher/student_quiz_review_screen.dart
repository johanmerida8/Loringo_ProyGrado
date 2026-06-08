import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/services/notifications/notification_service.dart';
import 'package:loringo_app/theme/app_theme.dart';

class StudentQuizReviewScreen extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String quizId;
  final String quizTitle;
  final String unitId;
  final String contentId;

  const StudentQuizReviewScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.quizId,
    required this.quizTitle,
    required this.unitId,
    required this.contentId,
  });

  @override
  State<StudentQuizReviewScreen> createState() => _StudentQuizReviewScreenState();
}

class _StudentQuizReviewScreenState extends State<StudentQuizReviewScreen> {
  List<Map<String, dynamic>> _questions = [];
  List<Map<String, dynamic>> _answers = [];
  bool _isLoading = true;
  int _score = 0;
  int _totalQuestions = 0;
  String _feedback = '';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Load quiz questions
      final questionsSnapshot = await FirebaseFirestore.instance
          .collection('quizzes')
          .doc(widget.quizId)
          .collection('questions')
          .orderBy('order')
          .get();

      _questions = questionsSnapshot.docs.map((doc) {
        final d = doc.data();
        return {
          'id': doc.id,
          'question': d['question'] ?? '',
          'options': List<String>.from(d['options'] ?? []),
          'correctIndex': d['correctIndex'] as int? ?? 0,
        };
      }).toList();
      _totalQuestions = _questions.length;

      // 2. Load student's answers from progress document
      final progressDoc = await FirebaseFirestore.instance
          .collection('students')
          .doc(widget.studentId)
          .collection('progress')
          .doc(widget.quizId)
          .get();

      if (progressDoc.exists) {
        final data = progressDoc.data() as Map<String, dynamic>;
        _score = data['score'] as int? ?? 0;
        _answers = List<Map<String, dynamic>>.from(data['answers'] ?? []);
      }

      // 3. Load existing feedback (if any)
      final reportsSnap = await FirebaseFirestore.instance
          .collection('students')
          .doc(widget.studentId)
          .collection('reports')
          .where('unitId', isEqualTo: widget.unitId)
          .limit(1)
          .get();

      if (reportsSnap.docs.isNotEmpty) {
        _feedback = reportsSnap.docs.first.data()['feedback'] as String? ?? '';
      }
    } catch (e) {
      debugPrint('Error loading quiz review: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _sendReport() async {
    if (_feedback.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add feedback before sending report')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final db = Database();

      // only save the report
      await db.saveReportOnly(
        studentId: widget.studentId, 
        unitId: widget.unitId, 
        unitTitle: widget.quizTitle, 
        score: _score, 
        totalQuestions: _totalQuestions, 
        stars: _getStars(), 
        feedback: _feedback
      );

      await NotificationService.sendReportNotification(
        studentId: widget.studentId, 
        studentName: widget.studentName, 
        unitTitle: widget.quizTitle,
      );

      final checkReport = await FirebaseFirestore.instance
          .collection('students')
          .doc(widget.studentId)
          .collection('reports')
          .doc(widget.unitId)
          .get();
      
      print('Report saved with feedback: ${checkReport.data()?['feedback']}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report sent to parent!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  int _getStars() {
    final percent = _totalQuestions == 0 ? 0 : (_score / _totalQuestions * 100).round();
    if (percent >= 90) return 3;
    if (percent >= 70) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text('Review: ${widget.quizTitle}'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Student info card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: AppColors.primary.withOpacity(0.1),
                          child: Text(widget.studentName.isNotEmpty ? widget.studentName[0].toUpperCase() : '?', style: TextStyle(fontSize: 24, color: AppColors.primary)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.studentName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              Text('Score: $_score/$_totalQuestions (${(_score / _totalQuestions * 100).round()}%)', style: TextStyle(fontSize: 14, color: _score >= (_totalQuestions * 0.7) ? Colors.green : Colors.orange)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('Questions Review', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  ..._questions.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final q = entry.value;
                    final studentAnswer = idx < _answers.length ? _answers[idx]['selectedIndex'] as int? : null;
                    final isCorrect = studentAnswer == q['correctIndex'];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isCorrect ? Colors.green.shade200 : Colors.red.shade200),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(isCorrect ? Icons.check_circle : Icons.cancel, color: isCorrect ? Colors.green : Colors.red, size: 20),
                              const SizedBox(width: 8),
                              Expanded(child: Text('Question ${idx+1}: ${q['question']}', style: const TextStyle(fontWeight: FontWeight.w600))),
                            ]),
                            const SizedBox(height: 8),
                            ...List.generate((q['options'] as List).length, (optIdx) {
                              final isStudentChoice = studentAnswer == optIdx;
                              final isCorrectChoice = q['correctIndex'] == optIdx;
                              Color? bgColor;
                              if (isCorrectChoice) bgColor = Colors.green.shade50;
                              else if (isStudentChoice && !isCorrectChoice) bgColor = Colors.red.shade50;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: bgColor,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: isCorrectChoice ? Colors.green : (isStudentChoice ? Colors.red : Colors.grey.shade200)),
                                ),
                                child: Row(children: [
                                  Text('${String.fromCharCode(65+optIdx)}.', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(q['options'][optIdx])),
                                  if (isCorrectChoice) const Icon(Icons.check_circle, color: Colors.green, size: 16),
                                  if (isStudentChoice && !isCorrectChoice) const Icon(Icons.cancel, color: Colors.red, size: 16),
                                ]),
                              );
                            }),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 24),
                  const Text('Teacher Feedback', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: TextEditingController(text: _feedback),
                    onChanged: (v) => _feedback = v,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText: 'Write feedback for the parent...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _sendReport,
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: _isSaving ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white)) : const Text('Send Report to Parent', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}