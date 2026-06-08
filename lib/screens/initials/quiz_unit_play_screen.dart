import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/initials/activity_complete_screen.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

class UnitQuizPlayScreen extends StatefulWidget {
  final String contentId;
  final String unitId;
  final String quizId;
  final String quizTitle;
  final String? studentId;
  final String studentName;
  final bool isPreview;

  const UnitQuizPlayScreen({
    super.key,
    required this.contentId,
    required this.unitId,
    required this.quizId,
    required this.quizTitle,
    this.studentId,
    this.studentName = '',
    this.isPreview = false,
  });

  @override
  State<UnitQuizPlayScreen> createState() => _UnitQuizPlayScreenState();
}

class _UnitQuizPlayScreenState extends State<UnitQuizPlayScreen> {
  final Database _db = Database();
  
  late Future<Map<String, dynamic>> _quizDataFuture;
  final Map<String, int?> _selectedAnswers = {};
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isSubmitting = false;
  String _unitTitle = '';

  // Cached data after loading
  int _totalQuestions = 0;
  List<Map<String, dynamic>> _questions = [];
  int _xpReward = 0;
  int _passingScore = 0;
  
  // NEW: Attempts tracking variables
  int _maxAttempts = 0;
  int _attemptsUsed = 0;
  int _attemptsRemaining = 0;
  bool _isLoadingAttempts = true;

  @override
  void initState() {
    super.initState();
    _quizDataFuture = _loadQuizData().then((data) {
      setState(() {
        _totalQuestions = data['totalQuestions'];
        _questions = List<Map<String, dynamic>>.from(data['questions']);
        _xpReward = data['xpReward'];
        _passingScore = data['passingScore'];
        _maxAttempts = data['maxAttempts'];
      });

      // Load attempts info if not in preview mode
      if (!widget.isPreview && widget.studentId != null) {
        _loadAttemptsInfo();
      } else {
        _isLoadingAttempts = false;
      }

      return data;
    });
  }

  Future<void> _loadAttemptsInfo() async {
    try {
      final progressDoc = await _db.studentProgress(widget.studentId!).doc(widget.quizId).get();
      
      debugPrint('_loadAttemptsInfo - _maxAttempts: $_maxAttempts');
      
      if (progressDoc.exists) {
        final data = progressDoc.data() as Map<String, dynamic>;
        _attemptsUsed = data['attempts'] as int? ?? 1;
        debugPrint('   attempts from Firestore: ${data['attempts']}');
      } else {
        _attemptsUsed = 0;
        debugPrint('   No progress document');
      }

      // Calculate remaining attempts using the current _maxAttempts
      _attemptsRemaining = _maxAttempts - _attemptsUsed;
      if (_attemptsRemaining < 0) _attemptsRemaining = 0;
      
      debugPrint('   _attemptsUsed: $_attemptsUsed');
      debugPrint('   _attemptsRemaining: $_attemptsRemaining');

      setState(() => _isLoadingAttempts = false);
    } catch (e) {
      debugPrint('Error loading attempts info: $e');
      setState(() => _isLoadingAttempts = false);
    }
  }

  Future<Map<String, dynamic>> _loadQuizData() async {
    final quizDoc = await _db.getPersonalizedUnitQuiz(widget.quizId);
    
    if (!quizDoc.exists) throw Exception('Quiz not found');
    
    final quizData = quizDoc.data() as Map<String, dynamic>;
    
    // Get max attempts from quiz data (default to 3)
    final maxAttempts = (quizData['maxAttempts'] as num?)?.toInt() ?? 0;

    _maxAttempts = maxAttempts;
    
    try {
      final unitDoc = await _db.personalizedUnits(widget.contentId).doc(widget.unitId).get();
      _unitTitle = (unitDoc.data() as Map<String, dynamic>?)?['title'] as String? ?? widget.quizTitle;
    } catch (_) {
      _unitTitle = widget.quizTitle;
    }
    
    final questionsSnapshot = await _db.getUnitQuizQuestions(widget.quizId);
    
    final questions = questionsSnapshot.docs.map((doc) {
      final d = doc.data() as Map<String, dynamic>;
      return {
        'id': doc.id,
        'question': d['question'] ?? '',
        'options': List<String>.from(d['options'] ?? []),
        'correctIndex': (d['correctIndex'] as num?)?.toInt() ?? 0,
      };
    }).toList();
    
    return {
      'title': quizData['title'] ?? widget.quizTitle,
      'passingScore': (quizData['passingScore'] as num?)?.toInt() ?? 1,
      'xpReward': (quizData['xpReward'] as num?)?.toInt() ?? 0,
      'totalQuestions': questions.length,
      'questions': questions,
      'maxAttempts': maxAttempts,
    };
  }

