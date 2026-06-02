import 'package:flutter/material.dart';
import 'package:loringo_app/components/image_dialog.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/utils/image_service.dart';

class CreatePersonalizedTaskScreen extends StatefulWidget {
  final String groupId;
  final String contentId;
  final String unitId;
  final String lessonId;
  final String activityId;
  final Color groupColor;
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

class _CreatePersonalizedTaskScreenState
    extends State<CreatePersonalizedTaskScreen> {
  final _formKey  = GlobalKey<FormState>();
  final Database db = Database();
  final imageService = ImageService();

  late TextEditingController orderController;
  late TextEditingController questionController;

  String selectedType = 'image_select';
  bool   isLoading    = false;

  static const Map<String, String> _defaultQuestions = {
    'image_select':         'Which of these is ___?',
    'image_select_reverse': 'Select the correct phrase',
    'complete_the_chat':    'Speaking about colours',
    'arrange':              'Arrange the words to form a sentence',
    'match':                'Match the words',
    'reading':              'Reading Comprehension',
  };

  String _defaultFor(String type) {
    if (type == 'reading') return '';
    return _defaultQuestions[type] ?? '';
  }

  // ── image_select ──────────────────────────────────────────────────────────
  List<Map<String, dynamic>> options = [
    {'text': '', 'image': '', 'isCorrect': false},
    {'text': '', 'image': '', 'isCorrect': false},
    {'text': '', 'image': '', 'isCorrect': false},
  ];
  List<TextEditingController> textControllers  = [];
  List<TextEditingController> imageControllers = [];
  List<Map<String, dynamic>?> pickedImages     = [null, null, null];
  Map<String, dynamic>? reversePickedImage;

  // ── complete_the_chat ─────────────────────────────────────────────────────
  List<_ChatTurn> chatTurns = [];

  // ── arrange ───────────────────────────────────────────────────────────────
  late TextEditingController arrangeController;

  // ── fill_blank ────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> questionSegments = [];
  List<Map<String, dynamic>> fillBlankOptions = [
    {'text': '', 'isCorrect': false, 'blankIndex': null},
    {'text': '', 'isCorrect': false, 'blankIndex': null},
    {'text': '', 'isCorrect': false, 'blankIndex': null},
  ];
  List<TextEditingController> fillBlankControllers = [];

  // ── image_select_reverse ──────────────────────────────────────────────────
  late TextEditingController imageUrlController;
  List<Map<String, dynamic>> reverseOptions = [
    {'text': '', 'isCorrect': false},
    {'text': '', 'isCorrect': false},
    {'text': '', 'isCorrect': false},
  ];
  List<TextEditingController> reverseOptionControllers = [];

  // ── match ─────────────────────────────────────────────────────────────────
  String _matchMode = 'text';
  List<_MatchPair> matchPairs = [];

  // ── reading ───────────────────────────────────────────────────────────────
  List<TextEditingController> pageControllers = [];
  int _currentPageEditorIndex = 0;
  static const int _warnWordsPerPage = 300;
  List<_ReadingQuestion> readingQuestions = [];

  final List<String> taskTypes = [
    'image_select',
    'image_select_reverse',
    'complete_the_chat',
    'fill_blank',
    'arrange',
    'match',
    'reading',
  ];

  String _getDisplayName(String t) {
    switch (t) {
      case 'image_select':         return 'Image Select';
      case 'image_select_reverse': return 'Image Select Reverse';
      case 'complete_the_chat':    return 'Complete the Chat';
      case 'fill_blank':           return 'Fill in the Blank';
      case 'arrange':              return 'Sentence Arrange';
      case 'match':                return 'Match';
      case 'reading':              return 'Reading Comprehension';
      default:                     return t;
    }
  }

  // ── fill_blank helpers ────────────────────────────────────────────────────
  int get _blankCount =>
      questionSegments.where((s) => s['type'] == 'blank').length;
  Set<int> get _assignedBlankIndices => fillBlankOptions
      .where((o) => o['isCorrect'] == true && o['blankIndex'] != null)
      .map((o) => o['blankIndex'] as int)
      .toSet();
  int get _assignedCorrectCount => _assignedBlankIndices.length;

  // ── arrange helpers ───────────────────────────────────────────────────────
  List<String> get _arrangeTiles =>
      arrangeController.text.trim()
          .split(' ')
          .where((w) => w.isNotEmpty)
          .toList();

  // ── reading helpers ───────────────────────────────────────────────────────
  int _wordCount(String text) =>
      text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  void _addPage() {
    if (pageControllers.length < 5) {
      setState(() {
        pageControllers.add(TextEditingController());
        _currentPageEditorIndex = pageControllers.length - 1;
      });
    }
  }

  void _removePage() {
    if (pageControllers.length > 1) {
      setState(() {
        pageControllers[_currentPageEditorIndex].dispose();
        pageControllers.removeAt(_currentPageEditorIndex);
        if (_currentPageEditorIndex >= pageControllers.length) {
          _currentPageEditorIndex = pageControllers.length - 1;
        }
      });
    }
  }

  // ── initState ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    // Normalise: any unknown/legacy type falls back to 'image_select'
    final rawType = widget.existingData?['type'] as String? ?? 'image_select';
    selectedType  = taskTypes.contains(rawType) ? rawType : 'image_select';

    final existingQuestion = widget.existingData?['question'] as String? ?? '';
    final defaultQuestion  =
        widget.existingData == null ? _defaultFor(selectedType) : '';
    questionController = TextEditingController(
        text: existingQuestion.isNotEmpty ? existingQuestion : defaultQuestion);

    orderController = TextEditingController(
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
    }
  }

  void _initSegments() {
    questionSegments = [
      {'type': 'text', 'value': '', 'controller': TextEditingController()},
    ];
  }

