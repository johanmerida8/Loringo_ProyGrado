// screen_seven.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
// import 'package:just_audio/just_audio.dart';
import 'package:loringo_app/screens/initials/widget/responsive_activity_shell.dart';
import 'package:loringo_app/screens/initials/widget/task_result_sheet.dart';
import 'package:loringo_app/services/audio/feedback_sound_service.dart';
import 'package:loringo_app/services/audio/task_feedback.dart';
import 'package:lottie/lottie.dart';
import 'package:loringo_app/screens/initials/widget/exit_task_dialog.dart';
import 'package:loringo_app/services/tts/tts_phonetic_service.dart';

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
  });

  @override
  State<ScreenSeven> createState() => _ScreenSevenState();
}

class _ScreenSevenState extends State<ScreenSeven>
    with TickerProviderStateMixin {
  Map<String, dynamic>? _taskData;
  bool _loading = true;

  final FlutterTts _tts = FlutterTts();
  // Kept only for feedback sound effects (correct/incorrect chime) — no
  // longer used for teacher voice recordings, since reading_task.dart no
  // longer produces audioData/Cloudinary URLs.
  // final AudioPlayer _feedbackPlayer = AudioPlayer();

  bool _isSpeaking = false;
  bool _ttsCompleted = false;

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

    _initTts();
    _loadTask();
  }

  @override
  void dispose() {
    _tts.stop();
    // _feedbackPlayer.dispose();
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
    _pageController.dispose();
    super.dispose();
  }

  // ── TTS ───────────────────────────────────────────────────────────────────
  // en-GB / rate 0.45 / pitch 1.1 — matches the teacher-facing preview in
  // reading_task.dart, so what the teacher hears there is what students
  // hear here.

  Future<void> _initTts() async {
    await _tts.setLanguage('en-GB');
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.1);

    // Same shared corrections used in the teacher preview — keeps
    // pronunciation consistent between what the teacher heard while writing
    // and what the student actually hears.
    await TtsPhoneticService.instance.load();

    try {
      final voices = await _tts.getVoices;
      if (voices != null) {
        const preferredVoices = [
          'en-gb-x-gbb-network', 'en-gb-language', 'en-gb'
        ];
        for (final name in preferredVoices) {
          final match = (voices as List).firstWhere(
            (v) => (v['name'] as String? ?? '').toLowerCase().contains(name),
            orElse: () => null,
          );
          if (match != null) {
            await _tts.setVoice(match);
            break;
          }
        }
      }
    } catch (_) {}

    _tts.setStartHandler(() {
      if (mounted) setState(() => _isSpeaking = true);
    });
    _tts.setCompletionHandler(() {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
          _ttsCompleted = true;
        });
        _tryAutoAdvance();
      }
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _isSpeaking = false);
    });
    _tts.setErrorHandler((_) {
      if (mounted) setState(() => _isSpeaking = false);
    });
  }

  void _tryAutoAdvance() {
    if (_phase != _Phase.reading || _currentPage <= 0) return;
    final contentIdx = _currentPage - 1;
    if (contentIdx < _pages.length - 1) {
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

  // ── Speak (TTS only) ───────────────────────────────────────────────────────

  Future<void> _speak(String text) async {
    if (text.isEmpty) return;
    await _tts.stop();
    if (mounted) {
      setState(() {
        _isSpeaking = true;
        _ttsCompleted = false;
      });
    }
    final spokenText = TtsPhoneticService.instance.applyFixes(text);
    await _tts.speak(spokenText);
  }

  Future<void> _stopTts() async {
    await _tts.stop();
    if (mounted) setState(() => _isSpeaking = false);
  }

  Future<void> _handleClose() async {
    final shouldExit = await confirmExitTask(context);
    if (shouldExit && context.mounted) Navigator.pop(context);
  }

  // ── Data ──────────────────────────────────────────────────────────────────

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

  // 'title' is the canonical field, written by the current editor inside
  // data. Falls back to the legacy top-level 'question' field for tasks
  // created before this field existed, so old content still shows its title
  // instead of the generic "Reading Passage" placeholder.
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

  // ── Answer handling ───────────────────────────────────────────────────────

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
      buttonLabel: _currentQ < _questions.length - 1 ? 'CONTINUE' : 'FINISH',
      // initialChildSize: 0.42,
      // maxChildSize: 0.6,
      onContinue: _continueToNextQuestion,
    );
  }

  // void _playFeedbackSound(bool correct) {
  //   FeedbackSoundService.instance.playResult(correct);
  // }

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

  // void _showResultSheet(bool correct) {
  //   showModalBottomSheet(
  //     context: context,
  //     backgroundColor: Colors.transparent,
  //     isDismissible: false,
  //     enableDrag: false,
  //     isScrollControlled: true,
  //     builder: (_) => DraggableScrollableSheet(
  //       initialChildSize: 0.42, maxChildSize: 0.6, minChildSize: 0.42,
  //       builder: (_, __) => Container(
  //         padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
  //         decoration: const BoxDecoration(
  //           color: Colors.white,
  //           borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
  //           boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, -5))],
  //         ),
  //         child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
  //           Container(width: 40, height: 4,
  //               decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
  //           const SizedBox(height: 8),
  //           Lottie.asset(correct ? 'assets/animation/correct.json' : 'assets/animation/fail.json', height: 120),
  //           const SizedBox(height: 16),
  //           SizedBox(
  //             width: double.infinity,
  //             child: ElevatedButton(
  //               onPressed: () { Navigator.pop(context); _continueToNextQuestion(); },
  //               style: ElevatedButton.styleFrom(
  //                 backgroundColor: correct ? _green : Colors.orange,
  //                 padding: const EdgeInsets.symmetric(vertical: 16),
  //                 shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  //                 elevation: 5,
  //               ),
  //               child: Text(
  //                 _currentQ < _questions.length - 1 ? 'CONTINUE' : 'FINISH',
  //                 style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.2),
  //               ),
  //             ),
  //           ),
  //         ]),
  //       ),
  //     ),
  //   );
  // }

  // ── Main build ────────────────────────────────────────────────────────────

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
    return Scaffold(
      backgroundColor: const Color(0xFFF3FBF3),
      body: SafeArea(
        child: _phase == _Phase.reading ? _buildReadingPhase() : _buildQuestionsPhase(),
      ),
    );
  }

  // ── Phase 1: Reading ──────────────────────────────────────────────────────

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
            if (index > 0) {
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
      ]),
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
                  Text(_title,
                      style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold,
                          color: Colors.black87, letterSpacing: 1, height: 1.3),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  Container(width: 60, height: 3,
                      decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 16),
                  Text('Tap the play button to start reading',
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
                  Text(pageText,
                      style: const TextStyle(fontSize: 18, height: 1.8,
                          color: Colors.black87, letterSpacing: 0.3),
                      textAlign: TextAlign.center),
                ],
              ],
            ),
          ),
        ),

        // Play / stop floating button
        Positioned(
          bottom: 24, right: 24,
          child: GestureDetector(
            onTap: () {
              if (_isSpeaking) {
                _stopTts();
              } else {
                if (isTitlePage) _speak(_title);
                else if (hasContent) _speak(pageText);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: _isSpeaking ? 50 : 56,
              height: _isSpeaking ? 50 : 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: _isSpeaking
                    ? [Colors.orange.shade400, Colors.orange.shade600]
                    : [_green, _green.withOpacity(0.8)]),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(
                    color: (_isSpeaking ? Colors.orange : _green).withOpacity(0.3),
                    blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _isSpeaking
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

        // Answer Questions button — last content page only
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

  // ── Phase 2: Questions ────────────────────────────────────────────────────

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