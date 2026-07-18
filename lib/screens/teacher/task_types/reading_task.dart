// reading_task.dart - Teacher writes page text and can preview it with TTS
// (ReadingTtsService -- flutter_edge_tts / Microsoft Edge neural voices,
// same engine and voice students hear on screen_seven, so what the
// teacher previews here matches actual playback exactly, word-boundary
// highlighting included). No voice recording, no Cloudinary audio
// upload, no AudioService dependency, no speech-to-text dictation --
// text entry is manual typing only.
//
// -- TTS migration (flutter_tts -> ReadingTtsService) ------------------
// Previously used flutter_tts with setProgressHandler for live
// word-by-word highlighting during preview. Since student-facing
// narration now goes through ReadingTtsService (Edge TTS), keeping the
// teacher preview on flutter_tts would mean the teacher hears a
// different (robotic, on-device) voice than what students actually get
// -- defeating the point of a preview. ReadingTtsService's synthesize()
// call returns real word-boundary timings (WordTiming: text/startMs/
// endMs) alongside the audio, same data screen_seven.dart uses for its
// highlight, so the highlight here is reconstructed from real timing
// data via a position-tracking stream listener instead of flutter_tts's
// character-offset progress callback.
//
// -- Word limit ---------------------------------------------------------
// Soft warning only, at 300 words -- not a hard cap. Target ages span
// 5-9 (grade-level guidance: ages 5-6 want ~20-50 words per passage,
// ages 8-9 can handle 300-500), so a single fixed limit doesn't suit
// every age band. 300 is a reasonable nudge for now; a per-task target
// age selector that adjusts this dynamically is a possible future
// addition, not implemented here.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loringo_app/screens/teacher/task_types/task_type_editor.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/services/tts/reading_tts_service.dart';

// -- ReadingQuestion ----------------------------------------------------

class ReadingQuestion {
  TextEditingController questionCtrl;
  List<Map<String, dynamic>> options;
  List<TextEditingController> optionCtrls;

  ReadingQuestion({
    String question = '',
    List<Map<String, dynamic>>? options,
    List<TextEditingController>? optionCtrls,
  })  : questionCtrl = TextEditingController(text: question),
        options = options ??
            List.generate(3, (_) => {'text': '', 'isCorrect': false}),
        optionCtrls =
            optionCtrls ?? List.generate(3, (_) => TextEditingController());

  void dispose() {
    questionCtrl.dispose();
    for (final c in optionCtrls) c.dispose();
  }
}

// -- PagePreviewState -----------------------------------------------------
// Tracks whether this page's text is currently being previewed, and the
// word-timing list + currently-highlighted word index for that preview.

class PagePreviewState {
  final String pageId;
  bool isPlaying;
  List<WordTiming> words;
  int highlightIndex;

  PagePreviewState({
    required this.pageId,
    this.isPlaying = false,
    this.words = const [],
    this.highlightIndex = -1,
  });

  PagePreviewState copyWith({
    bool? isPlaying,
    List<WordTiming>? words,
    int? highlightIndex,
  }) {
    return PagePreviewState(
      pageId: pageId,
      isPlaying: isPlaying ?? this.isPlaying,
      words: words ?? this.words,
      highlightIndex: highlightIndex ?? this.highlightIndex,
    );
  }
}

// -- ReadingTask ------------------------------------------------------------

class ReadingTask extends StatefulWidget {
  final Color groupColor;
  final Map<String, dynamic>? existingData;
  final TaskEditorController controller;
  final VoidCallback onChanged;
  final int maxPages;
  // Some older tasks stored the story title in a top-level 'question' field
  // on the task document, outside of 'data' (which is all loadData() sees).
  // If the parent screen has access to that document, it can pass the
  // legacy value here so it survives into the new 'data.title' field
  // instead of silently disappearing on first edit.
  final String? legacyTitle;

  const ReadingTask({
    super.key,
    required this.groupColor,
    this.existingData,
    required this.controller,
    required this.onChanged,
    this.maxPages = 10,
    this.legacyTitle,
  });

  @override
  State<ReadingTask> createState() => _ReadingTaskState();
}

