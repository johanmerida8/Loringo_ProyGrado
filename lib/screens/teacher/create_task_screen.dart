// create_task_screen.dart
import 'package:flutter/material.dart';
import 'package:loringo_app/components/image_dialog.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/utils/image_service.dart';

class CreatePersonalizedTaskScreen extends StatefulWidget {
  final String groupId;
  final String contentId;
  final String unitId;
  final String lessonId;
  final String activityId;
  final Color  groupColor;
  final String? taskId;
  final Map<String, dynamic>? existingData;

  const CreatePersonalizedTaskScreen({
    super.key,
    required this.groupId,
    required this.contentId,
    required this.unitId,
    required this.lessonId,
    required this.activityId,
    required this.groupColor,
    this.taskId,
    this.existingData,
  });

  @override
  State<CreatePersonalizedTaskScreen> createState() =>
      _CreatePersonalizedTaskScreenState();
}

// ── Chat turn model ───────────────────────────────────────────────────────────
class _ChatTurn {
  TextEditingController bubbleCtrl;
  List<Map<String, dynamic>> options;
  List<TextEditingController> optionCtrl;
  bool expanded;

  _ChatTurn({
    String bubble = '',
    List<Map<String, dynamic>>? options,
    List<TextEditingController>? optionCtrl,
    this.expanded = true,
  })  : bubbleCtrl = TextEditingController(text: bubble),
        options = options ??
            [
              {'text': '', 'isCorrect': false},
              {'text': '', 'isCorrect': false},
              {'text': '', 'isCorrect': false},
            ],
        optionCtrl = optionCtrl ??
            [
              TextEditingController(),
              TextEditingController(),
              TextEditingController(),
            ];

  void dispose() {
    bubbleCtrl.dispose();
    for (final c in optionCtrl) c.dispose();
  }
}

// ── Match pair model ──────────────────────────────────────────────────────────
class _MatchPair {
  TextEditingController englishCtrl;
  TextEditingController translatedCtrl;
  TextEditingController imageUrlCtrl;
  Map<String, dynamic>? pickedImage;

  _MatchPair({
    String english = '',
    String translated = '',
    String imageUrl = '',
  })  : englishCtrl    = TextEditingController(text: english),
        translatedCtrl = TextEditingController(text: translated),
        imageUrlCtrl   = TextEditingController(text: imageUrl);

  void dispose() {
    englishCtrl.dispose();
    translatedCtrl.dispose();
    imageUrlCtrl.dispose();
  }

  String get resolvedImageUrl =>
      pickedImage != null
          ? (pickedImage!['imageUrl'] as String? ?? '')
          : imageUrlCtrl.text.trim();
}

// ── Reading question model ────────────────────────────────────────────────────
class _ReadingQuestion {
  TextEditingController questionCtrl;
  List<Map<String, dynamic>> options;
  List<TextEditingController> optionCtrls;

  _ReadingQuestion({
    String question = '',
    List<Map<String, dynamic>>? options,
    List<TextEditingController>? optionCtrls,
  })  : questionCtrl = TextEditingController(text: question),
        options = options ??
            [
              {'text': '', 'isCorrect': false},
              {'text': '', 'isCorrect': false},
              {'text': '', 'isCorrect': false},
            ],
        optionCtrls = optionCtrls ??
            [
              TextEditingController(),
              TextEditingController(),
              TextEditingController(),
            ];