  // ── Load existing data ────────────────────────────────────────────────────
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
        textControllers.clear();
        imageControllers.clear();
        pickedImages.clear();
        for (final opt in opts) {
          final o = opt as Map<String, dynamic>;
          options.add({'text': o['text'] ?? '', 'image': o['image'] ?? '', 'isCorrect': o['isCorrect'] ?? false});
          textControllers.add(TextEditingController(text: o['text'] ?? ''));
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
      final q = data['question'] as String? ?? '';
      _loadSegmentsFromString(q);
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
          final t = turn as Map<String, dynamic>;
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

  // ── Segment operations ────────────────────────────────────────────────────
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
        if (idx == blankOrdinal) {
          fillBlankOptions[i]['isCorrect'] = false;
          fillBlankOptions[i]['blankIndex'] = null;
        } else if (idx != null && idx > blankOrdinal) {
          fillBlankOptions[i]['blankIndex'] = idx - 1;
        }
      }
      questionSegments.removeAt(segIndex);
      if (segIndex > 0 &&
          segIndex < questionSegments.length &&
          questionSegments[segIndex - 1]['type'] == 'text' &&
          questionSegments[segIndex]['type'] == 'text') {
        final l = questionSegments[segIndex - 1]['controller'] as TextEditingController;
        final r = questionSegments[segIndex]['controller'] as TextEditingController;
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
  void _addMatchPair() {
    if (matchPairs.length < 5) setState(() => matchPairs.add(_MatchPair()));
  }

  void _removeMatchPair(int index) {
    if (matchPairs.length > 3) {
      setState(() {
        matchPairs[index].dispose();
        matchPairs.removeAt(index);
      });
    }
  }

  // ── complete_the_chat operations ──────────────────────────────────────────
  void _addChatTurn() {
    if (chatTurns.length < 6) {
      setState(() {
        for (final t in chatTurns) t.expanded = false;
        chatTurns.add(_ChatTurn());
      });
    }
  }

  void _removeChatTurn(int index) {
    if (chatTurns.length > 1) {
      setState(() { chatTurns[index].dispose(); chatTurns.removeAt(index); });
    }
  }

  void _addChatOption(int turnIndex) {
    if (chatTurns[turnIndex].options.length < 4) {
      setState(() {
        chatTurns[turnIndex].options.add({'text': '', 'isCorrect': false});
        chatTurns[turnIndex].optionCtrl.add(TextEditingController());
      });
    }
  }

  void _removeChatOption(int turnIndex, int optIndex) {
    if (chatTurns[turnIndex].options.length > 3) {
      setState(() {
        chatTurns[turnIndex].options.removeAt(optIndex);
        chatTurns[turnIndex].optionCtrl[optIndex].dispose();
        chatTurns[turnIndex].optionCtrl.removeAt(optIndex);
      });
    }
  }

  // ── fill_blank operations ─────────────────────────────────────────────────
  void _addFillBlankOption() {
    if (fillBlankOptions.length < (_blankCount + 4).clamp(4, 8)) {
      setState(() {
        fillBlankOptions.add({'text': '', 'isCorrect': false, 'blankIndex': null});
        fillBlankControllers.add(TextEditingController());
      });
    }
  }

  void _removeFillBlankOption(int index) {
    if (fillBlankOptions.length > (_blankCount + 1).clamp(3, 99)) {
      setState(() {
        fillBlankOptions.removeAt(index);
        fillBlankControllers[index].dispose();
        fillBlankControllers.removeAt(index);
      });
    }
  }

  // ── image_select operations ───────────────────────────────────────────────
  void _addImageSelectOption() {
    if (options.length < 4) {
      setState(() {
        options.add({'text': '', 'image': '', 'isCorrect': false});
        textControllers.add(TextEditingController());
        imageControllers.add(TextEditingController());
        pickedImages.add(null);
      });
    }
  }

  void _removeImageSelectOption(int index) {
    if (options.length > 3) {
      setState(() {
        options.removeAt(index);
        textControllers[index].dispose();  textControllers.removeAt(index);
        imageControllers[index].dispose(); imageControllers.removeAt(index);
        pickedImages.removeAt(index);
      });
    }
  }

  // ── image_select_reverse operations ──────────────────────────────────────
  void _addReverseOption() {
    if (reverseOptions.length < 4) {
      setState(() {
        reverseOptions.add({'text': '', 'isCorrect': false});
        reverseOptionControllers.add(TextEditingController());
      });
    }
  }

  void _removeReverseOption(int index) {
    if (reverseOptions.length > 3) {
      setState(() {
        reverseOptions.removeAt(index);
        reverseOptionControllers[index].dispose();
        reverseOptionControllers.removeAt(index);
      });
    }
  }

  // ── dispose ───────────────────────────────────────────────────────────────
  @override
  void dispose() {
    questionController.dispose();
    orderController.dispose();
    arrangeController.dispose();
    for (var c in textControllers)          c.dispose();
    for (var c in imageControllers)         c.dispose();
    for (var c in fillBlankControllers)     c.dispose();
    imageUrlController.dispose();
    for (var c in reverseOptionControllers) c.dispose();
    for (final seg in questionSegments) {
      if (seg['type'] == 'text') (seg['controller'] as TextEditingController).dispose();
    }
    for (final t in chatTurns)  t.dispose();
    for (final p in matchPairs) p.dispose();
    for (final c in pageControllers)   c.dispose();
    for (final q in readingQuestions)  q.dispose();
    super.dispose();
  }

  bool _areOptionsEqual(
      List<Map<String, dynamic>> a, List<Map<String, dynamic>> b) {
    if (a.length != b.length) return false;
    final sort = (List<Map<String, dynamic>> list) =>
        List.from(list)
          ..sort((x, y) => (x['text'] as String).compareTo(y['text'] as String));
    final aSorted = sort(a);
    final bSorted = sort(b);
    for (int i = 0; i < aSorted.length; i++) {
      if (aSorted[i]['text']      != bSorted[i]['text'])      return false;
      if (aSorted[i]['isCorrect'] != bSorted[i]['isCorrect']) return false;
      if (aSorted[i]['image']     != bSorted[i]['image'])     return false;
    }
    return true;
  }

  // ── submit ────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);
    try {
      final taskId = widget.taskId ?? 'task_${DateTime.now().millisecondsSinceEpoch}';
      final questionText = selectedType == 'fill_blank'
          ? _buildQuestionString()
          : questionController.text.trim();

      // ── STEP 1: Validate ──────────────────────────────────────────────────
      if (selectedType == 'image_select') {
        bool hasCorrect = false;
        for (int i = 0; i < options.length; i++) {
          final hasImage = pickedImages[i] != null || imageControllers[i].text.trim().isNotEmpty;
          if (textControllers[i].text.trim().isEmpty || !hasImage) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Option ${i + 1} must have text and image')));
            setState(() => isLoading = false); return;
          }
          if (options[i]['isCorrect'] == true) hasCorrect = true;
        }
        if (!hasCorrect) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please mark at least one option as correct')));
          setState(() => isLoading = false); return;
        }
      } else if (selectedType == 'image_select_reverse') {
        final hasImage = reversePickedImage != null || imageUrlController.text.trim().isNotEmpty;
        if (!hasImage) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Image is required')));
          setState(() => isLoading = false); return;
        }
        bool hasCorrect = false; int filled = 0;
        for (int i = 0; i < reverseOptions.length; i++) {
          if (reverseOptionControllers[i].text.isNotEmpty) filled++;
          if (reverseOptions[i]['isCorrect'] == true) hasCorrect = true;
        }
        if (filled < 3) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You must provide at least 3 options')));
          setState(() => isLoading = false); return;
        }
        if (!hasCorrect) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please mark at least one option as correct')));
          setState(() => isLoading = false); return;
        }
      } else if (selectedType == 'complete_the_chat') {
        for (int t = 0; t < chatTurns.length; t++) {
          final turn = chatTurns[t];
          if (turn.bubbleCtrl.text.trim().isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Turn ${t + 1}: chat message cannot be empty')));
            setState(() => isLoading = false); return;
          }
          bool hasCorrect = false; int filled = 0;
          for (int o = 0; o < turn.options.length; o++) {
            if (turn.optionCtrl[o].text.isNotEmpty) filled++;
            if (turn.options[o]['isCorrect'] == true) hasCorrect = true;
          }
          if (filled < 3) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Turn ${t + 1}: provide at least 3 reply options'))); setState(() => isLoading = false); return; }
          if (!hasCorrect) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Turn ${t + 1}: mark one reply as correct'))); setState(() => isLoading = false); return; }
        }
      } else if (selectedType == 'fill_blank') {
        final blanks = _blankCount;
        if (blanks == 0) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one blank'))); setState(() => isLoading = false); return; }
        for (int b = 0; b < blanks; b++) {
          if (fillBlankOptions.where((o) => o['isCorrect'] == true && o['blankIndex'] == b).isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Blank ${b + 1} has no correct answer'))); setState(() => isLoading = false); return;
          }
        }
        if (fillBlankOptions.where((o) => o['isCorrect'] == false && fillBlankControllers[fillBlankOptions.indexOf(o)].text.isNotEmpty).isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one distractor'))); setState(() => isLoading = false); return;
        }
      } else if (selectedType == 'arrange') {
        if (_arrangeTiles.length < 3) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sentence must have at least 3 words'))); setState(() => isLoading = false); return; }
      } else if (selectedType == 'match') {
        for (int i = 0; i < matchPairs.length; i++) {
          if (matchPairs[i].englishCtrl.text.trim().isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pair ${i + 1}: English word is required'))); setState(() => isLoading = false); return;
          }
          if (_matchMode == 'text' && matchPairs[i].translatedCtrl.text.trim().isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pair ${i + 1}: translation is required'))); setState(() => isLoading = false); return;
          }
          if (_matchMode == 'image' && matchPairs[i].resolvedImageUrl.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pair ${i + 1}: image is required'))); setState(() => isLoading = false); return;
          }
        }
      } else if (selectedType == 'reading') {
        final pages = pageControllers.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
        if (pages.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reading passage cannot be empty'))); setState(() => isLoading = false); return; }
        if (readingQuestions.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one comprehension question'))); setState(() => isLoading = false); return; }
        for (int i = 0; i < readingQuestions.length; i++) {
          final rq = readingQuestions[i];
          if (rq.questionCtrl.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Question ${i + 1}: text cannot be empty'))); setState(() => isLoading = false); return; }
          if (!rq.options.any((o) => o['isCorrect'] == true)) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Question ${i + 1}: mark at least one correct answer'))); setState(() => isLoading = false); return; }
          if (rq.optionCtrls.where((c) => c.text.isNotEmpty).length < 3) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Question ${i + 1}: provide at least 3 options'))); setState(() => isLoading = false); return; }
        }
      }

      // ── STEP 2: Build data ────────────────────────────────────────────────
      Map<String, dynamic> data = {};

      if (selectedType == 'image_select') {
        data = {
          'word': questionText,
          'options': List.generate(options.length, (i) => {
            'text':      textControllers[i].text.trim(),
            'image':     pickedImages[i] != null ? (pickedImages[i]!['imageUrl'] as String? ?? '') : imageControllers[i].text.trim(),
            'isCorrect': options[i]['isCorrect'] ?? false,
          }),
        };
      } else if (selectedType == 'image_select_reverse') {
        data = {
          'image':    reversePickedImage != null ? (reversePickedImage!['imageUrl'] as String? ?? '') : imageUrlController.text.trim(),
          'question': questionText,
          'options':  List.generate(reverseOptions.length, (i) => {
            'text':      reverseOptionControllers[i].text.trim(),
            'isCorrect': reverseOptions[i]['isCorrect'] ?? false,
          }),
        };
      } else if (selectedType == 'complete_the_chat') {
        data = {
          'turns': chatTurns.map((turn) {
            for (int o = 0; o < turn.options.length; o++) {
              turn.options[o]['text'] = turn.optionCtrl[o].text.trim();
            }
            return {'bubble': turn.bubbleCtrl.text.trim(), 'options': List<Map<String, dynamic>>.from(turn.options)};
          }).toList(),
        };
      } else if (selectedType == 'fill_blank') {
        for (int i = 0; i < fillBlankOptions.length; i++) {
          fillBlankOptions[i]['text'] = fillBlankControllers[i].text.trim();
        }
        data = {'question': questionText, 'options': List<Map<String, dynamic>>.from(fillBlankOptions)};
      } else if (selectedType == 'arrange') {
        data = {'question': questionText, 'answer': _arrangeTiles};
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
        final pages = pageControllers.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
        data = {
          'pages': pages,
          'questions': readingQuestions.map((rq) {
            for (int o = 0; o < rq.options.length; o++) rq.options[o]['text'] = rq.optionCtrls[o].text.trim();
            return {'text': rq.questionCtrl.text.trim(), 'options': List<Map<String, dynamic>>.from(rq.options)};
          }).toList(),
        };
      }

      // ── STEP 3: Dirty-check (edit only) ───────────────────────────────────
      if (widget.taskId != null) {
        final orig     = widget.existingData!;
        final origData = orig['data'] as Map<String, dynamic>? ?? {};
        bool noChanges = false;

        if (selectedType != (orig['type'] as String? ?? '')) {
          noChanges = false;
        } else if (selectedType != 'fill_blank' && questionText != (orig['question'] as String? ?? '')) {
          noChanges = false;
        } else if (orderController.text.trim() != (orig['order']?.toString() ?? '')) {
          noChanges = false;
        } else {
          switch (selectedType) {
            case 'image_select':
              final origOpts = List<Map<String, dynamic>>.from(origData['options'] as List? ?? []);
              final newOpts  = List<Map<String, dynamic>>.from(data['options'] as List);
              noChanges = _areOptionsEqual(newOpts, origOpts) && questionText == (origData['word'] ?? '');
              break;

            case 'image_select_reverse':
              final origOpts = List<Map<String, dynamic>>.from(origData['options'] as List? ?? []);
              final newOpts  = List<Map<String, dynamic>>.from(data['options'] as List);
              bool equal = origOpts.length == newOpts.length;
              if (equal) {
                for (int i = 0; i < origOpts.length; i++) {
                  if (origOpts[i]['text'] != newOpts[i]['text'] || origOpts[i]['isCorrect'] != newOpts[i]['isCorrect']) { equal = false; break; }
                }
              }
              noChanges = equal && (data['image'] as String) == (origData['image'] as String? ?? '') && questionText == (orig['question'] as String? ?? '');
              break;

            case 'complete_the_chat':
              final origTurns = origData['turns'] as List? ?? [];
              final newTurns  = data['turns'] as List;
              if (origTurns.length == newTurns.length) {
                noChanges = true;
                for (int i = 0; i < origTurns.length; i++) {
                  final origTurn = origTurns[i] as Map;
                  final newTurn  = newTurns[i]  as Map;
                  if (origTurn['bubble'] != newTurn['bubble']) { noChanges = false; break; }
                  if (!_areOptionsEqual(List<Map<String, dynamic>>.from(origTurn['options'] ?? []), List<Map<String, dynamic>>.from(newTurn['options'] ?? []))) { noChanges = false; break; }
                }
              } else { noChanges = false; }
              break;

            case 'fill_blank':
              final origOpts = List<Map<String, dynamic>>.from(origData['options'] as List? ?? []);
              final newOpts  = List<Map<String, dynamic>>.from(data['options'] as List);
              if (origOpts.length == newOpts.length) {
                noChanges = true;
                for (int i = 0; i < origOpts.length; i++) {
                  if (origOpts[i]['text'] != newOpts[i]['text'] || origOpts[i]['isCorrect'] != newOpts[i]['isCorrect'] || origOpts[i]['blankIndex'] != newOpts[i]['blankIndex']) { noChanges = false; break; }
                }
              } else { noChanges = false; }
              noChanges = noChanges && (data['question'] as String) == (origData['question'] as String? ?? '');
              break;

            case 'arrange':
              final origAnswer = List<String>.from(origData['answer'] ?? []);
              final newAnswer  = data['answer'] as List<String>;
              noChanges = origAnswer.join(' ') == newAnswer.join(' ') && questionText == (orig['question'] as String? ?? '');
              break;

            case 'match':
              final origMode  = origData['mode']  as String? ?? 'text';
              final origPairs = List<Map<String, dynamic>>.from(origData['pairs'] as List? ?? []);
              final newPairs  = List<Map<String, dynamic>>.from(data['pairs'] as List);
              if (_matchMode != origMode) {
                noChanges = false;
              } else if (origPairs.length == newPairs.length) {
                noChanges = true;
                for (int i = 0; i < origPairs.length; i++) {
                  if (origPairs[i]['english']    != newPairs[i]['english'] ||
                      origPairs[i]['translated'] != newPairs[i]['translated'] ||
                      origPairs[i]['image']      != newPairs[i]['image']) { noChanges = false; break; }
                }
              } else { noChanges = false; }
              noChanges = noChanges && questionText == (orig['question'] as String? ?? '');
              break;

            case 'reading':
              final origPages = List<String>.from(origData['pages'] as List? ?? []);
              final newPages  = data['pages'] as List<String>;
              final origQs    = origData['questions'] as List? ?? [];
              final newQs     = data['questions'] as List;
              noChanges = true;
              if (origPages.length != newPages.length) { noChanges = false; }
              else { for (int i = 0; i < origPages.length; i++) { if (origPages[i] != newPages[i]) { noChanges = false; break; } } }
              if (noChanges) {
                if (origQs.length == newQs.length) {
                  for (int i = 0; i < origQs.length; i++) {
                    final origQ = Map<String, dynamic>.from(origQs[i] as Map);
                    final newQ  = Map<String, dynamic>.from(newQs[i]  as Map);
                    if (origQ['text'] != newQ['text']) { noChanges = false; break; }
                    if (!_areOptionsEqual(List<Map<String, dynamic>>.from(origQ['options'] ?? []), List<Map<String, dynamic>>.from(newQ['options'] ?? []))) { noChanges = false; break; }
                  }
                } else { noChanges = false; }
              }
              noChanges = noChanges && questionText == (orig['question'] as String? ?? '');
              break;

            default:
              noChanges = false;
          }
        }

        if (noChanges) {
          setState(() => isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No changes made'), backgroundColor: Colors.grey));
          return;
        }

        await db.updatePersonalizedTask(
          groupId: widget.groupId, contentId: widget.contentId,
          unitId: widget.unitId, lessonId: widget.lessonId,
          activityId: widget.activityId, taskId: taskId,
          type: selectedType, question: questionText,
          order: int.parse(orderController.text.trim()), data: data,
        );
      } else {
        await db.createPersonalizedTask(
          groupId: widget.groupId, contentId: widget.contentId,
          unitId: widget.unitId, lessonId: widget.lessonId,
          activityId: widget.activityId, taskId: taskId,
          type: selectedType, question: questionText,
          order: int.parse(orderController.text.trim()), data: data,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.taskId != null ? 'Changes saved' : 'Task created successfully!'),
          backgroundColor: Colors.green,
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => isLoading = false);
    }
  }

  // ── match editor ──────────────────────────────────────────────────────────
  Widget _buildMatchEditor() {
    final c = widget.groupColor;
    final isImage = _matchMode == 'image';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.withOpacity(0.07), borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.withOpacity(0.3)),
        ),
        child: const Row(children: [
          Icon(Icons.info_outline, size: 18, color: Color(0xFF4CAF50)),
          SizedBox(width: 8),
          Expanded(child: Text('Student taps one from each column to form a match. Minimum 3, maximum 5 pairs.', style: TextStyle(fontSize: 12, color: Color(0xFF2E7D32)))),
        ]),
      ),
      const SizedBox(height: 16),

      // Mode toggle
      Container(
        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
        child: Row(children: [
          Expanded(child: _modeToggleBtn('text',  'Text ↔ Translation', Icons.translate)),
          Expanded(child: _modeToggleBtn('image', 'Text ↔ Image',       Icons.image)),
        ]),
      ),
      const SizedBox(height: 16),

      // Column headers
      Row(children: [
        const SizedBox(width: 32),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(color: const Color(0xFF4CAF50).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.flag, size: 13, color: Color(0xFF4CAF50)),
              SizedBox(width: 4),
              Text('English', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: isImage ? Colors.purple.withOpacity(0.08) : Colors.orange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(isImage ? Icons.image_outlined : Icons.flag, size: 13, color: isImage ? Colors.purple : Colors.orange),
              const SizedBox(width: 4),
              Text(isImage ? 'Image' : 'Translation', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isImage ? Colors.purple : Colors.orange)),
            ]),
          ),
        ),
        const SizedBox(width: 34),
      ]),
      const SizedBox(height: 10),

      // Pairs
      ...List.generate(matchPairs.length, (index) {
        final pair = matchPairs[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 24, height: 24,
              margin: const EdgeInsets.only(right: 8, top: 10),
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
              child: Center(child: Text('${index + 1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
            ),
            Expanded(
              child: TextFormField(
                controller: pair.englishCtrl,
                decoration: InputDecoration(
                  hintText: 'e.g. "Red"',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c, width: 2)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  filled: true, fillColor: Colors.white,
                ),
                style: const TextStyle(fontSize: 14),
                validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              child: Icon(Icons.swap_horiz, color: Colors.grey.shade400, size: 20),
            ),
            Expanded(
              child: isImage
                  ? _buildImagePickerField(pair)
                  : TextFormField(
                      controller: pair.translatedCtrl,
                      decoration: InputDecoration(
                        hintText: 'e.g. "Rojo"',
                        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.orange, width: 2)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        filled: true, fillColor: Colors.white,
                      ),
                      style: const TextStyle(fontSize: 14),
                      validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
                    ),
            ),
            if (matchPairs.length > 3)
              GestureDetector(
                onTap: () => _removeMatchPair(index),
                child: Container(
                  margin: const EdgeInsets.only(left: 6, top: 8),
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle, border: Border.all(color: Colors.red.shade200)),
                  child: Icon(Icons.close, size: 14, color: Colors.red.shade400),
                ),
              )
            else
              const SizedBox(width: 34),
          ]),
        );
      }),

      if (matchPairs.length < 5)
        TextButton.icon(
          onPressed: _addMatchPair,
          icon: const Icon(Icons.add, color: Color(0xFF4CAF50), size: 18),
          label: Text('Add pair (${matchPairs.length}/5)', style: const TextStyle(color: Color(0xFF4CAF50), fontWeight: FontWeight.w600)),
        ),
    ]);
  }

  Widget _modeToggleBtn(String mode, String label, IconData icon) {
    final isActive = _matchMode == mode;
    final c = widget.groupColor;
    return GestureDetector(
      onTap: () => setState(() => _matchMode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: isActive ? c : Colors.transparent, borderRadius: BorderRadius.circular(9)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 16, color: isActive ? Colors.white : Colors.grey.shade500),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isActive ? Colors.white : Colors.grey.shade600)),
        ]),
      ),
    );
  }

  Widget _buildImagePickerField(_MatchPair pair) {
    final hasImage = pair.pickedImage != null || pair.imageUrlCtrl.text.trim().isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        height: 80,
        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
        child: hasImage
            ? ClipRRect(borderRadius: BorderRadius.circular(9), child: Image.network(pair.resolvedImageUrl, fit: BoxFit.cover, width: double.infinity, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 28)))
            : Center(child: Text('No image', style: TextStyle(fontSize: 12, color: Colors.grey.shade500))),
      ),
      const SizedBox(height: 6),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () async {
            final selected = await showDialog(context: context, builder: (_) => SelectImageDialog(singleSelect: true));
            if (selected != null) {
              setState(() {
                pair.pickedImage = selected as Map<String, dynamic>;
                pair.imageUrlCtrl.text = selected['imageUrl'] as String? ?? '';
              });
            }
          },
          icon: const Icon(Icons.image, size: 16),
          label: Text(hasImage ? 'Change' : 'Select Image', style: const TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade200, foregroundColor: Colors.black87, padding: const EdgeInsets.symmetric(vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        ),
      ),
    ]);
  }

  // ── fill_blank segment editor ─────────────────────────────────────────────
  Widget _buildSegmentEditor() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Question', style: TextStyle(fontSize: 14, color: Colors.black54)),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300, width: 1.5)),
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (int i = 0; i < questionSegments.length; i++) ...[
            if (questionSegments[i]['type'] == 'text') _buildTextSegment(i) else _buildBlankChip(i),
          ],
          const SizedBox(height: 8),
          if (questionSegments.isEmpty || questionSegments.last['type'] != 'blank')
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _insertBlankAfter(questionSegments.length - 1),
                icon: const Icon(Icons.add_box_outlined, color: Color(0xFF4CAF50), size: 20),
                label: const Text('Add blank here', style: TextStyle(color: Color(0xFF4CAF50), fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
              ),
            ),
        ]),
      ),
      if (_blankCount > 0) ...[
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: const Color(0xFF4CAF50).withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.4))),
          child: Text('$_blankCount blank${_blankCount > 1 ? 's' : ''} added — assign each one below', style: const TextStyle(fontSize: 12, color: Color(0xFF2E7D32), fontWeight: FontWeight.w500)),
        ),
      ],
    ]);
  }

  Widget _buildTextSegment(int segIndex) {
    final ctrl = questionSegments[segIndex]['controller'] as TextEditingController;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(
          hintText: segIndex == 0 ? 'e.g. "Roses are"' : 'e.g. "and Violets are"',
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          filled: true, fillColor: Colors.grey.shade50,
          suffixIcon: _canInsertBlankAfter(segIndex)
              ? Tooltip(message: 'Insert blank', child: IconButton(icon: const Icon(Icons.add_box_outlined, color: Color(0xFF4CAF50), size: 20), onPressed: () => _insertBlankAfter(segIndex)))
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

  Widget _buildBlankChip(int segIndex) {
    final blankOrdinal = _blankOrdinalAt(segIndex);
    final isAssigned   = _assignedBlankIndices.contains(blankOrdinal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isAssigned ? const Color(0xFF4CAF50).withOpacity(0.12) : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isAssigned ? const Color(0xFF4CAF50) : Colors.grey.shade400, width: isAssigned ? 2 : 1.5),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(isAssigned ? Icons.check_circle : Icons.help_outline, size: 16, color: isAssigned ? const Color(0xFF4CAF50) : Colors.grey.shade500),
            const SizedBox(width: 6),
            Text('Blank ${blankOrdinal + 1}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: isAssigned ? const Color(0xFF2E7D32) : Colors.grey.shade600)),
          ]),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => _removeBlank(segIndex),
          child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle, border: Border.all(color: Colors.red.shade200)), child: Icon(Icons.close, size: 14, color: Colors.red.shade400)),
        ),
      ]),
    );
  }

  Widget _buildFillBlankOptionCard(int index) {
    final blanks               = _blankCount;
    final opt                  = fillBlankOptions[index];
    final isCorrect            = opt['isCorrect'] as bool;
    final assignedBlankIndices = _assignedBlankIndices;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: isCorrect ? const Color(0xFF4CAF50) : Colors.grey.shade300, width: isCorrect ? 2 : 1),
        borderRadius: BorderRadius.circular(10),
        color: isCorrect ? const Color(0xFF4CAF50).withOpacity(0.05) : Colors.white,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Option ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const Spacer(),
          DropdownButton<int?>(
            value: isCorrect ? opt['blankIndex'] as int? : null,
            hint: Text('Distractor', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
            isDense: true, underline: const SizedBox.shrink(),
            items: [
              DropdownMenuItem<int?>(value: null, child: Text('Distractor', style: TextStyle(fontSize: 13, color: Colors.grey.shade600))),
              for (int b = 0; b < blanks; b++) ...[
                DropdownMenuItem<int?>(
                  value: b,
                  enabled: !(assignedBlankIndices.contains(b) && !(isCorrect && opt['blankIndex'] == b)),
                  child: Text(
                    (assignedBlankIndices.contains(b) && !(isCorrect && opt['blankIndex'] == b)) ? 'Blank ${b + 1} (ya asignado)' : 'Blank ${b + 1} answer',
                    style: TextStyle(fontSize: 13, color: (assignedBlankIndices.contains(b) && !(isCorrect && opt['blankIndex'] == b)) ? Colors.grey.shade400 : const Color(0xFF4CAF50)),
                  ),
                ),
              ],
            ],
            onChanged: (selected) {
              setState(() {
                if (selected == null) { fillBlankOptions[index]['isCorrect'] = false; fillBlankOptions[index]['blankIndex'] = null; }
                else { fillBlankOptions[index]['isCorrect'] = true; fillBlankOptions[index]['blankIndex'] = selected; }
              });
            },
          ),
          if (fillBlankOptions.length > (_blankCount + 1).clamp(3, 99))
            IconButton(icon: const Icon(Icons.remove_circle, color: Colors.red, size: 20), onPressed: () => _removeFillBlankOption(index), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
        ]),
        const SizedBox(height: 8),
        TextFormField(
          controller: fillBlankControllers[index],
          decoration: InputDecoration(
            labelText: isCorrect ? 'Answer for Blank ${(opt['blankIndex'] as int) + 1} (e.g., "red")' : 'Distractor word (e.g., "green")',
            border: const OutlineInputBorder(), filled: true, fillColor: Colors.grey.shade50,
          ),
          validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
        ),
      ]),
    );
  }

  Widget _buildArrangeEditor() {
    final tiles = _arrangeTiles;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.text_fields, size: 18, color: widget.groupColor), const SizedBox(width: 8), const Text('Sentence', style: TextStyle(fontWeight: FontWeight.bold))]),
          const SizedBox(height: 6),
          TextFormField(
            controller: arrangeController,
            decoration: InputDecoration(hintText: 'e.g., "The sky is blue today"', border: const OutlineInputBorder(), filled: true, fillColor: Colors.grey.shade50),
            maxLines: 2,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              if (v.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length < 3) return 'At least 3 words required';
              return null;
            },
          ),
        ]),
      ),
      const SizedBox(height: 16),
      if (tiles.isNotEmpty) ...[
        const Text('Tile preview (shown shuffled to student):', style: TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: tiles.map((word) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: widget.groupColor, width: 2), borderRadius: BorderRadius.circular(24)),
          child: Text(word, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        )).toList()),
      ],
    ]);
  }

  Widget _buildChatTurnCard(int turnIndex) {
    final turn       = chatTurns[turnIndex];
    final hasCorrect = turn.options.any((o) => o['isCorrect'] == true);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        border: Border.all(color: turn.expanded ? const Color(0xFF4CAF50) : Colors.grey.shade300, width: turn.expanded ? 2 : 1),
        borderRadius: BorderRadius.circular(12), color: Colors.white,
      ),
      child: Column(children: [
        GestureDetector(
          onTap: () => setState(() => turn.expanded = !turn.expanded),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: turn.expanded ? const Color(0xFF4CAF50).withOpacity(0.06) : Colors.grey.shade50, borderRadius: BorderRadius.circular(turn.expanded ? 10 : 12)),
            child: Row(children: [
              Container(width: 28, height: 28, decoration: const BoxDecoration(color: Color(0xFF4CAF50), shape: BoxShape.circle), child: Center(child: Text('${turnIndex + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)))),
              const SizedBox(width: 10),
              Expanded(child: Text(turn.bubbleCtrl.text.isNotEmpty ? turn.bubbleCtrl.text : 'Turn ${turnIndex + 1} — tap to edit', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: turn.bubbleCtrl.text.isNotEmpty ? Colors.black87 : Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (!turn.expanded) ...[
                if (hasCorrect) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: const Color(0xFF4CAF50).withOpacity(0.12), borderRadius: BorderRadius.circular(8)), child: const Text('✓ ready', style: TextStyle(fontSize: 11, color: Color(0xFF2E7D32)))),
                if (!hasCorrect) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.orange.withOpacity(0.12), borderRadius: BorderRadius.circular(8)), child: const Text('needs reply', style: TextStyle(fontSize: 11, color: Colors.orange))),
              ],
              const SizedBox(width: 8),
              Icon(turn.expanded ? Icons.expand_less : Icons.expand_more, color: Colors.grey),
              if (chatTurns.length > 1)
                GestureDetector(onTap: () => _removeChatTurn(turnIndex), child: Padding(padding: const EdgeInsets.only(left: 8), child: Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle, border: Border.all(color: Colors.red.shade200)), child: Icon(Icons.close, size: 13, color: Colors.red.shade400)))),
            ]),
          ),
        ),
        if (turn.expanded) Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Divider(height: 20),
            const Text('Chat bubble message', style: TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            TextFormField(controller: turn.bubbleCtrl, decoration: InputDecoration(hintText: 'e.g. "What colour is the sky?"', prefixIcon: const Icon(Icons.chat_bubble_outline, color: Color(0xFF4CAF50), size: 20), border: const OutlineInputBorder(), filled: true, fillColor: Colors.grey.shade50), maxLines: 2, onChanged: (_) => setState(() {}), validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null),
            const SizedBox(height: 14),
            Row(children: [
              const Text('Reply options (3-4)', style: TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w500)),
              const Spacer(),
              if (turn.options.length < 4) GestureDetector(onTap: () => _addChatOption(turnIndex), child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: const Color(0xFF4CAF50).withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add, size: 14, color: Color(0xFF4CAF50)), SizedBox(width: 4), Text('Add reply', style: TextStyle(fontSize: 12, color: Color(0xFF4CAF50), fontWeight: FontWeight.w600))]))),
            ]),
            const SizedBox(height: 8),
            ...List.generate(turn.options.length, (optIndex) {
              final isCorrect = turn.options[optIndex]['isCorrect'] as bool;
              return Container(
                margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                decoration: BoxDecoration(color: isCorrect ? const Color(0xFF4CAF50).withOpacity(0.05) : Colors.grey.shade50, border: Border.all(color: isCorrect ? const Color(0xFF4CAF50) : Colors.grey.shade300, width: isCorrect ? 1.5 : 1), borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  GestureDetector(onTap: () => setState(() => turn.options[optIndex]['isCorrect'] = !isCorrect), child: Container(width: 22, height: 22, decoration: BoxDecoration(shape: BoxShape.circle, color: isCorrect ? const Color(0xFF4CAF50) : Colors.white, border: Border.all(color: isCorrect ? const Color(0xFF4CAF50) : Colors.grey.shade400, width: 2)), child: isCorrect ? const Icon(Icons.check, size: 13, color: Colors.white) : null)),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: turn.optionCtrl[optIndex], decoration: InputDecoration(hintText: isCorrect ? 'Correct reply...' : 'Wrong reply...', hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400), border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero), style: const TextStyle(fontSize: 14))),
                  if (turn.options.length > 3) GestureDetector(onTap: () => _removeChatOption(turnIndex, optIndex), child: Icon(Icons.remove_circle_outline, size: 18, color: Colors.red.shade300)),
                ]),
              );
            }),
          ]),
        ),
      ]),
    );
  }

  Widget _buildReadingEditor() {
    final c           = widget.groupColor;
    final currentCtrl = pageControllers[_currentPageEditorIndex];
    final words       = _wordCount(currentCtrl.text);
    final isOverLimit = words > _warnWordsPerPage;
    final totalPages  = pageControllers.length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: c.withOpacity(0.07), borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withOpacity(0.3))), child: Row(children: [Icon(Icons.menu_book_rounded, color: c, size: 18), const SizedBox(width: 8), Expanded(child: Text('Write a short passage split across pages. Each page should be around 200–300 words for comfortable reading.', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)))])),
      const SizedBox(height: 20),
      Row(children: [
        const Text('Pages', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text('$totalPages/5', style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.bold))),
        const Spacer(),
        if (totalPages < 5) TextButton.icon(onPressed: _addPage, icon: Icon(Icons.add, size: 16, color: c), label: Text('Add Page', style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)), style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6))),
      ]),
      const SizedBox(height: 8),
      if (totalPages > 1)
        SizedBox(height: 36, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: totalPages, itemBuilder: (_, i) {
          final isActive = i == _currentPageEditorIndex;
          final pw       = _wordCount(pageControllers[i].text);
          final tooLong  = pw > _warnWordsPerPage;
          return GestureDetector(onTap: () => setState(() => _currentPageEditorIndex = i), child: Container(
            margin: const EdgeInsets.only(right: 6), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: isActive ? c : Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: tooLong ? Colors.orange : (isActive ? c : Colors.grey.shade300), width: isActive ? 0 : 1.5), boxShadow: isActive ? [BoxShadow(color: c.withOpacity(0.25), blurRadius: 6)] : null),
            child: Row(mainAxisSize: MainAxisSize.min, children: [Text('Page ${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isActive ? Colors.white : (tooLong ? Colors.orange : Colors.grey.shade700))), if (tooLong) ...[const SizedBox(width: 4), Icon(Icons.warning_amber_rounded, size: 12, color: isActive ? Colors.white70 : Colors.orange)]]),
          ));
        })),
      const SizedBox(height: 10),
      Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: isOverLimit ? Colors.orange : c.withOpacity(0.25), width: 1.5), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: isOverLimit ? Colors.orange.withOpacity(0.06) : c.withOpacity(0.05), borderRadius: const BorderRadius.vertical(top: Radius.circular(13)), border: Border(bottom: BorderSide(color: isOverLimit ? Colors.orange.withOpacity(0.2) : c.withOpacity(0.1)))),
            child: Row(children: [
              Icon(Icons.article_rounded, size: 16, color: isOverLimit ? Colors.orange : c),
              const SizedBox(width: 8),
              Text('Page ${_currentPageEditorIndex + 1} of $totalPages', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isOverLimit ? Colors.orange : c)),
              const Spacer(),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: isOverLimit ? Colors.orange.withOpacity(0.1) : c.withOpacity(0.08), borderRadius: BorderRadius.circular(8)), child: Text('$words / $_warnWordsPerPage words', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isOverLimit ? Colors.orange : c))),
              if (totalPages > 1) ...[const SizedBox(width: 8), GestureDetector(onTap: _removePage, child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle), child: Icon(Icons.close, size: 14, color: Colors.red.shade400)))],
            ]),
          ),
          TextFormField(controller: currentCtrl, maxLines: 10, onChanged: (_) => setState(() {}), decoration: InputDecoration(hintText: 'Write page ${_currentPageEditorIndex + 1} content here.\n\nKeep it simple for children aged 5–9.\nAim for 200–300 words per page.', hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13), border: InputBorder.none, contentPadding: const EdgeInsets.all(14)), style: const TextStyle(fontSize: 15, height: 1.6, color: Colors.black87), validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null),
          if (isOverLimit) Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(color: Colors.orange.withOpacity(0.08), borderRadius: const BorderRadius.vertical(bottom: Radius.circular(13)), border: Border(top: BorderSide(color: Colors.orange.withOpacity(0.2)))), child: Row(children: [const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange), const SizedBox(width: 6), Expanded(child: Text('${words - _warnWordsPerPage} words over the recommended limit. Consider splitting into an additional page.', style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w500))), TextButton(onPressed: totalPages < 5 ? _addPage : null, style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero), child: const Text('+ Split', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange)))])),
        ]),
      ),
      const SizedBox(height: 8),
      if (totalPages > 1) Center(child: Row(mainAxisSize: MainAxisSize.min, children: List.generate(totalPages, (i) => Container(width: i == _currentPageEditorIndex ? 20 : 7, height: 7, margin: const EdgeInsets.symmetric(horizontal: 3), decoration: BoxDecoration(color: i == _currentPageEditorIndex ? c : Colors.grey.shade300, borderRadius: BorderRadius.circular(4)))))),
      const SizedBox(height: 20),
      Row(children: [
        const Text('Questions', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text('${readingQuestions.length}/5', style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.bold))),
        const Spacer(),
        if (readingQuestions.length < 5) TextButton.icon(onPressed: () => setState(() => readingQuestions.add(_ReadingQuestion())), icon: Icon(Icons.add, size: 16, color: c), label: Text('Add Question', style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)), style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6))),
      ]),
      const SizedBox(height: 8),
      ...List.generate(readingQuestions.length, (qi) {
        final rq = readingQuestions[qi];
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2))]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: c.withOpacity(0.05), borderRadius: const BorderRadius.vertical(top: Radius.circular(11)), border: Border(bottom: BorderSide(color: c.withOpacity(0.1)))),
              child: Row(children: [
                Container(width: 26, height: 26, decoration: BoxDecoration(color: c, shape: BoxShape.circle), child: Center(child: Text('${qi + 1}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)))),
                const SizedBox(width: 8),
                Text('Question ${qi + 1}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: c)),
                const Spacer(),
                if (readingQuestions.length > 1) GestureDetector(onTap: () => setState(() { rq.dispose(); readingQuestions.removeAt(qi); }), child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle), child: Icon(Icons.close, size: 14, color: Colors.red.shade400))),
              ]),
            ),
            Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextFormField(controller: rq.questionCtrl, decoration: InputDecoration(hintText: 'e.g. "What does Tom do first?"', hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c, width: 2)), filled: true, fillColor: Colors.grey.shade50, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), prefixIcon: Icon(Icons.help_outline_rounded, color: Colors.grey.shade400, size: 18)), validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null),
              const SizedBox(height: 12),
              Row(children: [
                Text('Options', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                const Spacer(),
                if (rq.options.length < 4) GestureDetector(onTap: () => setState(() { rq.options.add({'text': '', 'isCorrect': false}); rq.optionCtrls.add(TextEditingController()); }), child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: c.withOpacity(0.08), borderRadius: BorderRadius.circular(8)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add, size: 13, color: c), const SizedBox(width: 3), Text('Add', style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600))]))),
              ]),
              const SizedBox(height: 8),
              ...List.generate(rq.options.length, (oi) {
                final isCorrect = rq.options[oi]['isCorrect'] as bool;
                final label     = String.fromCharCode(65 + oi);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(color: isCorrect ? Colors.green.shade50 : Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: isCorrect ? Colors.green : Colors.grey.shade200, width: isCorrect ? 2 : 1)),
                  child: Row(children: [
                    GestureDetector(onTap: () => setState(() => rq.options[oi]['isCorrect'] = !isCorrect), child: Container(width: 26, height: 26, decoration: BoxDecoration(shape: BoxShape.circle, color: isCorrect ? Colors.green : Colors.white, border: Border.all(color: isCorrect ? Colors.green : Colors.grey.shade400, width: 2)), child: Center(child: isCorrect ? const Icon(Icons.check, size: 14, color: Colors.white) : Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade500))))),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(controller: rq.optionCtrls[oi], decoration: InputDecoration(hintText: isCorrect ? 'Correct answer...' : 'Wrong answer...', hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12), border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero), style: TextStyle(fontSize: 13, color: isCorrect ? Colors.green.shade800 : Colors.black87))),
                    if (rq.options.length > 3) GestureDetector(onTap: () => setState(() { rq.options.removeAt(oi); rq.optionCtrls[oi].dispose(); rq.optionCtrls.removeAt(oi); }), child: Icon(Icons.remove_circle_outline, size: 16, color: Colors.red.shade300)),
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
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(title: Text(widget.taskId != null ? 'Edit Task' : 'Create Task'), backgroundColor: widget.groupColor, elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            DropdownButtonFormField<String>(
              value: selectedType,
              decoration: const InputDecoration(labelText: 'Task Type', border: OutlineInputBorder()),
              items: taskTypes.map((t) => DropdownMenuItem(value: t, child: Text(_getDisplayName(t)))).toList(),
              onChanged: (v) {
                setState(() {
                  selectedType = v!;
                  final currentText = questionController.text;
                  if (currentText.isEmpty || _defaultQuestions.values.contains(currentText)) {
                    questionController.text = _defaultFor(selectedType);
                  }
                });
              },
            ),
            const SizedBox(height: 20),

            // Question field
            if (selectedType == 'fill_blank')
              _buildSegmentEditor()
            else if (selectedType != 'arrange' && selectedType != 'match' && selectedType != 'reading')
              TextFormField(
                controller: questionController,
                decoration: InputDecoration(
                  labelText: selectedType == 'image_select' ? 'Question (e.g., "Which of these is red?")' : selectedType == 'image_select_reverse' ? 'Question (e.g., "Select the correct phrase")' : selectedType == 'complete_the_chat' ? 'Conversation title (e.g., "Speaking about colours")' : 'Question',
                  border: const OutlineInputBorder(),
                ),
                maxLines: selectedType == 'complete_the_chat' ? 1 : 3,
                validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
              ),

            if (selectedType == 'match') ...[
              TextFormField(controller: questionController, decoration: const InputDecoration(labelText: 'Title (e.g., "Match the colours")', border: OutlineInputBorder()), maxLines: 1, validator: (v) => v?.isEmpty ?? true ? 'Required' : null),
            ],

            const SizedBox(height: 16),

            if (selectedType == 'reading') ...[
              const Text('Reading Title', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextFormField(controller: questionController, decoration: InputDecoration(hintText: 'e.g. "Tom\'s Classroom Day"', border: const OutlineInputBorder(), filled: true, fillColor: Colors.white), validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null),
              const SizedBox(height: 16),
            ],

            TextFormField(controller: orderController, decoration: const InputDecoration(labelText: 'Order', border: OutlineInputBorder()), keyboardType: TextInputType.number, validator: (v) => v?.isEmpty ?? true ? 'Required' : null),
            const SizedBox(height: 16),

            // Type-specific editors
            if (selectedType == 'image_select') ...[
              const Divider(thickness: 2),
              Row(children: [const Text('Options (3-4 required)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const Spacer(), if (options.length < 4) IconButton(icon: const Icon(Icons.add_circle, color: Color(0xFF4CAF50)), onPressed: _addImageSelectOption)]),
              const SizedBox(height: 16),
              ...List.generate(options.length, (index) => Container(
                margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8), color: Colors.grey.shade50),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Text('Option ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), const Spacer(), Checkbox(value: options[index]['isCorrect'], activeColor: const Color(0xFF4CAF50), onChanged: (v) => setState(() => options[index]['isCorrect'] = v ?? false)), const Text('Correct'), if (options.length > 3) IconButton(icon: const Icon(Icons.remove_circle, color: Colors.red), onPressed: () => _removeImageSelectOption(index))]),
                  const SizedBox(height: 8),
                  TextFormField(controller: textControllers[index], decoration: const InputDecoration(labelText: 'Text (e.g., "Red")', border: OutlineInputBorder(), filled: true, fillColor: Colors.white), validator: (v) => v?.isEmpty ?? true ? 'Required' : null),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: Container(height: 100, decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)), child: pickedImages[index] != null ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(pickedImages[index]!['displayUrl'] ?? pickedImages[index]!['imageUrl'], fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 40))) : imageControllers[index].text.trim().isNotEmpty ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(imageControllers[index].text.trim(), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 40))) : Center(child: Text('No image', style: TextStyle(color: Colors.grey.shade500))))),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final selected = await showDialog(context: context, builder: (_) => SelectImageDialog(singleSelect: false));
                        if (selected != null) { setState(() { pickedImages[index] = selected as Map<String, dynamic>; imageControllers[index].text = selected['name'] ?? 'Selected'; }); }
                      },
                      icon: const Icon(Icons.image, size: 18), label: const Text('Select Image'), style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade200),
                    ),
                  ]),
                ]),
              )),
            ],

            if (selectedType == 'image_select_reverse') ...[
              const Divider(thickness: 2),
              const Text('Image', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Container(height: 120, decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)), child: reversePickedImage != null ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(reversePickedImage!['displayUrl'] ?? reversePickedImage!['imageUrl'], fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 40))) : imageUrlController.text.trim().isNotEmpty ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(imageUrlController.text.trim(), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 40))) : const Center(child: Text('No image selected', style: TextStyle(color: Colors.grey))))),
                const SizedBox(width: 12),
                ElevatedButton.icon(onPressed: () async { final selected = await showDialog(context: context, builder: (_) => SelectImageDialog(singleSelect: true)); if (selected != null) { setState(() { reversePickedImage = selected as Map<String, dynamic>; imageUrlController.text = selected['name'] ?? 'Selected'; }); } }, icon: const Icon(Icons.image, size: 20), label: const Text('Select Image'), style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade200)),
              ]),
              const SizedBox(height: 16),
              Row(children: [const Text('Text Options (3-4 required)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const Spacer(), if (reverseOptions.length < 4) IconButton(icon: const Icon(Icons.add_circle, color: Color(0xFF4CAF50)), onPressed: _addReverseOption)]),
              const SizedBox(height: 16),
              ...List.generate(reverseOptions.length, (index) => Container(
                margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8), color: Colors.grey.shade50),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Text('Option ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), const Spacer(), Checkbox(value: reverseOptions[index]['isCorrect'], activeColor: const Color(0xFF4CAF50), onChanged: (v) => setState(() => reverseOptions[index]['isCorrect'] = v ?? false)), const Text('Correct'), if (reverseOptions.length > 3) IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _removeReverseOption(index))]),
                  const SizedBox(height: 8),
                  TextFormField(controller: reverseOptionControllers[index], decoration: const InputDecoration(labelText: 'Text (e.g., "Stand up")', border: OutlineInputBorder(), filled: true, fillColor: Colors.white), validator: (v) => v?.isEmpty ?? true ? 'Required' : null),
                ]),
              )),
            ],

            if (selectedType == 'complete_the_chat') ...[
              const Divider(thickness: 2),
              Row(children: [const Text('Conversation turns', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(width: 8), Text('${chatTurns.length} turn${chatTurns.length != 1 ? 's' : ''}', style: const TextStyle(fontSize: 12, color: Colors.grey)), const Spacer(), if (chatTurns.length < 6) TextButton.icon(onPressed: _addChatTurn, icon: const Icon(Icons.add, size: 18, color: Color(0xFF4CAF50)), label: const Text('Add turn', style: TextStyle(color: Color(0xFF4CAF50), fontWeight: FontWeight.w600)))]),
              const SizedBox(height: 4),
              Container(margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade100)), child: const Row(children: [Icon(Icons.chat_bubble_outline, color: Colors.blue, size: 16), SizedBox(width: 8), Expanded(child: Text('Each turn = one chat bubble the student must reply to. Turns play in order.', style: TextStyle(fontSize: 12, color: Colors.blue)))])),
              ...List.generate(chatTurns.length, (i) => _buildChatTurnCard(i)),
            ],

            if (selectedType == 'fill_blank') ...[
              const Divider(thickness: 2),
              Row(children: [const Text('Options', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(width: 8), Text('$_assignedCorrectCount correct · ${fillBlankOptions.where((o) => o['isCorrect'] == false).length} distractor${fillBlankOptions.where((o) => o['isCorrect'] == false).length != 1 ? 's' : ''}', style: const TextStyle(fontSize: 12, color: Colors.grey)), const Spacer(), IconButton(icon: const Icon(Icons.add_circle, color: Color(0xFF4CAF50)), onPressed: _addFillBlankOption)]),
              const SizedBox(height: 16),
              ...List.generate(fillBlankOptions.length, (i) => _buildFillBlankOptionCard(i)),
            ],

            if (selectedType == 'arrange') ...[
              const Divider(thickness: 2),
              const Text('Sentence', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              _buildArrangeEditor(),
            ],

            if (selectedType == 'match') ...[
              const Divider(thickness: 2),
              const Text('Pairs', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              _buildMatchEditor(),
            ],

            if (selectedType == 'reading') ...[
              const Divider(thickness: 2),
              _buildReadingEditor(),
            ],

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(backgroundColor: widget.groupColor, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: isLoading ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text(widget.taskId != null ? 'Update' : 'Create', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}