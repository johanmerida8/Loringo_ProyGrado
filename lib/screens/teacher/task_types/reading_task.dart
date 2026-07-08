// reading_task.dart - Teacher writes page text and can preview it with TTS
// (same en-GB / rate / pitch config used on the student-facing screen, so
// what the teacher hears here matches what students hear). No voice
// recording, no Cloudinary audio upload, no AudioService dependency, no
// speech-to-text dictation — text entry is manual typing only.

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:loringo_app/screens/teacher/task_types/task_type_editor.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/services/tts/tts_phonetic_service.dart';

// ─── ReadingQuestion ──────────────────────────────────────────────────────────

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

// ─── PagePreviewState ─────────────────────────────────────────────────────────
// Tracks whether this page's text is currently being previewed via TTS, and
// the character range flutter_tts reports as currently being spoken (used to
// highlight the word being read live, word-by-word).

class PagePreviewState {
  final String pageId;
  bool isPlaying;
  int highlightStart;
  int highlightEnd;

  PagePreviewState({
    required this.pageId,
    this.isPlaying = false,
    this.highlightStart = -1,
    this.highlightEnd = -1,
  });

  PagePreviewState copyWith({
    bool? isPlaying,
    int? highlightStart,
    int? highlightEnd,
  }) {
    return PagePreviewState(
      pageId: pageId,
      isPlaying: isPlaying ?? this.isPlaying,
      highlightStart: highlightStart ?? this.highlightStart,
      highlightEnd: highlightEnd ?? this.highlightEnd,
    );
  }
}

