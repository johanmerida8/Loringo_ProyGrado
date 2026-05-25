import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class MyLoading extends StatelessWidget {
  final double size;

  const MyLoading({
    super.key,
    this.size = 200,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Lottie.asset(
        'assets/JSON/happy-loader.json',
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
  }
}