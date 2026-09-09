// lib/screens/initials/widget/practice_round_intro_screen.dart
//
// Full-screen intro shown exactly once, right when ActivityPlayScreen
// switches into the end-of-activity review round — before the first
// repeated task is displayed. The parrot mascot explains that this is
// just a repeat of what the student already did, so they can do a little
// better, framing it as encouragement rather than punishment for getting
// something wrong. Distinct from TaskResultSheet, which handles the
// correct/incorrect feedback for each individual answer and carries no
// mascot content of its own.

import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';

class PracticeRoundIntroScreen extends StatelessWidget {
  final VoidCallback onContinue;
  final int taskCount;

  const PracticeRoundIntroScreen({
    super.key,
    required this.onContinue,
    required this.taskCount,
  });

  static const Color _green = Color(0xFF4CAF50);

  static const List<String> _parrotAssets = [
    'assets/images/parrot-2.png',
    'assets/images/parrot-motivation-2.png',
  ];

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    final parrotAsset = _parrotAssets[Random().nextInt(_parrotAssets.length)];

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Image.asset(
                parrotAsset,
                height: 220,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 32),
              Text(
                'initials.practice_round_intro_screen.title'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'initials.practice_round_intro_screen.body'.plural(taskCount),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 3,
                  ),
                  child: Text(
                    'initials.practice_round_intro_screen.letsGo'.tr(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}