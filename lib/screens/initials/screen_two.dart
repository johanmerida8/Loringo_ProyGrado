import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:just_audio/just_audio.dart';
// import 'package:loringo_app/services/translation/teacher_ui_translations.dart';
import 'package:lottie/lottie.dart';

// ── Data model for one conversation turn ────────────────────────────────────
class _Turn {
  final String bubbleEn;        // original English bubble text
  final String bubbleTranslated; // translated for display
  final List<Map<String, dynamic>> options; // {textEn, isCorrect}

  const _Turn({
    required this.bubbleEn,
    required this.bubbleTranslated,
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
  });

  @override
  State<ScreenTwo> createState() => _ScreenTwoState();
}

class _ScreenTwoState extends State<ScreenTwo> {
  final AudioPlayer _player = AudioPlayer();
  final FlutterTts _tts = FlutterTts();
  late OnDeviceTranslator _translator;

  String _userLang = 'English';

  // All turns loaded from Firestore
  List<_Turn> _turns = [];

  // Which turn the student is currently answering (0-based)
  int _currentTurn = 0;

  // The reply selected for the current turn
  String _selectedReply = '';

  // History: list of {bubble, chosenReply, correct} — shown as a chat log above
  final List<Map<String, dynamic>> _history = [];

  // Overall correctness tracking
  int _correctCount = 0;
  int _wrongCount = 0;

  bool _isLoading = true;

  static const Color _green = Color(0xFF4CAF50);

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