class _ReadingTaskState extends State<ReadingTask>
    with TaskTypeEditorMixin
    implements TaskTypeEditor {
  // Soft warning threshold, not a hard cap -- reverted from a 150-word
  // hard limit. With target ages spanning 5-9 (per grade-level guidance:
  // ages 5-6 want ~20-50 words, ages 8-9 can handle 300-500), a single
  // fixed cap doesn't fit every age band. Until a per-task target-age
  // selector exists to set this dynamically, 300 stays as a visual
  // nudge only -- the teacher can still write past it.
  static const int _warnWords = 300;

  late TextEditingController _titleController;
  late List<TextEditingController> _pageControllers;
  late List<ReadingQuestion> _questions;
  late List<PagePreviewState> _previewStates;

  int _currentPageIndex = 0;
  int? _previewPageIndex;
  StreamSubscription<Duration>? _positionSub;

  // -- Lifecycle ------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _pageControllers = [TextEditingController()];
    _questions = [ReadingQuestion(), ReadingQuestion()];
    _previewStates = [PagePreviewState(pageId: 'page_0')];

    if (widget.existingData != null) {
      loadData(widget.existingData!);
      // Backfill from the parent-supplied legacy title only if loadData
      // didn't already find something in data.title/data.question.
      if (_titleController.text.trim().isEmpty &&
          widget.legacyTitle != null &&
          widget.legacyTitle!.trim().isNotEmpty) {
        _titleController.text = widget.legacyTitle!;
      }
    }
    widget.controller.registerEditor(this);

    // Tracks playback position during a preview to figure out which
    // word is currently being spoken, same approach as
    // screen_seven.dart's highlight.
    _positionSub = ReadingTtsService.positionStream.listen((position) {
      final idx = _previewPageIndex;
      if (idx == null || idx >= _previewStates.length || !mounted) return;
      final ms = position.inMilliseconds;
      final words = _previewStates[idx].words;
      int newIndex = -1;
      for (int i = 0; i < words.length; i++) {
        if (ms >= words[i].startMs && ms < words[i].endMs) {
          newIndex = i;
          break;
        }
      }
      if (newIndex != _previewStates[idx].highlightIndex) {
        setState(() {
          _previewStates[idx] = _previewStates[idx].copyWith(highlightIndex: newIndex);
        });
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    for (final c in _pageControllers) c.dispose();
    for (final q in _questions) q.dispose();
    _positionSub?.cancel();
    ReadingTtsService.stop();
    super.dispose();
  }

  // -- TaskTypeEditor ---------------------------------------------------------

  @override
  String get typeId => 'reading';

  @override
  String get displayName => 'Reading Comprehension';

  @override
  String get defaultQuestion => 'Reading Comprehension';

  @override
  void loadData(Map<String, dynamic> data) {
    // 'title' is the canonical field for the story's title, living inside
    // data (which this editor fully owns). Falls back to the legacy
    // top-level 'question' field for tasks created before this field
    // existed, so older content doesn't silently lose its title.
    _titleController.text =
        data['title'] as String? ?? data['question'] as String? ?? '';

    final pages = data['pages'] as List<dynamic>?;
    if (pages != null && pages.isNotEmpty) {
      for (final c in _pageControllers) c.dispose();
      _pageControllers = pages
          .map((p) => TextEditingController(text: (p as String?) ?? ''))
          .toList();

      _previewStates = List.generate(
        _pageControllers.length,
        (i) => PagePreviewState(pageId: 'page_$i'),
      );
    }

    final rawQs = data['questions'] as List<dynamic>?;
    if (rawQs != null && rawQs.isNotEmpty) {
      for (final q in _questions) q.dispose();
      _questions = rawQs.map((rq) {
        final q = rq as Map<String, dynamic>;
        final rawOpts = List<Map<String, dynamic>>.from(q['options'] ?? []);
        return ReadingQuestion(
          question: q['text'] as String? ?? '',
          options: rawOpts
              .map((o) => {
                    'text': o['text'] ?? '',
                    'isCorrect': o['isCorrect'] ?? false,
                  })
              .toList(),
          optionCtrls: rawOpts
              .map((o) => TextEditingController(text: o['text'] as String? ?? ''))
              .toList(),
        );
      }).toList();
    }

    // 'useVoiceRecording' and 'audioData' are intentionally no longer read --
    // any pre-existing tasks that had voice recordings simply fall back to
    // TTS playback on the student side, since that data is no longer
    // written or consumed here.
  }

  @override
  Map<String, dynamic> collectData() {
    return {
      'title': _titleController.text.trim(),
      'pages': _pageControllers
          .map((c) => c.text.trim())
          .where((t) => t.isNotEmpty)
          .toList(),
      'questions': _questions.map((rq) {
        for (int i = 0; i < rq.options.length; i++) {
          rq.options[i]['text'] = rq.optionCtrls[i].text.trim();
        }
        return {
          'text': rq.questionCtrl.text.trim(),
          'options': List<Map<String, dynamic>>.from(rq.options),
        };
      }).toList(),
    };
  }

  @override
  String? validate() {
    if (_titleController.text.trim().isEmpty) {
      return 'Add a title for this story';
    }

    final pages = _pageControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    if (pages.isEmpty) return 'Add at least one page of content';
    if (_questions.isEmpty) return 'Add at least one comprehension question';

    for (int i = 0; i < _questions.length; i++) {
      final rq = _questions[i];
      if (rq.questionCtrl.text.trim().isEmpty) {
        return 'Question ${i + 1}: text cannot be empty';
      }
      if (!rq.options.any((o) => o['isCorrect'] == true)) {
        return 'Question ${i + 1}: mark at least one correct answer';
      }
      if (rq.optionCtrls.where((c) => c.text.trim().isNotEmpty).length < 2) {
        return 'Question ${i + 1}: provide at least 2 answer options';
      }
    }

    return null;
  }

  // -- TTS Preview (hear how this page will sound to students) -----------

  bool get _isAnyPagePlaying => _previewPageIndex != null;

  Future<void> _playPreview(int idx) async {
    final text = _pageControllers[idx].text.trim();
    if (text.isEmpty) return;

    if (_previewPageIndex != null && _previewPageIndex != idx) {
      await ReadingTtsService.stop();
      setState(() {
        _previewStates[_previewPageIndex!] =
            _previewStates[_previewPageIndex!].copyWith(isPlaying: false, highlightIndex: -1);
      });
    }

    setState(() {
      _previewPageIndex = idx;
      _previewStates[idx] = _previewStates[idx].copyWith(isPlaying: true, highlightIndex: -1);
    });

    final success = await ReadingTtsService.speak(
      text,
      onAudioReady: () {
        if (!mounted) return;
        setState(() {
          _previewStates[idx] = _previewStates[idx].copyWith(words: ReadingTtsService.currentWords);
        });
      },
    );

    if (!mounted) return;
    setState(() {
      _previewStates[idx] = _previewStates[idx].copyWith(isPlaying: false, highlightIndex: -1);
      _previewPageIndex = null;
    });

    if (!success) {
      _showSnack('Could not play preview -- check your connection and try again.', isError: true);
    }
  }

  Future<void> _stopPreview(int idx) async {
    if (!_previewStates[idx].isPlaying) return;
    await ReadingTtsService.stop();
    if (mounted) {
      setState(() {
        _previewStates[idx] = _previewStates[idx].copyWith(isPlaying: false, highlightIndex: -1);
        _previewPageIndex = null;
      });
    }
  }

  // -- Page management --------------------------------------------------------

  void _addPage() {
    if (_pageControllers.length >= widget.maxPages) return;
    final newIdx = _pageControllers.length;
    setState(() {
      _pageControllers.add(TextEditingController());
      _previewStates.add(PagePreviewState(pageId: 'page_$newIdx'));
      _currentPageIndex = newIdx;
    });
    widget.onChanged();
  }

  void _removePage() {
    if (_pageControllers.length <= 1) return;
    final idx = _currentPageIndex;
    if (_previewStates[idx].isPlaying) return;
    setState(() {
      _pageControllers[idx].dispose();
      _pageControllers.removeAt(idx);
      _previewStates.removeAt(idx);
      if (_currentPageIndex >= _pageControllers.length) {
        _currentPageIndex = _pageControllers.length - 1;
      }
    });
    widget.onChanged();
  }

  // -- Question management ------------------------------------------------------

  void _addQuestion() {
    if (_questions.length >= 5) return;
    setState(() => _questions.add(ReadingQuestion()));
    widget.onChanged();
  }

  void _removeQuestion(int idx) {
    if (_questions.length <= 1) return;
    setState(() {
      _questions[idx].dispose();
      _questions.removeAt(idx);
    });
    widget.onChanged();
  }

  // -- Helpers ------------------------------------------------------------------

  int _wordCount(String text) =>
      text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.danger : AppColors.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // -- Build ----------------------------------------------------------------

  @override
  Widget buildEditor(BuildContext context) => build(context);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTitleField(),
        const SizedBox(height: AppSpacing.md),
        _buildPagesSection(),
        const SizedBox(height: AppSpacing.md),
        _buildQuestionsSection(),
      ],
    );
  }

  // -- Title field ------------------------------------------------------------

  Widget _buildTitleField() {
    final c = widget.groupColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Story title',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey[800])),
        const SizedBox(height: 8),
        TextFormField(
          controller: _titleController,
          onChanged: (_) => widget.onChanged(),
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87),
          decoration: InputDecoration(
            hintText: 'e.g. "A Sunny Morning Visit"',
            hintStyle: TextStyle(color: Colors.grey[400], fontWeight: FontWeight.normal),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
              borderSide: BorderSide(color: AppColors.divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
              borderSide: BorderSide(color: AppColors.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
              borderSide: BorderSide(color: c, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  // -- Pages section --------------------------------------------------------

  Widget _buildPagesSection() {
    final c = widget.groupColor;
    final ctrl = _pageControllers[_currentPageIndex];
    final words = _wordCount(ctrl.text);
    final isOver = words > _warnWords;
    final total = _pageControllers.length;
    final preview = _previewStates[_currentPageIndex];
    final hasText = ctrl.text.trim().isNotEmpty;

    final isOtherPagePlaying =
        _previewPageIndex != null && _previewPageIndex != _currentPageIndex;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Text('Pages',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800])),
            const SizedBox(width: 6),
            _chip('$total / ${widget.maxPages}', c),
            const Spacer(),
            if (total < widget.maxPages)
              TextButton.icon(
                onPressed: _addPage,
                icon: Icon(Icons.add, size: 14, color: c),
                label: Text('Add page',
                    style: TextStyle(
                        fontSize: 12, color: c, fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),

        // Page tabs
        if (total > 1) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 30,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: total,
              itemBuilder: (_, i) {
                final isActive = i == _currentPageIndex;
                final isPlayingThis = _previewStates[i].isPlaying;

                return GestureDetector(
                  onTap: () => setState(() => _currentPageIndex = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: isActive ? c : Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: isPlayingThis
                            ? Colors.blue
                            : (isActive ? c : AppColors.divider),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isPlayingThis) ...[
                          Icon(Icons.volume_up_rounded,
                              size: 10,
                              color: isActive ? Colors.white : Colors.blue),
                          const SizedBox(width: 3),
                        ],
                        Text('P${i + 1}',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isActive
                                    ? Colors.white
                                    : Colors.grey[600])),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],

        const SizedBox(height: 8),

        // Page card
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: preview.isPlaying
                  ? Colors.blue.withOpacity(0.5)
                  : isOtherPagePlaying
                      ? Colors.blue.withOpacity(0.2)
                      : (isOver
                          ? Colors.orange.withOpacity(0.4)
                          : c.withOpacity(0.25)),
              width: preview.isPlaying ? 2 : 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Card header
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 0),
                child: Row(children: [
                  if (preview.isPlaying)
                    Icon(Icons.volume_up_rounded, size: 14, color: Colors.blue)
                  else
                    Icon(Icons.article_outlined,
                        size: 14, color: isOver ? Colors.orange : c),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      preview.isPlaying
                          ? 'Playing...'
                          : 'Page ${_currentPageIndex + 1} of $total',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: preview.isPlaying
                              ? Colors.blue
                              : (isOver ? Colors.orange : c)),
                    ),
                  ),
                  Text('$words / $_warnWords',
                      style: TextStyle(
                          fontSize: 11,
                          color: isOver ? Colors.orange : Colors.grey[400])),
                  if (total > 1 && !preview.isPlaying) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _removePage,
                      child:
                          Icon(Icons.close, size: 15, color: Colors.grey[400]),
                    ),
                  ],
                ]),
              ),

              // Text field with live word highlight while TTS plays
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: preview.isPlaying
                    ? _buildHighlightedText(ctrl.text, preview)
                    : TextFormField(
                        controller: ctrl,
                        maxLines: 8,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.65,
                          color: Colors.black87,
                        ),
                        onChanged: (_) => widget.onChanged(),
                        decoration: InputDecoration(
                          hintText:
                              'Write the reading passage for page ${_currentPageIndex + 1}...',
                          hintStyle: TextStyle(
                              color: Colors.grey[400], fontSize: 13),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
              ),

              Divider(height: 1, thickness: 0.5, color: Colors.grey[200]),

              // Preview row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: _buildPreviewRow(preview, hasText, isOtherPagePlaying),
              ),
            ],
          ),
        ),

        if (isOtherPagePlaying) ...[
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.info_outline, size: 13, color: Colors.blue[700]),
            const SizedBox(width: 4),
            Text(
              'Playing preview for page ${(_previewPageIndex! + 1)}.',
              style: TextStyle(fontSize: 11, color: Colors.blue[700]),
            ),
          ]),
        ],
      ],
    );
  }

  // -- Highlighted text while TTS preview is playing -----------------------
  // Built from real WordTiming data (same as screen_seven.dart's
  // highlight) rather than flutter_tts's character-offset progress
  // callback -- matches word-for-word what a student would see/hear.

  Widget _buildHighlightedText(String text, PagePreviewState preview) {
    const baseStyle = TextStyle(fontSize: 14, height: 1.65, color: Colors.black87);

    if (preview.words.isEmpty) {
      return SelectableText(text, style: baseStyle);
    }

    final spans = <TextSpan>[];
    int searchStart = 0;
    for (int i = 0; i < preview.words.length; i++) {
      final word = preview.words[i].text;
      final matchIdx = text.indexOf(word, searchStart);
      if (matchIdx < 0) continue;

      if (matchIdx > searchStart) {
        spans.add(TextSpan(text: text.substring(searchStart, matchIdx)));
      }
      final isActive = i == preview.highlightIndex;
      spans.add(TextSpan(
        text: word,
        style: isActive
            ? TextStyle(backgroundColor: Colors.blue.withOpacity(0.25), color: Colors.blue.shade900)
            : null,
      ));
      searchStart = matchIdx + word.length;
    }
    if (searchStart < text.length) {
      spans.add(TextSpan(text: text.substring(searchStart)));
    }

    return RichText(text: TextSpan(style: baseStyle, children: spans));
  }

  // -- Preview row (TTS) -----------------------------------------------------

  Widget _buildPreviewRow(
      PagePreviewState preview, bool hasText, bool isOtherPagePlaying) {
    final c = widget.groupColor;

    return Row(children: [
      Icon(Icons.headphones_rounded,
          size: 14, color: preview.isPlaying ? Colors.blue : Colors.grey[400]),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          preview.isPlaying
              ? 'Playing...'
              : (hasText
                  ? 'Hear how this sounds to students'
                  : 'Write some text first'),
          style: TextStyle(
            fontSize: 12,
            color: preview.isPlaying ? Colors.blue[700] : Colors.grey[500],
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      if (preview.isPlaying)
        _actionBtn(
          label: 'Stop',
          icon: Icons.stop_rounded,
          color: Colors.red,
          onTap: () => _stopPreview(_currentPageIndex),
        )
      else if (hasText && !isOtherPagePlaying)
        _actionBtn(
          label: 'Hear TTS',
          icon: Icons.volume_up_rounded,
          color: c,
          onTap: () => _playPreview(_currentPageIndex),
        ),
    ]);
  }

  Widget _actionBtn({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration:
            BoxDecoration(color: color, borderRadius: BorderRadius.circular(7)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  // -- Questions section ------------------------------------------------------

  Widget _buildQuestionsSection() {
    final c = widget.groupColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('Questions',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800])),
          const SizedBox(width: 6),
          _chip('${_questions.length} / 5', c),
          const Spacer(),
          if (_questions.length < 5)
            TextButton.icon(
              onPressed: _addQuestion,
              icon: Icon(Icons.add, size: 14, color: c),
              label: Text('Add question',
                  style: TextStyle(
                      fontSize: 12, color: c, fontWeight: FontWeight.w600)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ]),
        const SizedBox(height: 8),
        ...List.generate(_questions.length, (i) => _buildQuestionCard(i, c)),
      ],
    );
  }

  Widget _buildQuestionCard(int index, Color c) {
    final rq = _questions[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
            child: Row(children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                child: Center(
                  child: Text('${index + 1}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 8),
              Text('Question ${index + 1}',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: c)),
              const Spacer(),
              if (_questions.length > 1)
                GestureDetector(
                  onTap: () => _removeQuestion(index),
                  child: Icon(Icons.close, size: 15, color: Colors.grey[400]),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            child: TextFormField(
              controller: rq.questionCtrl,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
              decoration: InputDecoration(
                hintText: 'e.g. What does the character do first?',
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey[300]!)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey[300]!)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: c, width: 1.5)),
                filled: true,
                fillColor: Colors.grey[50],
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                isDense: true,
              ),
              onChanged: (_) => widget.onChanged(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('OPTIONS',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey[400],
                          letterSpacing: 0.6)),
                  const Spacer(),
                  if (rq.options.length < 4)
                    GestureDetector(
                      onTap: () => setState(() {
                        rq.options.add({'text': '', 'isCorrect': false});
                        rq.optionCtrls.add(TextEditingController());
                        widget.onChanged();
                      }),
                      child: Text('+ Add option',
                          style: TextStyle(
                              fontSize: 11,
                              color: c,
                              fontWeight: FontWeight.w600)),
                    ),
                ]),
                const SizedBox(height: 6),
                ...List.generate(rq.options.length, (oi) {
                  final isCorrect = rq.options[oi]['isCorrect'] == true;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: isCorrect ? Colors.green.shade50 : Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: isCorrect
                              ? Colors.green.shade300
                              : Colors.grey[300]!),
                    ),
                    child: Row(children: [
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setState(() {
                          rq.options[oi]['isCorrect'] = !isCorrect;
                          widget.onChanged();
                        }),
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isCorrect ? Colors.green : Colors.white,
                            border: Border.all(
                                color: isCorrect
                                    ? Colors.green
                                    : Colors.grey[400]!,
                                width: 1.5),
                          ),
                          child: isCorrect
                              ? const Icon(Icons.check,
                                  size: 12, color: Colors.white)
                              : Center(
                                  child: Text(
                                    String.fromCharCode(65 + oi),
                                    style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey[500]),
                                  ),
                                ),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: rq.optionCtrls[oi],
                          style: TextStyle(
                              fontSize: 13,
                              color: isCorrect
                                  ? Colors.green.shade800
                                  : Colors.black87),
                          decoration: InputDecoration(
                            hintText: isCorrect ? 'Correct answer' : 'Wrong answer',
                            hintStyle:
                                TextStyle(color: Colors.grey[400], fontSize: 12),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                            isDense: true,
                          ),
                          onChanged: (_) => widget.onChanged(),
                        ),
                      ),
                      if (rq.options.length > 2)
                        GestureDetector(
                          onTap: () => setState(() {
                            rq.options.removeAt(oi);
                            rq.optionCtrls[oi].dispose();
                            rq.optionCtrls.removeAt(oi);
                            widget.onChanged();
                          }),
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Icon(Icons.remove_circle_outline,
                                size: 14, color: Colors.grey[400]),
                          ),
                        ),
                    ]),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10)),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}