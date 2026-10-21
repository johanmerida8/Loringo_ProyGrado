import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';

/// Result screen for normal activities. Quizzes have their own
/// (QuizCompleteScreen), so there is no pass/fail or retake logic here.
class ActivityCompleteScreen extends StatefulWidget {
  final String activityTitle;
  final int scorePercent;
  final int correctAnswers;
  final int wrongAnswers;
  final int xpEarned;
  final bool isFirstCompletion;

  const ActivityCompleteScreen({
    super.key,
    required this.activityTitle,
    required this.scorePercent,
    required this.correctAnswers,
    required this.wrongAnswers,
    required this.xpEarned,
    this.isFirstCompletion = true,
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
      await _player.setAsset('assets/sound/celebration.mp3');
      _player.play();
    } catch (_) {}
  }

  @override
  void dispose() {
    _xpController.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    const titleColor = Color(0xFF2D6A2F);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF6E96B), Color(0xFFBEDC74), Color(0xFFA2CA71)],
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
                  'assets/animation/happy_star.json',
                  repeat: false,
                  fit: BoxFit.contain,
                ),
              ),

              const SizedBox(height: 12),

              // Title
              Text(
                'common.activityComplete'.tr(),
                style: const TextStyle(
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

              const SizedBox(height: 40),

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

              // Continue button
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: titleColor,
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
