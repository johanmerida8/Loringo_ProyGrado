// screen_two.dart
// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
// import 'package:just_audio/just_audio.dart';
import 'package:loringo_app/screens/initials/widget/responsive_activity_shell.dart';
import 'package:loringo_app/screens/initials/widget/retryable_task.dart';
import 'package:loringo_app/screens/initials/widget/task_exit_guard.dart';
import 'package:loringo_app/screens/initials/widget/task_result_sheet.dart';
// import 'package:loringo_app/services/audio/feedback_sound_service.dart';
import 'package:loringo_app/services/audio/task_feedback.dart';
// import 'package:lottie/lottie.dart';
import 'package:loringo_app/screens/initials/widget/exit_task_dialog.dart';

// -- Data model for one conversation turn ------------------------------------
class _Turn {
  final String bubbleEn;        // original English bubble text
  final List<Map<String, dynamic>> options; // {textEn, isCorrect}

  const _Turn({
    required this.bubbleEn,
    required this.options,
  });
}

class ScreenTwo extends StatefulWidget {
  final String contentId;
  final String unitId;
  final String lessonId;
  final String activityId;
  final String taskId;
  final Function(bool isCorrect) onTaskComplete;
  final int currentTaskNumber;
  final int totalTasks;
  final String collectionName;
  final bool isPracticeRound;

