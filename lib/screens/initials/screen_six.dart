// screen_six.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loringo_app/screens/initials/widget/responsive_activity_shell.dart';
import 'package:loringo_app/screens/initials/widget/task_exit_guard.dart';
import 'package:loringo_app/screens/initials/widget/task_result_sheet.dart';
import 'package:loringo_app/services/audio/feedback_sound_service.dart';
import 'package:loringo_app/services/audio/task_feedback.dart';
import 'package:loringo_app/screens/initials/widget/exit_task_dialog.dart';
import 'package:loringo_app/screens/initials/widget/task_callbacks.dart';
import 'package:loringo_app/services/tts/task_tts_service.dart';
import 'package:loringo_app/services/tts/tts_voices.dart';

class _MatchPair {
  final int id;
  final String english;
  final String translated;
  final String image;

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
  // ── TEACHER REVIEW FEATURE ──────────────────────────────────────────
  // See widget/task_callbacks.dart for why this uses a shared typedef.
  // answerDetail shape: {'type': 'match', 'mode': 'text'|'image',
  // 'pairs': [{'english': ..., 'translated': ..., 'image': ...}, ...]}.
  // Unlike every other task type, 'match' has no wrong-answer state that
  // survives to completion — a mismatched tap resets after a beat (see
  // _tryMatch below) and every pair is eventually matched correctly
  // before onTaskComplete ever fires. So there's no "student picked X,
  // correct was Y" to report; the detail is purely informational — which
  // pairs this task contained — so the teacher review screen can still
  // show the exercise's content even though there's nothing to grade
  // per-pair.
  final TaskCompleteCallback onTaskComplete;
  final int currentTaskNumber;
  final int totalTasks;
  final String collectionName;
  final bool isPracticeRound;

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
    this.isPracticeRound = false,
  });

  @override
  State<ScreenSix> createState() => _ScreenSixState();
}

class _ScreenSixState extends State<ScreenSix> with SingleTickerProviderStateMixin {
  static const Color _green = Color(0xFF4CAF50);

  String _userLang = 'Spanish';
  String _mode = 'text';

  List<_MatchPair> _pairs = [];
  List<_MatchPair> _leftCol = [];
  List<_MatchPair> _rightCol = [];

  int? _selectedLeftId;
  int? _selectedRightId;
  final Set<int> _matchedIds = {};
  int? _wrongLeftId;
  int? _wrongRightId;

