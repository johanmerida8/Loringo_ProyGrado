import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';

class ActivityCompleteScreen extends StatefulWidget {
  final String activityTitle;
  final int scorePercent;
  final int correctAnswers;
  final int wrongAnswers;
  final int xpEarned;
  final bool isFirstCompletion;
  final String? screenTitle;

  // Quiz-specific (only for graded quizzes)
  //
  // BUGFIX: this used to be a plain VoidCallback. QuizPlayScreen's
  // _onRetakeQuiz needs a BuildContext to navigate with, and it used to
  // read its OWN (already-unmounted) context — see the doc comment on
  // _onRetakeQuiz in quiz_play_screen.dart for the full crash trace.
  // Widening this to take a BuildContext lets _onRetake (below) hand it
  // THIS screen's context instead, which is guaranteed to still be
  // mounted at the moment the button is tapped.
  final void Function(BuildContext context)? onRetake;
  final int attemptsRemaining;
  final int maxAttempts;
  final bool isGraded;

  const ActivityCompleteScreen({
    super.key,
    required this.activityTitle,
    required this.scorePercent,
    required this.correctAnswers,
    required this.wrongAnswers,
    required this.xpEarned,
    this.isFirstCompletion = true,
    this.screenTitle,
    this.onRetake,
    this.attemptsRemaining = 0,
    this.maxAttempts = 3,
    this.isGraded = true,
  });

  @override
  State<ActivityCompleteScreen> createState() => _ActivityCompleteScreenState();
}

