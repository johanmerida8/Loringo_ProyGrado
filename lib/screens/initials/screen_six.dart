import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:loringo_app/services/translation/teacher_ui_translations.dart';
import 'package:lottie/lottie.dart';

// ── Data model for one match pair ─────────────────────────────────────────────
class _MatchPair {
  final int id;
  final String english;
  final String translated; // used only in text mode
  final String image;      // used only in image mode

  const _MatchPair({
    required this.id,
    required this.english,
    this.translated = '',
    this.image = '',
  });
}

class ScreenSix extends StatefulWidget {
  final String contentId;
  final String unitId;
  final String lessonId;
  final String activityId;
  final String taskId;
  final Function(bool isCorrect) onTaskComplete;
  final int currentTaskNumber;
  final int totalTasks;
  final String collectionName;

  const ScreenSix({
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
  State<ScreenSix> createState() => _ScreenSixState();
}

class _ScreenSixState extends State<ScreenSix> with SingleTickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  final FlutterTts _tts = FlutterTts();

  static const Color _green = Color(0xFF4CAF50);

  String _userLang = 'Spanish';
  String _mode = 'text'; // 'text' or 'image'

  List<_MatchPair> _pairs = [];
  List<_MatchPair> _leftCol = [];
  List<_MatchPair> _rightCol = [];

  int? _selectedLeftId;
  int? _selectedRightId;
  final Set<int> _matchedIds = {};
  int? _wrongLeftId;
  int? _wrongRightId;

  bool _isLoading = true;
  late AnimationController _shakeCtrl;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _setUp();
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    _player.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _setUp() async {
    await _initTts();
    await _fetchTask();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-GB');
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
  }

  Future<void> _fetchTask() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (userDoc.exists) _userLang = userDoc['language'] ?? 'Spanish';
      }

      final doc = await FirebaseFirestore.instance
          .collection(widget.collectionName).doc(widget.contentId)
          .collection('units').doc(widget.unitId)
          .collection('lessons').doc(widget.lessonId)
          .collection('activities').doc(widget.activityId)
          .collection('tasks').doc(widget.taskId)
          .get();

      if (!doc.exists) return;

      final raw = doc.data() as Map<String, dynamic>;
      final taskData = raw['data'] as Map<String, dynamic>? ?? raw;

      _mode = taskData['mode'] as String? ?? 'text';

      final rawPairs = List<Map<String, dynamic>>.from(taskData['pairs'] ?? []);
      final pairs = rawPairs.asMap().entries.map((e) => _MatchPair(
        id: e.key,
        english: e.value['english'] as String? ?? '',
        translated: e.value['translated'] as String? ?? '',
        image: e.value['image'] as String? ?? '',
      )).toList();

      final leftCol = List<_MatchPair>.from(pairs)..shuffle();
      final rightCol = List<_MatchPair>.from(pairs)..shuffle();

      setState(() {
        _pairs = pairs;
        _leftCol = leftCol;
        _rightCol = rightCol;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('ScreenSix ERROR: $e');
      setState(() => _isLoading = false);
    }
  }

  void _onTapLeft(int pairId) {
    if (_matchedIds.contains(pairId) || _wrongLeftId != null) return;
    setState(() => _selectedLeftId = pairId);
    _tts.speak(_pairs.firstWhere((p) => p.id == pairId).english);
    _tryMatch();
  }

  void _onTapRight(int pairId) {
    if (_matchedIds.contains(pairId) || _wrongRightId != null) return;
    setState(() => _selectedRightId = pairId);
    _tryMatch();
  }