  void _selectAnswer(int questionIndex, int optionIndex) {
    setState(() => _selectedAnswers[questionIndex.toString()] = optionIndex);
  }

  void _nextPage() {
    if (_currentPage < _totalQuestions - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  // NEW: Check if student can retake
  Future<bool> _canRetake() async {
    if (widget.isPreview) return false;
    if (widget.studentId == null) return false;
    
    final progressDoc = await _db.studentProgress(widget.studentId!).doc(widget.quizId).get();
    if (!progressDoc.exists) return true; // first attempt
    
    final data = progressDoc.data() as Map<String, dynamic>?;
    final attemptsUsed = data?['attempts'] as int? ?? 1;
    final isCompleted = data?['isCompleted'] as bool? ?? false;
    
    // If already passed, no need to retake
    if (isCompleted) return false;
    
    return attemptsUsed < _maxAttempts;
  }

  Future<void> _submitQuiz() async {
    final totalQ = _totalQuestions;
    final passingScore = _passingScore;
    final maxXpReward = _xpReward;

    if (_selectedAnswers.length < totalQ) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please answer all $totalQ questions'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Check if student has attempts left
    final canRetake = await _canRetake();
    if (!canRetake && !widget.isPreview) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You have used all $_maxAttempts attempts for this quiz.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    int correctCount = 0;
    for (int i = 0; i < _questions.length; i++) {
      if (_selectedAnswers[i.toString()] == _questions[i]['correctIndex'] as int) {
        correctCount++;
      }
    }

    final scorePercent = (correctCount / totalQ * 100).round();
    final passed = correctCount >= passingScore;
    final stars = scorePercent >= 90 ? 3 : scorePercent >= 70 ? 2 : 1;
    
    int xpEarned = 0;
    
    // Declare these variables outside the try block so they're accessible later
    int currentAttemptCount = 0;
    int remainingAttempts = 0;

    if (!widget.isPreview && widget.studentId != null) {
      try {
        final progressDoc = await _db.studentProgress(widget.studentId!).doc(widget.quizId).get();
        
        final wasCompleted = progressDoc.exists && 
            (progressDoc.data() as Map<String, dynamic>?)?['isCompleted'] == true;
        
        // Get previous score and attempts
        int previousScore = -1;
        if (progressDoc.exists) {
          final data = progressDoc.data() as Map<String, dynamic>;
          previousScore = data['score'] as int? ?? -1;
          currentAttemptCount = data['attempts'] as int? ?? 0;
        }
        
        // Calculate XP based on performance (no penalty for retakes)
        if (!wasCompleted && passed) {
          xpEarned = (correctCount * maxXpReward / totalQ).round();
          if (xpEarned < 5 && correctCount > 0) {
            xpEarned = 5;
          }
        } else if (wasCompleted && correctCount > previousScore) {
          // Improvement bonus
          final previousPercent = (previousScore / totalQ * 100).round();
          final newPercent = (correctCount / totalQ * 100).round();
          final improvement = newPercent - previousPercent;
          xpEarned = (improvement / 5).round().clamp(3, 10);
        }
        
        await _db.saveQuizCompletion(
          studentId: widget.studentId!,
          quizId: widget.quizId,
          contentId: widget.contentId,
          unitId: widget.unitId,
          score: correctCount,
          totalQuestions: totalQ,
          stars: stars,
          xpEarned: xpEarned,
          updateBestOnly: wasCompleted,
          unitTitle: _unitTitle,
          generateReport: false,
          reportType: 'unit',
          studentName: widget.studentName,
          passed: passed,
        );

        await _saveStudentAnswers();
        
        // Update attempts remaining after save
        await _loadAttemptsInfo();
      } catch (e) {
        debugPrint('Error saving unit quiz progress: $e');
      }
    }

    setState(() => _isSubmitting = false);
    if (!mounted) return;

    // ✅ CALCULATE REMAINING ATTEMPTS HERE
    final newAttemptsUsed = currentAttemptCount + 1;
    remainingAttempts = _maxAttempts - newAttemptsUsed;
    
    debugPrint('    Submit Quiz - Attempts Calculation:');
    debugPrint('   currentAttemptCount: $currentAttemptCount');
    debugPrint('   newAttemptsUsed: $newAttemptsUsed');
    debugPrint('   _maxAttempts: $_maxAttempts');
    debugPrint('   remainingAttempts: $remainingAttempts');

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ActivityCompleteScreen(
          screenTitle: passed ? 'Quiz Passed! 🎉' : 'Quiz Complete',
          activityTitle: widget.quizTitle,
          scorePercent: scorePercent,
          correctAnswers: correctCount,
          wrongAnswers: totalQ - correctCount,
          xpEarned: xpEarned,
          isGraded: true,
          onRetake: passed ? null : _onRetakeQuiz,
          attemptsRemaining: remainingAttempts > 0 ? remainingAttempts : 0,
          maxAttempts: _maxAttempts,
        ),
      ),
    );
  }

