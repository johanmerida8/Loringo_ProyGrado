import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class UnitQuizPlayScreen extends StatefulWidget {
  final String contentId;
  final String unitId;
  final String quizId;
  final String quizTitle;
  final bool isPreview;

  const UnitQuizPlayScreen({
    super.key,
    required this.contentId,
    required this.unitId,
    required this.quizId,
    required this.quizTitle,
    this.isPreview = false,
  });

  @override
  State<UnitQuizPlayScreen> createState() => _UnitQuizPlayScreenState();
}

class _UnitQuizPlayScreenState extends State<UnitQuizPlayScreen> {
  late Future<Map<String, dynamic>> _quizDataFuture;
  final Map<String, int?> _selectedAnswers = {};
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _quizDataFuture = _loadQuizData();
  }

  Future<Map<String, dynamic>> _loadQuizData() async {
    // Load quiz header
    final quizDoc = await FirebaseFirestore.instance
        .collection('quizzes')
        .doc(widget.quizId)
        .get();

    if (!quizDoc.exists) {
      throw Exception('Quiz not found');
    }

    final quizData = quizDoc.data() as Map<String, dynamic>;
    
    // Load questions
    final questionsSnapshot = await FirebaseFirestore.instance
        .collection('quizzes')
        .doc(widget.quizId)
        .collection('questions')
        .orderBy('order')
        .get();

    final questions = questionsSnapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return {
        'id': doc.id,
        'question': data['question'] ?? '',
        'options': List<String>.from(data['options'] ?? []),
        'correctIndex': data['correctIndex'] ?? 0,
      };
    }).toList();

    return {
      'title': quizData['title'] ?? widget.quizTitle,
      'passingScore': quizData['passingScore'] ?? 1,
      'xpReward': quizData['xpReward'] ?? 0,
      'totalQuestions': questions.length,
      'questions': questions,
    };
  }

  void _selectAnswer(int questionIndex, int optionIndex) {
    setState(() {
      _selectedAnswers[questionIndex.toString()] = optionIndex;
    });
  }

  Future<void> _submitQuiz() async {
    final quizData = await _quizDataFuture;
    final questions = quizData['questions'] as List;
    final totalQuestions = questions.length;
    final passingScore = quizData['passingScore'] as int;

    // Check if all questions are answered
    if (_selectedAnswers.length < totalQuestions) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please answer all ${totalQuestions} questions'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    // Calculate score
    int correctCount = 0;
    for (int i = 0; i < questions.length; i++) {
      final selected = _selectedAnswers[i.toString()];
      final correctIndex = questions[i]['correctIndex'] as int;
      if (selected == correctIndex) {
        correctCount++;
      }
    }

    final score = (correctCount / totalQuestions * 100).round();
    final passed = correctCount >= passingScore;
    final xpEarned = passed ? (quizData['xpReward'] as int) : 0;

    // Show result dialog
    _showResultDialog(
      correctCount: correctCount,
      totalQuestions: totalQuestions,
      score: score,
      passed: passed,
      xpEarned: xpEarned,
    );

    setState(() => _isSubmitting = false);
  }

  void _showResultDialog({
    required int correctCount,
    required int totalQuestions,
    required int score,
    required bool passed,
    required int xpEarned,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              passed ? Icons.emoji_events : Icons.sentiment_dissatisfied,
              color: passed ? Colors.amber : Colors.grey,
              size: 32,
            ),
            const SizedBox(width: 12),
            Text(passed ? 'Congratulations!' : 'Keep Practicing'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'You got $correctCount out of $totalQuestions correct',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Score: $score%',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: passed ? Colors.green : Colors.red,
              ),
            ),
            if (passed) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '+$xpEarned XP Earned!',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.amber,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (!passed) ...[
              const SizedBox(height: 8),
              Text(
                'You need $correctCount/${(_quizDataFuture as dynamic)?.passingScore ?? 1} to pass',
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Return to previous screen
            },
            child: const Text('Close'),
          ),
          if (!passed)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                setState(() {
                  _selectedAnswers.clear();
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
              ),
              child: const Text('Try Again'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(widget.quizTitle),
        backgroundColor: const Color(0xFF7C3AED),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _quizDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _quizDataFuture = _loadQuizData();
                      });
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final quizData = snapshot.data!;
          final questions = quizData['questions'] as List;
          final totalQuestions = quizData['totalQuestions'] as int;

          return Column(
            children: [
              // Quiz header with progress
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C3AED).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_selectedAnswers.length}/$totalQuestions',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF7C3AED),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.star, size: 16, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(
                            '${quizData['xpReward']} XP',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Questions list
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: questions.length,
                  itemBuilder: (context, index) {
                    final question = questions[index];
                    final options = List<String>.from(question['options']);
                    final selected = _selectedAnswers[index.toString()];

                    return _QuestionCard(
                      index: index,
                      question: question['question'],
                      options: options,
                      selectedOption: selected,
                      onSelected: (optionIndex) => _selectAnswer(index, optionIndex),
                    );
                  },
                ),
              ),
              // Submit button
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitQuiz,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Submit Quiz',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// Question Card Widget
class _QuestionCard extends StatelessWidget {
  final int index;
  final String question;
  final List<String> options;
  final int? selectedOption;
  final Function(int) onSelected;

  const _QuestionCard({
    required this.index,
    required this.question,
    required this.options,
    required this.selectedOption,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withOpacity(0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: Color(0xFF7C3AED),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    question,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Options
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: List.generate(options.length, (optIndex) {
                final letter = String.fromCharCode(65 + optIndex); // A, B, C, D
                final isSelected = selectedOption == optIndex;
                
                return GestureDetector(
                  onTap: () => onSelected(optIndex),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected 
                          ? const Color(0xFF7C3AED).withOpacity(0.08)
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF7C3AED)
                            : Colors.grey.shade200,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected
                                ? const Color(0xFF7C3AED)
                                : Colors.white,
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF7C3AED)
                                  : Colors.grey.shade400,
                              width: 2,
                            ),
                          ),
                          child: Center(
                            child: isSelected
                                ? const Icon(Icons.check, size: 16, color: Colors.white)
                                : Text(
                                    letter,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            options[optIndex],
                            style: TextStyle(
                              fontSize: 14,
                              color: isSelected
                                  ? const Color(0xFF7C3AED)
                                  : Colors.black87,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}