  const ScreenTwo({
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
  State<ScreenTwo> createState() => _ScreenTwoState();
}

class _ScreenTwoState extends State<ScreenTwo> with RetryableTask {
  // final AudioPlayer _player = AudioPlayer();
  final FlutterTts _tts = FlutterTts();

  // All turns loaded from Firestore
  List<_Turn> _turns = [];

  // Which turn the student is currently answering (0-based)
  int _currentTurn = 0;

  // The reply selected for the current turn
  String _selectedReply = '';

  // History: list of {bubble, chosenReply, correct} -- shown as a chat log above
  final List<Map<String, dynamic>> _history = [];

  // Overall correctness tracking
  int _correctCount = 0;
  int _wrongCount = 0;

  bool _isLoading = true;

  static const Color _green = Color(0xFF4CAF50);

  @override
  void initState() {
    super.initState();
    _initTts();
    _fetchTask();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-GB');
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
  }

  @override
  void dispose() {
    // _player.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _fetchTask() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(widget.collectionName)
          .doc(widget.contentId)
          .collection('units').doc(widget.unitId)
          .collection('lessons').doc(widget.lessonId)
          .collection('activities').doc(widget.activityId)
          .collection('tasks').doc(widget.taskId)
          .get();

      if (!doc.exists) return;
      final raw = doc.data() as Map<String, dynamic>;
      final taskData = raw['data'] as Map<String, dynamic>? ?? raw;

      final rawTurns = taskData['turns'] as List<dynamic>?;

      if (rawTurns != null) {
        final built = <_Turn>[];
        for (final t in rawTurns) {
          final turn = t as Map<String, dynamic>;
          final bubbleEn = turn['bubble'] as String? ?? '';
          final rawOpts = List<Map<String, dynamic>>.from(turn['options'] ?? []);
          final opts = rawOpts.map((o) => {
            'textEn': o['text'] ?? '',
            'isCorrect': o['isCorrect'] ?? false,
          }).toList();
          built.add(_Turn(bubbleEn: bubbleEn, options: opts));
        }
        _turns = built;
      } else {
        final questionEn = taskData['question'] as String? ?? '';
        final rawOpts = List<Map<String, dynamic>>.from(taskData['options'] ?? []);
        final opts = rawOpts.map((o) => {
          'textEn': o['text'] ?? '',
          'isCorrect': o['isCorrect'] ?? false,
        }).toList();
        _turns = [_Turn(bubbleEn: questionEn, options: opts)];
      }

      setState(() => _isLoading = false);

      // Auto-speak the first turn's bubble as soon as the task is
      // ready, same auto-play pattern used in screen_seven for reading
      // -- the teacher's line reads itself instead of requiring a
      // manual tap on the speaker icon first.
      if (_turns.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _speak(_turns[_currentTurn].bubbleEn);
        });
      }
    } catch (e) {
      debugPrint('ScreenTwo ERROR: $e');
      setState(() => _isLoading = false);
    }
  }

  void _speak(String text) async {
    if (text.isNotEmpty) await _tts.speak(text);
  }

  Future<void> _handleClose() async {
    final shouldExit = await confirmExitTask(context);
    if (shouldExit && context.mounted) Navigator.pop(context);
  }

  void _checkCurrentTurn() {
    final turn = _turns[_currentTurn];
    final correct = turn.options.firstWhere(
      (o) => o['textEn'] == _selectedReply,
      orElse: () => {'textEn': '', 'isCorrect': false},
    )['isCorrect'] == true;

    TaskFeedback.fire(correct);

    // Soft wrong answer on this turn, attempts left -> retry the SAME
    // turn (clear the reply choice only) without touching _history,
    // _correctCount/_wrongCount, or advancing _currentTurn. Nothing is
    // scored for this turn until a hard result is reached.
    if (!correct &&
        offerRetry(
          context: context,
          onRetry: () => setState(() => _selectedReply = ''),
        )) {
      return;
    }

    if (correct) _correctCount++; else _wrongCount++;
    // Attempts for this turn are done (correct, or wrong with none
    // left) -- reset the counter so the NEXT turn gets its own fresh 2
    // attempts instead of inheriting whatever was left on this one.
    resetAttempts();

    _history.add({
      'bubbleEn': turn.bubbleEn,
      'chosenReply': _selectedReply,
      'correct': correct,
    });

    final isLastTurn = _currentTurn == _turns.length - 1;

    TaskResultSheet.show(
      context,
      isCorrect: correct,
      isPracticeRound: widget.isPracticeRound,
      buttonLabel: isLastTurn ? 'Finish' : 'Continue',
      onContinue: () {
        if (isLastTurn) {
          final overallCorrect = _correctCount > _wrongCount;
          widget.onTaskComplete(overallCorrect);
        } else {
          setState(() {
            _currentTurn++;
            _selectedReply = '';
          });
          // Auto-speak the new turn's bubble right after advancing --
          // same reasoning as the first-turn auto-speak in _fetchTask,
          // just deferred a frame so it fires once the new bubble is
          // actually built/on screen.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _speak(_turns[_currentTurn].bubbleEn);
          });
        }
      },
    );
  }

  Widget _buildHistory() {
    if (_history.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _history.map((entry) {
        final correct = entry['correct'] as bool;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildBubble(entry['bubbleEn'] as String, past: true),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 260),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: correct ? _green.withOpacity(0.15) : Colors.orange.withOpacity(0.15),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(4),
                  ),
                  border: Border.all(color: correct ? _green.withOpacity(0.4) : Colors.orange.withOpacity(0.4)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(child: Text(entry['chosenReply'] as String, style: TextStyle(fontSize: 14, color: correct ? const Color(0xFF2E7D32) : Colors.orange.shade800))),
                  const SizedBox(width: 6),
                  Icon(correct ? Icons.check_circle : Icons.cancel, size: 16, color: correct ? _green : Colors.orange),
                ]),
              ),
            ),
          ]),
        );
      }).toList(),
    );
  }

  Widget _buildBubble(String text, {bool past = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: past ? Colors.grey.shade200 : _green.withOpacity(0.15),
            shape: BoxShape.circle,
            border: Border.all(color: past ? Colors.grey.shade300 : _green.withOpacity(0.4), width: 1.5),
          ),
          child: Icon(Icons.school, color: past ? Colors.grey : _green, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: past ? Colors.grey.shade100 : Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
              ),
              boxShadow: past ? [] : [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Text(text, style: TextStyle(fontSize: past ? 13 : 16, color: past ? Colors.black54 : Colors.black87, height: 1.3)),
          ),
        ),
        if (!past) ...[
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.volume_up, color: _green, size: 22),
            onPressed: () => _speak(text),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ],
    );
  }

  Widget _buildReplyOption(String text) {
    final isSelected = _selectedReply == text;
    return GestureDetector(
      onTap: () => setState(() => _selectedReply = text),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        decoration: BoxDecoration(
          color: isSelected ? _green : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? _green : Colors.grey.shade300, width: isSelected ? 2 : 1.5),
          boxShadow: [BoxShadow(color: isSelected ? _green.withOpacity(0.22) : Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 20, height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: isSelected ? Colors.white : Colors.grey.shade400, width: 2),
              color: isSelected ? Colors.white : Colors.transparent,
            ),
            child: isSelected ? const Icon(Icons.check, size: 12, color: _green) : null,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : Colors.black87))),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const grad = BoxDecoration(
      gradient: LinearGradient(colors: [Color(0xFFE8F5E9), Colors.white], begin: Alignment.topCenter, end: Alignment.bottomCenter),
    );

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_turns.isEmpty) {
      return const Scaffold(body: Center(child: Text('No conversation data')));
    }

    final currentTurnData = _turns[_currentTurn];

    return TaskExitGuard(
      onRequestExit: _handleClose,
      child: Scaffold(
        body: Container(
          decoration: grad,
          child: SafeArea(
            child: ResponsiveActivityShell(
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(children: [
                    IconButton(icon: const Icon(Icons.close, color: Colors.black87, size: 28), onPressed: _handleClose),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.all(Radius.circular(30)),
                        child: LinearProgressIndicator(
                          value: (widget.currentTaskNumber + (_currentTurn / _turns.length)) / widget.totalTasks,
                          backgroundColor: Colors.blueGrey,
                          valueColor: const AlwaysStoppedAnimation<Color>(_green),
                          minHeight: 8,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: _green.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                        child: Text('${_currentTurn + 1}/${_turns.length}', style: const TextStyle(fontSize: 11, color: _green, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ]),
                ),
              
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _buildHistory(),
                      _buildBubble(currentTurnData.bubbleEn),
                      const SizedBox(height: 20),
              
                      Row(children: [
                        Expanded(child: Divider(color: Colors.grey.shade300)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            'Your reply',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
                          ),
                        ),
                        Expanded(child: Divider(color: Colors.grey.shade300)),
                      ]),
                      const SizedBox(height: 12),
              
                      ...currentTurnData.options.map((opt) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildReplyOption(opt['textEn'] as String),
                      )),
              
                      const SizedBox(height: 8),
                    ]),
                  ),
                ),
              
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _selectedReply.isEmpty ? null : _checkCurrentTurn,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        padding: const EdgeInsets.symmetric(vertical: 17),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text(
                        'Check',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}