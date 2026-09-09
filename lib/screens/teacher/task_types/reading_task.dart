// reading_task.dart - Teacher writes page text and can preview it with TTS
// (ReadingTtsService -- Google Cloud Text-to-Speech via the
// generateReadingAudio Cloud Function, same engine and voice students hear
// on screen_seven, so what the teacher previews here matches actual
// playback exactly, word-boundary highlighting included). No voice
// recording, no Cloudinary audio upload, no AudioService dependency, no
// speech-to-text dictation -- text entry is manual typing only.
//
// -- TTS migration (flutter_tts -> ReadingTtsService) ------------------
// Previously used flutter_tts with setProgressHandler for live
// word-by-word highlighting during preview. Since student-facing
// narration goes through ReadingTtsService (server-side Cloud TTS),
// keeping the teacher preview on flutter_tts would mean the teacher hears
// a different (robotic, on-device) voice than what students actually get
// -- defeating the point of a preview. ReadingTtsService's synthesize()
// call returns real word-boundary timings (WordTiming: text/startMs/
// endMs) alongside the audio, same data screen_seven.dart uses for its
// highlight, so the highlight here is reconstructed from real timing
// data via a position-tracking stream listener instead of flutter_tts's
// character-offset progress callback.
//
// -- Story length / word limit -------------------------------------------
// Teacher picks 'short' (max 150 words total, max 10 pages) or 'long'
// (max 300 words total, max 15 pages) up front. Both the total word
// count and page count are hard limits, enforced in validate() -- unlike
// the old soft-300-word-per-page warning this replaces. Existing tasks
// saved before this field existed have no 'storyLength' -- loadData()
// infers 'long' for them if their current content already exceeds the
// short caps, so a pre-existing story never becomes instantly invalid
// just from being reopened.
//
// -- Images -----------------------------------------------------------------
// Cover image (whole story) and per-page illustrations are both optional
// and picked the same way as every other task type's image field: via
// SelectImageDialog, which lets the teacher pick an already-uploaded,
// already-moderated image from the admin or their own media library (see
// image_select_task.dart) -- no separate upload/Cloudinary logic needed
// here, the URL it returns is already live.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/components/image_dialog.dart';
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
    this.legacyTitle,
  });

  @override
  State<ReadingTask> createState() => _ReadingTaskState();
}