  void _onRetakeQuiz() {
    // Reset selected answers
    _selectedAnswers.clear();
    _currentPage = 0;
    _pageController.jumpToPage(0);
    
    // Use pushReplacement to replace the completion screen with a fresh quiz screen
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => UnitQuizPlayScreen(
          contentId: widget.contentId,
          unitId: widget.unitId,
          quizId: widget.quizId,
          quizTitle: widget.quizTitle,
          studentId: widget.studentId,
          studentName: widget.studentName,
          isPreview: widget.isPreview,
        ),
      ),
    );
  }

  Future<void> _saveStudentAnswers() async {
    try {
      final answers = <Map<String, dynamic>>[];
      for (int i = 0; i < _questions.length; i++) {
        answers.add({
          'questionIndex': i,
          'selectedIndex': _selectedAnswers[i.toString()],
          'correctIndex': _questions[i]['correctIndex'],
          'isCorrect': _selectedAnswers[i.toString()] == _questions[i]['correctIndex'],
        });
      }
      
      await _db.studentProgress(widget.studentId!)
          .doc(widget.quizId)
          .set({
            'answers': answers,
            'completedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error saving student answers: $e');
    }
  }

  // NEW: Build attempts remaining indicator for header
  Widget _buildAttemptsRemaining() {
    if (widget.isPreview || _isLoadingAttempts) {
      return const SizedBox.shrink();
    }
    
    final remaining = _maxAttempts - _attemptsUsed;
    final color = remaining > 0 ? Colors.blue : Colors.red;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            remaining > 0 ? Icons.refresh_rounded : Icons.warning_amber_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            'Attempts: $remaining/$_maxAttempts',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primary;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        title: Text(widget.quizTitle, style: AppText.appBarTitle),
        backgroundColor: primary,
        foregroundColor: AppColors.onPrimary,
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
                  const Icon(Icons.error_outline, size: 64, color: AppColors.danger),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(() => _quizDataFuture = _loadQuizData()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final allAnswered = _selectedAnswers.length == _totalQuestions;

          return Column(
            children: [
              // Header bar - SIMPLIFIED (no scroll)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: Colors.white,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Question and attempts combined
                    _buildQuestionChip(),
                    
                    // XP reward
                    _buildInfoChip(
                      text: '$_xpReward XP',
                      icon: Icons.star_rounded,
                      color: Colors.amber,
                    ),
                    
                    // Passing score
                    _buildInfoChip(
                      text: 'Pass: $_passingScore/$_totalQuestions',
                      icon: Icons.check_circle_outline,
                      color: AppColors.success,
                    ),
                  ],
                ),
              ),
              Divider(height: 0, color: AppColors.divider),

              // PageView with questions
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _totalQuestions,
                  onPageChanged: (index) => setState(() => _currentPage = index),
                  itemBuilder: (context, index) {
                    final q = _questions[index];
                    final options = List<String>.from(q['options'] as List);
                    final selected = _selectedAnswers[index.toString()];
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: _QuestionCard(
                        index: index,
                        question: q['question'] as String,
                        options: options,
                        selectedOption: selected,
                        onSelected: (oi) => _selectAnswer(index, oi),
                      ),
                    );
                  },
                ),
              ),

              // Navigation buttons (keep as is)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, -2))],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (_currentPage > 0)
                      OutlinedButton.icon(
                        onPressed: _previousPage,
                        icon: const Icon(Icons.arrow_back, size: 18),
                        label: const Text('Previous'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primary,
                          side: BorderSide(color: primary.withOpacity(0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                        ),
                      )
                    else
                      const SizedBox(width: 100),

                    if (_currentPage < _totalQuestions - 1)
                      ElevatedButton.icon(
                        onPressed: _selectedAnswers[_currentPage.toString()] != null ? _nextPage : null,
                        icon: const Icon(Icons.arrow_forward, size: 18, color: Colors.white),
                        label: const Text('Next'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primary,
                          disabledBackgroundColor: Colors.grey.shade300,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                        ),
                      )
                    else
                      SizedBox(
                        width: 160,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: (allAnswered && !_isSubmitting) ? _submitQuiz : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            disabledBackgroundColor: Colors.grey.shade300,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                          ),
                          child: _isSubmitting
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Text('Submit Quiz', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildQuestionChip() {
    final primary = AppColors.primary;

    final showAttempts = !widget.isPreview && 
        !_isLoadingAttempts &&
        _maxAttempts > 1;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Text(
            '${_currentPage + 1}/$_totalQuestions',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primary),
          ),
          // Optional: Show attempts remaining (only for graded quizzes)
          if (showAttempts) ...[
            const SizedBox(width: 8),
            Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: Colors.grey,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Row(
              children: [
                Icon(
                  Icons.refresh_rounded,
                  size: 12,
                  color: _attemptsRemaining > 0 ? Colors.blue : Colors.red,
                ),
                const SizedBox(width: 2),
                Text(
                  '${_attemptsRemaining}/$_maxAttempts',
                  style: TextStyle(
                    fontSize: 11, 
                    fontWeight: FontWeight.w500, 
                    color: _attemptsRemaining > 0 ? Colors.blue : Colors.red,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}


Widget _buildInfoChip({
  required String text,
  IconData? icon,
  required Color color,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
        ],
        Text(
          text,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
        ),
      ],
    ),
  );
}

// _QuestionCard remains unchanged
class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.index,
    required this.question,
    required this.options,
    required this.selectedOption,
    required this.onSelected,
  });

  final int index;
  final String question;
  final List<String> options;
  final int? selectedOption;
  final void Function(int) onSelected;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primary;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(
          color: selectedOption != null ? primary.withOpacity(0.25) : AppColors.divider,
          width: selectedOption != null ? 1.5 : 1,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: primary.withOpacity(0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
              border: Border(bottom: BorderSide(color: primary.withOpacity(0.08))),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: selectedOption != null ? primary : AppColors.muted.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: selectedOption != null ? AppColors.onPrimary : AppColors.muted,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(question, style: AppText.body.copyWith(fontWeight: FontWeight.w600)),
                ),
                if (selectedOption != null)
                  Icon(Icons.check_circle, color: primary.withOpacity(0.6), size: 18),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: List.generate(options.length, (oi) {
                final letter = String.fromCharCode(65 + oi);
                final isSelected = selectedOption == oi;
                return GestureDetector(
                  onTap: () => onSelected(oi),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? primary.withOpacity(0.07) : AppColors.scaffoldBackground,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      border: Border.all(
                        color: isSelected ? primary : AppColors.divider,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected ? primary : Colors.white,
                            border: Border.all(color: isSelected ? primary : AppColors.divider, width: 2),
                          ),
                          child: Center(
                            child: isSelected
                                ? const Icon(Icons.check, size: 14, color: Colors.white)
                                : Text(letter, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.muted)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            options[oi],
                            style: TextStyle(
                              fontSize: 14,
                              color: isSelected ? primary : Colors.black87,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
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