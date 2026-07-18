// screen_seven.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/initials/widget/responsive_activity_shell.dart';
import 'package:loringo_app/screens/initials/widget/task_exit_guard.dart';
import 'package:loringo_app/screens/initials/widget/task_result_sheet.dart';
import 'package:loringo_app/services/audio/task_feedback.dart';
import 'package:loringo_app/screens/initials/widget/exit_task_dialog.dart';
import 'package:loringo_app/services/tts/reading_tts_service.dart';

enum _Phase { reading, questions }

class ScreenSeven extends StatefulWidget {
  final String contentId;
  final String unitId;
  final String lessonId;
  final String activityId;
  final String taskId;
  final void Function(bool isCorrect, int correct, int wrong) onTaskComplete;
  final int currentTaskNumber;
  final int totalTasks;
  final String collectionName;
  final bool isPracticeRound;

  const ScreenSeven({
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
  State<ScreenSeven> createState() => _ScreenSevenState();
}

class _ScreenSevenState extends State<ScreenSeven>
    with TickerProviderStateMixin {
  Map<String, dynamic>? _taskData;
  bool _loading = true;

  bool _isLoadingAudio = false;
  bool _isSpeaking = false;
  bool _ttsCompleted = false;

  // Word highlight: index into ReadingTtsService.currentWords of the word
  // currently being spoken, or -1 if none/not tracked for this text.
  int _highlightWordIndex = -1;
  StreamSubscription<Duration>? _positionSub;

  _Phase _phase = _Phase.reading;
  int _currentPage = 0;

  int _currentQ = 0;
  int? _selectedIdx;
  bool _answered = false;
  int _correctCount = 0;
  bool _feedbackShown = false;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  static const Color _green = Color(0xFF4CAF50);
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();

    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _fadeCtrl.forward();

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 850))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.82, end: 1.18).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    // Tracks playback position to figure out which word is currently
    // being spoken, using the timings ReadingTtsService returns
    // alongside the audio.
    _positionSub = ReadingTtsService.positionStream.listen((position) {
      if (!mounted || !_isSpeaking) return;
      final ms = position.inMilliseconds;
      final words = ReadingTtsService.currentWords;
      int newIndex = -1;
      for (int i = 0; i < words.length; i++) {
        if (ms >= words[i].startMs && ms < words[i].endMs) {
          newIndex = i;
          break;
        }
      }
      if (newIndex != _highlightWordIndex) {
        setState(() => _highlightWordIndex = newIndex);
      }
    });

    _loadTask();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    ReadingTtsService.stop();
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _tryAutoAdvance() {
    if (_phase != _Phase.reading) return;
    final totalPages = 1 + _pages.length;
    if (_currentPage < totalPages - 1) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted && _phase == _Phase.reading) {
          _pageController.nextPage(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  Future<void> _speak(String text) async {
    if (text.isEmpty) return;
    setState(() {
      _isLoadingAudio = true;
      _isSpeaking = false;
      _ttsCompleted = false;
      _highlightWordIndex = -1;
    });

    final success = await ReadingTtsService.speak(
      text,
      onAudioReady: () {
        if (!mounted) return;
        setState(() {
          _isLoadingAudio = false;
          _isSpeaking = true;
        });
      },
    );

    if (!mounted) return;
    setState(() {
      _isLoadingAudio = false;
      _isSpeaking = false;
      _ttsCompleted = success;
      _highlightWordIndex = -1;
    });

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "Couldn't play narration -- check your connection and try again."),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    _tryAutoAdvance();
  }

  Future<void> _stopTts() async {
    await ReadingTtsService.stop();
    if (mounted) {
      setState(() {
        _isLoadingAudio = false;
        _isSpeaking = false;
        _highlightWordIndex = -1;
      });
    }
  }

  void _toggleSpeed() {
    final next = ReadingTtsService.speed == ReadingSpeed.normal
        ? ReadingSpeed.slow
        : ReadingSpeed.normal;
    ReadingTtsService.setSpeed(next);
    setState(() {});

    final currentText = _currentPage == 0
        ? _title
        : (_currentPage - 1 < _pages.length ? _pages[_currentPage - 1] : '');
    if (currentText.isNotEmpty) _speak(currentText);

    ReadingTtsService.prefetchPages(_pages);
  }

  Future<void> _handleClose() async {
    final shouldExit = await confirmExitTask(context);
    if (shouldExit && context.mounted) Navigator.pop(context);
  }

  Future<void> _loadTask() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(widget.collectionName)
          .doc(widget.contentId)
          .collection('units').doc(widget.unitId)
          .collection('lessons').doc(widget.lessonId)
          .collection('activities').doc(widget.activityId)
          .collection('tasks').doc(widget.taskId)
          .get();
      if (mounted) {
        setState(() {
          _taskData = doc.data() as Map<String, dynamic>?;
          _loading = false;
          _currentPage = 0;
        });

        if (_pages.isNotEmpty && _phase == _Phase.reading) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _phase == _Phase.reading && _currentPage == 0) {
              _speak(_title);
            }
          });
          ReadingTtsService.prefetchPages(_pages);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> get _pages {
    final data = _taskData?['data'] as Map<String, dynamic>?;
    final pagesRaw = data?['pages'] as List<dynamic>?;
    if (pagesRaw != null && pagesRaw.isNotEmpty) {
      return pagesRaw.cast<String>().where((p) => p.trim().isNotEmpty).toList();
    }
    final passage = data?['passage'] as String? ?? '';
    return passage.trim().isNotEmpty ? [passage] : [];
  }

  String get _currentPageText =>
      _currentPage > 0 && (_currentPage - 1) < _pages.length
          ? _pages[_currentPage - 1]
          : '';

  String get _title {
    final data = _taskData?['data'] as Map<String, dynamic>?;
    final dataTitle = data?['title'] as String?;
    if (dataTitle != null && dataTitle.trim().isNotEmpty) return dataTitle;
    final legacyTitle = _taskData?['question'] as String?;
    if (legacyTitle != null && legacyTitle.trim().isNotEmpty) return legacyTitle;
    return 'Reading Passage';
  }

  List<Map<String, dynamic>> get _questions {
    final data = _taskData?['data'] as Map<String, dynamic>?;
    return (data?['questions'] as List<dynamic>? ?? []).cast();
  }

  void _startQuestions() {
    _stopTts();
    setState(() => _phase = _Phase.questions);
  }

  void _goBackToReading() {
    _stopTts();
    setState(() {
      _phase = _Phase.reading;
      _currentPage = 0;
      _pageController.jumpToPage(0);
    });
  }

  void _selectAnswer(int index) async {
    if (_answered || _feedbackShown) return;
    _stopTts();
    final opts = (_questions[_currentQ]['options'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final isCorrect = opts[index]['isCorrect'] == true;
    setState(() {
      _selectedIdx = index;
      _answered = true;
      _feedbackShown = true;
      if (isCorrect) _correctCount++;
    });

    TaskFeedback.fire(isCorrect);

    TaskResultSheet.show(
      context,
      isCorrect: isCorrect,
      isPracticeRound: widget.isPracticeRound,
      buttonLabel: _currentQ < _questions.length - 1 ? 'CONTINUE' : 'FINISH',
      onContinue: _continueToNextQuestion,
    );
  }

  void _continueToNextQuestion() {
    if (_currentQ < _questions.length - 1) {
      _fadeCtrl.reset();
      setState(() {
        _currentQ++;
        _selectedIdx = null;
        _answered = false;
        _feedbackShown = false;
      });
      _fadeCtrl.forward();
    } else {
      final totalQs = _questions.length;
      final wrong = totalQs - _correctCount;
      final pass = _correctCount >= (totalQs / 2).ceil();
      widget.onTaskComplete(pass, _correctCount, wrong);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          backgroundColor: Color(0xFFF3FBF3),
          body: Center(child: CircularProgressIndicator(color: _green)));
    }
    if (_pages.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFFF3FBF3),
        body: Center(child: ResponsiveActivityShell(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.menu_book_rounded, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('No reading content found', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => widget.onTaskComplete(false, 0, 0),
              style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Continue'),
            ),
          ]),
        )),
      );
    }
    return TaskExitGuard(
      onRequestExit: _handleClose,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3FBF3),
        body: SafeArea(
          child: _phase == _Phase.reading ? _buildReadingPhase() : _buildQuestionsPhase(),
        ),
      ),
    );
  }

  Widget _buildReadingPhase() {
    final totalPages = 1 + _pages.length;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(children: [
        PageView.builder(
          controller: _pageController,
          onPageChanged: (index) {
            setState(() => _currentPage = index);
            _stopTts();
            if (index == 0) {
              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted && _phase == _Phase.reading && _currentPage == 0) {
                  _speak(_title);
                }
              });
            } else {
              final contentIdx = index - 1;
              if (contentIdx < _pages.length) {
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (mounted && _phase == _Phase.reading) {
                    _speak(_pages[contentIdx]);
                  }
                });
              }
            }
          },
          itemCount: totalPages,
          itemBuilder: (_, index) => _buildBookPage(index),
        ),
        Positioned(
          top: 16, left: 16,
          child: GestureDetector(
            onTap: _handleClose,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8)]),
              child: const Icon(Icons.arrow_back, color: Colors.black87, size: 24),
            ),
          ),
        ),
        Positioned(
          top: 16, right: 16,
          child: GestureDetector(
            onTap: _toggleSpeed,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8)],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  ReadingTtsService.speed == ReadingSpeed.slow
                      ? Icons.slow_motion_video_rounded
                      : Icons.speed_rounded,
                  size: 18,
                  color: _green,
                ),
                const SizedBox(width: 6),
                Text(
                  ReadingTtsService.speed == ReadingSpeed.slow ? 'Slow' : 'Normal',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _green),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  /// Builds the page text with the currently-spoken word highlighted.
  /// Always renders through the same RichText/TextSpan tree -- even when
  /// nothing is highlighted -- so the base text style (weight, size,
  /// height) never changes between "no word active" and "word active"
  /// states. Previously this fell back to a plain Text() widget when
  /// _highlightWordIndex was -1, which used a different style resolution
  /// path than the RichText branch and made the whole line visibly
  /// flip between two different font weights/thicknesses every time
  /// highlighting turned on/off -- that flicker, not the highlight
  /// color itself, was the "stutter"/"thin vs bold" effect.
  static const TextStyle _pageTextStyle = TextStyle(
    fontSize: 18,
    height: 1.8,
    color: Colors.black87,
    letterSpacing: 0.3,
    fontWeight: FontWeight.normal,
  );

  Widget _buildHighlightedText(String pageText) {
    final words = ReadingTtsService.currentWords;

    if (words.isEmpty) {
      return Text(pageText, style: _pageTextStyle, textAlign: TextAlign.center);
    }

    final spans = <TextSpan>[];
    int searchStart = 0;
    for (int i = 0; i < words.length; i++) {
      final word = words[i].text;
      final matchIdx = pageText.indexOf(word, searchStart);
      if (matchIdx < 0) continue;

      if (matchIdx > searchStart) {
        spans.add(TextSpan(text: pageText.substring(searchStart, matchIdx)));
      }
      final isActive = _isSpeaking && i == _highlightWordIndex;
      spans.add(TextSpan(
        text: word,
        style: isActive
            ? TextStyle(backgroundColor: _green.withOpacity(0.25), color: const Color(0xFF1B5E20))
            : null,
      ));
      searchStart = matchIdx + word.length;
    }
    if (searchStart < pageText.length) {
      spans.add(TextSpan(text: pageText.substring(searchStart)));
    }

    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(style: _pageTextStyle, children: spans),
    );
  }

  Widget _buildBookPage(int pageIndex) {
    final bool isTitlePage = pageIndex == 0;
    final int contentIdx = pageIndex - 1;
    final bool hasContent = !isTitlePage && contentIdx < _pages.length;
    final String pageText = hasContent ? _pages[contentIdx] : '';

    return Container(
      color: Colors.white,
      child: Stack(children: [
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (isTitlePage) ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: _green.withOpacity(0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.menu_book_rounded, size: 80, color: _green),
                  ),
                  const SizedBox(height: 40),
                  _buildHighlightedText(_title),
                  const SizedBox(height: 20),
                  Container(width: 60, height: 3,
                      decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 16),
                  Text('Listen -- the story starts automatically',
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                        color: _green.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                    child: Text('Page ${contentIdx + 1} of ${_pages.length}',
                        style: const TextStyle(fontSize: 14, color: _green, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 32),
                  _buildHighlightedText(pageText),
                ],
              ],
            ),
          ),
        ),

        if (_isLoadingAudio)
          Positioned(
            bottom: 92, right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Preparing narration...',
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
          ),

        Positioned(
          bottom: 24, right: 24,
          child: GestureDetector(
            onTap: () {
              if (_isLoadingAudio) return;
              if (_isSpeaking) {
                _stopTts();
              } else {
                if (isTitlePage) _speak(_title);
                else if (hasContent) _speak(pageText);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: (_isSpeaking || _isLoadingAudio) ? 50 : 56,
              height: (_isSpeaking || _isLoadingAudio) ? 50 : 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: _isLoadingAudio
                    ? [Colors.blueGrey.shade300, Colors.blueGrey.shade400]
                    : _isSpeaking
                        ? [Colors.orange.shade400, Colors.orange.shade600]
                        : [_green, _green.withOpacity(0.8)]),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(
                    color: (_isLoadingAudio
                            ? Colors.blueGrey
                            : _isSpeaking ? Colors.orange : _green)
                        .withOpacity(0.3),
                    blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _isLoadingAudio
                    ? const SizedBox(
                        key: ValueKey('loading'),
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : _isSpeaking
                        ? ScaleTransition(
                            scale: _pulseAnim,
                            child: const Icon(Icons.graphic_eq_rounded,
                                key: ValueKey('speaking'), color: Colors.white, size: 28))
                        : const Icon(Icons.play_arrow_rounded,
                            key: ValueKey('play'), color: Colors.white, size: 30),
              ),
            ),
          ),
        ),

        if (!isTitlePage && contentIdx == _pages.length - 1)
          Positioned(
            bottom: 24, left: 0, right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _startQuestions,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: _green, width: 2),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1),
                        blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.quiz_rounded, color: _green, size: 18),
                    SizedBox(width: 6),
                    Text('Answer Questions',
                        style: TextStyle(color: _green, fontWeight: FontWeight.bold, fontSize: 14)),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _buildQuestionsPhase() {
    if (_questions.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onTaskComplete(true, 0, 0));
      return const Center(child: CircularProgressIndicator(color: _green));
    }
    final q = _questions[_currentQ];
    final opts = (q['options'] as List<dynamic>).cast<Map<String, dynamic>>();
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(child: Column(children: [
        _buildQuestionsHeader(),
        Expanded(child: FadeTransition(opacity: _fadeAnim, child: _buildQuestion(q, opts))),
      ])),
    );
  }

  Widget _buildQuestionsHeader() {
    return Container(
      color: _green,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(children: [
        GestureDetector(
          onTap: _goBackToReading,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
            child: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Task ${widget.currentTaskNumber + 1} of ${widget.totalTasks}',
              style: const TextStyle(color: Colors.white70, fontSize: 10)),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: widget.totalTasks > 0 ? (widget.currentTaskNumber + 1) / widget.totalTasks : 0,
              backgroundColor: Colors.white.withOpacity(0.25),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
              minHeight: 5,
            ),
          ),
        ])),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(16)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.quiz_rounded, size: 12, color: Colors.white),
            const SizedBox(width: 4),
            Text('Q ${_currentQ + 1} / ${_questions.length}',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildQuestion(Map<String, dynamic> q, List<Map<String, dynamic>> opts) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
          ),
          child: Row(children: [
            Container(width: 26, height: 26,
                decoration: const BoxDecoration(color: _green, shape: BoxShape.circle),
                child: Center(child: Text('${_currentQ + 1}',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)))),
            const SizedBox(width: 10),
            Expanded(child: Text(q['text'] as String? ?? '',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87))),
          ]),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Column(children: [
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: opts.length,
                itemBuilder: (context, i) {
                  final opt = opts[i];
                  final isSelected = _selectedIdx == i;
                  final isCorrect = opt['isCorrect'] == true;
                  final showResult = _answered && _selectedIdx != null;

                  Color bgColor = Colors.white;
                  Color borderColor = Colors.grey.shade200;
                  Color radioColor = _green;
                  if (showResult) {
                    if (isSelected) {
                      bgColor = isCorrect ? Colors.green.shade50 : Colors.red.shade50;
                      borderColor = isCorrect ? Colors.green : Colors.red;
                      radioColor = isCorrect ? Colors.green : Colors.red;
                    } else if (isCorrect) {
                      bgColor = Colors.green.shade50;
                      borderColor = Colors.green;
                      radioColor = Colors.green;
                    }
                  }

                  return GestureDetector(
                    onTap: _answered ? null : () => setState(() => _selectedIdx = i),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderColor,
                            width: showResult && (isSelected || isCorrect) ? 2 : 1.5),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4)],
                      ),
                      child: Row(children: [
                        Container(
                          width: 24, height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected ? radioColor : Colors.white,
                            border: Border.all(
                                color: isSelected ? radioColor : Colors.grey.shade400, width: 2),
                          ),
                          child: isSelected ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(
                          '${String.fromCharCode(65 + i)}. ${opt['text']}',
                          style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500,
                            color: showResult && isSelected && !isCorrect
                                ? Colors.red.shade800
                                : showResult && isCorrect ? Colors.green.shade800 : Colors.black87,
                          ),
                        )),
                        if (showResult && isCorrect && isSelected)
                          const Icon(Icons.check_circle, color: Colors.green, size: 20),
                        if (showResult && isSelected && !isCorrect)
                          const Icon(Icons.cancel, color: Colors.red, size: 20),
                      ]),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _answered || _selectedIdx == null
                      ? null
                      : () => _selectAnswer(_selectedIdx!),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    disabledBackgroundColor: Colors.grey.shade300,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                  ),
                  child: Text(
                    _answered ? 'Answered' : 'Check',
                    style: const TextStyle(color: Colors.white, fontSize: 16,
                        fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}