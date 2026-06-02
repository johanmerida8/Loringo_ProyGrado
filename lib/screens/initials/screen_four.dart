import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:just_audio/just_audio.dart';
import 'package:loringo_app/services/translation/teacher_ui_translations.dart';
import 'package:lottie/lottie.dart';

class ScreenFour extends StatefulWidget {
  final String contentId;
  final String unitId;
  final String lessonId;
  final String activityId;
  final String taskId;
  final Function(bool isCorrect)? onTaskComplete;
  final int currentTaskNumber;
  final int totalTasks;
  final String collectionName;

  const ScreenFour({
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
  State<ScreenFour> createState() => _ScreenFourState();
}

// ── Data model for a single option loaded from Firestore ─────────────────────
class _FillOption {
  final String textEn;
  final String textTranslated;
  final bool isCorrect;

  // null = distractor; 0,1,2... = index of the blank this answers
  final int? blankIndex;

  _FillOption({
    required this.textEn,
    required this.textTranslated,
    required this.isCorrect,
    this.blankIndex,
  });
}

class _ScreenFourState extends State<ScreenFour> {
  final AudioPlayer _player = AudioPlayer();
  final FlutterTts _tts = FlutterTts();
  late OnDeviceTranslator _translator;

  static const Color _green = Color(0xFF4CAF50);

  String _userLang = 'Spanish';
  String _subtitle = '';

  // ── Parsed question segments ────────────────────────────────────────────────
  // The question is stored as e.g. "Roses are ___ and violets are ___".
  // We split it on "___" to get the text segments between/around the blanks.
  // segments.length == blanks.length + 1  (always one more segment than blanks)
  List<String> _segments = [];

  // ── Options pool ────────────────────────────────────────────────────────────
  List<_FillOption> _options = [];

  // ── Drag & drop state (multi-blank) ─────────────────────────────────────────
  // _droppedWords[i] = textEn of the word dropped into blank i, or null.
  List<String?> _droppedWords = [];

  // ── Tap state (single-blank legacy) ─────────────────────────────────────────
  String _selectedOptionEn = '';

  bool _isLoading = true;

  // Convenience: how many blanks this task has
  int get _blankCount => _segments.length - 1;

  // True when every blank has been filled
  bool get _allBlanksFilled =>
      _blankCount == 1
          ? _selectedOptionEn.isNotEmpty
          : _droppedWords.every((w) => w != null);

  @override
  void initState() {
    super.initState();
    _setUp();
  }

  Future<void> _setUp() async {
    await _initTranslator();
    await _initTts();
    await _fetchTask();
  }

  // ── Translator ──────────────────────────────────────────────────────────────
  Future<void> _initTranslator() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    String lang = 'Spanish';
    if (uid != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (doc.exists) lang = doc['language'] ?? 'Spanish';
    }
    _userLang = lang;
    _translator = OnDeviceTranslator(
      sourceLanguage: TranslateLanguage.english,
      targetLanguage: _langEnum(lang),
    );
  }

  TranslateLanguage _langEnum(String lang) {
    switch (lang.toLowerCase()) {
      case 'spanish':
        return TranslateLanguage.spanish;
      case 'french':
        return TranslateLanguage.french;
      case 'german':
        return TranslateLanguage.german;
      case 'italian':
        return TranslateLanguage.italian;
      default:
        return TranslateLanguage.spanish;
    }
  }

  // ── TTS ─────────────────────────────────────────────────────────────────────
  Future<void> _initTts() async {
    await _tts.setLanguage('en-GB');
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
  }

  void _speak(String text) async {
    if (text.isNotEmpty) await _tts.speak(text);
  }

  // Reconstruct the complete correct sentence for TTS.
  String get _fullSentence {
    final buf = StringBuffer();
    for (int i = 0; i < _segments.length; i++) {
      buf.write(_segments[i]);
      if (i < _blankCount) {
        buf.write('...');
      }
    }
    return buf.toString();
  }

  // ── Firestore fetch ─────────────────────────────────────────────────────────
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

      if (!doc.exists) return;

      final raw = doc.data() as Map<String, dynamic>;
      final taskData = raw['data'] as Map<String, dynamic>? ?? raw;

      _subtitle = taskData['subtitle'] ?? '';
      final questionEn = taskData['question'] as String? ?? '';

      // Split the question on ___ to get text segments.
      // "Roses are ___ and violets are ___"
      //   → ["Roses are ", " and violets are ", ""]
      _segments = questionEn.split('___');

      // ── Build options ──
      final rawOptions =
          List<Map<String, dynamic>>.from(taskData['options'] ?? []);

      final built = <_FillOption>[];
      for (final o in rawOptions) {
        final translated = await _translator.translateText(o['text'] ?? '');

        // Support both old schema (no blankIndex) and new multi-blank schema.
        // Old schema: isCorrect: true → automatically assign to blank 0.
        int? blankIdx = o['blankIndex'] as int?;
        final isCorrect = o['isCorrect'] as bool? ?? false;
        if (isCorrect && blankIdx == null) {
          blankIdx = 0;
        }

        built.add(_FillOption(
          textEn: o['text'] ?? '',
          textTranslated: translated,
          isCorrect: isCorrect,
          blankIndex: blankIdx,
        ));
      }

      // Shuffle so options don't always appear in creation order.
      built.shuffle();
      _options = built;

      // Initialise drop slots — one per blank, all empty.
      _droppedWords = List<String?>.filled(_blankCount, null);

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('ScreenFour ERROR: $e');
      setState(() => _isLoading = false);
    }
  }

  // ── Answer checking ─────────────────────────────────────────────────────────
  void _checkAnswer() {
    bool correct;

    if (_blankCount == 1) {
      final correctOpt = _options.firstWhere(
        (o) => o.isCorrect && o.blankIndex == 0,
        orElse: () =>
            _FillOption(textEn: '', textTranslated: '', isCorrect: false),
      );
      correct = _selectedOptionEn == correctOpt.textEn;
    } else {
      correct = true;
      for (int i = 0; i < _blankCount; i++) {
        final correctOpt = _options.firstWhere(
          (o) => o.isCorrect && o.blankIndex == i,
          orElse: () =>
              _FillOption(textEn: '', textTranslated: '', isCorrect: false),
        );
        if (_droppedWords[i] != correctOpt.textEn) {
          correct = false;
          break;
        }
      }
    }

    _playFeedback(correct);
  }

  void _playFeedback(bool correct) {
    if (correct) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
    _player
        .setAsset(correct
            ? 'assets/sound/success-2.mp3'
            : 'assets/sound/fail-2.mp3')
        .then((_) => _player.play());
    _showResultSheet(correct);
  }

  void _showResultSheet(bool correct) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.4,
        maxChildSize: 0.6,
        builder: (_, __) => Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black26,
                  blurRadius: 20,
                  offset: Offset(0, -5))
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Lottie.asset(
                correct
                    ? 'assets/animation/correct.json'
                    : 'assets/animation/fail.json',
                height: 150,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onTaskComplete!(correct);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: correct ? _green : Colors.orange,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 5,
                  ),
                  child: Text(
                    TeacherUITranslations.get('continueBtnText', _userLang),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _translator.close();
    _player.dispose();
    _tts.stop();
    super.dispose();
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  SHARED UI HELPERS
  // ────────────────────────────────────────────────────────────────────────────

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.black87, size: 28),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(30)),
              child: LinearProgressIndicator(
                value: (widget.currentTaskNumber + 1) / widget.totalTasks,
                backgroundColor: Colors.blueGrey,
                valueColor: const AlwaysStoppedAnimation<Color>(_green),
                minHeight: 8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubtitle() {
    if (_subtitle.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        _subtitle,
        style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.black87),
      ),
    );
  }

  Widget _buildCheckButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _allBlanksFilled ? _checkAnswer : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: _green,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
          child: Text(
            TeacherUITranslations.get('check', _userLang),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2),
          ),
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  SINGLE-BLANK UI  (tap — legacy behaviour, unchanged feel)
  // ────────────────────────────────────────────────────────────────────────────

  Widget _buildSingleBlankQuestion() {
    final before = _segments.isNotEmpty ? _segments[0] : '';
    final after = _segments.length > 1 ? _segments[1] : '';
    final correctOpt = _options.firstWhere(
      (o) => o.isCorrect && o.blankIndex == 0,
      orElse: () =>
          _FillOption(textEn: '___', textTranslated: '', isCorrect: false),
    );
    final blankWidth =
        (correctOpt.textEn.length * 12.0).clamp(48.0, 200.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            onPressed: () => _speak(_fullSentence),
            icon: const Icon(Icons.volume_up, color: _green, size: 28),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: Colors.grey.shade300, width: 1.5),
              ),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 4,
                children: [
                  if (before.isNotEmpty)
                    Text(before,
                        style: const TextStyle(
                            fontSize: 18, color: Colors.black87)),
                  Container(
                    width: blankWidth,
                    height: 28,
                    margin:
                        const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  if (after.isNotEmpty)
                    Text(after,
                        style: const TextStyle(
                            fontSize: 18, color: Colors.black87)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleBlankOptions() {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ListView.builder(
          itemCount: _options.length,
          itemBuilder: (context, index) {
            final opt = _options[index];
            final isSelected = _selectedOptionEn == opt.textEn;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () =>
                    setState(() => _selectedOptionEn = opt.textEn),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: isSelected ? _green : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color:
                          isSelected ? _green : Colors.grey.shade300,
                      width: 2,
                    ),
                  ),
                  child: Text(
                    opt.textEn,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.black87,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  MULTI-BLANK UI  (drag & drop)
  // ────────────────────────────────────────────────────────────────────────────

  Widget _buildMultiBlankQuestion() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => _speak(_fullSentence),
                  icon: const Icon(Icons.volume_up,
                      color: _green, size: 24),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                Text(
                  // TeacherUITranslations.get(
                  //     'dragWordsInstruction', _userLang),
                  'Drag the correct words into the blanks',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 2,
              runSpacing: 8,
              children: _buildSentenceChunks(),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSentenceChunks() {
    final chunks = <Widget>[];
    for (int i = 0; i < _segments.length; i++) {
      if (_segments[i].isNotEmpty) {
        chunks.add(Text(
          _segments[i],
          style:
              const TextStyle(fontSize: 18, color: Colors.black87),
        ));
      }
      if (i < _blankCount) {
        chunks.add(_buildDropTarget(i));
      }
    }
    return chunks;
  }

  Widget _buildDropTarget(int blankIdx) {
    final dropped = _droppedWords[blankIdx];
    final correctOpt = _options.firstWhere(
      (o) => o.isCorrect && o.blankIndex == blankIdx,
      orElse: () =>
          _FillOption(textEn: '______', textTranslated: '', isCorrect: false),
    );
    final minWidth =
        (correctOpt.textEn.length * 11.0).clamp(56.0, 180.0);

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) {
        setState(() {
          // If the incoming word was already in another blank, clear it first.
          for (int i = 0; i < _blankCount; i++) {
            if (_droppedWords[i] == details.data) {
              _droppedWords[i] = null;
            }
          }
          _droppedWords[blankIdx] = details.data;
        });
      },
      builder: (context, candidates, rejected) {
        final isHovering = candidates.isNotEmpty;
        return GestureDetector(
          // Tap a filled blank to return the word to the pool
          onTap: dropped != null
              ? () => setState(() => _droppedWords[blankIdx] = null)
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            constraints: BoxConstraints(minWidth: minWidth),
            height: 36,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: dropped != null
                  ? _green.withOpacity(0.15)
                  : isHovering
                      ? _green.withOpacity(0.08)
                      : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: dropped != null
                    ? _green
                    : isHovering
                        ? _green.withOpacity(0.6)
                        : Colors.grey.shade400,
                width: dropped != null ? 2 : 1.5,
              ),
            ),
            child: dropped != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        dropped,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2E7D32)),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.close,
                          size: 14, color: Color(0xFF2E7D32)),
                    ],
                  )
                : Text(
                    'Blank ${blankIdx + 1}',
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade500),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildWordPool() {
    // Only show words not already dropped into a blank.
    final available = _options
        .where((o) => !_droppedWords.contains(o.textEn))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          // TeacherUITranslations.get('wordPool', _userLang),
          'Word Pool',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children:
              available.map((opt) => _buildDraggableChip(opt)).toList(),
        ),
      ],
    );
  }

  Widget _buildDraggableChip(_FillOption opt) {
    return Draggable<String>(
      data: opt.textEn,
      feedback: Material(
        color: Colors.transparent,
        child: _wordChip(opt.textEn, dragging: true),
      ),
      childWhenDragging: _wordChip(opt.textEn, ghost: true),
      child: _wordChip(opt.textEn),
    );
  }

  Widget _wordChip(String text,
      {bool dragging = false, bool ghost = false}) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: ghost
            ? Colors.grey.shade100
            : dragging
                ? _green
                : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ghost
              ? Colors.grey.shade300
              : dragging
                  ? _green
                  : Colors.grey.shade400,
          width: 2,
        ),
        boxShadow: dragging
            ? [
                BoxShadow(
                    color: _green.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4))
              ]
            : null,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: ghost
              ? Colors.grey.shade400
              : dragging
                  ? Colors.white
                  : Colors.black87,
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  build()
  // ────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    const grad = BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFFE8F5E9), Colors.white],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
    );

    return Scaffold(
      body: Container(
        decoration: grad,
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _options.isEmpty
                  ? const Center(child: Text('No options available'))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildProgressBar(),
                        _buildSubtitle(),
                        const SizedBox(height: 16),

                        // Adaptive: grey-box question (1 blank) or
                        // inline DragTargets (2+ blanks)
                        if (_blankCount == 1)
                          _buildSingleBlankQuestion()
                        else
                          _buildMultiBlankQuestion(),

                        const SizedBox(height: 24),

                        // Adaptive: tap list (1 blank) or word pool (2+ blanks)
                        if (_blankCount == 1)
                          _buildSingleBlankOptions()
                        else ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20),
                            child: _buildWordPool(),
                          ),
                          const Spacer(),
                        ],

                        _buildCheckButton(),
                      ],
                    ),
        ),
      ),
    );
  }
}