class _ReadingTaskState extends State<ReadingTask>
    with TaskTypeEditorMixin
    implements TaskTypeEditor {
  // -- Story length presets ---------------------------------------------
  static const int _shortMaxWords = 150;
  static const int _shortMaxPages = 10;
  static const int _longMaxWords = 300;
  static const int _longMaxPages = 15;

  String _storyLength = 'short'; // 'short' | 'long'

  int get _maxWords => _storyLength == 'long' ? _longMaxWords : _shortMaxWords;
  int get _maxPages => _storyLength == 'long' ? _longMaxPages : _shortMaxPages;

  late TextEditingController _titleController;
  late List<TextEditingController> _pageControllers;
  // Parallel to _pageControllers -- the Cloudinary URL of that page's
  // optional illustration, or '' if the page has none.
  late List<String> _pageImageUrls;
  // Optional cover image for the whole story, or '' if none.
  String _coverImageUrl = '';

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
    _pageImageUrls = [''];
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
  String get displayName => 'teacher.reading_task.displayName'.tr();

  @override
  String get defaultQuestion => 'teacher.reading_task.displayName'.tr();

  @override
  void loadData(Map<String, dynamic> data) {
    // 'title' is the canonical field for the story's title, living inside
    // data (which this editor fully owns). Falls back to the legacy
    // top-level 'question' field for tasks created before this field
    // existed, so older content doesn't silently lose its title.
    _titleController.text =
        data['title'] as String? ?? data['question'] as String? ?? '';

    _coverImageUrl = data['coverImage'] as String? ?? '';

    final pages = data['pages'] as List<dynamic>?;
    if (pages != null && pages.isNotEmpty) {
      for (final c in _pageControllers) c.dispose();
      _pageControllers = [];
      _pageImageUrls = [];
      for (final p in pages) {
        if (p is Map) {
          _pageControllers.add(TextEditingController(text: p['text'] as String? ?? ''));
          _pageImageUrls.add(p['image'] as String? ?? '');
        } else {
          // Legacy shape: pages was a plain List<String>.
          _pageControllers.add(TextEditingController(text: (p as String?) ?? ''));
          _pageImageUrls.add('');
        }
      }

      _previewStates = List.generate(
        _pageControllers.length,
        (i) => PagePreviewState(pageId: 'page_$i'),
      );
    }

    // Stored explicitly for tasks created with this field. Older tasks
    // have none -- infer 'long' if the content they already have would
    // otherwise exceed the 'short' caps, so reopening one never makes it
    // instantly invalid.
    final storedLength = data['storyLength'] as String?;
    if (storedLength == 'short' || storedLength == 'long') {
      _storyLength = storedLength!;
    } else {
      final totalWords = _pageControllers.fold<int>(0, (sum, c) => sum + _wordCount(c.text));
      _storyLength =
          (totalWords > _shortMaxWords || _pageControllers.length > _shortMaxPages)
              ? 'long'
              : 'short';
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
    final pages = <Map<String, dynamic>>[];
    for (int i = 0; i < _pageControllers.length; i++) {
      final text = _pageControllers[i].text.trim();
      if (text.isEmpty) continue;
      pages.add({'text': text, 'image': _pageImageUrls[i]});
    }

    return {
      'title': _titleController.text.trim(),
      'storyLength': _storyLength,
      'coverImage': _coverImageUrl,
      'pages': pages,
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
      return 'teacher.reading_task.titleRequired'.tr();
    }

    final pages = _pageControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    if (pages.isEmpty) return 'teacher.reading_task.pagesRequired'.tr();
    if (pages.length > _maxPages) {
      return 'teacher.reading_task.pagesLimitExceeded'.tr(namedArgs: {
        'storyType': _storyLength == 'short'
            ? 'teacher.reading_task.storyTypeShort'.tr()
            : 'teacher.reading_task.storyTypeLong'.tr(),
        'maxPages': '$_maxPages',
        'overBy': '${pages.length - _maxPages}',
      });
    }

    final totalWords = pages.fold<int>(0, (sum, t) => sum + _wordCount(t));
    if (totalWords > _maxWords) {
      return 'teacher.reading_task.wordsLimitExceeded'.tr(namedArgs: {
        'storyType': _storyLength == 'short'
            ? 'teacher.reading_task.storyTypeShort'.tr()
            : 'teacher.reading_task.storyTypeLong'.tr(),
        'maxWords': '$_maxWords',
        'totalWords': '$totalWords',
      });
    }

    if (_questions.isEmpty) {
      return 'teacher.reading_task.questionsRequired'.tr();
    }

    for (int i = 0; i < _questions.length; i++) {
      final rq = _questions[i];
      if (rq.questionCtrl.text.trim().isEmpty) {
        return 'teacher.reading_task.questionTextEmpty'
            .tr(namedArgs: {'number': '${i + 1}'});
      }
      if (!rq.options.any((o) => o['isCorrect'] == true)) {
        return 'teacher.reading_task.questionNeedsCorrectAnswer'
            .tr(namedArgs: {'number': '${i + 1}'});
      }
      if (rq.optionCtrls.where((c) => c.text.trim().isNotEmpty).length < 2) {
        return 'teacher.reading_task.questionNeedsTwoOptions'
            .tr(namedArgs: {'number': '${i + 1}'});
      }
    }

    return null;
  }

  // -- TTS Preview (hear how this page will sound to students) -----------

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

    final result = await ReadingTtsService.speak(
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

    if (result == SpeakResult.failed) {
      _showSnack('teacher.reading_task.previewPlaybackFailed'.tr(), isError: true);
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

  // -- Story length -------------------------------------------------------

  void _setStoryLength(String length) {
    if (_storyLength == length) return;
    setState(() => _storyLength = length);
    widget.onChanged();
  }

  // -- Cover image ----------------------------------------------------------

  Future<void> _pickCoverImage() async {
    final selected = await showDialog(
      context: context,
      builder: (_) => const SelectImageDialog(singleSelect: true),
    );
    if (selected == null) return;
    final map = selected as Map<String, dynamic>;
    setState(() {
      _coverImageUrl = (map['imageUrl'] as String?) ?? (map['displayUrl'] as String?) ?? '';
    });
    widget.onChanged();
  }

  void _removeCoverImage() {
    setState(() => _coverImageUrl = '');
    widget.onChanged();
  }

  // -- Page illustration ---------------------------------------------------

  Future<void> _pickPageImage(int idx) async {
    final selected = await showDialog(
      context: context,
      builder: (_) => const SelectImageDialog(singleSelect: true),
    );
    if (selected == null) return;
    final map = selected as Map<String, dynamic>;
    setState(() {
      _pageImageUrls[idx] = (map['imageUrl'] as String?) ?? (map['displayUrl'] as String?) ?? '';
    });
    widget.onChanged();
  }

  void _removePageImage(int idx) {
    setState(() => _pageImageUrls[idx] = '');
    widget.onChanged();
  }

  // -- Page management --------------------------------------------------------

  void _addPage() {
    if (_pageControllers.length >= _maxPages) return;
    final newIdx = _pageControllers.length;
    setState(() {
      _pageControllers.add(TextEditingController());
      _pageImageUrls.add('');
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
      _pageImageUrls.removeAt(idx);
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

  int get _totalWords => _pageControllers.fold<int>(0, (sum, c) => sum + _wordCount(c.text));

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
    context.watch<LocaleProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStoryLengthSelector(),
        const SizedBox(height: AppSpacing.md),
        _buildTitleField(),
        const SizedBox(height: AppSpacing.md),
        _buildCoverImageSection(),
        const SizedBox(height: AppSpacing.md),
        _buildPagesSection(),
        const SizedBox(height: AppSpacing.md),
        _buildQuestionsSection(),
      ],
    );
  }

  // -- Story length selector -------------------------------------------------

  Widget _buildStoryLengthSelector() {
    final c = widget.groupColor;
    final totalWords = _totalWords;
    final isOverWords = totalWords > _maxWords;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('teacher.reading_task.storyLengthLabel'.tr(),
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey[800])),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _lengthOption(
                label: 'teacher.reading_task.storyTypeShort'.tr(),
                subtitle: 'teacher.reading_task.storyLengthSubtitle'.tr(namedArgs: {
                  'maxWords': '$_shortMaxWords',
                  'maxPages': '$_shortMaxPages',
                }),
                selected: _storyLength == 'short',
                color: c,
                onTap: () => _setStoryLength('short'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _lengthOption(
                label: 'teacher.reading_task.storyTypeLong'.tr(),
                subtitle: 'teacher.reading_task.storyLengthSubtitle'.tr(namedArgs: {
                  'maxWords': '$_longMaxWords',
                  'maxPages': '$_longMaxPages',
                }),
                selected: _storyLength == 'long',
                color: c,
                onTap: () => _setStoryLength('long'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.text_fields_rounded,
                size: 14, color: isOverWords ? AppColors.danger : Colors.grey[500]),
            const SizedBox(width: 6),
            Text(
              'teacher.reading_task.totalWordsLabel'.tr(namedArgs: {
                'totalWords': '$totalWords',
                'maxWords': '$_maxWords',
              }),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isOverWords ? AppColors.danger : Colors.grey[600],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _lengthOption({
    required String label,
    required String subtitle,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: selected ? color : AppColors.divider, width: selected ? 1.5 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 16,
                color: selected ? color : Colors.grey[400],
              ),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected ? color : Colors.black87)),
            ]),
            const SizedBox(height: 3),
            Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }

  // -- Title field ------------------------------------------------------------

  Widget _buildTitleField() {
    final c = widget.groupColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('teacher.reading_task.storyTitleLabel'.tr(),
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey[800])),
        const SizedBox(height: 8),
        TextFormField(
          controller: _titleController,
          onChanged: (_) => widget.onChanged(),
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87),
          decoration: InputDecoration(
            hintText: 'teacher.reading_task.storyTitleHint'.tr(),
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

  // -- Cover image section --------------------------------------------------

  Widget _buildCoverImageSection() {
    final c = widget.groupColor;
    final hasImage = _coverImageUrl.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('teacher.reading_task.coverImageLabel'.tr(),
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey[800])),
          const SizedBox(width: 6),
          Text('teacher.reading_task.optionalLabel'.tr(), style: TextStyle(fontSize: 11, color: Colors.grey[400])),
        ]),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(AppRadii.sm),
                border: Border.all(color: AppColors.divider),
              ),
              child: hasImage
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                      child: Image.network(
                        _coverImageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Icon(Icons.broken_image, color: Colors.grey[400]),
                      ),
                    )
                  : Icon(Icons.menu_book_rounded, color: Colors.grey[350], size: 32),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'teacher.reading_task.coverImageDescription'.tr(),
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _imgActionBtn(
                      label: hasImage
                          ? 'common.change'.tr()
                          : 'teacher.reading_task.addCoverLabel'.tr(),
                      icon: Icons.image_outlined,
                      color: c,
                      onTap: _pickCoverImage,
                    ),
                    if (hasImage)
                      _imgActionBtn(
                        label: 'teacher.reading_task.removeLabel'.tr(),
                        icon: Icons.delete_outline,
                        color: AppColors.danger,
                        onTap: _removeCoverImage,
                      ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _imgActionBtn({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  // -- Pages section --------------------------------------------------------

  Widget _buildPagesSection() {
    final c = widget.groupColor;
    final ctrl = _pageControllers[_currentPageIndex];
    final total = _pageControllers.length;
    final preview = _previewStates[_currentPageIndex];
    final hasText = ctrl.text.trim().isNotEmpty;
    final pageImage = _pageImageUrls[_currentPageIndex];
    final hasPageImage = pageImage.trim().isNotEmpty;

    final isOtherPagePlaying =
        _previewPageIndex != null && _previewPageIndex != _currentPageIndex;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Text('teacher.reading_task.pagesLabel'.tr(),
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800])),
            const SizedBox(width: 6),
            _chip('teacher.reading_task.pagesCountChip'.tr(namedArgs: {
              'count': '$total',
              'max': '$_maxPages',
            }), c),
            const Spacer(),
            if (total < _maxPages)
              TextButton.icon(
                onPressed: _addPage,
                icon: Icon(Icons.add, size: 14, color: c),
                label: Text('teacher.reading_task.addPageLabel'.tr(),
                    style: TextStyle(
                        fontSize: 12, color: c, fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              )
            else
              Text('teacher.reading_task.pageLimitReached'.tr(),
                  style: TextStyle(fontSize: 11, color: Colors.grey[400])),
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
                        if (_pageImageUrls[i].trim().isNotEmpty) ...[
                          Icon(Icons.image,
                              size: 10,
                              color: isActive ? Colors.white : Colors.grey[500]),
                          const SizedBox(width: 3),
                        ],
                        Text(
                            'teacher.reading_task.pageTabLabel'
                                .tr(namedArgs: {'number': '${i + 1}'}),
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
                      : c.withOpacity(0.25),
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
                    Icon(Icons.article_outlined, size: 14, color: c),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      preview.isPlaying
                          ? 'teacher.reading_task.playingLabel'.tr()
                          : 'teacher.reading_task.pageOfTotal'.tr(namedArgs: {
                              'current': '${_currentPageIndex + 1}',
                              'total': '$total',
                            }),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: preview.isPlaying ? Colors.blue : c),
                    ),
                  ),
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
                        maxLength: 300,
                        maxLines: 8,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.65,
                          color: Colors.black87,
                        ),
                        onChanged: (_) => widget.onChanged(),
                        decoration: InputDecoration(
                          hintText: 'teacher.reading_task.pageTextHint'
                              .tr(namedArgs: {
                            'number': '${_currentPageIndex + 1}',
                          }),
                          hintStyle: TextStyle(
                              color: Colors.grey[400], fontSize: 13),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          counterStyle: TextStyle(fontSize: 10, color: Colors.grey[400]),
                        ),
                      ),
              ),

              Divider(height: 1, thickness: 0.5, color: Colors.grey[200]),

              // Page illustration (optional)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: hasPageImage
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                pageImage,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    Icon(Icons.broken_image, size: 16, color: Colors.grey[400]),
                              ),
                            )
                          : Icon(Icons.image_outlined, size: 16, color: Colors.grey[350]),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hasPageImage
                            ? 'teacher.reading_task.pageIllustrationAdded'.tr()
                            : 'teacher.reading_task.pageIllustrationNone'.tr(),
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ),
                    _imgActionBtn(
                      label: hasPageImage
                          ? 'common.change'.tr()
                          : 'teacher.reading_task.addImageLabel'.tr(),
                      icon: Icons.image_outlined,
                      color: c,
                      onTap: () => _pickPageImage(_currentPageIndex),
                    ),
                    if (hasPageImage) ...[
                      const SizedBox(width: 6),
                      _imgActionBtn(
                        label: 'teacher.reading_task.removeLabel'.tr(),
                        icon: Icons.delete_outline,
                        color: AppColors.danger,
                        onTap: () => _removePageImage(_currentPageIndex),
                      ),
                    ],
                  ],
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
              'teacher.reading_task.playingPreviewForPage'.tr(namedArgs: {
                'number': '${_previewPageIndex! + 1}',
              }),
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
              ? 'teacher.reading_task.playingLabel'.tr()
              : (hasText
                  ? 'teacher.reading_task.hearHowSounds'.tr()
                  : 'teacher.reading_task.writeTextFirst'.tr()),
          style: TextStyle(
            fontSize: 12,
            color: preview.isPlaying ? Colors.blue[700] : Colors.grey[500],
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      if (preview.isPlaying)
        _actionBtn(
          label: 'teacher.reading_task.stopLabel'.tr(),
          icon: Icons.stop_rounded,
          color: Colors.red,
          onTap: () => _stopPreview(_currentPageIndex),
        )
      else if (hasText && !isOtherPagePlaying)
        _actionBtn(
          label: 'teacher.reading_task.hearTtsLabel'.tr(),
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
          Text('teacher.reading_task.questionsLabel'.tr(),
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800])),
          const SizedBox(width: 6),
          _chip('teacher.reading_task.questionsCountChip'
              .tr(namedArgs: {'count': '${_questions.length}'}), c),
          const Spacer(),
          if (_questions.length < 5)
            TextButton.icon(
              onPressed: _addQuestion,
              icon: Icon(Icons.add, size: 14, color: c),
              label: Text('teacher.reading_task.addQuestionLabel'.tr(),
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
              Text(
                  'teacher.reading_task.questionNumberLabel'
                      .tr(namedArgs: {'number': '${index + 1}'}),
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
                hintText: 'teacher.reading_task.questionHint'.tr(),
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
                  Text('teacher.reading_task.optionsLabel'.tr(),
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
                      child: Text('teacher.reading_task.addOptionLabel'.tr(),
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
                            hintText: isCorrect
                                ? 'teacher.reading_task.correctAnswerHint'.tr()
                                : 'teacher.reading_task.wrongAnswerHint'.tr(),
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