class _ActivityCompleteScreenState extends State<ActivityCompleteScreen>
    with TickerProviderStateMixin {
  late final AnimationController _xpController;
  late final Animation<int> _xpAnimation;
  final AudioPlayer _player = AudioPlayer();

  int get _stars {
    if (widget.scorePercent >= 90) return 3;
    if (widget.scorePercent >= 60) return 2;
    return 1;
  }

  bool get _isPassed => widget.scorePercent >= 60;
  
  bool get _canRetake => widget.isGraded 
      && widget.onRetake != null 
      && widget.attemptsRemaining > 0 
      && !_isPassed;

  String get _buttonText {
    if (!widget.isGraded) return 'common.continue'.tr();
    if (_isPassed) return 'common.continue'.tr();
    return widget.attemptsRemaining == 0
        ? 'common.backToMenu'.tr()
        : 'common.continue'.tr();
  }

  @override
  void initState() {
    super.initState();
    _xpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _xpAnimation = IntTween(begin: 0, end: widget.xpEarned).animate(
      CurvedAnimation(parent: _xpController, curve: Curves.easeOut),
    );
    _playCelebration();
    HapticFeedback.lightImpact();
    Future.delayed(const Duration(milliseconds: 150), () {
      HapticFeedback.mediumImpact();
    });
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        HapticFeedback.heavyImpact();
        _xpController.forward();
      }
    });
  }

  Future<void> _playCelebration() async {
    try {
      // showCelebration mirrors the same condition used in build() for
      // picking the gradient/animation/colors (!widget.isGraded ||
      // _isPassed) — an ungraded activity always gets the celebratory
      // sound, a graded quiz only gets it if the student actually
      // passed. A failed graded attempt plays unit-failed.mp3 instead,
      // so the audio cue matches the sad star / orange palette already
      // shown for that case rather than contradicting it with a
      // celebration sound.
      final showCelebration = !widget.isGraded || _isPassed;
      final asset = showCelebration
          ? 'assets/sound/celebration.mp3'
          : 'assets/sound/unit-failed.mp3';
      await _player.setAsset(asset);
      _player.play();
    } catch (_) {}
  }

  @override
  void dispose() {
    _xpController.dispose();
    _player.dispose();
    super.dispose();
  }

  // BUGFIX: this used to call Navigator.pop(context) BEFORE
  // widget.onRetake!(). At the point this screen exists, the nav stack
  // is [..., student_activities_screen, ActivityCompleteScreen] —
  // ActivityCompleteScreen is what QuizPlayScreen.pushReplacement'd
  // itself into on submit, so ActivityCompleteScreen is the top of the
  // stack, not something layered on top of a still-present
  // QuizPlayScreen. Popping here therefore revealed
  // student_activities_screen underneath — visibly, since Navigator
  // transitions aren't instant — before onRetake's own
  // Navigator.pushReplacement (in QuizPlayScreen._onRetakeQuiz) pushed
  // the fresh quiz attempt on top of THAT. The net result was correct
  // once both animations settled, but the student saw a flash of the
  // home/activities screen in between, which read as "it kicked me
  // back to the menu" even though a moment later it recovered into a
  // new attempt.
  //
  // Fix (part 1): don't pop at all. onRetake (QuizPlayScreen's
  // _onRetakeQuiz) uses pushReplacement internally, which already
  // correctly swaps out ActivityCompleteScreen (the current top of the
  // stack) for a fresh QuizPlayScreen — no manual pop needed.
  //
  // Fix (part 2): pass THIS screen's own `context` to onRetake rather
  // than calling it with no arguments. QuizPlayScreen._onRetakeQuiz
  // needs a BuildContext to call Navigator.of(...).pushReplacement on,
  // and the QuizPlayScreen instance that owns this callback is already
  // dead by the time the student taps "Try Again" — its own context
  // throws "widget has been unmounted" the instant it's read (see that
  // method's doc comment for the full trace). This screen
  // (ActivityCompleteScreen) is the one actually mounted and on-screen
  // right now, so its context is always safe to navigate from.
  void _onRetake() {
    if (widget.onRetake != null) {
      widget.onRetake!(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    final screenTitle = widget.screenTitle ?? 'common.activityComplete'.tr();
    final showCelebration = !widget.isGraded || _isPassed;
    final gradientColors = showCelebration
        ? [const Color(0xFFF6E96B), const Color(0xFFBEDC74), const Color(0xFFA2CA71)]
        : [const Color(0xFFFFE0B2), const Color(0xFFFFCC80), const Color(0xFFFFB74D)];
    
    final titleColor = showCelebration ? const Color(0xFF2D6A2F) : const Color(0xFFE65100);
    final buttonColor = showCelebration ? const Color(0xFF2D6A2F) : const Color(0xFFE65100);
    
    String animationAsset;
    if (!widget.isGraded || _isPassed) {
      animationAsset = 'assets/animation/happy_star.json';
    } else {
      animationAsset = 'assets/animation/sad_star.json';
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 16),
              
              // Lottie animation
              SizedBox(
                height: 200,
                child: Lottie.asset(
                  animationAsset,
                  repeat: false,
                  fit: BoxFit.contain,
                ),
              ),

              const SizedBox(height: 12),

              // Title
              Text(
                screenTitle,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: titleColor,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.activityTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF558B2F),
                ),
              ),

              const SizedBox(height: 24),

              // Message for failed graded quiz with attempts left
              if (widget.isGraded && !_isPassed && widget.attemptsRemaining > 0)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.info_outline, size: 16, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text(
                        'initials.activity_complete_screen.attemptsLeftBanner'
                            .plural(widget.attemptsRemaining),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 16),

              // Stars row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) {
                  final filled = i < _stars;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      filled ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: filled ? const Color(0xFFFFD600) : Colors.white38,
                      size: 44,
                    ),
                  );
                }),
              ),

              const SizedBox(height: 28),

              // XP earned badge
              if (widget.xpEarned > 0)
                AnimatedBuilder(
                  animation: _xpAnimation,
                  builder: (_, __) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.18),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Text(
                          '+${_xpAnimation.value} XP',
                          style: const TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2D6A2F),
                            letterSpacing: 1,
                          ),
                        ),
                        Text(
                          'common.experienceEarned'.tr(),
                          style: const TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 28),

              // Stats row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Row(
                  children: [
                    _statCard(
                      label: 'common.score'.tr(),
                      value: '${widget.scorePercent}%',
                      color: const Color(0xFF43A047),
                      icon: Icons.bar_chart_rounded,
                    ),
                    const SizedBox(width: 12),
                    _statCard(
                      label: 'common.correct'.tr(),
                      value: '${widget.correctAnswers}',
                      color: const Color(0xFF1E88E5),
                      icon: Icons.check_circle_outline_rounded,
                    ),
                    const SizedBox(width: 12),
                    _statCard(
                      label: 'common.wrong'.tr(),
                      value: '${widget.wrongAnswers}',
                      color: const Color(0xFFE53935),
                      icon: Icons.cancel_outlined,
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                child: Column(
                  children: [
                    // Try Again button (failed + attempts left)
                    if (_canRetake)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _onRetake,
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          label: Text(
                            'initials.activity_complete_screen.tryAgainWithAttempts'
                                .plural(widget.attemptsRemaining),
                            style: const TextStyle(fontSize: 16),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE65100),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    
                    // Continue/Back to Menu button
                    if (!_canRetake)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: buttonColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            _buttonText,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statCard({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}