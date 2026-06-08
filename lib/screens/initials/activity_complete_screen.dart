import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lottie/lottie.dart';

class ActivityCompleteScreen extends StatefulWidget {
  final String activityTitle;
  final int scorePercent;
  final int correctAnswers;
  final int wrongAnswers;
  final int xpEarned;
  final bool isFirstCompletion;
  final String screenTitle;
  
  // Quiz-specific (only for graded quizzes)
  final VoidCallback? onRetake;
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
    this.screenTitle = 'Activity Complete!', 
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
    if (!widget.isGraded) return 'Continue';
    if (_isPassed) return 'Continue';
    return widget.attemptsRemaining == 0 ? 'Back to Menu' : 'Continue';
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

  void _onRetake() {
    Navigator.pop(context);
    if (widget.onRetake != null) {
      widget.onRetake!();
    }
  }

  @override
  Widget build(BuildContext context) {
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
                widget.screenTitle,
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
                        'You have ${widget.attemptsRemaining} attempt${widget.attemptsRemaining != 1 ? 's' : ''} left',
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
                        const Text(
                          'Experience Earned',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
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
                      label: 'Score',
                      value: '${widget.scorePercent}%',
                      color: const Color(0xFF43A047),
                      icon: Icons.bar_chart_rounded,
                    ),
                    const SizedBox(width: 12),
                    _statCard(
                      label: 'Correct',
                      value: '${widget.correctAnswers}',
                      color: const Color(0xFF1E88E5),
                      icon: Icons.check_circle_outline_rounded,
                    ),
                    const SizedBox(width: 12),
                    _statCard(
                      label: 'Wrong',
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
                            'Try Again (${widget.attemptsRemaining} attempt${widget.attemptsRemaining != 1 ? 's' : ''} left)',
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