// ─── ReadingTask ──────────────────────────────────────────────────────────────

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
  static const int _warnWords = 300;

  late TextEditingController _titleController;
  late List<TextEditingController> _pageControllers;
  late List<ReadingQuestion> _questions;
  late List<PagePreviewState> _previewStates;

  int _currentPageIndex = 0;

  final FlutterTts _tts = FlutterTts();
  bool _isTtsReady = false;

  // ─── Lifecycle ────────────────────────────────────────────────────────────

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

    _initTts();
  }

  Future<void> _initTts() async {
    // en-GB: authentic British English, not US — matches student-facing
    // playback voice so what the teacher previews here is what students hear.
    await _tts.setLanguage('en-GB');
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.1);

    // Load phonetic corrections (e.g. "Mia" -> "Mee-ah") once, shared with
    // the student-facing screen so previews here match actual playback.
    await TtsPhoneticService.instance.load();

    _tts.setProgressHandler((text, start, end, word) {
      if (_highlightDisabledForCurrentPreview) return;
      final idx = _previewPageIndex ?? _currentPageIndex;
      if (idx >= _previewStates.length || !mounted) return;
      setState(() {
        _previewStates[idx] = _previewStates[idx].copyWith(
          highlightStart: start,
          highlightEnd: end,
        );
      });
    });

    _tts.setCompletionHandler(() {
      final idx = _previewPageIndex ?? _currentPageIndex;
      if (idx >= _previewStates.length || !mounted) return;
      setState(() {
        _previewStates[idx] = _previewStates[idx].copyWith(
          isPlaying: false,
          highlightStart: -1,
          highlightEnd: -1,
        );
        _previewPageIndex = null;
      });
    });

    _tts.setCancelHandler(() {
      final idx = _previewPageIndex ?? _currentPageIndex;
      if (idx >= _previewStates.length || !mounted) return;
      setState(() {
        _previewStates[idx] = _previewStates[idx].copyWith(
          isPlaying: false,
          highlightStart: -1,
          highlightEnd: -1,
        );
        _previewPageIndex = null;
      });
    });

    _tts.setErrorHandler((dynamic msg) {
      debugPrint('[TTS] error: $msg');
      final idx = _previewPageIndex ?? _currentPageIndex;
      if (idx < _previewStates.length && mounted) {
        setState(() {
          _previewStates[idx] = _previewStates[idx].copyWith(isPlaying: false);
          _previewPageIndex = null;
        });
      }
    });

    if (mounted) setState(() => _isTtsReady = true);
  }

  int? _previewPageIndex;
  bool _highlightDisabledForCurrentPreview = false;

  @override
  void dispose() {
    _titleController.dispose();
    for (final c in _pageControllers) c.dispose();
    for (final q in _questions) q.dispose();
    _tts.stop();
    super.dispose();
  }

  // ─── TaskTypeEditor ───────────────────────────────────────────────────────

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

    // 'useVoiceRecording' and 'audioData' are intentionally no longer read —
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

  // ─── TTS Preview (hear how this page will sound to students) ─────────────

  bool get _isAnyPagePlaying => _previewPageIndex != null;

  Future<void> _playPreview(int idx) async {
    final text = _pageControllers[idx].text.trim();
    if (text.isEmpty) return;

    // If another page is currently playing, stop it first so state doesn't
    // get out of sync (the handlers key off _previewPageIndex).
    if (_previewPageIndex != null && _previewPageIndex != idx) {
      await _tts.stop();
      setState(() {
        _previewStates[_previewPageIndex!] =
            _previewStates[_previewPageIndex!].copyWith(
          isPlaying: false,
          highlightStart: -1,
          highlightEnd: -1,
        );
      });
    }

    if (!_isTtsReady) {
      if (mounted) {
        _showSnack('Text-to-speech is still loading, try again in a moment',
            isError: true);
      }
      return;
    }

    final spokenText = TtsPhoneticService.instance.applyFixes(text);
    // If a phonetic fix changed the text, the character offsets
    // setProgressHandler reports will refer to spokenText, not the original
    // displayed text — they'd no longer line up for highlighting. Rather
    // than show a misaligned highlight, we disable it for this playback
    // (_highlightDisabledForCurrentPreview) and just play audio normally.
    _highlightDisabledForCurrentPreview = spokenText != text;

    setState(() {
      _previewPageIndex = idx;
      _previewStates[idx] = _previewStates[idx].copyWith(isPlaying: true);
    });

    try {
      await _tts.speak(spokenText);
    } catch (e) {
      debugPrint('[TTS] speak error: $e');
      if (mounted) {
        setState(() {
          _previewStates[idx] = _previewStates[idx].copyWith(isPlaying: false);
          _previewPageIndex = null;
        });
        _showSnack('Could not play preview: $e', isError: true);
      }
    }
  }

  Future<void> _stopPreview(int idx) async {
    if (!_previewStates[idx].isPlaying) return;
    await _tts.stop();
    // setCancelHandler will flip isPlaying back to false and clear
    // _previewPageIndex, so no need to setState manually here.
  }

  // ─── Page management ──────────────────────────────────────────────────────

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

  // ─── Question management ──────────────────────────────────────────────────

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

  // ─── Helpers ──────────────────────────────────────────────────────────────

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

  // ─── Build ────────────────────────────────────────────────────────────────

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

  // ─── Title field ────────────────────────────────────────────────────────

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

  // ─── Pages section ────────────────────────────────────────────────────────

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

  // ─── Highlighted text while TTS preview is playing ────────────────────────

  Widget _buildHighlightedText(String text, PagePreviewState preview) {
    final hasRange = preview.highlightStart >= 0 &&
        preview.highlightEnd > preview.highlightStart &&
        preview.highlightEnd <= text.length;

    if (!hasRange) {
      return SelectableText(
        text,
        style: const TextStyle(fontSize: 14, height: 1.65, color: Colors.black87),
      );
    }

    final before = text.substring(0, preview.highlightStart);
    final current = text.substring(preview.highlightStart, preview.highlightEnd);
    final after = text.substring(preview.highlightEnd);

    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 14, height: 1.65, color: Colors.black87),
        children: [
          TextSpan(text: before),
          TextSpan(
            text: current,
            style: TextStyle(
              backgroundColor: Colors.blue.withOpacity(0.25),
              fontWeight: FontWeight.w700,
              color: Colors.blue.shade900,
            ),
          ),
          TextSpan(text: after),
        ],
      ),
    );
  }

  // ─── Preview row (TTS) ─────────────────────────────────────────────────────

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

  // ─── Questions section ────────────────────────────────────────────────────

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