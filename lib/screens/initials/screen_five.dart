import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lottie/lottie.dart';

class ScreenFive extends StatefulWidget {
  final String contentId;
  final String unitId;
  final String lessonId;
  final String activityId;
  final String taskId;
  final Function(bool isCorrect)? onTaskComplete;
  final int currentTaskNumber;
  final int totalTasks;
  final String collectionName;

  const ScreenFive({
    super.key,
    required this.contentId,
    required this.unitId,
    required this.lessonId,
    required this.activityId,
    required this.taskId,
    this.onTaskComplete,
    this.currentTaskNumber = 1,
    this.totalTasks = 1,
    this.collectionName = 'content',
  });

  @override
  State<ScreenFive> createState() => _ScreenFiveState();
}

class _ScreenFiveState extends State<ScreenFive> {
  final FlutterTts flutterTts = FlutterTts();
  final player = AudioPlayer();

  String imageUrl = '';
  String question = '';
  List<Map<String, dynamic>> textOptions = [];
  String selectedOption = '';

  static const Color greenPrimary = Color(0xFF4CAF50);
  static const Color greyAccent = Color(0xFF81C784);

  @override
  void initState() {
    super.initState();
    _fetchTask();
  }

  Future<void> _fetchTask() async {
    try {
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

      if (doc.exists) {
        final taskData = doc.data();
        if (taskData != null && taskData['type'] == 'image_select_reverse') {
          final data = taskData['data'] as Map<String, dynamic>? ?? {};
          
          setState(() {
            imageUrl = data['image'] ?? '';
            question = taskData['question']?.isNotEmpty == true ? taskData['question'] : 'Select the correct phrase';
            textOptions = List<Map<String, dynamic>>.from(data['options'] ?? []);
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching task: $e');
    }
  }

  void _speak(String text) async {
    await flutterTts.setLanguage('en-GB');
    await flutterTts.speak(text);
  }

  void _handleSelection(String text) {
    setState(() {
      selectedOption = text;
    });
  }

  void _checkAnswer() {
    final option = textOptions.firstWhere(
      (option) => option['text'] == selectedOption,
      orElse: () => {},
    );
    final bool isCorrect = option['isCorrect'] == true;
    _playFeedback(isCorrect);
  }

  void _playFeedback(bool isCorrect) async {
    if (isCorrect) HapticFeedback.mediumImpact(); else HapticFeedback.heavyImpact();
    player.setAsset(isCorrect ? 'assets/sound/success-2.mp3' : 'assets/sound/fail-2.mp3').then((_) => player.play());
    _showResultBottomSheet(isCorrect);
  }

  void _showResultBottomSheet(bool isCorrect) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.4,
        maxChildSize: 0.6,
        builder: (_, controller) => Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, -5))],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Lottie.asset(isCorrect ? 'assets/animation/correct.json' : 'assets/animation/fail.json', height: 120),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onTaskComplete!(isCorrect);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isCorrect ? greenPrimary : Colors.orange,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 5,
                  ),
                  child: Text(isCorrect ? 'Continue' : 'Try Again', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const backgroundGradient = LinearGradient(
      colors: [Color(0xFFE8F5E9), Colors.white],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: backgroundGradient),
        child: SafeArea(
          child: imageUrl.isEmpty || textOptions.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: Row(
                        children: [
                          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.black87, size: 28)),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: const BorderRadius.all(Radius.circular(30)),
                              child: LinearProgressIndicator(
                                value: widget.currentTaskNumber / widget.totalTasks,
                                backgroundColor: Colors.blueGrey,
                                valueColor: const AlwaysStoppedAnimation<Color>(greenPrimary),
                                minHeight: 8,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          IconButton(icon: const Icon(Icons.volume_up, color: Colors.black87, size: 28), onPressed: () => _speak(question)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(question, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87))),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            const SizedBox(height: 20),
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 40),
                              height: 250,
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15, offset: const Offset(0, 5))]),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: imageUrl.endsWith('.svg') && !imageUrl.contains('f_png')
                                    ? SvgPicture.network(imageUrl, fit: BoxFit.contain, placeholderBuilder: (context) => const Center(child: CircularProgressIndicator()))
                                    : CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.contain, placeholder: (_, __) => const Center(child: CircularProgressIndicator()), errorWidget: (_, __, ___) => const Icon(Icons.error, size: 50)),
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Text('Select the correct phrase', style: TextStyle(fontSize: 18, color: Colors.black54)),
                            const SizedBox(height: 16),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: Column(
                                children: List.generate(textOptions.length, (index) {
                                  final option = textOptions[index];
                                  final isSelected = selectedOption == option['text'];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: GestureDetector(
                                      onTap: () => _handleSelection(option['text']),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 300),
                                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                                        decoration: BoxDecoration(
                                          color: isSelected ? greenPrimary : Colors.white,
                                          borderRadius: BorderRadius.circular(15),
                                          border: Border.all(color: isSelected ? greenPrimary : greyAccent, width: 3),
                                          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: const Offset(0, 3))],
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 30, height: 30,
                                              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: isSelected ? Colors.white : greyAccent, width: 2), color: isSelected ? Colors.white : Colors.transparent),
                                              child: isSelected ? const Icon(Icons.check, size: 18, color: greenPrimary) : null,
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(child: Text(option['text'], style: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontSize: 18, fontWeight: FontWeight.w600))),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: selectedOption.isEmpty ? null : _checkAnswer,
                          style: ElevatedButton.styleFrom(backgroundColor: greenPrimary, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 5),
                          child: const Text('Check', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}