  bool _isLoading = true;
  String? _errorMessage;
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
    TaskTtsService.stop();
    super.dispose();
  }

  Future<void> _setUp() async {
    await _fetchTask();
  }

  Future<void> _handleClose() async {
    final shouldExit = await confirmExitTask(context);
    if (shouldExit && context.mounted) Navigator.pop(context);
  }

  Future<void> _fetchTask() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        try {
          final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
          if (userDoc.exists) {
            _userLang = (userDoc.data()?['language'] as String?) ?? 'Spanish';
          }
        } catch (e) {
          debugPrint('Error fetching user language: $e');
        }
      }

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

      if (!doc.exists) {
        setState(() {
          _errorMessage = 'Task not found';
          _isLoading = false;
        });
        return;
      }

      final raw = doc.data() as Map<String, dynamic>;
      debugPrint('ScreenSix raw data: $raw');

      Map<String, dynamic> taskData;
      if (raw.containsKey('data') && raw['data'] is Map<String, dynamic>) {
        taskData = raw['data'] as Map<String, dynamic>;
      } else {
        taskData = raw;
      }

      debugPrint('ScreenSix taskData: $taskData');

      _mode = taskData['mode'] as String? ?? 'text';

      List<Map<String, dynamic>> rawPairs = [];

      if (taskData.containsKey('pairs') && taskData['pairs'] is List) {
        rawPairs = List<Map<String, dynamic>>.from(taskData['pairs']);
      } else {
        final keys = taskData.keys.where((k) => k.startsWith('pair_') || k.startsWith('pair'));
        if (keys.isNotEmpty) {
          for (final key in keys) {
            final pair = taskData[key];
            if (pair is Map<String, dynamic>) {
              rawPairs.add(pair);
            }
          }
        }
      }

      debugPrint('ScreenSix rawPairs count: ${rawPairs.length}');

      if (rawPairs.isEmpty) {
        setState(() {
          _errorMessage = 'No pairs found in this task';
          _isLoading = false;
        });
        return;
      }

      final pairs = rawPairs.asMap().entries.map((e) {
        final data = e.value;
        return _MatchPair(
          id: e.key,
          english: data['english'] as String? ?? data['en'] as String? ?? '',
          translated: data['translated'] as String? ?? data['es'] as String? ?? '',
          image: data['image'] as String? ?? '',
        );
      }).toList();

      final validPairs = pairs.where((p) => p.english.isNotEmpty).toList();

      if (validPairs.isEmpty) {
        setState(() {
          _errorMessage = 'No valid pairs found';
          _isLoading = false;
        });
        return;
      }

      final leftCol = List<_MatchPair>.from(validPairs)..shuffle();
      final rightCol = List<_MatchPair>.from(validPairs)..shuffle();

      setState(() {
        _pairs = validPairs;
        _leftCol = leftCol;
        _rightCol = rightCol;
        _isLoading = false;
        _errorMessage = null;
      });

      TaskTtsService.prefetch(validPairs.map((p) => p.english).toList());

      debugPrint('ScreenSix loaded ${validPairs.length} pairs');
    } catch (e, stackTrace) {
      debugPrint('ScreenSix ERROR: $e');
      debugPrint('StackTrace: $stackTrace');
      setState(() {
        _errorMessage = 'Error loading task: $e';
        _isLoading = false;
      });
    }
  }

  void _onTapLeft(int pairId) {
    if (_matchedIds.contains(pairId) || _wrongLeftId != null) return;
    setState(() => _selectedLeftId = pairId);
    
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
      // Whether THIS match is the one that completes the whole exercise --
      // checked BEFORE _matchedIds.add() below, since after adding it
      // _matchedIds.length would already equal _pairs.length even for the
      // check itself; computing it here against the pre-add state is
      // clearer than reordering the add.
      final willCompleteExercise = _matchedIds.length + 1 == _pairs.length;

      if (willCompleteExercise) {
        // CHANGED: the match that finishes the whole exercise gets a
        // stronger confirmation -- medium-tap + heavy haptic -- instead of
        // the regular light-tap/light haptic every other correct match
        // gets, so it reads as "that was the last one" rather than just
        // another pair.
        HapticFeedback.heavyImpact();
        FeedbackSoundService.instance.playAsset('assets/sound/medium-tap.mp3');
      } else {
        HapticFeedback.lightImpact();
        FeedbackSoundService.instance.playAsset('assets/sound/light-tap.mp3');
      }

      final pair = _pairs.firstWhere(
        (p) => p.id == leftId,
        orElse: () => const _MatchPair(id: -1, english: ''),
      );
      if (pair.english.isNotEmpty) TaskTtsService.speak(pair.english, voice: TtsVoiceDefaults.defaultEnglish);

      setState(() {
        _matchedIds.add(leftId);
        _selectedLeftId = null;
        _selectedRightId = null;
      });
      if (_matchedIds.length == _pairs.length) {
        Future.delayed(const Duration(milliseconds: 600), () {
          // FIXED: this was dropped in the previous edit -- the real
          // success sound/haptic needs to fire once here, right before
          // showing the result sheet, so completing the exercise still
          // gets its actual success chime (not just the medium-tap from
          // the final match above, which is a distinct "last pair" cue,
          // not the overall completion sound).
          TaskFeedback.fire(true);
          TaskResultSheet.show(
            context,
            isCorrect: true,
            onContinue: () {
              // Teacher review detail: every pair the task contained,
              // all matched correctly by construction (see class doc
              // comment on why 'match' has no per-pair right/wrong to
              // report — completion only happens once everything is
              // matched).
              final pairsDetail = _pairs
                  .map((p) => {
                        'english': p.english,
                        'translated': p.translated,
                        'image': p.image,
                      })
                  .toList();
              widget.onTaskComplete(true, {
                'type': 'match',
                'mode': _mode,
                'pairs': pairsDetail,
              });
            },
          );
        });
      }
    } else {
      TaskFeedback.fire(false);
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

  Widget _buildLeftTile(_MatchPair pair) {
    final isMatched = _matchedIds.contains(pair.id);
    final c = _tileColors(pair.id, true);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: GestureDetector(
        onTap: isMatched ? null : () => _onTapLeft(pair.id),
        child: Container(
          constraints: const BoxConstraints(minHeight: _rightTileHeight),
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
          ]),
        ),
      ),
    );
  }

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

  static const double _rightTileHeight = 100;

  Widget _buildTextTile(_MatchPair pair, bool isMatched) {
    return Container(
      height: _rightTileHeight,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
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
          ],
        ),
      ),
    );
  }

  Widget _buildImageTile(_MatchPair pair, bool isMatched) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        children: [
          SizedBox(
            height: _rightTileHeight, // ya coincide, mismo valor
            width: double.infinity,
            child: pair.image.isNotEmpty
                ? Image.network(
                    pair.image,
                    fit: BoxFit.contain,
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
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF4CAF50)),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                ),
                child: const Text('Go Back', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    if (_pairs.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 64, color: Colors.orange),
              const SizedBox(height: 16),
              const Text(
                'No pairs found',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'This task has no matching pairs configured',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                ),
                child: const Text('Go Back', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    final progressValue = (widget.currentTaskNumber + 1) / widget.totalTasks;
    final matchedCount = _matchedIds.length;
    final totalPairs = _pairs.length;
    final isImageMode = _mode == 'image';

    return TaskExitGuard(
      onRequestExit: _handleClose,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFE8F5E9), Colors.white],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: ResponsiveActivityShell(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Row(children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.black87, size: 28),
                        onPressed: _handleClose,
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
        ),
      ),
    );
  }
}