  void _tryMatch() {
    if (_selectedLeftId == null || _selectedRightId == null) return;

    final leftId = _selectedLeftId!;
    final rightId = _selectedRightId!;

    if (leftId == rightId) {
      HapticFeedback.mediumImpact();
      _player.setAsset('assets/sound/success-2.mp3').then((_) => _player.play());
      setState(() {
        _matchedIds.add(leftId);
        _selectedLeftId = null;
        _selectedRightId = null;
      });
      if (_matchedIds.length == _pairs.length) {
        Future.delayed(const Duration(milliseconds: 600), () => _showResultSheet(true));
      }
    } else {
      HapticFeedback.heavyImpact();
      _player.setAsset('assets/sound/fail-2.mp3').then((_) => _player.play());
      _shakeCtrl.forward(from: 0);
      setState(() {
        _wrongLeftId = leftId;
        _wrongRightId = rightId;
      });
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) {
          setState(() {
            _wrongLeftId = null;
            _wrongRightId = null;
            _selectedLeftId = null;
            _selectedRightId = null;
          });
        }
      });
    }
  }

  void _showResultSheet(bool correct) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: false,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.4,
        maxChildSize: 0.55,
        builder: (_, __) => Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, -5))],
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Lottie.asset(
              correct ? 'assets/animation/correct.json' : 'assets/animation/fail.json',
              height: 130,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onTaskComplete(correct);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: correct ? _green : Colors.orange,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  TeacherUITranslations.get('continueBtnText', _userLang),
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Tile color helper ─────────────────────────────────────────────────────
  ({Color bg, Color border, Color text}) _tileColors(int pairId, bool isLeft) {
    final isMatched = _matchedIds.contains(pairId);
    final isSelected = isLeft ? _selectedLeftId == pairId : _selectedRightId == pairId;
    final isWrong = isLeft ? _wrongLeftId == pairId : _wrongRightId == pairId;

    if (isMatched) {
      return (bg: _green.withOpacity(0.12), border: _green, text: const Color(0xFF2E7D32));
    } else if (isWrong) {
      return (bg: Colors.red.withOpacity(0.1), border: Colors.red, text: Colors.red.shade700);
    } else if (isSelected) {
      return (bg: _green.withOpacity(0.08), border: _green, text: const Color(0xFF2E7D32));
    }
    return (bg: Colors.white, border: Colors.grey.shade300, text: Colors.black87);
  }

  // ── Left tile (English word) ─────────────────────────────────────────────
  Widget _buildLeftTile(_MatchPair pair) {
    final isMatched = _matchedIds.contains(pair.id);
    final c = _tileColors(pair.id, true);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: GestureDetector(
        onTap: isMatched ? null : () => _onTapLeft(pair.id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border, width: (isMatched || _selectedLeftId == pair.id || _wrongLeftId == pair.id) ? 2 : 1.5),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2)),
              if (_selectedLeftId == pair.id) BoxShadow(color: _green.withOpacity(0.18), blurRadius: 8, offset: const Offset(0, 3)),
            ],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (isMatched) ...[
              const Icon(Icons.check_circle, color: _green, size: 16),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                pair.english,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isMatched || _selectedLeftId == pair.id ? FontWeight.bold : FontWeight.w600,
                  color: c.text,
                ),
              ),
            ),
            if (!isMatched) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => _tts.speak(pair.english),
                child: Icon(Icons.volume_up, size: 16, color: _selectedLeftId == pair.id ? _green : Colors.grey.shade400),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  // ── Right tile (text or image) ───────────────────────────────────────────
  Widget _buildRightTile(_MatchPair pair) {
    final isMatched = _matchedIds.contains(pair.id);
    final c = _tileColors(pair.id, false);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: GestureDetector(
        onTap: isMatched ? null : () => _onTapRight(pair.id),
        child: Container(
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border, width: (isMatched || _selectedRightId == pair.id || _wrongRightId == pair.id) ? 2 : 1.5),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2)),
              if (_selectedRightId == pair.id) BoxShadow(color: _green.withOpacity(0.18), blurRadius: 8, offset: const Offset(0, 3)),
            ],
          ),
          child: _mode == 'image'
              ? _buildImageTile(pair, isMatched)
              : _buildTextTile(pair, isMatched),
        ),
      ),
    );
  }

  // Text mode right tile
  Widget _buildTextTile(_MatchPair pair, bool isMatched) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (isMatched) ...[
          const Icon(Icons.check_circle, color: _green, size: 16),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            pair.translated,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, fontWeight: isMatched ? FontWeight.bold : FontWeight.w600, color: Colors.black87),
          ),
        ),
      ]),
    );
  }

  // Image mode right tile – uses fixed height + contain to avoid cropping
  Widget _buildImageTile(_MatchPair pair, bool isMatched) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        children: [
          SizedBox(
            height: 100,
            width: double.infinity,
            child: pair.image.isNotEmpty
                ? Image.network(
                    pair.image,
                    fit: BoxFit.contain, // Prevents cropping
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey.shade100,
                      child: const Center(child: Icon(Icons.broken_image, size: 32, color: Colors.grey)),
                    ),
                  )
                : Container(
                    color: Colors.grey.shade100,
                    child: const Center(child: Icon(Icons.image, size: 32, color: Colors.grey)),
                  ),
          ),
          if (isMatched)
            Positioned.fill(
              child: Container(
                color: _green.withOpacity(0.25),
                child: const Center(child: Icon(Icons.check_circle, color: Colors.white, size: 28)),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_pairs.isEmpty) {
      return const Scaffold(body: Center(child: Text('No pairs found')));
    }

    final progressValue = (widget.currentTaskNumber + 1) / widget.totalTasks;
    final matchedCount = _matchedIds.length;
    final totalPairs = _pairs.length;
    final isImageMode = _mode == 'image';

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE8F5E9), Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header with progress
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.black87, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.all(Radius.circular(30)),
                      child: LinearProgressIndicator(
                        value: progressValue,
                        backgroundColor: Colors.blueGrey,
                        valueColor: const AlwaysStoppedAnimation<Color>(_green),
                        minHeight: 8,
                      ),
                    ),
                  ),
                ]),
              ),

              // Title and counter
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Match the pairs',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: _green.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _green.withOpacity(0.3)),
                      ),
                      child: Text(
                        '$matchedCount / $totalPairs',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _green),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Column headers
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(children: [
                  Expanded(
                    child: Center(
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.flag, size: 14, color: _green),
                        const SizedBox(width: 4),
                        Text('English', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade600, letterSpacing: 0.8)),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Center(
                      child: isImageMode
                          ? Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.image_outlined, size: 14, color: Colors.purple.shade400),
                              const SizedBox(width: 4),
                              Text('Image', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade600, letterSpacing: 0.8)),
                            ])
                          : Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.flag, size: 14, color: Colors.orange),
                              const SizedBox(width: 4),
                              Text(_userLang, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade600, letterSpacing: 0.8)),
                            ]),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 8),

              // Two‑column scrollable area
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: SingleChildScrollView(child: Column(children: _leftCol.map(_buildLeftTile).toList()))),
                      const SizedBox(width: 16),
                      Expanded(child: SingleChildScrollView(child: Column(children: _rightCol.map(_buildRightTile).toList()))),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}