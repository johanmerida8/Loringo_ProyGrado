import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/theme/app_theme.dart';

/// Result screen for Lesson Quizzes (formative) and Unit Quizzes
/// (summative). Same look as ActivityCompleteScreen, which stays the
/// activities-only result screen; the quiz-specific rules live here:
///  - Lesson Quiz: always "Quiz Complete!", no pass/fail wording, no retake.
///  - Unit Quiz passed: "Quiz Passed! 🎉".
///  - Unit Quiz not passed: "Quiz Complete!" (never "Failed"), shown with
///    the sad star, an orange gradient and unit-failed.mp3, plus an
///    optional "Try Again" while attempts remain. "Continue" is always
///    the last action.
class QuizCompleteScreen extends StatefulWidget {
  final String quizTitle;
  final bool isLessonQuiz;
  final bool passed;
  final int scorePercent;
  final int correctAnswers;
  final int wrongAnswers;
  final int xpEarned;
  final int attemptsRemaining;

  /// Starts a new attempt. Receives THIS screen's context — the
  /// QuizPlayScreen that built this callback is already unmounted by the
  /// time it's tapped (see QuizPlayScreen._onRetakeQuiz).
  final void Function(BuildContext context)? onRetake;

  const QuizCompleteScreen({
    super.key,
    required this.quizTitle,
    required this.isLessonQuiz,
    required this.passed,
    required this.scorePercent,
    required this.correctAnswers,
    required this.wrongAnswers,
    required this.xpEarned,
    this.attemptsRemaining = 0,
    this.onRetake,
  });

  @override
  State<QuizCompleteScreen> createState() => _QuizCompleteScreenState();
}

