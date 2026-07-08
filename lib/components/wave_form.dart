import 'package:flutter/material.dart';

/// A reusable wave divider that creates a smooth curve between sections
class WaveDivider extends StatelessWidget {
  final Color color;
  final double height;
  final double waveIntensity; // Controls wave amplitude
  final bool inverted; // Flips the wave direction

  const WaveDivider({
    super.key,
    required this.color,
    this.height = 54,
    this.waveIntensity = 1.0,
    this.inverted = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _WavePainter(
          color: color,
          waveIntensity: waveIntensity,
          inverted: inverted,
        ),
        size: Size(double.infinity, height),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final Color color;
  final double waveIntensity;
  final bool inverted;

  const _WavePainter({
    required this.color,
    required this.waveIntensity,
    required this.inverted,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    
    final startY = inverted ? size.height * 0.8 : size.height * 0.55;
    path.moveTo(0, startY);

    // Adjust control points based on wave intensity
    final intensity = waveIntensity.clamp(0.5, 1.5);
    
    if (!inverted) {
      // Standard wave (downward curve)
      path.cubicTo(
        size.width * 0.20, size.height * (-0.1 * intensity),
        size.width * 0.45, size.height * (0.9 * intensity),
        size.width * 0.65, size.height * (0.25 * intensity),
      );
      path.cubicTo(
        size.width * 0.80, size.height * (-0.05 * intensity),
        size.width * 0.90, size.height * (0.5 * intensity),
        size.width, size.height * (0.3 * intensity),
      );
    } else {
      // Inverted wave (upward curve)
      path.cubicTo(
        size.width * 0.20, size.height * 1.1,
        size.width * 0.45, size.height * 0.2,
        size.width * 0.65, size.height * 0.9,
      );
      path.cubicTo(
        size.width * 0.80, size.height * 1.05,
        size.width * 0.90, size.height * 0.6,
        size.width, size.height * 0.8,
      );
    }

    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) {
    return old.color != color ||
        old.waveIntensity != waveIntensity ||
        old.inverted != inverted;
  }
}