  void dispose() {
    questionCtrl.dispose();
    for (final c in optionCtrls) c.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _CreatePersonalizedTaskScreenState
    extends State<CreatePersonalizedTaskScreen> {
  final _formKey    = GlobalKey<FormState>();
  final Database    db = Database();
  final imageService  = ImageService();

  late TextEditingController orderController;
  late TextEditingController questionController;

  String selectedType = 'image_select';
  bool   isLoading    = false;

  // ── per-type state ────────────────────────────────────────────────────────
  List<Map<String, dynamic>>      options             = List.generate(3, (_) => {'text': '', 'image': '', 'isCorrect': false});
  List<TextEditingController>     textControllers     = [];
  List<TextEditingController>     imageControllers    = [];
  List<Map<String, dynamic>?>     pickedImages        = [null, null, null];
  Map<String, dynamic>?           reversePickedImage;

  List<_ChatTurn>                 chatTurns           = [];
  late TextEditingController      arrangeController;
  List<Map<String, dynamic>>      questionSegments    = [];
  List<Map<String, dynamic>>      fillBlankOptions    = List.generate(3, (_) => {'text': '', 'isCorrect': false, 'blankIndex': null});
  List<TextEditingController>     fillBlankControllers = [];
  late TextEditingController      imageUrlController;
  List<Map<String, dynamic>>      reverseOptions      = List.generate(3, (_) => {'text': '', 'isCorrect': false});
  List<TextEditingController>     reverseOptionControllers = [];
  String                          _matchMode          = 'text';
  List<_MatchPair>                matchPairs          = [];
  List<TextEditingController>     pageControllers     = [];
  int                             _currentPageEditorIndex = 0;
  static const int                _warnWordsPerPage   = 300;
  List<_ReadingQuestion>          readingQuestions    = [];

  // ── dirty-check snapshot (set once after _loadExistingTaskData) ───────────
  Map<String, dynamic>?           _originalData;

  static const Map<String, String> _defaultQuestions = {
    'image_select':         'Which of these is ___?',
    'image_select_reverse': 'Select the correct phrase',
    'complete_the_chat':    'Speaking about colours',
    'arrange':              'Arrange the words to form a sentence',
    'match':                'Match the words',
    'reading':              'Reading Comprehension',
  };

  final List<String> taskTypes = [
    'image_select',
    'image_select_reverse',
    'complete_the_chat',
    'fill_blank',
    'arrange',
    'match',
    'reading',
  ];

  String _displayName(String t) {
    const map = {
      'image_select':         'Image Select',
      'image_select_reverse': 'Image Select Reverse',
      'complete_the_chat':    'Complete the Chat',
      'fill_blank':           'Fill in the Blank',
      'arrange':              'Sentence Arrange',
      'match':                'Match',
      'reading':              'Reading Comprehension',
    };
    return map[t] ?? t;
  }

  String _defaultFor(String type) {
    if (type == 'reading') return '';
    return _defaultQuestions[type] ?? '';
  }

  // ── helpers ───────────────────────────────────────────────────────────────
  int get _blankCount =>
      questionSegments.where((s) => s['type'] == 'blank').length;
  Set<int> get _assignedBlankIndices => fillBlankOptions
      .where((o) => o['isCorrect'] == true && o['blankIndex'] != null)
      .map((o) => o['blankIndex'] as int)
      .toSet();
  int get _assignedCorrectCount => _assignedBlankIndices.length;
  List<String> get _arrangeTiles => arrangeController.text
      .trim()
      .split(' ')
      .where((w) => w.isNotEmpty)
      .toList();
  int _wordCount(String text) =>
      text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  // ── Dirty-check helpers ───────────────────────────────────────────────────

  /// Serialises the current UI state into a plain map — same shape as what
  /// gets written to Firestore — so we can compare it to _originalData.
  Map<String, dynamic> _buildCurrentData() {
    final questionText = selectedType == 'fill_blank'
        ? _buildQuestionString()
        : questionController.text.trim();

    Map<String, dynamic> data = {};
    if (selectedType == 'image_select') {
      data = {
        'word': questionText,
        'options': List.generate(options.length, (i) => {
          'text':      textControllers[i].text.trim(),
          'image':     pickedImages[i] != null
                           ? (pickedImages[i]!['imageUrl'] as String? ?? '')
                           : imageControllers[i].text.trim(),
          'isCorrect': options[i]['isCorrect'] ?? false,
        }),
      };
    } else if (selectedType == 'image_select_reverse') {
      data = {
        'image': reversePickedImage != null
            ? (reversePickedImage!['imageUrl'] as String? ?? '')
            : imageUrlController.text.trim(),
        'question': questionText,
        'options': List.generate(reverseOptions.length, (i) => {
          'text':      reverseOptionControllers[i].text.trim(),
          'isCorrect': reverseOptions[i]['isCorrect'] ?? false,
        }),
      };
    } else if (selectedType == 'complete_the_chat') {
      data = {
        'turns': chatTurns.map((turn) => {
          'bubble':  turn.bubbleCtrl.text.trim(),
          'options': List.generate(turn.options.length, (o) => {
            'text':      turn.optionCtrl[o].text.trim(),
            'isCorrect': turn.options[o]['isCorrect'] ?? false,
          }),
        }).toList(),
      };
    } else if (selectedType == 'fill_blank') {
      data = {
        'question': questionText,
        'options': List.generate(fillBlankOptions.length, (i) => {
          'text':       fillBlankControllers[i].text.trim(),
          'isCorrect':  fillBlankOptions[i]['isCorrect'] ?? false,
          'blankIndex': fillBlankOptions[i]['blankIndex'],
        }),
      };
    } else if (selectedType == 'arrange') {
      data = {
        'question': questionText,
        'answer':   _arrangeTiles,
      };
    } else if (selectedType == 'match') {
      data = {
        'mode': _matchMode,
        'pairs': matchPairs.map((p) => {
          'english':    p.englishCtrl.text.trim(),
          'translated': _matchMode == 'text' ? p.translatedCtrl.text.trim() : '',
          'image':      _matchMode == 'image' ? p.resolvedImageUrl : '',
        }).toList(),
      };
    } else if (selectedType == 'reading') {
      data = {
        'pages': pageControllers
            .map((c) => c.text.trim())
            .where((t) => t.isNotEmpty)
            .toList(),
        'questions': readingQuestions.map((rq) => {
          'text': rq.questionCtrl.text.trim(),
          'options': List.generate(rq.options.length, (o) => {
            'text':      rq.optionCtrls[o].text.trim(),
            'isCorrect': rq.options[o]['isCorrect'] ?? false,
          }),
        }).toList(),
      };
    }

    return {
      'type':     selectedType,
      'question': questionText,
      'order':    orderController.text.trim(),
      'data':     data,
    };
  }

  /// Deep-equality comparison via JSON encoding — covers nested lists/maps.
  bool get _hasChanges {
    if (_originalData == null) return true; // create mode — always allow
    final current = _buildCurrentData();
    // Simple but reliable: encode both sides and compare strings.
    String enc(Map<String, dynamic> m) {
      // Normalise lists so order doesn't create false positives in options
      // (we want structural equality, not reference equality).
      return m.toString();
    }
    return enc(current) != enc(_originalData!);
  }

  // ── initState ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    final rawType = widget.existingData?['type'] as String? ?? 'image_select';
    selectedType  = taskTypes.contains(rawType) ? rawType : 'image_select';
    final existingQ  = widget.existingData?['question'] as String? ?? '';
    final defaultQ   = widget.existingData == null ? _defaultFor(selectedType) : '';
    questionController = TextEditingController(
        text: existingQ.isNotEmpty ? existingQ : defaultQ);
    orderController    = TextEditingController(
        text: widget.existingData?['order']?.toString() ?? '');

    for (int i = 0; i < 3; i++) {
      textControllers.add(TextEditingController());
      imageControllers.add(TextEditingController());
      fillBlankControllers.add(TextEditingController());
    }
    imageUrlController = TextEditingController();
    for (int i = 0; i < 3; i++) {
      reverseOptionControllers.add(TextEditingController());
    }
    arrangeController = TextEditingController();
    chatTurns  = [_ChatTurn()];
    matchPairs = [_MatchPair(), _MatchPair(), _MatchPair()];
    _matchMode = 'text';
    pageControllers  = [TextEditingController()];
    readingQuestions = [_ReadingQuestion(), _ReadingQuestion()];
    _initSegments();
    if (widget.existingData != null) {
      _loadExistingTaskData();
      // Snapshot taken AFTER loading so dirty check compares against original values.
      _originalData = _buildCurrentData();
    }
  }

  void _initSegments() {
    questionSegments = [
      {'type': 'text', 'value': '', 'controller': TextEditingController()},
    ];
  }

  // ── load existing data ────────────────────────────────────────────────────
  void _loadExistingTaskData() {
    final data = widget.existingData!['data'] as Map<String, dynamic>?;
    if (data == null) return;
    if (selectedType == 'image_select') {
      questionController.text = data['word'] ?? '';
      final opts = data['options'] as List<dynamic>?;
      if (opts != null) {
        options.clear();
        for (var c in textControllers)  c.dispose();
        for (var c in imageControllers) c.dispose();
        textControllers.clear(); imageControllers.clear(); pickedImages.clear();
        for (final opt in opts) {
          final o = opt as Map<String, dynamic>;
          options.add({'text': o['text'] ?? '', 'image': o['image'] ?? '', 'isCorrect': o['isCorrect'] ?? false});
          textControllers.add(TextEditingController(text: o['text']  ?? ''));
          imageControllers.add(TextEditingController(text: o['image'] ?? ''));
          pickedImages.add(null);
        }
      }
    } else if (selectedType == 'image_select_reverse') {
      imageUrlController.text = data['image'] ?? '';
      questionController.text = data['question'] ?? widget.existingData!['question'] ?? '';
      final opts = data['options'] as List<dynamic>? ?? [];
      reverseOptions.clear();
      for (var c in reverseOptionControllers) c.dispose();
      reverseOptionControllers.clear();
      for (final opt in opts) {
        final o = opt as Map<String, dynamic>;
        reverseOptions.add({'text': o['text'] ?? '', 'isCorrect': o['isCorrect'] ?? false});
        reverseOptionControllers.add(TextEditingController(text: o['text'] ?? ''));
      }
      while (reverseOptions.length < 3) {
        reverseOptions.add({'text': '', 'isCorrect': false});
        reverseOptionControllers.add(TextEditingController());
      }
    } else if (selectedType == 'fill_blank') {
      _loadSegmentsFromString(data['question'] as String? ?? '');
      final opts = data['options'] as List<dynamic>?;
      if (opts != null) {
        fillBlankOptions.clear();
        for (var c in fillBlankControllers) c.dispose();
        fillBlankControllers.clear();
        for (final opt in opts) {
          final o = opt as Map<String, dynamic>;
          int? blankIdx = o['blankIndex'] as int?;
          final isCorrect = o['isCorrect'] as bool? ?? false;
          if (isCorrect && blankIdx == null) blankIdx = 0;
          fillBlankOptions.add({'text': o['text'] ?? '', 'isCorrect': isCorrect, 'blankIndex': blankIdx});
          fillBlankControllers.add(TextEditingController(text: o['text'] ?? ''));
        }
      }
    } else if (selectedType == 'arrange') {
      final answer = data['answer'] as List<dynamic>?;
      if (answer != null) arrangeController.text = answer.join(' ');
      questionController.text = data['question'] ?? widget.existingData!['question'] ?? '';
    } else if (selectedType == 'complete_the_chat') {
      final turns = data['turns'] as List<dynamic>?;
      if (turns != null && turns.isNotEmpty) {
        for (final t in chatTurns) t.dispose();
        chatTurns.clear();
        for (final turn in turns) {
          final t       = turn as Map<String, dynamic>;
          final bubble  = t['bubble'] as String? ?? '';
          final rawOpts = List<Map<String, dynamic>>.from(t['options'] ?? []);
          final opts    = rawOpts.map((o) => {'text': o['text'] ?? '', 'isCorrect': o['isCorrect'] ?? false}).toList();
          final ctrls   = rawOpts.map((o) => TextEditingController(text: o['text'] ?? '')).toList();
          chatTurns.add(_ChatTurn(bubble: bubble, options: opts, optionCtrl: ctrls, expanded: false));
        }
      }
    } else if (selectedType == 'match') {
      _matchMode = data['mode'] as String? ?? 'text';
      final rawPairs = data['pairs'] as List<dynamic>?;
      if (rawPairs != null && rawPairs.isNotEmpty) {
        for (final p in matchPairs) p.dispose();
        matchPairs.clear();
        for (final pair in rawPairs) {
          final p = pair as Map<String, dynamic>;
          matchPairs.add(_MatchPair(
            english:    p['english']    as String? ?? '',
            translated: p['translated'] as String? ?? '',
            imageUrl:   p['image']      as String? ?? '',
          ));
        }
      }
    } else if (selectedType == 'reading') {
      questionController.text = widget.existingData!['question'] as String? ?? '';
      final pages = data['pages'] as List<dynamic>?;
      if (pages != null && pages.isNotEmpty) {
        for (final c in pageControllers) c.dispose();
        pageControllers.clear();
        for (final pageText in pages) {
          pageControllers.add(TextEditingController(text: pageText as String? ?? ''));
        }
      }
      final rawQs = data['questions'] as List<dynamic>?;
      if (rawQs != null && rawQs.isNotEmpty) {
        for (final q in readingQuestions) q.dispose();
        readingQuestions.clear();
        for (final rq in rawQs) {
          final q       = rq as Map<String, dynamic>;
          final rawOpts = List<Map<String, dynamic>>.from(q['options'] ?? []);
          readingQuestions.add(_ReadingQuestion(
            question:    q['text'] as String? ?? '',
            options:     rawOpts.map((o) => {'text': o['text'] ?? '', 'isCorrect': o['isCorrect'] ?? false}).toList(),
            optionCtrls: rawOpts.map((o) => TextEditingController(text: o['text'] ?? '')).toList(),
          ));
        }
      }
    }
  }

  void _loadSegmentsFromString(String q) {
    final parts = q.split('___');
    for (final s in questionSegments) {
      if (s['type'] == 'text') (s['controller'] as TextEditingController).dispose();
    }
    questionSegments = [];
    for (int i = 0; i < parts.length; i++) {
      final ctrl = TextEditingController(text: parts[i]);
      questionSegments.add({'type': 'text', 'value': parts[i], 'controller': ctrl});
      if (i < parts.length - 1) {
        questionSegments.add({'type': 'blank', 'value': null, 'controller': null});
      }
    }
  }

  // ── dispose ───────────────────────────────────────────────────────────────
  @override
  void dispose() {
    questionController.dispose();
    orderController.dispose();
    arrangeController.dispose();
    for (var c in textControllers)           c.dispose();
    for (var c in imageControllers)          c.dispose();
    for (var c in fillBlankControllers)      c.dispose();
    imageUrlController.dispose();
    for (var c in reverseOptionControllers)  c.dispose();
    for (final seg in questionSegments) {
      if (seg['type'] == 'text') (seg['controller'] as TextEditingController).dispose();
    }
    for (final t in chatTurns)  t.dispose();
    for (final p in matchPairs) p.dispose();
    for (final c in pageControllers)   c.dispose();
    for (final q in readingQuestions)  q.dispose();
    super.dispose();
  }

  // ── segment operations ────────────────────────────────────────────────────
  void _insertBlankAfter(int afterIndex) {
    setState(() {
      questionSegments.insert(afterIndex + 1, {'type': 'blank', 'value': null, 'controller': null});
      questionSegments.insert(afterIndex + 2, {'type': 'text', 'value': '', 'controller': TextEditingController()});
    });
  }

  void _removeBlank(int segIndex) {
    setState(() {
      final blankOrdinal = _blankOrdinalAt(segIndex);
      for (int i = 0; i < fillBlankOptions.length; i++) {
        final idx = fillBlankOptions[i]['blankIndex'] as int?;
        if (idx == blankOrdinal) { fillBlankOptions[i]['isCorrect'] = false; fillBlankOptions[i]['blankIndex'] = null; }
        else if (idx != null && idx > blankOrdinal) { fillBlankOptions[i]['blankIndex'] = idx - 1; }
      }
      questionSegments.removeAt(segIndex);
      if (segIndex > 0 && segIndex < questionSegments.length &&
          questionSegments[segIndex - 1]['type'] == 'text' &&
          questionSegments[segIndex]['type']     == 'text') {
        final l = questionSegments[segIndex - 1]['controller'] as TextEditingController;
        final r = questionSegments[segIndex]['controller']     as TextEditingController;
        l.text = l.text + r.text;
        r.dispose();
        questionSegments.removeAt(segIndex);
      }
    });
  }

  int _blankOrdinalAt(int segIndex) {
    int count = 0;
    for (int i = 0; i < segIndex; i++) {
      if (questionSegments[i]['type'] == 'blank') count++;
    }
    return count;
  }

  String _buildQuestionString() {
    final buf = StringBuffer();
    for (final seg in questionSegments) {
      if (seg['type'] == 'text') {
        buf.write((seg['controller'] as TextEditingController).text.trim());
      } else {
        buf.write('___');
      }
    }
    return buf.toString();
  }

  // ── match operations ──────────────────────────────────────────────────────
  void _addMatchPair()            { if (matchPairs.length < 5) setState(() => matchPairs.add(_MatchPair())); }
  void _removeMatchPair(int i)    { if (matchPairs.length > 3) setState(() { matchPairs[i].dispose(); matchPairs.removeAt(i); }); }

  // ── chat operations ───────────────────────────────────────────────────────
  void _addChatTurn()             { if (chatTurns.length < 6)  setState(() { for (final t in chatTurns) t.expanded = false; chatTurns.add(_ChatTurn()); }); }
  void _removeChatTurn(int i)     { if (chatTurns.length > 1)  setState(() { chatTurns[i].dispose(); chatTurns.removeAt(i); }); }
  void _addChatOption(int ti)     { if (chatTurns[ti].options.length < 4) setState(() { chatTurns[ti].options.add({'text': '', 'isCorrect': false}); chatTurns[ti].optionCtrl.add(TextEditingController()); }); }
  void _removeChatOption(int ti, int oi) {
    if (chatTurns[ti].options.length > 3) setState(() { chatTurns[ti].options.removeAt(oi); chatTurns[ti].optionCtrl[oi].dispose(); chatTurns[ti].optionCtrl.removeAt(oi); });
  }

  // ── fill_blank operations ─────────────────────────────────────────────────
  void _addFillBlankOption()      { if (fillBlankOptions.length < (_blankCount + 4).clamp(4, 8)) setState(() { fillBlankOptions.add({'text': '', 'isCorrect': false, 'blankIndex': null}); fillBlankControllers.add(TextEditingController()); }); }
  void _removeFillBlankOption(int i) {
    if (fillBlankOptions.length > (_blankCount + 1).clamp(3, 99)) setState(() { fillBlankOptions.removeAt(i); fillBlankControllers[i].dispose(); fillBlankControllers.removeAt(i); });
  }

  // ── image_select operations ───────────────────────────────────────────────
  void _addImageSelectOption()    { if (options.length < 4) setState(() { options.add({'text': '', 'image': '', 'isCorrect': false}); textControllers.add(TextEditingController()); imageControllers.add(TextEditingController()); pickedImages.add(null); }); }
  void _removeImageSelectOption(int i) {
    if (options.length > 3) setState(() { options.removeAt(i); textControllers[i].dispose(); textControllers.removeAt(i); imageControllers[i].dispose(); imageControllers.removeAt(i); pickedImages.removeAt(i); });
  }
  void _addReverseOption()        { if (reverseOptions.length < 4) setState(() { reverseOptions.add({'text': '', 'isCorrect': false}); reverseOptionControllers.add(TextEditingController()); }); }
  void _removeReverseOption(int i) {
    if (reverseOptions.length > 3) setState(() { reverseOptions.removeAt(i); reverseOptionControllers[i].dispose(); reverseOptionControllers.removeAt(i); });
  }

  // ── reading page operations ───────────────────────────────────────────────
  void _addPage() {
    if (pageControllers.length < 5) {
      setState(() { pageControllers.add(TextEditingController()); _currentPageEditorIndex = pageControllers.length - 1; });
    }
  }
  void _removePage() {
    if (pageControllers.length > 1) {
      setState(() {
        pageControllers[_currentPageEditorIndex].dispose();
        pageControllers.removeAt(_currentPageEditorIndex);
        if (_currentPageEditorIndex >= pageControllers.length) _currentPageEditorIndex = pageControllers.length - 1;
      });
    }
  }

  bool _areOptionsEqual(List<Map<String, dynamic>> a, List<Map<String, dynamic>> b) {
    if (a.length != b.length) return false;
    final sort = (List<Map<String, dynamic>> list) => List.from(list)..sort((x, y) => (x['text'] as String).compareTo(y['text'] as String));
    final aSorted = sort(a); final bSorted = sort(b);
    for (int i = 0; i < aSorted.length; i++) {
      if (aSorted[i]['text'] != bSorted[i]['text'] || aSorted[i]['isCorrect'] != bSorted[i]['isCorrect'] || aSorted[i]['image'] != bSorted[i]['image']) return false;
    }
    return true;
  }

  // ── submit (unchanged logic, just snackbar colors updated) ────────────────
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => isLoading = true);
    try {
      final taskId      = widget.taskId ?? 'task_${DateTime.now().millisecondsSinceEpoch}';
      final questionText = selectedType == 'fill_blank' ? _buildQuestionString() : questionController.text.trim();

      // ── validate ──────────────────────────────────────────────────────────
      if (selectedType == 'image_select') {
        bool hasCorrect = false;
        for (int i = 0; i < options.length; i++) {
          final hasImage = pickedImages[i] != null || imageControllers[i].text.trim().isNotEmpty;
          if (textControllers[i].text.trim().isEmpty || !hasImage) { _snack('Option ${i + 1} must have text and image'); setState(() => isLoading = false); return; }
          if (options[i]['isCorrect'] == true) hasCorrect = true;
        }
        if (!hasCorrect) { _snack('Mark at least one option as correct'); setState(() => isLoading = false); return; }
      } else if (selectedType == 'image_select_reverse') {
        final hasImage = reversePickedImage != null || imageUrlController.text.trim().isNotEmpty;
        if (!hasImage) { _snack('Image is required'); setState(() => isLoading = false); return; }
        bool hasCorrect = false; int filled = 0;
        for (int i = 0; i < reverseOptions.length; i++) { if (reverseOptionControllers[i].text.isNotEmpty) filled++; if (reverseOptions[i]['isCorrect'] == true) hasCorrect = true; }
        if (filled < 3) { _snack('Provide at least 3 options'); setState(() => isLoading = false); return; }
        if (!hasCorrect) { _snack('Mark at least one option as correct'); setState(() => isLoading = false); return; }
      } else if (selectedType == 'complete_the_chat') {
        for (int t = 0; t < chatTurns.length; t++) {
          final turn = chatTurns[t];
          if (turn.bubbleCtrl.text.trim().isEmpty) { _snack('Turn ${t + 1}: chat message cannot be empty'); setState(() => isLoading = false); return; }
          bool hasCorrect = false; int filled = 0;
          for (int o = 0; o < turn.options.length; o++) { if (turn.optionCtrl[o].text.isNotEmpty) filled++; if (turn.options[o]['isCorrect'] == true) hasCorrect = true; }
          if (filled < 3) { _snack('Turn ${t + 1}: provide at least 3 reply options'); setState(() => isLoading = false); return; }
          if (!hasCorrect) { _snack('Turn ${t + 1}: mark one reply as correct'); setState(() => isLoading = false); return; }
        }
      } else if (selectedType == 'fill_blank') {
        final blanks = _blankCount;
        if (blanks == 0) { _snack('Add at least one blank'); setState(() => isLoading = false); return; }
        for (int b = 0; b < blanks; b++) { if (fillBlankOptions.where((o) => o['isCorrect'] == true && o['blankIndex'] == b).isEmpty) { _snack('Blank ${b + 1} has no correct answer'); setState(() => isLoading = false); return; } }
        if (fillBlankOptions.where((o) => o['isCorrect'] == false && fillBlankControllers[fillBlankOptions.indexOf(o)].text.isNotEmpty).isEmpty) { _snack('Add at least one distractor'); setState(() => isLoading = false); return; }
      } else if (selectedType == 'arrange') {
        if (_arrangeTiles.length < 3) { _snack('Sentence must have at least 3 words'); setState(() => isLoading = false); return; }
      } else if (selectedType == 'match') {
        for (int i = 0; i < matchPairs.length; i++) {
          if (matchPairs[i].englishCtrl.text.trim().isEmpty) { _snack('Pair ${i + 1}: English word is required'); setState(() => isLoading = false); return; }
          if (_matchMode == 'text' && matchPairs[i].translatedCtrl.text.trim().isEmpty) { _snack('Pair ${i + 1}: translation is required'); setState(() => isLoading = false); return; }
          if (_matchMode == 'image' && matchPairs[i].resolvedImageUrl.isEmpty) { _snack('Pair ${i + 1}: image is required'); setState(() => isLoading = false); return; }
        }
      } else if (selectedType == 'reading') {
        final pages = pageControllers.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
        if (pages.isEmpty) { _snack('Reading passage cannot be empty'); setState(() => isLoading = false); return; }
        if (readingQuestions.isEmpty) { _snack('Add at least one comprehension question'); setState(() => isLoading = false); return; }
        for (int i = 0; i < readingQuestions.length; i++) {
          final rq = readingQuestions[i];
          if (rq.questionCtrl.text.trim().isEmpty) { _snack('Question ${i + 1}: text cannot be empty'); setState(() => isLoading = false); return; }
          if (!rq.options.any((o) => o['isCorrect'] == true)) { _snack('Question ${i + 1}: mark at least one correct answer'); setState(() => isLoading = false); return; }
          if (rq.optionCtrls.where((c) => c.text.isNotEmpty).length < 3) { _snack('Question ${i + 1}: provide at least 3 options'); setState(() => isLoading = false); return; }
        }
      }

      // ── build data ────────────────────────────────────────────────────────
      Map<String, dynamic> data = {};
      if (selectedType == 'image_select') {
        data = {'word': questionText, 'options': List.generate(options.length, (i) => {'text': textControllers[i].text.trim(), 'image': pickedImages[i] != null ? (pickedImages[i]!['imageUrl'] as String? ?? '') : imageControllers[i].text.trim(), 'isCorrect': options[i]['isCorrect'] ?? false})};
      } else if (selectedType == 'image_select_reverse') {
        data = {'image': reversePickedImage != null ? (reversePickedImage!['imageUrl'] as String? ?? '') : imageUrlController.text.trim(), 'question': questionText, 'options': List.generate(reverseOptions.length, (i) => {'text': reverseOptionControllers[i].text.trim(), 'isCorrect': reverseOptions[i]['isCorrect'] ?? false})};
      } else if (selectedType == 'complete_the_chat') {
        data = {'turns': chatTurns.map((turn) { for (int o = 0; o < turn.options.length; o++) turn.options[o]['text'] = turn.optionCtrl[o].text.trim(); return {'bubble': turn.bubbleCtrl.text.trim(), 'options': List<Map<String, dynamic>>.from(turn.options)}; }).toList()};
      } else if (selectedType == 'fill_blank') {
        for (int i = 0; i < fillBlankOptions.length; i++) fillBlankOptions[i]['text'] = fillBlankControllers[i].text.trim();
        data = {'question': questionText, 'options': List<Map<String, dynamic>>.from(fillBlankOptions)};
      } else if (selectedType == 'arrange') {
        data = {'question': questionText, 'answer': _arrangeTiles};
      } else if (selectedType == 'match') {
        data = {'mode': _matchMode, 'pairs': matchPairs.map((p) => {'english': p.englishCtrl.text.trim(), 'translated': _matchMode == 'text' ? p.translatedCtrl.text.trim() : '', 'image': _matchMode == 'image' ? p.resolvedImageUrl : ''}).toList()};
      } else if (selectedType == 'reading') {
        final pages = pageControllers.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
        data = {'pages': pages, 'questions': readingQuestions.map((rq) { for (int o = 0; o < rq.options.length; o++) rq.options[o]['text'] = rq.optionCtrls[o].text.trim(); return {'text': rq.questionCtrl.text.trim(), 'options': List<Map<String, dynamic>>.from(rq.options)}; }).toList()};
      }

      // ── dirty check — block save if nothing actually changed ─────────────
      if (widget.taskId != null && !_hasChanges) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No changes made'),
          backgroundColor: Colors.grey,
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }

      if (widget.taskId != null) {
        await db.updatePersonalizedTask(
          groupId:    widget.groupId,  contentId: widget.contentId,
          unitId:     widget.unitId,   lessonId:  widget.lessonId,
          activityId: widget.activityId, taskId:  taskId,
          type:       selectedType,    question:  questionText,
          order:      int.parse(orderController.text.trim()), data: data,
        );
      } else {
        await db.createPersonalizedTask(
          groupId:    widget.groupId,  contentId: widget.contentId,
          unitId:     widget.unitId,   lessonId:  widget.lessonId,
          activityId: widget.activityId, taskId:  taskId,
          type:       selectedType,    question:  questionText,
          order:      int.parse(orderController.text.trim()), data: data,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.taskId != null ? 'Changes saved' : 'Task created!'),
          backgroundColor: AppColors.primary,
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) _snack('Error: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _snack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color ?? AppColors.danger,
    ));
  }

  // ── type-specific editors (theme-unified) ─────────────────────────────────

  Widget _buildMatchEditor() {
    final c       = widget.groupColor;
    final isImage = _matchMode == 'image';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Info banner
      Container(
        padding: const EdgeInsets.all(AppSpacing.md - 2),
        decoration: BoxDecoration(color: c.withOpacity(0.07), borderRadius: BorderRadius.circular(AppRadii.md), border: Border.all(color: c.withOpacity(0.3))),
        child: Row(children: [Icon(Icons.info_outline, size: 18, color: c), const SizedBox(width: AppSpacing.sm), Expanded(child: Text('Student taps one from each column to form a match. Min 3, max 5 pairs.', style: TextStyle(fontSize: 12, color: Colors.grey[700])))]),
      ),
      const SizedBox(height: AppSpacing.md),

      // Mode toggle
      Container(
        decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(AppRadii.md), border: Border.all(color: AppColors.divider)),
        child: Row(children: [
          Expanded(child: _modeToggleBtn('text',  'Text ↔ Translation', Icons.translate,     c)),
          Expanded(child: _modeToggleBtn('image', 'Text ↔ Image',       Icons.image_outlined, c)),
        ]),
      ),
      const SizedBox(height: AppSpacing.md),

      // Column headers
      Row(children: [
        const SizedBox(width: 32),
        Expanded(child: _columnHeader('English', Icons.flag, c)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: _columnHeader(isImage ? 'Image' : 'Translation', isImage ? Icons.image_outlined : Icons.flag, isImage ? Colors.purple : Colors.orange)),
        const SizedBox(width: 34),
      ]),
      const SizedBox(height: AppSpacing.sm),

      // Pairs
      ...List.generate(matchPairs.length, (index) {
        final pair = matchPairs[index];
        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _pairIndexBadge(index + 1, c),
            Expanded(child: _pairTextField(pair.englishCtrl, c, 'e.g. "Red"')),
            Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs + 2, vertical: AppSpacing.sm + 2), child: Icon(Icons.swap_horiz, color: Colors.grey[400], size: 20)),
            Expanded(child: isImage ? _buildImagePickerField(pair) : _pairTextField(pair.translatedCtrl, Colors.orange, 'e.g. "Rojo"')),
            if (matchPairs.length > 3)
              GestureDetector(onTap: () => _removeMatchPair(index), child: Container(margin: const EdgeInsets.only(left: AppSpacing.xs, top: AppSpacing.sm), padding: const EdgeInsets.all(AppSpacing.xs), decoration: BoxDecoration(color: AppColors.danger.withOpacity(0.08), shape: BoxShape.circle), child: Icon(Icons.close, size: 14, color: AppColors.danger)))
            else
              const SizedBox(width: 34),
          ]),
        );
      }),

      if (matchPairs.length < 5)
        TextButton.icon(
          onPressed: _addMatchPair,
          icon: Icon(Icons.add, color: c, size: 18),
          label: Text('Add pair (${matchPairs.length}/5)', style: TextStyle(color: c, fontWeight: FontWeight.w600)),
        ),
    ]);
  }

  Widget _columnHeader(String label, IconData icon, Color color) => Container(
    padding: const EdgeInsets.symmetric(vertical: 7),
    decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(AppRadii.sm)),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 13, color: color), const SizedBox(width: 4), Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color))]),
  );

  Widget _pairIndexBadge(int n, Color c) => Container(
    width: 24, height: 24,
    margin: const EdgeInsets.only(right: AppSpacing.sm, top: AppSpacing.sm),
    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    child: Center(child: Text('$n', style: const TextStyle(color: AppColors.onPrimary, fontSize: 11, fontWeight: FontWeight.bold))),
  );

  Widget _pairTextField(TextEditingController ctrl, Color c, String hint) => TextFormField(
    controller: ctrl,
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.sm), borderSide: BorderSide(color: AppColors.divider)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.sm), borderSide: BorderSide(color: c, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
      filled: true, fillColor: Colors.white,
    ),
    style: const TextStyle(fontSize: 14),
    validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
  );

  Widget _modeToggleBtn(String mode, String label, IconData icon, Color c) {
    final isActive = _matchMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _matchMode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.all(AppSpacing.xs),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
        decoration: BoxDecoration(color: isActive ? c : Colors.transparent, borderRadius: BorderRadius.circular(AppRadii.sm)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 16, color: isActive ? AppColors.onPrimary : Colors.grey[500]),
          const SizedBox(width: AppSpacing.xs + 2),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isActive ? AppColors.onPrimary : Colors.grey[600])),
        ]),
      ),
    );
  }

  Widget _buildImagePickerField(_MatchPair pair) {
    final hasImage = pair.pickedImage != null || pair.imageUrlCtrl.text.trim().isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        height: 80,
        decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(AppRadii.sm), border: Border.all(color: AppColors.divider)),
        child: hasImage
            ? ClipRRect(borderRadius: BorderRadius.circular(AppRadii.sm - 1), child: Image.network(pair.resolvedImageUrl, fit: BoxFit.cover, width: double.infinity, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 28)))
            : Center(child: Text('No image', style: TextStyle(fontSize: 12, color: Colors.grey[500]))),
      ),
      const SizedBox(height: AppSpacing.xs + 2),
      SizedBox(width: double.infinity, child: ElevatedButton.icon(
        onPressed: () async {
          final selected = await showDialog(context: context, builder: (_) => SelectImageDialog(singleSelect: true));
          if (selected != null) setState(() { pair.pickedImage = selected as Map<String, dynamic>; pair.imageUrlCtrl.text = selected['imageUrl'] as String? ?? ''; });
        },
        icon: const Icon(Icons.image, size: 16),
        label: Text(hasImage ? 'Change' : 'Select Image', style: const TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[200], foregroundColor: Colors.black87, padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm))),
      )),
    ]);
  }

  Widget _buildSegmentEditor() {
    final c = widget.groupColor;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Question', style: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.w500)),
      const SizedBox(height: AppSpacing.sm),
      Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadii.md), border: Border.all(color: AppColors.divider, width: 1.5)),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (int i = 0; i < questionSegments.length; i++) ...[
            if (questionSegments[i]['type'] == 'text') _buildTextSegment(i, c) else _buildBlankChip(i, c),
          ],
          const SizedBox(height: AppSpacing.sm),
          if (questionSegments.isEmpty || questionSegments.last['type'] != 'blank')
            TextButton.icon(
              onPressed: () => _insertBlankAfter(questionSegments.length - 1),
              icon: Icon(Icons.add_box_outlined, color: c, size: 20),
              label: Text('Add blank here', style: TextStyle(color: c, fontWeight: FontWeight.w600)),
            ),
        ]),
      ),
      if (_blankCount > 0) ...[
        const SizedBox(height: AppSpacing.xs + 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2, vertical: AppSpacing.xs + 1),
          decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(AppRadii.pill), border: Border.all(color: c.withOpacity(0.4))),
          child: Text('$_blankCount blank${_blankCount > 1 ? 's' : ''} added — assign each one below', style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w500)),
        ),
      ],
    ]);
  }

  Widget _buildTextSegment(int segIndex, Color c) {
    final ctrl = questionSegments[segIndex]['controller'] as TextEditingController;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(
          hintText: segIndex == 0 ? 'e.g. "Roses are"' : 'e.g. "and Violets are"',
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.sm), borderSide: BorderSide(color: AppColors.divider)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.sm), borderSide: BorderSide(color: AppColors.divider)),
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
          filled: true, fillColor: Colors.grey[50],
          suffixIcon: _canInsertBlankAfter(segIndex)
              ? Tooltip(message: 'Insert blank', child: IconButton(icon: Icon(Icons.add_box_outlined, color: c, size: 20), onPressed: () => _insertBlankAfter(segIndex)))
              : null,
        ),
        style: const TextStyle(fontSize: 16),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  bool _canInsertBlankAfter(int segIndex) {
    if (segIndex + 1 >= questionSegments.length) return false;
    return questionSegments[segIndex + 1]['type'] != 'blank';
  }

  Widget _buildBlankChip(int segIndex, Color c) {
    final blankOrdinal = _blankOrdinalAt(segIndex);
    final isAssigned   = _assignedBlankIndices.contains(blankOrdinal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 2),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
          decoration: BoxDecoration(
            color: isAssigned ? c.withOpacity(0.1) : Colors.grey[200],
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border: Border.all(color: isAssigned ? c : Colors.grey[400]!, width: isAssigned ? 2 : 1.5),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(isAssigned ? Icons.check_circle : Icons.help_outline, size: 16, color: isAssigned ? c : Colors.grey[500]),
            const SizedBox(width: AppSpacing.xs + 2),
            Text('Blank ${blankOrdinal + 1}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: isAssigned ? c : Colors.grey[600])),
          ]),
        ),
        const SizedBox(width: AppSpacing.sm),
        GestureDetector(
          onTap: () => _removeBlank(segIndex),
          child: Container(padding: const EdgeInsets.all(AppSpacing.xs), decoration: BoxDecoration(color: AppColors.danger.withOpacity(0.08), shape: BoxShape.circle), child: Icon(Icons.close, size: 14, color: AppColors.danger)),
        ),
      ]),
    );
  }

  Widget _buildFillBlankOptionCard(int index) {
    final blanks            = _blankCount;
    final opt               = fillBlankOptions[index];
    final isCorrect         = opt['isCorrect'] as bool;
    final assignedIndices   = _assignedBlankIndices;
    final c                 = widget.groupColor;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: isCorrect ? c : AppColors.divider, width: isCorrect ? 2 : 1),
        borderRadius: BorderRadius.circular(AppRadii.md),
        color: isCorrect ? c.withOpacity(0.04) : Colors.white,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Option ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const Spacer(),
          DropdownButton<int?>(
            value: isCorrect ? opt['blankIndex'] as int? : null,
            hint: Text('Distractor', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
            isDense: true, underline: const SizedBox.shrink(),
            items: [
              DropdownMenuItem<int?>(value: null, child: Text('Distractor', style: TextStyle(fontSize: 13, color: Colors.grey[600]))),
              for (int b = 0; b < blanks; b++)
                DropdownMenuItem<int?>(
                  value: b,
                  enabled: !(assignedIndices.contains(b) && !(isCorrect && opt['blankIndex'] == b)),
                  child: Text('Blank ${b + 1} answer', style: TextStyle(fontSize: 13, color: (assignedIndices.contains(b) && !(isCorrect && opt['blankIndex'] == b)) ? Colors.grey[400] : c)),
                ),
            ],
            onChanged: (selected) => setState(() {
              if (selected == null) { fillBlankOptions[index]['isCorrect'] = false; fillBlankOptions[index]['blankIndex'] = null; }
              else { fillBlankOptions[index]['isCorrect'] = true; fillBlankOptions[index]['blankIndex'] = selected; }
            }),
          ),
          if (fillBlankOptions.length > (_blankCount + 1).clamp(3, 99))
            IconButton(icon: Icon(Icons.remove_circle_outline, color: AppColors.danger, size: 20), onPressed: () => _removeFillBlankOption(index), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
        ]),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: fillBlankControllers[index],
          decoration: InputDecoration(
            labelText: isCorrect ? 'Answer for Blank ${(opt['blankIndex'] as int) + 1}' : 'Distractor word',
            border: const OutlineInputBorder(), filled: true, fillColor: Colors.grey[50],
          ),
          validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
        ),
      ]),
    );
  }

  Widget _buildArrangeEditor() {
    final c     = widget.groupColor;
    final tiles = _arrangeTiles;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadii.md), border: Border.all(color: AppColors.divider)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.text_fields, size: 18, color: c), const SizedBox(width: AppSpacing.sm), const Text('Sentence', style: TextStyle(fontWeight: FontWeight.bold))]),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: arrangeController,
            decoration: InputDecoration(hintText: 'e.g., "The sky is blue today"', border: const OutlineInputBorder(), filled: true, fillColor: Colors.grey[50]),
            maxLines: 2,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              if (v.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length < 3) return 'At least 3 words';
              return null;
            },
          ),
        ]),
      ),
      if (tiles.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.md),
        Text('Tile preview (shown shuffled):', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: tiles.map((word) => Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md - 2, vertical: AppSpacing.sm + 2),
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: c, width: 2), borderRadius: BorderRadius.circular(AppRadii.pill)),
            child: Text(word, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          )).toList(),
        ),
      ],
    ]);
  }

  Widget _buildChatTurnCard(int turnIndex) {
    final turn       = chatTurns[turnIndex];
    final hasCorrect = turn.options.any((o) => o['isCorrect'] == true);
    final c          = widget.groupColor;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: turn.expanded ? c : AppColors.divider, width: turn.expanded ? 2 : 1),
        borderRadius: BorderRadius.circular(AppRadii.md), color: Colors.white,
      ),
      child: Column(children: [
        GestureDetector(
          onTap: () => setState(() => turn.expanded = !turn.expanded),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md - 2, vertical: AppSpacing.md - 4),
            decoration: BoxDecoration(color: turn.expanded ? c.withOpacity(0.05) : Colors.grey[50], borderRadius: BorderRadius.circular(turn.expanded ? AppRadii.sm + 2 : AppRadii.md)),
            child: Row(children: [
              Container(width: 28, height: 28, decoration: BoxDecoration(color: c, shape: BoxShape.circle), child: Center(child: Text('${turnIndex + 1}', style: const TextStyle(color: AppColors.onPrimary, fontWeight: FontWeight.bold, fontSize: 13)))),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(turn.bubbleCtrl.text.isNotEmpty ? turn.bubbleCtrl.text : 'Turn ${turnIndex + 1} — tap to edit', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: turn.bubbleCtrl.text.isNotEmpty ? Colors.black87 : Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (!turn.expanded) ...[
                if (hasCorrect)  _statusChip('✓ ready',      c),
                if (!hasCorrect) _statusChip('needs reply',  Colors.orange),
              ],
              const SizedBox(width: AppSpacing.sm),
              Icon(turn.expanded ? Icons.expand_less : Icons.expand_more, color: Colors.grey),
              if (chatTurns.length > 1)
                GestureDetector(onTap: () => _removeChatTurn(turnIndex), child: Padding(padding: const EdgeInsets.only(left: AppSpacing.sm), child: Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(color: AppColors.danger.withOpacity(0.08), shape: BoxShape.circle), child: Icon(Icons.close, size: 13, color: AppColors.danger)))),
            ]),
          ),
        ),
        if (turn.expanded) Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md - 2, 0, AppSpacing.md - 2, AppSpacing.md - 2),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Divider(height: 20),
            Text('Chat bubble message', style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
            const SizedBox(height: AppSpacing.xs + 2),
            TextFormField(controller: turn.bubbleCtrl, decoration: InputDecoration(hintText: 'e.g. "What colour is the sky?"', prefixIcon: Icon(Icons.chat_bubble_outline, color: c, size: 20), border: const OutlineInputBorder(), filled: true, fillColor: Colors.grey[50]), maxLines: 2, onChanged: (_) => setState(() {}), validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null),
            const SizedBox(height: AppSpacing.md),
            Row(children: [
              Text('Reply options (3–4)', style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
              const Spacer(),
              if (turn.options.length < 4) GestureDetector(onTap: () => _addChatOption(turnIndex), child: Container(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs), decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(AppRadii.sm)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add, size: 14, color: c), const SizedBox(width: AppSpacing.xs), Text('Add reply', style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600))]))),
            ]),
            const SizedBox(height: AppSpacing.sm),
            ...List.generate(turn.options.length, (oi) {
              final isCorrect = turn.options[oi]['isCorrect'] as bool;
              return Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm - 2), padding: const EdgeInsets.fromLTRB(AppSpacing.sm + 2, AppSpacing.sm, AppSpacing.xs + 2, AppSpacing.sm),
                decoration: BoxDecoration(color: isCorrect ? c.withOpacity(0.04) : Colors.grey[50], border: Border.all(color: isCorrect ? c : AppColors.divider, width: isCorrect ? 1.5 : 1), borderRadius: BorderRadius.circular(AppRadii.sm)),
                child: Row(children: [
                  GestureDetector(onTap: () => setState(() => turn.options[oi]['isCorrect'] = !isCorrect), child: Container(width: 22, height: 22, decoration: BoxDecoration(shape: BoxShape.circle, color: isCorrect ? c : Colors.white, border: Border.all(color: isCorrect ? c : Colors.grey[400]!, width: 2)), child: isCorrect ? const Icon(Icons.check, size: 13, color: AppColors.onPrimary) : null)),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: TextField(controller: turn.optionCtrl[oi], decoration: InputDecoration(hintText: isCorrect ? 'Correct reply…' : 'Wrong reply…', hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]), border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero), style: const TextStyle(fontSize: 14))),
                  if (turn.options.length > 3) GestureDetector(onTap: () => _removeChatOption(turnIndex, oi), child: Icon(Icons.remove_circle_outline, size: 18, color: Colors.red[300])),
                ]),
              );
            }),
          ]),
        ),
      ]),
    );
  }

  Widget _statusChip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs + 2, vertical: 2),
    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(AppRadii.sm)),
    child: Text(label, style: TextStyle(fontSize: 11, color: color)),
  );

  Widget _buildReadingEditor() {
    final c           = widget.groupColor;
    final currentCtrl = pageControllers[_currentPageEditorIndex];
    final words       = _wordCount(currentCtrl.text);
    final isOverLimit = words > _warnWordsPerPage;
    final totalPages  = pageControllers.length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(AppSpacing.md - 2),
        decoration: BoxDecoration(color: c.withOpacity(0.07), borderRadius: BorderRadius.circular(AppRadii.md), border: Border.all(color: c.withOpacity(0.3))),
        child: Row(children: [Icon(Icons.menu_book_rounded, color: c, size: 18), const SizedBox(width: AppSpacing.sm), Expanded(child: Text('Write a short passage split across pages. Aim for 200–300 words per page.', style: TextStyle(fontSize: 12, color: Colors.grey[700])))]),
      ),
      const SizedBox(height: AppSpacing.lg),
      Row(children: [
        const Text('Pages', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(width: AppSpacing.sm),
        _statusChip('$totalPages/5', c),
        const Spacer(),
        if (totalPages < 5) TextButton.icon(onPressed: _addPage, icon: Icon(Icons.add, size: 16, color: c), label: Text('Add Page', style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)), style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs + 2))),
      ]),
      const SizedBox(height: AppSpacing.sm),
      if (totalPages > 1)
        SizedBox(height: 36, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: totalPages, itemBuilder: (_, i) {
          final isActive = i == _currentPageEditorIndex;
          final pw       = _wordCount(pageControllers[i].text);
          final tooLong  = pw > _warnWordsPerPage;
          return GestureDetector(onTap: () => setState(() => _currentPageEditorIndex = i), child: Container(
            margin: const EdgeInsets.only(right: AppSpacing.xs + 2), padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md - 2, vertical: AppSpacing.sm),
            decoration: BoxDecoration(color: isActive ? c : Colors.white, borderRadius: BorderRadius.circular(AppRadii.pill), border: Border.all(color: tooLong ? Colors.orange : (isActive ? c : AppColors.divider), width: isActive ? 0 : 1.5), boxShadow: isActive ? [BoxShadow(color: c.withOpacity(0.25), blurRadius: 6)] : null),
            child: Text('Page ${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isActive ? AppColors.onPrimary : (tooLong ? Colors.orange : Colors.grey[700]))),
          ));
        })),
      const SizedBox(height: AppSpacing.sm),
      Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadii.md), border: Border.all(color: isOverLimit ? Colors.orange : c.withOpacity(0.25), width: 1.5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md - 2, vertical: AppSpacing.sm + 2),
            decoration: BoxDecoration(color: isOverLimit ? Colors.orange.withOpacity(0.06) : c.withOpacity(0.05), borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.md - 1)), border: Border(bottom: BorderSide(color: isOverLimit ? Colors.orange.withOpacity(0.2) : c.withOpacity(0.1)))),
            child: Row(children: [
              Icon(Icons.article_rounded, size: 16, color: isOverLimit ? Colors.orange : c),
              const SizedBox(width: AppSpacing.sm),
              Text('Page ${_currentPageEditorIndex + 1} of $totalPages', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isOverLimit ? Colors.orange : c)),
              const Spacer(),
              _statusChip('$words / $_warnWordsPerPage words', isOverLimit ? Colors.orange : c),
              if (totalPages > 1) ...[const SizedBox(width: AppSpacing.sm), GestureDetector(onTap: _removePage, child: Container(padding: const EdgeInsets.all(AppSpacing.xs), decoration: BoxDecoration(color: AppColors.danger.withOpacity(0.08), shape: BoxShape.circle), child: Icon(Icons.close, size: 14, color: AppColors.danger)))],
            ]),
          ),
          TextFormField(controller: currentCtrl, maxLines: 10, onChanged: (_) => setState(() {}), decoration: InputDecoration(hintText: 'Write page ${_currentPageEditorIndex + 1} content here…', hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13), border: InputBorder.none, contentPadding: const EdgeInsets.all(AppSpacing.md - 2)), style: const TextStyle(fontSize: 15, height: 1.6), validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null),
        ]),
      ),
      const SizedBox(height: AppSpacing.lg),
      Row(children: [
        const Text('Questions', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(width: AppSpacing.sm),
        _statusChip('${readingQuestions.length}/5', c),
        const Spacer(),
        if (readingQuestions.length < 5) TextButton.icon(onPressed: () => setState(() => readingQuestions.add(_ReadingQuestion())), icon: Icon(Icons.add, size: 16, color: c), label: Text('Add Question', style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)), style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs + 2))),
      ]),
      const SizedBox(height: AppSpacing.sm),
      ...List.generate(readingQuestions.length, (qi) {
        final rq = readingQuestions[qi];
        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadii.md), border: Border.all(color: AppColors.divider), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2))]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md - 2, vertical: AppSpacing.sm + 2),
              decoration: BoxDecoration(color: c.withOpacity(0.05), borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.md - 1)), border: Border(bottom: BorderSide(color: c.withOpacity(0.1)))),
              child: Row(children: [
                Container(width: 26, height: 26, decoration: BoxDecoration(color: c, shape: BoxShape.circle), child: Center(child: Text('${qi + 1}', style: const TextStyle(color: AppColors.onPrimary, fontSize: 12, fontWeight: FontWeight.bold)))),
                const SizedBox(width: AppSpacing.sm),
                Text('Question ${qi + 1}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: c)),
                const Spacer(),
                if (readingQuestions.length > 1) GestureDetector(onTap: () => setState(() { rq.dispose(); readingQuestions.removeAt(qi); }), child: Container(padding: const EdgeInsets.all(AppSpacing.xs), decoration: BoxDecoration(color: AppColors.danger.withOpacity(0.08), shape: BoxShape.circle), child: Icon(Icons.close, size: 14, color: AppColors.danger))),
              ]),
            ),
            Padding(padding: const EdgeInsets.all(AppSpacing.md), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextFormField(controller: rq.questionCtrl, decoration: InputDecoration(hintText: 'e.g. "What does Tom do first?"', hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13), border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md), borderSide: BorderSide(color: c, width: 2)), filled: true, fillColor: Colors.grey[50], contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2)), validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null),
              const SizedBox(height: AppSpacing.md),
              Row(children: [
                Text('Options', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[600])),
                const Spacer(),
                if (rq.options.length < 4) GestureDetector(onTap: () => setState(() { rq.options.add({'text': '', 'isCorrect': false}); rq.optionCtrls.add(TextEditingController()); }), child: Container(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs), decoration: BoxDecoration(color: c.withOpacity(0.08), borderRadius: BorderRadius.circular(AppRadii.sm)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add, size: 13, color: c), const SizedBox(width: 3), Text('Add', style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600))]))),
              ]),
              const SizedBox(height: AppSpacing.sm),
              ...List.generate(rq.options.length, (oi) {
                final isCorrect = rq.options[oi]['isCorrect'] as bool;
                final label     = String.fromCharCode(65 + oi);
                return Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm - 2), padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2, vertical: AppSpacing.sm),
                  decoration: BoxDecoration(color: isCorrect ? Colors.green.shade50 : Colors.grey[50], borderRadius: BorderRadius.circular(AppRadii.sm), border: Border.all(color: isCorrect ? AppColors.primary : AppColors.divider, width: isCorrect ? 2 : 1)),
                  child: Row(children: [
                    GestureDetector(onTap: () => setState(() => rq.options[oi]['isCorrect'] = !isCorrect), child: Container(width: 26, height: 26, decoration: BoxDecoration(shape: BoxShape.circle, color: isCorrect ? AppColors.primary : Colors.white, border: Border.all(color: isCorrect ? AppColors.primary : Colors.grey[400]!, width: 2)), child: Center(child: isCorrect ? const Icon(Icons.check, size: 14, color: AppColors.onPrimary) : Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[500]))))),
                    const SizedBox(width: AppSpacing.sm + 2),
                    Expanded(child: TextField(controller: rq.optionCtrls[oi], decoration: InputDecoration(hintText: isCorrect ? 'Correct answer…' : 'Wrong answer…', hintStyle: TextStyle(color: Colors.grey[400], fontSize: 12), border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero), style: TextStyle(fontSize: 13, color: isCorrect ? Colors.green.shade800 : Colors.black87))),
                    if (rq.options.length > 3) GestureDetector(onTap: () => setState(() { rq.options.removeAt(oi); rq.optionCtrls[oi].dispose(); rq.optionCtrls.removeAt(oi); }), child: Icon(Icons.remove_circle_outline, size: 16, color: Colors.red[300])),
                  ]),
                );
              }),
            ])),
          ]),
        );
      }),
    ]);
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final c = widget.groupColor;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: c,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.onPrimary),
        title: Text(
          widget.taskId != null ? 'Edit Task' : 'Create Task',
          style: const TextStyle(
              color: AppColors.onPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 20),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Task type selector ────────────────────────────────────────
            DropdownButtonFormField<String>(
              value: selectedType,
              decoration: InputDecoration(
                labelText: 'Task Type',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md), borderSide: BorderSide(color: c, width: 2)),
                filled: true, fillColor: Colors.white,
              ),
              items: taskTypes.map((t) => DropdownMenuItem(value: t, child: Text(_displayName(t)))).toList(),
              onChanged: (v) => setState(() {
                selectedType = v!;
                final cur = questionController.text;
                if (cur.isEmpty || _defaultQuestions.values.contains(cur)) {
                  questionController.text = _defaultFor(selectedType);
                }
              }),
            ),
            const SizedBox(height: AppSpacing.md),

            // ── Question field ────────────────────────────────────────────
            if (selectedType == 'fill_blank')
              _buildSegmentEditor()
            else if (selectedType == 'reading') ...[
              _labelRow('Reading Title'),
              const SizedBox(height: AppSpacing.xs + 2),
              TextFormField(controller: questionController, decoration: _fieldDeco(c, 'e.g. "Tom\'s Classroom Day"'), validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null),
            ] else if (selectedType == 'match') ...[
              _labelRow('Title'),
              const SizedBox(height: AppSpacing.xs + 2),
              TextFormField(controller: questionController, decoration: _fieldDeco(c, 'e.g. "Match the colours"'), validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null),
            ] else if (selectedType != 'arrange') ...[
              _labelRow('Question'),
              const SizedBox(height: AppSpacing.xs + 2),
              TextFormField(
                controller: questionController,
                decoration: _fieldDeco(c, _defaultFor(selectedType)),
                maxLines: selectedType == 'complete_the_chat' ? 1 : 3,
                validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
              ),
            ],

            const SizedBox(height: AppSpacing.md),

            // ── Order field ───────────────────────────────────────────────
            _labelRow('Order'),
            const SizedBox(height: AppSpacing.xs + 2),
            TextFormField(
              controller: orderController,
              decoration: _fieldDeco(c, '1, 2, 3…'),
              keyboardType: TextInputType.number,
              validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
            ),
            const SizedBox(height: AppSpacing.md),

            // ── Type-specific editor ──────────────────────────────────────
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),

            if (selectedType == 'image_select') ...[
              _sectionHeader(context, 'Options (3–4)', onAdd: options.length < 4 ? _addImageSelectOption : null),
              const SizedBox(height: AppSpacing.md),
              ...List.generate(options.length, (index) => Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(border: Border.all(color: AppColors.divider), borderRadius: BorderRadius.circular(AppRadii.md), color: Colors.white),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('Option ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const Spacer(),
                    Row(children: [Checkbox(value: options[index]['isCorrect'], activeColor: c, onChanged: (v) => setState(() => options[index]['isCorrect'] = v ?? false)), const Text('Correct', style: TextStyle(fontSize: 13))]),
                    if (options.length > 3) IconButton(icon: Icon(Icons.remove_circle_outline, color: AppColors.danger), onPressed: () => _removeImageSelectOption(index)),
                  ]),
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(controller: textControllers[index], decoration: _fieldDeco(c, 'e.g. "Red"'), validator: (v) => v?.isEmpty ?? true ? 'Required' : null),
                  const SizedBox(height: AppSpacing.sm),
                  Row(children: [
                    Expanded(child: Container(height: 100, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(AppRadii.sm), border: Border.all(color: AppColors.divider)), child: pickedImages[index] != null ? ClipRRect(borderRadius: BorderRadius.circular(AppRadii.sm), child: Image.network(pickedImages[index]!['displayUrl'] ?? pickedImages[index]!['imageUrl'], fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 40))) : imageControllers[index].text.trim().isNotEmpty ? ClipRRect(borderRadius: BorderRadius.circular(AppRadii.sm), child: Image.network(imageControllers[index].text.trim(), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 40))) : Center(child: Text('No image', style: TextStyle(color: Colors.grey[500]))))),
                    const SizedBox(width: AppSpacing.sm),
                    ElevatedButton.icon(
                      onPressed: () async { final s = await showDialog(context: context, builder: (_) => SelectImageDialog(singleSelect: false)); if (s != null) setState(() { pickedImages[index] = s as Map<String, dynamic>; imageControllers[index].text = s['name'] ?? 'Selected'; }); },
                      icon: const Icon(Icons.image, size: 18), label: const Text('Select'), style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[200], foregroundColor: Colors.black87),
                    ),
                  ]),
                ]),
              )),
            ],

            if (selectedType == 'image_select_reverse') ...[
              _sectionHeader(context, 'Image'),
              const SizedBox(height: AppSpacing.sm),
              Row(children: [
                Expanded(child: Container(height: 120, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(AppRadii.md), border: Border.all(color: AppColors.divider)), child: reversePickedImage != null ? ClipRRect(borderRadius: BorderRadius.circular(AppRadii.md), child: Image.network(reversePickedImage!['displayUrl'] ?? reversePickedImage!['imageUrl'], fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 40))) : imageUrlController.text.trim().isNotEmpty ? ClipRRect(borderRadius: BorderRadius.circular(AppRadii.md), child: Image.network(imageUrlController.text.trim(), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 40))) : const Center(child: Text('No image', style: TextStyle(color: Colors.grey))))),
                const SizedBox(width: AppSpacing.md),
                ElevatedButton.icon(onPressed: () async { final s = await showDialog(context: context, builder: (_) => SelectImageDialog(singleSelect: true)); if (s != null) setState(() { reversePickedImage = s as Map<String, dynamic>; imageUrlController.text = s['name'] ?? 'Selected'; }); }, icon: const Icon(Icons.image, size: 20), label: const Text('Select'), style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[200], foregroundColor: Colors.black87)),
              ]),
              const SizedBox(height: AppSpacing.md),
              _sectionHeader(context, 'Text Options (3–4)', onAdd: reverseOptions.length < 4 ? _addReverseOption : null),
              const SizedBox(height: AppSpacing.md),
              ...List.generate(reverseOptions.length, (index) => Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.md), padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(border: Border.all(color: AppColors.divider), borderRadius: BorderRadius.circular(AppRadii.md), color: Colors.white),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Text('Option ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)), const Spacer(), Row(children: [Checkbox(value: reverseOptions[index]['isCorrect'], activeColor: c, onChanged: (v) => setState(() => reverseOptions[index]['isCorrect'] = v ?? false)), const Text('Correct', style: TextStyle(fontSize: 13))]), if (reverseOptions.length > 3) IconButton(icon: Icon(Icons.delete_outline, color: AppColors.danger), onPressed: () => _removeReverseOption(index))]),
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(controller: reverseOptionControllers[index], decoration: _fieldDeco(c, 'e.g. "Stand up"'), validator: (v) => v?.isEmpty ?? true ? 'Required' : null),
                ]),
              )),
            ],

            if (selectedType == 'complete_the_chat') ...[
              _sectionHeader(context, 'Conversation turns  ${chatTurns.length} turn${chatTurns.length != 1 ? 's' : ''}', onAdd: chatTurns.length < 6 ? _addChatTurn : null),
              const SizedBox(height: AppSpacing.sm),
              Container(margin: const EdgeInsets.only(bottom: AppSpacing.md), padding: const EdgeInsets.all(AppSpacing.sm + 2), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(AppRadii.sm), border: Border.all(color: Colors.blue.shade100)), child: Row(children: [const Icon(Icons.chat_bubble_outline, color: Colors.blue, size: 16), const SizedBox(width: AppSpacing.sm), Expanded(child: Text('Each turn = one chat bubble the student must reply to. Turns play in order.', style: TextStyle(fontSize: 12, color: Colors.blue.shade700)))])),
              ...List.generate(chatTurns.length, (i) => _buildChatTurnCard(i)),
            ],

            if (selectedType == 'fill_blank') ...[
              const SizedBox(height: AppSpacing.sm),
              _sectionHeader(context, 'Options  $_assignedCorrectCount correct · ${fillBlankOptions.where((o) => !o['isCorrect']).length} distractors', onAdd: _addFillBlankOption),
              const SizedBox(height: AppSpacing.md),
              ...List.generate(fillBlankOptions.length, (i) => _buildFillBlankOptionCard(i)),
            ],

            if (selectedType == 'arrange') ...[
              _sectionHeader(context, 'Sentence'),
              const SizedBox(height: AppSpacing.md),
              _buildArrangeEditor(),
            ],

            if (selectedType == 'match') ...[
              _sectionHeader(context, 'Pairs'),
              const SizedBox(height: AppSpacing.md),
              _buildMatchEditor(),
            ],

            if (selectedType == 'reading') ...[
              _buildReadingEditor(),
            ],

            const SizedBox(height: AppSpacing.lg),

            // ── Submit ────────────────────────────────────────────────────
            SizedBox(
              width: double.infinity, height: 54,
              child: ElevatedButton(
                onPressed: isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: c,
                  foregroundColor: AppColors.onPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md)),
                ),
                child: isLoading
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: AppColors.onPrimary, strokeWidth: 2))
                    : Text(widget.taskId != null ? 'Update' : 'Create', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── local helpers ─────────────────────────────────────────────────────────

  InputDecoration _fieldDeco(Color c, String hint) => InputDecoration(
    hintText: hint,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md), borderSide: BorderSide(color: c.withOpacity(0.3))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md), borderSide: BorderSide(color: c, width: 2)),
    filled: true, fillColor: Colors.white,
  );

  Widget _labelRow(String text) => Row(children: [
    Icon(Icons.label_outline, size: 14, color: widget.groupColor),
    const SizedBox(width: AppSpacing.xs + 2),
    Text(text.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: widget.groupColor, letterSpacing: 1.1)),
  ]);

  Widget _sectionHeader(BuildContext context, String title, {VoidCallback? onAdd}) => Row(children: [
    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    const Spacer(),
    if (onAdd != null) IconButton(icon: Icon(Icons.add_circle_rounded, color: widget.groupColor, size: 26), onPressed: onAdd, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
  ]);
}