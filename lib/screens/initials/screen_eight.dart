import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/initials/widget/responsive_activity_shell.dart';
import 'package:loringo_app/screens/initials/widget/retryable_task.dart';
import 'package:loringo_app/screens/initials/widget/task_exit_guard.dart';
import 'package:loringo_app/screens/initials/widget/task_result_sheet.dart';
import 'package:loringo_app/services/audio/task_feedback.dart';
import 'package:loringo_app/screens/initials/widget/exit_task_dialog.dart';
import 'package:loringo_app/screens/initials/widget/task_callbacks.dart';
import 'package:loringo_app/services/tts/task_tts_service.dart';
import 'package:loringo_app/services/tts/tts_voices.dart';

class ScreenEight extends StatefulWidget {
  final String contentId;
  final String unitId;
  final String lessonId;
  final String activityId;
  final String taskId;
  // ── TEACHER REVIEW FEATURE ──────────────────────────────────────────
  // See widget/task_callbacks.dart for why this uses a shared typedef.
  // answerDetail shape: {'type': 'sentence_builder', 'prompt': <ES or EN
  // prompt sentence>, 'direction': 'es_to_en'|'en_to_es',
  // 'studentSentence': <words the student assembled, joined>,
  // 'correctSentence': <the expected answer, joined>}.
  final TaskCompleteCallback onTaskComplete;
  final int currentTaskNumber;
  final int totalTasks;
  final String collectionName;
  final bool isPracticeRound;

  const ScreenEight({
    super.key,
    required this.contentId,
    required this.unitId,
    required this.lessonId,
    required this.activityId,
    required this.taskId,
    required this.onTaskComplete,
    required this.currentTaskNumber,
    required this.totalTasks,
    this.collectionName = 'content',
    this.isPracticeRound = false,
  });

  @override
  State<ScreenEight> createState() => _ScreenEightState();
}

class _ScreenEightState extends State<ScreenEight> with RetryableTask {
  static const Color _green = Color(0xFF4CAF50);
  static const Color _greyBg = Color(0xFFF5F5F5);

  String _promptSentence = '';
  String _direction = 'es_to_en';
  List<String> _correctAnswer = [];
  List<String> _wordBank = [];

  List<String> _selectedWords = [];

  bool _isLoading = true;
  bool _isResultSheetOpen = false;

  static const List<String> _incorrectHints = [
    'Almost there! Check the word order.',
    'Good try! Keep going.',
    'You can do it! Think about the full sentence.',
    'Try again! You\'re very close.',
    'Don\'t give up! Give it another try.',
  ];

  int _hintCycleCount = 0;

  bool get _isEsToEn => _direction == 'es_to_en';
  String get _headerLabel => _isEsToEn ? 'Translate to English' : 'Translate to Spanish';
  String get _listenTooltip => _isEsToEn ? 'Listen to Spanish' : 'Listen to English';

  @override
  void initState() {
    super.initState();
    _fetchTask();
  }

  Future<void> _handleClose() async {
    final shouldExit = await confirmExitTask(context);
    if (shouldExit && context.mounted) Navigator.pop(context);
  }

  Future<void> _fetchTask() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(widget.collectionName)
          .doc(widget.contentId)
          .collection('units')
          .doc(widget.unitId)
          .collection('lessons')
          .doc(widget.lessonId)
          .collection('activities')
          .doc(widget.activityId)
          .collection('tasks')
          .doc(widget.taskId)
          .get();