  Future<void> _initTranslator() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    String lang = 'Spanish';
    if (uid != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
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
      case 'spanish': return TranslateLanguage.spanish;
      case 'french':  return TranslateLanguage.french;
      case 'german':  return TranslateLanguage.german;
      case 'italian': return TranslateLanguage.italian;
      default:        return TranslateLanguage.spanish;
    }
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-GB');
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
  }

  @override
  void dispose() {
    _translator.close();
    _player.dispose();
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

      // ── Support both old schema (single question + options) and new
      //    multi-turn schema (turns list) ──────────────────────────────
      final rawTurns = taskData['turns'] as List<dynamic>?;

      if (rawTurns != null) {
        // New multi-turn schema
        final built = <_Turn>[];
        for (final t in rawTurns) {
          final turn = t as Map<String, dynamic>;
          final bubbleEn = turn['bubble'] as String? ?? '';
          final bubbleTranslated = await _translator.translateText(bubbleEn);
          final rawOpts = List<Map<String, dynamic>>.from(turn['options'] ?? []);
          final opts = rawOpts.map((o) => {
            'textEn': o['text'] ?? '',
            'isCorrect': o['isCorrect'] ?? false,
          }).toList();
          built.add(_Turn(bubbleEn: bubbleEn, bubbleTranslated: bubbleTranslated, options: opts));
        }
        _turns = built;
      } else {
        // Legacy single-turn schema — wrap in one turn
        final questionEn = taskData['question'] as String? ?? '';
        final bubbleTranslated = await _translator.translateText(questionEn);
        final rawOpts = List<Map<String, dynamic>>.from(taskData['options'] ?? []);
        final opts = rawOpts.map((o) => {
          'textEn': o['text'] ?? '',
          'isCorrect': o['isCorrect'] ?? false,
        }).toList();
        _turns = [_Turn(bubbleEn: questionEn, bubbleTranslated: bubbleTranslated, options: opts)];
      }

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('ScreenTwo ERROR: $e');
      setState(() => _isLoading = false);
    }
  }

  void _speak(String text) async {
    if (text.isNotEmpty) await _tts.speak(text);
  }

  // Called when the student taps Check on the current turn
  void _checkCurrentTurn() {
    final turn = _turns[_currentTurn];
    final correct = turn.options.firstWhere(
      (o) => o['textEn'] == _selectedReply,
      orElse: () => {'textEn': '', 'isCorrect': false},
    )['isCorrect'] == true;

    if (correct) _correctCount++; else _wrongCount++;

    // Play sound + haptic
    if (correct) HapticFeedback.mediumImpact(); else HapticFeedback.heavyImpact();
    _player.setAsset(correct ? 'assets/sound/success-2.mp3' : 'assets/sound/fail-2.mp3')
        .then((_) => _player.play());

    // Add to history
    _history.add({
      'bubbleEn': turn.bubbleEn,
      'bubbleTranslated': turn.bubbleTranslated,
      'chosenReply': _selectedReply,
      'correct': correct,
    });

    _showTurnFeedback(correct);
  }

  void _showTurnFeedback(bool correct) {
    final isLastTurn = _currentTurn == _turns.length - 1;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: false,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.38,
        maxChildSize: 0.55,
        builder: (_, __) => Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, -5))],
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Lottie.asset(correct ? 'assets/animation/correct.json' : 'assets/animation/fail.json', height: 120),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  if (isLastTurn) {
                    // Conversation complete — report overall result to ActivityPlayScreen.
                    // Considered correct if more than half the turns were answered correctly.
                    final overallCorrect = _correctCount > _wrongCount;
                    widget.onTaskComplete(overallCorrect);
                  } else {
                    // Advance to next turn
                    setState(() {
                      _currentTurn++;
                      _selectedReply = '';
                    });
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: correct ? _green : Colors.orange,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  isLastTurn
                      ? 'Finish'
                      : 'Continue',
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Chat history (previously answered turns) ─────────────────────────────────
  Widget _buildHistory() {
    if (_history.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _history.map((entry) {
        final correct = entry['correct'] as bool;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Teacher bubble (past)
            _buildBubble(entry['bubbleTranslated'] as String, entry['bubbleEn'] as String, past: true),
            const SizedBox(height: 8),
            // Student reply bubble (right-aligned)
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

  // ── Active chat bubble with TTS ──────────────────────────────────────────────
  Widget _buildBubble(String translated, String english, {bool past = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Avatar
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
            // Show translated above, English below (smaller)
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(translated, style: TextStyle(fontSize: past ? 13 : 16, color: past ? Colors.black54 : Colors.black87, height: 1.3)),
              if (!past) ...[
                const SizedBox(height: 4),
                Text(english, style: const TextStyle(fontSize: 12, color: Colors.black38, fontStyle: FontStyle.italic)),
              ],
            ]),
          ),
        ),
        if (!past) ...[
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.volume_up, color: _green, size: 22),
            onPressed: () => _speak(english),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ],
    );
  }

  // ── Reply option chip ────────────────────────────────────────────────────────
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

    return Scaffold(
      body: Container(
        decoration: grad,
        child: SafeArea(
          child: Column(children: [
            // ── Progress bar ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(children: [
                IconButton(icon: const Icon(Icons.close, color: Colors.black87, size: 28), onPressed: () => Navigator.pop(context)),
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.all(Radius.circular(30)),
                    child: LinearProgressIndicator(
                      // Progress combines task progress and turn progress
                      value: (widget.currentTaskNumber + (_currentTurn / _turns.length)) / widget.totalTasks,
                      backgroundColor: Colors.blueGrey,
                      valueColor: const AlwaysStoppedAnimation<Color>(_green),
                      minHeight: 8,
                    ),
                  ),
                ),
                // Turn indicator pill
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

            // ── Scrollable chat area ─────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Past turns as greyed-out history
                  _buildHistory(),

                  // Current active bubble
                  _buildBubble(currentTurnData.bubbleTranslated, currentTurnData.bubbleEn),
                  const SizedBox(height: 20),

                  // Divider + "Your reply" label
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

                  // Reply options for current turn
                  ...currentTurnData.options.map((opt) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buildReplyOption(opt['textEn'] as String),
                  )),

                  const SizedBox(height: 8),
                ]),
              ),
            ),

            // ── Check button ─────────────────────────────────────────
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
                  child: Text(
                    'Check',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}