class _QuizCompleteScreenState extends State<QuizCompleteScreen>
    with TickerProviderStateMixin {
  static const _green = Color(0xFF2D6A2F);
  static const _orange = Color(0xFFBF360C);

  /// A Unit Quiz that wasn't passed: sad star, orange screen and the
  /// unit-failed sound instead of the celebration. Lesson Quizzes are
  /// ungraded, so they always get the celebratory version.
  bool get _notPassed => !widget.isLessonQuiz && !widget.passed;

  /// Accent for title, hint, XP and buttons — dark green normally, dark
  /// orange on a not-passed Unit Quiz so it matches the orange background.
  Color get _accent => _notPassed ? _orange : _green;

  late final AnimationController _xpController;
  late final Animation<int> _xpAnimation;
  late final AnimationController _entrance;
  final AudioPlayer _player = AudioPlayer();

  int get _stars {
    if (widget.scorePercent >= 90) return 3;
    if (widget.scorePercent >= 60) return 2;
    return 1;
  }

  bool get _showPassed => !widget.isLessonQuiz && widget.passed;

  bool get _canRetake =>
      !widget.isLessonQuiz &&
      !widget.passed &&
      widget.onRetake != null &&
      widget.attemptsRemaining > 0;

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
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();

    _playResultSound();
    HapticFeedback.lightImpact();
    Future.delayed(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      if (widget.isLessonQuiz || widget.passed) HapticFeedback.mediumImpact();
      _xpController.forward();
    });
  }

  Future<void> _playResultSound() async {
    try {
      await _player.setAsset(_notPassed
          ? 'assets/sound/unit-failed.mp3'
          : 'assets/sound/celebration.mp3');
      _player.play();
    } catch (_) {}
  }

  @override
  void dispose() {
    _xpController.dispose();
    _entrance.dispose();
    _player.dispose();
    super.dispose();
  }

  /// Staggered fade + slide-up for one block of the screen; [start]/[end]
  /// are fractions of the entrance animation.
  Widget _reveal(double start, double end, Widget child) {
    final curve = CurvedAnimation(
      parent: _entrance,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.15), end: Offset.zero)
            .animate(curve),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    final title = _showPassed
        ? 'initials.quiz_complete_screen.quizPassed'.tr()
        // Not passed: "Almost there!" when a retry is offered right
        // below, "Nice effort!" when no attempts are left (Continue only).
        : _notPassed
            ? (_canRetake
                ? 'initials.quiz_complete_screen.almostThere'.tr()
                : 'initials.quiz_complete_screen.niceEffort'.tr())
            : 'initials.quiz_complete_screen.quizComplete'.tr();

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _notPassed
                ? const [Color(0xFFFFE0B2), Color(0xFFFFB74D), Color(0xFFFB8C00)]
                : const [Color(0xFFF6E96B), Color(0xFFBEDC74), Color(0xFFA2CA71)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 16),
              SizedBox(
                height: 200,
                child: Lottie.asset(
                  _notPassed
                      ? 'assets/animation/sad_star.json'
                      : 'assets/animation/happy_star.json',
                  repeat: false,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 12),

              _reveal(
                0.0,
                0.45,
                Column(children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: _accent,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      widget.quizTitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 15,
                          color: _notPassed
                              ? const Color(0xFFE65100)
                              : const Color(0xFF558B2F)),
                    ),
                  ),
                ]),
              ),

              // Not passed: either "you can try again — N left" (with the
              // Try Again button below) or, with no attempts left, a
              // reassurance that the teacher will help — only Continue
              // is offered then.
              if (_notPassed) ...[
                const SizedBox(height: 16),
                _reveal(
                  0.15,
                  0.55,
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 32),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                            _canRetake
                                ? Icons.lightbulb_outline_rounded
                                : Icons.favorite_outline_rounded,
                            size: 16,
                            color: _accent),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _canRetake
                                ? 'initials.quiz_complete_screen.tryAgainHint'
                                    .plural(widget.attemptsRemaining)
                                : 'initials.quiz_complete_screen.teacherWillHelp'
                                    .tr(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 20),

              _reveal(
                0.2,
                0.6,
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(3, (i) {
                    final filled = i < _stars;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        filled
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color:
                            filled ? const Color(0xFFFFD600) : Colors.white38,
                        size: 44,
                      ),
                    );
                  }),
                ),
              ),

              const SizedBox(height: 28),

              if (widget.xpEarned > 0)
                _reveal(
                  0.35,
                  0.75,
                  AnimatedBuilder(
                    animation: _xpAnimation,
                    builder: (_, __) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 36, vertical: 18),
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
                            style: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                              color: _accent,
                              letterSpacing: 1,
                            ),
                          ),
                          Text(
                            'common.experienceEarned'.tr(),
                            style: const TextStyle(
                                fontSize: 13, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 28),

              _reveal(
                0.5,
                0.9,
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
              ),

              const Spacer(),

              _reveal(
                0.6,
                1.0,
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                  child: Column(
                    children: [
                      if (_canRetake) ...[
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => widget.onRetake!(context),
                            icon: const Icon(Icons.refresh_rounded, size: 20),
                            label: Text(
                              'initials.quiz_complete_screen.tryAgain'.tr(),
                              style: const TextStyle(fontSize: 16),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _accent,
                              backgroundColor: Colors.white.withOpacity(0.5),
                              side: BorderSide(color: _accent, width: 1.5),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      // Continue is always the final action.
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            'common.continue'.tr(),
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

/// Shown over QuizPlayScreen from "Submit" until QuizCompleteScreen fades in —
/// a short, friendly beat so finishing the quiz doesn't jump straight to
/// the result.
class QuizCheckingOverlay extends StatelessWidget {
  const QuizCheckingOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        builder: (_, t, child) => ColoredBox(
          color: Colors.black.withOpacity(0.35 * t),
          child: Opacity(
            opacity: t,
            child: Transform.scale(scale: 0.9 + 0.1 * t, child: child),
          ),
        ),
        child: Center(
          child: Container(
            width: 260,
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 120,
                  child: Lottie.asset(
                    'assets/JSON/loading.json',
                    repeat: false,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'initials.quiz_complete_screen.checkingAnswers'.tr(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2D6A2F),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