      if (doc.exists) {
        final taskData = doc.data() as Map<String, dynamic>;
        final data = taskData['data'] as Map<String, dynamic>? ?? {};

        setState(() {
          _direction = data['direction'] ?? 'es_to_en';
          _promptSentence = data['sentence'] ?? data['spanishSentence'] ?? '';
          _correctAnswer = List<String>.from(data['correctAnswer'] ?? []);
          _wordBank = List<String>.from(data['wordBank'] ?? []);
          _wordBank.shuffle();
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error fetching sentence builder task: $e');
      setState(() => _isLoading = false);
    }
  }

  void _speakPrompt() async {
    // Spanish prompts use Ximena, English prompts use Maisie -- picked
    // fresh on every call since _direction (and therefore the prompt's
    // language) can differ from one task to the next.
    await TaskTtsService.speak(_promptSentence, voice: _isEsToEn ? TtsVoice.ximena : TtsVoiceDefaults.defaultEnglish);
  }

  void _addWord(String word) {
    setState(() {
      _selectedWords.add(word);
      _wordBank.remove(word);
    });
  }

  void _removeWord(int index) {
    setState(() {
      final word = _selectedWords[index];
      _selectedWords.removeAt(index);
      _wordBank.add(word);
    });
  }

  void _clearAll() {
    setState(() {
      _wordBank.addAll(_selectedWords);
      _selectedWords.clear();
      _wordBank.shuffle();
    });
  }

  void _checkAnswer() {
    if (_isResultSheetOpen) return;

    final isCorrect = _selectedWords.join(' ') == _correctAnswer.join(' ');

    TaskFeedback.fire(isCorrect);

    if (!isCorrect) {
      _isResultSheetOpen = true;
      final softRetry = offerRetry(
        context: context,
        onRetry: () {
          _isResultSheetOpen = false;
          _clearAll();
        },
      );
      if (softRetry) return;
      _hintCycleCount++;
    }

    _isResultSheetOpen = true;
    TaskResultSheet.show(
      context,
      isCorrect: isCorrect,
      isPracticeRound: widget.isPracticeRound,
      extraContent: isCorrect ? null : TaskResultHintBox(hint: _currentHint),
      onContinue: () {
        _isResultSheetOpen = false;
        widget.onTaskComplete(isCorrect, {
          'type': 'sentence_builder',
          'prompt': _promptSentence,
          'direction': _direction,
          'studentSentence': _selectedWords.join(' '),
          'correctSentence': _correctAnswer.join(' '),
        });
      },
    ).then((_) => _isResultSheetOpen = false);
  }

  String get _currentHint {
    return _incorrectHints[(_hintCycleCount - 1) % _incorrectHints.length];
  }

  @override
  void dispose() {
    TaskTtsService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final progressValue = (widget.currentTaskNumber + 1) / widget.totalTasks;

    return TaskExitGuard(
      onRequestExit: _handleClose,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFE8F5E9), Colors.white],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: ResponsiveActivityShell(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.black87,
                            size: 28,
                          ),
                          onPressed: _handleClose,
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.all(
                              Radius.circular(30),
                            ),
                            child: LinearProgressIndicator(
                              value: progressValue,
                              backgroundColor: Colors.blueGrey,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                _green,
                              ),
                              minHeight: 8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(Icons.translate, color: _green, size: 24),
                            const SizedBox(width: 12),
                            Text(
                              _headerLabel,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.black54,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: Icon(
                                Icons.volume_up,
                                color: _green,
                                size: 24,
                              ),
                              onPressed: _speakPrompt,
                              tooltip: _listenTooltip,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _promptSentence,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
              
                  const SizedBox(height: 16),
              
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        const Text(
                          'Your Answer',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const Spacer(),
                        if (_selectedWords.isNotEmpty)
                          TextButton.icon(
                            onPressed: _clearAll,
                            icon: const Icon(Icons.clear_all, size: 18),
                            label: const Text('Clear All'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                          ),
                      ],
                    ),
                  ),
              
                  const SizedBox(height: 8),
              
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _greyBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: _selectedWords.isEmpty
                        ? Center(
                            child: Text(
                              'Tap words below to build your sentence',
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 14,
                              ),
                            ),
                          )
                        : Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: _selectedWords.asMap().entries.map((entry) {
                              final index = entry.key;
                              final word = entry.value;
                              return GestureDetector(
                                onTap: () => _removeWord(index),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _green,
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _green.withOpacity(0.3),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        word,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(
                                        Icons.close,
                                        size: 16,
                                        color: Colors.white70,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                  ),
              
                  const SizedBox(height: 20),
              
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        const Text(
                          'Word Bank',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Tap to add',
                            style: TextStyle(
                              fontSize: 11,
                              color: _green,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              
                  const SizedBox(height: 8),
              
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _wordBank.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    size: 60,
                                    color: _green.withOpacity(0.5),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'All words used!',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Tap CHECK when ready',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : GridView.builder(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                childAspectRatio: 1.8,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              itemCount: _wordBank.length,
                              itemBuilder: (context, index) {
                                final word = _wordBank[index];
                                return GestureDetector(
                                  onTap: () => _addWord(word),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: _green.withOpacity(0.3),
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                        child: Text(
                                          word,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black87,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
              
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed:
                            _selectedWords.isEmpty ? null : _checkAnswer,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _green,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 3,
                        ),
                        child: const Text(
                          'CHECK',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}